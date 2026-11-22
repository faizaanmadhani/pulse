import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pulse_training_hub/models/activity.dart';
import 'package:pulse_training_hub/models/strava_enrichment.dart';
import 'package:pulse_training_hub/services/strava_auth_store.dart';
import 'package:pulse_training_hub/services/strava_service.dart';
import 'package:pulse_training_hub/services/url_opener.dart';

Activity _makeGarminActivity({
  required String id,
  required SportDiscipline discipline,
  required DateTime timestamp,
  required double distanceKm,
  String title = 'Garmin Activity',
}) {
  return Activity(
    id: id,
    title: title,
    description: '',
    discipline: discipline,
    timestamp: timestamp,
    formattedDate: 'Nov 20, 2026',
    location: 'San Francisco, CA',
    deviceHardware: 'Forerunner 965',
    sensorChain: 'HRM-Pro',
    distanceKm: distanceKm,
    durationSeconds: 3600,
    movingTime: '1:00:00',
    elapsedTime: '1:01:00',
    avgSpeedOrPace: '4:30 /km',
    maxSpeedOrPace: '3:50 /km',
    avgHr: 152,
    maxHr: 176,
    elevationGainM: 120,
    elevationLossM: 118,
    calories: 640,
  );
}

void main() {
  group('StravaAuthStore & StravaSession', () {
    test('saves, loads, and clears session on customFilePath', () async {
      final tmpDir = await Directory.systemTemp.createTemp('strava_store_test_');
      try {
        final store = StravaAuthStore(
          customFilePath: '${tmpDir.path}/strava_session.json',
        );
        final expiresAt = DateTime.utc(2030, 1, 1, 12, 0, 0);
        final session = StravaSession(
          accessToken: 'acc_123',
          refreshToken: 'ref_456',
          expiresAt: expiresAt,
          clientId: '99999',
          clientSecret: 'sec_abc',
          athleteName: 'Jane Doe',
          athleteId: '42',
        );

        await store.save(session);
        final loaded = await store.load();

        expect(loaded, isNotNull);
        expect(loaded!.accessToken, 'acc_123');
        expect(loaded.refreshToken, 'ref_456');
        expect(loaded.expiresAt.toUtc(), expiresAt);
        expect(loaded.clientId, '99999');
        expect(loaded.clientSecret, 'sec_abc');
        expect(loaded.athleteName, 'Jane Doe');
        expect(loaded.athleteId, '42');
        expect(loaded.isExpired, isFalse);

        await store.clear();
        expect(await store.load(), isNull);
      } finally {
        await tmpDir.delete(recursive: true);
      }
    });

    test('isExpired returns true when token is past or within 2 min of expiry', () {
      final expired = StravaSession(
        accessToken: 'tok',
        expiresAt: DateTime.now().add(const Duration(seconds: 30)),
      );
      final fresh = StravaSession(
        accessToken: 'tok',
        expiresAt: DateTime.now().add(const Duration(hours: 2)),
      );
      expect(expired.isExpired, isTrue);
      expect(fresh.isExpired, isFalse);
    });
  });

  group('StravaService OAuth', () {
    test('buildAuthorizeUrl constructs Strava OAuth URL with required scopes', () {
      final service = StravaService(
        client: MockClient((_) async => http.Response('', 200)),
      );
      final url = service.buildAuthorizeUrl(
        '12345',
        'http://127.0.0.1:8765/callback',
      );
      final uri = Uri.parse(url);

      expect(uri.scheme, 'https');
      expect(uri.host, 'www.strava.com');
      expect(uri.path, '/oauth/authorize');
      expect(uri.queryParameters['client_id'], '12345');
      expect(
        uri.queryParameters['redirect_uri'],
        'http://127.0.0.1:8765/callback',
      );
      expect(uri.queryParameters['response_type'], 'code');
      expect(uri.queryParameters['scope'], 'read,activity:read_all');
    });

    test('exchangeAuthorizationCode parses tokens and athlete info', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.toString(), 'https://www.strava.com/oauth/token');
        expect(request.bodyFields['client_id'], 'cid_1');
        expect(request.bodyFields['client_secret'], 'csec_1');
        expect(request.bodyFields['code'], 'auth_code_xyz');
        expect(request.bodyFields['grant_type'], 'authorization_code');

        return http.Response(
          jsonEncode({
            'token_type': 'Bearer',
            'expires_at': 1900000000,
            'refresh_token': 'ref_tok_1',
            'access_token': 'acc_tok_1',
            'athlete': {
              'id': 777123,
              'firstname': 'Alex',
              'lastname': 'Rivera',
            },
          }),
          200,
        );
      });

      final service = StravaService(client: mockClient);
      final session = await service.exchangeAuthorizationCode(
        'cid_1',
        'csec_1',
        'auth_code_xyz',
      );

      expect(session.accessToken, 'acc_tok_1');
      expect(session.refreshToken, 'ref_tok_1');
      expect(session.clientId, 'cid_1');
      expect(session.clientSecret, 'csec_1');
      expect(session.athleteId, '777123');
      expect(session.athleteName, 'Alex Rivera');
      expect(
        session.expiresAt.toUtc(),
        DateTime.fromMillisecondsSinceEpoch(1900000000 * 1000, isUtc: true),
      );
    });

    test('refreshToken exchanges refresh token and preserves athlete metadata', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.bodyFields['grant_type'], 'refresh_token');
        expect(request.bodyFields['refresh_token'], 'old_ref');
        expect(request.bodyFields['client_id'], 'cid_1');
        expect(request.bodyFields['client_secret'], 'csec_1');

        return http.Response(
          jsonEncode({
            'access_token': 'new_acc',
            'refresh_token': 'new_ref',
            'expires_at': 1950000000,
          }),
          200,
        );
      });

      final service = StravaService(client: mockClient);
      final initial = StravaSession(
        accessToken: 'old_acc',
        refreshToken: 'old_ref',
        expiresAt: DateTime.utc(2020, 1, 1),
        clientId: 'cid_1',
        clientSecret: 'csec_1',
        athleteName: 'Alex Rivera',
        athleteId: '777123',
      );

      final refreshed = await service.refreshToken(initial);
      expect(refreshed.accessToken, 'new_acc');
      expect(refreshed.refreshToken, 'new_ref');
      expect(refreshed.athleteName, 'Alex Rivera');
      expect(refreshed.athleteId, '777123');
      expect(refreshed.clientId, 'cid_1');
    });

    test('waitForOAuthCode captures code on localhost and returns HTML confirmation', () async {
      final service = StravaService(
        client: MockClient((_) async => http.Response('', 200)),
      );
      String? responseBody;
      int? statusCode;

      final code = await service.waitForOAuthCode(
        port: 0,
        timeout: const Duration(seconds: 5),
        onServerReady: (redirectUri) async {
          final client = HttpClient();
          try {
            final req = await client.getUrl(
              Uri.parse('$redirectUri?code=live_code_999&scope=read,activity:read_all'),
            );
            final resp = await req.close();
            statusCode = resp.statusCode;
            responseBody = await resp.transform(utf8.decoder).join();
          } finally {
            client.close();
          }
        },
      );

      expect(code, 'live_code_999');
      expect(statusCode, 200);
      expect(responseBody, contains('Connected to Pulse Training'));
    });
  });

  group('StravaService API parsing', () {
    final session = StravaSession(
      accessToken: 'bearer_tok',
      expiresAt: DateTime.now().add(const Duration(hours: 2)),
    );

    test('fetchActivities parses activity list and stravaUrl', () async {
      final mockClient = MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer bearer_tok');
        expect(request.url.path, '/api/v3/athlete/activities');
        expect(request.url.queryParameters['page'], '2');
        expect(request.url.queryParameters['per_page'], '50');

        return http.Response(
          jsonEncode([
            {
              'id': 1122334455,
              'name': 'Hawk Hill Dawn Patrol',
              'kudos_count': 24,
              'comment_count': 3,
              'suffer_score': 88.5,
              'sport_type': 'Ride',
              'start_date': '2026-11-20T14:30:00Z',
              'distance': 45200.0,
              'moving_time': 5400,
            },
          ]),
          200,
        );
      });

      final service = StravaService(client: mockClient);
      final activities = await service.fetchActivities(session, page: 2, perPage: 50);

      expect(activities, hasLength(1));
      final item = activities.first;
      expect(item.stravaId, '1122334455');
      expect(item.title, 'Hawk Hill Dawn Patrol');
      expect(item.kudosCount, 24);
      expect(item.commentCount, 3);
      expect(item.sufferScore, 88.5);
      expect(item.sportType, 'Ride');
      expect(item.distanceM, 45200.0);
      expect(item.movingTimeSec, 5400);
      expect(item.stravaUrl, 'https://www.strava.com/activities/1122334455');
    });

    test('fetchActivityDetail parses description, gear, segments, best efforts, suffer score', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/api/v3/activities/998877');
        return http.Response(
          jsonEncode({
            'id': 998877,
            'name': 'Tempo 10K + Strides',
            'description': 'Felt smooth at threshold pace.',
            'kudos_count': 19,
            'comment_count': 2,
            'suffer_score': 104,
            'sport_type': 'Run',
            'start_date': '2026-11-21T15:00:00Z',
            'distance': 10050.0,
            'moving_time': 2410,
            'gear': {'id': 'g123', 'name': 'Nike Vaporfly 3'},
            'segment_efforts': [
              {
                'id': 5001,
                'name': 'Marina Green Mile',
                'distance': 1609.3,
                'elapsed_time': 365,
                'pr_rank': 1,
                'kom_rank': 1,
                'average_watts': 345.2,
                'segment': {'average_grade': 0.4},
              },
              {
                'id': 5002,
                'name': 'Presidio Climb',
                'distance': 850.0,
                'elapsed_time': 240,
                'pr_rank': 2,
                'kom_rank': null,
                'segment': {'average_grade': 6.8},
              },
            ],
            'best_efforts': [
              {'name': '5k', 'distance': 5000, 'elapsed_time': 1175},
              {'name': '10k', 'distance': 10000, 'elapsed_time': 2398},
            ],
          }),
          200,
        );
      });

      final service = StravaService(client: mockClient);
      final detail = await service.fetchActivityDetail(session, '998877');

      expect(detail.description, 'Felt smooth at threshold pace.');
      expect(detail.gearName, 'Nike Vaporfly 3');
      expect(detail.sufferScore, 104.0);
      expect(detail.segmentEfforts, hasLength(2));
      expect(detail.segmentEfforts[0].name, 'Marina Green Mile');
      expect(detail.segmentEfforts[0].prRank, 1);
      expect(detail.segmentEfforts[0].isKom, isTrue);
      expect(detail.segmentEfforts[0].avgWatts, 345.2);
      expect(detail.segmentEfforts[0].avgGrade, 0.4);
      expect(detail.segmentEfforts[1].isKom, isFalse);
      expect(detail.segmentEfforts[1].prRank, 2);
      expect(detail.bestEfforts, hasLength(2));
      expect(detail.bestEfforts[0].name, '5k');
      expect(detail.bestEfforts[0].elapsedSec, 1175);

      // Verify toJson/fromJson round-trip preserves full enrichment.
      final roundTrip = StravaActivityEnrichment.fromJson(detail.toJson());
      expect(roundTrip.stravaId, detail.stravaId);
      expect(roundTrip.gearName, 'Nike Vaporfly 3');
      expect(roundTrip.segmentEfforts.length, 2);
      expect(roundTrip.bestEfforts.length, 2);
    });

    test('fetchActivityComments parses author name, text, and timestamp', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/api/v3/activities/998877/comments');
        return http.Response(
          jsonEncode([
            {
              'id': 8001,
              'text': 'Crushed that tempo!',
              'created_at': '2026-11-21T16:10:00Z',
              'athlete': {'firstname': 'Maya', 'lastname': 'Lin'},
            },
          ]),
          200,
        );
      });

      final service = StravaService(client: mockClient);
      final comments = await service.fetchActivityComments(session, '998877');

      expect(comments, hasLength(1));
      expect(comments.first.id, '8001');
      expect(comments.first.authorName, 'Maya Lin');
      expect(comments.first.text, 'Crushed that tempo!');
      expect(comments.first.createdAt.toUtc(), DateTime.utc(2026, 11, 21, 16, 10));
    });
  });

  group('StravaService.matchStravaToGarmin', () {
    final baseTime = DateTime.utc(2026, 11, 20, 14, 0, 0);

    test('matches exact timestamp, distance, and sport', () {
      final garmin = [
        _makeGarminActivity(
          id: 'g_run_1',
          discipline: SportDiscipline.run,
          timestamp: baseTime,
          distanceKm: 10.0,
        ),
      ];
      final strava = [
        StravaActivityEnrichment(
          stravaId: 's_run_1',
          title: 'Morning 10K',
          kudosCount: 12,
          commentCount: 1,
          sportType: 'Run',
          startDate: baseTime,
          distanceM: 10000.0,
          movingTimeSec: 2700,
        ),
      ];

      final matched = StravaService.matchStravaToGarmin(garmin, strava);
      expect(matched.keys, ['g_run_1']);
      expect(matched['g_run_1']!.stravaId, 's_run_1');
    });

    test('matches with slight time drift (<=5 min) and distance drift (<=5%)', () {
      final garmin = [
        _makeGarminActivity(
          id: 'g_bike_1',
          discipline: SportDiscipline.bike,
          timestamp: baseTime,
          distanceKm: 50.0,
        ),
      ];
      final strava = [
        StravaActivityEnrichment(
          stravaId: 's_bike_1',
          title: 'Coastal Loop',
          kudosCount: 8,
          commentCount: 0,
          sportType: 'GravelRide',
          startDate: baseTime.add(const Duration(minutes: 4, seconds: 15)),
          distanceM: 51800.0, // +3.6% drift
          movingTimeSec: 6000,
        ),
      ];

      final matched = StravaService.matchStravaToGarmin(garmin, strava);
      expect(matched['g_bike_1']?.stravaId, 's_bike_1');
    });

    test('matches short/indoor/strength activities within ±200m tolerance', () {
      final garmin = [
        _makeGarminActivity(
          id: 'g_strength_1',
          discipline: SportDiscipline.strength,
          timestamp: baseTime,
          distanceKm: 0.0,
        ),
        _makeGarminActivity(
          id: 'g_indoor_1',
          discipline: SportDiscipline.indoorBike,
          timestamp: baseTime.add(const Duration(hours: 2)),
          distanceKm: 1.0,
        ),
      ];
      final strava = [
        StravaActivityEnrichment(
          stravaId: 's_strength_1',
          title: 'Upper Body Lift',
          kudosCount: 3,
          commentCount: 0,
          sportType: 'WeightTraining',
          startDate: baseTime.add(const Duration(minutes: 2)),
          distanceM: 0.0,
          movingTimeSec: 2400,
        ),
        StravaActivityEnrichment(
          stravaId: 's_indoor_1',
          title: 'Trainer Warmup',
          kudosCount: 2,
          commentCount: 0,
          sportType: 'VirtualRide',
          startDate: baseTime.add(const Duration(hours: 2, minutes: 1)),
          distanceM: 1150.0, // 150m drift (>5% but <=200m)
          movingTimeSec: 600,
        ),
      ];

      final matched = StravaService.matchStravaToGarmin(garmin, strava);
      expect(matched['g_strength_1']?.stravaId, 's_strength_1');
      expect(matched['g_indoor_1']?.stravaId, 's_indoor_1');
    });

    test('rejects non-matching sport even with identical timestamp and distance', () {
      final garmin = [
        _makeGarminActivity(
          id: 'g_run_2',
          discipline: SportDiscipline.run,
          timestamp: baseTime,
          distanceKm: 10.0,
        ),
      ];
      final strava = [
        StravaActivityEnrichment(
          stravaId: 's_ride_2',
          title: 'Same-time Ride',
          kudosCount: 5,
          commentCount: 0,
          sportType: 'Ride',
          startDate: baseTime,
          distanceM: 10000.0,
          movingTimeSec: 1800,
        ),
      ];

      final matched = StravaService.matchStravaToGarmin(garmin, strava);
      expect(matched, isEmpty);
    });

    test('rejects time drift > 5 minutes or outdoor distance drift > 5%', () {
      final garmin = [
        _makeGarminActivity(
          id: 'g_run_late',
          discipline: SportDiscipline.run,
          timestamp: baseTime,
          distanceKm: 10.0,
        ),
        _makeGarminActivity(
          id: 'g_run_dist',
          discipline: SportDiscipline.run,
          timestamp: baseTime.add(const Duration(hours: 3)),
          distanceKm: 10.0,
        ),
      ];
      final strava = [
        StravaActivityEnrichment(
          stravaId: 's_late',
          title: 'Too Late',
          kudosCount: 1,
          commentCount: 0,
          sportType: 'Run',
          startDate: baseTime.add(const Duration(minutes: 6)),
          distanceM: 10000.0,
          movingTimeSec: 2700,
        ),
        StravaActivityEnrichment(
          stravaId: 's_dist',
          title: 'Distance Mismatch',
          kudosCount: 1,
          commentCount: 0,
          sportType: 'Run',
          startDate: baseTime.add(const Duration(hours: 3)),
          distanceM: 11200.0, // +12% drift
          movingTimeSec: 2700,
        ),
      ];

      final matched = StravaService.matchStravaToGarmin(garmin, strava);
      expect(matched, isEmpty);
    });
  });

  group('UrlOpener', () {
    test('validates https URLs and rejects non-https schemes', () {
      expect(UrlOpener.isValidHttpsUrl('https://www.strava.com/settings/api'), isTrue);
      expect(UrlOpener.isValidHttpsUrl('http://www.strava.com/settings/api'), isFalse);
      expect(UrlOpener.isValidHttpsUrl('file:///etc/passwd'), isFalse);
      expect(UrlOpener.isValidHttpsUrl('javascript:alert(1)'), isFalse);
      expect(UrlOpener.isValidHttpsUrl(''), isFalse);
    });

    test('garminActivityUrl formats canonical Garmin Connect URL', () {
      expect(
        UrlOpener.garminActivityUrl('18765432100'),
        'https://connect.garmin.com/modern/activity/18765432100',
      );
    });
  });
}
