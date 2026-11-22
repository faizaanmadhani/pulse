import 'dart:convert';
import 'dart:io';

class StravaSession {
  final String accessToken;
  final String? refreshToken;
  final DateTime expiresAt;
  final String? clientId;
  final String? clientSecret;
  final String? athleteName;
  final String? athleteId;

  const StravaSession({
    required this.accessToken,
    this.refreshToken,
    required this.expiresAt,
    this.clientId,
    this.clientSecret,
    this.athleteName,
    this.athleteId,
  });

  bool get isExpired =>
      DateTime.now().isAfter(expiresAt.subtract(const Duration(minutes: 2)));

  bool get canRefresh =>
      (refreshToken?.isNotEmpty ?? false) &&
      (clientId?.isNotEmpty ?? false) &&
      (clientSecret?.isNotEmpty ?? false);

  StravaSession copyWith({
    String? accessToken,
    String? refreshToken,
    DateTime? expiresAt,
    String? clientId,
    String? clientSecret,
    String? athleteName,
    String? athleteId,
  }) {
    return StravaSession(
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      expiresAt: expiresAt ?? this.expiresAt,
      clientId: clientId ?? this.clientId,
      clientSecret: clientSecret ?? this.clientSecret,
      athleteName: athleteName ?? this.athleteName,
      athleteId: athleteId ?? this.athleteId,
    );
  }

  Map<String, dynamic> toJson() => {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'expiresAt': expiresAt.toUtc().toIso8601String(),
        'clientId': clientId,
        'clientSecret': clientSecret,
        'athleteName': athleteName,
        'athleteId': athleteId,
      };

  factory StravaSession.fromJson(Map<String, dynamic> json) {
    return StravaSession(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String?,
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      clientId: json['clientId'] as String?,
      clientSecret: json['clientSecret'] as String?,
      athleteName: json['athleteName'] as String?,
      athleteId: json['athleteId']?.toString(),
    );
  }
}

/// Persists Strava OAuth tokens locally inside macOS Application Support.
class StravaAuthStore {
  final String? customFilePath;

  const StravaAuthStore({this.customFilePath});

  File _getSessionFile() {
    if (customFilePath != null) {
      return File(customFilePath!);
    }
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      return File(
        '$home/Library/Application Support/pulse_training_hub/strava_session.json',
      );
    }
    return File(
      '${Directory.systemTemp.path}/pulse_training_hub_strava_session.json',
    );
  }

  Future<void> save(StravaSession session) async {
    final file = _getSessionFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(session.toJson()));
    // Best-effort restrict file permissions to current user (0600) on macOS/Linux.
    if (!Platform.isWindows) {
      try {
        await Process.run('chmod', ['600', file.path]);
      } catch (_) {}
    }
  }

  Future<StravaSession?> load() async {
    try {
      final file = _getSessionFile();
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return StravaSession.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    try {
      final file = _getSessionFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}
