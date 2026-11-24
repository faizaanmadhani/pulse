import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pulse_training_hub/models/activity.dart';
import 'package:pulse_training_hub/models/training_plan.dart';
import 'package:pulse_training_hub/services/chatgpt_auth_store.dart';
import 'package:pulse_training_hub/services/chatgpt_service.dart';
import 'package:pulse_training_hub/utils/athlete_context_builder.dart';
import 'package:pulse_training_hub/utils/unit_formatter.dart';

String _encodeJwt(Map<String, dynamic> payload) {
  final header = base64UrlEncode(utf8.encode(jsonEncode({'alg': 'RS256'})))
      .replaceAll('=', '');
  final body =
      base64UrlEncode(utf8.encode(jsonEncode(payload))).replaceAll('=', '');
  return '$header.$body.sig_placeholder';
}

AthleteContext _sampleAthleteContext({
  PlanAdherenceSummary? adherence,
}) {
  return AthleteContext(
    asOfDate: DateTime(2026, 11, 24),
    zones: const AthleteZonesSnapshot(
      maxHr: 190,
      lthr: 171,
      hrZones: [
        HrZoneRange(zone: 1, label: 'Recovery', lowBpm: 110, highBpm: 138),
        HrZoneRange(zone: 2, label: 'Aerobic', lowBpm: 139, highBpm: 152),
        HrZoneRange(zone: 3, label: 'Tempo', lowBpm: 153, highBpm: 164),
        HrZoneRange(zone: 4, label: 'Threshold', lowBpm: 165, highBpm: 174),
        HrZoneRange(zone: 5, label: 'VO2max', lowBpm: 175, highBpm: 190),
      ],
      runThresholdPaceSecPerKm: 255,
      swimCssSecPer100m: 105,
      bikeFtpWatts: 265,
    ),
    ctl: 58.4,
    atl: 62.1,
    tsb: -3.7,
    acwr: 1.06,
    acwrStatus: 'Optimal',
    restingHr: 48,
    hrvMs: 72,
    vo2MaxEst: 56.2,
    avgWeeklyHours4w: 8.5,
    avgWeeklyHours12w: 7.8,
    adherenceSummary: adherence,
  );
}

TrainingPlanConfig _sampleConfig() {
  return const TrainingPlanConfig(
    raceName: 'Ironman 70.3 Oceanside',
    raceDistance: '70.3',
    raceDate: '2027-03-28',
    weeklyHoursBudget: 10.0,
    longRunDay: 'Sunday',
    longRideDay: 'Saturday',
    restDay: 'Friday',
    limiterSport: 'Swim',
    zones: AthleteZonesSnapshot(
      maxHr: 190,
      lthr: 171,
      runThresholdPaceSecPerKm: 255,
      swimCssSecPer100m: 105,
      bikeFtpWatts: 265,
    ),
  );
}

int _maxObjectNestingDepth(
  Map<String, dynamic> node,
  Map<String, dynamic> defs, [
  int currentDepth = 1,
  Set<String> activeRefs = const {},
]) {
  var maxDepth = currentDepth;

  void visit(dynamic sub, int depthForObject) {
    if (sub is! Map) return;
    final ref = sub[r'$ref'];
    if (ref is String && ref.startsWith(r'#/$defs/')) {
      final defName = ref.substring(r'#/$defs/'.length);
      if (activeRefs.contains(defName)) {
        fail('Circular \$ref detected: $defName');
      }
      final target = defs[defName];
      if (target is Map<String, dynamic>) {
        final d = _maxObjectNestingDepth(
          target,
          defs,
          depthForObject,
          {...activeRefs, defName},
        );
        if (d > maxDepth) maxDepth = d;
      }
      return;
    }

    if (sub['anyOf'] is List) {
      for (final option in sub['anyOf'] as List) {
        visit(option, depthForObject);
      }
      return;
    }

    if (sub['items'] is Map) {
      visit(sub['items'], depthForObject);
      return;
    }

    if (sub['type'] == 'object' && sub is Map<String, dynamic>) {
      final d = _maxObjectNestingDepth(
        sub,
        defs,
        depthForObject,
        activeRefs,
      );
      if (d > maxDepth) maxDepth = d;
    }
  }

  final props = node['properties'];
  if (props is Map) {
    for (final propSchema in props.values) {
      visit(propSchema, currentDepth + 1);
    }
  }
  return maxDepth;
}

void main() {
  group('ChatGptSession & ChatGptAuthStore', () {
    test('saves, loads, and clears session atomically with 0600 permissions',
        () async {
      final tmpDir =
          await Directory.systemTemp.createTemp('chatgpt_store_test_');
      try {
        final filePath = '${tmpDir.path}/chatgpt_session.json';
        final store = ChatGptAuthStore(customFilePath: filePath);
        final expiresAt = DateTime.utc(2030, 5, 1, 14, 30, 0);
        final session = ChatGptSession(
          clientId: 'oaiapp_test_123',
          accessToken: 'acc_tok_xyz',
          refreshToken: 'ref_tok_abc',
          idToken: 'hdr.payload.sig',
          expiresAt: expiresAt,
          userName: 'Alex Mercer',
          userEmail: 'alex@example.com',
          planTier: 'plus',
        );

        await store.save(session);

        final file = File(filePath);
        expect(await file.exists(), isTrue);
        expect(await File('$filePath.tmp').exists(), isFalse);
        final siblings = tmpDir.listSync().map((e) => e.path).toList();
        expect(siblings.where((p) => p.endsWith('.tmp')), isEmpty);

        if (!Platform.isWindows) {
          final mode = (await file.stat()).mode & 0x1FF;
          expect(mode, 0x180); // 0600
        }

        final loaded = await store.load();
        expect(loaded, isNotNull);
        expect(loaded!.clientId, 'oaiapp_test_123');
        expect(loaded.accessToken, 'acc_tok_xyz');
        expect(loaded.refreshToken, 'ref_tok_abc');
        expect(loaded.idToken, 'hdr.payload.sig');
        expect(loaded.expiresAt.toUtc(), expiresAt);
        expect(loaded.userName, 'Alex Mercer');
        expect(loaded.userEmail, 'alex@example.com');
        expect(loaded.planTier, 'plus');
        expect(loaded.isExpired, isFalse);
        expect(loaded.canRefresh, isTrue);

        // Stale temp files are cleaned up on clear().
        await File('$filePath.tmp').writeAsString('stale');
        await File('$filePath.999.0.tmp').writeAsString('stale2');

        await store.clear();
        expect(await store.load(), isNull);
        expect(await file.exists(), isFalse);
        expect(await File('$filePath.tmp').exists(), isFalse);
        expect(await File('$filePath.999.0.tmp').exists(), isFalse);
      } finally {
        await tmpDir.delete(recursive: true);
      }
    });

    test('isExpired uses 2-minute buffer and canRefresh requires clientId + refreshToken',
        () {
      final expiredPast = ChatGptSession(
        clientId: 'oaiapp_1',
        accessToken: 'tok',
        refreshToken: 'ref',
        expiresAt: DateTime.now().subtract(const Duration(seconds: 10)),
      );
      final expiredInBuffer = ChatGptSession(
        clientId: 'oaiapp_1',
        accessToken: 'tok',
        refreshToken: 'ref',
        expiresAt: DateTime.now().add(const Duration(seconds: 90)),
      );
      final valid = ChatGptSession(
        clientId: 'oaiapp_1',
        accessToken: 'tok',
        refreshToken: 'ref',
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      );
      final missingRefresh = ChatGptSession(
        clientId: 'oaiapp_1',
        accessToken: 'tok',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      final missingClient = ChatGptSession(
        clientId: '  ',
        accessToken: 'tok',
        refreshToken: 'ref',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );

      expect(expiredPast.isExpired, isTrue);
      expect(expiredInBuffer.isExpired, isTrue);
      expect(valid.isExpired, isFalse);
      expect(valid.canRefresh, isTrue);
      expect(missingRefresh.canRefresh, isFalse);
      expect(missingClient.canRefresh, isFalse);
    });

    test('load returns null safely on missing, empty, corrupt, or incomplete JSON',
        () async {
      final tmpDir =
          await Directory.systemTemp.createTemp('chatgpt_corrupt_test_');
      try {
        final filePath = '${tmpDir.path}/chatgpt_session.json';
        final store = ChatGptAuthStore(customFilePath: filePath);

        // Missing
        expect(await store.load(), isNull);

        // Whitespace
        await File(filePath).writeAsString('   \n ');
        expect(await store.load(), isNull);

        // Truncated JSON
        await File(filePath).writeAsString('{"clientId": "abc"');
        expect(await store.load(), isNull);

        // Non-Map JSON
        await File(filePath).writeAsString('[1, 2, 3]');
        expect(await store.load(), isNull);

        // Incomplete JSON (missing accessToken)
        await File(filePath).writeAsString(jsonEncode({
          'clientId': 'oaiapp_1',
          'expiresAt': DateTime.utc(2030, 1, 1).toIso8601String(),
        }));
        expect(await store.load(), isNull);
      } finally {
        await tmpDir.delete(recursive: true);
      }
    });

    test('concurrent saves across two store instances preserve valid JSON',
        () async {
      final tmpDir =
          await Directory.systemTemp.createTemp('chatgpt_concurrent_test_');
      try {
        final filePath = '${tmpDir.path}/chatgpt_session.json';
        final storeA = ChatGptAuthStore(customFilePath: filePath);
        final storeB = ChatGptAuthStore(customFilePath: filePath);

        final futures = <Future<void>>[];
        for (var i = 0; i < 12; i++) {
          final store = i.isEven ? storeA : storeB;
          futures.add(
            store.save(
              ChatGptSession(
                clientId: 'oaiapp_conc',
                accessToken: 'token_$i',
                refreshToken: 'refresh_$i',
                expiresAt: DateTime.utc(2030, 1, 1).add(Duration(minutes: i)),
              ),
            ),
          );
        }
        await Future.wait(futures);

        final loaded = await storeA.load();
        expect(loaded, isNotNull);
        expect(loaded!.accessToken, startsWith('token_'));
        final leftovers = tmpDir
            .listSync()
            .where((e) => e.path.endsWith('.tmp'))
            .toList();
        expect(leftovers, isEmpty);
      } finally {
        await tmpDir.delete(recursive: true);
      }
    });
  });

  group('ChatGptService OAuth 2.0 + PKCE', () {
    test('generateCodeVerifier & computeCodeChallengeS256 adhere to RFC 7636',
        () {
      final verifier = ChatGptService.generateCodeVerifier();
      expect(verifier.length, 64);
      expect(RegExp(r'^[A-Za-z0-9\-._~]+$').hasMatch(verifier), isTrue);

      expect(ChatGptService.generateCodeVerifier(length: 43).length, 43);
      expect(ChatGptService.generateCodeVerifier(length: 128).length, 128);
      expect(
        () => ChatGptService.generateCodeVerifier(length: 42),
        throwsArgumentError,
      );
      expect(
        () => ChatGptService.generateCodeVerifier(length: 129),
        throwsArgumentError,
      );

      // RFC 7636 Appendix B test vector
      const rfcVerifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';
      const expectedChallenge = 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM';
      expect(
        ChatGptService.computeCodeChallengeS256(rfcVerifier),
        expectedChallenge,
      );
      expect(
        () => ChatGptService.computeCodeChallengeS256(''),
        throwsArgumentError,
      );

      final s1 = ChatGptService.generateState();
      final s2 = ChatGptService.generateState();
      expect(s1.length, greaterThanOrEqualTo(24));
      expect(s1, isNot(s2));
    });

    test('parseIdTokenClaims decodes unpadded UTF-8 claims and ignores malformed tokens',
        () {
      final jwt = _encodeJwt({
        'email': 'athlete@example.com',
        'name': 'José Runner',
        'https://api.openai.com/auth': {
          'chatgpt_plan_type': 'plus',
        },
      });
      final claims = ChatGptService.parseIdTokenClaims(jwt);
      expect(claims['email'], 'athlete@example.com');
      expect(claims['name'], 'José Runner');
      expect(
        (claims['https://api.openai.com/auth'] as Map)['chatgpt_plan_type'],
        'plus',
      );

      expect(ChatGptService.parseIdTokenClaims(''), isEmpty);
      expect(ChatGptService.parseIdTokenClaims('not-a-jwt'), isEmpty);
      expect(ChatGptService.parseIdTokenClaims('a.!!!invalid!!!.c'), isEmpty);
    });

    test('buildAuthorizeUrl constructs ChatGPT PKCE authorize URL', () {
      final service = ChatGptService(
        client: MockClient((_) async => http.Response('', 200)),
      );
      final uri = service.buildAuthorizeUrl(
        clientId: 'oaiapp_123',
        redirectUri: 'http://127.0.0.1:1455/callback',
        codeChallenge: 'chal_xyz',
        state: 'state_abc',
      );

      expect(uri.scheme, 'https');
      expect(uri.host, 'auth.openai.com');
      expect(uri.path, '/api/accounts/authorize');
      expect(uri.queryParameters['response_type'], 'code');
      expect(uri.queryParameters['client_id'], 'oaiapp_123');
      expect(
        uri.queryParameters['redirect_uri'],
        'http://127.0.0.1:1455/callback',
      );
      expect(
        uri.queryParameters['scope'],
        'openid profile email offline_access chatgpt.tokens.use.direct',
      );
      expect(uri.queryParameters['code_challenge'], 'chal_xyz');
      expect(uri.queryParameters['code_challenge_method'], 'S256');
      expect(uri.queryParameters['state'], 'state_abc');

      expect(
        () => service.buildAuthorizeUrl(
          clientId: '  ',
          redirectUri: 'http://127.0.0.1:1455/callback',
          codeChallenge: 'c',
          state: 's',
        ),
        throwsA(isA<ChatGptAuthException>()),
      );
    });

    test('parseOAuthCallbackInput handles raw code, redirect URL, state mismatch, and error',
        () {
      expect(
        ChatGptService.parseOAuthCallbackInput('raw_auth_code_42'),
        'raw_auth_code_42',
      );
      expect(
        ChatGptService.parseOAuthCallbackInput(
          'http://127.0.0.1:1455/callback?code=url_code_99&state=st_1',
          expectedState: 'st_1',
        ),
        'url_code_99',
      );
      expect(
        () => ChatGptService.parseOAuthCallbackInput(
          'http://127.0.0.1:1455/callback?code=url_code_99&state=wrong',
          expectedState: 'st_1',
        ),
        throwsA(isA<ChatGptAuthException>()),
      );
      expect(
        () => ChatGptService.parseOAuthCallbackInput(
          'http://127.0.0.1:1455/callback?error=access_denied&error_description=User+cancelled',
        ),
        throwsA(isA<ChatGptAuthException>()),
      );
      expect(
        () => ChatGptService.parseOAuthCallbackInput(
          'http://127.0.0.1:1455/callback?code=evil_code',
          expectedState: 'st_1',
        ),
        throwsA(isA<ChatGptAuthException>()),
      );
      expect(
        ChatGptService.parseOAuthCallbackInput(
          'HTTP://127.0.0.1:1455/callback?code=c_upper&state=st_1',
          expectedState: 'st_1',
        ),
        'c_upper',
      );
      expect(
        ChatGptService.parseOAuthCallbackInput(
          'HTTPS://127.0.0.1:1455/callback?code=c_https_upper&state=st_1',
          expectedState: 'st_1',
        ),
        'c_https_upper',
      );
      expect(
        ChatGptService.parseOAuthCallbackInput(
          '127.0.0.1:1455/callback?code=c_schemeless&state=st_1',
          expectedState: 'st_1',
        ),
        'c_schemeless',
      );
      expect(
        ChatGptService.parseOAuthCallbackInput(
          'raw_auth_code_42',
          expectedState: 'st_1',
        ),
        'raw_auth_code_42',
      );
    });

    test('waitForOAuthCode receives loopback callback, ignores favicon, validates state, and closes server',
        () async {
      final service = ChatGptService(
        client: MockClient((_) async => http.Response('', 200)),
      );
      late int boundPort;

      final code = await service.waitForOAuthCode(
        port: 0,
        expectedState: 'state_expected_123',
        timeout: const Duration(seconds: 5),
        onServerReady: (redirectUri) async {
          final parsed = Uri.parse(redirectUri);
          boundPort = parsed.port;
          final httpClient = HttpClient();
          try {
            // Non-callback path should return 404 and keep server open.
            final favReq = await httpClient.getUrl(
              Uri.parse('http://127.0.0.1:$boundPort/favicon.ico'),
            );
            final favRes = await favReq.close();
            await favRes.drain<void>();
            expect(favRes.statusCode, HttpStatus.notFound);

            // Real callback with matching state.
            final cbReq = await httpClient.getUrl(
              Uri.parse(
                '$redirectUri?code=oauth_live_code&state=state_expected_123',
              ),
            );
            final cbRes = await cbReq.close();
            final body = await utf8.decoder.bind(cbRes).join();
            expect(cbRes.statusCode, HttpStatus.ok);
            expect(body, contains('Connected to Pulse Training'));
          } finally {
            httpClient.close(force: true);
          }
        },
      );

      expect(code, 'oauth_live_code');

      // Server must already be closed.
      final postCloseClient = HttpClient();
      try {
        await expectLater(
          postCloseClient.getUrl(
            Uri.parse('http://127.0.0.1:$boundPort/callback'),
          ),
          throwsA(isA<SocketException>()),
        );
      } finally {
        postCloseClient.close(force: true);
      }
    });

    test('waitForOAuthCode rejects mismatched state', () async {
      final service = ChatGptService(
        client: MockClient((_) async => http.Response('', 200)),
      );

      await expectLater(
        service.waitForOAuthCode(
          port: 0,
          expectedState: 'correct_state',
          timeout: const Duration(seconds: 5),
          onServerReady: (redirectUri) async {
            final httpClient = HttpClient();
            try {
              final req = await httpClient.getUrl(
                Uri.parse('$redirectUri?code=abc&state=tampered_state'),
              );
              final res = await req.close();
              await res.drain<void>();
              expect(res.statusCode, HttpStatus.badRequest);
            } finally {
              httpClient.close(force: true);
            }
          },
        ),
        throwsA(isA<ChatGptAuthException>()),
      );
    });

    test('exchangeAuthorizationCode and refreshToken execute PKCE token flow without client_secret',
        () async {
      final idToken = _encodeJwt({
        'email': 'triathlete@pulse.app',
        'name': 'Taylor Swim',
        'https://api.openai.com/auth': {'chatgpt_plan_type': 'pro'},
      });

      final mockClient = MockClient((request) async {
        expect(
          request.url.toString(),
          'https://auth.openai.com/api/accounts/oauth/token',
        );
        expect(request.method, 'POST');
        final fields = request.bodyFields;
        expect(fields.containsKey('client_secret'), isFalse);

        if (fields['grant_type'] == 'authorization_code') {
          expect(fields['client_id'], 'oaiapp_abc');
          expect(fields['code'], 'code_123');
          expect(fields['code_verifier'], 'verifier_xyz');
          expect(fields['redirect_uri'], 'http://127.0.0.1:1455/callback');
          return http.Response(
            jsonEncode({
              'access_token': 'access_1',
              'refresh_token': 'refresh_1',
              'id_token': idToken,
              'expires_in': 3600,
            }),
            200,
          );
        }

        if (fields['grant_type'] == 'refresh_token') {
          expect(fields['client_id'], 'oaiapp_abc');
          expect(fields['refresh_token'], 'refresh_1');
          // Omit refresh_token and id_token to verify preservation.
          return http.Response(
            jsonEncode({
              'access_token': 'access_2',
              'expires_in': 7200,
            }),
            200,
          );
        }

        return http.Response('unexpected grant_type', 400);
      });

      final service = ChatGptService(client: mockClient);
      final initial = await service.exchangeAuthorizationCode(
        clientId: 'oaiapp_abc',
        code: 'code_123',
        codeVerifier: 'verifier_xyz',
        redirectUri: 'http://127.0.0.1:1455/callback',
      );

      expect(initial.accessToken, 'access_1');
      expect(initial.refreshToken, 'refresh_1');
      expect(initial.idToken, idToken);
      expect(initial.userEmail, 'triathlete@pulse.app');
      expect(initial.userName, 'Taylor Swim');
      expect(initial.planTier, 'pro');

      final refreshed = await service.refreshToken(initial);
      expect(refreshed.accessToken, 'access_2');
      expect(refreshed.refreshToken, 'refresh_1');
      expect(refreshed.idToken, idToken);
      expect(refreshed.userEmail, 'triathlete@pulse.app');
      expect(refreshed.userName, 'Taylor Swim');
      expect(refreshed.planTier, 'pro');
    });

    test('zero OpenAI API key path exists in auth store or chatgpt service', () {
      final authStoreSrc =
          File('lib/services/chatgpt_auth_store.dart').readAsStringSync();
      final serviceSrc =
          File('lib/services/chatgpt_service.dart').readAsStringSync();
      final combined = '$authStoreSrc\n$serviceSrc';

      expect(combined.contains('OPENAI_API_KEY'), isFalse);
      expect(combined.contains('x-api-key'), isFalse);
      expect(RegExp(r'\bapi_?[kK]ey\b').hasMatch(combined), isFalse);
    });
  });

  group('ChatGptService Responses API Schema, Coach & Plans', () {
    test('trainingPlanJsonSchema satisfies OpenAI strict mode (<=5 nesting levels, additionalProperties: false, all required, no circular ref)',
        () {
      final schema = ChatGptService.trainingPlanJsonSchema();
      final defs = Map<String, dynamic>.from(schema[r'$defs'] as Map);

      final depth = _maxObjectNestingDepth(schema, defs);
      expect(depth, lessThanOrEqualTo(5));

      void assertStrictObject(Map<String, dynamic> obj, String label) {
        expect(obj['type'], 'object', reason: '$label must be object');
        expect(
          obj['additionalProperties'],
          isFalse,
          reason: '$label missing additionalProperties: false',
        );
        final props = (obj['properties'] as Map).keys.toSet();
        final req = (obj['required'] as List).cast<String>().toSet();
        expect(req, equals(props), reason: '$label required != properties');
      }

      assertStrictObject(schema, 'root');
      for (final entry in defs.entries) {
        assertStrictObject(
          Map<String, dynamic>.from(entry.value as Map),
          entry.key,
        );
      }
    });

    test('sendCoachMessage sends Bearer token, sports-science instructions, context, deduplicates trailing message, and avoids double output_text',
        () async {
      late Map<String, dynamic> capturedRequest;
      final service = ChatGptService(
        client: MockClient((request) async {
          expect(request.url.toString(), 'https://api.openai.com/v1/responses');
          expect(request.headers['Authorization'], 'Bearer oauth_tok_live');
          expect(request.headers['Content-Type'], startsWith('application/json'));
          capturedRequest = jsonDecode(request.body) as Map<String, dynamic>;

          return http.Response(
            jsonEncode({
              'status': 'completed',
              'output_text': 'SHOULD_NOT_APPEND_WHEN_OUTPUT_PRESENT',
              'output': [
                {
                  'type': 'message',
                  'role': 'assistant',
                  'content': [
                    {
                      'type': 'output_text',
                      'text': 'Keep 80% of your run volume in Zone 2 this week.',
                    },
                  ],
                },
              ],
            }),
            200,
          );
        }),
      );

      final session = ChatGptSession(
        clientId: 'oaiapp_1',
        accessToken: 'oauth_tok_live',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );

      final reply = await service.sendCoachMessage(
        session: session,
        history: [
          CoachMessage(
            id: 'm1',
            role: CoachMessageRole.assistant,
            content: 'Ready to review your week.',
            createdAt: DateTime.utc(2026, 11, 23),
          ),
          CoachMessage(
            id: 'm2',
            role: CoachMessageRole.user,
            content: 'How should I pace Tuesday?',
            createdAt: DateTime.utc(2026, 11, 24),
          ),
        ],
        userMessage: 'How should I pace Tuesday?',
        athleteContext: _sampleAthleteContext(),
        config: _sampleConfig(),
        unitSystem: UnitSystem.metric,
      );

      expect(reply, 'Keep 80% of your run volume in Zone 2 this week.');
      final instructions = capturedRequest['instructions'] as String;
      expect(instructions, contains('80/20'));
      expect(instructions, contains('5-10%'));
      expect(instructions, contains('3:1'));
      expect(instructions, contains('zwiftRide'));
      expect(instructions, contains('<= 30'));
      expect(instructions, contains('CTL 58.4'));
      expect(instructions, contains('Ironman 70.3 Oceanside'));

      final input = capturedRequest['input'] as List;
      expect(input.length, 2); // trailing duplicate user message deduplicated
      expect(input[0]['role'], 'assistant');
      expect(input[1]['role'], 'user');
      expect(input[1]['content'], 'How should I pace Tuesday?');
    });

    test('handles 401, refusal, incomplete, failed, top-level error, and output_text-only fallback',
        () async {
      final session = ChatGptSession(
        clientId: 'oaiapp_1',
        accessToken: 'tok',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );

      // 401 -> ChatGptUnauthorizedException
      final s401 = ChatGptService(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'error': {'message': 'Invalid token'}
            }),
            401,
          ),
        ),
      );
      await expectLater(
        s401.sendCoachMessage(
          session: session,
          history: const [],
          userMessage: 'Hi',
          athleteContext: _sampleAthleteContext(),
        ),
        throwsA(isA<ChatGptUnauthorizedException>()),
      );

      // Refusal
      final sRefusal = ChatGptService(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'status': 'completed',
              'output_text': 'ignored fallback',
              'output': [
                {
                  'type': 'message',
                  'content': [
                    {'type': 'refusal', 'refusal': 'Cannot fulfill request.'}
                  ],
                },
              ],
            }),
            200,
          ),
        ),
      );
      await expectLater(
        sRefusal.sendCoachMessage(
          session: session,
          history: const [],
          userMessage: 'Hi',
          athleteContext: _sampleAthleteContext(),
        ),
        throwsA(
          isA<ChatGptApiException>().having((e) => e.isRefusal, 'isRefusal', isTrue),
        ),
      );

      // Incomplete
      final sIncomplete = ChatGptService(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'status': 'incomplete',
              'incomplete_details': {'reason': 'max_output_tokens'},
              'output_text': '{"partial":',
            }),
            200,
          ),
        ),
      );
      await expectLater(
        sIncomplete.sendCoachMessage(
          session: session,
          history: const [],
          userMessage: 'Hi',
          athleteContext: _sampleAthleteContext(),
        ),
        throwsA(isA<ChatGptApiException>()),
      );

      // Top-level error on 200
      final sErr = ChatGptService(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'error': {'message': 'Upstream failure', 'code': 'server_error'}
            }),
            200,
          ),
        ),
      );
      await expectLater(
        sErr.sendCoachMessage(
          session: session,
          history: const [],
          userMessage: 'Hi',
          athleteContext: _sampleAthleteContext(),
        ),
        throwsA(isA<ChatGptApiException>()),
      );

      // output_text-only fallback when output array is absent
      final sFallback = ChatGptService(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'status': 'completed',
              'output_text': 'Fallback text response.',
            }),
            200,
          ),
        ),
      );
      final res = await sFallback.sendCoachMessage(
        session: session,
        history: const [],
        userMessage: 'Hi',
        athleteContext: _sampleAthleteContext(),
      );
      expect(res, 'Fallback text response.');
    });

    test('generateTrainingPlan parses Run/Swim/Zwift/Brick, converts brickRunLeg.steps -> blocks, and enforces <= 30m Brick step cap',
        () async {
      final planJsonPayload = {
        'name': 'Oceanside 70.3 Prep',
        'coachOverview': '80/20 polarized build focusing on swim limiter.',
        'weeks': [
          {
            'weekNumber': 1,
            'startDate': '2026-11-24',
            'phaseName': 'Base',
            'focusSummary': 'Aerobic foundation & threshold touch',
            'targetHours': 8.5,
            'targetTss': 430,
            'workouts': [
              {
                'id': 'w1_swim_int',
                'date': '2026-11-24',
                'title': 'CSS Swim Intervals',
                'discipline': 'swim',
                'archetype': 'intervals',
                'estimatedDurationMinutes': 50,
                'estimatedDistanceKm': 2.4,
                'estimatedTss': 55,
                'coachNotes': 'Hold CSS pace with 15s rest',
                'rationale': 'Improve swim limiter efficiency',
                'blocks': [
                  {
                    'repeatCount': 1,
                    'step': {
                      'kind': 'warmup',
                      'endCondition': 'distance',
                      'endValue': 400,
                      'targetKind': 'none',
                      'targetLow': null,
                      'targetHigh': null,
                      'notes': 'Easy freestyle',
                      'strokeType': 'freestyle',
                    },
                    'steps': [],
                  },
                  {
                    'repeatCount': 8,
                    'step': null,
                    'steps': [
                      {
                        'kind': 'interval',
                        'endCondition': 'distance',
                        'endValue': 100,
                        'targetKind': 'paceMps',
                        'targetLow': 0.92,
                        'targetHigh': 0.98,
                        'notes': 'CSS pace',
                        'strokeType': 'freestyle',
                      },
                      {
                        'kind': 'rest',
                        'endCondition': 'time',
                        'endValue': 15,
                        'targetKind': 'none',
                        'targetLow': null,
                        'targetHigh': null,
                        'notes': 'Wall rest',
                        'strokeType': null,
                      },
                    ],
                  },
                ],
                'zwiftPrescription': null,
                'brickRunLeg': null,
              },
              {
                'id': 'w1_bike_zwift',
                'date': '2026-11-25',
                'title': 'Zwift Sweet Spot Ride',
                'discipline': 'indoorBike',
                'archetype': 'zwiftRide',
                'estimatedDurationMinutes': 60,
                'estimatedDistanceKm': null,
                'estimatedTss': 58,
                'coachNotes': 'Stay seated in aero',
                'rationale': 'Build aerobic cycling power',
                'blocks': [],
                'zwiftPrescription': {
                  'durationMinutes': 60,
                  'difficulty': 'Sweet Spot',
                  'targetTss': 58,
                  'zwiftCategory': 'Sweet Spot',
                  'suggestedSearchTerms': ['SST Short', 'Emily Short Mix'],
                  'cadenceFocus': '88-92 rpm',
                  'notes': 'ERG mode recommended',
                },
                'brickRunLeg': null,
              },
              {
                'id': 'w1_sat_brick',
                'date': '2026-11-28',
                'title': 'Saturday Brick: Bike + Transition Run',
                'discipline': 'bike',
                'archetype': 'brick',
                'estimatedDurationMinutes': 120,
                'estimatedDistanceKm': null,
                'estimatedTss': 115,
                'coachNotes': 'Smooth T2 transition',
                'rationale': 'Race-specific bike-to-run neuromuscular adaptation',
                'blocks': [],
                'zwiftPrescription': {
                  'durationMinutes': 90,
                  'difficulty': 'Tempo',
                  'targetTss': 85,
                  'zwiftCategory': 'Tempo',
                  'suggestedSearchTerms': ['Tempo', 'Watopia Flat'],
                  'cadenceFocus': '85-90 rpm',
                  'notes': 'Steady tempo effort',
                },
                // Intentionally exceeds 30 min (45 min & 2700s of steps) to test cap!
                'brickRunLeg': {
                  'id': 'w1_sat_brick_run',
                  'title': 'T2 Transition Run',
                  'archetype': 'threshold',
                  'estimatedDurationMinutes': 45,
                  'estimatedDistanceKm': 8.0,
                  'estimatedTss': 35,
                  'coachNotes': 'Quick turnover',
                  'rationale': 'Run off fatigued quads',
                  'steps': [
                    {
                      'kind': 'steady',
                      'endCondition': 'time',
                      'endValue': 1800,
                      'targetKind': 'heartRateZone',
                      'targetLow': 2,
                      'targetHigh': 3,
                      'notes': 'Settle into rhythm',
                      'strokeType': null,
                    },
                    {
                      'kind': 'cooldown',
                      'endCondition': 'time',
                      'endValue': 900,
                      'targetKind': 'heartRateZone',
                      'targetLow': 1,
                      'targetHigh': 2,
                      'notes': 'Easy jog',
                      'strokeType': null,
                    },
                  ],
                },
              },
            ],
          },
        ],
      };

      final service = ChatGptService(
        client: MockClient((request) async {
          final reqBody = jsonDecode(request.body) as Map<String, dynamic>;
          expect(reqBody['text']['format']['type'], 'json_schema');
          expect(reqBody['text']['format']['strict'], isTrue);
          return http.Response(
            jsonEncode({
              'status': 'completed',
              'output': [
                {
                  'type': 'message',
                  'content': [
                    {
                      'type': 'output_text',
                      'text': '```json\n${jsonEncode(planJsonPayload)}\n```',
                    },
                  ],
                },
              ],
            }),
            200,
          );
        }),
      );

      final session = ChatGptSession(
        clientId: 'oaiapp_1',
        accessToken: 'tok',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      final config = _sampleConfig();

      final plan = await service.generateTrainingPlan(
        session: session,
        config: config,
        athleteContext: _sampleAthleteContext(),
      );

      expect(plan.config.raceName, config.raceName);
      expect(plan.weeks, hasLength(1));
      final workouts = plan.weeks.first.workouts;
      expect(workouts, hasLength(3));

      expect(workouts[0].archetype, WorkoutArchetype.intervals);
      expect(workouts[0].discipline, SportDiscipline.swim);
      expect(workouts[0].blocks, hasLength(2));

      expect(workouts[1].archetype, WorkoutArchetype.zwiftRide);
      expect(workouts[1].isGarminPushable, isFalse);
      expect(workouts[1].zwiftPrescription?.suggestedSearchTerms,
          contains('SST Short'));

      final brick = workouts[2];
      expect(brick.archetype, WorkoutArchetype.brick);
      expect(brick.isGarminPushable, isTrue);
      expect(brick.brickRunLeg, isNotNull);
      expect(brick.brickRunLeg!.estimatedDurationMinutes, lessThanOrEqualTo(30));
      expect(brick.brickRunLeg!.blocks, hasLength(2));

      var totalLegSec = 0.0;
      for (final b in brick.brickRunLeg!.blocks) {
        for (final s in b.effectiveSteps) {
          totalLegSec += s.endValue ?? 0.0;
        }
      }
      expect(totalLegSec, lessThanOrEqualTo(1800.0));
      expect(totalLegSec, closeTo(1800.0, 2.0));
    });

    test('generateTrainingPlan rejects empty weeks, unrecognized archetypes, and incompatible run/swim archetypes',
        () async {
      final session = ChatGptSession(
        clientId: 'oaiapp_1',
        accessToken: 'tok',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );

      Future<TrainingPlan> runWithPayload(Map<String, dynamic> payload) {
        final service = ChatGptService(
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'status': 'completed',
                'output_text': jsonEncode(payload),
              }),
              200,
            ),
          ),
        );
        return service.generateTrainingPlan(
          session: session,
          config: _sampleConfig(),
          athleteContext: _sampleAthleteContext(),
        );
      }

      // Empty weeks
      await expectLater(
        runWithPayload({
          'name': 'Empty',
          'coachOverview': 'None',
          'weeks': [],
        }),
        throwsA(isA<ChatGptApiException>()),
      );

      // Unrecognized raw archetype
      await expectLater(
        runWithPayload({
          'name': 'Bad Arch',
          'coachOverview': 'Overview',
          'weeks': [
            {
              'weekNumber': 1,
              'startDate': '2026-11-24',
              'phaseName': 'Base',
              'focusSummary': 'Focus',
              'targetHours': 5,
              'targetTss': 200,
              'workouts': [
                {
                  'id': 'w1',
                  'date': '2026-11-24',
                  'title': 'Mystery Session',
                  'discipline': 'run',
                  'archetype': 'super_sprint_mystery',
                  'estimatedDurationMinutes': 40,
                  'blocks': [],
                },
              ],
            },
          ],
        }),
        throwsA(isA<ChatGptApiException>()),
      );

      // Incompatible run + zwiftRide archetype
      await expectLater(
        runWithPayload({
          'name': 'Incompatible',
          'coachOverview': 'Overview',
          'weeks': [
            {
              'weekNumber': 1,
              'startDate': '2026-11-24',
              'phaseName': 'Base',
              'focusSummary': 'Focus',
              'targetHours': 5,
              'targetTss': 200,
              'workouts': [
                {
                  'id': 'w1',
                  'date': '2026-11-24',
                  'title': 'Zwift Run',
                  'discipline': 'run',
                  'archetype': 'zwiftRide',
                  'estimatedDurationMinutes': 40,
                  'blocks': [],
                },
              ],
            },
          ],
        }),
        throwsA(isA<ChatGptApiException>()),
      );

      // Incompatible run + strength / rest and swim + rest archetypes
      for (final badCase in [
        ('run', 'strength'),
        ('run', 'rest'),
        ('swim', 'restday'),
        ('swim', 'off'),
        ('swim', 'brick'),
      ]) {
        await expectLater(
          runWithPayload({
            'name': 'Incompatible ${badCase.$1} ${badCase.$2}',
            'coachOverview': 'Overview',
            'weeks': [
              {
                'weekNumber': 1,
                'startDate': '2026-11-24',
                'phaseName': 'Base',
                'focusSummary': 'Focus',
                'targetHours': 5,
                'targetTss': 200,
                'workouts': [
                  {
                    'id': 'w_bad_${badCase.$1}_${badCase.$2}',
                    'date': '2026-11-24',
                    'title': 'Bad Combo',
                    'discipline': badCase.$1,
                    'archetype': badCase.$2,
                    'estimatedDurationMinutes': 30,
                    'blocks': [],
                  },
                ],
              },
            ],
          }),
          throwsA(isA<ChatGptApiException>()),
        );
      }
    });

    test('generateTrainingPlan Brick run-leg overflow scaling never emits 0.0s timed steps and stays <= 1800s',
        () async {
      final session = ChatGptSession(
        clientId: 'oaiapp_1',
        accessToken: 'tok',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );

      final oneSecStep = {
        'kind': 'interval',
        'endCondition': 'time',
        'endValue': 1,
        'targetKind': 'none',
        'targetLow': null,
        'targetHigh': null,
        'notes': null,
        'strokeType': null,
      };

      final payload = {
        'name': 'Brick Scale Test',
        'coachOverview': 'Overview',
        'weeks': [
          {
            'weekNumber': 1,
            'startDate': '2026-11-24',
            'phaseName': 'Build',
            'focusSummary': 'Brick',
            'targetHours': 8,
            'targetTss': 400,
            'workouts': [
              {
                'id': 'w1_brick_micro',
                'date': '2026-11-28',
                'title': 'Micro-step Brick',
                'discipline': 'bike',
                'archetype': 'brick',
                'estimatedDurationMinutes': 120,
                'blocks': [],
                'zwiftPrescription': {
                  'durationMinutes': 90,
                  'difficulty': 'Tempo',
                  'targetTss': 80,
                  'zwiftCategory': 'Tempo',
                  'suggestedSearchTerms': ['Tempo'],
                  'cadenceFocus': null,
                  'notes': null,
                },
                'brickRunLeg': {
                  'id': 'w1_brick_micro_run',
                  'title': 'Micro-step Run Leg',
                  'archetype': 'intervals',
                  'estimatedDurationMinutes': 40,
                  'blocks': [
                    {
                      'repeatCount': 100,
                      'step': null,
                      'steps': List.generate(20, (_) => Map.of(oneSecStep)),
                    },
                  ],
                },
              },
            ],
          },
        ],
      };

      final service = ChatGptService(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'status': 'completed',
              'output_text': jsonEncode(payload),
            }),
            200,
          ),
        ),
      );

      final plan = await service.generateTrainingPlan(
        session: session,
        config: _sampleConfig(),
        athleteContext: _sampleAthleteContext(),
      );

      final leg = plan.weeks.single.workouts.single.brickRunLeg!;
      expect(leg.estimatedDurationMinutes, lessThanOrEqualTo(30));

      var totalTimedSeconds = 0.0;
      var zeroSecSteps = 0;
      for (final block in leg.blocks) {
        final repeats = block.repeatCount > 1 ? block.repeatCount : 1;
        for (final step in block.effectiveSteps) {
          if (step.endCondition == StepEndCondition.time) {
            final v = step.endValue ?? 0.0;
            if (v < 1.0) zeroSecSteps++;
            totalTimedSeconds += v * repeats;
          }
        }
      }
      expect(zeroSecSteps, 0);
      expect(totalTimedSeconds, lessThanOrEqualTo(1800.0));
      expect(totalTimedSeconds, greaterThan(0.0));
    });

    test('generateTrainingPlan scales repeatCount=1 block with both step (>1800s) and steps without deleting block',
        () async {
      final session = ChatGptSession(
        clientId: 'oaiapp_1',
        accessToken: 'tok',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );

      final payload = {
        'name': 'Brick Both Step And Steps Test',
        'coachOverview': 'Overview',
        'weeks': [
          {
            'weekNumber': 1,
            'startDate': '2026-11-24',
            'phaseName': 'Build',
            'focusSummary': 'Brick',
            'targetHours': 8,
            'targetTss': 400,
            'workouts': [
              {
                'id': 'w1_brick_both',
                'date': '2026-11-28',
                'title': 'Brick With Step and Steps',
                'discipline': 'bike',
                'archetype': 'brick',
                'estimatedDurationMinutes': 100,
                'blocks': [],
                'zwiftPrescription': {
                  'durationMinutes': 70,
                  'difficulty': 'Tempo',
                  'targetTss': 70,
                  'zwiftCategory': 'Tempo',
                  'suggestedSearchTerms': ['Tempo'],
                  'cadenceFocus': null,
                  'notes': null,
                },
                'brickRunLeg': {
                  'id': 'w1_brick_both_run',
                  'title': 'Transition Run',
                  'archetype': 'easy',
                  'estimatedDurationMinutes': 0,
                  'blocks': [
                    {
                      'repeatCount': 1,
                      'step': {
                        'kind': 'steady',
                        'endCondition': 'time',
                        'endValue': 2000,
                        'targetKind': 'none',
                        'targetLow': null,
                        'targetHigh': null,
                        'notes': 'Primary step',
                        'strokeType': null,
                      },
                      'steps': [
                        {
                          'kind': 'interval',
                          'endCondition': 'time',
                          'endValue': 100,
                          'targetKind': 'none',
                          'targetLow': null,
                          'targetHigh': null,
                          'notes': 'Ignored by effectiveSteps',
                          'strokeType': null,
                        },
                        {
                          'kind': 'recovery',
                          'endCondition': 'time',
                          'endValue': 100,
                          'targetKind': 'none',
                          'targetLow': null,
                          'targetHigh': null,
                          'notes': 'Ignored by effectiveSteps',
                          'strokeType': null,
                        },
                      ],
                    },
                  ],
                },
              },
            ],
          },
        ],
      };

      final service = ChatGptService(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'status': 'completed',
              'output_text': jsonEncode(payload),
            }),
            200,
          ),
        ),
      );

      final plan = await service.generateTrainingPlan(
        session: session,
        config: _sampleConfig(),
        athleteContext: _sampleAthleteContext(),
      );

      final leg = plan.weeks.single.workouts.single.brickRunLeg!;
      expect(leg.blocks, hasLength(1));
      expect(leg.blocks.single.step, isNotNull);
      expect(leg.blocks.single.steps, isEmpty);
      expect(leg.blocks.single.effectiveSteps, hasLength(1));
      expect(leg.blocks.single.effectiveSteps.single.endValue, 1800.0);
      expect(leg.estimatedDurationMinutes, 30);
    });

    test('generateTrainingPlan rejects incompatible brickRunLeg archetypes',
        () async {
      final session = ChatGptSession(
        clientId: 'oaiapp_1',
        accessToken: 'tok',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );

      for (final badArch in ['strength', 'rest', 'zwiftRide', 'brick']) {
        final payload = {
          'name': 'Bad Brick Leg Arch',
          'coachOverview': 'Overview',
          'weeks': [
            {
              'weekNumber': 1,
              'startDate': '2026-11-24',
              'phaseName': 'Build',
              'focusSummary': 'Brick',
              'targetHours': 8,
              'targetTss': 400,
              'workouts': [
                {
                  'id': 'w1_brick_bad_leg',
                  'date': '2026-11-28',
                  'title': 'Bad Brick Leg',
                  'discipline': 'bike',
                  'archetype': 'brick',
                  'estimatedDurationMinutes': 90,
                  'blocks': [],
                  'brickRunLeg': {
                    'id': 'w1_brick_bad_leg_run',
                    'title': 'Invalid Leg',
                    'archetype': badArch,
                    'estimatedDurationMinutes': 20,
                    'blocks': [],
                  },
                },
              ],
            },
          ],
        };

        final service = ChatGptService(
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'status': 'completed',
                'output_text': jsonEncode(payload),
              }),
              200,
            ),
          ),
        );

        await expectLater(
          service.generateTrainingPlan(
            session: session,
            config: _sampleConfig(),
            athleteContext: _sampleAthleteContext(),
          ),
          throwsA(isA<ChatGptApiException>()),
        );
      }
    });

    test('adaptTrainingPlan preserves past, completed, and skipped workouts even if LLM mutates or omits them',
        () async {
      final config = _sampleConfig();
      final syncedAt = DateTime.utc(2026, 11, 20, 8, 0);
      final completedWorkout = PlannedWorkout(
        id: 'w1_mon_run',
        date: '2026-11-23',
        title: 'Easy Aerobic Run',
        discipline: SportDiscipline.run,
        archetype: WorkoutArchetype.easy,
        estimatedDurationMinutes: 40,
        status: WorkoutStatus.completed,
        matchedActivityId: 'garmin_act_777',
        adherencePercent: 96.5,
        garminWorkoutId: 'gw_111',
        garminScheduleId: 'gs_222',
        garminSyncedAt: syncedAt,
        blocks: const [
          WorkoutBlock(
            repeatCount: 1,
            step: WorkoutStep(
              kind: StepKind.steady,
              endCondition: StepEndCondition.time,
              endValue: 2400,
              targetKind: StepTargetKind.heartRateZone,
              targetLow: 2,
              targetHigh: 2,
            ),
          ),
        ],
      );
      final skippedWorkout = PlannedWorkout(
        id: 'w1_tue_swim',
        date: '2026-11-24',
        title: 'Threshold Swim',
        discipline: SportDiscipline.swim,
        archetype: WorkoutArchetype.threshold,
        estimatedDurationMinutes: 45,
        status: WorkoutStatus.skipped,
      );
      final pastScheduledWorkout = PlannedWorkout(
        id: 'w1_wed_run',
        date: '2026-11-25',
        title: 'Run Intervals',
        discipline: SportDiscipline.run,
        archetype: WorkoutArchetype.intervals,
        estimatedDurationMinutes: 50,
        status: WorkoutStatus.scheduled,
      );
      final todayCompletedWorkout = PlannedWorkout(
        id: 'w2_thu_run',
        date: '2026-11-26',
        title: 'Morning Easy Run (Done)',
        discipline: SportDiscipline.run,
        archetype: WorkoutArchetype.easy,
        estimatedDurationMinutes: 35,
        status: WorkoutStatus.completed,
        matchedActivityId: 'garmin_act_888',
        adherencePercent: 100.0,
      );
      final futureWorkout = PlannedWorkout(
        id: 'w2_sat_brick',
        date: '2026-11-28',
        title: 'Original Saturday Brick',
        discipline: SportDiscipline.bike,
        archetype: WorkoutArchetype.brick,
        estimatedDurationMinutes: 100,
        status: WorkoutStatus.scheduled,
      );

      final existingPlan = TrainingPlan(
        id: 'plan_existing_1',
        name: 'Oceanside 70.3',
        createdAt: DateTime.utc(2026, 11, 20),
        updatedAt: DateTime.utc(2026, 11, 23),
        config: config,
        coachOverview: 'Initial plan',
        weeks: [
          TrainingWeek(
            weekNumber: 1,
            startDate: '2026-11-23',
            phaseName: 'Base',
            focusSummary: 'Week 1',
            targetHours: 7.0,
            targetTss: 350,
            workouts: [completedWorkout, skippedWorkout, pastScheduledWorkout],
          ),
          TrainingWeek(
            weekNumber: 2,
            startDate: '2026-11-26',
            phaseName: 'Base',
            focusSummary: 'Week 2',
            targetHours: 7.5,
            targetTss: 380,
            workouts: [todayCompletedWorkout, futureWorkout],
          ),
        ],
      );

      // Adversarial mock LLM: omits Week 1, tries to overwrite today's completed
      // workout with a brand-new ID on 2026-11-26, and adapts 2026-11-28.
      final llmAdaptedPayload = {
        'name': 'Oceanside 70.3 Adapted',
        'coachOverview': 'Reduced load after missed swim.',
        'weeks': [
          {
            'weekNumber': 2,
            'startDate': '2026-11-26',
            'phaseName': 'Base Adjusted',
            'focusSummary': 'Adapted Week 2',
            'targetHours': 6.5,
            'targetTss': 320,
            'workouts': [
              {
                'id': 'llm_overwrite_thu',
                'date': '2026-11-26',
                'title': 'LLM Tried To Overwrite Completed Run',
                'discipline': 'run',
                'archetype': 'intervals',
                'estimatedDurationMinutes': 60,
                'blocks': [],
              },
              {
                'id': 'w2_sat_brick_adapted',
                'date': '2026-11-28',
                'title': 'Adapted Saturday Brick',
                'discipline': 'bike',
                'archetype': 'brick',
                'estimatedDurationMinutes': 85,
                'zwiftPrescription': {
                  'durationMinutes': 65,
                  'difficulty': 'Endurance',
                  'targetTss': 55,
                  'zwiftCategory': 'Endurance',
                  'suggestedSearchTerms': ['Endurance'],
                  'cadenceFocus': null,
                  'notes': null,
                },
                'brickRunLeg': {
                  'id': 'w2_sat_brick_adapted_run',
                  'title': 'Short T2 Run',
                  'archetype': 'easy',
                  'estimatedDurationMinutes': 40, // Should be capped <= 30
                  'steps': [
                    {
                      'kind': 'steady',
                      'endCondition': 'time',
                      'endValue': 2400, // Should be scaled <= 1800
                      'targetKind': 'none',
                      'targetLow': null,
                      'targetHigh': null,
                      'notes': null,
                      'strokeType': null,
                    },
                  ],
                },
                'blocks': [],
              },
            ],
          },
        ],
      };

      final service = ChatGptService(
        client: MockClient((request) async {
          final reqBody = jsonDecode(request.body) as Map<String, dynamic>;
          final userMsg = (reqBody['input'] as List).last['content'] as String;
          expect(userMsg, contains('Knee feels slightly tight'));
          expect(userMsg, contains('w1_mon_run'));

          return http.Response(
            jsonEncode({
              'status': 'completed',
              'output_text': jsonEncode(llmAdaptedPayload),
            }),
            200,
          );
        }),
      );

      final session = ChatGptSession(
        clientId: 'oaiapp_1',
        accessToken: 'tok',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );

      final adapted = await service.adaptTrainingPlan(
        session: session,
        existingPlan: existingPlan,
        athleteContext: _sampleAthleteContext(
          adherence: const PlanAdherenceSummary(
            totalDue: 3,
            completed: 1,
            skipped: 1,
            missedOrPending: 1,
            avgAdherencePercent: 96.5,
          ),
        ),
        referenceDate: DateTime(2026, 11, 26),
        userFeedback: 'Knee feels slightly tight after yesterday.',
      );

      expect(adapted.id, existingPlan.id);
      expect(adapted.createdAt, existingPlan.createdAt);
      expect(adapted.weeks, hasLength(2));

      // Week 1 preserved verbatim even though LLM omitted it.
      final w1 = adapted.weeks[0];
      expect(w1.weekNumber, 1);
      expect(w1.workouts, hasLength(3));
      expect(w1.workouts[0].id, 'w1_mon_run');
      expect(w1.workouts[0].status, WorkoutStatus.completed);
      expect(w1.workouts[0].matchedActivityId, 'garmin_act_777');
      expect(w1.workouts[0].adherencePercent, 96.5);
      expect(w1.workouts[0].garminWorkoutId, 'gw_111');
      expect(w1.workouts[0].garminScheduleId, 'gs_222');
      expect(w1.workouts[0].garminSyncedAt, syncedAt);
      expect(w1.workouts[0].blocks.single.step?.endValue, 2400);
      expect(w1.workouts[1].id, 'w1_tue_swim');
      expect(w1.workouts[1].status, WorkoutStatus.skipped);
      expect(w1.workouts[2].id, 'w1_wed_run');

      // Week 2 preserved completed 2026-11-26 workout & adapted 2026-11-28 brick.
      final w2 = adapted.weeks[1];
      expect(w2.weekNumber, 2);
      expect(w2.workouts, hasLength(2));
      expect(w2.workouts[0].id, 'w2_thu_run');
      expect(w2.workouts[0].matchedActivityId, 'garmin_act_888');
      expect(w2.workouts[1].id, 'w2_sat_brick_adapted');
      expect(
        w2.workouts[1].brickRunLeg!.estimatedDurationMinutes,
        lessThanOrEqualTo(30),
      );
      expect(
        w2.workouts[1].brickRunLeg!.blocks.single.step!.endValue,
        lessThanOrEqualTo(1800.0),
      );
    });

    test('adaptTrainingPlan preserves same-day double-session with shared archetype across sports',
        () async {
      final config = _sampleConfig();
      final existingPlan = TrainingPlan(
        id: 'plan_double_session',
        name: 'Double Session Test',
        createdAt: DateTime.utc(2026, 11, 20),
        updatedAt: DateTime.utc(2026, 11, 25),
        config: config,
        coachOverview: 'Initial',
        weeks: [
          TrainingWeek(
            weekNumber: 1,
            startDate: '2026-11-23',
            phaseName: 'Base',
            focusSummary: 'Week 1',
            targetHours: 8.0,
            targetTss: 400,
            workouts: [
              PlannedWorkout(
                id: 'w1_am_swim',
                date: '2026-11-26',
                title: 'Morning Easy Swim',
                discipline: SportDiscipline.swim,
                archetype: WorkoutArchetype.easy,
                estimatedDurationMinutes: 40,
                status: WorkoutStatus.completed,
                matchedActivityId: 'act_swim_1',
                adherencePercent: 100.0,
              ),
              PlannedWorkout(
                id: 'w1_pm_run',
                date: '2026-11-26',
                title: 'Original Afternoon Run',
                discipline: SportDiscipline.run,
                archetype: WorkoutArchetype.easy,
                estimatedDurationMinutes: 45,
                status: WorkoutStatus.scheduled,
              ),
            ],
          ),
        ],
      );

      final llmPayload = {
        'name': 'Double Session Test',
        'coachOverview': 'Adapted afternoon run',
        'weeks': [
          {
            'weekNumber': 1,
            'startDate': '2026-11-23',
            'phaseName': 'Base',
            'focusSummary': 'Adapted Week 1',
            'targetHours': 7.5,
            'targetTss': 375,
            'workouts': [
              {
                'id': 'w1_pm_run_adapted',
                'date': '2026-11-26',
                'title': 'Adapted Afternoon Easy Run',
                'discipline': 'run',
                'archetype': 'easy',
                'estimatedDurationMinutes': 30,
                'blocks': [],
              },
            ],
          },
        ],
      };

      final service = ChatGptService(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'status': 'completed',
              'output_text': jsonEncode(llmPayload),
            }),
            200,
          ),
        ),
      );
      final session = ChatGptSession(
        clientId: 'oaiapp_1',
        accessToken: 'tok',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );

      final adapted = await service.adaptTrainingPlan(
        session: session,
        existingPlan: existingPlan,
        athleteContext: _sampleAthleteContext(),
        referenceDate: DateTime(2026, 11, 26),
      );

      expect(adapted.weeks, hasLength(1));
      final workouts = adapted.weeks.single.workouts;
      expect(workouts, hasLength(2));
      expect(workouts.map((w) => w.id), containsAll(['w1_am_swim', 'w1_pm_run_adapted']));
    });

    test('adaptTrainingPlan matches weeks by startDate/window when LLM renumbers remaining weeks starting at 1',
        () async {
      final config = _sampleConfig();
      final existingPlan = TrainingPlan(
        id: 'plan_week_match',
        name: 'Week Match Test',
        createdAt: DateTime.utc(2026, 11, 15),
        updatedAt: DateTime.utc(2026, 11, 25),
        config: config,
        coachOverview: 'Initial',
        weeks: [
          TrainingWeek(
            weekNumber: 1,
            startDate: '2026-11-16',
            phaseName: 'Base 1',
            focusSummary: 'Past Week 1',
            targetHours: 7.0,
            targetTss: 350,
            workouts: [
              PlannedWorkout(
                id: 'w1_mon_done',
                date: '2026-11-16',
                title: 'Week 1 Completed Run',
                discipline: SportDiscipline.run,
                archetype: WorkoutArchetype.easy,
                estimatedDurationMinutes: 40,
                status: WorkoutStatus.completed,
              ),
            ],
          ),
          TrainingWeek(
            weekNumber: 2,
            startDate: '2026-11-23',
            phaseName: 'Base 2',
            focusSummary: 'Current Week 2',
            targetHours: 8.0,
            targetTss: 400,
            workouts: [
              PlannedWorkout(
                id: 'w2_sat_old',
                date: '2026-11-28',
                title: 'Old Week 2 Saturday Run',
                discipline: SportDiscipline.run,
                archetype: WorkoutArchetype.long,
                estimatedDurationMinutes: 75,
                status: WorkoutStatus.scheduled,
              ),
            ],
          ),
        ],
      );

      // LLM omits Week 1 and renumbers remaining Week 2 as weekNumber: 1.
      final llmPayload = {
        'name': 'Week Match Test',
        'coachOverview': 'Rebalanced remaining week',
        'weeks': [
          {
            'weekNumber': 1,
            'startDate': '2026-11-23',
            'phaseName': 'Base 2 Adapted',
            'focusSummary': 'Adapted Week 2',
            'targetHours': 6.5,
            'targetTss': 320,
            'workouts': [
              {
                'id': 'w2_sat_adapted',
                'date': '2026-11-28',
                'title': 'Adapted Week 2 Saturday Run',
                'discipline': 'run',
                'archetype': 'easy',
                'estimatedDurationMinutes': 50,
                'blocks': [],
              },
            ],
          },
        ],
      };

      late String capturedInstructions;
      final service = ChatGptService(
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          capturedInstructions = body['instructions'] as String;
          return http.Response(
            jsonEncode({
              'status': 'completed',
              'output_text': jsonEncode(llmPayload),
            }),
            200,
          );
        }),
      );
      final session = ChatGptSession(
        clientId: 'oaiapp_1',
        accessToken: 'tok',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );

      final adapted = await service.adaptTrainingPlan(
        session: session,
        existingPlan: existingPlan,
        athleteContext: _sampleAthleteContext(),
        referenceDate: DateTime(2026, 11, 26),
      );

      expect(capturedInstructions, contains('weekNumber'));
      expect(capturedInstructions, contains('startDate'));

      expect(adapted.weeks, hasLength(2));
      expect(adapted.weeks[0].weekNumber, 1);
      expect(adapted.weeks[0].startDate, '2026-11-16');
      expect(adapted.weeks[0].workouts.map((w) => w.id), ['w1_mon_done']);

      expect(adapted.weeks[1].weekNumber, 2);
      expect(adapted.weeks[1].startDate, '2026-11-23');
      expect(adapted.weeks[1].workouts.map((w) => w.id), ['w2_sat_adapted']);
    });

    test('adaptTrainingPlan sorts omitted historical week with empty startDate chronologically before future weeks',
        () async {
      final config = _sampleConfig();
      final existingPlan = TrainingPlan(
        id: 'plan_empty_start',
        name: 'Empty Start Date Test',
        createdAt: DateTime.utc(2026, 11, 1),
        updatedAt: DateTime.utc(2026, 11, 10),
        config: config,
        coachOverview: 'Initial',
        weeks: [
          TrainingWeek(
            weekNumber: 1,
            startDate: '',
            phaseName: 'Base 1',
            focusSummary: 'Past Week Without Start Date',
            targetHours: 6.0,
            targetTss: 300,
            workouts: [
              PlannedWorkout(
                id: 'w1_past',
                date: '2026-11-03',
                title: 'Past Completed Run',
                discipline: SportDiscipline.run,
                archetype: WorkoutArchetype.easy,
                estimatedDurationMinutes: 35,
                status: WorkoutStatus.completed,
              ),
            ],
          ),
          TrainingWeek(
            weekNumber: 2,
            startDate: '2026-11-16',
            phaseName: 'Base 2',
            focusSummary: 'Future Week',
            targetHours: 7.0,
            targetTss: 350,
            workouts: [
              PlannedWorkout(
                id: 'w2_old',
                date: '2026-11-18',
                title: 'Old Future Run',
                discipline: SportDiscipline.run,
                archetype: WorkoutArchetype.easy,
                estimatedDurationMinutes: 45,
                status: WorkoutStatus.scheduled,
              ),
            ],
          ),
        ],
      );

      final llmPayload = {
        'name': 'Empty Start Date Test',
        'coachOverview': 'Updated future week',
        'weeks': [
          {
            'weekNumber': 1,
            'startDate': '2026-11-16',
            'phaseName': 'Base 2 Adapted',
            'focusSummary': 'Updated Future Week',
            'targetHours': 6.5,
            'targetTss': 320,
            'workouts': [
              {
                'id': 'w2_new',
                'date': '2026-11-18',
                'title': 'Adapted Future Run',
                'discipline': 'run',
                'archetype': 'threshold',
                'estimatedDurationMinutes': 50,
                'blocks': [],
              },
            ],
          },
        ],
      };

      final service = ChatGptService(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'status': 'completed',
              'output_text': jsonEncode(llmPayload),
            }),
            200,
          ),
        ),
      );
      final session = ChatGptSession(
        clientId: 'oaiapp_1',
        accessToken: 'tok',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );

      final adapted = await service.adaptTrainingPlan(
        session: session,
        existingPlan: existingPlan,
        athleteContext: _sampleAthleteContext(),
        referenceDate: DateTime(2026, 11, 15),
      );

      expect(adapted.weeks, hasLength(2));
      expect(adapted.weeks[0].weekNumber, 1);
      expect(adapted.weeks[0].startDate, '2026-11-03');
      expect(adapted.weeks[0].workouts.map((w) => w.id), ['w1_past']);

      expect(adapted.weeks[1].weekNumber, 2);
      expect(adapted.weeks[1].startDate, '2026-11-16');
      expect(adapted.weeks[1].workouts.map((w) => w.id), ['w2_new']);
    });

    test('waitForOAuthCode handles OAuth error param, timeout, and onServerReady failure cleanly',
        () async {
      final service = ChatGptService(
        client: MockClient((_) async => http.Response('', 200)),
      );

      // OAuth error query param & HTML-escaped callback response
      late String errorHtmlBody;
      await expectLater(
        service.waitForOAuthCode(
          port: 0,
          expectedState: 'st_err',
          timeout: const Duration(seconds: 5),
          onServerReady: (redirectUri) async {
            final httpClient = HttpClient();
            try {
              final req = await httpClient.getUrl(
                Uri.parse(
                  '$redirectUri?error=access_denied&error_description=${Uri.encodeQueryComponent('<script>alert("xss")</script> User denied')}&state=st_err',
                ),
              );
              final res = await req.close();
              errorHtmlBody = await utf8.decoder.bind(res).join();
            } finally {
              httpClient.close(force: true);
            }
          },
        ),
        throwsA(
          isA<ChatGptAuthException>().having(
            (e) => e.message,
            'message',
            contains('User denied'),
          ),
        ),
      );
      expect(errorHtmlBody, isNot(contains('<script>')));
      expect(errorHtmlBody, contains('&lt;script&gt;'));

      // Timeout closes server
      await expectLater(
        service.waitForOAuthCode(
          port: 0,
          expectedState: 'st_timeout',
          timeout: const Duration(milliseconds: 50),
        ),
        throwsA(
          isA<ChatGptAuthException>().having(
            (e) => e.message,
            'message',
            contains('Timed out'),
          ),
        ),
      );

      // onServerReady throws
      await expectLater(
        service.waitForOAuthCode(
          port: 0,
          expectedState: 'st_boom',
          timeout: const Duration(seconds: 5),
          onServerReady: (_) async => throw StateError('Browser unavailable'),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('exchangeAuthorizationCode and refreshToken reject error status and invalid session',
        () async {
      final errService = ChatGptService(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'error': 'invalid_grant',
              'error_description': 'Code expired',
            }),
            400,
          ),
        ),
      );

      await expectLater(
        errService.exchangeAuthorizationCode(
          clientId: 'oaiapp_1',
          code: 'expired_code',
          codeVerifier: 'verifier',
          redirectUri: 'http://127.0.0.1:1455/callback',
        ),
        throwsA(
          isA<ChatGptAuthException>().having(
            (e) => e.message,
            'message',
            contains('Code expired'),
          ),
        ),
      );

      final noRefreshSession = ChatGptSession(
        clientId: 'oaiapp_1',
        accessToken: 'tok',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      await expectLater(
        errService.refreshToken(noRefreshSession),
        throwsA(isA<ChatGptAuthException>()),
      );
    });
  });
}
