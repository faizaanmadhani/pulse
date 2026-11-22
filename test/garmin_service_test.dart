import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pulse_training_hub/models/activity.dart';
import 'package:pulse_training_hub/services/garmin_auth_store.dart';
import 'package:pulse_training_hub/services/garmin_service.dart';

void main() {
  group('OAuth1Signer', () {
    test('percentEncode encodes RFC 5849 reserved characters', () {
      expect(OAuth1Signer.percentEncode("a!b*c'd(e)f"), 'a%21b%2Ac%27d%28e%29f');
    });

    test('buildAuthorizationHeader produces deterministic HMAC-SHA1 header', () {
      final header = OAuth1Signer.buildAuthorizationHeader(
        method: 'GET',
        url: Uri.parse('https://connectapi.garmin.com/oauth-service/oauth/preauthorized?ticket=ST-123'),
        consumerKey: 'ckey',
        consumerSecret: 'csecret',
        nonce: 'fixednonce',
        timestamp: '1700000000',
      );

      expect(header, startsWith('OAuth '));
      expect(header, contains('oauth_consumer_key="ckey"'));
      expect(header, contains('oauth_nonce="fixednonce"'));
      expect(header, contains('oauth_signature_method="HMAC-SHA1"'));
      expect(header, contains('oauth_timestamp="1700000000"'));
      expect(header, contains('oauth_version="1.0"'));
      expect(header, contains('oauth_signature="'));
    });
  });

  group('GarminService authentication', () {
    test('rejects empty email or password', () async {
      final service = GarminService(
        client: MockClient((_) async => http.Response('', 200)),
      );
      expect(
        () => service.login(email: '', password: 'secret'),
        throwsA(isA<GarminAuthException>()),
      );
      expect(
        () => service.login(email: 'user@example.com', password: ''),
        throwsA(isA<GarminAuthException>()),
      );
    });

    test('completes full SSO -> OAuth1 -> OAuth2 login flow', () async {
      final mockClient = MockClient((request) async {
        final url = request.url.toString();
        if (url.contains('oauth_consumer.json')) {
          return http.Response(
            jsonEncode({'consumer_key': 'test_ck', 'consumer_secret': 'test_cs'}),
            200,
          );
        }
        if (url.contains('/sso/embed')) {
          return http.Response('<html></html>', 200, headers: {
            'set-cookie': 'SESSION=abc123; Path=/; HttpOnly',
          });
        }
        if (url.contains('/sso/signin') && request.method == 'GET') {
          return http.Response(
            '<form><input type="hidden" name="_csrf" value="csrf_tok_1"></form>',
            200,
          );
        }
        if (url.contains('/sso/signin') && request.method == 'POST') {
          expect(request.bodyFields['username'], 'runner@example.com');
          expect(request.bodyFields['password'], 'pw123');
          expect(request.bodyFields['_csrf'], 'csrf_tok_1');
          return http.Response(
            '<html><head><title>Success</title></head><body><a href="https://sso.garmin.com/sso/embed?ticket=ST-99999-abc">ok</a></body></html>',
            200,
          );
        }
        if (url.contains('/oauth/preauthorized')) {
          expect(request.headers['Authorization'], startsWith('OAuth '));
          return http.Response(
            'oauth_token=o1_tok&oauth_token_secret=o1_sec',
            200,
          );
        }
        if (url.contains('/oauth/exchange/user/2.0')) {
          expect(request.headers['Authorization'], contains('oauth_token="o1_tok"'));
          return http.Response(
            jsonEncode({
              'access_token': 'bearer_xyz',
              'refresh_token': 'ref_xyz',
              'expires_in': 3600,
            }),
            200,
          );
        }
        return http.Response('Not found: $url', 404);
      });

      final service = GarminService(client: mockClient);
      final result = await service.login(email: 'runner@example.com', password: 'pw123');

      expect(result.requiresMfa, isFalse);
      expect(result.session, isNotNull);
      expect(result.session!.accessToken, 'bearer_xyz');
      expect(result.session!.oauth1Token, 'o1_tok');
    });

    test('handles MFA challenge and completes verification', () async {
      final mockClient = MockClient((request) async {
        final url = request.url.toString();
        if (url.contains('oauth_consumer.json')) {
          return http.Response(
            jsonEncode({'consumer_key': 'ck', 'consumer_secret': 'cs'}),
            200,
          );
        }
        if (url.contains('/sso/embed')) {
          return http.Response('', 200);
        }
        if (url.contains('/sso/signin') && request.method == 'GET') {
          return http.Response('<input name="_csrf" value="c1">', 200);
        }
        if (url.contains('/sso/signin') && request.method == 'POST') {
          return http.Response(
            '<html><head><title>GARMIN > MFA</title></head><body><input name="_csrf" value="c2"></body></html>',
            200,
          );
        }
        if (url.contains('/verifyMFA/loginEnterMfaCode')) {
          expect(request.bodyFields['mfa-code'], '654321');
          expect(request.bodyFields['_csrf'], 'c2');
          return http.Response(
            '<html><head><title>Success</title></head><body>embed?ticket=ST-MFA-777</body></html>',
            200,
          );
        }
        if (url.contains('/oauth/preauthorized')) {
          return http.Response('oauth_token=o1_mfa&oauth_token_secret=o1_mfa_sec&mfa_token=mt1', 200);
        }
        if (url.contains('/oauth/exchange/user/2.0')) {
          return http.Response(
            jsonEncode({'access_token': 'bearer_mfa', 'expires_in': 3600}),
            200,
          );
        }
        return http.Response('Unexpected $url', 404);
      });

      final service = GarminService(client: mockClient);
      final loginRes = await service.login(email: 'a@b.com', password: 'pw');
      expect(loginRes.requiresMfa, isTrue);

      final session = await service.submitMfaCode(
        challenge: loginRes.mfaChallenge!,
        mfaCode: '654321',
      );
      expect(session.accessToken, 'bearer_mfa');
      expect(session.mfaToken, 'mt1');
    });

    test('surfaces clear error on invalid credentials and rate limit', () async {
      final invalidClient = MockClient((request) async {
        final url = request.url.toString();
        if (url.contains('oauth_consumer.json')) {
          return http.Response(jsonEncode({'consumer_key': 'ck', 'consumer_secret': 'cs'}), 200);
        }
        if (url.contains('/sso/signin') && request.method == 'GET') {
          return http.Response('<input name="_csrf" value="c1">', 200);
        }
        if (url.contains('/sso/signin') && request.method == 'POST') {
          return http.Response('<html><head><title>GARMIN Sign In</title></head></html>', 429);
        }
        return http.Response('', 200);
      });

      final service = GarminService(client: invalidClient);
      expect(
        () => service.login(email: 'a@b.com', password: 'wrong'),
        throwsA(isA<GarminAuthException>().having((e) => e.message, 'message', contains('rate-limited'))),
      );
    });
  });

  group('GarminService data parsing & TrainingLoadCalculator', () {
    final fakeSession = GarminSession(
      oauth1Token: 'o1',
      oauth1TokenSecret: 'o1s',
      accessToken: 'acc',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
      consumerKey: 'ck',
      consumerSecret: 'cs',
    );

    test('parses real Garmin activity payloads across disciplines', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/search/activities')) {
          return http.Response(
            jsonEncode([
              {
                'activityId': 101,
                'activityName': 'Morning Tempo Run',
                'activityType': {'typeKey': 'running'},
                'startTimeLocal': '2026-11-20 07:30:00',
                'distance': 10000.0,
                'duration': 2700.0,
                'movingDuration': 2680.0,
                'averageSpeed': 3.7037,
                'maxSpeed': 4.5,
                'averageHR': 155,
                'maxHR': 174,
                'elevationGain': 85.0,
                'calories': 680,
                'averageRunningCadenceInStepsPerMinute': 176,
                'avgGroundContactTime': 224,
                'avgVerticalOscillation': 82.0,
                'avgStrideLength': 121.0,
                'locationName': 'Central Park',
                'activityTrainingLoad': 88.0,
              },
              {
                'activityId': 102,
                'activityName': 'Pool Swim',
                'activityType': {'typeKey': 'lap_swimming'},
                'startTimeLocal': '2026-11-19 06:15:00',
                'distance': 2000.0,
                'duration': 2100.0,
                'averageSpeed': 1.0,
                'averageHR': 138,
                'averageSwolf': 35,
                'calories': 450,
              },
            ]),
            200,
          );
        }
        return http.Response('[]', 200);
      });

      final service = GarminService(client: mockClient);
      final acts = await service.fetchActivities(fakeSession);

      expect(acts.length, 2);
      expect(acts[0].id, '101');
      expect(acts[0].discipline, SportDiscipline.run);
      expect(acts[0].distanceKm, 10.0);
      expect(acts[0].avgSpeedOrPace, '4:30 /km');
      expect(acts[0].runningDynamics?.groundContactTimeMs, 224);
      expect(acts[0].runningDynamics?.verticalOscillationCm, 8.2);
      expect(acts[0].runningDynamics?.strideLengthM, 1.21);

      expect(acts[1].discipline, SportDiscipline.swim);
      expect(acts[1].swolf, 35);
      expect(acts[1].avgSpeedOrPace, '1:40 /100m');

      final load = TrainingLoadCalculator.computeFromActivities(acts, now: DateTime(2026, 11, 21));
      expect(load.pmcSeries.length, 42);
      expect(load.ctl, greaterThan(0));
      expect(load.atl, greaterThan(0));
      expect(load.acwr, isNotNull);
    });

    test('TrainingLoadCalculator handles empty activity list cleanly', () {
      final load = TrainingLoadCalculator.computeFromActivities(const []);
      expect(load.pmcSeries, isEmpty);
      expect(load.ctl, isNull);
      expect(load.atl, isNull);
      expect(load.acwr, isNull);
    });

    test('TrainingLoadCalculator computes CTL, ATL, TSB across multi-year history', () {
      final now = DateTime(2026, 11, 21);
      final oldActivity = Activity(
        id: 'old-1',
        title: 'Old Marathon Build',
        description: '',
        discipline: SportDiscipline.run,
        timestamp: DateTime(2024, 6, 1, 8, 0),
        formattedDate: 'Jun 1, 2024',
        location: 'Boston',
        deviceHardware: 'Forerunner 965',
        sensorChain: '',
        distanceKm: 20.0,
        durationSeconds: 5400,
        movingTime: '1h 30m',
        elapsedTime: '1h 30m',
        avgSpeedOrPace: '4:30 /km',
        maxSpeedOrPace: '4:00 /km',
        avgHr: 155,
        maxHr: 175,
        elevationGainM: 120,
        elevationLossM: 120,
        tss: 120,
        calories: 1200,
        avgCadence: 178,
        maxCadence: 190,
      );
      final recentActivity = Activity(
        id: 'recent-1',
        title: 'Recent Tempo',
        description: '',
        discipline: SportDiscipline.run,
        timestamp: DateTime(2026, 11, 20, 8, 0),
        formattedDate: 'Nov 20, 2026',
        location: 'Boston',
        deviceHardware: 'Forerunner 965',
        sensorChain: '',
        distanceKm: 10.0,
        durationSeconds: 2700,
        movingTime: '45m',
        elapsedTime: '45m',
        avgSpeedOrPace: '4:30 /km',
        maxSpeedOrPace: '4:00 /km',
        avgHr: 160,
        maxHr: 180,
        elevationGainM: 50,
        elevationLossM: 50,
        tss: 70,
        calories: 650,
        avgCadence: 180,
        maxCadence: 192,
      );

      final load = TrainingLoadCalculator.computeFromActivities(
        [recentActivity, oldActivity],
        now: now,
      );

      // Should span from 2024-06-01 to 2026-11-21 (> 730 days)
      expect(load.pmcSeries.length, greaterThan(800));
      expect(load.pmcSeries.first.date, DateTime(2024, 6, 1));
      expect(load.pmcSeries.first.ctl, greaterThan(0));
      expect(load.pmcSeries.first.atl, greaterThan(0));
      expect(load.pmcSeries.first.tsb, lessThan(0));
    });

    test('GarminAuthStore persists, loads, and clears session', () async {
      final tempDir = await Directory.systemTemp.createTemp('garmin_store_test_');
      addTearDown(() => tempDir.delete(recursive: true));

      final store = GarminAuthStore(customFilePath: '${tempDir.path}/session.json');
      expect(await store.load(), isNull);

      const profile = GarminUserProfile(displayName: 'jane_d', fullName: 'Jane Doe');
      await store.save(fakeSession, profile: profile);

      final loaded = await store.load();
      expect(loaded, isNotNull);
      expect(loaded!.session.accessToken, 'acc');
      expect(loaded.profile?.fullName, 'Jane Doe');
      expect(loaded.profile?.initials, 'JD');

      await store.clear();
      expect(await store.load(), isNull);
    });

    test('extracts single-quoted ticket and reversed-attribute CSRF token', () async {
      final mockClient = MockClient((request) async {
        final url = request.url.toString();
        if (url.contains('oauth_consumer.json')) {
          return http.Response(jsonEncode({'consumer_key': 'ck', 'consumer_secret': 'cs'}), 200);
        }
        if (url.contains('/sso/embed')) {
          return http.Response('', 200);
        }
        if (url.contains('/sso/signin') && request.method == 'GET') {
          return http.Response("<input value='rev_csrf' name='_csrf' type='hidden'>", 200);
        }
        if (url.contains('/sso/signin') && request.method == 'POST') {
          expect(request.bodyFields['_csrf'], 'rev_csrf');
          return http.Response(
            "<title>Success</title><script>window.location.replace('https://sso.garmin.com/sso/embed?ticket=ST-SINGLE-42');</script>",
            200,
          );
        }
        if (url.contains('/oauth/preauthorized')) {
          expect(request.url.queryParameters['ticket'], 'ST-SINGLE-42');
          return http.Response('oauth_token=o1&oauth_token_secret=s1', 200);
        }
        if (url.contains('/oauth/exchange/user/2.0')) {
          return http.Response(jsonEncode({'access_token': 'acc_sq', 'expires_in': 3600}), 200);
        }
        return http.Response('Not found', 404);
      });

      final service = GarminService(client: mockClient);
      final res = await service.login(email: 'a@b.com', password: 'pw');
      expect(res.session?.accessToken, 'acc_sq');
    });

    test('formats lap splits per sport discipline and handles numeric firmware safely', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/splits')) {
          return http.Response(
            jsonEncode({
              'lapDTOs': [
                {
                  'distance': 1000.0,
                  'duration': 100.0,
                  'averageSpeed': 10.0, // 36.0 km/h on bike, 1:40 /km on run
                  'averageHR': 160,
                  'avgPower': 285,
                }
              ]
            }),
            200,
          );
        }
        if (request.url.path.contains('/deviceregistration/devices')) {
          return http.Response(
            jsonEncode([
              {
                'deviceId': 12345,
                'productDisplayName': 'Edge 840',
                'deviceTypeName': 'Bike Computer',
                'currentFirmwareVersion': 24.19, // numeric firmware version!
              }
            ]),
            200,
          );
        }
        return http.Response('[]', 200);
      });

      final service = GarminService(client: mockClient);
      final bikeSplits = await service.fetchActivitySplits(
        fakeSession,
        '999',
        discipline: SportDiscipline.bike,
      );
      expect(bikeSplits.length, 1);
      expect(bikeSplits.first.paceOrSpeed, '36.0 km/h');
      expect(bikeSplits.first.avgPower, 285);

      final swimSplits = await service.fetchActivitySplits(
        fakeSession,
        '999',
        discipline: SportDiscipline.swim,
      );
      expect(swimSplits.first.paceOrSpeed, '0:10 /100m');

      final devices = await service.fetchDevices(fakeSession);
      expect(devices.length, 1);
      expect(devices.first.name, 'Edge 840');
      expect(devices.first.firmwareVersion, 'v24.19');
    });

    test('throws GarminUnauthorizedException on HTTP 401', () async {
      final mockClient = MockClient((_) async => http.Response('Unauthorized', 401));
      final service = GarminService(client: mockClient);
      expect(
        () => service.fetchUserProfile(fakeSession),
        throwsA(isA<GarminUnauthorizedException>()),
      );
      expect(
        () => service.fetchActivities(fakeSession),
        throwsA(isA<GarminUnauthorizedException>()),
      );
    });

    test('GarminAuthStore persists and loads race goals', () async {
      final tempDir = await Directory.systemTemp.createTemp('garmin_goals_test_');
      addTearDown(() => tempDir.delete(recursive: true));

      final store = GarminAuthStore(customFilePath: '${tempDir.path}/session.json');
      expect(await store.loadGoals(), isEmpty);

      await store.saveGoals([
        {'id': 'g1', 'name': 'Boston Marathon', 'tier': 'tierA', 'raceDate': '2027-04-19T00:00:00.000'},
      ]);
      final loaded = await store.loadGoals();
      expect(loaded.length, 1);
      expect(loaded.first['name'], 'Boston Marathon');
    });
  });
}
