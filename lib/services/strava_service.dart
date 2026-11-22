import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../models/activity.dart';
import '../models/strava_enrichment.dart';
import 'strava_auth_store.dart';

class StravaAuthException implements Exception {
  final String message;

  const StravaAuthException(this.message);

  @override
  String toString() => 'StravaAuthException: $message';
}

class StravaApiException implements Exception {
  final int statusCode;
  final String message;

  const StravaApiException(this.statusCode, this.message);

  @override
  String toString() => 'StravaApiException($statusCode): $message';
}

class StravaService {
  static const String apiBaseUrl = 'https://www.strava.com/api/v3';
  static const String tokenEndpoint = 'https://www.strava.com/oauth/token';
  static const String defaultScope = 'read,activity:read_all';

  final http.Client _client;
  final bool _ownsClient;

  StravaService({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }

  /// Builds the Strava OAuth 2.0 browser authorization URL.
  String buildAuthorizeUrl(String clientId, String redirectUri) {
    final trimmedId = clientId.trim();
    if (trimmedId.isEmpty) {
      throw const StravaAuthException('Strava Client ID is required.');
    }
    return Uri.https('www.strava.com', '/oauth/authorize', {
      'client_id': trimmedId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'approval_prompt': 'auto',
      'scope': defaultScope,
    }).toString();
  }

  /// Exchanges an OAuth 2.0 authorization code for a [StravaSession].
  Future<StravaSession> exchangeAuthorizationCode(
    String clientId,
    String clientSecret,
    String code,
  ) async {
    final trimmedId = clientId.trim();
    final trimmedSecret = clientSecret.trim();
    final trimmedCode = code.trim();
    if (trimmedId.isEmpty || trimmedSecret.isEmpty || trimmedCode.isEmpty) {
      throw const StravaAuthException(
        'Client ID, Client Secret, and authorization code are required.',
      );
    }

    final response = await _client.post(
      Uri.parse(tokenEndpoint),
      headers: const {'Accept': 'application/json'},
      body: {
        'client_id': trimmedId,
        'client_secret': trimmedSecret,
        'code': trimmedCode,
        'grant_type': 'authorization_code',
      },
    );

    final body = _decodeJsonMap(response);
    if (response.statusCode != 200) {
      throw StravaAuthException(
        _extractErrorMessage(body, response.statusCode, 'Token exchange failed'),
      );
    }

    final accessToken = (body['access_token'] as String?) ?? '';
    if (accessToken.isEmpty) {
      throw const StravaAuthException('Strava did not return an access token.');
    }

    final refreshToken = body['refresh_token'] as String?;
    final expiresAtEpoch = (body['expires_at'] as num?)?.toInt();
    final expiresAt = expiresAtEpoch != null
        ? DateTime.fromMillisecondsSinceEpoch(expiresAtEpoch * 1000, isUtc: true)
        : DateTime.now().toUtc().add(const Duration(hours: 6));

    String? athleteName;
    String? athleteId;
    final athlete = body['athlete'];
    if (athlete is Map<String, dynamic>) {
      athleteId = athlete['id']?.toString();
      final first = (athlete['firstname'] as String?)?.trim() ?? '';
      final last = (athlete['lastname'] as String?)?.trim() ?? '';
      final combined = '$first $last'.trim();
      if (combined.isNotEmpty) {
        athleteName = combined;
      }
    }

    return StravaSession(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: expiresAt,
      clientId: trimmedId,
      clientSecret: trimmedSecret,
      athleteName: athleteName,
      athleteId: athleteId,
    );
  }

  /// Refreshes an expired [StravaSession] using its stored refresh token.
  Future<StravaSession> refreshToken(StravaSession session) async {
    if (!session.canRefresh) {
      throw const StravaAuthException(
        'Cannot refresh Strava token: missing refresh token or client credentials.',
      );
    }

    final response = await _client.post(
      Uri.parse(tokenEndpoint),
      headers: const {'Accept': 'application/json'},
      body: {
        'client_id': session.clientId!,
        'client_secret': session.clientSecret!,
        'refresh_token': session.refreshToken!,
        'grant_type': 'refresh_token',
      },
    );

    final body = _decodeJsonMap(response);
    if (response.statusCode != 200) {
      throw StravaAuthException(
        _extractErrorMessage(body, response.statusCode, 'Token refresh failed'),
      );
    }

    final accessToken = (body['access_token'] as String?) ?? '';
    if (accessToken.isEmpty) {
      throw const StravaAuthException('Strava did not return a refreshed access token.');
    }

    final newRefreshToken = (body['refresh_token'] as String?) ?? session.refreshToken;
    final expiresAtEpoch = (body['expires_at'] as num?)?.toInt();
    final expiresAt = expiresAtEpoch != null
        ? DateTime.fromMillisecondsSinceEpoch(expiresAtEpoch * 1000, isUtc: true)
        : DateTime.now().toUtc().add(const Duration(hours: 6));

    return session.copyWith(
      accessToken: accessToken,
      refreshToken: newRefreshToken,
      expiresAt: expiresAt,
    );
  }

  /// Binds a local HTTP server on `127.0.0.1:[port]` and waits for Strava's
  /// OAuth callback at `/callback?code=...`.
  ///
  /// If [onServerReady] is provided, it is invoked with the bound redirect URI
  /// (`http://127.0.0.1:<port>/callback`) once the server is listening.
  Future<String> waitForOAuthCode({
    int port = 8765,
    Duration timeout = const Duration(minutes: 3),
    Future<void> Function(String redirectUri)? onServerReady,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    final actualPort = server.port;
    final redirectUri = 'http://127.0.0.1:$actualPort/callback';
    final completer = Completer<String>();
    late final StreamSubscription<HttpRequest> subscription;
    Timer? timer;

    Future<void> shutdown() async {
      timer?.cancel();
      await subscription.cancel();
      await server.close(force: true);
    }

    subscription = server.listen(
      (HttpRequest request) async {
        if (request.uri.path != '/callback') {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }

        final error = request.uri.queryParameters['error'];
        final code = request.uri.queryParameters['code'];

        if (error != null && error.isNotEmpty) {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.html
            ..write(_callbackHtml(
              title: 'Strava Connection Cancelled',
              body: 'Authorization was cancelled ($error). You can close this tab and return to Pulse Training.',
            ));
          await request.response.close();
          if (!completer.isCompleted) {
            completer.completeError(
              StravaAuthException('Strava authorization was denied: $error'),
            );
          }
          await shutdown();
          return;
        }

        if (code == null || code.trim().isEmpty) {
          request.response
            ..statusCode = HttpStatus.badRequest
            ..headers.contentType = ContentType.html
            ..write(_callbackHtml(
              title: 'Missing Authorization Code',
              body: 'Strava did not return an authorization code. Please try again from Pulse Training.',
            ));
          await request.response.close();
          if (!completer.isCompleted) {
            completer.completeError(
              const StravaAuthException('Callback missing authorization code.'),
            );
          }
          await shutdown();
          return;
        }

        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.html
          ..write(_callbackHtml(
            title: 'Connected to Pulse Training',
            body: 'Connected to Pulse Training — you can close this tab.',
          ));
        await request.response.close();

        if (!completer.isCompleted) {
          completer.complete(code.trim());
        }
        await shutdown();
      },
      onError: (Object err, StackTrace st) async {
        if (!completer.isCompleted) {
          completer.completeError(err, st);
        }
        await shutdown();
      },
    );

    timer = Timer(timeout, () async {
      if (!completer.isCompleted) {
        completer.completeError(
          const StravaAuthException('Timed out waiting for Strava OAuth callback.'),
        );
      }
      await shutdown();
    });

    if (onServerReady != null) {
      try {
        await onServerReady(redirectUri);
      } catch (err, st) {
        if (!completer.isCompleted) {
          completer.completeError(err, st);
        }
        await shutdown();
      }
    }

    return completer.future;
  }

  /// Fetches the authenticated athlete's basic profile (`GET /athlete`).
  Future<({String id, String name})> fetchAthleteProfile(StravaSession session) async {
    final uri = Uri.parse('$apiBaseUrl/athlete');
    final response = await _client.get(uri, headers: _authHeaders(session));
    if (response.statusCode != 200) {
      throw _apiError(response, 'Failed to fetch Strava athlete profile');
    }
    final json = _decodeJsonMap(response);
    final id = (json['id'] ?? '').toString();
    final first = (json['firstname'] as String?)?.trim() ?? '';
    final last = (json['lastname'] as String?)?.trim() ?? '';
    final name = '$first $last'.trim();
    return (id: id, name: name.isNotEmpty ? name : 'Strava Athlete');
  }

  /// Fetches paginated athlete activity summaries (`GET /athlete/activities`).
  Future<List<StravaActivityEnrichment>> fetchActivities(
    StravaSession session, {
    int page = 1,
    int perPage = 100,
  }) async {
    final uri = Uri.parse('$apiBaseUrl/athlete/activities').replace(
      queryParameters: {
        'page': page.toString(),
        'per_page': perPage.toString(),
      },
    );
    final response = await _client.get(uri, headers: _authHeaders(session));
    if (response.statusCode != 200) {
      throw _apiError(response, 'Failed to fetch Strava activities');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      return const [];
    }
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(StravaActivityEnrichment.fromStravaApi)
        .toList();
  }

  /// Fetches detailed activity enrichment including description, gear,
  /// segment efforts, best efforts, and suffer score (`GET /activities/{id}`).
  Future<StravaActivityEnrichment> fetchActivityDetail(
    StravaSession session,
    String stravaId,
  ) async {
    final uri = Uri.parse('$apiBaseUrl/activities/$stravaId').replace(
      queryParameters: const {'include_all_efforts': 'true'},
    );
    final response = await _client.get(uri, headers: _authHeaders(session));
    if (response.statusCode != 200) {
      throw _apiError(response, 'Failed to fetch Strava activity detail');
    }
    final json = _decodeJsonMap(response);
    return StravaActivityEnrichment.fromStravaApi(json);
  }

  /// Fetches comments for an activity (`GET /activities/{id}/comments`).
  Future<List<StravaComment>> fetchActivityComments(
    StravaSession session,
    String stravaId,
  ) async {
    final uri = Uri.parse('$apiBaseUrl/activities/$stravaId/comments');
    final response = await _client.get(uri, headers: _authHeaders(session));
    if (response.statusCode != 200) {
      throw _apiError(response, 'Failed to fetch Strava activity comments');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      return const [];
    }
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(StravaComment.fromStravaApi)
        .toList();
  }

  /// Matches Strava activities to Garmin activities by:
  /// - Start timestamp within ±5 minutes
  /// - Distance within ±5% (or ±200m for short/indoor/strength activities)
  /// - Compatible sport discipline
  ///
  /// Returns a map keyed by `garminActivity.id`.
  static Map<String, StravaActivityEnrichment> matchStravaToGarmin(
    List<Activity> garminActivities,
    List<StravaActivityEnrichment> stravaActivities,
  ) {
    final matches = <String, StravaActivityEnrichment>{};
    final usedStravaIds = <String>{};

    const maxTimeDelta = Duration(minutes: 5);

    for (final garmin in garminActivities) {
      StravaActivityEnrichment? bestCandidate;
      double bestScore = double.infinity;

      final garminStartUtc = garmin.timestamp.toUtc();
      final garminDistanceM = garmin.distanceKm * 1000.0;

      for (final strava in stravaActivities) {
        if (usedStravaIds.contains(strava.stravaId)) continue;
        if (!_isCompatibleSport(garmin.discipline, strava.sportType)) continue;

        final timeDiff = garminStartUtc.difference(strava.startDate.toUtc()).abs();
        if (timeDiff > maxTimeDelta) continue;

        if (!_isCompatibleDistance(
          garmin.discipline,
          garminDistanceM,
          strava.distanceM,
        )) {
          continue;
        }

        // Score prefers closest start time, breaking ties by closest distance.
        final distanceDiffM = (garminDistanceM - strava.distanceM).abs();
        final score = timeDiff.inSeconds.toDouble() + (distanceDiffM / 100.0);
        if (score < bestScore) {
          bestScore = score;
          bestCandidate = strava;
        }
      }

      if (bestCandidate != null) {
        matches[garmin.id] = bestCandidate;
        usedStravaIds.add(bestCandidate.stravaId);
      }
    }

    return matches;
  }

  static bool _isCompatibleDistance(
    SportDiscipline discipline,
    double garminDistanceM,
    double stravaDistanceM,
  ) {
    final diffM = (garminDistanceM - stravaDistanceM).abs();
    final maxDistM = math.max(garminDistanceM, stravaDistanceM);

    final isShortOrIndoorOrStrength = discipline == SportDiscipline.strength ||
        discipline == SportDiscipline.indoorBike ||
        maxDistM <= 1000.0;

    if (isShortOrIndoorOrStrength) {
      if (diffM <= 200.0) return true;
      return maxDistM > 0 && (diffM / maxDistM) <= 0.05;
    }

    if (maxDistM == 0) return true;
    return (diffM / maxDistM) <= 0.05;
  }

  static bool _isCompatibleSport(
    SportDiscipline discipline,
    String stravaSportType,
  ) {
    final normalized = stravaSportType
        .toLowerCase()
        .replaceAll(RegExp(r'[\s_\-]'), '');

    switch (discipline) {
      case SportDiscipline.run:
        return const {
          'run',
          'trailrun',
          'virtualrun',
          'treadmill',
        }.contains(normalized);
      case SportDiscipline.bike:
        return const {
          'ride',
          'gravelride',
          'mountainbikeride',
          'ebikeride',
          'emountainbikeride',
          'handcycle',
          'velomobile',
        }.contains(normalized);
      case SportDiscipline.indoorBike:
        return const {
          'virtualride',
          'ride',
          'indoorcycling',
        }.contains(normalized);
      case SportDiscipline.swim:
        return const {
          'swim',
          'openwaterswim',
        }.contains(normalized);
      case SportDiscipline.strength:
        return const {
          'weighttraining',
          'workout',
          'crossfit',
          'hiit',
          'yoga',
          'pilates',
          'strengthtraining',
          'elliptical',
          'stairstepper',
        }.contains(normalized);
    }
  }

  Map<String, String> _authHeaders(StravaSession session) => {
        'Authorization': 'Bearer ${session.accessToken}',
        'Accept': 'application/json',
      };

  Map<String, dynamic> _decodeJsonMap(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {}
    return const {};
  }

  String _extractErrorMessage(
    Map<String, dynamic> body,
    int statusCode,
    String fallback,
  ) {
    final message = body['message'] as String?;
    if (message != null && message.trim().isNotEmpty) {
      return '$message (HTTP $statusCode)';
    }
    return '$fallback (HTTP $statusCode)';
  }

  StravaApiException _apiError(http.Response response, String fallback) {
    final body = _decodeJsonMap(response);
    return StravaApiException(
      response.statusCode,
      _extractErrorMessage(body, response.statusCode, fallback),
    );
  }

  String _callbackHtml({required String title, required String body}) {
    return '''
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title>$title</title>
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
      background: #f5f5f7;
      color: #1d1d1f;
      display: flex;
      align-items: center;
      justify-content: center;
      min-height: 100vh;
      margin: 0;
    }
    .card {
      background: #ffffff;
      border: 1px solid rgba(0, 0, 0, 0.08);
      border-radius: 14px;
      padding: 28px 34px;
      max-width: 440px;
      text-align: center;
      box-shadow: 0 6px 24px rgba(0, 0, 0, 0.06);
    }
    h1 { font-size: 18px; margin: 0 0 8px 0; }
    p { font-size: 14px; color: #515154; margin: 0; line-height: 1.45; }
  </style>
</head>
<body>
  <div class="card">
    <h1>$title</h1>
    <p>$body</p>
  </div>
</body>
</html>
''';
  }
}
