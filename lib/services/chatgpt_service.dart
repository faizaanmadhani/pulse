import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../models/activity.dart';
import '../models/training_plan.dart';
import '../utils/athlete_context_builder.dart';
import '../utils/unit_formatter.dart';
import '../utils/workout_compliance_matcher.dart';
import 'chatgpt_auth_store.dart';

class ChatGptAuthException implements Exception {
  final String message;

  const ChatGptAuthException(this.message);

  @override
  String toString() => 'ChatGptAuthException: $message';
}

class ChatGptUnauthorizedException extends ChatGptAuthException {
  const ChatGptUnauthorizedException([
    super.message = 'ChatGPT session expired (HTTP 401). Please sign in again.',
  ]);
}

class ChatGptApiException implements Exception {
  final int statusCode;
  final String message;
  final String? errorCode;
  final bool isRefusal;

  const ChatGptApiException(
    this.statusCode,
    this.message, {
    this.errorCode,
    this.isRefusal = false,
  });

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => 'ChatGptApiException($statusCode): $message';
}

class ChatGptService {
  static const String authorizeHost = 'auth.openai.com';
  static const String authorizePath = '/api/accounts/authorize';
  static const String authorizeEndpoint =
      'https://auth.openai.com/api/accounts/authorize';
  static const String tokenEndpoint =
      'https://auth.openai.com/api/accounts/oauth/token';
  static const String responsesEndpoint = 'https://api.openai.com/v1/responses';
  static const String defaultScope =
      'openid profile email offline_access chatgpt.tokens.use.direct';
  static const int defaultCallbackPort = 1455;
  static const String defaultModel = 'gpt-4o';
  static const Duration _httpTimeout = Duration(seconds: 90);

  static const String _pkceCharset =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
  static final math.Random _random = math.Random.secure();

  final http.Client _client;
  final bool _ownsClient;
  final String _defaultModel;

  ChatGptService({
    http.Client? client,
    String model = defaultModel,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _defaultModel = model.trim().isNotEmpty ? model.trim() : defaultModel;

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }

  // ---------------------------------------------------------------------------
  // OAuth 2.0 + PKCE Helpers (No API Key Path)
  // ---------------------------------------------------------------------------

  /// Generates an RFC 7636 §4.1 cryptographically random `code_verifier`.
  static String generateCodeVerifier({int length = 64}) {
    if (length < 43 || length > 128) {
      throw ArgumentError.value(
        length,
        'length',
        'PKCE code_verifier length must be between 43 and 128 characters.',
      );
    }
    return List<String>.generate(
      length,
      (_) => _pkceCharset[_random.nextInt(_pkceCharset.length)],
    ).join();
  }

  /// Computes the RFC 7636 S256 `code_challenge` for [verifier].
  static String computeCodeChallengeS256(String verifier) {
    if (verifier.isEmpty) {
      throw ArgumentError.value(
        verifier,
        'verifier',
        'Code verifier cannot be empty.',
      );
    }
    final digest = sha256.convert(utf8.encode(verifier));
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  /// Generates a URL-safe cryptographically random OAuth `state` token.
  static String generateState() {
    final bytes = List<int>.generate(24, (_) => _random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  /// Defensively decodes the payload claims of an OIDC JWT `id_token`.
  /// Never throws on malformed or non-JWT inputs (returns `{}`).
  static Map<String, dynamic> parseIdTokenClaims(String idToken) {
    final trimmed = idToken.trim();
    if (trimmed.isEmpty) return const {};

    final parts = trimmed.split('.');
    if (parts.length < 2 || parts.length > 3 || parts[1].isEmpty) {
      return const {};
    }

    try {
      final normalized = base64Url.normalize(parts[1]);
      final jsonStr = utf8.decode(base64Url.decode(normalized));
      final decoded = jsonDecode(jsonStr);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return const {};
    } catch (_) {
      return const {};
    }
  }

  static ({String? userName, String? userEmail, String? planTier})
      _extractClaimsMetadata(Map<String, dynamic> claims) {
    String? nonEmpty(dynamic value) {
      if (value is! String) return null;
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    final email = nonEmpty(claims['email']);

    final given = nonEmpty(claims['given_name']) ?? '';
    final family = nonEmpty(claims['family_name']) ?? '';
    final combinedName = '$given $family'.trim();
    final name = nonEmpty(claims['name']) ??
        (combinedName.isNotEmpty ? combinedName : null) ??
        nonEmpty(claims['preferred_username']) ??
        nonEmpty(claims['nickname']);

    final authNs = claims['https://api.openai.com/auth'];
    final authMap = authNs is Map ? authNs : null;
    final planTier = nonEmpty(authMap?['chatgpt_plan_type']) ??
        nonEmpty(authMap?['plan_type']) ??
        nonEmpty(claims['chatgpt_plan_type']) ??
        nonEmpty(claims['plan_tier']) ??
        nonEmpty(claims['planTier']) ??
        nonEmpty(claims['plan_type']);

    return (userName: name, userEmail: email, planTier: planTier);
  }

  /// Builds the `https://auth.openai.com/api/accounts/authorize` OAuth PKCE URI.
  Uri buildAuthorizeUrl({
    required String clientId,
    required String redirectUri,
    required String codeChallenge,
    required String state,
    String scope = defaultScope,
  }) {
    final trimmedClientId = clientId.trim();
    final trimmedRedirectUri = redirectUri.trim();
    final trimmedChallenge = codeChallenge.trim();
    final trimmedState = state.trim();
    final trimmedScope = scope.trim();

    if (trimmedClientId.isEmpty) {
      throw const ChatGptAuthException('ChatGPT OAuth Client ID is required.');
    }
    if (trimmedRedirectUri.isEmpty) {
      throw const ChatGptAuthException('OAuth redirect URI is required.');
    }
    if (trimmedChallenge.isEmpty) {
      throw const ChatGptAuthException('PKCE code_challenge is required.');
    }
    if (trimmedState.isEmpty) {
      throw const ChatGptAuthException('OAuth state is required.');
    }
    if (trimmedScope.isEmpty) {
      throw const ChatGptAuthException('OAuth scope is required.');
    }

    return Uri.https(authorizeHost, authorizePath, {
      'response_type': 'code',
      'client_id': trimmedClientId,
      'redirect_uri': trimmedRedirectUri,
      'scope': trimmedScope,
      'code_challenge': trimmedChallenge,
      'code_challenge_method': 'S256',
      'state': trimmedState,
    });
  }

  /// Starts a loopback HTTP server on `127.0.0.1:[port]` and waits for the
  /// OAuth callback at `/callback?code=...&state=...`.
  ///
  /// Supports `port: 0` for ephemeral port allocation in tests and cleans up
  /// the server, stream subscription, and timer in a `finally` block.
  Future<String> waitForOAuthCode({
    int port = defaultCallbackPort,
    required String expectedState,
    Duration timeout = const Duration(minutes: 3),
    Future<void> Function(String redirectUri)? onServerReady,
  }) async {
    final trimmedExpectedState = expectedState.trim();
    if (trimmedExpectedState.isEmpty) {
      throw const ChatGptAuthException(
        'Expected OAuth state is required before listening for callback.',
      );
    }

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    final actualPort = server.port;
    final redirectUri = 'http://127.0.0.1:$actualPort/callback';
    final completer = Completer<String>();
    StreamSubscription<HttpRequest>? subscription;
    Timer? timer;
    var closed = false;

    Future<void> shutdown() async {
      if (closed) return;
      closed = true;
      timer?.cancel();
      timer = null;
      await subscription?.cancel();
      subscription = null;
      await server.close(force: true);
    }

    try {
      subscription = server.listen(
        (HttpRequest request) async {
          if (request.uri.path != '/callback') {
            request.response.statusCode = HttpStatus.notFound;
            await request.response.close();
            return;
          }

          final error = request.uri.queryParameters['error'];
          final errorDescription =
              request.uri.queryParameters['error_description'];
          final state = request.uri.queryParameters['state'];
          final code = request.uri.queryParameters['code'];

          if (error != null && error.trim().isNotEmpty) {
            final detail = (errorDescription != null &&
                    errorDescription.trim().isNotEmpty)
                ? errorDescription.trim()
                : error.trim();
            request.response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.html
              ..write(_callbackHtml(
                title: 'ChatGPT Sign-In Cancelled',
                body:
                    'Authorization was cancelled ($detail). You can close this tab and return to Pulse Training.',
              ));
            await request.response.close();
            if (!completer.isCompleted) {
              completer.completeError(
                ChatGptAuthException('ChatGPT authorization failed: $detail'),
              );
            }
            return;
          }

          if (state == null || state.trim() != trimmedExpectedState) {
            request.response
              ..statusCode = HttpStatus.badRequest
              ..headers.contentType = ContentType.html
              ..write(_callbackHtml(
                title: 'Invalid OAuth State',
                body:
                    'The sign-in state did not match this session. Please close this tab and retry from Pulse Training.',
              ));
            await request.response.close();
            if (!completer.isCompleted) {
              completer.completeError(
                const ChatGptAuthException(
                  'OAuth state mismatch. Please try signing in again.',
                ),
              );
            }
            return;
          }

          if (code == null || code.trim().isEmpty) {
            request.response
              ..statusCode = HttpStatus.badRequest
              ..headers.contentType = ContentType.html
              ..write(_callbackHtml(
                title: 'Missing Authorization Code',
                body:
                    'ChatGPT did not return an authorization code. Please try again from Pulse Training.',
              ));
            await request.response.close();
            if (!completer.isCompleted) {
              completer.completeError(
                const ChatGptAuthException(
                  'Callback missing authorization code.',
                ),
              );
            }
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
        },
        onError: (Object err, StackTrace st) {
          if (!completer.isCompleted) {
            completer.completeError(err, st);
          }
        },
      );

      timer = Timer(timeout, () {
        if (!completer.isCompleted) {
          completer.completeError(
            const ChatGptAuthException(
              'Timed out waiting for ChatGPT OAuth callback.',
            ),
          );
        }
      });

      final resultFuture = completer.future..ignore();

      if (onServerReady != null) {
        try {
          await onServerReady(redirectUri);
        } catch (err, st) {
          if (!completer.isCompleted) {
            completer.completeError(err, st);
          }
        }
      }

      return await resultFuture;
    } finally {
      await shutdown();
    }
  }

  /// Parses either a raw authorization code or a full pasted OAuth callback URL
  /// (validating `error` and `state` when present).
  static String parseOAuthCallbackInput(
    String input, {
    String? expectedState,
  }) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw const ChatGptAuthException(
        'Enter an authorization code or callback URL.',
      );
    }

    final lower = trimmed.toLowerCase();
    final hasHttpScheme =
        lower.startsWith('http://') || lower.startsWith('https://');
    final looksLikeUrlOrQuery = hasHttpScheme ||
        trimmed.contains('?') ||
        trimmed.contains('code=') ||
        trimmed.contains('error=');

    if (looksLikeUrlOrQuery) {
      final Uri? uri;
      if (hasHttpScheme) {
        uri = Uri.tryParse(trimmed);
      } else if (trimmed.contains('?')) {
        final qIndex = trimmed.indexOf('?');
        final query = trimmed.substring(qIndex + 1);
        uri = Uri.tryParse('http://127.0.0.1/callback?$query');
      } else {
        uri = Uri.tryParse('http://127.0.0.1/callback?$trimmed');
      }

      if (uri == null) {
        throw const ChatGptAuthException(
          'Could not parse the pasted callback URL.',
        );
      }

      final error = uri.queryParameters['error'];
      final errorDescription = uri.queryParameters['error_description'];
      if (error != null && error.trim().isNotEmpty) {
        final detail =
            (errorDescription != null && errorDescription.trim().isNotEmpty)
                ? errorDescription.trim()
                : error.trim();
        throw ChatGptAuthException('ChatGPT authorization failed: $detail');
      }

      final trimmedExpectedState = expectedState?.trim();
      if (trimmedExpectedState != null && trimmedExpectedState.isNotEmpty) {
        final returnedState = uri.queryParameters['state']?.trim() ?? '';
        if (returnedState.isEmpty || returnedState != trimmedExpectedState) {
          throw const ChatGptAuthException(
            'OAuth state mismatch or missing state in pasted callback URL.',
          );
        }
      }

      final code = uri.queryParameters['code']?.trim() ?? '';
      if (code.isEmpty) {
        throw const ChatGptAuthException(
          'Callback URL is missing an authorization code.',
        );
      }
      return code;
    }

    if (RegExp(r'\s').hasMatch(trimmed)) {
      throw const ChatGptAuthException(
        'Authorization code contains invalid whitespace.',
      );
    }
    return trimmed;
  }

  /// Exchanges a PKCE authorization [code] for a [ChatGptSession] (no client_secret).
  Future<ChatGptSession> exchangeAuthorizationCode({
    required String clientId,
    required String code,
    required String codeVerifier,
    required String redirectUri,
  }) async {
    final trimmedClientId = clientId.trim();
    final trimmedCode = code.trim();
    final trimmedVerifier = codeVerifier.trim();
    final trimmedRedirectUri = redirectUri.trim();

    if (trimmedClientId.isEmpty ||
        trimmedCode.isEmpty ||
        trimmedVerifier.isEmpty ||
        trimmedRedirectUri.isEmpty) {
      throw const ChatGptAuthException(
        'Client ID, authorization code, PKCE verifier, and redirect URI are required.',
      );
    }

    final response = await _client
        .post(
          Uri.parse(tokenEndpoint),
          headers: const {'Accept': 'application/json'},
          body: {
            'grant_type': 'authorization_code',
            'client_id': trimmedClientId,
            'code': trimmedCode,
            'code_verifier': trimmedVerifier,
            'redirect_uri': trimmedRedirectUri,
          },
        )
        .timeout(_httpTimeout);

    final body = _decodeJsonMap(response.body);
    if (response.statusCode != 200) {
      throw ChatGptAuthException(
        _extractOAuthErrorMessage(
          body,
          response.statusCode,
          'Token exchange failed',
        ),
      );
    }

    if (body['error'] != null) {
      throw ChatGptAuthException(
        _extractOAuthErrorMessage(
          body,
          response.statusCode,
          'Token exchange failed',
        ),
      );
    }

    final accessToken = (body['access_token'] as String?)?.trim() ?? '';
    if (accessToken.isEmpty) {
      throw const ChatGptAuthException(
        'ChatGPT OAuth response was missing an access token.',
      );
    }

    final refreshTokenRaw = (body['refresh_token'] as String?)?.trim();
    final idTokenRaw = (body['id_token'] as String?)?.trim();
    final expiresAt = _computeExpiresAt(body);

    final claims = idTokenRaw != null && idTokenRaw.isNotEmpty
        ? parseIdTokenClaims(idTokenRaw)
        : const <String, dynamic>{};
    final meta = _extractClaimsMetadata(claims);

    return ChatGptSession(
      clientId: trimmedClientId,
      accessToken: accessToken,
      refreshToken: (refreshTokenRaw != null && refreshTokenRaw.isNotEmpty)
          ? refreshTokenRaw
          : null,
      idToken:
          (idTokenRaw != null && idTokenRaw.isNotEmpty) ? idTokenRaw : null,
      expiresAt: expiresAt,
      userName: meta.userName,
      userEmail: meta.userEmail,
      planTier: meta.planTier,
    );
  }

  /// Refreshes an existing [ChatGptSession] using its PKCE `refresh_token`.
  Future<ChatGptSession> refreshToken(ChatGptSession session) async {
    if (!session.canRefresh) {
      throw const ChatGptAuthException(
        'Cannot refresh ChatGPT token: missing refresh token or client ID.',
      );
    }

    final response = await _client
        .post(
          Uri.parse(tokenEndpoint),
          headers: const {'Accept': 'application/json'},
          body: {
            'grant_type': 'refresh_token',
            'client_id': session.clientId.trim(),
            'refresh_token': session.refreshToken!.trim(),
          },
        )
        .timeout(_httpTimeout);

    final body = _decodeJsonMap(response.body);
    if (response.statusCode != 200) {
      throw ChatGptAuthException(
        _extractOAuthErrorMessage(
          body,
          response.statusCode,
          'Token refresh failed',
        ),
      );
    }

    if (body['error'] != null) {
      throw ChatGptAuthException(
        _extractOAuthErrorMessage(
          body,
          response.statusCode,
          'Token refresh failed',
        ),
      );
    }

    final accessToken = (body['access_token'] as String?)?.trim() ?? '';
    if (accessToken.isEmpty) {
      throw const ChatGptAuthException(
        'ChatGPT OAuth refresh response was missing an access token.',
      );
    }

    final returnedRefresh = (body['refresh_token'] as String?)?.trim();
    final nextRefreshToken =
        (returnedRefresh != null && returnedRefresh.isNotEmpty)
            ? returnedRefresh
            : session.refreshToken;

    final returnedIdToken = (body['id_token'] as String?)?.trim();
    final nextIdToken = (returnedIdToken != null && returnedIdToken.isNotEmpty)
        ? returnedIdToken
        : session.idToken;

    final claims = (returnedIdToken != null && returnedIdToken.isNotEmpty)
        ? parseIdTokenClaims(returnedIdToken)
        : const <String, dynamic>{};
    final meta = _extractClaimsMetadata(claims);

    return session.copyWith(
      accessToken: accessToken,
      refreshToken: nextRefreshToken,
      idToken: nextIdToken,
      expiresAt: _computeExpiresAt(body),
      userName: meta.userName ?? session.userName,
      userEmail: meta.userEmail ?? session.userEmail,
      planTier: meta.planTier ?? session.planTier,
    );
  }

  DateTime _computeExpiresAt(Map<String, dynamic> body) {
    final expiresAtEpoch = (body['expires_at'] as num?)?.toInt();
    if (expiresAtEpoch != null && expiresAtEpoch > 0) {
      return DateTime.fromMillisecondsSinceEpoch(
        expiresAtEpoch * 1000,
        isUtc: true,
      );
    }
    final expiresIn = (body['expires_in'] as num?)?.toInt();
    final seconds = (expiresIn != null && expiresIn > 0) ? expiresIn : 3600;
    return DateTime.now().toUtc().add(Duration(seconds: seconds));
  }

  Map<String, dynamic> _decodeJsonMap(String raw) {
    if (raw.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return const {};
    } catch (_) {
      return const {};
    }
  }

  String _extractOAuthErrorMessage(
    Map<String, dynamic> body,
    int statusCode,
    String fallback,
  ) {
    final desc = body['error_description']?.toString().trim();
    if (desc != null && desc.isNotEmpty) return '$desc (HTTP $statusCode)';
    final err = body['error'];
    if (err is Map) {
      final msg = err['message']?.toString().trim();
      if (msg != null && msg.isNotEmpty) return '$msg (HTTP $statusCode)';
    }
    if (err != null && err.toString().trim().isNotEmpty) {
      return '${err.toString().trim()} (HTTP $statusCode)';
    }
    final msg = body['message']?.toString().trim();
    if (msg != null && msg.isNotEmpty) return '$msg (HTTP $statusCode)';
    return '$fallback (HTTP $statusCode)';
  }

  // ---------------------------------------------------------------------------
  // OpenAI Responses API Coach & Plan Engine
  // ---------------------------------------------------------------------------

  /// Sends an interactive coaching turn to OpenAI Responses API grounded in
  /// sports science principles and the athlete's real telemetry context.
  Future<String> sendCoachMessage({
    required ChatGptSession session,
    required List<CoachMessage> history,
    required String userMessage,
    required AthleteContext athleteContext,
    TrainingPlanConfig? config,
    TrainingPlan? activePlan,
    UnitSystem unitSystem = UnitSystem.metric,
    String? model,
  }) async {
    final trimmedUser = userMessage.trim();
    if (trimmedUser.isEmpty) {
      throw const ChatGptApiException(400, 'Coach message cannot be empty.');
    }

    final instructions = _buildCoachInstructions(
      athleteContext: athleteContext,
      config: config,
      activePlan: activePlan,
      unitSystem: unitSystem,
    );

    final input = _buildCoachInput(history, trimmedUser);

    return _postResponses(
      session: session,
      instructions: instructions,
      input: input,
      model: model,
    );
  }

  /// Generates a structured multi-week triathlon training plan via OpenAI
  /// Responses API Structured Outputs and enforces all plan/brick invariants.
  Future<TrainingPlan> generateTrainingPlan({
    required ChatGptSession session,
    required TrainingPlanConfig config,
    required AthleteContext athleteContext,
    List<CoachMessage> coachHistory = const [],
    DateTime? startDate,
    int? totalWeeks,
    UnitSystem unitSystem = UnitSystem.metric,
    String? model,
  }) async {
    final effectiveStart = (startDate ?? athleteContext.asOfDate).toLocal();
    final startKey = PlannedWorkout.formatLocalDate(effectiveStart);
    final weeksCount = _resolveTotalWeeks(
      config: config,
      startDate: effectiveStart,
      explicitWeeks: totalWeeks,
    );

    final instructions = _buildPlanGenerationInstructions(
      athleteContext: athleteContext,
      config: config,
      startDateKey: startKey,
      weeksCount: weeksCount,
      unitSystem: unitSystem,
    );

    final input = <Map<String, dynamic>>[
      ..._historyToInputItems(coachHistory),
      {
        'role': 'user',
        'content':
            'Generate a complete $weeksCount-week structured triathlon training plan '
                'starting $startKey for "${config.raceName}" (${config.raceDistance}'
                '${config.raceDate.isNotEmpty ? ', race date ${config.raceDate}' : ''}) '
                'within ${config.weeklyHoursBudget.toStringAsFixed(1)} hrs/week. '
                'Output valid JSON matching the schema.',
      },
    ];

    final rawText = await _postResponses(
      session: session,
      instructions: instructions,
      input: input,
      textFormat: _trainingPlanJsonFormat(),
      model: model,
    );

    final decoded = _decodePlanJson(rawText);
    _validateRawPlanJson(decoded);
    _normalizeRawPlanJson(decoded);

    final parsed = TrainingPlan.fromJson(decoded);
    return _finalizePlan(parsed, config: config);
  }

  /// Adapts remaining future workouts in [existingPlan] based on athlete
  /// adherence, telemetry, and [userFeedback], while programmatically preserving
  /// all completed, skipped, and `< referenceDate` workouts verbatim.
  Future<TrainingPlan> adaptTrainingPlan({
    required ChatGptSession session,
    required TrainingPlan existingPlan,
    required AthleteContext athleteContext,
    String? userFeedback,
    DateTime? referenceDate,
    UnitSystem unitSystem = UnitSystem.metric,
    String? model,
  }) async {
    final effectiveRef = (referenceDate ?? athleteContext.asOfDate).toLocal();
    final refKey = PlannedWorkout.formatLocalDate(effectiveRef);
    final trimmedFeedback = userFeedback?.trim() ?? '';

    final instructions = _buildPlanAdaptationInstructions(
      athleteContext: athleteContext,
      existingPlan: existingPlan,
      referenceDateKey: refKey,
      unitSystem: unitSystem,
    );

    final userPrompt = StringBuffer()
      ..writeln(
        'Adapt the remaining training plan from $refKey onward while keeping '
        'all workouts before $refKey and all completed or skipped workouts intact.',
      );
    if (trimmedFeedback.isNotEmpty) {
      userPrompt.writeln('Athlete feedback / request: $trimmedFeedback');
    }
    userPrompt.writeln('Current plan JSON:');
    userPrompt.writeln(jsonEncode(existingPlan.toJson()));

    final rawText = await _postResponses(
      session: session,
      instructions: instructions,
      input: [
        {
          'role': 'user',
          'content': userPrompt.toString(),
        },
      ],
      textFormat: _trainingPlanJsonFormat(),
      model: model,
    );

    final decoded = _decodePlanJson(rawText);
    _validateRawPlanJson(decoded);
    _normalizeRawPlanJson(decoded);

    final parsed = TrainingPlan.fromJson(decoded);
    final finalized = _finalizePlan(parsed, config: existingPlan.config);

    return _preservePastAndLockedWorkouts(
      existingPlan: existingPlan,
      adaptedPlan: finalized,
      referenceDateKey: refKey,
    );
  }

  /// Builds a self-contained prompt the user can copy into ChatGPT (web/app)
  /// to generate a structured JSON training plan grounded in their Garmin data.
  String buildCopyablePlanPrompt({
    required AthleteContext athleteContext,
    required TrainingPlanConfig config,
    int? totalWeeks,
    DateTime? startDate,
    UnitSystem unitSystem = UnitSystem.metric,
    String? extraNotes,
  }) {
    final effectiveStart = (startDate ?? athleteContext.asOfDate).toLocal();
    final startKey = PlannedWorkout.formatLocalDate(effectiveStart);
    final weeksCount = _resolveTotalWeeks(
      config: config,
      startDate: effectiveStart,
      explicitWeeks: totalWeeks,
    );

    final instructions = _buildPlanGenerationInstructions(
      athleteContext: athleteContext,
      config: config,
      startDateKey: startKey,
      weeksCount: weeksCount,
      unitSystem: unitSystem,
    );

    final buf = StringBuffer()
      ..writeln(instructions.trim())
      ..writeln()
      ..writeln('REQUEST:')
      ..writeln(
        'Generate a complete $weeksCount-week structured triathlon training plan '
        'starting $startKey for "${config.raceName}" (${config.raceDistance}'
        '${config.raceDate.isNotEmpty ? ', race date ${config.raceDate}' : ''}) '
        'within ${config.weeklyHoursBudget.toStringAsFixed(1)} hrs/week.',
      );
    final notes = extraNotes?.trim() ?? '';
    if (notes.isNotEmpty) {
      buf.writeln('Additional athlete notes: $notes');
    }
    buf
      ..writeln()
      ..writeln(
        'IMPORTANT EXPORT FORMAT: Reply with ONLY a single ```json ... ``` code block '
        'conforming strictly to this JSON schema (no extra commentary outside the code block):',
      )
      ..writeln(jsonEncode(trainingPlanJsonSchema()));
    return buf.toString();
  }

  /// Builds a self-contained prompt the user can copy into ChatGPT (web/app)
  /// to adapt their remaining active training plan.
  String buildCopyableAdaptPrompt({
    required AthleteContext athleteContext,
    required TrainingPlan existingPlan,
    String? userFeedback,
    DateTime? referenceDate,
    UnitSystem unitSystem = UnitSystem.metric,
  }) {
    final effectiveRef = (referenceDate ?? athleteContext.asOfDate).toLocal();
    final refKey = PlannedWorkout.formatLocalDate(effectiveRef);
    final trimmedFeedback = userFeedback?.trim() ?? '';

    final instructions = _buildPlanAdaptationInstructions(
      athleteContext: athleteContext,
      existingPlan: existingPlan,
      referenceDateKey: refKey,
      unitSystem: unitSystem,
    );

    final buf = StringBuffer()
      ..writeln(instructions.trim())
      ..writeln()
      ..writeln(
        'Adapt the remaining training plan from $refKey onward while keeping '
        'all workouts before $refKey and all completed or skipped workouts intact.',
      );
    if (trimmedFeedback.isNotEmpty) {
      buf.writeln('Athlete feedback / request: $trimmedFeedback');
    }
    buf
      ..writeln()
      ..writeln('Current plan JSON:')
      ..writeln(jsonEncode(existingPlan.toJson()))
      ..writeln()
      ..writeln(
        'IMPORTANT EXPORT FORMAT: Reply with ONLY a single ```json ... ``` code block '
        'conforming strictly to this JSON schema (no extra commentary outside the code block):',
      )
      ..writeln(jsonEncode(trainingPlanJsonSchema()));
    return buf.toString();
  }

  /// Parses, validates, normalizes, and finalizes a training plan JSON string
  /// pasted or imported from ChatGPT web/app.
  TrainingPlan parseImportedPlan(
    String rawText, {
    required TrainingPlanConfig config,
    TrainingPlan? existingPlan,
    DateTime? referenceDate,
  }) {
    if (rawText.trim().isEmpty) {
      throw const ChatGptApiException(
        400,
        'Paste the JSON training plan from ChatGPT before importing.',
      );
    }
    final decoded = _decodePlanJson(rawText);
    _validateRawPlanJson(decoded);
    _normalizeRawPlanJson(decoded);

    final parsed = TrainingPlan.fromJson(decoded);
    final finalized = _finalizePlan(
      parsed,
      config: existingPlan?.config ?? config,
    );

    if (existingPlan != null) {
      final effectiveRef = (referenceDate ?? DateTime.now()).toLocal();
      final refKey = PlannedWorkout.formatLocalDate(effectiveRef);
      return _preservePastAndLockedWorkouts(
        existingPlan: existingPlan,
        adaptedPlan: finalized,
        referenceDateKey: refKey,
      );
    }
    return finalized;
  }

  /// Returns the 5-level-safe OpenAI Structured Outputs JSON Schema for a
  /// triathlon `TrainingPlan`.
  static Map<String, dynamic> trainingPlanJsonSchema() {
    return {
      'type': 'object',
      'additionalProperties': false,
      'required': ['name', 'coachOverview', 'weeks'],
      'properties': {
        'name': {'type': 'string'},
        'coachOverview': {'type': 'string'},
        'weeks': {
          'type': 'array',
          'items': {r'$ref': r'#/$defs/TrainingWeek'},
        },
      },
      r'$defs': {
        'TrainingWeek': {
          'type': 'object',
          'additionalProperties': false,
          'required': [
            'weekNumber',
            'startDate',
            'phaseName',
            'focusSummary',
            'targetHours',
            'targetTss',
            'workouts',
          ],
          'properties': {
            'weekNumber': {'type': 'integer'},
            'startDate': {'type': 'string'},
            'phaseName': {'type': 'string'},
            'focusSummary': {'type': 'string'},
            'targetHours': {'type': 'number'},
            'targetTss': {'type': 'integer'},
            'workouts': {
              'type': 'array',
              'items': {r'$ref': r'#/$defs/PlannedWorkout'},
            },
          },
        },
        'PlannedWorkout': {
          'type': 'object',
          'additionalProperties': false,
          'required': [
            'id',
            'date',
            'title',
            'discipline',
            'archetype',
            'estimatedDurationMinutes',
            'estimatedDistanceKm',
            'estimatedTss',
            'coachNotes',
            'rationale',
            'blocks',
            'zwiftPrescription',
            'brickRunLeg',
          ],
          'properties': {
            'id': {'type': 'string'},
            'date': {'type': 'string'},
            'title': {'type': 'string'},
            'discipline': {
              'type': 'string',
              'enum': ['swim', 'bike', 'run', 'strength', 'indoorBike'],
            },
            'archetype': {
              'type': 'string',
              'enum': [
                'intervals',
                'threshold',
                'easy',
                'long',
                'zwiftRide',
                'brick',
                'strength',
                'rest',
              ],
            },
            'estimatedDurationMinutes': {'type': 'integer'},
            'estimatedDistanceKm': {
              'type': ['number', 'null'],
            },
            'estimatedTss': {
              'type': ['number', 'null'],
            },
            'coachNotes': {
              'type': ['string', 'null'],
            },
            'rationale': {
              'type': ['string', 'null'],
            },
            'blocks': {
              'type': 'array',
              'items': {r'$ref': r'#/$defs/WorkoutBlock'},
            },
            'zwiftPrescription': {
              'anyOf': [
                {r'$ref': r'#/$defs/ZwiftPrescription'},
                {'type': 'null'},
              ],
            },
            'brickRunLeg': {
              'anyOf': [
                {r'$ref': r'#/$defs/BrickRunLeg'},
                {'type': 'null'},
              ],
            },
          },
        },
        'WorkoutBlock': {
          'type': 'object',
          'additionalProperties': false,
          'required': ['repeatCount', 'step', 'steps'],
          'properties': {
            'repeatCount': {'type': 'integer'},
            'step': {
              'anyOf': [
                {r'$ref': r'#/$defs/WorkoutStep'},
                {'type': 'null'},
              ],
            },
            'steps': {
              'type': 'array',
              'items': {r'$ref': r'#/$defs/WorkoutStep'},
            },
          },
        },
        'ZwiftPrescription': {
          'type': 'object',
          'additionalProperties': false,
          'required': [
            'durationMinutes',
            'difficulty',
            'targetTss',
            'zwiftCategory',
            'suggestedSearchTerms',
            'cadenceFocus',
            'notes',
          ],
          'properties': {
            'durationMinutes': {'type': 'integer'},
            'difficulty': {'type': 'string'},
            'targetTss': {'type': 'integer'},
            'zwiftCategory': {'type': 'string'},
            'suggestedSearchTerms': {
              'type': 'array',
              'items': {'type': 'string'},
            },
            'cadenceFocus': {
              'type': ['string', 'null'],
            },
            'notes': {
              'type': ['string', 'null'],
            },
          },
        },
        'BrickRunLeg': {
          'type': 'object',
          'additionalProperties': false,
          'required': [
            'id',
            'title',
            'archetype',
            'estimatedDurationMinutes',
            'estimatedDistanceKm',
            'estimatedTss',
            'coachNotes',
            'rationale',
            'steps',
          ],
          'properties': {
            'id': {'type': 'string'},
            'title': {'type': 'string'},
            'archetype': {
              'type': 'string',
              'enum': ['intervals', 'threshold', 'easy', 'long'],
            },
            'estimatedDurationMinutes': {'type': 'integer'},
            'estimatedDistanceKm': {
              'type': ['number', 'null'],
            },
            'estimatedTss': {
              'type': ['number', 'null'],
            },
            'coachNotes': {
              'type': ['string', 'null'],
            },
            'rationale': {
              'type': ['string', 'null'],
            },
            'steps': {
              'type': 'array',
              'items': {r'$ref': r'#/$defs/WorkoutStep'},
            },
          },
        },
        'WorkoutStep': {
          'type': 'object',
          'additionalProperties': false,
          'required': [
            'kind',
            'endCondition',
            'endValue',
            'targetKind',
            'targetLow',
            'targetHigh',
            'notes',
            'strokeType',
          ],
          'properties': {
            'kind': {
              'type': 'string',
              'enum': [
                'warmup',
                'interval',
                'recovery',
                'cooldown',
                'rest',
                'steady',
              ],
            },
            'endCondition': {
              'type': 'string',
              'enum': ['time', 'distance', 'lapButton'],
            },
            'endValue': {
              'type': ['number', 'null'],
            },
            'targetKind': {
              'type': 'string',
              'enum': ['none', 'heartRateBpm', 'heartRateZone', 'paceMps'],
            },
            'targetLow': {
              'type': ['number', 'null'],
            },
            'targetHigh': {
              'type': ['number', 'null'],
            },
            'notes': {
              'type': ['string', 'null'],
            },
            'strokeType': {
              'type': ['string', 'null'],
            },
          },
        },
      },
    };
  }

  static Map<String, dynamic> _trainingPlanJsonFormat() => {
        'type': 'json_schema',
        'name': 'triathlon_training_plan',
        'strict': true,
        'schema': trainingPlanJsonSchema(),
      };

  Future<String> _postResponses({
    required ChatGptSession session,
    required String instructions,
    required List<Map<String, dynamic>> input,
    Map<String, dynamic>? textFormat,
    String? model,
  }) async {
    final accessToken = session.accessToken.trim();
    if (accessToken.isEmpty) {
      throw const ChatGptAuthException(
        'Missing ChatGPT OAuth access token. Please sign in with ChatGPT.',
      );
    }

    final resolvedModel =
        (model != null && model.trim().isNotEmpty) ? model.trim() : _defaultModel;

    final payload = <String, dynamic>{
      'model': resolvedModel,
      'instructions': instructions,
      'input': input,
      if (textFormat != null) 'text': {'format': textFormat},
    };

    final response = await _client
        .post(
          Uri.parse(responsesEndpoint),
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(payload),
        )
        .timeout(_httpTimeout);

    return _extractResponseText(response);
  }

  static String _extractResponseText(http.Response response) {
    Map<String, dynamic> body = const {};
    try {
      final decoded =
          response.body.trim().isEmpty ? null : jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        body = decoded;
      } else if (decoded is Map) {
        body = Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      body = const {};
    }

    String? extractErrorText() {
      final err = body['error'];
      if (err is Map) {
        final msg = err['message']?.toString().trim();
        if (msg != null && msg.isNotEmpty) return msg;
      } else if (err != null && err.toString().trim().isNotEmpty) {
        return err.toString().trim();
      }
      final topMsg = body['message']?.toString().trim();
      if (topMsg != null && topMsg.isNotEmpty) return topMsg;
      return null;
    }

    String? extractErrorCode() {
      final err = body['error'];
      if (err is Map) {
        final code = err['code']?.toString().trim();
        if (code != null && code.isNotEmpty) return code;
      }
      return null;
    }

    if (response.statusCode == 401) {
      final msg = extractErrorText();
      throw ChatGptUnauthorizedException(
        msg != null
            ? 'ChatGPT session expired (HTTP 401): $msg'
            : 'ChatGPT session expired (HTTP 401). Please sign in again.',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final msg = extractErrorText() ??
          'ChatGPT request failed (HTTP ${response.statusCode}).';
      throw ChatGptApiException(
        response.statusCode,
        msg,
        errorCode: extractErrorCode(),
      );
    }

    if (body['error'] != null) {
      final msg = extractErrorText() ?? 'ChatGPT returned an error payload.';
      throw ChatGptApiException(
        response.statusCode,
        msg,
        errorCode: extractErrorCode(),
      );
    }

    final status = body['status']?.toString().trim().toLowerCase();
    if (status == 'failed' || status == 'cancelled') {
      throw ChatGptApiException(
        response.statusCode,
        'ChatGPT response $status.',
        errorCode: extractErrorCode(),
      );
    }
    if (status == 'incomplete') {
      final details = body['incomplete_details'];
      final reason = (details is Map ? details['reason'] : null)
              ?.toString()
              .trim() ??
          'unknown';
      throw ChatGptApiException(
        response.statusCode,
        'ChatGPT returned an incomplete response ($reason).',
      );
    }

    final outputBuffer = StringBuffer();
    final output = body['output'];
    if (output is List) {
      // Check for refusals across all output items before returning any text.
      for (final item in output) {
        if (item is! Map) continue;
        if (item['type'] == 'refusal') {
          final refusal = item['refusal']?.toString().trim();
          throw ChatGptApiException(
            response.statusCode,
            (refusal != null && refusal.isNotEmpty)
                ? refusal
                : 'ChatGPT refused to fulfill this request.',
            isRefusal: true,
          );
        }
        final content = item['content'];
        if (content is! List) continue;
        for (final part in content) {
          if (part is! Map) continue;
          if (part['type'] == 'refusal' || part['refusal'] != null) {
            final refusal = part['refusal']?.toString().trim() ??
                part['text']?.toString().trim();
            throw ChatGptApiException(
              response.statusCode,
              (refusal != null && refusal.isNotEmpty)
                  ? refusal
                  : 'ChatGPT refused to fulfill this request.',
              isRefusal: true,
            );
          }
        }
      }

      for (final item in output) {
        if (item is! Map) continue;
        final content = item['content'];
        if (content is! List) continue;
        for (final part in content) {
          if (part is! Map) continue;
          final partType = part['type']?.toString();
          if (partType == 'output_text' || partType == 'text') {
            final rawText = part['text'];
            if (rawText is String && rawText.isNotEmpty) {
              outputBuffer.write(rawText);
            } else if (rawText is Map && rawText['value'] is String) {
              outputBuffer.write(rawText['value'] as String);
            }
          }
        }
      }
    }

    final fromOutput = outputBuffer.toString().trim();
    if (fromOutput.isNotEmpty) {
      return fromOutput;
    }

    final topLevelOutputText = body['output_text'];
    if (topLevelOutputText is String && topLevelOutputText.trim().isNotEmpty) {
      return topLevelOutputText.trim();
    }

    throw ChatGptApiException(
      response.statusCode,
      'ChatGPT returned an empty response.',
    );
  }

  static String _stripJsonCodeFences(String raw) {
    var trimmed = raw.trim();
    final fenceMatch = RegExp(
      r'```(?:json)?\s*\r?\n([\s\S]*?)```',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (fenceMatch != null) {
      return fenceMatch.group(1)!.trim();
    }
    if (trimmed.startsWith('```')) {
      final firstNewline = trimmed.indexOf('\n');
      if (firstNewline != -1) {
        trimmed = trimmed.substring(firstNewline + 1);
      } else {
        trimmed = trimmed.replaceFirst(RegExp(r'^```[a-zA-Z]*'), '');
      }
      if (trimmed.endsWith('```')) {
        trimmed = trimmed.substring(0, trimmed.length - 3);
      }
      trimmed = trimmed.trim();
    }
    if (!trimmed.startsWith('{')) {
      final start = trimmed.indexOf('{');
      final end = trimmed.lastIndexOf('}');
      if (start != -1 && end > start) {
        return trimmed.substring(start, end + 1).trim();
      }
    }
    return trimmed;
  }

  static Map<String, dynamic> _decodePlanJson(String rawText) {
    final cleaned = _stripJsonCodeFences(rawText);
    try {
      final decoded = jsonDecode(cleaned);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    throw const ChatGptApiException(
      200,
      'ChatGPT returned malformed JSON for the training plan.',
    );
  }

  static const Set<String> _runSwimAllowedArchetypeTokens = {
    'intervals',
    'interval',
    'vo2',
    'vo2max',
    'speed',
    'threshold',
    'tempo',
    'lt',
    'lactatethreshold',
    'easy',
    'recovery',
    'aerobic',
    'endurance',
    'long',
    'longrun',
    'longswim',
  };

  static const Set<String> _recognizedArchetypeTokens = {
    ..._runSwimAllowedArchetypeTokens,
    'longride',
    'zwiftride',
    'zwift',
    'cycling',
    'bike',
    'ride',
    'indoorbike',
    'brick',
    'bikerun',
    'strength',
    'rest',
    'restday',
    'off',
  };

  static String _normalizeToken(String raw) => raw
      .trim()
      .toLowerCase()
      .replaceAll('_', '')
      .replaceAll('-', '')
      .replaceAll('.', '')
      .replaceAll(' ', '');

  static bool _isValidRawArchetype(dynamic raw) {
    if (raw is! String) return false;
    final token = _normalizeToken(raw);
    return _recognizedArchetypeTokens.contains(token);
  }

  static void _validateRawPlanJson(Map<String, dynamic> rawPlan) {
    final weeks = rawPlan['weeks'];
    if (weeks is! List || weeks.isEmpty) {
      throw const ChatGptApiException(
        200,
        'Generated training plan contained no weeks.',
      );
    }

    for (final week in weeks) {
      if (week is! Map) {
        throw const ChatGptApiException(
          200,
          'Generated training plan contained an invalid week entry.',
        );
      }
      final workouts = week['workouts'];
      if (workouts is! List) continue;
      for (final workout in workouts) {
        if (workout is! Map) continue;
        final rawArch = workout['archetype'];
        if (!_isValidRawArchetype(rawArch)) {
          throw ChatGptApiException(
            200,
            'Unrecognized workout archetype "$rawArch" in generated plan.',
          );
        }

        final archToken = _normalizeToken(rawArch as String);
        final rawDisc = workout['discipline'];
        final discToken =
            rawDisc is String ? _normalizeToken(rawDisc) : '';
        final isRunOrSwim = discToken == 'run' ||
            discToken == 'running' ||
            discToken == 'treadmill' ||
            discToken == 'trailrun' ||
            discToken == 'swim' ||
            discToken == 'swimming' ||
            discToken == 'poolswim' ||
            discToken == 'openwater' ||
            discToken == 'openwaterswim';

        if (isRunOrSwim && !_runSwimAllowedArchetypeTokens.contains(archToken)) {
          throw ChatGptApiException(
            200,
            'Incompatible workout archetype "$rawArch" for $rawDisc workout.',
          );
        }

        final rawLeg = workout['brickRunLeg'];
        if (rawLeg is Map && rawLeg.containsKey('archetype')) {
          final legArch = rawLeg['archetype'];
          if (!_isValidRawArchetype(legArch)) {
            throw ChatGptApiException(
              200,
              'Unrecognized brick run-leg archetype "$legArch" in generated plan.',
            );
          }
          final legArchToken = _normalizeToken(legArch as String);
          if (!_runSwimAllowedArchetypeTokens.contains(legArchToken)) {
            throw ChatGptApiException(
              200,
              'Incompatible brick run-leg archetype "$legArch" for run leg.',
            );
          }
        }
      }
    }
  }

  static void _normalizeRawPlanJson(Map<String, dynamic> rawPlan) {
    final weeks = rawPlan['weeks'];
    if (weeks is! List) return;

    for (final week in weeks) {
      if (week is! Map) continue;
      final workouts = week['workouts'];
      if (workouts is! List) continue;
      for (final workout in workouts) {
        if (workout is! Map) continue;
        final leg = workout['brickRunLeg'];
        if (leg is Map) {
          final existingBlocks = leg['blocks'];
          final rawSteps = leg['steps'];
          if ((existingBlocks is! List || existingBlocks.isEmpty) &&
              rawSteps is List) {
            leg['blocks'] = [
              for (final step in rawSteps)
                if (step is Map)
                  {
                    'repeatCount': 1,
                    'step': step,
                    'steps': const [],
                  },
            ];
          }
        }
      }
    }
  }

  static TrainingPlan _finalizePlan(
    TrainingPlan plan, {
    required TrainingPlanConfig config,
  }) {
    if (plan.weeks.isEmpty) {
      throw const ChatGptApiException(
        200,
        'Generated training plan contained no weeks.',
      );
    }

    final normalizedWeeks = <TrainingWeek>[];
    for (final week in plan.weeks) {
      final normalizedWorkouts = <PlannedWorkout>[];
      for (final workout in week.workouts) {
        normalizedWorkouts.add(_enforceWorkoutInvariants(workout));
      }
      normalizedWeeks.add(week.copyWith(workouts: normalizedWorkouts));
    }

    return plan.copyWith(
      config: config,
      weeks: normalizedWeeks,
    );
  }

  static PlannedWorkout _enforceWorkoutInvariants(PlannedWorkout workout) {
    switch (workout.archetype) {
      case WorkoutArchetype.rest:
        return workout.copyWith(
          discipline: SportDiscipline.strength,
          estimatedDurationMinutes: 0,
          clearEstimatedDistanceKm: true,
          estimatedTss: 0,
          blocks: const [],
          clearZwiftPrescription: true,
          clearBrickRunLeg: true,
        );

      case WorkoutArchetype.strength:
        return workout.copyWith(
          discipline: SportDiscipline.strength,
          clearZwiftPrescription: true,
          clearBrickRunLeg: true,
        );

      case WorkoutArchetype.zwiftRide:
        final bikeDiscipline = workout.discipline == SportDiscipline.bike
            ? SportDiscipline.bike
            : SportDiscipline.indoorBike;
        final prescription = workout.zwiftPrescription ??
            ZwiftPrescription(
              durationMinutes: workout.estimatedDurationMinutes > 0
                  ? workout.estimatedDurationMinutes
                  : 60,
              difficulty: 'Endurance',
              targetTss: (workout.estimatedTss ?? 55).round().clamp(0, 1000),
              zwiftCategory: 'Endurance',
              suggestedSearchTerms: const ['Endurance', 'Foundation'],
            );
        return workout.copyWith(
          discipline: bikeDiscipline,
          blocks: const [],
          zwiftPrescription: prescription,
          clearBrickRunLeg: true,
        );

      case WorkoutArchetype.brick:
        final bikeDiscipline =
            workout.discipline == SportDiscipline.indoorBike
                ? SportDiscipline.indoorBike
                : SportDiscipline.bike;
        final bikeMinutes = workout.estimatedDurationMinutes > 30
            ? (workout.estimatedDurationMinutes - 20).clamp(20, 600)
            : (workout.estimatedDurationMinutes > 0
                ? workout.estimatedDurationMinutes
                : 60);
        final prescription = workout.zwiftPrescription ??
            ZwiftPrescription(
              durationMinutes: bikeMinutes,
              difficulty: 'Tempo / Race Pace',
              targetTss: (workout.estimatedTss ?? 65).round().clamp(0, 1000),
              zwiftCategory: 'Tempo',
              suggestedSearchTerms: const ['Triathlon', 'Tempo'],
            );
        final rawLeg = workout.brickRunLeg ??
            PlannedWorkout(
              id: '${workout.id}_run',
              date: workout.date,
              title: 'Brick Transition Run',
              discipline: SportDiscipline.run,
              archetype: WorkoutArchetype.easy,
              estimatedDurationMinutes: 20,
              blocks: const [
                WorkoutBlock(
                  repeatCount: 1,
                  step: WorkoutStep(
                    kind: StepKind.steady,
                    endCondition: StepEndCondition.time,
                    endValue: 1200,
                    targetKind: StepTargetKind.heartRateZone,
                    targetLow: 2,
                    targetHigh: 2,
                    notes: 'Smooth off-the-bike transition cadence',
                  ),
                ),
              ],
            );
        final cappedLeg = _capBrickRunLeg(
          rawLeg,
          parentId: workout.id,
          parentDate: workout.date,
        );
        return workout.copyWith(
          discipline: bikeDiscipline,
          zwiftPrescription: prescription,
          brickRunLeg: cappedLeg,
        );

      case WorkoutArchetype.intervals:
      case WorkoutArchetype.threshold:
      case WorkoutArchetype.easy:
      case WorkoutArchetype.long:
        if (workout.discipline == SportDiscipline.bike ||
            workout.discipline == SportDiscipline.indoorBike) {
          if (workout.brickRunLeg != null) {
            return _enforceWorkoutInvariants(
              workout.copyWith(archetype: WorkoutArchetype.brick),
            );
          }
          return _enforceWorkoutInvariants(
            workout.copyWith(archetype: WorkoutArchetype.zwiftRide),
          );
        }
        final targetDiscipline = workout.discipline == SportDiscipline.swim
            ? SportDiscipline.swim
            : SportDiscipline.run;
        return workout.copyWith(
          discipline: targetDiscipline,
          clearZwiftPrescription: true,
          clearBrickRunLeg: true,
        );
    }
  }

  /// Ensures a Brick run leg is `<= 30` minutes AND total timed steps across
  /// `blocks` sum to `<= 1800.0` seconds (scaling proportionally if exceeded).
  static PlannedWorkout _capBrickRunLeg(
    PlannedWorkout leg, {
    required String parentId,
    required String parentDate,
  }) {
    var clampedMinutes = leg.estimatedDurationMinutes.clamp(0, 30);
    var blocks = leg.blocks;

    if (blocks.isEmpty) {
      final durationSec =
          (clampedMinutes > 0 ? clampedMinutes : 15) * 60.0;
      blocks = [
        WorkoutBlock(
          repeatCount: 1,
          step: WorkoutStep(
            kind: StepKind.steady,
            endCondition: StepEndCondition.time,
            endValue: durationSec.clamp(60.0, 1800.0),
            targetKind: StepTargetKind.heartRateZone,
            targetLow: 2,
            targetHigh: 2,
          ),
        ),
      ];
      if (clampedMinutes == 0) {
        clampedMinutes = 15;
      }
    } else {
      final totalTimedSec = _sumTimedSeconds(blocks);
      if (totalTimedSec > 1800.0) {
        final scale = 1800.0 / totalTimedSec;
        blocks = _scaleTimedBlocks(blocks, scale);
      }
      final finalTimedSec = _sumTimedSeconds(blocks);
      if (clampedMinutes == 0 && finalTimedSec > 0) {
        clampedMinutes = (finalTimedSec / 60.0).round().clamp(1, 30);
      }
    }

    return PlannedWorkout(
      id: leg.id.trim().isNotEmpty ? leg.id.trim() : '${parentId}_run',
      date: parentDate,
      title: leg.title.trim().isNotEmpty ? leg.title.trim() : 'Brick Transition Run',
      discipline: SportDiscipline.run,
      archetype: (leg.archetype == WorkoutArchetype.intervals ||
              leg.archetype == WorkoutArchetype.threshold ||
              leg.archetype == WorkoutArchetype.easy ||
              leg.archetype == WorkoutArchetype.long)
          ? leg.archetype
          : WorkoutArchetype.easy,
      estimatedDurationMinutes: clampedMinutes,
      estimatedDistanceKm: leg.estimatedDistanceKm,
      estimatedTss: leg.estimatedTss,
      coachNotes: leg.coachNotes,
      rationale: leg.rationale,
      blocks: blocks,
      status: leg.status,
      matchedActivityId: leg.matchedActivityId,
      adherencePercent: leg.adherencePercent,
      garminWorkoutId: leg.garminWorkoutId,
      garminScheduleId: leg.garminScheduleId,
      garminSyncedAt: leg.garminSyncedAt,
    );
  }

  static double _sumTimedSeconds(List<WorkoutBlock> blocks) {
    var total = 0.0;
    for (final block in blocks) {
      final children = block.effectiveSteps;
      final repeats =
          (block.repeatCount > 1 && children.isNotEmpty) ? block.repeatCount : 1;
      for (final step in children) {
        if (step.endCondition == StepEndCondition.time &&
            step.endValue != null &&
            step.endValue!.isFinite &&
            step.endValue! > 0) {
          total += step.endValue! * repeats;
        }
      }
    }
    return total;
  }

  static bool _isTimedStep(WorkoutStep step) =>
      step.endCondition == StepEndCondition.time &&
      step.endValue != null &&
      step.endValue!.isFinite &&
      step.endValue! > 0;

  static List<WorkoutBlock> _scaleTimedBlocks(
    List<WorkoutBlock> blocks,
    double scale,
  ) {
    WorkoutStep scaleStep(WorkoutStep step, double factor) {
      if (!_isTimedStep(step)) return step;
      final scaled = (step.endValue! * factor).floorToDouble();
      return step.copyWith(endValue: math.max(1.0, scaled));
    }

    WorkoutBlock mapBlockSteps(
      WorkoutBlock block,
      WorkoutStep Function(WorkoutStep) fn,
    ) {
      if (block.step != null) {
        return block.copyWith(
          step: fn(block.step!),
          steps: const [],
        );
      }
      if (block.steps.isNotEmpty) {
        return block.copyWith(steps: [for (final s in block.steps) fn(s)]);
      }
      return block;
    }

    var scaledBlocks = <WorkoutBlock>[
      for (final block in blocks)
        mapBlockSteps(block, (s) => scaleStep(s, scale)),
    ];

    // Guard against floor clamping (e.g. many 1s steps) pushing sum > 1800s.
    var total = _sumTimedSeconds(scaledBlocks);
    if (total > 1800.0) {
      final fixScale = 1800.0 / total;
      scaledBlocks = [
        for (final block in scaledBlocks)
          mapBlockSteps(block, (s) => scaleStep(s, fixScale)),
      ];
      total = _sumTimedSeconds(scaledBlocks);
    }

    // If keeping every timed step >= 1.0s still exceeds 1800s (e.g. 100 x 20 x 1s),
    // first reduce repeatCount on repeat blocks, then trim trailing timed steps.
    if (total > 1800.0) {
      for (var i = scaledBlocks.length - 1; i >= 0 && total > 1800.0; i--) {
        final block = scaledBlocks[i];
        final children = block.effectiveSteps;
        if (block.repeatCount <= 1 || children.isEmpty) continue;
        var repSec = 0.0;
        for (final step in children) {
          if (_isTimedStep(step)) {
            repSec += step.endValue!;
          }
        }
        if (repSec <= 0) continue;

        final excess = total - 1800.0;
        final maxDrop = block.repeatCount - 1;
        final neededDrop = (excess / repSec).ceil();
        final drop = math.min(maxDrop, neededDrop);
        if (drop > 0) {
          scaledBlocks[i] = block.copyWith(repeatCount: block.repeatCount - drop);
          total -= drop * repSec;
        }
      }
    }

    if (total > 1800.0) {
      for (var i = scaledBlocks.length - 1; i >= 0 && total > 1800.0; i--) {
        final block = scaledBlocks[i];
        final children = List<WorkoutStep>.from(block.effectiveSteps);
        final repeats = (block.repeatCount > 1 && children.isNotEmpty)
            ? block.repeatCount
            : 1;

        var idx = children.length - 1;
        while (idx >= 0 && total > 1800.0) {
          if (_isTimedStep(children[idx])) {
            final removed = children.removeAt(idx);
            total -= removed.endValue! * repeats;
          }
          idx--;
        }

        if (children.isEmpty) {
          scaledBlocks.removeAt(i);
        } else if (block.step != null) {
          scaledBlocks[i] = block.copyWith(
            step: children.single,
            steps: const [],
          );
        } else {
          scaledBlocks[i] = block.copyWith(steps: children);
        }
      }
    }

    return scaledBlocks;
  }

  static TrainingPlan _preservePastAndLockedWorkouts({
    required TrainingPlan existingPlan,
    required TrainingPlan adaptedPlan,
    required String referenceDateKey,
  }) {
    bool isLocked(PlannedWorkout w) {
      if (w.status == WorkoutStatus.completed ||
          w.status == WorkoutStatus.skipped) {
        return true;
      }
      if (w.date.isNotEmpty && w.date.compareTo(referenceDateKey) < 0) {
        return true;
      }
      final leg = w.brickRunLeg;
      if (leg != null &&
          (leg.status == WorkoutStatus.completed ||
              leg.status == WorkoutStatus.skipped)) {
        return true;
      }
      return false;
    }

    DateTime? parseDay(String key) {
      if (key.trim().isEmpty) return null;
      final parsed = DateTime.tryParse(key.trim());
      if (parsed == null) return null;
      return DateTime(parsed.year, parsed.month, parsed.day);
    }

    final existingWeeks = existingPlan.weeks;
    final lockedByExistingIdx = <int, List<PlannedWorkout>>{};
    final lockedIds = <String>{};
    final lockedSameOrFutureByDate = <String, List<PlannedWorkout>>{};

    for (var i = 0; i < existingWeeks.length; i++) {
      final week = existingWeeks[i];
      for (final workout in week.workouts) {
        if (!isLocked(workout)) continue;
        lockedByExistingIdx.putIfAbsent(i, () => []).add(workout);
        lockedIds.add(workout.id);
        if (workout.date.isNotEmpty &&
            workout.date.compareTo(referenceDateKey) >= 0) {
          lockedSameOrFutureByDate
              .putIfAbsent(workout.date, () => [])
              .add(workout);
        }
      }
    }

    // Compute calendar windows [winStart, winEnd] for each existing week.
    final startByIdx = <int, DateTime>{};
    for (var i = 0; i < existingWeeks.length; i++) {
      var parsed = parseDay(existingWeeks[i].startDate);
      if (parsed == null) {
        for (final w in existingWeeks[i].workouts) {
          final wDate = parseDay(w.date);
          if (wDate != null && (parsed == null || wDate.isBefore(parsed))) {
            parsed = wDate;
          }
        }
      }
      if (parsed != null) {
        startByIdx[i] = parsed;
      }
    }
    final sortedIdxByStart = startByIdx.keys.toList()
      ..sort((a, b) {
        final cmp = startByIdx[a]!.compareTo(startByIdx[b]!);
        return cmp != 0 ? cmp : a.compareTo(b);
      });
    final windowByIdx = <int, ({DateTime start, DateTime end})>{};
    for (var pos = 0; pos < sortedIdxByStart.length; pos++) {
      final idx = sortedIdxByStart[pos];
      final winStart = startByIdx[idx]!;
      var winEnd = winStart.add(const Duration(days: 6));
      for (var nextPos = pos + 1; nextPos < sortedIdxByStart.length; nextPos++) {
        final nextStart = startByIdx[sortedIdxByStart[nextPos]]!;
        if (nextStart.isAfter(winStart)) {
          if (!nextStart.isAfter(winEnd)) {
            winEnd = nextStart.subtract(const Duration(days: 1));
          }
          break;
        }
      }
      windowByIdx[idx] = (start: winStart, end: winEnd);
    }

    bool conflictsWithLocked(PlannedWorkout llmW, PlannedWorkout locked) {
      if (locked.archetype == WorkoutArchetype.rest ||
          llmW.archetype == WorkoutArchetype.rest) {
        return true;
      }
      if (WorkoutComplianceMatcher.isSportCompatible(
        locked.discipline,
        llmW.discipline,
      )) {
        return true;
      }
      if (locked.archetype == WorkoutArchetype.brick &&
          (llmW.discipline == SportDiscipline.run ||
              WorkoutComplianceMatcher.isSportCompatible(
                SportDiscipline.bike,
                llmW.discipline,
              ))) {
        return true;
      }
      if (llmW.archetype == WorkoutArchetype.brick &&
          (locked.discipline == SportDiscipline.run ||
              WorkoutComplianceMatcher.isSportCompatible(
                SportDiscipline.bike,
                locked.discipline,
              ))) {
        return true;
      }
      return false;
    }

    final matchedAdaptedMetaByIdx = <int, TrainingWeek>{};
    final matchedWorkoutsByIdx = <int, List<PlannedWorkout>>{};
    final unmatchedNewWeeks = <TrainingWeek>[];

    int? findExistingIdxForAdapted(TrainingWeek adaptedW) {
      // 1. Exact startDate match (preferring unmatched existing weeks first).
      if (adaptedW.startDate.isNotEmpty) {
        for (var i = 0; i < existingWeeks.length; i++) {
          if (!matchedAdaptedMetaByIdx.containsKey(i) &&
              existingWeeks[i].startDate == adaptedW.startDate) {
            return i;
          }
        }
        for (var i = 0; i < existingWeeks.length; i++) {
          if (existingWeeks[i].startDate == adaptedW.startDate) {
            return i;
          }
        }
      }

      // 2. Adapted startDate inside an existing week's calendar window.
      final adaptedStart = parseDay(adaptedW.startDate);
      if (adaptedStart != null) {
        for (final i in sortedIdxByStart) {
          final win = windowByIdx[i]!;
          if (!matchedAdaptedMetaByIdx.containsKey(i) &&
              !adaptedStart.isBefore(win.start) &&
              !adaptedStart.isAfter(win.end)) {
            return i;
          }
        }
        for (final i in sortedIdxByStart) {
          final win = windowByIdx[i]!;
          if (!adaptedStart.isBefore(win.start) &&
              !adaptedStart.isAfter(win.end)) {
            return i;
          }
        }
      }

      // 3. Workout date overlap against existing week windows.
      if (adaptedW.workouts.isNotEmpty && windowByIdx.isNotEmpty) {
        final overlapCounts = <int, int>{};
        for (final w in adaptedW.workouts) {
          final d = parseDay(w.date);
          if (d == null) continue;
          for (final i in sortedIdxByStart) {
            final win = windowByIdx[i]!;
            if (!d.isBefore(win.start) && !d.isAfter(win.end)) {
              overlapCounts[i] = (overlapCounts[i] ?? 0) + 1;
              break;
            }
          }
        }
        if (overlapCounts.isNotEmpty) {
          final ranked = overlapCounts.keys.toList()
            ..sort((a, b) {
              final countCmp = overlapCounts[b]!.compareTo(overlapCounts[a]!);
              if (countCmp != 0) return countCmp;
              final aMatched = matchedAdaptedMetaByIdx.containsKey(a) ? 1 : 0;
              final bMatched = matchedAdaptedMetaByIdx.containsKey(b) ? 1 : 0;
              if (aMatched != bMatched) return aMatched.compareTo(bMatched);
              return a.compareTo(b);
            });
          return ranked.first;
        }
      }

      // 4. Fallback to weekNumber only when neither startDates nor workout dates exist.
      if (adaptedW.startDate.isEmpty &&
          adaptedW.workouts.every((w) => w.date.isEmpty)) {
        for (var i = 0; i < existingWeeks.length; i++) {
          if (existingWeeks[i].weekNumber == adaptedW.weekNumber &&
              existingWeeks[i].startDate.isEmpty) {
            return i;
          }
        }
      }

      return null;
    }

    for (final week in adaptedPlan.weeks) {
      final filtered = <PlannedWorkout>[];
      for (final llmW in week.workouts) {
        if (llmW.date.isNotEmpty &&
            llmW.date.compareTo(referenceDateKey) < 0) {
          continue;
        }
        if (lockedIds.contains(llmW.id)) {
          continue;
        }
        final dayLocked = lockedSameOrFutureByDate[llmW.date];
        if (dayLocked != null &&
            dayLocked.any((locked) => conflictsWithLocked(llmW, locked))) {
          continue;
        }
        filtered.add(llmW);
      }

      final matchIdx = findExistingIdxForAdapted(week);
      if (matchIdx != null) {
        matchedAdaptedMetaByIdx.putIfAbsent(matchIdx, () => week);
        matchedWorkoutsByIdx.putIfAbsent(matchIdx, () => []).addAll(filtered);
      } else if (filtered.isNotEmpty) {
        unmatchedNewWeeks.add(week.copyWith(workouts: filtered));
      }
    }

    int compareWorkouts(PlannedWorkout a, PlannedWorkout b) {
      if (a.date.isEmpty && b.date.isEmpty) return 0;
      if (a.date.isEmpty) return 1;
      if (b.date.isEmpty) return -1;
      return a.date.compareTo(b.date);
    }

    final mergedWeeks = <TrainingWeek>[];
    for (var i = 0; i < existingWeeks.length; i++) {
      final existingW = existingWeeks[i];
      final locked = lockedByExistingIdx[i] ?? const <PlannedWorkout>[];
      final adaptedMeta = matchedAdaptedMetaByIdx[i];

      if (adaptedMeta == null) {
        final keepHistorical = locked.isNotEmpty ||
            (existingW.startDate.trim().isNotEmpty &&
                existingW.startDate.compareTo(referenceDateKey) < 0);
        if (keepHistorical) {
          final keptWorkouts = List<PlannedWorkout>.from(locked)
            ..sort(compareWorkouts);
          final preservedStartDate = existingW.startDate.trim().isNotEmpty
              ? existingW.startDate
              : (startByIdx[i] != null
                  ? PlannedWorkout.formatLocalDate(startByIdx[i]!)
                  : existingW.startDate);
          mergedWeeks.add(
            existingW.copyWith(
              startDate: preservedStartDate,
              workouts: locked.isNotEmpty ? keptWorkouts : existingW.workouts,
            ),
          );
        }
        continue;
      }

      final seenIds = <String>{};
      final combined = <PlannedWorkout>[];
      for (final w in [...locked, ...?matchedWorkoutsByIdx[i]]) {
        if (seenIds.add(w.id)) {
          combined.add(w);
        }
      }
      combined.sort(compareWorkouts);

      final effectiveStartDate = existingW.startDate.trim().isNotEmpty
          ? existingW.startDate
          : (adaptedMeta.startDate.trim().isNotEmpty
              ? adaptedMeta.startDate
              : (startByIdx[i] != null
                  ? PlannedWorkout.formatLocalDate(startByIdx[i]!)
                  : adaptedMeta.startDate));
      mergedWeeks.add(
        adaptedMeta.copyWith(
          startDate: effectiveStartDate,
          workouts: combined,
        ),
      );
    }

    for (final newWeek in unmatchedNewWeeks) {
      final sortedWorkouts = List<PlannedWorkout>.from(newWeek.workouts)
        ..sort(compareWorkouts);
      mergedWeeks.add(newWeek.copyWith(workouts: sortedWorkouts));
    }

    mergedWeeks.sort((a, b) {
      final aEmpty = a.startDate.trim().isEmpty;
      final bEmpty = b.startDate.trim().isEmpty;
      if (aEmpty && bEmpty) {
        return a.weekNumber.compareTo(b.weekNumber);
      }
      if (aEmpty) return 1;
      if (bEmpty) return -1;
      final dateCmp = a.startDate.compareTo(b.startDate);
      return dateCmp != 0 ? dateCmp : a.weekNumber.compareTo(b.weekNumber);
    });

    final renumberedWeeks = <TrainingWeek>[
      for (var i = 0; i < mergedWeeks.length; i++)
        mergedWeeks[i].copyWith(weekNumber: i + 1),
    ];

    return existingPlan.copyWith(
      name: adaptedPlan.name.trim().isNotEmpty
          ? adaptedPlan.name
          : existingPlan.name,
      coachOverview: adaptedPlan.coachOverview.trim().isNotEmpty
          ? adaptedPlan.coachOverview
          : existingPlan.coachOverview,
      updatedAt: DateTime.now().toUtc(),
      weeks: renumberedWeeks,
    );
  }

  int _resolveTotalWeeks({
    required TrainingPlanConfig config,
    required DateTime startDate,
    int? explicitWeeks,
  }) {
    if (explicitWeeks != null) {
      return explicitWeeks.clamp(1, 52);
    }
    if (config.raceDate.trim().isNotEmpty) {
      final parsed = DateTime.tryParse(config.raceDate.trim());
      if (parsed != null) {
        final startDay = DateTime(startDate.year, startDate.month, startDate.day);
        final raceDay = DateTime(parsed.year, parsed.month, parsed.day);
        final diffDays = raceDay.difference(startDay).inDays;
        if (diffDays > 0) {
          return ((diffDays + 6) ~/ 7).clamp(4, 24);
        }
      }
    }
    return 8;
  }

  // ---------------------------------------------------------------------------
  // Prompt & Input Builders
  // ---------------------------------------------------------------------------

  static const String _sportsScienceRules = '''
SPORTS SCIENCE & WORKOUT DESIGN RULES:
1. Polarized 80/20 distribution: ~80% of weekly volume in Z1-Z2 aerobic endurance, ~20% in Z3-Z5 quality/threshold/VO2max work.
2. Progressive overload: limit build-week volume increases to 5-10% per week.
3. 3:1 build/recovery mesocycles: follow every 3 build weeks with 1 recovery/deload week (~60-75% of build volume). Include a race-specific taper in the final 1-2 weeks before the target race date.
4. Run and Swim workouts MUST use ONLY the 4 structured archetypes: "intervals", "threshold", "easy", or "long", with explicit warmup, main-set (repeat blocks with interval + recovery steps when appropriate), and cooldown steps using the athlete's HR (heartRateBpm/heartRateZone) or pace (paceMps) targets.
5. Cycling workouts MUST use archetype "zwiftRide" with a zwiftPrescription (durationMinutes, difficulty, targetTss, zwiftCategory, suggestedSearchTerms, cadenceFocus, notes) instead of granular cycling interval trees.
6. Brick workouts MUST use archetype "brick" pairing a bike zwiftPrescription with a Garmin-syncable brickRunLeg strictly capped at <= 30 minutes (total timed steps <= 1800 seconds).
7. Respect the athlete's preferred rest day, long run day, long ride day, weekly hours budget, limiter sport, and current fatigue/readiness (CTL/ATL/TSB/ACWR).
''';

  String _formatConfigSummary(TrainingPlanConfig config) {
    final zones = config.zones;
    final buf = StringBuffer()
      ..writeln('ATHLETE PLAN CONFIGURATION:')
      ..writeln('- Race: ${config.raceName} (${config.raceDistance})')
      ..writeln(
        '- Race Date: ${config.raceDate.isNotEmpty ? config.raceDate : 'Flexible / 8-week block'}',
      )
      ..writeln(
        '- Weekly Hours Budget: ${config.weeklyHoursBudget.toStringAsFixed(1)} hrs/wk',
      )
      ..writeln(
        '- Preferred Days: Long Ride = ${config.longRideDay}, Long Run = ${config.longRunDay}, Rest = ${config.restDay}',
      )
      ..writeln('- Limiter Sport: ${config.limiterSport}')
      ..writeln(
        '- Zones: MaxHR ${zones.maxHr} bpm, LTHR ${zones.lthr} bpm'
        '${zones.runThresholdPaceSecPerKm != null ? ', Run Threshold ${zones.runThresholdPaceSecPerKm!.round()} s/km (${zones.runThresholdSpeedMps!.toStringAsFixed(2)} m/s)' : ''}'
        '${zones.swimCssSecPer100m != null ? ', Swim CSS ${zones.swimCssSecPer100m!.round()} s/100m' : ''}'
        '${zones.bikeFtpWatts != null ? ', Bike FTP ${zones.bikeFtpWatts} W' : ''}',
      );
    if (config.additionalNotes != null &&
        config.additionalNotes!.trim().isNotEmpty) {
      buf.writeln('- Additional Notes: ${config.additionalNotes!.trim()}');
    }
    return buf.toString();
  }

  String _buildCoachInstructions({
    required AthleteContext athleteContext,
    TrainingPlanConfig? config,
    TrainingPlan? activePlan,
    required UnitSystem unitSystem,
  }) {
    final buf = StringBuffer()
      ..writeln(
        'You are Pulse Coach, an expert endurance and triathlon coach integrated into Pulse Training.',
      )
      ..writeln(_sportsScienceRules)
      ..writeln(athleteContext.toPromptPayload(unitSystem: unitSystem));

    if (config != null) {
      buf.writeln();
      buf.writeln(_formatConfigSummary(config));
    }
    if (activePlan != null) {
      buf.writeln();
      buf.writeln(
        'ACTIVE TRAINING PLAN: "${activePlan.name}" (${activePlan.weeks.length} weeks, '
        '${activePlan.allWorkouts.length} total workouts).',
      );
    }
    return buf.toString();
  }

  String _buildPlanGenerationInstructions({
    required AthleteContext athleteContext,
    required TrainingPlanConfig config,
    required String startDateKey,
    required int weeksCount,
    required UnitSystem unitSystem,
  }) {
    return '''
You are Pulse Coach, an expert endurance and triathlon training plan architect.
Generate a $weeksCount-week structured triathlon training plan starting on $startDateKey.

$_sportsScienceRules

OUTPUT REQUIREMENTS:
- Output ONLY valid JSON conforming strictly to the provided JSON schema.
- Every workout date MUST be formatted YYYY-MM-DD starting from $startDateKey.
- Run and Swim workouts MUST have structured warmup / main set / cooldown blocks with realistic step durations/distances and paceMps or heartRateBpm/heartRateZone targets calibrated to the athlete's derived zones.
- Cycling workouts MUST use archetype "zwiftRide" with discipline "indoorBike" (or "bike") and a populated zwiftPrescription.
- Brick workouts MUST use archetype "brick", discipline "bike" (or "indoorBike"), a zwiftPrescription for the bike leg, and a brickRunLeg whose estimatedDurationMinutes <= 30 and whose steps total <= 1800 seconds.
- Rest days MUST use archetype "rest", discipline "strength", estimatedDurationMinutes 0, and empty blocks.

${athleteContext.toPromptPayload(unitSystem: unitSystem)}

${_formatConfigSummary(config)}
''';
  }

  String _buildPlanAdaptationInstructions({
    required AthleteContext athleteContext,
    required TrainingPlan existingPlan,
    required String referenceDateKey,
    required UnitSystem unitSystem,
  }) {
    return '''
You are Pulse Coach, an expert endurance and triathlon training plan architect.
Adapt the remaining weeks of the athlete's existing training plan starting from $referenceDateKey onward.

$_sportsScienceRules

ADAPTATION RULES:
- Preserve ALL workouts dated before $referenceDateKey and ALL workouts already marked "completed" or "skipped" without altering their IDs, dates, blocks, or status.
- Preserve the original weekNumber and startDate values from the existing plan for all weeks (do NOT renumber remaining weeks starting at 1).
- Rebalance workouts from $referenceDateKey onward based on recent adherence, missed sessions, current CTL/ATL/TSB/ACWR, and athlete feedback.
- Maintain all Run/Swim 4-archetype, Zwift cycling prescription, and Brick run-leg <= 30 min (<= 1800s) rules.
- Output ONLY valid JSON conforming strictly to the provided JSON schema.

${athleteContext.toPromptPayload(unitSystem: unitSystem)}

${_formatConfigSummary(existingPlan.config)}
''';
  }

  List<Map<String, dynamic>> _historyToInputItems(List<CoachMessage> history) {
    final items = <Map<String, dynamic>>[];
    for (final msg in history) {
      final text = msg.content.trim();
      if (text.isEmpty) continue;
      final role = switch (msg.role) {
        CoachMessageRole.user => 'user',
        CoachMessageRole.assistant => 'assistant',
        CoachMessageRole.system => 'developer',
      };
      items.add({
        'role': role,
        'content': text,
      });
    }
    return items;
  }

  List<Map<String, dynamic>> _buildCoachInput(
    List<CoachMessage> history,
    String userMessage,
  ) {
    final items = _historyToInputItems(history);
    final alreadyTrailing = items.isNotEmpty &&
        items.last['role'] == 'user' &&
        items.last['content'] == userMessage;
    if (!alreadyTrailing) {
      items.add({
        'role': 'user',
        'content': userMessage,
      });
    }
    return items;
  }

  String _callbackHtml({required String title, required String body}) {
    final safeTitle = const HtmlEscape().convert(title);
    final safeBody = const HtmlEscape().convert(body);
    return '''
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title>$safeTitle</title>
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
    <h1>$safeTitle</h1>
    <p>$safeBody</p>
  </div>
</body>
</html>
''';
  }
}
