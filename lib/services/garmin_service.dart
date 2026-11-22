import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../models/activity.dart';
import '../models/device_status.dart';
import '../models/performance_metrics.dart';
import 'garmin_auth_store.dart';

class GarminAuthException implements Exception {
  final String message;
  const GarminAuthException(this.message);

  @override
  String toString() => message;
}

class GarminUnauthorizedException extends GarminAuthException {
  const GarminUnauthorizedException([
    super.message = 'Garmin session expired (HTTP 401). Please sign in again.',
  ]);
}

class GarminMfaChallenge {
  final String csrfToken;
  final Map<String, String> cookies;
  final String consumerKey;
  final String consumerSecret;
  final String domain;

  const GarminMfaChallenge({
    required this.csrfToken,
    required this.cookies,
    required this.consumerKey,
    required this.consumerSecret,
    this.domain = 'garmin.com',
  });
}

class GarminLoginResult {
  final GarminSession? session;
  final GarminMfaChallenge? mfaChallenge;

  const GarminLoginResult._({this.session, this.mfaChallenge});

  factory GarminLoginResult.authenticated(GarminSession session) =>
      GarminLoginResult._(session: session);

  factory GarminLoginResult.mfaRequired(GarminMfaChallenge challenge) =>
      GarminLoginResult._(mfaChallenge: challenge);

  bool get requiresMfa => mfaChallenge != null;
}

class GarminDailyStats {
  final int? restingHr;
  final int? hrvMs;
  final double? vo2Max;
  final int? dailySteps;
  final int? activeCalories;

  const GarminDailyStats({
    this.restingHr,
    this.hrvMs,
    this.vo2Max,
    this.dailySteps,
    this.activeCalories,
  });
}

/// RFC 5849 OAuth 1.0a HMAC-SHA1 request signer used for Garmin token exchange.
class OAuth1Signer {
  static final Random _random = Random.secure();

  static String percentEncode(String input) {
    final encoded = Uri.encodeComponent(input);
    // RFC 5849 requires encoding !, *, ', (, )
    return encoded
        .replaceAll('!', '%21')
        .replaceAll('*', '%2A')
        .replaceAll("'", '%27')
        .replaceAll('(', '%28')
        .replaceAll(')', '%29');
  }

  static String generateNonce() {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return List.generate(24, (_) => chars[_random.nextInt(chars.length)]).join();
  }

  static String buildAuthorizationHeader({
    required String method,
    required Uri url,
    required String consumerKey,
    required String consumerSecret,
    String? token,
    String? tokenSecret,
    Map<String, String>? bodyParams,
    String? nonce,
    String? timestamp,
  }) {
    final oauthParams = <String, String>{
      'oauth_consumer_key': consumerKey,
      'oauth_nonce': nonce ?? generateNonce(),
      'oauth_signature_method': 'HMAC-SHA1',
      'oauth_timestamp': timestamp ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString(),
      'oauth_version': '1.0',
      if (token != null) 'oauth_token': token,
    };

    // Collect all query + body + oauth parameters for signature base string
    final allParams = <MapEntry<String, String>>[];
    url.queryParametersAll.forEach((k, values) {
      for (final v in values) {
        allParams.add(MapEntry(percentEncode(k), percentEncode(v)));
      }
    });
    if (bodyParams != null) {
      bodyParams.forEach((k, v) {
        allParams.add(MapEntry(percentEncode(k), percentEncode(v)));
      });
    }
    oauthParams.forEach((k, v) {
      allParams.add(MapEntry(percentEncode(k), percentEncode(v)));
    });

    allParams.sort((a, b) {
      final keyCmp = a.key.compareTo(b.key);
      return keyCmp != 0 ? keyCmp : a.value.compareTo(b.value);
    });

    final paramString = allParams.map((e) => '${e.key}=${e.value}').join('&');
    final baseUrl = '${url.scheme}://${url.host}${url.hasPort ? ':${url.port}' : ''}${url.path}';
    final signatureBase =
        '${method.toUpperCase()}&${percentEncode(baseUrl)}&${percentEncode(paramString)}';

    final signingKey = '${percentEncode(consumerSecret)}&${percentEncode(tokenSecret ?? '')}';
    final hmac = Hmac(sha1, utf8.encode(signingKey));
    final digest = hmac.convert(utf8.encode(signatureBase));
    final signature = base64Encode(digest.bytes);

    final headerParams = <String, String>{
      ...oauthParams,
      'oauth_signature': signature,
    };

    final headerEntries = headerParams.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    final headerValue = headerEntries
        .map((e) => '${percentEncode(e.key)}="${percentEncode(e.value)}"')
        .join(', ');

    return 'OAuth $headerValue';
  }
}

/// Real Garmin Connect SSO + OAuth1/OAuth2 + REST API client.
class GarminService {
  static const String _oauthConsumerUrl = 'https://thegarth.s3.amazonaws.com/oauth_consumer.json';
  static const String _ssoUserAgent = 'com.garmin.android.apps.connectmobile';
  static const String _apiUserAgent = 'GCM-iOS-5.7.2.1';
  static const Duration _timeout = Duration(seconds: 20);

  final http.Client _client;

  GarminService({http.Client? client}) : _client = client ?? http.Client();

  Future<({String key, String secret})> _fetchOAuthConsumer() async {
    final res = await _client.get(Uri.parse(_oauthConsumerUrl)).timeout(_timeout);
    if (res.statusCode != 200) {
      throw GarminAuthException(
        'Could not load Garmin OAuth consumer configuration (HTTP ${res.statusCode}).',
      );
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final key = data['consumer_key']?.toString();
    final secret = data['consumer_secret']?.toString();
    if (key == null || secret == null || key.isEmpty || secret.isEmpty) {
      throw const GarminAuthException('Invalid Garmin OAuth consumer configuration.');
    }
    return (key: key, secret: secret);
  }

  Map<String, String> _ssoParams(String domain) {
    final ssoEmbed = 'https://sso.$domain/sso/embed';
    return {
      'id': 'gauth-widget',
      'embedWidget': 'true',
      'gauthHost': ssoEmbed,
      'service': ssoEmbed,
      'source': ssoEmbed,
      'redirectAfterAccountLoginUrl': ssoEmbed,
      'redirectAfterAccountCreationUrl': ssoEmbed,
    };
  }

  void _mergeCookies(Map<String, String> jar, http.Response response) {
    final rawSetCookie = response.headers['set-cookie'];
    if (rawSetCookie == null || rawSetCookie.isEmpty) return;
    // Split multiple Set-Cookie headers safely without breaking Expires=Wed, ...
    final parts = rawSetCookie.split(RegExp(r',(?=\s*[A-Za-z0-9_\-]+=)'));
    for (final part in parts) {
      final firstSegment = part.split(';').first.trim();
      final eqIdx = firstSegment.indexOf('=');
      if (eqIdx > 0) {
        final name = firstSegment.substring(0, eqIdx).trim();
        final value = firstSegment.substring(eqIdx + 1).trim();
        if (value.isEmpty) {
          jar.remove(name);
        } else {
          jar[name] = value;
        }
      }
    }
  }

  String _cookieHeader(Map<String, String> jar) {
    return jar.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  String? _extractCsrf(String html) {
    final forward = RegExp(
      r'''name=["']_csrf["'][^>]*?value=["']([^"']+)["']''',
      caseSensitive: false,
    ).firstMatch(html);
    if (forward != null) return forward.group(1);

    final reverse = RegExp(
      r'''value=["']([^"']+)["'][^>]*?name=["']_csrf["']''',
      caseSensitive: false,
    ).firstMatch(html);
    return reverse?.group(1);
  }

  String? _extractTitle(String html) {
    final match = RegExp(r'<title>(.*?)</title>', caseSensitive: false, dotAll: true).firstMatch(html);
    return match?.group(1)?.trim();
  }

  String? _extractTicket(String html) {
    final match = RegExp(r'''embed\?ticket=([^"'&\s<)\\]+)''').firstMatch(html);
    return match?.group(1);
  }

  /// Signs into Garmin Connect using email and password.
  /// Returns either an authenticated [GarminSession] or a [GarminMfaChallenge].
  Future<GarminLoginResult> login({
    required String email,
    required String password,
    String domain = 'garmin.com',
  }) async {
    final trimmedEmail = email.trim();
    if (trimmedEmail.isEmpty || password.isEmpty) {
      throw const GarminAuthException('Please enter both your Garmin email and password.');
    }

    final consumer = await _fetchOAuthConsumer();
    final cookies = <String, String>{};
    final ssoBase = 'https://sso.$domain/sso';
    final ssoEmbed = '$ssoBase/embed';
    final params = _ssoParams(domain);

    // 1. Prime SSO cookies on /sso/embed
    final embedUri = Uri.parse(ssoEmbed).replace(queryParameters: {
      'id': 'gauth-widget',
      'embedWidget': 'true',
      'gauthHost': ssoBase,
    });
    final embedRes = await _client.get(
      embedUri,
      headers: {'User-Agent': _ssoUserAgent},
    ).timeout(_timeout);
    _mergeCookies(cookies, embedRes);

    // 2. Fetch /sso/signin to obtain CSRF token
    final signinUri = Uri.parse('$ssoBase/signin').replace(queryParameters: params);
    final getSigninRes = await _client.get(
      signinUri,
      headers: {
        'User-Agent': _ssoUserAgent,
        'Referer': embedUri.toString(),
        if (cookies.isNotEmpty) 'Cookie': _cookieHeader(cookies),
      },
    ).timeout(_timeout);
    _mergeCookies(cookies, getSigninRes);

    if (getSigninRes.statusCode == 429) {
      throw const GarminAuthException(
        'Garmin temporarily rate-limited sign-in attempts (HTTP 429). Please wait a few minutes and try again.',
      );
    }
    if (getSigninRes.statusCode >= 400) {
      throw GarminAuthException(
        'Garmin sign-in page rejected the request (HTTP ${getSigninRes.statusCode}).',
      );
    }

    final csrf = _extractCsrf(getSigninRes.body);
    if (csrf == null || csrf.isEmpty) {
      throw const GarminAuthException(
        'Unable to initialize Garmin sign-in session (missing CSRF token).',
      );
    }

    // 3. Submit credentials to /sso/signin
    final postSigninRes = await _client.post(
      signinUri,
      headers: {
        'User-Agent': _ssoUserAgent,
        'Referer': signinUri.toString(),
        'Content-Type': 'application/x-www-form-urlencoded',
        if (cookies.isNotEmpty) 'Cookie': _cookieHeader(cookies),
      },
      body: {
        'username': trimmedEmail,
        'password': password,
        'embed': 'true',
        '_csrf': csrf,
      },
    ).timeout(_timeout);
    _mergeCookies(cookies, postSigninRes);

    final title = _extractTitle(postSigninRes.body) ?? '';
    if (title.contains('MFA')) {
      final mfaCsrf = _extractCsrf(postSigninRes.body) ?? csrf;
      return GarminLoginResult.mfaRequired(
        GarminMfaChallenge(
          csrfToken: mfaCsrf,
          cookies: cookies,
          consumerKey: consumer.key,
          consumerSecret: consumer.secret,
          domain: domain,
        ),
      );
    }

    if (title != 'Success') {
      if (postSigninRes.statusCode == 429) {
        throw const GarminAuthException(
          'Garmin temporarily rate-limited sign-in attempts. Please wait a few minutes and try again.',
        );
      }
      if (postSigninRes.statusCode == 403) {
        throw const GarminAuthException(
          'Garmin Connect blocked this sign-in request (HTTP 403). Please try again shortly.',
        );
      }
      throw const GarminAuthException(
        'Garmin sign-in failed. Please verify your email and password.',
      );
    }

    final ticket = _extractTicket(postSigninRes.body);
    if (ticket == null || ticket.isEmpty) {
      throw const GarminAuthException('Garmin sign-in succeeded but no service ticket was returned.');
    }

    final session = await _exchangeTicketForSession(
      ticket: ticket,
      consumerKey: consumer.key,
      consumerSecret: consumer.secret,
      domain: domain,
    );
    return GarminLoginResult.authenticated(session);
  }

  /// Completes a Garmin Connect 2FA / MFA challenge with the 6-digit code.
  Future<GarminSession> submitMfaCode({
    required GarminMfaChallenge challenge,
    required String mfaCode,
  }) async {
    final trimmedCode = mfaCode.trim();
    if (trimmedCode.isEmpty) {
      throw const GarminAuthException('Please enter the verification code from Garmin.');
    }

    final ssoBase = 'https://sso.${challenge.domain}/sso';
    final params = _ssoParams(challenge.domain);
    final mfaUri = Uri.parse('$ssoBase/verifyMFA/loginEnterMfaCode').replace(queryParameters: params);
    final cookies = Map<String, String>.from(challenge.cookies);

    final res = await _client.post(
      mfaUri,
      headers: {
        'User-Agent': _ssoUserAgent,
        'Referer': '$ssoBase/signin',
        'Content-Type': 'application/x-www-form-urlencoded',
        if (cookies.isNotEmpty) 'Cookie': _cookieHeader(cookies),
      },
      body: {
        'mfa-code': trimmedCode,
        'embed': 'true',
        '_csrf': challenge.csrfToken,
        'fromPage': 'setupEnterMfaCode',
      },
    ).timeout(_timeout);
    _mergeCookies(cookies, res);

    final title = _extractTitle(res.body) ?? '';
    if (title != 'Success') {
      if (res.statusCode == 429) {
        throw const GarminAuthException(
          'Too many verification attempts. Please wait a few minutes and try again.',
        );
      }
      throw const GarminAuthException('Invalid or expired verification code. Please try again.');
    }

    final ticket = _extractTicket(res.body);
    if (ticket == null || ticket.isEmpty) {
      throw const GarminAuthException('Verification succeeded but no Garmin ticket was returned.');
    }

    return _exchangeTicketForSession(
      ticket: ticket,
      consumerKey: challenge.consumerKey,
      consumerSecret: challenge.consumerSecret,
      domain: challenge.domain,
    );
  }

  /// Exchanges a CAS service ticket (`ST-...`) obtained from the native macOS
  /// WKWebView Garmin Connect sign-in for a full OAuth1 + OAuth2 session.
  Future<GarminSession> loginWithTicket({
    required String ticket,
    String domain = 'garmin.com',
  }) async {
    final trimmed = ticket.trim();
    if (trimmed.isEmpty) {
      throw const GarminAuthException('Garmin sign-in did not return a valid service ticket.');
    }
    final consumer = await _fetchOAuthConsumer();
    return _exchangeTicketForSession(
      ticket: trimmed,
      consumerKey: consumer.key,
      consumerSecret: consumer.secret,
      domain: domain,
    );
  }

  Future<GarminSession> _exchangeTicketForSession({
    required String ticket,
    required String consumerKey,
    required String consumerSecret,
    required String domain,
  }) async {
    final ssoEmbed = 'https://sso.$domain/sso/embed';
    final preauthUri = Uri.parse('https://connectapi.$domain/oauth-service/oauth/preauthorized')
        .replace(queryParameters: {
      'ticket': ticket,
      'login-url': ssoEmbed,
      'accepts-mfa-tokens': 'true',
    });

    final oauth1Header = OAuth1Signer.buildAuthorizationHeader(
      method: 'GET',
      url: preauthUri,
      consumerKey: consumerKey,
      consumerSecret: consumerSecret,
    );

    final oauth1Res = await _client.get(
      preauthUri,
      headers: {
        'User-Agent': _ssoUserAgent,
        'Authorization': oauth1Header,
      },
    ).timeout(_timeout);

    if (oauth1Res.statusCode != 200) {
      throw GarminAuthException(
        'Failed to obtain Garmin OAuth1 token (HTTP ${oauth1Res.statusCode}).',
      );
    }

    final oauth1Params = Uri.splitQueryString(oauth1Res.body);
    final oauth1Token = oauth1Params['oauth_token'];
    final oauth1Secret = oauth1Params['oauth_token_secret'];
    final mfaToken = oauth1Params['mfa_token'];

    if (oauth1Token == null || oauth1Secret == null) {
      throw const GarminAuthException('Garmin OAuth1 response was missing required tokens.');
    }

    return _exchangeOAuth1ForOAuth2(
      oauth1Token: oauth1Token,
      oauth1Secret: oauth1Secret,
      mfaToken: mfaToken,
      consumerKey: consumerKey,
      consumerSecret: consumerSecret,
      domain: domain,
    );
  }

  Future<GarminSession> refreshOAuth2Token(GarminSession session) {
    return _exchangeOAuth1ForOAuth2(
      oauth1Token: session.oauth1Token,
      oauth1Secret: session.oauth1TokenSecret,
      mfaToken: session.mfaToken,
      consumerKey: session.consumerKey,
      consumerSecret: session.consumerSecret,
      domain: session.domain,
    );
  }

  Future<GarminSession> _exchangeOAuth1ForOAuth2({
    required String oauth1Token,
    required String oauth1Secret,
    String? mfaToken,
    required String consumerKey,
    required String consumerSecret,
    required String domain,
  }) async {
    final exchangeUri = Uri.parse('https://connectapi.$domain/oauth-service/oauth/exchange/user/2.0');
    final bodyParams = <String, String>{
      if (mfaToken != null && mfaToken.isNotEmpty) 'mfa_token': mfaToken,
    };

    final authHeader = OAuth1Signer.buildAuthorizationHeader(
      method: 'POST',
      url: exchangeUri,
      consumerKey: consumerKey,
      consumerSecret: consumerSecret,
      token: oauth1Token,
      tokenSecret: oauth1Secret,
      bodyParams: bodyParams,
    );

    final res = await _client.post(
      exchangeUri,
      headers: {
        'User-Agent': _ssoUserAgent,
        'Authorization': authHeader,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: bodyParams,
    ).timeout(_timeout);

    if (res.statusCode != 200) {
      throw GarminAuthException(
        'Failed to exchange Garmin OAuth2 token (HTTP ${res.statusCode}).',
      );
    }

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final accessToken = json['access_token'] as String?;
    final refreshToken = json['refresh_token'] as String?;
    final expiresIn = (json['expires_in'] as num?)?.toInt() ?? 3600;

    if (accessToken == null || accessToken.isEmpty) {
      throw const GarminAuthException('Garmin OAuth2 response was missing an access token.');
    }

    return GarminSession(
      oauth1Token: oauth1Token,
      oauth1TokenSecret: oauth1Secret,
      mfaToken: mfaToken,
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
      consumerKey: consumerKey,
      consumerSecret: consumerSecret,
      domain: domain,
    );
  }

  Map<String, String> _apiHeaders(GarminSession session) => {
        'Authorization': 'Bearer ${session.accessToken}',
        'User-Agent': _apiUserAgent,
        'Accept': 'application/json',
        'DI-Backend': 'connectapi.${session.domain}',
      };

  Future<GarminUserProfile> fetchUserProfile(GarminSession session) async {
    final uri = Uri.parse('https://connectapi.${session.domain}/userprofile-service/socialProfile');
    final res = await _client.get(uri, headers: _apiHeaders(session)).timeout(_timeout);
    if (res.statusCode == 401) {
      throw const GarminUnauthorizedException();
    }
    if (res.statusCode != 200) {
      throw GarminAuthException('Failed to fetch Garmin profile (HTTP ${res.statusCode}).');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final displayName = data['displayName']?.toString() ?? '';
    final fullName = data['fullName']?.toString();
    return GarminUserProfile(
      displayName: displayName,
      fullName: (fullName != null && fullName.trim().isNotEmpty)
          ? fullName.trim()
          : (displayName.isNotEmpty ? displayName : 'Garmin Athlete'),
      userName: data['userName']?.toString(),
      profileImageUrl:
          data['profileImageUrlSmall']?.toString() ?? data['profileImageUrlMedium']?.toString(),
    );
  }

  Future<List<Activity>> fetchActivities(
    GarminSession session, {
    int start = 0,
    int limit = 100,
  }) async {
    final uri = Uri.parse(
      'https://connectapi.${session.domain}/activitylist-service/activities/search/activities',
    ).replace(queryParameters: {'start': start.toString(), 'limit': limit.toString()});

    final res = await _client.get(uri, headers: _apiHeaders(session)).timeout(_timeout);
    if (res.statusCode == 401) {
      throw const GarminUnauthorizedException();
    }
    if (res.statusCode != 200) {
      throw GarminAuthException('Failed to fetch Garmin activities (HTTP ${res.statusCode}).');
    }

    final decoded = jsonDecode(res.body);
    if (decoded is! List) return [];

    return decoded
        .whereType<Map<String, dynamic>>()
        .map(_parseGarminActivity)
        .toList();
  }

  Future<List<ActivitySplit>> fetchActivitySplits(
    GarminSession session,
    String activityId, {
    SportDiscipline discipline = SportDiscipline.run,
  }) async {
    final uri = Uri.parse(
      'https://connectapi.${session.domain}/activity-service/activity/$activityId/splits',
    );
    final res = await _client.get(uri, headers: _apiHeaders(session)).timeout(_timeout);
    if (res.statusCode == 401) {
      throw const GarminUnauthorizedException();
    }
    if (res.statusCode != 200 || res.body.isEmpty) return [];

    final dynamic decoded;
    try {
      decoded = jsonDecode(res.body);
    } catch (_) {
      return [];
    }
    if (decoded is! Map<String, dynamic>) return [];
    final laps = decoded['lapDTOs'];
    if (laps is! List) return [];

    final splits = <ActivitySplit>[];
    for (int i = 0; i < laps.length; i++) {
      final lap = laps[i];
      if (lap is! Map<String, dynamic>) continue;
      final distM = (lap['distance'] as num?)?.toDouble() ?? 0.0;
      final durSec = (lap['duration'] as num?)?.toDouble() ?? 0.0;
      final avgSpeedMps = (lap['averageSpeed'] as num?)?.toDouble() ?? 0.0;
      final avgHr = (lap['averageHR'] as num?)?.round() ?? 0;
      final avgPower = (lap['averagePower'] as num?)?.round() ?? (lap['avgPower'] as num?)?.round();
      final elevGain = (lap['elevationGain'] as num?)?.toDouble();
      final cadence = (lap['averageRunCadence'] as num?)?.round() ??
          (lap['averageBikeCadence'] as num?)?.round() ??
          (lap['averageSwimCadence'] as num?)?.round();

      splits.add(
        ActivitySplit(
          splitNumber: i + 1,
          label: 'Lap ${i + 1}',
          time: formatDurationSeconds(durSec),
          distanceKm: double.parse((distM / 1000.0).toStringAsFixed(2)),
          paceOrSpeed: avgSpeedMps > 0 ? formatMetricForDiscipline(discipline, avgSpeedMps) : '—',
          avgHr: avgHr,
          avgPower: avgPower,
          elevationDeltaM: elevGain,
          cadence: cadence,
        ),
      );
    }
    return splits;
  }

  /// Fetches downsampled GPS polyline + synchronized per-point telemetry streams
  /// (elevation, HR, speed, cadence, power, vertical oscillation, GCT) from Garmin Connect.
  Future<List<GpsPoint>> fetchActivityPolyline(
    GarminSession session,
    String activityId, {
    int maxPolylineSize = 200,
  }) async {
    final uri = Uri.parse(
      'https://connectapi.${session.domain}/activity-service/activity/$activityId/details',
    ).replace(queryParameters: {
      'maxChartSize': maxPolylineSize.toString(),
      'maxPolylineSize': maxPolylineSize.toString(),
    });
    final res = await _client.get(uri, headers: _apiHeaders(session)).timeout(_timeout);
    if (res.statusCode == 401) {
      throw const GarminUnauthorizedException();
    }
    if (res.statusCode != 200 || res.body.isEmpty) return const [];

    final dynamic decoded;
    try {
      decoded = jsonDecode(res.body);
    } catch (_) {
      return const [];
    }
    if (decoded is! Map<String, dynamic>) return const [];
    final geoDto = decoded['geoPolylineDTO'];
    if (geoDto is! Map<String, dynamic>) return const [];
    final rawPoints = geoDto['polyline'];
    if (rawPoints is! List) return const [];

    // Parse Garmin metricDescriptors + activityDetailMetrics when available
    final metricIndexByKey = <String, int>{};
    final descriptors = decoded['metricDescriptors'];
    if (descriptors is List) {
      for (final d in descriptors) {
        if (d is Map<String, dynamic>) {
          final key = d['key']?.toString();
          final idx = (d['metricsIndex'] as num?)?.toInt();
          if (key != null && idx != null) {
            metricIndexByKey[key] = idx;
          }
        }
      }
    }
    final detailMetrics = decoded['activityDetailMetrics'] is List
        ? (decoded['activityDetailMetrics'] as List)
        : const [];

    double? metricAt(int pointIndex, int totalPoints, List<String> keys) {
      if (detailMetrics.isEmpty) return null;
      final mIdx = totalPoints <= 1
          ? 0
          : ((pointIndex / (totalPoints - 1)) * (detailMetrics.length - 1))
              .round()
              .clamp(0, detailMetrics.length - 1);
      final row = detailMetrics[mIdx];
      if (row is! Map<String, dynamic>) return null;
      final vals = row['metrics'];
      if (vals is! List) return null;
      for (final k in keys) {
        final col = metricIndexByKey[k];
        if (col != null && col >= 0 && col < vals.length) {
          final v = vals[col];
          if (v is num && v.isFinite) return v.toDouble();
        }
      }
      return null;
    }

    final points = <GpsPoint>[];
    double cumulativeDistM = 0.0;
    final totalRaw = rawPoints.length;

    for (int i = 0; i < totalRaw; i++) {
      final pt = rawPoints[i];
      if (pt is! Map<String, dynamic>) continue;
      final lat = (pt['lat'] as num?)?.toDouble();
      final lon = (pt['lon'] as num?)?.toDouble();
      if (lat == null || lon == null || lat.abs() > 90 || lon.abs() > 180) continue;

      final rawSpeed = (pt['speed'] as num?)?.toDouble();
      final rawTimeMs = (pt['time'] as num?)?.toDouble();
      final timeSec = rawTimeMs != null
          ? (rawTimeMs > 1e11 ? rawTimeMs / 1000.0 : rawTimeMs)
          : null;

      if (points.isNotEmpty) {
        cumulativeDistM += _haversineMeters(points.last.lat, points.last.lon, lat, lon);
      }

      double? speedMps = (rawSpeed != null && rawSpeed > 0)
          ? rawSpeed
          : metricAt(i, totalRaw, ['directSpeed']);
      if ((speedMps == null || speedMps <= 0) &&
          points.isNotEmpty &&
          timeSec != null &&
          points.last.timeSec != null) {
        final dt = timeSec - points.last.timeSec!;
        if (dt > 0.2) {
          final distM = _haversineMeters(points.last.lat, points.last.lon, lat, lon);
          final calc = distM / dt;
          if (calc > 0.1 && calc < 40.0) {
            speedMps = calc;
          }
        }
      }

      final distMetric = metricAt(i, totalRaw, ['sumDistance']);
      final elevM = metricAt(i, totalRaw, ['directElevation', 'elevation']);
      final hrVal = metricAt(i, totalRaw, ['directHeartRate', 'heartRate']);
      final cadVal = metricAt(i, totalRaw, [
        'directRunCadence',
        'directDoubleCadence',
        'directBikeCadence',
        'directSwimCadence',
        'cadence',
      ]);
      final pwrVal = metricAt(i, totalRaw, ['directPower', 'power']);
      final voVal = metricAt(i, totalRaw, ['directVerticalOscillation']);
      final gctVal = metricAt(i, totalRaw, ['directGroundContactTime']);

      points.add(
        GpsPoint(
          lat,
          lon,
          speedMps: (speedMps != null && speedMps > 0) ? speedMps : null,
          timeSec: timeSec,
          distanceM: distMetric ?? cumulativeDistM,
          elevationM: elevM,
          heartRate: hrVal != null && hrVal > 0 ? hrVal.round() : null,
          cadence: cadVal != null && cadVal > 0 ? cadVal.round() : null,
          powerW: pwrVal != null && pwrVal > 0 ? pwrVal.round() : null,
          verticalOscillationCm: voVal != null && voVal > 0
              ? (voVal > 25 ? voVal / 10.0 : voVal) // Garmin sometimes reports mm
              : null,
          groundContactTimeMs: gctVal != null && gctVal > 0 ? gctVal.round() : null,
        ),
      );
    }
    return points;
  }

  static double _haversineMeters(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180.0;
    final dLon = (lon2 - lon1) * pi / 180.0;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180.0) * cos(lat2 * pi / 180.0) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }

  Future<List<ConnectedDevice>> fetchDevices(GarminSession session) async {
    final uri = Uri.parse(
      'https://connectapi.${session.domain}/device-service/deviceregistration/devices',
    );
    final res = await _client.get(uri, headers: _apiHeaders(session)).timeout(_timeout);
    if (res.statusCode == 401) {
      throw const GarminUnauthorizedException();
    }
    if (res.statusCode != 200 || res.body.isEmpty) return [];

    final decoded = jsonDecode(res.body);
    if (decoded is! List) return [];

    return decoded.whereType<Map<String, dynamic>>().map((d) {
      final name = d['productDisplayName']?.toString().trim().isNotEmpty == true
          ? d['productDisplayName'].toString().trim()
          : (d['displayName']?.toString().trim().isNotEmpty == true
              ? d['displayName'].toString().trim()
              : 'Garmin Device');
      final id = (d['deviceId'] ?? d['unitId'] ?? name).toString();
      final category = d['deviceTypeName']?.toString().trim().isNotEmpty == true
          ? d['deviceTypeName'].toString().trim()
          : 'Garmin Hardware';
      final fwRaw = d['currentFirmwareVersion']?.toString().trim();
      final fw = (fwRaw != null && fwRaw.isNotEmpty) ? fwRaw : 'Unknown';
      final lastSyncMs = (d['lastSyncTime'] as num?)?.toInt();
      final lastSyncText = lastSyncMs != null
          ? DateFormat('MMM d, h:mm a').format(DateTime.fromMillisecondsSinceEpoch(lastSyncMs))
          : 'Synced via Garmin Connect';
      final partNum = d['partNumber']?.toString();

      return ConnectedDevice(
        id: id,
        name: name,
        category: category,
        protocol: 'Garmin Connect',
        state: DeviceConnectionState.connected,
        batteryPercent: 100,
        lastSyncTime: lastSyncText,
        firmwareVersion: fw == 'Unknown' ? fw : (fw.startsWith('v') ? fw : 'v$fw'),
        telemetryChannels: (partNum != null && partNum.isNotEmpty)
            ? 'Part #$partNum'
            : 'Registered Garmin Connect Device',
      );
    }).toList();
  }

  Future<GarminDailyStats> fetchDailyStats(
    GarminSession session,
    String displayName,
    DateTime date,
  ) async {
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    int? restingHr;
    int? hrvMs;
    double? vo2Max;
    int? dailySteps;
    int? activeCalories;

    // 1. Daily Summary (resting HR, steps, calories)
    if (displayName.isNotEmpty) {
      try {
        final summaryUri = Uri.parse(
          'https://connectapi.${session.domain}/usersummary-service/usersummary/daily/$displayName',
        ).replace(queryParameters: {'calendarDate': dateStr});
        final res = await _client.get(summaryUri, headers: _apiHeaders(session)).timeout(_timeout);
        if (res.statusCode == 200 && res.body.isNotEmpty) {
          final json = jsonDecode(res.body);
          if (json is Map<String, dynamic>) {
            restingHr = (json['restingHeartRate'] as num?)?.round();
            dailySteps = (json['totalSteps'] as num?)?.round();
            activeCalories = (json['activeKilocalories'] as num?)?.round();
          }
        }
      } catch (_) {}
    }

    // 2. HRV Summary
    try {
      final hrvUri = Uri.parse('https://connectapi.${session.domain}/hrv-service/hrv/$dateStr');
      final res = await _client.get(hrvUri, headers: _apiHeaders(session)).timeout(_timeout);
      if (res.statusCode == 200 && res.body.isNotEmpty) {
        final json = jsonDecode(res.body);
        if (json is Map<String, dynamic>) {
          final summary = json['hrvSummary'] as Map<String, dynamic>?;
          hrvMs = (summary?['lastNightAvg'] as num?)?.round() ??
              (summary?['weeklyAvg'] as num?)?.round();
        }
      }
    } catch (_) {}

    // 3. VO2 Max
    try {
      final maxMetUri = Uri.parse(
        'https://connectapi.${session.domain}/metrics-service/metrics/maxmet/latest/$dateStr',
      );
      final res = await _client.get(maxMetUri, headers: _apiHeaders(session)).timeout(_timeout);
      if (res.statusCode == 200 && res.body.isNotEmpty) {
        final decoded = jsonDecode(res.body);
        Map<String, dynamic>? entry;
        if (decoded is List && decoded.isNotEmpty && decoded.first is Map<String, dynamic>) {
          entry = decoded.first as Map<String, dynamic>;
        } else if (decoded is Map<String, dynamic>) {
          entry = decoded;
        }
        final generic = entry?['generic'] as Map<String, dynamic>?;
        final cycling = entry?['cycling'] as Map<String, dynamic>?;
        vo2Max = (generic?['vo2MaxPreciseValue'] as num?)?.toDouble() ??
            (generic?['vo2MaxValue'] as num?)?.toDouble() ??
            (cycling?['vo2MaxPreciseValue'] as num?)?.toDouble() ??
            (cycling?['vo2MaxValue'] as num?)?.toDouble();
      }
    } catch (_) {}

    return GarminDailyStats(
      restingHr: restingHr,
      hrvMs: hrvMs,
      vo2Max: vo2Max,
      dailySteps: dailySteps,
      activeCalories: activeCalories,
    );
  }

  /// Parses a Garmin Connect activity summary JSON object into our [Activity] model.
  Activity _parseGarminActivity(Map<String, dynamic> json) {
    final activityId = (json['activityId'] ?? '').toString();
    final title = (json['activityName'] as String?)?.trim().isNotEmpty == true
        ? (json['activityName'] as String).trim()
        : 'Garmin Activity';
    final description = (json['description'] as String?)?.trim() ?? '';

    final typeMap = json['activityType'] as Map<String, dynamic>?;
    final typeKey = ((typeMap?['typeKey'] as String?) ?? '').toLowerCase();
    final discipline = mapGarminSportType(typeKey);

    final startLocalStr = json['startTimeLocal'] as String?;
    final timestamp = startLocalStr != null
        ? (DateTime.tryParse(startLocalStr.replaceFirst(' ', 'T')) ?? DateTime.now())
        : DateTime.now();
    final formattedDate = DateFormat('EEE, MMM d, yyyy • h:mm a').format(timestamp);

    final distanceM = (json['distance'] as num?)?.toDouble() ?? 0.0;
    final distanceKm = double.parse((distanceM / 1000.0).toStringAsFixed(2));
    final durationSec = (json['duration'] as num?)?.toDouble() ?? 0.0;
    final movingSec = (json['movingDuration'] as num?)?.toDouble() ?? durationSec;

    final avgSpeedMps = (json['averageSpeed'] as num?)?.toDouble() ?? 0.0;
    final maxSpeedMps = (json['maxSpeed'] as num?)?.toDouble() ?? 0.0;

    final avgSpeedOrPace = formatMetricForDiscipline(discipline, avgSpeedMps);
    final maxSpeedOrPace = formatMetricForDiscipline(discipline, maxSpeedMps);

    final avgHr = (json['averageHR'] as num?)?.round() ?? 0;
    final maxHr = (json['maxHR'] as num?)?.round() ?? 0;
    final elevGain = (json['elevationGain'] as num?)?.toDouble() ?? 0.0;
    final elevLoss = (json['elevationLoss'] as num?)?.toDouble() ?? 0.0;
    final avgPower = (json['avgPower'] as num?)?.round();
    final normPower = (json['normPower'] as num?)?.round();
    final maxPower = (json['maxPower'] as num?)?.round();
    final tss = (json['trainingStressScore'] as num?)?.toDouble() ??
        (json['activityTrainingLoad'] as num?)?.toDouble();
    final intensityFactor = (json['intensityFactor'] as num?)?.toDouble();
    final calories = (json['calories'] as num?)?.round() ?? 0;

    final avgCadence = (json['averageRunningCadenceInStepsPerMinute'] as num?)?.round() ??
        (json['averageBikingCadenceInRevPerMinute'] as num?)?.round() ??
        (json['averageSwimCadenceInStrokesPerMinute'] as num?)?.round();
    final maxCadence = (json['maxRunningCadenceInStepsPerMinute'] as num?)?.round() ??
        (json['maxBikingCadenceInRevPerMinute'] as num?)?.round();

    final swolf = (json['averageSwolf'] as num?)?.round();
    final location = (json['locationName'] as String?)?.trim().isNotEmpty == true
        ? (json['locationName'] as String).trim()
        : 'Garmin Connect';

    RunningDynamics? runningDynamics;
    final gct = (json['avgGroundContactTime'] as num?)?.round();
    final vo = (json['avgVerticalOscillation'] as num?)?.toDouble();
    final stride = (json['avgStrideLength'] as num?)?.toDouble();
    if (gct != null || vo != null || stride != null) {
      final leftBal = (json['avgGroundContactBalance'] as num?)?.toDouble() ?? 50.0;
      runningDynamics = RunningDynamics(
        groundContactTimeMs: gct ?? 0,
        leftBalancePercent: leftBal,
        rightBalancePercent: double.parse((100.0 - leftBal).toStringAsFixed(1)),
        verticalOscillationCm: vo != null ? double.parse((vo / 10.0).toStringAsFixed(1)) : 0.0,
        strideLengthM: stride != null ? double.parse((stride / 100.0).toStringAsFixed(2)) : 0.0,
        runningPowerWatts: avgPower ?? 0,
        verticalRatioPercent: (json['avgVerticalRatio'] as num?)?.toDouble() ?? 0.0,
      );
    }

    return Activity(
      id: activityId,
      title: title,
      description: description,
      discipline: discipline,
      timestamp: timestamp,
      formattedDate: formattedDate,
      location: location,
      deviceHardware: 'Garmin Connect',
      sensorChain: typeKey.isNotEmpty ? typeKey.replaceAll('_', ' ') : 'Garmin Activity',
      distanceKm: distanceKm,
      durationSeconds: durationSec,
      movingTime: formatDurationSeconds(movingSec),
      elapsedTime: formatDurationSeconds(durationSec),
      avgSpeedOrPace: avgSpeedOrPace,
      maxSpeedOrPace: maxSpeedOrPace,
      avgHr: avgHr,
      maxHr: maxHr,
      elevationGainM: elevGain,
      elevationLossM: elevLoss,
      avgPowerW: avgPower,
      normPowerW: normPower,
      maxPowerW: maxPower,
      variabilityIndex: (avgPower != null && avgPower > 0 && normPower != null)
          ? double.parse((normPower / avgPower).toStringAsFixed(2))
          : null,
      intensityFactor: intensityFactor,
      tss: tss,
      calories: calories,
      avgCadence: avgCadence,
      maxCadence: maxCadence,
      startLatitude: (json['startLatitude'] as num?)?.toDouble(),
      startLongitude: (json['startLongitude'] as num?)?.toDouble(),
      runningDynamics: runningDynamics,
      swolf: swolf,
    );
  }

  static SportDiscipline mapGarminSportType(String typeKey) {
    if (typeKey.contains('swim')) return SportDiscipline.swim;
    if (typeKey.contains('indoor_cycling') ||
        typeKey.contains('virtual_ride') ||
        typeKey.contains('indoor_bike')) {
      return SportDiscipline.indoorBike;
    }
    if (typeKey.contains('cycl') || typeKey.contains('bik')) return SportDiscipline.bike;
    if (typeKey.contains('strength') ||
        typeKey.contains('fitness_equipment') ||
        typeKey.contains('weight') ||
        typeKey.contains('hiit') ||
        typeKey.contains('yoga') ||
        typeKey.contains('pilates') ||
        typeKey.contains('crossfit')) {
      return SportDiscipline.strength;
    }
    return SportDiscipline.run;
  }

  static String formatDurationSeconds(double seconds) {
    final total = seconds.round().clamp(0, 86400 * 10);
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  static String formatSpeedAsPace(double speedMps) {
    if (speedMps <= 0.01) return '—';
    final secPerKm = (1000.0 / speedMps).round();
    final min = secPerKm ~/ 60;
    final sec = secPerKm % 60;
    return '$min:${sec.toString().padLeft(2, '0')} /km';
  }

  static String formatMetricForDiscipline(SportDiscipline discipline, double speedMps) {
    if (speedMps <= 0.01) return '—';
    switch (discipline) {
      case SportDiscipline.bike:
      case SportDiscipline.indoorBike:
        final kmh = speedMps * 3.6;
        return '${kmh.toStringAsFixed(1)} km/h';
      case SportDiscipline.swim:
        final secPer100m = (100.0 / speedMps).round();
        final min = secPer100m ~/ 60;
        final sec = secPer100m % 60;
        return '$min:${sec.toString().padLeft(2, '0')} /100m';
      case SportDiscipline.run:
        return formatSpeedAsPace(speedMps);
      case SportDiscipline.strength:
        return '—';
    }
  }
}

/// Computes PMC (CTL/ATL/TSB) and ACWR from real Garmin activities.
class TrainingLoadCalculator {
  static ({
    List<PmcDataPoint> pmcSeries,
    double? ctl,
    double? atl,
    double? tsb,
    double? acwr,
    String? acwrStatus,
  }) computeFromActivities(List<Activity> activities, {int days = 42, DateTime? now}) {
    if (activities.isEmpty) {
      return (
        pmcSeries: const [],
        ctl: null,
        atl: null,
        tsb: null,
        acwr: null,
        acwrStatus: null,
      );
    }

    final today = now ?? DateTime.now();
    final endDay = DateTime(today.year, today.month, today.day);

    final dailyLoad = <DateTime, double>{};
    DateTime? earliestActivityDay;
    for (final act in activities) {
      final d = DateTime(act.timestamp.year, act.timestamp.month, act.timestamp.day);
      if (d.isAfter(endDay)) continue;
      if (earliestActivityDay == null || d.isBefore(earliestActivityDay)) {
        earliestActivityDay = d;
      }
      // Use Garmin TSS / training load if present; otherwise estimate from duration (hours * 50)
      final load = act.tss ?? ((act.durationSeconds / 3600.0) * 50.0);
      dailyLoad[d] = (dailyLoad[d] ?? 0.0) + load;
    }

    // Start from the earliest synced activity (up to 730 days back) so CTL/ATL warm up
    // across full history and 12W/6M/1Y/ALL windows have complete data.
    final minStartDay = endDay.subtract(Duration(days: days - 1));
    final maxHistoryStart = endDay.subtract(const Duration(days: 729));
    DateTime startDay = minStartDay;
    if (earliestActivityDay != null && earliestActivityDay.isBefore(startDay)) {
      startDay = earliestActivityDay.isBefore(maxHistoryStart)
          ? maxHistoryStart
          : earliestActivityDay;
    }
    final totalDays = endDay.difference(startDay).inDays + 1;

    double ctl = 0.0;
    double atl = 0.0;
    final series = <PmcDataPoint>[];

    for (int i = 0; i < totalDays; i++) {
      final day = startDay.add(Duration(days: i));
      final tss = dailyLoad[day] ?? 0.0;
      ctl = ctl + (tss - ctl) / 42.0;
      atl = atl + (tss - atl) / 7.0;
      final tsb = ctl - atl;
      series.add(
        PmcDataPoint(
          date: day,
          ctl: double.parse(ctl.toStringAsFixed(1)),
          atl: double.parse(atl.toStringAsFixed(1)),
          tsb: double.parse(tsb.toStringAsFixed(1)),
          dailyTss: double.parse(tss.toStringAsFixed(1)),
        ),
      );
    }

    final latest = series.last;
    final double? acwr = latest.ctl > 0.5
        ? double.parse((latest.atl / latest.ctl).toStringAsFixed(2))
        : null;

    String? status;
    if (acwr != null) {
      if (acwr < 0.8) {
        status = 'Recovery';
      } else if (acwr <= 1.3) {
        status = 'Optimal';
      } else if (acwr <= 1.5) {
        status = 'High Load';
      } else {
        status = 'Overreaching';
      }
    }

    return (
      pmcSeries: series,
      ctl: latest.ctl,
      atl: latest.atl,
      tsb: latest.tsb,
      acwr: acwr,
      acwrStatus: status,
    );
  }
}
