import 'dart:convert';
import 'dart:io';

class ChatGptSession {
  final String clientId;
  final String accessToken;
  final String? refreshToken;
  final String? idToken;
  final DateTime expiresAt;
  final String? userName;
  final String? userEmail;
  final String? planTier;

  const ChatGptSession({
    required this.clientId,
    required this.accessToken,
    this.refreshToken,
    this.idToken,
    required this.expiresAt,
    this.userName,
    this.userEmail,
    this.planTier,
  });

  /// Proactive 2-minute buffer before expiry so callers refresh cleanly.
  bool get isExpired => DateTime.now().isAfter(
        expiresAt.subtract(const Duration(minutes: 2)),
      );

  /// Public-client PKCE refresh requires only [clientId] and [refreshToken].
  bool get canRefresh =>
      (refreshToken?.trim().isNotEmpty ?? false) && clientId.trim().isNotEmpty;

  ChatGptSession copyWith({
    String? clientId,
    String? accessToken,
    String? refreshToken,
    bool clearRefreshToken = false,
    String? idToken,
    bool clearIdToken = false,
    DateTime? expiresAt,
    String? userName,
    bool clearUserName = false,
    String? userEmail,
    bool clearUserEmail = false,
    String? planTier,
    bool clearPlanTier = false,
  }) {
    return ChatGptSession(
      clientId: clientId ?? this.clientId,
      accessToken: accessToken ?? this.accessToken,
      refreshToken:
          clearRefreshToken ? null : (refreshToken ?? this.refreshToken),
      idToken: clearIdToken ? null : (idToken ?? this.idToken),
      expiresAt: expiresAt ?? this.expiresAt,
      userName: clearUserName ? null : (userName ?? this.userName),
      userEmail: clearUserEmail ? null : (userEmail ?? this.userEmail),
      planTier: clearPlanTier ? null : (planTier ?? this.planTier),
    );
  }

  Map<String, dynamic> toJson() => {
        'clientId': clientId,
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'idToken': idToken,
        'expiresAt': expiresAt.toUtc().toIso8601String(),
        'userName': userName,
        'userEmail': userEmail,
        'planTier': planTier,
      };

  factory ChatGptSession.fromJson(Map<String, dynamic> json) {
    final rawClientId = json['clientId'];
    if (rawClientId is! String || rawClientId.trim().isEmpty) {
      throw const FormatException('ChatGptSession missing valid clientId.');
    }

    final rawAccessToken = json['accessToken'];
    if (rawAccessToken is! String || rawAccessToken.trim().isEmpty) {
      throw const FormatException('ChatGptSession missing valid accessToken.');
    }

    final rawExpiresAt = json['expiresAt'];
    if (rawExpiresAt is! String || rawExpiresAt.trim().isEmpty) {
      throw const FormatException('ChatGptSession missing valid expiresAt.');
    }
    final expiresAt = DateTime.parse(rawExpiresAt.trim());

    String? optionalNonEmptyString(dynamic value, {bool trimValue = false}) {
      if (value is! String) return null;
      final trimmed = value.trim();
      if (trimmed.isEmpty) return null;
      return trimValue ? trimmed : value;
    }

    return ChatGptSession(
      clientId: rawClientId.trim(),
      accessToken: rawAccessToken,
      refreshToken: optionalNonEmptyString(json['refreshToken']),
      idToken: optionalNonEmptyString(json['idToken']),
      expiresAt: expiresAt,
      userName: optionalNonEmptyString(json['userName'], trimValue: true),
      userEmail: optionalNonEmptyString(json['userEmail'], trimValue: true),
      planTier: optionalNonEmptyString(json['planTier'], trimValue: true),
    );
  }
}

class ChatGptAuthStore {
  static final Map<String, Future<void>> _pathLocks = {};
  static int _tempCounter = 0;

  final String? customFilePath;

  const ChatGptAuthStore({this.customFilePath});

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

  File _getSessionFile() {
    if (customFilePath != null && customFilePath!.isNotEmpty) {
      return File(customFilePath!);
    }
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      return File(
        '$home/Library/Application Support/pulse_training_hub/chatgpt_session.json',
      );
    }
    return File(
      '${Directory.systemTemp.path}/pulse_training_hub_chatgpt_session.json',
    );
  }

  /// Atomically writes [session] to disk via a unique `.tmp` file + rename
  /// and restricts permissions to owner-only (`0600`) on macOS/Linux.
  Future<void> save(ChatGptSession session) {
    final file = _getSessionFile();
    return _withPathLock(_lockKey(file), () async {
      await file.parent.create(recursive: true);

      final encoded = jsonEncode(session.toJson());
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

  /// Reads and deserializes the persisted [ChatGptSession] from disk.
  /// Returns `null` if the file is missing, empty, corrupt, or incomplete
  /// (never throws).
  Future<ChatGptSession?> load() {
    final file = _getSessionFile();
    return _withPathLock(_lockKey(file), () async {
      try {
        if (!await file.exists()) return null;

        final raw = await file.readAsString();
        if (raw.trim().isEmpty) return null;

        final decoded = jsonDecode(raw);
        if (decoded is! Map) return null;

        final map = decoded is Map<String, dynamic>
            ? decoded
            : Map<String, dynamic>.from(decoded);
        return ChatGptSession.fromJson(map);
      } catch (_) {
        return null;
      }
    });
  }

  /// Safely deletes the session file and any stale `.tmp` files if present.
  Future<void> clear() {
    final file = _getSessionFile();
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
