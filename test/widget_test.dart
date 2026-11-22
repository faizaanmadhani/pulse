import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pulse_training_hub/main.dart';
import 'package:pulse_training_hub/services/garmin_auth_store.dart';
import 'package:pulse_training_hub/services/garmin_service.dart';
import 'package:pulse_training_hub/services/local_data_cache.dart';
import 'package:pulse_training_hub/state/app_state.dart';

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

  @override
  Future<void> save(GarminSession session, {GarminUserProfile? profile}) async {
    _session = session;
    _profile = profile;
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

void main() {
  testWidgets('Signed-out app renders macOS UI with zero fake data and opens Garmin Sign In',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final appState = AppState(
      authStore: _InMemoryAuthStore(),
      dataCache: _InMemoryDataCache(),
      autoRestoreSession: false,
    );

    await tester.pumpWidget(PulseTrainingApp(appState: appState));
    await tester.pumpAndSettle();

    // Native macOS labels present
    expect(find.text('Pulse Training'), findsOneWidget);
    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('Calendar'), findsOneWidget);
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

  testWidgets('Signing in with Garmin pulls live activities & devices and Sign Out clears them',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mockClient = MockClient((request) async {
      final url = request.url.toString();
      if (url.contains('oauth_consumer.json')) {
        return http.Response(jsonEncode({'consumer_key': 'ck', 'consumer_secret': 'cs'}), 200);
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
        return http.Response(jsonEncode({'access_token': 'acc1', 'expires_in': 3600}), 200);
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
        return http.Response(jsonEncode({'restingHeartRate': 48, 'totalSteps': 9120}), 200);
      }
      if (url.contains('/hrv-service/hrv/')) {
        return http.Response(jsonEncode({'hrvSummary': {'lastNightAvg': 68}}), 200);
      }
      if (url.contains('/maxmet/latest/')) {
        return http.Response(jsonEncode([{'generic': {'vo2MaxPreciseValue': 54.2}}]), 200);
      }
      return http.Response('[]', 200);
    });

    final appState = AppState(
      garminService: GarminService(client: mockClient),
      authStore: _InMemoryAuthStore(),
      dataCache: _InMemoryDataCache(),
      autoRestoreSession: false,
    );

    await tester.pumpWidget(PulseTrainingApp(appState: appState));
    await tester.pumpAndSettle();

    final ok = await appState.signInWithGarmin(email: 'alex@example.com', password: 'secret');
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

  testWidgets('All 6 tabs, ActivityDetailView, Dark Mode, and Search render cleanly at 1100x750 min size',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 750);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    int profileCalls = 0;
    final mockClient = MockClient((request) async {
      final url = request.url.toString();
      if (url.contains('oauth_consumer.json')) {
        return http.Response(jsonEncode({'consumer_key': 'ck', 'consumer_secret': 'cs'}), 200);
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
        return http.Response(jsonEncode({'access_token': 'acc_refreshed', 'expires_in': 3600}), 200);
      }
      if (url.contains('/socialProfile')) {
        profileCalls++;
        if (profileCalls == 1) {
          // Simulate expired token -> 401 -> automatic OAuth1->OAuth2 refresh & retry!
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
        return http.Response(jsonEncode({'restingHeartRate': 46, 'totalSteps': 11200}), 200);
      }
      if (url.contains('/hrv-service/hrv/')) {
        return http.Response(jsonEncode({'hrvSummary': {'lastNightAvg': 74}}), 200);
      }
      if (url.contains('/maxmet/latest/')) {
        return http.Response(jsonEncode([{'generic': {'vo2MaxPreciseValue': 56.8}}]), 200);
      }
      return http.Response('[]', 200);
    });

    final appState = AppState(
      garminService: GarminService(client: mockClient),
      authStore: _InMemoryAuthStore(),
      dataCache: _InMemoryDataCache(),
      autoRestoreSession: false,
    );

    await tester.pumpWidget(PulseTrainingApp(appState: appState));
    await tester.pumpAndSettle();

    final ok = await appState.signInWithGarmin(email: 'alex@example.com', password: 'secret');
    expect(ok, isTrue);
    expect(profileCalls, 2); // Confirms automatic 401 refresh retry worked!
    await tester.pumpAndSettle();

    // Visit every single tab at 1100x750
    for (final tab in ['Calendar', 'Analytics', 'Activities', 'Strength', 'Garmin & Devices', 'Dashboard']) {
      await tester.tap(find.text(tab).first);
      await tester.pumpAndSettle();
    }

    // Search from Dashboard automatically switches to Activities & filters
    await tester.enterText(find.byType(TextField).first, 'Coastal');
    await tester.pumpAndSettle();
    expect(appState.currentNavIndex, 3);
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
}
