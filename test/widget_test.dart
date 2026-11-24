import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pulse_training_hub/components/chatgpt_connect_dialog.dart';
import 'package:pulse_training_hub/main.dart';
import 'package:pulse_training_hub/models/activity.dart';
import 'package:pulse_training_hub/models/performance_metrics.dart';
import 'package:pulse_training_hub/models/training_plan.dart';
import 'package:pulse_training_hub/services/chatgpt_auth_store.dart';
import 'package:pulse_training_hub/services/chatgpt_service.dart';
import 'package:pulse_training_hub/services/garmin_auth_store.dart';
import 'package:pulse_training_hub/services/garmin_service.dart';
import 'package:pulse_training_hub/services/local_data_cache.dart';
import 'package:pulse_training_hub/services/strava_auth_store.dart';
import 'package:pulse_training_hub/services/training_plan_store.dart';
import 'package:pulse_training_hub/state/app_state.dart';
import 'package:pulse_training_hub/theme/app_colors.dart';
import 'package:pulse_training_hub/utils/unit_formatter.dart';
import 'package:pulse_training_hub/views/scheduled_workout_detail_view.dart';
import 'package:pulse_training_hub/views/training_plan_view.dart';

class _InMemoryDataCache extends LocalDataCache {
  CachedTelemetrySnapshot? _snapshot;

  @override
  Future<void> save(CachedTelemetrySnapshot snapshot) async {
    _snapshot = snapshot;
  }

  @override
  Future<CachedTelemetrySnapshot?> load() async => _snapshot;

  @override
  Future<void> clear() async {
    _snapshot = null;
  }
}

class _InMemoryAuthStore extends GarminAuthStore {
  GarminSession? _session;
  GarminUserProfile? _profile;
  List<Map<String, dynamic>> _goals = [];
  int saveCount = 0;

  @override
  Future<void> save(GarminSession session, {GarminUserProfile? profile}) async {
    _session = session;
    if (profile != null) {
      _profile = profile;
    }
    saveCount++;
  }

  @override
  Future<({GarminSession session, GarminUserProfile? profile})?> load() async {
    if (_session == null) return null;
    return (session: _session!, profile: _profile);
  }

  @override
  Future<void> saveGoals(List<Map<String, dynamic>> goals) async {
    _goals = List<Map<String, dynamic>>.from(goals);
  }

  @override
  Future<List<Map<String, dynamic>>> loadGoals() async {
    return List<Map<String, dynamic>>.from(_goals);
  }

  @override
  Future<void> clear() async {
    _session = null;
    _profile = null;
  }
}

class _InMemoryStravaAuthStore extends StravaAuthStore {
  StravaSession? _session;

  @override
  Future<void> save(StravaSession session) async {
    _session = session;
  }

  @override
  Future<StravaSession?> load() async => _session;

  @override
  Future<void> clear() async {
    _session = null;
  }
}

class _InMemoryChatGptAuthStore extends ChatGptAuthStore {
  ChatGptSession? _session;
  int saveCount = 0;

  @override
  Future<void> save(ChatGptSession session) async {
    _session = session;
    saveCount++;
  }

  @override
  Future<ChatGptSession?> load() async => _session;

  @override
  Future<void> clear() async {
    _session = null;
  }
}

class _InMemoryTrainingPlanStore extends TrainingPlanStore {
  TrainingPlanSnapshot? _snapshot;
  int saveCount = 0;

  @override
  Future<void> save(
    TrainingPlan? plan, [
    List<CoachMessage> messages = const [],
  ]) async {
    _snapshot = TrainingPlanSnapshot(
      plan: plan,
      messages: List<CoachMessage>.from(messages),
    );
    saveCount++;
  }

  @override
  Future<TrainingPlanSnapshot?> load() async => _snapshot;

  @override
  Future<void> clear() async {
    _snapshot = null;
  }
}

AppState _createTestAppState({
  GarminService? garminService,
  GarminAuthStore? authStore,
  LocalDataCache? dataCache,
  StravaAuthStore? stravaStore,
  ChatGptService? chatGptService,
  ChatGptAuthStore? chatGptAuthStore,
  TrainingPlanStore? trainingPlanStore,
  bool autoRestoreSession = false,
}) {
  return AppState(
    garminService: garminService,
    authStore: authStore ?? _InMemoryAuthStore(),
    dataCache: dataCache ?? _InMemoryDataCache(),
    stravaStore: stravaStore ?? _InMemoryStravaAuthStore(),
    chatGptService: chatGptService,
    chatGptAuthStore: chatGptAuthStore ?? _InMemoryChatGptAuthStore(),
    trainingPlanStore: trainingPlanStore ?? _InMemoryTrainingPlanStore(),
    autoRestoreSession: autoRestoreSession,
  );
}

String _buildTestIdToken({
  String name = 'Alex Rivera',
  String email = 'alex@example.com',
  String planTier = 'plus',
}) {
  String b64Url(Map<String, dynamic> data) =>
      base64UrlEncode(utf8.encode(jsonEncode(data))).replaceAll('=', '');
  final header = b64Url({'alg': 'RS256', 'typ': 'JWT'});
  final payload = b64Url({
    'name': name,
    'email': email,
    'https://api.openai.com/auth': {'chatgpt_plan_type': planTier},
  });
  return '$header.$payload.sig';
}

TrainingPlan _buildSampleTrainingPlan({
  required String todayKey,
  required String tomorrowKey,
  required String nextMonthKey,
}) {
  return TrainingPlan(
    id: 'plan_1',
    name: 'Oceanside 70.3 Build',
    createdAt: DateTime.utc(2026, 11, 20),
    updatedAt: DateTime.utc(2026, 11, 20),
    config: const TrainingPlanConfig(
      raceName: 'Spring 70.3',
      raceDistance: '70.3',
      raceDate: '2027-04-04',
      weeklyHoursBudget: 9.5,
      longRunDay: 'Sunday',
      longRideDay: 'Saturday',
      restDay: 'Friday',
      limiterSport: 'Swim',
    ),
    coachOverview: 'Polarized build emphasizing swim CSS and brick transitions.',
    weeks: [
      TrainingWeek(
        weekNumber: 1,
        startDate: todayKey,
        phaseName: 'Base',
        focusSummary: 'Aerobic base & pacing discipline',
        targetHours: 8.5,
        targetTss: 420,
        workouts: [
          PlannedWorkout(
            id: 'wo_run_1',
            date: todayKey,
            title: 'Threshold Cruise Intervals',
            discipline: SportDiscipline.run,
            archetype: WorkoutArchetype.threshold,
            estimatedDurationMinutes: 45,
            estimatedDistanceKm: 9.0,
            estimatedTss: 62,
            blocks: const [
              WorkoutBlock(
                step: WorkoutStep(
                  kind: StepKind.warmup,
                  endCondition: StepEndCondition.time,
                  endValue: 600,
                  targetKind: StepTargetKind.heartRateZone,
                  targetLow: 2,
                  targetHigh: 2,
                ),
              ),
              WorkoutBlock(
                repeatCount: 3,
                steps: [
                  WorkoutStep(
                    kind: StepKind.interval,
                    endCondition: StepEndCondition.time,
                    endValue: 480,
                    targetKind: StepTargetKind.paceMps,
                    targetLow: 3.7,
                    targetHigh: 3.9,
                  ),
                  WorkoutStep(
                    kind: StepKind.recovery,
                    endCondition: StepEndCondition.time,
                    endValue: 120,
                    targetKind: StepTargetKind.none,
                  ),
                ],
              ),
            ],
          ),
          PlannedWorkout(
            id: 'wo_zwift_1',
            date: todayKey,
            title: 'Zwift Sweet Spot Tempo',
            discipline: SportDiscipline.indoorBike,
            archetype: WorkoutArchetype.zwiftRide,
            estimatedDurationMinutes: 60,
            estimatedTss: 58,
            zwiftPrescription: const ZwiftPrescription(
              durationMinutes: 60,
              difficulty: 'Sweet Spot',
              targetTss: 58,
              zwiftCategory: 'Sweet Spot',
              suggestedSearchTerms: ['SST Short', '2x15 Tempo'],
            ),
          ),
          PlannedWorkout(
            id: 'wo_brick_1',
            date: tomorrowKey,
            title: 'Saturday Endurance Brick',
            discipline: SportDiscipline.bike,
            archetype: WorkoutArchetype.brick,
            estimatedDurationMinutes: 110,
            estimatedTss: 95,
            zwiftPrescription: const ZwiftPrescription(
              durationMinutes: 90,
              difficulty: 'Endurance',
              targetTss: 72,
              zwiftCategory: 'Endurance',
              suggestedSearchTerms: ['Zone 2 Endurance'],
            ),
            brickRunLeg: PlannedWorkout(
              id: 'wo_brick_1_run',
              date: tomorrowKey,
              title: 'T2 Transition Run',
              discipline: SportDiscipline.run,
              archetype: WorkoutArchetype.easy,
              estimatedDurationMinutes: 20,
              estimatedDistanceKm: 3.8,
              blocks: const [
                WorkoutBlock(
                  step: WorkoutStep(
                    kind: StepKind.steady,
                    endCondition: StepEndCondition.time,
                    endValue: 1200,
                    targetKind: StepTargetKind.heartRateZone,
                    targetLow: 2,
                    targetHigh: 3,
                  ),
                ),
              ],
            ),
          ),
          PlannedWorkout(
            id: 'wo_future_far',
            date: nextMonthKey,
            title: 'Long Aerobic Run',
            discipline: SportDiscipline.run,
            archetype: WorkoutArchetype.long,
            estimatedDurationMinutes: 90,
            estimatedDistanceKm: 17.5,
            blocks: const [
              WorkoutBlock(
                step: WorkoutStep(
                  kind: StepKind.steady,
                  endCondition: StepEndCondition.time,
                  endValue: 5400,
                  targetKind: StepTargetKind.heartRateZone,
                  targetLow: 2,
                  targetHigh: 2,
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

class _PassthroughHttpOverrides extends HttpOverrides {}

void main() {
  testWidgets(
      'Signed-out app renders macOS UI with zero fake data and opens Garmin Sign In',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final appState = _createTestAppState();

    await tester.pumpWidget(PulseTrainingApp(appState: appState));
    await tester.pumpAndSettle();

    // Native macOS labels present (including new Training Plan tab)
    expect(find.text('Pulse'), findsOneWidget);
    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('Calendar'), findsOneWidget);
    expect(find.text('Training Plan'), findsOneWidget);
    expect(find.text('Analytics'), findsOneWidget);
    expect(find.text('Activities'), findsOneWidget);
    expect(find.text('Strength'), findsWidgets);
    expect(find.text('Garmin & Devices'), findsOneWidget);
    expect(find.text('Connect Your Garmin Account'), findsOneWidget);

    // Zero sci-fi labels or hardcoded fake data
    expect(find.text('PULSE 70.3 // LOCAL TELEMETRY'), findsNothing);
    expect(find.text('NAVIGATION ENGINE'), findsNothing);
    expect(find.textContaining('Marin Headlands'), findsNothing);
    expect(find.textContaining('Oceanside 70.3'), findsNothing);
    expect(find.textContaining('Cervélo'), findsNothing);

    // Clicking Sign in with Garmin opens native sign-in modal
    await tester.tap(find.text('Sign in with Garmin').first);
    await tester.pumpAndSettle();
    expect(find.text('Sign in to Garmin Connect'), findsOneWidget);
  });

  testWidgets(
      'Signing in with Garmin pulls live activities & devices and Sign Out clears them',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mockClient = MockClient((request) async {
      final url = request.url.toString();
      if (url.contains('oauth_consumer.json')) {
        return http.Response(
            jsonEncode({'consumer_key': 'ck', 'consumer_secret': 'cs'}), 200);
      }
      if (url.contains('/sso/embed')) {
        return http.Response('', 200);
      }
      if (url.contains('/sso/signin') && request.method == 'GET') {
        return http.Response('<input name="_csrf" value="tok">', 200);
      }
      if (url.contains('/sso/signin') && request.method == 'POST') {
        return http.Response(
          '<html><head><title>Success</title></head><body>embed?ticket=ST-OK</body></html>',
          200,
        );
      }
      if (url.contains('/oauth/preauthorized')) {
        return http.Response('oauth_token=t1&oauth_token_secret=s1', 200);
      }
      if (url.contains('/oauth/exchange/user/2.0')) {
        return http.Response(
            jsonEncode({'access_token': 'acc1', 'expires_in': 3600}), 200);
      }
      if (url.contains('/socialProfile')) {
        return http.Response(
          jsonEncode({'displayName': 'alex_runner', 'fullName': 'Alex Rivera'}),
          200,
        );
      }
      if (url.contains('/search/activities')) {
        return http.Response(
          jsonEncode([
            {
              'activityId': 555,
              'activityName': 'Charles River 10K',
              'activityType': {'typeKey': 'running'},
              'startTimeLocal': '2026-11-21 08:00:00',
              'distance': 10000.0,
              'duration': 2800.0,
              'averageSpeed': 3.57,
              'averageHR': 152,
              'calories': 640,
              'locationName': 'Boston, MA',
            }
          ]),
          200,
        );
      }
      if (url.contains('/deviceregistration/devices')) {
        return http.Response(
          jsonEncode([
            {
              'deviceId': '999',
              'productDisplayName': 'Forerunner 265',
              'deviceTypeName': 'Watch',
              'currentFirmwareVersion': '20.26',
            }
          ]),
          200,
        );
      }
      if (url.contains('/usersummary/daily/')) {
        return http.Response(
            jsonEncode({'restingHeartRate': 48, 'totalSteps': 9120}), 200);
      }
      if (url.contains('/hrv-service/hrv/')) {
        return http.Response(
            jsonEncode({'hrvSummary': {'lastNightAvg': 68}}), 200);
      }
      if (url.contains('/maxmet/latest/')) {
        return http.Response(
            jsonEncode([
              {'generic': {'vo2MaxPreciseValue': 54.2}}
            ]),
            200);
      }
      return http.Response('[]', 200);
    });

    final appState = _createTestAppState(
      garminService: GarminService(client: mockClient),
    );

    await tester.pumpWidget(PulseTrainingApp(appState: appState));
    await tester.pumpAndSettle();

    final ok = await appState.signInWithGarmin(
        email: 'alex@example.com', password: 'secret');
    expect(ok, isTrue);
    await tester.pumpAndSettle();

    // Real synced Garmin data renders on Dashboard
    expect(find.text('Alex Rivera'), findsOneWidget);
    expect(find.text('Charles River 10K'), findsOneWidget);
    expect(find.text('48'), findsOneWidget);
    expect(find.text('54.2'), findsOneWidget);

    // Navigate to Garmin & Devices and verify real synced device appears
    await tester.tap(find.text('Garmin & Devices'));
    await tester.pumpAndSettle();
    expect(find.text('Forerunner 265'), findsOneWidget);

    // Sign out clears all synced data
    await tester.tap(find.text('Sign Out'));
    await tester.pumpAndSettle();
    expect(find.text('Forerunner 265'), findsNothing);
    expect(appState.isSignedIn, isFalse);
    expect(appState.activities, isEmpty);
  });

  testWidgets(
      'All 7 tabs, ActivityDetailView, Dark Mode, and Search render cleanly at 1100x750 min size',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 750);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    int profileCalls = 0;
    final mockClient = MockClient((request) async {
      final url = request.url.toString();
      if (url.contains('oauth_consumer.json')) {
        return http.Response(
            jsonEncode({'consumer_key': 'ck', 'consumer_secret': 'cs'}), 200);
      }
      if (url.contains('/sso/embed')) {
        return http.Response('', 200);
      }
      if (url.contains('/sso/signin') && request.method == 'GET') {
        return http.Response('<input name="_csrf" value="tok">', 200);
      }
      if (url.contains('/sso/signin') && request.method == 'POST') {
        return http.Response(
          '<html><head><title>Success</title></head><body>embed?ticket=ST-OK</body></html>',
          200,
        );
      }
      if (url.contains('/oauth/preauthorized')) {
        return http.Response('oauth_token=t1&oauth_token_secret=s1', 200);
      }
      if (url.contains('/oauth/exchange/user/2.0')) {
        return http.Response(
            jsonEncode({'access_token': 'acc_refreshed', 'expires_in': 3600}),
            200);
      }
      if (url.contains('/socialProfile')) {
        profileCalls++;
        if (profileCalls == 1) {
          return http.Response('Unauthorized', 401);
        }
        return http.Response(
          jsonEncode({
            'displayName': 'alex_runner_long_display_name',
            'fullName': 'Alex Bartholomew Montgomery-Rivera III',
          }),
          200,
        );
      }
      if (url.contains('/search/activities')) {
        return http.Response(
          jsonEncode([
            {
              'activityId': 701,
              'activityName': 'Coastal Highway Aero Ride',
              'activityType': {'typeKey': 'road_biking'},
              'startTimeLocal': '2026-11-21 09:00:00',
              'distance': 45000.0,
              'duration': 4500.0,
              'averageSpeed': 10.0,
              'averageHR': 148,
              'avgPower': 240,
              'normPower': 252,
              'calories': 1120,
              'locationName': 'Pacific Coast',
            },
            {
              'activityId': 702,
              'activityName': 'Full Body Kettlebell Strength',
              'activityType': {'typeKey': 'strength_training'},
              'startTimeLocal': '2026-11-20 18:00:00',
              'distance': 0.0,
              'duration': 2700.0,
              'averageHR': 124,
              'calories': 390,
            }
          ]),
          200,
        );
      }
      if (url.contains('/activity/701/splits')) {
        return http.Response(
          jsonEncode({
            'lapDTOs': [
              {
                'distance': 5000.0,
                'duration': 500.0,
                'averageSpeed': 10.0,
                'averageHR': 150,
                'averagePower': 260,
              }
            ]
          }),
          200,
        );
      }
      if (url.contains('/deviceregistration/devices')) {
        return http.Response(
          jsonEncode([
            {
              'deviceId': 42,
              'productDisplayName': 'Edge 1040 Solar',
              'deviceTypeName': 'Bike Computer',
              'currentFirmwareVersion': 21.18,
            }
          ]),
          200,
        );
      }
      if (url.contains('/usersummary/daily/')) {
        return http.Response(
            jsonEncode({'restingHeartRate': 46, 'totalSteps': 11200}), 200);
      }
      if (url.contains('/hrv-service/hrv/')) {
        return http.Response(
            jsonEncode({'hrvSummary': {'lastNightAvg': 74}}), 200);
      }
      if (url.contains('/maxmet/latest/')) {
        return http.Response(
            jsonEncode([
              {'generic': {'vo2MaxPreciseValue': 56.8}}
            ]),
            200);
      }
      return http.Response('[]', 200);
    });

    final appState = _createTestAppState(
      garminService: GarminService(client: mockClient),
    );

    await tester.pumpWidget(PulseTrainingApp(appState: appState));
    await tester.pumpAndSettle();

    final ok = await appState.signInWithGarmin(
        email: 'alex@example.com', password: 'secret');
    expect(ok, isTrue);
    expect(profileCalls, 2);
    await tester.pumpAndSettle();

    // Visit every single tab (0..6) at 1100x750
    for (final tab in [
      'Calendar',
      'Training Plan',
      'Analytics',
      'Activities',
      'Strength',
      'Garmin & Devices',
      'Dashboard',
    ]) {
      await tester.tap(find.text(tab).first);
      await tester.pumpAndSettle();
    }

    // Search from Dashboard automatically switches to Activities (index 4) & filters
    await tester.enterText(find.byType(TextField).first, 'Coastal');
    await tester.pumpAndSettle();
    expect(appState.currentNavIndex, 4);
    expect(find.text('Coastal Highway Aero Ride'), findsOneWidget);
    expect(find.text('Full Body Kettlebell Strength'), findsNothing);

    // Open bike activity detail and verify cycling split displays km/h & Speed header
    await tester.tap(find.text('Coastal Highway Aero Ride'));
    await tester.pumpAndSettle();
    expect(find.text('Speed'), findsOneWidget);
    expect(find.text('36.0 km/h'), findsWidgets);

    // Toggle Dark Mode and ensure zero layout errors
    appState.toggleDarkMode();
    await tester.pumpAndSettle();
    expect(appState.isDarkMode, isTrue);

    // Sign out clears search query & toolbar field
    await appState.signOutGarmin();
    await tester.pumpAndSettle();
    expect(appState.searchQuery, isEmpty);
  });

  testWidgets(
      'DeviceSyncView ChatGPT Account card renders disconnected, connected, and Disconnect clears session at 1100x750 & 1440x900',
      (WidgetTester tester) async {
    final chatGptStore = _InMemoryChatGptAuthStore();
    final planStore = _InMemoryTrainingPlanStore();
    final todayKey = PlannedWorkout.formatLocalDate(DateTime.now());
    final plan = _buildSampleTrainingPlan(
      todayKey: todayKey,
      tomorrowKey: PlannedWorkout.formatLocalDate(
          DateTime.now().add(const Duration(days: 1))),
      nextMonthKey: PlannedWorkout.formatLocalDate(
          DateTime.now().add(const Duration(days: 30))),
    );
    await planStore.save(plan, const []);

    final appState = _createTestAppState(
      chatGptAuthStore: chatGptStore,
      trainingPlanStore: planStore,
    );
    await appState.restoreSession();

    for (final viewport in const [Size(1100, 750), Size(1440, 900)]) {
      tester.view.physicalSize = viewport;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(PulseTrainingApp(appState: appState));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Garmin & Devices').first);
      await tester.pumpAndSettle();

      // Disconnected ChatGPT card
      expect(find.text('ChatGPT Coach'), findsOneWidget);
      expect(find.text('Connect ChatGPT'), findsOneWidget);
    }

    // Seed connected session and restore
    await chatGptStore.save(
      ChatGptSession(
        clientId: 'oaiapp_live_001',
        accessToken: 'acc_tok',
        refreshToken: 'ref_tok',
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 2)),
        userName: 'Alex Rivera',
        userEmail: 'alex@example.com',
        planTier: 'plus',
      ),
    );
    await appState.restoreSession();
    await tester.pumpAndSettle();

    expect(find.text('ChatGPT • Alex Rivera'), findsOneWidget);
    expect(find.text('PLUS'), findsOneWidget);
    expect(find.textContaining('alex@example.com'), findsOneWidget);
    expect(find.textContaining('oaiapp_live_001'), findsOneWidget);
    expect(find.text('Disconnect'), findsOneWidget);

    // Disconnect clears session + store, but keeps active training plan
    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();
    expect(appState.isChatGptConnected, isFalse);
    expect(await chatGptStore.load(), isNull);
    expect(appState.activeTrainingPlan, isNotNull);
    expect(find.text('Connect ChatGPT'), findsOneWidget);
  });

  testWidgets(
      'ChatGptConnectDialog uses OAuth PKCE only, copies callback URL, and completes via manual code fallback',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    String? clipboardText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        final args = call.arguments as Map<dynamic, dynamic>;
        clipboardText = args['text'] as String?;
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    final mockChatGptClient = MockClient((request) async {
      expect(request.url.toString(), ChatGptService.tokenEndpoint);
      expect(request.bodyFields['grant_type'], 'authorization_code');
      expect(request.bodyFields['client_id'], 'oaiapp_test_123');
      expect(request.bodyFields['code'], 'manual_auth_code_999');
      expect(request.bodyFields['redirect_uri'],
          ChatGptConnectDialog.defaultCallbackUrl);
      return http.Response(
        jsonEncode({
          'access_token': 'gpt_access_1',
          'refresh_token': 'gpt_refresh_1',
          'id_token': _buildTestIdToken(
            name: 'Morgan Coach',
            email: 'morgan@example.com',
            planTier: 'pro',
          ),
          'expires_in': 3600,
        }),
        200,
      );
    });

    final chatGptStore = _InMemoryChatGptAuthStore();
    final appState = _createTestAppState(
      chatGptService: ChatGptService(client: mockChatGptClient),
      chatGptAuthStore: chatGptStore,
    );

    await tester.pumpWidget(PulseTrainingApp(appState: appState));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Garmin & Devices').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Connect ChatGPT'));
    await tester.pumpAndSettle();

    // Verify OAuth PKCE UI and zero API key field
    expect(find.text('Sign in with ChatGPT'), findsOneWidget);
    expect(find.text(ChatGptConnectDialog.defaultCallbackUrl), findsOneWidget);
    expect(find.text('Continue with ChatGPT'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.textContaining('API Key'), findsNothing);
    expect(find.textContaining('sk-'), findsNothing);

    // Copy callback URL
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(clipboardText, ChatGptConnectDialog.defaultCallbackUrl);
    expect(find.text('Copied'), findsOneWidget);

    // Enter Client ID + manual code and submit
    final fields = find.descendant(
      of: find.byType(ChatGptConnectDialog),
      matching: find.byType(TextField),
    );
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.at(0), 'oaiapp_test_123');
    await tester.enterText(fields.at(1), 'manual_auth_code_999');
    await tester.tap(find.text('Complete Sign-In'));
    await tester.pumpAndSettle();

    expect(find.byType(ChatGptConnectDialog), findsNothing);
    expect(appState.isChatGptConnected, isTrue);
    expect(appState.chatGptSession?.userEmail, 'morgan@example.com');
    expect(appState.chatGptSession?.planTier, 'pro');
    expect(await chatGptStore.load(), isNotNull);
  });

  test('AppState.connectChatGpt handles loopback port 0, cancelChatGptAuth port cleanup, and mid-flight/post-timeout manual completion',
      () async {
    await HttpOverrides.runWithHttpOverrides(() async {
      String? exchangedRedirectUri;
      final mockClient = MockClient((request) async {
        exchangedRedirectUri = request.bodyFields['redirect_uri'];
        return http.Response(
          jsonEncode({
            'access_token': 'loop_acc',
            'refresh_token': 'loop_ref',
            'id_token': _buildTestIdToken(),
            'expires_in': 3600,
          }),
          200,
        );
      });

      final chatGptStore = _InMemoryChatGptAuthStore();
      final appState = _createTestAppState(
        chatGptService: ChatGptService(client: mockClient),
        chatGptAuthStore: chatGptStore,
      );

      // 1) Ephemeral port 0 loopback OAuth flow
      final ok = await appState.connectChatGpt(
        'oaiapp_loop',
        callbackPort: 0,
        onAuthorizeUrl: (authUrl) async {
          final uri = Uri.parse(authUrl);
          final redirectUri = Uri.parse(uri.queryParameters['redirect_uri']!);
          final state = uri.queryParameters['state']!;
          expect(redirectUri.port, greaterThan(0));

          final httpClient = HttpClient();
          final req = await httpClient.getUrl(
            redirectUri.replace(
              queryParameters: {'code': 'loop_code_1', 'state': state},
            ),
          );
          final res = await req.close();
          await res.drain<void>();
          httpClient.close(force: true);
        },
      );
      expect(ok, isTrue);
      expect(appState.isChatGptConnected, isTrue);
      expect(exchangedRedirectUri, startsWith('http://127.0.0.1:'));
      expect(exchangedRedirectUri, isNot('http://127.0.0.1:0/callback'));

      await appState.disconnectChatGpt();
      expect(appState.isChatGptConnected, isFalse);

      // 2) Cancel mid-flight frees bound loopback port immediately & leaves zero stale errors
      int? boundPort;
      final cancelledOk = await appState.connectChatGpt(
        'oaiapp_cancel',
        callbackPort: 0,
        onAuthorizeUrl: (authUrl) async {
          final redirectUri =
              Uri.parse(Uri.parse(authUrl).queryParameters['redirect_uri']!);
          boundPort = redirectUri.port;
          await appState.cancelChatGptAuth();
        },
      );
      expect(cancelledOk, isFalse);
      expect(appState.isAuthenticatingChatGpt, isFalse);
      expect(appState.chatGptError, isNull);
      expect(boundPort, isNotNull);

      // Verify port is released and can be rebound immediately
      final rebound =
          await HttpServer.bind(InternetAddress.loopbackIPv4, boundPort!);
      await rebound.close(force: true);

      // 3) Mid-flight manual code override frees server & uses pending PKCE verifier/state
      int? midFlightPort;
      final serverReady = Completer<String>();
      final midFlightFuture = appState.connectChatGpt(
        'oaiapp_mid',
        callbackPort: 0,
        onAuthorizeUrl: (authUrl) async {
          final uri = Uri.parse(authUrl);
          midFlightPort =
              Uri.parse(uri.queryParameters['redirect_uri']!).port;
          serverReady.complete(uri.queryParameters['state']!);
        },
      );
      final pendingState = await serverReady.future;
      final manualOk = await appState.completeChatGptOAuthWithCode(
        'http://127.0.0.1:$midFlightPort/callback?code=mid_code&state=$pendingState',
        clientId: 'oaiapp_mid',
      );
      final backgroundResult = await midFlightFuture;
      expect(manualOk, isTrue);
      expect(backgroundResult, isFalse);
      expect(appState.isChatGptConnected, isTrue);
      expect(appState.chatGptError, isNull);
      final rebound2 =
          await HttpServer.bind(InternetAddress.loopbackIPv4, midFlightPort!);
      await rebound2.close(force: true);
    }, _PassthroughHttpOverrides());
  });

  test('AppState.restoreSession restores ChatGPT + TrainingPlan offline and matches cached Garmin activities',
      () async {
    final now = DateTime.now();
    final todayKey = PlannedWorkout.formatLocalDate(now);
    final tomorrowKey =
        PlannedWorkout.formatLocalDate(now.add(const Duration(days: 1)));
    final nextMonthKey =
        PlannedWorkout.formatLocalDate(now.add(const Duration(days: 30)));

    final chatGptStore = _InMemoryChatGptAuthStore();
    final planStore = _InMemoryTrainingPlanStore();
    final authStore = _InMemoryAuthStore();
    final dataCache = _InMemoryDataCache();

    await chatGptStore.save(
      ChatGptSession(
        clientId: 'oaiapp_offline',
        accessToken: 'tok',
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
        userEmail: 'offline@example.com',
      ),
    );
    await planStore.save(
      _buildSampleTrainingPlan(
        todayKey: todayKey,
        tomorrowKey: tomorrowKey,
        nextMonthKey: nextMonthKey,
      ),
      [
        CoachMessage(
          id: 'm1',
          role: CoachMessageRole.assistant,
          content: 'Focus on threshold control.',
          createdAt: DateTime.utc(2026, 11, 20),
        ),
      ],
    );

    // Case A: Garmin signed out -> ChatGPT + Plan + Coach history still restore
    final appStateSignedOut = _createTestAppState(
      authStore: authStore,
      dataCache: dataCache,
      chatGptAuthStore: chatGptStore,
      trainingPlanStore: planStore,
    );
    await appStateSignedOut.restoreSession();
    expect(appStateSignedOut.isChatGptConnected, isTrue);
    expect(appStateSignedOut.activeTrainingPlan, isNotNull);
    expect(appStateSignedOut.coachMessages, hasLength(1));

    // Case B: Garmin signed in with cached activity -> compliance matcher runs on restore
    await authStore.save(
      GarminSession(
        domain: 'garmin.com',
        oauth1Token: 'o1',
        oauth1TokenSecret: 's1',
        accessToken: 'o2',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        consumerKey: 'ck',
        consumerSecret: 'cs',
      ),
      profile: const GarminUserProfile(
        displayName: 'alex',
        fullName: 'Alex Rivera',
      ),
    );
    await dataCache.save(
      CachedTelemetrySnapshot(
        activities: [
          Activity(
            id: 'act_run_today',
            title: 'Threshold Run',
            description: 'Threshold run session',
            discipline: SportDiscipline.run,
            timestamp: DateTime(now.year, now.month, now.day, 7, 30),
            formattedDate: todayKey,
            location: 'Boston, MA',
            deviceHardware: 'Forerunner 265',
            sensorChain: 'Wrist HR',
            durationSeconds: 2700,
            movingTime: '45:00',
            elapsedTime: '45:00',
            distanceKm: 9.0,
            avgSpeedOrPace: '5:00 /km',
            maxSpeedOrPace: '4:30 /km',
            avgHr: 162,
            maxHr: 174,
            calories: 610,
            elevationGainM: 40,
            elevationLossM: 40,
          ),
        ],
        connectedDevices: const [],
        profile: const AthletePhysiologicalProfile(),
      ),
    );

    final offlineGarminClient = MockClient((_) async => http.Response('{}', 500));
    final appStateSignedIn = _createTestAppState(
      garminService: GarminService(client: offlineGarminClient),
      authStore: authStore,
      dataCache: dataCache,
      chatGptAuthStore: chatGptStore,
      trainingPlanStore: planStore,
    );
    await appStateSignedIn.restoreSession();

    final matchedRun = appStateSignedIn.activeTrainingPlan!.allWorkouts
        .firstWhere((w) => w.id == 'wo_run_1');
    expect(matchedRun.status, WorkoutStatus.completed);
    expect(matchedRun.matchedActivityId, 'act_run_today');
    expect(matchedRun.adherencePercent, isNotNull);
  });

  test('AppState Garmin workout sync handles 401 refresh+save+retry, Brick run-leg, zwiftRide rejection, remove & bulk 2-week sync',
      () async {
    final now = DateTime.now();
    final todayKey = PlannedWorkout.formatLocalDate(now);
    final tomorrowKey =
        PlannedWorkout.formatLocalDate(now.add(const Duration(days: 1)));
    final nextMonthKey =
        PlannedWorkout.formatLocalDate(now.add(const Duration(days: 30)));

    int createCalls = 0;
    int scheduleCalls = 0;
    int deleteScheduleCalls = 0;
    int deleteWorkoutCalls = 0;
    int tokenExchangeCalls = 0;

    final mockGarminClient = MockClient((request) async {
      final url = request.url.toString();
      if (url.contains('oauth_consumer.json')) {
        return http.Response(
            jsonEncode({'consumer_key': 'ck', 'consumer_secret': 'cs'}), 200);
      }
      if (url.contains('/socialProfile')) {
        return http.Response(
          jsonEncode({'displayName': 'alex', 'fullName': 'Alex Rivera'}),
          200,
        );
      }
      if (url.contains('/oauth/exchange/user/2.0')) {
        tokenExchangeCalls++;
        return http.Response(
          jsonEncode({'access_token': 'refreshed_o2', 'expires_in': 3600}),
          200,
        );
      }
      if (url.contains('/workout-service/workout') && request.method == 'POST') {
        createCalls++;
        return http.Response(jsonEncode({'workoutId': 'gw_$createCalls'}), 200);
      }
      if (url.contains('/workout-service/schedule/') &&
          request.method == 'POST') {
        scheduleCalls++;
        // First schedule attempt returns 401 -> must refresh + save + retry schedule ONLY (no second createWorkout!)
        if (scheduleCalls == 1) {
          return http.Response('Unauthorized', 401);
        }
        return http.Response(
            jsonEncode({'workoutScheduleId': 'gs_$scheduleCalls'}), 200);
      }
      if (url.contains('/workout-service/schedule/') &&
          request.method == 'DELETE') {
        deleteScheduleCalls++;
        return http.Response('', 204);
      }
      if (url.contains('/workout-service/workout/') &&
          request.method == 'DELETE') {
        deleteWorkoutCalls++;
        return http.Response('', 204);
      }
      return http.Response('{}', 200);
    });

    final authStore = _InMemoryAuthStore();
    await authStore.save(
      GarminSession(
        domain: 'garmin.com',
        oauth1Token: 'o1',
        oauth1TokenSecret: 's1',
        accessToken: 'initial_o2',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        consumerKey: 'ck',
        consumerSecret: 'cs',
      ),
      profile: const GarminUserProfile(
          displayName: 'alex', fullName: 'Alex Rivera'),
    );
    final planStore = _InMemoryTrainingPlanStore();
    await planStore.save(
      _buildSampleTrainingPlan(
        todayKey: todayKey,
        tomorrowKey: tomorrowKey,
        nextMonthKey: nextMonthKey,
      ),
    );

    final appState = _createTestAppState(
      garminService: GarminService(client: mockGarminClient),
      authStore: authStore,
      trainingPlanStore: planStore,
    );
    await appState.restoreSession();

    // 1) zwiftRide is rejected without hitting Garmin API
    final zwiftResult = await appState.syncWorkoutToGarmin('wo_zwift_1');
    expect(zwiftResult, isFalse);
    expect(appState.planError, isNotNull);
    expect(createCalls, 0);

    // 2) Run workout push triggers 401 on schedule -> refreshes + saves + retries schedule without duplicating createWorkout
    final runResult = await appState.syncWorkoutToGarmin('wo_run_1');
    expect(runResult, isTrue);
    expect(createCalls, 1);
    expect(scheduleCalls, 2);
    expect(tokenExchangeCalls, 1);
    final savedAuth = await authStore.load();
    expect(savedAuth?.session.accessToken, 'refreshed_o2');
    expect(savedAuth?.profile?.fullName, 'Alex Rivera');

    // 3) Bulk sync upcoming 14 days pushes Brick run leg (skips already-synced Run, Zwift, and 30-day Run)
    final bulkCount = await appState.syncUpcomingWorkoutsToGarmin(days: 14);
    expect(bulkCount, 1);
    final brick = appState.activeTrainingPlan!.allWorkouts
        .firstWhere((w) => w.id == 'wo_brick_1');
    expect(brick.isSyncedToGarmin, isTrue);
    expect(brick.brickRunLeg?.isSyncedToGarmin, isTrue);
    expect(brick.brickRunLeg?.garminWorkoutId, brick.garminWorkoutId);

    // 4) Remove Brick from Garmin clears metadata on both parent and brickRunLeg
    final removeOk = await appState.removeWorkoutFromGarmin('wo_brick_1');
    expect(removeOk, isTrue);
    expect(deleteScheduleCalls, 1);
    expect(deleteWorkoutCalls, 1);
    final brickAfterRemove = appState.activeTrainingPlan!.allWorkouts
        .firstWhere((w) => w.id == 'wo_brick_1');
    expect(brickAfterRemove.isSyncedToGarmin, isFalse);
    expect(brickAfterRemove.brickRunLeg?.isSyncedToGarmin, isFalse);

    // 5) Reschedule clears stale Garmin metadata and updates brickRunLeg date; nav clears selectedPlannedWorkout
    appState.selectPlannedWorkout(
      appState.activeTrainingPlan!.allWorkouts
          .firstWhere((w) => w.id == 'wo_run_1'),
    );
    expect(appState.selectedPlannedWorkout, isNotNull);
    await appState.reschedulePlannedWorkout(
      'wo_run_1',
      now.add(const Duration(days: 3)),
    );
    expect(appState.selectedPlannedWorkout?.isSyncedToGarmin, isFalse);
    appState.setNavIndex(1);
    expect(appState.selectedPlannedWorkout, isNull);
  });

  test('AppState ChatGPT coach & plan actions auto-refresh on 401 and persist post-timeout manual OAuth',
      () async {
    int responsesCalls = 0;
    int refreshCalls = 0;
    final mockClient = MockClient((request) async {
      final url = request.url.toString();
      if (url == ChatGptService.tokenEndpoint) {
        if (request.bodyFields['grant_type'] == 'refresh_token') {
          refreshCalls++;
          return http.Response(
            jsonEncode({
              'access_token': 'gpt_refreshed_tok',
              'refresh_token': 'gpt_refresh_2',
              'id_token': _buildTestIdToken(),
              'expires_in': 3600,
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'access_token': 'gpt_initial_tok',
            'refresh_token': 'gpt_refresh_1',
            'id_token': _buildTestIdToken(),
            'expires_in': 3600,
          }),
          200,
        );
      }
      if (url == ChatGptService.responsesEndpoint) {
        responsesCalls++;
        if (responsesCalls == 1) {
          return http.Response('Unauthorized', 401);
        }
        return http.Response(
          jsonEncode({
            'output_text': 'Keep Zone 2 aerobic volume steady this week.',
          }),
          200,
        );
      }
      return http.Response('{}', 404);
    });

    final chatGptStore = _InMemoryChatGptAuthStore();
    final planStore = _InMemoryTrainingPlanStore();
    final appState = _createTestAppState(
      chatGptService: ChatGptService(client: mockClient),
      chatGptAuthStore: chatGptStore,
      trainingPlanStore: planStore,
    );

    // Post-timeout manual code completion retains pending PKCE verifier & state
    late String capturedState;
    final failedConnect = await appState.connectChatGpt(
      'oaiapp_timeout',
      callbackPort: 0,
      onAuthorizeUrl: (authUrl) async {
        final uri = Uri.parse(authUrl);
        capturedState = uri.queryParameters['state']!;
        // Force server close with error to simulate timeout/failure while retaining pending PKCE state
        throw const ChatGptAuthException(
          'Timed out waiting for ChatGPT OAuth callback.',
        );
      },
    );
    expect(failedConnect, isFalse);
    expect(appState.chatGptError, contains('Timed out'));

    final recovered = await appState.completeChatGptOAuthWithCode(
      'http://127.0.0.1:9999/callback?code=post_timeout_code&state=$capturedState',
      clientId: 'oaiapp_timeout',
    );
    expect(recovered, isTrue);
    expect(appState.isChatGptConnected, isTrue);

    // Coach chat hits 401 -> refreshes token -> saves to store -> retries once and succeeds
    final chatOk = await appState.sendCoachChatMessage('How should I pace Sunday?');
    expect(chatOk, isTrue);
    expect(refreshCalls, 1);
    expect(responsesCalls, 2);
    expect((await chatGptStore.load())?.accessToken, 'gpt_refreshed_tok');
    expect(appState.coachMessages, hasLength(2));
    expect((await planStore.load())?.messages, hasLength(2));
  });

  testWidgets(
      'TrainingPlanView renders empty and active states cleanly in Light & Dark mode at 1100x750 & 1440x900',
      (WidgetTester tester) async {
    final now = DateTime.now();
    final planStore = _InMemoryTrainingPlanStore();
    final appState = _createTestAppState(trainingPlanStore: planStore);

    for (final viewport in const [Size(1100, 750), Size(1440, 900)]) {
      tester.view.physicalSize = viewport;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(PulseTrainingApp(appState: appState));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Training Plan').first);
      await tester.pumpAndSettle();

      expect(appState.currentNavIndex, 2);
      expect(find.text('Connect ChatGPT for AI Triathlon Coaching'),
          findsOneWidget);
      expect(find.text('Derived Athlete Telemetry & Zones'), findsOneWidget);
    }

    // Apply active plan and test Dark Mode at 1100x750
    await appState.applyGeneratedPlan(
      _buildSampleTrainingPlan(
        todayKey: PlannedWorkout.formatLocalDate(now),
        tomorrowKey:
            PlannedWorkout.formatLocalDate(now.add(const Duration(days: 1))),
        nextMonthKey:
            PlannedWorkout.formatLocalDate(now.add(const Duration(days: 30))),
      ),
    );
    appState.toggleDarkMode();
    await tester.pumpAndSettle();

    expect(find.text('Oceanside 70.3 Build'), findsOneWidget);
    expect(find.text('Sync Next 2 Weeks to Garmin'), findsOneWidget);
    expect(find.text('Week 1 • Base'), findsOneWidget);

    appState.selectPlannedWorkout(
      appState.activeTrainingPlan!.allWorkouts.first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Workout Details'), findsOneWidget);
    appState.selectPlannedWorkout(null);
    await tester.pumpAndSettle();
  });

  testWidgets(
      'M4 TrainingPlanView Mode 1: disconnected OAuth CTA, editable derived zones, unit toggle, Reset to Derived, Coach Chat & Generate/Apply Plan at 1100x750 & 1440x900',
      (WidgetTester tester) async {
    addTearDown(() => AppColors.isDark = false);

    final now = DateTime.now();
    final todayKey = PlannedWorkout.formatLocalDate(now);
    final tomorrowKey =
        PlannedWorkout.formatLocalDate(now.add(const Duration(days: 1)));

    String? capturedCoachRequestBody;
    String? capturedGenerateRequestBody;

    final mockChatGptClient = MockClient((request) async {
      if (request.url.toString() == ChatGptService.responsesEndpoint) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (body.containsKey('text')) {
          capturedGenerateRequestBody = request.body;
          final generatedPlanJson = {
            'id': 'plan_gen_m4',
            'name': 'Olympic Peak Build',
            'coachOverview':
                'Structured 8-week Olympic build with Run Intervals, Swim Long, Zwift Bike, and <=30m Brick.',
            'weeks': [
              {
                'weekNumber': 1,
                'startDate': todayKey,
                'phaseName': 'Base',
                'focusSummary': 'Aerobic speed & swim CSS control',
                'targetHours': 8.5,
                'targetTss': 430,
                'workouts': [
                  {
                    'id': 'wo_gen_run',
                    'date': todayKey,
                    'title': 'VO2 Track Intervals',
                    'discipline': 'run',
                    'archetype': 'intervals',
                    'estimatedDurationMinutes': 50,
                    'estimatedDistanceKm': 9.5,
                    'estimatedTss': 68,
                    'blocks': [
                      {
                        'repeatCount': 1,
                        'step': {
                          'kind': 'warmup',
                          'endCondition': 'time',
                          'endValue': 600,
                          'targetKind': 'heartRateZone',
                          'targetLow': 2,
                          'targetHigh': 2,
                        },
                      },
                      {
                        'repeatCount': 4,
                        'steps': [
                          {
                            'kind': 'interval',
                            'endCondition': 'distance',
                            'endValue': 800,
                            'targetKind': 'paceMps',
                            'targetLow': 3.9,
                            'targetHigh': 4.1,
                          },
                          {
                            'kind': 'recovery',
                            'endCondition': 'time',
                            'endValue': 90,
                            'targetKind': 'none',
                          },
                        ],
                      },
                    ],
                  },
                  {
                    'id': 'wo_gen_brick',
                    'date': tomorrowKey,
                    'title': 'Sunday Olympic Brick',
                    'discipline': 'bike',
                    'archetype': 'brick',
                    'estimatedDurationMinutes': 95,
                    'estimatedTss': 85,
                    'zwiftPrescription': {
                      'durationMinutes': 75,
                      'difficulty': 'Tempo',
                      'targetTss': 65,
                      'zwiftCategory': 'Tempo',
                      'suggestedSearchTerms': ['SST Med', 'Tempo 75'],
                    },
                    'brickRunLeg': {
                      'id': 'wo_gen_brick_run',
                      'date': tomorrowKey,
                      'title': 'T2 Transition Run',
                      'discipline': 'run',
                      'archetype': 'easy',
                      'estimatedDurationMinutes': 25,
                      'estimatedDistanceKm': 4.5,
                      'blocks': [
                        {
                          'repeatCount': 1,
                          'step': {
                            'kind': 'steady',
                            'endCondition': 'time',
                            'endValue': 1500,
                            'targetKind': 'heartRateZone',
                            'targetLow': 2,
                            'targetHigh': 3,
                          },
                        },
                      ],
                    },
                  },
                ],
              },
            ],
          };
          return http.Response(
            jsonEncode({'output_text': jsonEncode(generatedPlanJson)}),
            200,
          );
        }

        capturedCoachRequestBody = request.body;
        return http.Response(
          jsonEncode({
            'output_text':
                'Great focus! Let us schedule Tuesday intervals and keep Saturday brick run <= 25 min.',
          }),
          200,
        );
      }
      return http.Response('{}', 404);
    });

    final authStore = _InMemoryAuthStore();
    await authStore.save(
      GarminSession(
        domain: 'garmin.com',
        oauth1Token: 'o1',
        oauth1TokenSecret: 's1',
        accessToken: 'o2',
        expiresAt: DateTime.now().add(const Duration(hours: 2)),
        consumerKey: 'ck',
        consumerSecret: 'cs',
      ),
      profile: const GarminUserProfile(
          displayName: 'alex', fullName: 'Alex Rivera'),
    );

    final dataCache = _InMemoryDataCache();
    await dataCache.save(
      CachedTelemetrySnapshot(
        activities: [
          Activity(
            id: 'act_run_seed',
            title: 'Threshold 10K',
            description: 'Threshold run',
            discipline: SportDiscipline.run,
            timestamp: now.subtract(const Duration(days: 3)),
            formattedDate: '2026-11-20',
            location: 'Boston, MA',
            deviceHardware: 'Forerunner 970',
            sensorChain: 'Wrist HR',
            durationSeconds: 2700,
            movingTime: '45:00',
            elapsedTime: '45:00',
            distanceKm: 10.0,
            avgSpeedOrPace: '4:30 /km',
            maxSpeedOrPace: '4:05 /km',
            avgHr: 170,
            maxHr: 190,
            calories: 650,
            elevationGainM: 35,
            elevationLossM: 35,
          ),
          Activity(
            id: 'act_swim_seed',
            title: 'CSS Pool 1500m',
            description: 'Swim session',
            discipline: SportDiscipline.swim,
            timestamp: now.subtract(const Duration(days: 2)),
            formattedDate: '2026-11-21',
            location: 'Pool',
            deviceHardware: 'Forerunner 970',
            sensorChain: 'Optical HR',
            durationSeconds: 1500,
            movingTime: '25:00',
            elapsedTime: '25:00',
            distanceKm: 1.5,
            avgSpeedOrPace: '1:40 /100m',
            maxSpeedOrPace: '1:30 /100m',
            avgHr: 145,
            maxHr: 162,
            calories: 380,
            elevationGainM: 0,
            elevationLossM: 0,
          ),
          Activity(
            id: 'act_bike_seed',
            title: 'Threshold Trainer Ride',
            description: 'Bike ride',
            discipline: SportDiscipline.indoorBike,
            timestamp: now.subtract(const Duration(days: 1)),
            formattedDate: '2026-11-22',
            location: 'Zwift',
            deviceHardware: 'Tacx Neo',
            sensorChain: 'Power',
            durationSeconds: 3600,
            movingTime: '1:00:00',
            elapsedTime: '1:00:00',
            distanceKm: 36.0,
            avgSpeedOrPace: '36.0 km/h',
            maxSpeedOrPace: '45.0 km/h',
            avgHr: 154,
            maxHr: 176,
            calories: 820,
            elevationGainM: 220,
            elevationLossM: 220,
            avgPowerW: 255,
            normPowerW: 265,
          ),
        ],
        connectedDevices: const [],
        profile: const AthletePhysiologicalProfile(ctlFitness: 58.0),
      ),
    );

    final chatGptStore = _InMemoryChatGptAuthStore();
    final appState = _createTestAppState(
      garminService: GarminService(client: MockClient((_) async => http.Response('{}', 500))),
      authStore: authStore,
      dataCache: dataCache,
      chatGptService: ChatGptService(client: mockChatGptClient),
      chatGptAuthStore: chatGptStore,
    );
    await appState.restoreSession();

    // Test disconnected OAuth CTA -> opens ChatGptConnectDialog (no API key field)
    tester.view.physicalSize = const Size(1100, 750);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(PulseTrainingApp(appState: appState));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Training Plan').first);
    await tester.pumpAndSettle();

    expect(find.text('Connect ChatGPT for AI Triathlon Coaching'), findsOneWidget);
    expect(find.text('Derived Athlete Telemetry & Zones'), findsOneWidget);
    await tester.tap(find.text('Connect ChatGPT').first);
    await tester.pumpAndSettle();
    expect(find.text('Sign in with ChatGPT'), findsOneWidget);
    expect(find.textContaining('API Key'), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // Connect ChatGPT session and verify auto-derived editable zones + unit switching
    await chatGptStore.save(
      ChatGptSession(
        clientId: 'oaiapp_m4',
        accessToken: 'gpt_tok',
        refreshToken: 'gpt_ref',
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 2)),
        userName: 'Alex Rivera',
        userEmail: 'alex@example.com',
      ),
    );
    await appState.restoreSession();
    await tester.pumpAndSettle();

    expect(find.text('Connect ChatGPT for AI Triathlon Coaching'), findsNothing);
    expect(find.text('Grounded Garmin Fitness Context'), findsOneWidget);

    final derived = appState.deriveAthleteZones();
    final derivedRunText = UnitFormatter.formatPaceOrSpeed(
      SportDiscipline.run,
      1000.0 / derived.runThresholdPaceSecPerKm!,
      UnitSystem.metric,
    ).split(' ').first;
    expect(find.widgetWithText(TextField, derivedRunText), findsWidgets);

    // Toggle to Imperial and verify pace/CSS fields re-format cleanly
    appState.toggleUnitSystem();
    await tester.pumpAndSettle();
    expect(find.text('Run Threshold (/mi)'), findsOneWidget);
    expect(find.text('Swim CSS (/100yd)'), findsOneWidget);

    // Toggle back to Metric
    appState.toggleUnitSystem();
    await tester.pumpAndSettle();
    expect(find.text('Run Threshold (/km)'), findsOneWidget);
    expect(find.text('Swim CSS (/100m)'), findsOneWidget);

    // Edit Run Threshold Pace & Max HR, then Reset to Derived
    final fieldsInView = find.descendant(
      of: find.byType(TrainingPlanView),
      matching: find.byType(TextField),
    );
    // Field 0: Target Event Name, 1: Additional Notes, 2: Max HR, 3: LTHR, 4: Run Pace, 5: Swim CSS, 6: Bike FTP, 7: Chat input
    await tester.enterText(fieldsInView.at(2), '195');
    await tester.enterText(fieldsInView.at(4), '4:10');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, '195'), findsOneWidget);

    await tester.ensureVisible(find.text('Reset to Derived'));
    await tester.tap(find.text('Reset to Derived'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, derived.maxHr.toString()), findsWidgets);

    // Select Olympic distance & Run limiter, edit zones, send Coach Chat message
    await tester.ensureVisible(find.text('Olympic'));
    await tester.tap(find.text('Olympic'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Run').first);
    await tester.tap(find.text('Run').first);
    await tester.pumpAndSettle();

    await tester.enterText(fieldsInView.at(2), '192');
    await tester.enterText(fieldsInView.at(3), '174');
    await tester.enterText(fieldsInView.at(4), '4:20');
    await tester.pumpAndSettle();

    // Send coach chat message at 1440x900 in Dark Mode
    tester.view.physicalSize = const Size(1440, 900);
    appState.toggleDarkMode();
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Send'));
    await tester.enterText(fieldsInView.last, 'Keep Tuesday intervals fast.');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(capturedCoachRequestBody, isNotNull);
    expect(capturedCoachRequestBody, contains('Keep Tuesday intervals fast.'));
    expect(
      find.text(
          'Great focus! Let us schedule Tuesday intervals and keep Saturday brick run <= 25 min.'),
      findsOneWidget,
    );

    // Generate Plan -> shows Plan Preview Card -> Apply Plan to Calendar -> Mode 2
    await tester.ensureVisible(find.text('Generate Plan'));
    await tester.tap(find.text('Generate Plan'));
    await tester.pumpAndSettle();

    expect(capturedGenerateRequestBody, isNotNull);
    expect(find.text('Generated Plan Preview'), findsOneWidget);
    expect(find.text('Olympic Peak Build'), findsOneWidget);
    expect(find.text('Apply Plan to Calendar'), findsOneWidget);

    await tester.ensureVisible(find.text('Apply Plan to Calendar'));
    await tester.tap(find.text('Apply Plan to Calendar'));
    await tester.pumpAndSettle();

    // Now in Mode 2 with edited zones preserved (4:20 /km = 260 sec/km, maxHr 192, lthr 174)
    expect(appState.activeTrainingPlan, isNotNull);
    expect(appState.activeTrainingPlan!.config.raceDistance, 'Olympic');
    expect(appState.activeTrainingPlan!.config.zones.maxHr, 192);
    expect(appState.activeTrainingPlan!.config.zones.lthr, 174);
    expect(appState.activeTrainingPlan!.config.zones.runThresholdPaceSecPerKm,
        260.0);
    expect(appState.activeTrainingPlan!.config.zones.hrZones, hasLength(5));
    expect(find.text('Olympic Peak Build'), findsOneWidget);
    expect(find.text('Sync Next 2 Weeks to Garmin'), findsOneWidget);
    expect(find.text('Week 1 • Base'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'M4 TrainingPlanView Mode 2: Garmin 2-week bulk sync, Adapt Remaining Plan, Builder toggle, and workout click-through at 1100x750 & 1440x900',
      (WidgetTester tester) async {
    addTearDown(() => AppColors.isDark = false);

    final now = DateTime.now();
    final todayKey = PlannedWorkout.formatLocalDate(now);
    final tomorrowKey =
        PlannedWorkout.formatLocalDate(now.add(const Duration(days: 1)));
    final nextMonthKey =
        PlannedWorkout.formatLocalDate(now.add(const Duration(days: 30)));

    int garminCreateCalls = 0;
    int garminScheduleCalls = 0;
    final mockGarminClient = MockClient((request) async {
      final url = request.url.toString();
      if (url.contains('/workout-service/workout') && request.method == 'POST') {
        garminCreateCalls++;
        return http.Response(
            jsonEncode({'workoutId': 'gw_m4_$garminCreateCalls'}), 200);
      }
      if (url.contains('/workout-service/schedule/') &&
          request.method == 'POST') {
        garminScheduleCalls++;
        return http.Response(
            jsonEncode({'workoutScheduleId': 'gs_m4_$garminScheduleCalls'}),
            200);
      }
      return http.Response('{}', 200);
    });

    final mockChatGptClient = MockClient((request) async {
      if (request.url.toString() == ChatGptService.responsesEndpoint) {
        final adaptedPlanJson = {
          'id': 'plan_1',
          'name': 'Oceanside 70.3 Build (Adapted)',
          'coachOverview': 'Adapted volume after travel day.',
          'weeks': [
            {
              'weekNumber': 1,
              'startDate': todayKey,
              'phaseName': 'Base',
              'focusSummary': 'Adapted base week',
              'targetHours': 7.5,
              'targetTss': 380,
              'workouts': [
                {
                  'id': 'wo_run_1',
                  'date': todayKey,
                  'title': 'Threshold Cruise Intervals',
                  'discipline': 'run',
                  'archetype': 'threshold',
                  'estimatedDurationMinutes': 45,
                  'estimatedDistanceKm': 9.0,
                },
                {
                  'id': 'wo_adapted_swim',
                  'date': tomorrowKey,
                  'title': 'Adapted Recovery Swim',
                  'discipline': 'swim',
                  'archetype': 'easy',
                  'estimatedDurationMinutes': 35,
                  'estimatedDistanceKm': 1.5,
                },
              ],
            },
          ],
        };
        return http.Response(
          jsonEncode({'output_text': jsonEncode(adaptedPlanJson)}),
          200,
        );
      }
      return http.Response('{}', 404);
    });

    final authStore = _InMemoryAuthStore();
    await authStore.save(
      GarminSession(
        domain: 'garmin.com',
        oauth1Token: 'o1',
        oauth1TokenSecret: 's1',
        accessToken: 'o2',
        expiresAt: DateTime.now().add(const Duration(hours: 2)),
        consumerKey: 'ck',
        consumerSecret: 'cs',
      ),
      profile: const GarminUserProfile(
          displayName: 'alex', fullName: 'Alex Rivera'),
    );
    final chatGptStore = _InMemoryChatGptAuthStore();
    await chatGptStore.save(
      ChatGptSession(
        clientId: 'oaiapp_mode2',
        accessToken: 'gpt_tok',
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 2)),
      ),
    );
    final planStore = _InMemoryTrainingPlanStore();
    await planStore.save(
      _buildSampleTrainingPlan(
        todayKey: todayKey,
        tomorrowKey: tomorrowKey,
        nextMonthKey: nextMonthKey,
      ),
    );

    final appState = _createTestAppState(
      garminService: GarminService(client: mockGarminClient),
      authStore: authStore,
      chatGptService: ChatGptService(client: mockChatGptClient),
      chatGptAuthStore: chatGptStore,
      trainingPlanStore: planStore,
    );
    await appState.restoreSession();

    // Mark wo_run_1 completed before testing bulk sync & adapt
    await appState.updatePlannedWorkoutStatus(
      'wo_run_1',
      WorkoutStatus.completed,
    );

    for (final viewport in const [Size(1100, 750), Size(1440, 900)]) {
      tester.view.physicalSize = viewport;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(PulseTrainingApp(appState: appState));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Training Plan').first);
      await tester.pumpAndSettle();

      expect(find.text('Oceanside 70.3 Build'), findsOneWidget);
      expect(find.text('Week 1 • Base'), findsOneWidget);
      expect(find.text('Saturday Endurance Brick'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }

    // Toggle Dark Mode & tap Sync Next 2 Weeks to Garmin (pushes only wo_brick_1 run leg)
    appState.toggleDarkMode();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sync Next 2 Weeks to Garmin'));
    await tester.pumpAndSettle();

    expect(garminCreateCalls, 1);
    expect(garminScheduleCalls, 1);
    expect(find.text('1 Synced to Watch'), findsOneWidget);

    // Toggle Coach & Plan Builder and back
    await tester.tap(find.text('Coach & Plan Builder'));
    await tester.pumpAndSettle();
    expect(find.text('Back to Active Plan'), findsOneWidget);
    await tester.tap(find.text('Back to Active Plan'));
    await tester.pumpAndSettle();

    // Adapt Remaining Plan dialog
    await tester.tap(find.text('Adapt Remaining Plan'));
    await tester.pumpAndSettle();
    expect(find.text('Adaptation Feedback (optional)'), findsOneWidget);
    final dialogField = find.descendant(
      of: find.byType(Dialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(dialogField, 'Reduce tomorrow swim intensity.');
    await tester.tap(find.text('Adapt Plan'));
    await tester.pumpAndSettle();

    expect(find.text('Adapted Recovery Swim'), findsOneWidget);
    final preservedCompleted = appState.activeTrainingPlan!.allWorkouts
        .firstWhere((w) => w.id == 'wo_run_1');
    expect(preservedCompleted.status, WorkoutStatus.completed);

    // Click a workout card -> navigates to ScheduledWorkoutDetailView
    await tester.ensureVisible(find.text('Adapted Recovery Swim'));
    await tester.tap(find.text('Adapted Recovery Swim'));
    await tester.pumpAndSettle();
    expect(find.text('Workout Details'), findsOneWidget);
    expect(find.byType(ScheduledWorkoutDetailView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'M4 ScheduledWorkoutDetailView renders Run, Swim, Zwift, and Brick + Planned vs Actual with Garmin sync, status, reschedule & Back at 1100x750 & 1440x900',
      (WidgetTester tester) async {
    addTearDown(() => AppColors.isDark = false);

    final now = DateTime.now();
    final todayKey = PlannedWorkout.formatLocalDate(now);
    final tomorrowKey =
        PlannedWorkout.formatLocalDate(now.add(const Duration(days: 1)));

    int createCalls = 0;
    int scheduleCalls = 0;
    int deleteCalls = 0;
    final List<String> serializedWorkoutNames = [];

    final mockGarminClient = MockClient((request) async {
      final url = request.url.toString();
      if (url.contains('/workout-service/workout') && request.method == 'POST') {
        createCalls++;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        serializedWorkoutNames.add(body['workoutName'] as String);
        return http.Response(
            jsonEncode({'workoutId': 'gw_det_$createCalls'}), 200);
      }
      if (url.contains('/workout-service/schedule/') &&
          request.method == 'POST') {
        scheduleCalls++;
        return http.Response(
            jsonEncode({'workoutScheduleId': 'gs_det_$scheduleCalls'}), 200);
      }
      if (url.contains('/workout-service/') && request.method == 'DELETE') {
        deleteCalls++;
        return http.Response('', 204);
      }
      return http.Response('{}', 500);
    });

    final authStore = _InMemoryAuthStore();
    await authStore.save(
      GarminSession(
        domain: 'garmin.com',
        oauth1Token: 'o1',
        oauth1TokenSecret: 's1',
        accessToken: 'o2',
        expiresAt: DateTime.now().add(const Duration(hours: 2)),
        consumerKey: 'ck',
        consumerSecret: 'cs',
      ),
      profile: const GarminUserProfile(
          displayName: 'alex', fullName: 'Alex Rivera'),
    );

    final dataCache = _InMemoryDataCache();
    await dataCache.save(
      CachedTelemetrySnapshot(
        activities: [
          Activity(
            id: 'act_brick_bike',
            title: 'Saturday Aero Ride',
            description: 'Bike leg',
            discipline: SportDiscipline.indoorBike,
            timestamp: DateTime(now.year, now.month, now.day + 1, 8, 0),
            formattedDate: tomorrowKey,
            location: 'Zwift',
            deviceHardware: 'Tacx Neo',
            sensorChain: 'Power',
            durationSeconds: 5400,
            movingTime: '1:30:00',
            elapsedTime: '1:30:00',
            distanceKm: 48.0,
            avgSpeedOrPace: '32.0 km/h',
            maxSpeedOrPace: '41.0 km/h',
            avgHr: 149,
            maxHr: 168,
            calories: 980,
            elevationGainM: 310,
            elevationLossM: 310,
            avgPowerW: 220,
          ),
          Activity(
            id: 'act_brick_run',
            title: 'T2 Transition Brick Run',
            description: 'Run leg',
            discipline: SportDiscipline.run,
            timestamp: DateTime(now.year, now.month, now.day + 1, 9, 35),
            formattedDate: tomorrowKey,
            location: 'Boston, MA',
            deviceHardware: 'Forerunner 970',
            sensorChain: 'Wrist HR',
            durationSeconds: 1200,
            movingTime: '20:00',
            elapsedTime: '20:00',
            distanceKm: 4.0,
            avgSpeedOrPace: '5:00 /km',
            maxSpeedOrPace: '4:30 /km',
            avgHr: 158,
            maxHr: 170,
            calories: 270,
            elevationGainM: 15,
            elevationLossM: 15,
          ),
        ],
        connectedDevices: const [],
        profile: const AthletePhysiologicalProfile(),
      ),
    );

    final runWorkout = PlannedWorkout(
      id: 'det_run',
      date: todayKey,
      title: 'VO2 Track Intervals',
      discipline: SportDiscipline.run,
      archetype: WorkoutArchetype.intervals,
      estimatedDurationMinutes: 48,
      estimatedDistanceKm: 9.2,
      estimatedTss: 66,
      coachNotes: 'Relax shoulders on 800m repeats.',
      rationale: 'Builds aerobic ceiling.',
      blocks: const [
        WorkoutBlock(
          step: WorkoutStep(
            kind: StepKind.warmup,
            endCondition: StepEndCondition.time,
            endValue: 600,
            targetKind: StepTargetKind.heartRateZone,
            targetLow: 2,
            targetHigh: 2,
            notes: 'Easy jog',
          ),
        ),
        WorkoutBlock(
          repeatCount: 3,
          steps: [
            WorkoutStep(
              kind: StepKind.interval,
              endCondition: StepEndCondition.distance,
              endValue: 800,
              targetKind: StepTargetKind.paceMps,
              targetLow: 3.9,
              targetHigh: 4.1,
              notes: '5K effort',
            ),
            WorkoutStep(
              kind: StepKind.recovery,
              endCondition: StepEndCondition.lapButton,
              targetKind: StepTargetKind.none,
            ),
          ],
        ),
        WorkoutBlock(
          step: WorkoutStep(
            kind: StepKind.cooldown,
            endCondition: StepEndCondition.time,
            endValue: 600,
            targetKind: StepTargetKind.heartRateBpm,
            targetLow: 125,
            targetHigh: 140,
          ),
        ),
      ],
    );

    final swimWorkout = PlannedWorkout(
      id: 'det_swim',
      date: todayKey,
      title: 'Endurance Pool Swim',
      discipline: SportDiscipline.swim,
      archetype: WorkoutArchetype.long,
      estimatedDurationMinutes: 55,
      estimatedDistanceKm: 2.6,
      estimatedTss: 52,
      blocks: const [
        WorkoutBlock(
          step: WorkoutStep(
            kind: StepKind.warmup,
            endCondition: StepEndCondition.distance,
            endValue: 400,
            targetKind: StepTargetKind.none,
            strokeType: 'Freestyle',
            notes: 'Smooth catch',
          ),
        ),
        WorkoutBlock(
          repeatCount: 4,
          steps: [
            WorkoutStep(
              kind: StepKind.steady,
              endCondition: StepEndCondition.distance,
              endValue: 400,
              targetKind: StepTargetKind.paceMps,
              targetLow: 0.92,
              targetHigh: 0.98,
              strokeType: 'Freestyle',
            ),
            WorkoutStep(
              kind: StepKind.rest,
              endCondition: StepEndCondition.time,
              endValue: 30,
              targetKind: StepTargetKind.none,
            ),
          ],
        ),
      ],
    );

    final zwiftWorkout = PlannedWorkout(
      id: 'det_zwift',
      date: todayKey,
      title: 'Zwift Sweet Spot 60',
      discipline: SportDiscipline.indoorBike,
      archetype: WorkoutArchetype.zwiftRide,
      estimatedDurationMinutes: 60,
      estimatedTss: 58,
      zwiftPrescription: const ZwiftPrescription(
        durationMinutes: 60,
        difficulty: 'Sweet Spot',
        targetTss: 58,
        zwiftCategory: 'Sweet Spot',
        suggestedSearchTerms: ['SST Short', '2x15 Tempo'],
        cadenceFocus: '88-92 rpm',
        notes: 'Keep cadence smooth.',
      ),
    );

    final brickWorkout = PlannedWorkout(
      id: 'det_brick',
      date: tomorrowKey,
      title: 'Saturday Endurance Brick',
      discipline: SportDiscipline.bike,
      archetype: WorkoutArchetype.brick,
      estimatedDurationMinutes: 110,
      estimatedTss: 95,
      status: WorkoutStatus.completed,
      matchedActivityId: 'act_brick_bike',
      adherencePercent: 98.0,
      zwiftPrescription: const ZwiftPrescription(
        durationMinutes: 90,
        difficulty: 'Endurance',
        targetTss: 72,
        zwiftCategory: 'Endurance',
        suggestedSearchTerms: ['Zone 2 Endurance'],
      ),
      brickRunLeg: PlannedWorkout(
        id: 'det_brick_run',
        date: tomorrowKey,
        title: 'T2 Transition Run',
        discipline: SportDiscipline.run,
        archetype: WorkoutArchetype.easy,
        estimatedDurationMinutes: 20,
        estimatedDistanceKm: 3.8,
        status: WorkoutStatus.completed,
        matchedActivityId: 'act_brick_run',
        adherencePercent: 96.0,
        blocks: const [
          WorkoutBlock(
            step: WorkoutStep(
              kind: StepKind.steady,
              endCondition: StepEndCondition.time,
              endValue: 1200,
              targetKind: StepTargetKind.heartRateZone,
              targetLow: 2,
              targetHigh: 3,
            ),
          ),
        ],
      ),
    );

    final planStore = _InMemoryTrainingPlanStore();
    await planStore.save(
      TrainingPlan(
        id: 'plan_det',
        name: 'Triathlon Detail Test Plan',
        createdAt: DateTime.utc(2026, 11, 20),
        updatedAt: DateTime.utc(2026, 11, 20),
        config: const TrainingPlanConfig(
          raceName: 'Target Triathlon',
          raceDistance: '70.3',
          raceDate: '2027-04-04',
          weeklyHoursBudget: 9.0,
          longRunDay: 'Sunday',
          longRideDay: 'Saturday',
          restDay: 'Friday',
          limiterSport: 'Swim',
          zones: AthleteZonesSnapshot(
            maxHr: 190,
            lthr: 171,
            hrZones: [
              HrZoneRange(zone: 1, label: 'Recovery', lowBpm: 95, highBpm: 138),
              HrZoneRange(zone: 2, label: 'Aerobic', lowBpm: 139, highBpm: 152),
              HrZoneRange(zone: 3, label: 'Tempo', lowBpm: 153, highBpm: 159),
              HrZoneRange(
                  zone: 4, label: 'Threshold', lowBpm: 160, highBpm: 173),
              HrZoneRange(zone: 5, label: 'VO2 Max', lowBpm: 174, highBpm: 190),
            ],
            runThresholdPaceSecPerKm: 255,
            swimCssSecPer100m: 105,
            bikeFtpWatts: 250,
          ),
        ),
        coachOverview: 'Detail test overview.',
        weeks: [
          TrainingWeek(
            weekNumber: 1,
            startDate: todayKey,
            phaseName: 'Base',
            focusSummary: 'All 4 archetypes',
            targetHours: 6.0,
            targetTss: 320,
            workouts: [runWorkout, swimWorkout, zwiftWorkout, brickWorkout],
          ),
        ],
      ),
    );

    final appState = _createTestAppState(
      garminService: GarminService(client: mockGarminClient),
      authStore: authStore,
      dataCache: dataCache,
      trainingPlanStore: planStore,
    );
    await appState.restoreSession();

    tester.view.physicalSize = const Size(1100, 750);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(PulseTrainingApp(appState: appState));
    await tester.pumpAndSettle();
    appState.setNavIndex(2);
    await tester.pumpAndSettle();

    // 1) Run Intervals Detail View + Send to Garmin + Remove from Garmin
    appState.selectPlannedWorkout(
      appState.activeTrainingPlan!.allWorkouts
          .firstWhere((w) => w.id == 'det_run'),
    );
    await tester.pumpAndSettle();
    expect(find.text('VO2 Track Intervals'), findsOneWidget);
    expect(find.text('Workout Structure & Steps'), findsOneWidget);
    expect(find.text('3× Repeat'), findsOneWidget);
    expect(find.text('800 m'), findsOneWidget);
    expect(find.text('Lap Button'), findsOneWidget);
    expect(find.text('Send to Garmin'), findsOneWidget);

    await tester.tap(find.text('Send to Garmin'));
    await tester.pumpAndSettle();
    expect(createCalls, 1);
    expect(scheduleCalls, 1);
    expect(serializedWorkoutNames.last, 'VO2 Track Intervals');
    expect(find.text('Synced to Garmin ✓'), findsOneWidget);

    await tester.tap(find.text('Remove from Garmin'));
    await tester.pumpAndSettle();
    expect(deleteCalls, 2); // schedule + workout template
    expect(find.text('Send to Garmin'), findsOneWidget);

    // 2) Swim Long Detail View in Metric & Imperial
    appState.selectPlannedWorkout(
      appState.activeTrainingPlan!.allWorkouts
          .firstWhere((w) => w.id == 'det_swim'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Endurance Pool Swim'), findsOneWidget);
    expect(find.text('4× Repeat'), findsOneWidget);
    expect(find.text('Freestyle'), findsWidgets);
    expect(find.text('400 m'), findsWidgets);

    appState.toggleUnitSystem(); // Imperial
    await tester.pumpAndSettle();
    expect(find.text('437 yd'), findsWidgets);
    appState.toggleUnitSystem(); // Back to Metric
    await tester.pumpAndSettle();

    // 3) Zwift Ride Detail View -> Zwift card, NO Send to Garmin button
    appState.selectPlannedWorkout(
      appState.activeTrainingPlan!.allWorkouts
          .firstWhere((w) => w.id == 'det_zwift'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Zwift Cycling Prescription'), findsOneWidget);
    expect(find.text('SST Short'), findsOneWidget);
    expect(find.text('2x15 Tempo'), findsOneWidget);
    expect(
        find.text('Zwift Suggestion — Not pushed to Garmin'), findsWidgets);
    expect(find.text('Send to Garmin'), findsNothing);

    // 4) Brick Detail View at 1440x900 in Dark Mode + Planned vs Actual + Parent ID Garmin sync + Manual Controls + Back
    tester.view.physicalSize = const Size(1440, 900);
    appState.toggleDarkMode();
    appState.selectPlannedWorkout(
      appState.activeTrainingPlan!.allWorkouts
          .firstWhere((w) => w.id == 'det_brick'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Saturday Endurance Brick'), findsOneWidget);
    expect(find.text('T2 → Run'), findsOneWidget);
    expect(find.text('<= 30 min'), findsOneWidget);
    expect(find.text('Planned vs Actual'), findsOneWidget);
    expect(find.text('Bike Leg Comparison'), findsOneWidget);
    expect(find.text('Brick Run Leg Comparison'), findsOneWidget);
    expect(find.text('Open Activity Details'), findsNWidgets(2));

    // Send Run Leg to Garmin uses parent Brick workout.id
    await tester.tap(find.text('Send Run Leg to Garmin').first);
    await tester.pumpAndSettle();
    expect(serializedWorkoutNames.last, 'T2 Transition Run');
    expect(find.text('Synced to Garmin ✓'), findsOneWidget);

    // Reopen -> Skip -> Mark Done
    await tester.tap(find.text('Reopen'));
    await tester.pumpAndSettle();
    expect(appState.selectedPlannedWorkout!.status, WorkoutStatus.scheduled);

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(appState.selectedPlannedWorkout!.status, WorkoutStatus.skipped);

    await tester.tap(find.text('Mark Done'));
    await tester.pumpAndSettle();
    expect(appState.selectedPlannedWorkout!.status, WorkoutStatus.completed);

    // Reschedule via showDatePicker -> updates date and clears Garmin sync
    final targetDayNum = now.add(const Duration(days: 1)).day == 15 ? '16' : '15';
    await tester.tap(find.text('Reschedule'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(targetDayNum));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(appState.selectedPlannedWorkout!.isSyncedToGarmin, isFalse);

    // Back button returns to TrainingPlanView
    await tester.tap(
      find.descendant(
        of: find.byType(ScheduledWorkoutDetailView),
        matching: find.text('Training Plan'),
      ),
    );
    await tester.pumpAndSettle();
    expect(appState.selectedPlannedWorkout, isNull);
    expect(find.byType(TrainingPlanView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'M4 regression: TrainingPlanView Mode 1 handles low & partial LTHR without ArgumentError on Generate Plan and Coach Chat Send',
      (WidgetTester tester) async {
    final now = DateTime.now();
    final todayKey = PlannedWorkout.formatLocalDate(now);

    int coachCalls = 0;
    int planCalls = 0;
    final mockChatGptClient = MockClient((request) async {
      if (request.url.toString() == ChatGptService.responsesEndpoint) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (body.containsKey('text')) {
          planCalls++;
          final generatedPlanJson = {
            'id': 'plan_hr_reg_$planCalls',
            'name': 'HR Boundary Plan $planCalls',
            'coachOverview': 'Boundary HR zone check.',
            'weeks': [
              {
                'weekNumber': 1,
                'startDate': todayKey,
                'phaseName': 'Base',
                'focusSummary': 'Easy aerobic',
                'targetHours': 6.0,
                'targetTss': 300,
                'workouts': [
                  {
                    'id': 'wo_hr_$planCalls',
                    'date': todayKey,
                    'title': 'Easy Aerobic Run',
                    'discipline': 'run',
                    'archetype': 'easy',
                    'estimatedDurationMinutes': 40,
                    'estimatedDistanceKm': 7.0,
                  },
                ],
              },
            ],
          };
          return http.Response(
            jsonEncode({'output_text': jsonEncode(generatedPlanJson)}),
            200,
          );
        }
        coachCalls++;
        return http.Response(
          jsonEncode({'output_text': 'Coach reply #$coachCalls received.'}),
          200,
        );
      }
      return http.Response('{}', 404);
    });

    final chatGptStore = _InMemoryChatGptAuthStore();
    await chatGptStore.save(
      ChatGptSession(
        clientId: 'oaiapp_hr_reg',
        accessToken: 'gpt_tok',
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 2)),
      ),
    );
    final appState = _createTestAppState(
      chatGptService: ChatGptService(client: mockChatGptClient),
      chatGptAuthStore: chatGptStore,
    );
    await appState.restoreSession();

    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(PulseTrainingApp(appState: appState));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Training Plan').first);
    await tester.pumpAndSettle();

    final fieldsInView = find.descendant(
      of: find.byType(TrainingPlanView),
      matching: find.byType(TextField),
    );
    // Field 2: Max HR, Field 3: LTHR, Field 7 (last): Coach Chat input
    for (final (maxHr, lthr) in [(200, 120), (200, 100)]) {
      await tester.enterText(fieldsInView.at(2), '$maxHr');
      await tester.enterText(fieldsInView.at(3), '$lthr');
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Generate Plan'));
      await tester.tap(find.text('Generate Plan'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Generated Plan Preview'), findsOneWidget);
      expect(find.text('HR Boundary Plan $planCalls'), findsOneWidget);

      await tester.ensureVisible(find.text('Apply Plan to Calendar'));
      await tester.tap(find.text('Apply Plan to Calendar'));
      await tester.pumpAndSettle();

      final zones = appState.activeTrainingPlan!.config.zones;
      expect(zones.hrZones, hasLength(5));
      for (var i = 0; i < 5; i++) {
        expect(zones.hrZones[i].lowBpm, lessThan(zones.hrZones[i].highBpm));
        if (i > 0) {
          expect(
            zones.hrZones[i].lowBpm,
            greaterThan(zones.hrZones[i - 1].highBpm),
          );
        }
      }
      expect(zones.hrZones.last.highBpm, lessThanOrEqualTo(maxHr));

      await tester.tap(find.text('Coach & Plan Builder'));
      await tester.pumpAndSettle();
    }

    // Coach Chat Send with empty and partial LTHR ("", "11") with Max HR = 190
    for (final partialLthr in ['', '11']) {
      await tester.enterText(fieldsInView.at(2), '190');
      await tester.enterText(fieldsInView.at(3), partialLthr);
      await tester.enterText(fieldsInView.last, 'Check zones with $partialLthr');
      await tester.ensureVisible(find.text('Send'));
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Coach reply #$coachCalls received.'), findsOneWidget);
    }
    expect(coachCalls, 2);
  });

  testWidgets(
      'M4 regression: _AdaptPlanDialog displays planError inline when adaptRemainingPlan fails',
      (WidgetTester tester) async {
    final now = DateTime.now();
    final todayKey = PlannedWorkout.formatLocalDate(now);
    final tomorrowKey =
        PlannedWorkout.formatLocalDate(now.add(const Duration(days: 1)));
    final nextMonthKey =
        PlannedWorkout.formatLocalDate(now.add(const Duration(days: 30)));

    final mockChatGptClient = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'error': {'message': 'Upstream model temporarily unavailable'},
        }),
        500,
      );
    });

    final chatGptStore = _InMemoryChatGptAuthStore();
    await chatGptStore.save(
      ChatGptSession(
        clientId: 'oaiapp_adapt_err',
        accessToken: 'gpt_tok',
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 2)),
      ),
    );
    final planStore = _InMemoryTrainingPlanStore();
    await planStore.save(
      _buildSampleTrainingPlan(
        todayKey: todayKey,
        tomorrowKey: tomorrowKey,
        nextMonthKey: nextMonthKey,
      ),
    );

    final appState = _createTestAppState(
      chatGptService: ChatGptService(client: mockChatGptClient),
      chatGptAuthStore: chatGptStore,
      trainingPlanStore: planStore,
    );
    await appState.restoreSession();

    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(PulseTrainingApp(appState: appState));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Training Plan').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Adapt Remaining Plan'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);

    await tester.tap(find.text('Adapt Plan'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(appState.planError, isNotNull);
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text(appState.planError!),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'M4 regression: ScheduledWorkoutDetailView resets _copiedTerm on workout change, clamps pre-2020 reschedule date, and highlights Brick Run Leg bar on hover',
      (WidgetTester tester) async {
    String? copiedClipboardText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copiedClipboardText =
            (call.arguments as Map<dynamic, dynamic>)['text'] as String?;
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    final now = DateTime.now();
    final todayKey = PlannedWorkout.formatLocalDate(now);

    final zwiftA = PlannedWorkout(
      id: 'zwift_a',
      date: '2018-05-10',
      title: 'Legacy Zwift Ride A',
      discipline: SportDiscipline.indoorBike,
      archetype: WorkoutArchetype.zwiftRide,
      estimatedDurationMinutes: 60,
      zwiftPrescription: const ZwiftPrescription(
        durationMinutes: 60,
        difficulty: 'Endurance',
        targetTss: 55,
        zwiftCategory: 'Endurance',
        suggestedSearchTerms: ['Zone 2 Endurance'],
      ),
    );
    final zwiftB = PlannedWorkout(
      id: 'zwift_b',
      date: todayKey,
      title: 'Current Zwift Ride B',
      discipline: SportDiscipline.indoorBike,
      archetype: WorkoutArchetype.zwiftRide,
      estimatedDurationMinutes: 45,
      zwiftPrescription: const ZwiftPrescription(
        durationMinutes: 45,
        difficulty: 'Endurance',
        targetTss: 42,
        zwiftCategory: 'Endurance',
        suggestedSearchTerms: ['Zone 2 Endurance'],
      ),
    );
    final brickHover = PlannedWorkout(
      id: 'brick_hover',
      date: todayKey,
      title: 'Brick Hover Check',
      discipline: SportDiscipline.bike,
      archetype: WorkoutArchetype.brick,
      estimatedDurationMinutes: 80,
      status: WorkoutStatus.completed,
      brickRunLeg: PlannedWorkout(
        id: 'brick_hover_run',
        date: todayKey,
        title: 'T2 Brick Run Hover',
        discipline: SportDiscipline.run,
        archetype: WorkoutArchetype.easy,
        estimatedDurationMinutes: 20,
        status: WorkoutStatus.completed,
        matchedActivityId: 'missing_run_999',
        blocks: const [
          WorkoutBlock(
            step: WorkoutStep(
              kind: StepKind.warmup,
              endCondition: StepEndCondition.time,
              endValue: 600,
              targetKind: StepTargetKind.heartRateZone,
              targetLow: 1,
              targetHigh: 1,
            ),
          ),
          WorkoutBlock(
            step: WorkoutStep(
              kind: StepKind.steady,
              endCondition: StepEndCondition.time,
              endValue: 600,
              targetKind: StepTargetKind.heartRateZone,
              targetLow: 2,
              targetHigh: 2,
            ),
          ),
        ],
      ),
    );

    final planStore = _InMemoryTrainingPlanStore();
    await planStore.save(
      TrainingPlan(
        id: 'plan_detail_reg',
        name: 'Detail Regression Plan',
        createdAt: DateTime.utc(2026, 11, 20),
        updatedAt: DateTime.utc(2026, 11, 20),
        config: const TrainingPlanConfig(
          raceName: 'Target Triathlon',
          raceDistance: 'Olympic',
          raceDate: '2027-05-01',
          weeklyHoursBudget: 8.0,
          longRunDay: 'Sunday',
          longRideDay: 'Saturday',
          restDay: 'Friday',
          limiterSport: 'Run',
        ),
        coachOverview: 'Detail regression checks.',
        weeks: [
          TrainingWeek(
            weekNumber: 1,
            startDate: todayKey,
            phaseName: 'Base',
            focusSummary: 'Regression week',
            targetHours: 4.0,
            targetTss: 200,
            workouts: [zwiftA, zwiftB, brickHover],
          ),
        ],
      ),
    );

    final appState = _createTestAppState(trainingPlanStore: planStore);
    await appState.restoreSession();

    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(PulseTrainingApp(appState: appState));
    await tester.pumpAndSettle();
    appState.setNavIndex(2);
    appState.selectPlannedWorkout(zwiftA);
    await tester.pumpAndSettle();

    // Tap search term chip -> shows (Copied)
    await tester.ensureVisible(find.text('Zone 2 Endurance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zone 2 Endurance'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(copiedClipboardText, 'Zone 2 Endurance');
    expect(find.text('Zone 2 Endurance (Copied)'), findsOneWidget);

    // Pre-2020 date clamps cleanly to 2020 when opening Reschedule showDatePicker
    await tester.ensureVisible(find.text('Reschedule'));
    await tester.tap(find.text('Reschedule'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('2020'), findsWidgets);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // Switch to another workout -> _copiedTerm resets cleanly
    appState.selectPlannedWorkout(zwiftB);
    await tester.pumpAndSettle();
    expect(find.text('Current Zwift Ride B'), findsOneWidget);
    expect(find.text('Zone 2 Endurance (Copied)'), findsNothing);
    expect(find.text('Zone 2 Endurance'), findsOneWidget);

    // Switch to Brick workout -> verify missing brickRunLeg.matchedActivityId fallback & hover highlight
    appState.selectPlannedWorkout(brickHover);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('missing_run_999'),
      findsOneWidget,
    );

    // Find the 2 bar segment Containers inside Brick Run Leg's ClipRRect -> MouseRegion
    final barClip = find.descendant(
      of: find.byType(ScheduledWorkoutDetailView),
      matching: find.byType(ClipRRect),
    );
    final barMouseRegions = find.descendant(
      of: barClip.first,
      matching: find.byType(MouseRegion),
    );
    final barContainers = find.descendant(
      of: barMouseRegions,
      matching: find.byType(Container),
    );
    expect(barContainers, findsNWidgets(2));
    await tester.ensureVisible(barContainers.at(0));
    await tester.pumpAndSettle();

    // Before hover: both segments have opacity 0.9
    final beforeFirst = tester.widget<Container>(barContainers.at(0));
    final beforeSecond = tester.widget<Container>(barContainers.at(1));
    expect((beforeFirst.decoration! as BoxDecoration).color!.opacity,
        closeTo(0.9, 0.01));
    expect((beforeSecond.decoration! as BoxDecoration).color!.opacity,
        closeTo(0.9, 0.01));

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(barContainers.at(0)));
    await tester.pumpAndSettle();

    final afterFirst = tester.widget<Container>(barContainers.at(0));
    final afterSecond = tester.widget<Container>(barContainers.at(1));
    expect((afterFirst.decoration! as BoxDecoration).color!.opacity,
        closeTo(1.0, 0.01));
    expect((afterSecond.decoration! as BoxDecoration).color!.opacity,
        closeTo(0.45, 0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'M4 regression: TrainingPlanView Mode 1 renders with zero RenderFlex overflow at 1180x750, 1280x800, and 1300x750 in Light & Dark mode',
      (WidgetTester tester) async {
    addTearDown(() => AppColors.isDark = false);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final appState = _createTestAppState();

    for (final viewport in const [
      Size(1180, 750),
      Size(1280, 800),
      Size(1300, 750),
    ]) {
      for (final dark in const [false, true]) {
        AppColors.isDark = dark;
        tester.view.physicalSize = viewport;
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(PulseTrainingApp(appState: appState));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Training Plan').first);
        await tester.pumpAndSettle();

        expect(find.byType(TrainingPlanView), findsOneWidget);
        expect(find.text('Flexible (8 Weeks)'), findsOneWidget);
        expect(find.text('Weekly Hours Budget'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets(
      'M4 regression: TrainingPlanView and ScheduledWorkoutDetailView guard non-finite estimatedTss on Brick parent and brickRunLeg',
      (WidgetTester tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final todayKey = PlannedWorkout.formatLocalDate(DateTime.now());
    final infBrick = PlannedWorkout(
      id: 'wo_inf_brick',
      date: todayKey,
      title: 'Non-Finite Brick Check',
      discipline: SportDiscipline.bike,
      archetype: WorkoutArchetype.brick,
      estimatedDurationMinutes: 85,
      estimatedDistanceKm: double.nan,
      estimatedTss: double.infinity,
      adherencePercent: double.infinity,
      brickRunLeg: PlannedWorkout(
        id: 'wo_inf_brick_run',
        date: todayKey,
        title: 'T2 Non-Finite Run Leg',
        discipline: SportDiscipline.run,
        archetype: WorkoutArchetype.easy,
        estimatedDurationMinutes: 20,
        estimatedDistanceKm: double.nan,
        estimatedTss: double.infinity,
        blocks: const [
          WorkoutBlock(
            step: WorkoutStep(
              kind: StepKind.steady,
              endCondition: StepEndCondition.time,
              endValue: 1200,
              targetKind: StepTargetKind.heartRateZone,
              targetLow: 2,
              targetHigh: 2,
            ),
          ),
        ],
      ),
    );

    final planStore = _InMemoryTrainingPlanStore();
    await planStore.save(
      TrainingPlan(
        id: 'plan_inf_tss',
        name: 'Non-Finite TSS Plan',
        createdAt: DateTime.utc(2026, 11, 20),
        updatedAt: DateTime.utc(2026, 11, 20),
        config: const TrainingPlanConfig(
          raceName: 'Target Triathlon',
          raceDistance: '70.3',
          raceDate: '2027-05-01',
          weeklyHoursBudget: 8.0,
          longRunDay: 'Sunday',
          longRideDay: 'Saturday',
          restDay: 'Friday',
          limiterSport: 'Swim',
        ),
        coachOverview: 'Check non-finite TSS guards.',
        weeks: [
          TrainingWeek(
            weekNumber: 1,
            startDate: todayKey,
            phaseName: 'Base',
            focusSummary: 'Guard check',
            targetHours: 5.0,
            targetTss: 250,
            workouts: [infBrick],
          ),
        ],
      ),
    );

    final appState = _createTestAppState(trainingPlanStore: planStore);
    await appState.restoreSession();

    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;

    await tester.pumpWidget(PulseTrainingApp(appState: appState));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Training Plan').first);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Non-Finite Brick Check'), findsOneWidget);
    expect(find.textContaining('Infinity'), findsNothing);
    expect(find.textContaining('NaN'), findsNothing);

    await tester.tap(find.text('Non-Finite Brick Check'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(ScheduledWorkoutDetailView), findsOneWidget);
    expect(find.text('T2 → Run'), findsOneWidget);
    expect(find.text('Run Leg TSS'), findsNothing);
    expect(find.text('Target TSS'), findsNothing);
    expect(find.textContaining('Infinity'), findsNothing);
    expect(find.textContaining('NaN'), findsNothing);
  });

  testWidgets(
      'M4 regression: _AdaptPlanDialog Cancel after HTTP 500 clears stale planError on immediate reopen',
      (WidgetTester tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now();
    final todayKey = PlannedWorkout.formatLocalDate(now);
    final tomorrowKey =
        PlannedWorkout.formatLocalDate(now.add(const Duration(days: 1)));
    final nextMonthKey =
        PlannedWorkout.formatLocalDate(now.add(const Duration(days: 30)));

    final mockChatGptClient = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'error': {'message': 'Upstream model temporarily unavailable'},
        }),
        500,
      );
    });

    final chatGptStore = _InMemoryChatGptAuthStore();
    await chatGptStore.save(
      ChatGptSession(
        clientId: 'oaiapp_adapt_reopen',
        accessToken: 'gpt_tok',
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 2)),
      ),
    );
    final planStore = _InMemoryTrainingPlanStore();
    await planStore.save(
      _buildSampleTrainingPlan(
        todayKey: todayKey,
        tomorrowKey: tomorrowKey,
        nextMonthKey: nextMonthKey,
      ),
    );

    final appState = _createTestAppState(
      chatGptService: ChatGptService(client: mockChatGptClient),
      chatGptAuthStore: chatGptStore,
      trainingPlanStore: planStore,
    );
    await appState.restoreSession();

    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;

    await tester.pumpWidget(PulseTrainingApp(appState: appState));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Training Plan').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Adapt Remaining Plan'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);

    await tester.tap(find.text('Adapt Plan'));
    await tester.pumpAndSettle();
    expect(appState.planError, isNotNull);
    final capturedError = appState.planError!;
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text(capturedError),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(appState.planError, isNull);
    expect(find.text(capturedError), findsNothing);

    // Immediately reopen Adapt Remaining Plan -> zero stale error banner
    await tester.tap(find.text('Adapt Remaining Plan'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(appState.planError, isNull);
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text(capturedError),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}
