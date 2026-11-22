import 'dart:convert';
import 'dart:io';

class GarminSession {
  final String oauth1Token;
  final String oauth1TokenSecret;
  final String? mfaToken;
  final String accessToken;
  final String? refreshToken;
  final DateTime expiresAt;
  final String consumerKey;
  final String consumerSecret;
  final String domain;

  const GarminSession({
    required this.oauth1Token,
    required this.oauth1TokenSecret,
    this.mfaToken,
    required this.accessToken,
    this.refreshToken,
    required this.expiresAt,
    required this.consumerKey,
    required this.consumerSecret,
    this.domain = 'garmin.com',
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt.subtract(const Duration(minutes: 2)));

  GarminSession copyWith({
    String? accessToken,
    String? refreshToken,
    DateTime? expiresAt,
  }) {
    return GarminSession(
      oauth1Token: oauth1Token,
      oauth1TokenSecret: oauth1TokenSecret,
      mfaToken: mfaToken,
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      expiresAt: expiresAt ?? this.expiresAt,
      consumerKey: consumerKey,
      consumerSecret: consumerSecret,
      domain: domain,
    );
  }

  Map<String, dynamic> toJson() => {
        'oauth1Token': oauth1Token,
        'oauth1TokenSecret': oauth1TokenSecret,
        'mfaToken': mfaToken,
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'expiresAt': expiresAt.toIso8601String(),
        'consumerKey': consumerKey,
        'consumerSecret': consumerSecret,
        'domain': domain,
      };

  factory GarminSession.fromJson(Map<String, dynamic> json) {
    return GarminSession(
      oauth1Token: json['oauth1Token'] as String,
      oauth1TokenSecret: json['oauth1TokenSecret'] as String,
      mfaToken: json['mfaToken'] as String?,
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String?,
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      consumerKey: json['consumerKey'] as String,
      consumerSecret: json['consumerSecret'] as String,
      domain: (json['domain'] as String?) ?? 'garmin.com',
    );
  }
}

class GarminUserProfile {
  final String displayName;
  final String fullName;
  final String? userName;
  final String? profileImageUrl;

  const GarminUserProfile({
    required this.displayName,
    required this.fullName,
    this.userName,
    this.profileImageUrl,
  });

  String get initials {
    final source = fullName.trim().isNotEmpty ? fullName.trim() : displayName.trim();
    if (source.isEmpty) return 'G';
    final parts = source.split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return source[0].toUpperCase();
  }

  Map<String, dynamic> toJson() => {
        'displayName': displayName,
        'fullName': fullName,
        'userName': userName,
        'profileImageUrl': profileImageUrl,
      };

  factory GarminUserProfile.fromJson(Map<String, dynamic> json) {
    return GarminUserProfile(
      displayName: (json['displayName'] as String?) ?? '',
      fullName: (json['fullName'] as String?) ?? '',
      userName: json['userName'] as String?,
      profileImageUrl: json['profileImageUrl'] as String?,
    );
  }
}

/// Persists Garmin OAuth tokens locally inside macOS Application Support.
/// Never stores the user's password.
class GarminAuthStore {
  final String? customFilePath;

  const GarminAuthStore({this.customFilePath});

  File _getSessionFile() {
    if (customFilePath != null) {
      return File(customFilePath!);
    }
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      return File('$home/Library/Application Support/pulse_training_hub/garmin_session.json');
    }
    return File('${Directory.systemTemp.path}/pulse_training_hub_garmin_session.json');
  }

  Future<void> save(GarminSession session, {GarminUserProfile? profile}) async {
    final file = _getSessionFile();
    await file.parent.create(recursive: true);
    final payload = {
      'session': session.toJson(),
      if (profile != null) 'profile': profile.toJson(),
    };
    await file.writeAsString(jsonEncode(payload));
    // Best-effort restrict file permissions to current user (0600) on macOS/Linux.
    if (!Platform.isWindows) {
      try {
        await Process.run('chmod', ['600', file.path]);
      } catch (_) {}
    }
  }

  Future<({GarminSession session, GarminUserProfile? profile})?> load() async {
    try {
      final file = _getSessionFile();
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final sessionJson = decoded['session'] as Map<String, dynamic>?;
      if (sessionJson == null) return null;
      final session = GarminSession.fromJson(sessionJson);
      final profileJson = decoded['profile'] as Map<String, dynamic>?;
      final profile = profileJson != null ? GarminUserProfile.fromJson(profileJson) : null;
      return (session: session, profile: profile);
    } catch (_) {
      return null;
    }
  }

  File _getGoalsFile() {
    final sessionFile = _getSessionFile();
    return File('${sessionFile.parent.path}/race_goals.json');
  }

  Future<void> saveGoals(List<Map<String, dynamic>> goals) async {
    try {
      final file = _getGoalsFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(goals));
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> loadGoals() async {
    try {
      final file = _getGoalsFile();
      if (!await file.exists()) return const [];
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      return const [];
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
