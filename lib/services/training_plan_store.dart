import 'dart:convert';
import 'dart:io';

import '../models/training_plan.dart';

class TrainingPlanSnapshot {
  final TrainingPlan? plan;
  final List<CoachMessage> messages;

  const TrainingPlanSnapshot({
    this.plan,
    this.messages = const [],
  });
}

class TrainingPlanStore {
  static const int schemaVersion = 1;
  static final Map<String, Future<void>> _pathLocks = {};
  static int _tempCounter = 0;

  final String? customFilePath;

  const TrainingPlanStore({this.customFilePath});

  static String _lockKey(File file) =>
      file.absolute.uri.normalizePath().toFilePath();

  static Future<T> _withPathLock<T>(
    String key,
    Future<T> Function() action,
  ) {
    final previous = _pathLocks[key] ?? Future<void>.value();
    final next = previous.catchError((_) {}).then((_) => action());
    final gate = next.then((_) {}, onError: (_) {});
    _pathLocks[key] = gate;
    gate.whenComplete(() {
      if (identical(_pathLocks[key], gate)) {
        _pathLocks.remove(key);
      }
    });
    return next;
  }

  File _getPlanFile() {
    if (customFilePath != null && customFilePath!.isNotEmpty) {
      return File(customFilePath!);
    }
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      return File(
        '$home/Library/Application Support/pulse_training_hub/training_plan.json',
      );
    }
    return File(
      '${Directory.systemTemp.path}/pulse_training_hub_training_plan.json',
    );
  }

  /// Atomically writes [plan] and [messages] to disk via a unique `.tmp` file
  /// + rename and restricts permissions to owner-only (`0600`) on macOS/Linux.
  Future<void> save(
    TrainingPlan? plan, [
    List<CoachMessage> messages = const [],
  ]) {
    final file = _getPlanFile();
    return _withPathLock(_lockKey(file), () async {
      await file.parent.create(recursive: true);

      final payload = <String, dynamic>{
        'schemaVersion': schemaVersion,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'plan': plan?.toJson(),
        'messages': messages.map((m) => m.toJson()).toList(),
      };
      final encoded = jsonEncode(payload);
      final tmpFile = File('${file.path}.$pid.${_tempCounter++}.tmp');
      var renamed = false;

      try {
        await tmpFile.writeAsString(encoded, flush: true);

        if (!Platform.isWindows) {
          try {
            await Process.run('chmod', ['600', tmpFile.path]);
          } catch (_) {}
        }

        await tmpFile.rename(file.path);
        renamed = true;

        if (!Platform.isWindows) {
          try {
            await Process.run('chmod', ['600', file.path]);
          } catch (_) {}
        }
      } finally {
        if (!renamed) {
          try {
            if (await tmpFile.exists()) {
              await tmpFile.delete();
            }
          } catch (_) {}
        }
      }
    });
  }

  /// Reads and deserializes the persisted plan snapshot from disk.
  /// Returns `null` if the file is missing, empty, corrupt, or has an
  /// unexpected schema shape (never throws).
  Future<TrainingPlanSnapshot?> load() {
    final file = _getPlanFile();
    return _withPathLock(_lockKey(file), () async {
      try {
        if (!await file.exists()) return null;

        final raw = await file.readAsString();
        if (raw.trim().isEmpty) return null;

        final decoded = jsonDecode(raw);
        if (decoded is! Map<String, dynamic>) return null;

        final hasExpectedKey = decoded.containsKey('schemaVersion') ||
            decoded.containsKey('plan') ||
            decoded.containsKey('messages');
        if (!hasExpectedKey) return null;

        final rawPlan = decoded['plan'];
        if (rawPlan != null && rawPlan is! Map) return null;

        final rawMessages = decoded['messages'];
        if (rawMessages != null && rawMessages is! List) return null;

        final TrainingPlan? plan = rawPlan is Map
            ? TrainingPlan.fromJson(Map<String, dynamic>.from(rawPlan))
            : null;

        final messages = <CoachMessage>[];
        if (rawMessages is List) {
          for (final item in rawMessages) {
            if (item is Map<String, dynamic>) {
              messages.add(CoachMessage.fromJson(item));
            } else if (item is Map) {
              messages.add(
                CoachMessage.fromJson(Map<String, dynamic>.from(item)),
              );
            } else {
              return null;
            }
          }
        }

        return TrainingPlanSnapshot(
          plan: plan,
          messages: messages,
        );
      } catch (_) {
        return null;
      }
    });
  }

  /// Safely deletes the plan file (and any stale `.tmp` files) if present.
  Future<void> clear() {
    final file = _getPlanFile();
    return _withPathLock(_lockKey(file), () async {
      try {
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
      try {
        final legacyTmp = File('${file.path}.tmp');
        if (await legacyTmp.exists()) {
          await legacyTmp.delete();
        }
      } catch (_) {}
      try {
        final parent = file.parent;
        if (await parent.exists()) {
          final baseName = file.path.split(RegExp(r'[/\\]')).last;
          if (baseName.isNotEmpty) {
            final prefix = '$baseName.';
            await for (final entity in parent.list(followLinks: false)) {
              if (entity is File) {
                final name = entity.path.split(RegExp(r'[/\\]')).last;
                if (name.startsWith(prefix) && name.endsWith('.tmp')) {
                  try {
                    await entity.delete();
                  } catch (_) {}
                }
              }
            }
          }
        }
      } catch (_) {}
    });
  }
}
