import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_training_hub/components/gear_tracker_card.dart';
import 'package:pulse_training_hub/models/activity.dart';
import 'package:pulse_training_hub/models/gear_item.dart';
import 'package:pulse_training_hub/models/strava_enrichment.dart';
import 'package:pulse_training_hub/services/gear_tracker_service.dart';
import 'package:pulse_training_hub/utils/unit_formatter.dart';

Activity _makeActivity({
  required String id,
  required SportDiscipline discipline,
  required double distanceKm,
  required DateTime timestamp,
  String? gearName,
}) {
  return Activity(
    id: id,
    title: 'Test $id',
    description: '',
    discipline: discipline,
    timestamp: timestamp,
    formattedDate: 'Nov 2026',
    location: 'Test City',
    deviceHardware: 'Garmin Forerunner 965',
    sensorChain: 'HRM-Pro Plus',
    distanceKm: distanceKm,
    durationSeconds: 3600,
    movingTime: '1:00:00',
    elapsedTime: '1:00:00',
    avgSpeedOrPace: '4:30 /km',
    maxSpeedOrPace: '4:00 /km',
    avgHr: 150,
    maxHr: 175,
    elevationGainM: 100,
    elevationLossM: 100,
    calories: 600,
    gearName: gearName,
  );
}

StravaActivityEnrichment _makeEnrichment({
  required String stravaId,
  String? gearName,
  String sportType = 'Run',
  double distanceM = 10000,
}) {
  return StravaActivityEnrichment(
    stravaId: stravaId,
    title: 'Strava $stravaId',
    kudosCount: 5,
    commentCount: 0,
    gearName: gearName,
    sportType: sportType,
    startDate: DateTime.utc(2026, 11, 20),
    distanceM: distanceM,
    movingTimeSec: 3600,
  );
}

void main() {
  group('GearItem model', () {
    test('uses category default max distances and computes wear metrics', () {
      final shoe = GearItem(
        id: 'gear_shoe',
        name: 'Nike Vaporfly 3',
        category: GearCategory.shoes,
        totalDistanceKm: 325.0,
        activityCount: 20,
        source: 'Strava',
      );
      expect(shoe.maxDistanceKm, 650.0);
      expect(shoe.usageFraction, closeTo(0.5, 0.0001));
      expect(shoe.remainingKm, closeTo(325.0, 0.0001));
      expect(shoe.overdueKm, 0.0);
      expect(shoe.alertLevel, GearAlertLevel.ok);

      final bike = GearItem(
        id: 'gear_bike',
        name: 'Cervélo S5',
        category: GearCategory.bike,
        totalDistanceKm: 6400.0,
        activityCount: 80,
        source: 'Garmin',
      );
      expect(bike.maxDistanceKm, 8000.0);
      expect(bike.usageFraction, closeTo(0.80, 0.0001));
      expect(bike.remainingKm, closeTo(1600.0, 0.0001));
      expect(bike.alertLevel, GearAlertLevel.warning);

      final other = GearItem(
        id: 'gear_other',
        name: 'Custom Gear',
        category: GearCategory.other,
        totalDistanceKm: 1050.0,
        activityCount: 15,
        source: 'Garmin',
      );
      expect(other.maxDistanceKm, 1000.0);
      expect(other.usageFraction, closeTo(1.05, 0.0001));
      expect(other.remainingKm, 0.0);
      expect(other.overdueKm, closeTo(50.0, 0.0001));
      expect(other.alertLevel, GearAlertLevel.replace);
    });

    test('alert thresholds trigger at exactly 80% warning and 100% replace', () {
      final belowWarning = GearItem(
        id: 'a',
        name: 'Shoe A',
        category: GearCategory.shoes,
        totalDistanceKm: 519.9,
        maxDistanceKm: 650.0,
        activityCount: 10,
        source: 'Garmin',
      );
      expect(belowWarning.alertLevel, GearAlertLevel.ok);

      final atWarning = GearItem(
        id: 'b',
        name: 'Shoe B',
        category: GearCategory.shoes,
        totalDistanceKm: 520.0, // 520 / 650 == 0.80
        maxDistanceKm: 650.0,
        activityCount: 10,
        source: 'Garmin',
      );
      expect(atWarning.alertLevel, GearAlertLevel.warning);

      final atReplace = GearItem(
        id: 'c',
        name: 'Shoe C',
        category: GearCategory.shoes,
        totalDistanceKm: 650.0, // 650 / 650 == 1.00
        maxDistanceKm: 650.0,
        activityCount: 10,
        source: 'Strava',
      );
      expect(atReplace.alertLevel, GearAlertLevel.replace);
    });

    test('toJson and fromJson round-trip cleanly', () {
      final original = GearItem(
        id: 'gear_nike_pegasus_41',
        name: 'Nike Pegasus 41',
        category: GearCategory.shoes,
        totalDistanceKm: 412.5,
        maxDistanceKm: 700.0,
        activityCount: 34,
        lastUsedAt: DateTime.utc(2026, 11, 21, 14, 30),
        source: 'Garmin + Strava',
      );

      final decoded = GearItem.fromJson(original.toJson());
      expect(decoded.id, original.id);
      expect(decoded.name, original.name);
      expect(decoded.category, GearCategory.shoes);
      expect(decoded.totalDistanceKm, original.totalDistanceKm);
      expect(decoded.maxDistanceKm, original.maxDistanceKm);
      expect(decoded.activityCount, original.activityCount);
      expect(decoded.lastUsedAt, original.lastUsedAt);
      expect(decoded.source, 'Garmin + Strava');
    });
  });

  group('GearTrackerService.computeGearInventory', () {
    test('aggregates distance, session count, and latest timestamp from Garmin + Strava', () {
      final t1 = DateTime.utc(2026, 10, 1, 8, 0);
      final t2 = DateTime.utc(2026, 10, 10, 8, 0);
      final t3 = DateTime.utc(2026, 10, 20, 8, 0);

      final activities = [
        // Garmin-only gear
        _makeActivity(
          id: 'act_1',
          discipline: SportDiscipline.run,
          distanceKm: 15.0,
          timestamp: t1,
          gearName: 'Nike Vaporfly 3',
        ),
        // Strava enrichment overrides empty Garmin gear and merges into same shoe (case-insensitive)
        _makeActivity(
          id: 'act_2',
          discipline: SportDiscipline.run,
          distanceKm: 21.1,
          timestamp: t3,
          gearName: null,
        ),
        // Strava enrichment overrides different Garmin gear name
        _makeActivity(
          id: 'act_3',
          discipline: SportDiscipline.bike,
          distanceKm: 85.0,
          timestamp: t2,
          gearName: 'Old Bike Label',
        ),
        // Activity without any gear should be ignored
        _makeActivity(
          id: 'act_4',
          discipline: SportDiscipline.swim,
          distanceKm: 2.5,
          timestamp: t3,
          gearName: '   ',
        ),
      ];

      final enrichments = {
        'act_2': _makeEnrichment(
          stravaId: 's_2',
          gearName: 'Nike Vaporfly 3',
        ),
        'act_3': _makeEnrichment(
          stravaId: 's_3',
          gearName: 'Specialized Tarmac SL8',
          sportType: 'Ride',
        ),
      };

      final items = GearTrackerService.computeGearInventory(
        activities,
        enrichments,
      );

      expect(items.length, 2);

      final bike = items.firstWhere((i) => i.name == 'Specialized Tarmac SL8');
      expect(bike.category, GearCategory.bike);
      expect(bike.totalDistanceKm, closeTo(85.0, 0.001));
      expect(bike.activityCount, 1);
      expect(bike.lastUsedAt, t2);
      expect(bike.source, 'Strava');

      final shoe = items.firstWhere((i) => i.name == 'Nike Vaporfly 3');
      expect(shoe.category, GearCategory.shoes);
      expect(shoe.totalDistanceKm, closeTo(36.1, 0.001));
      expect(shoe.activityCount, 2);
      expect(shoe.lastUsedAt, t3);
      expect(shoe.source, 'Garmin + Strava');
    });

    test('classifies shoes vs bikes via keywords and discipline fallback', () {
      final now = DateTime.utc(2026, 11, 20);
      final activities = [
        _makeActivity(
          id: '1',
          discipline: SportDiscipline.strength,
          distanceKm: 10.0,
          timestamp: now,
          gearName: 'Hoka Clifton 9',
        ),
        _makeActivity(
          id: '2',
          discipline: SportDiscipline.strength,
          distanceKm: 50.0,
          timestamp: now,
          gearName: 'Wahoo KICKR Core',
        ),
        _makeActivity(
          id: '3',
          discipline: SportDiscipline.run,
          distanceKm: 12.0,
          timestamp: now,
          gearName: 'Daily Trainer Alpha',
        ),
        _makeActivity(
          id: '4',
          discipline: SportDiscipline.indoorBike,
          distanceKm: 40.0,
          timestamp: now,
          gearName: 'Winter Rig',
        ),
        _makeActivity(
          id: '5',
          discipline: SportDiscipline.swim,
          distanceKm: 3.0,
          timestamp: now,
          gearName: 'Roka Wetsuit',
        ),
      ];

      final items = GearTrackerService.computeGearInventory(
        activities,
        const {},
      );

      expect(
        items.firstWhere((i) => i.name == 'Hoka Clifton 9').category,
        GearCategory.shoes,
      );
      expect(
        items.firstWhere((i) => i.name == 'Wahoo KICKR Core').category,
        GearCategory.bike,
      );
      expect(
        items.firstWhere((i) => i.name == 'Daily Trainer Alpha').category,
        GearCategory.shoes,
      );
      expect(
        items.firstWhere((i) => i.name == 'Winter Rig').category,
        GearCategory.bike,
      );
      expect(
        items.firstWhere((i) => i.name == 'Roka Wetsuit').category,
        GearCategory.other,
      );
    });

    test('sorts by alertLevel priority (replace -> warning -> ok) then totalDistanceKm desc', () {
      final now = DateTime.utc(2026, 11, 20);
      final activities = [
        // OK bike with very high distance (2000 / 8000 = 25%)
        _makeActivity(
          id: 'ok_bike',
          discipline: SportDiscipline.bike,
          distanceKm: 2000.0,
          timestamp: now,
          gearName: 'Cervélo P5',
        ),
        // OK shoe with lower distance (200 / 650 = 31%)
        _makeActivity(
          id: 'ok_shoe',
          discipline: SportDiscipline.run,
          distanceKm: 200.0,
          timestamp: now,
          gearName: 'Asics Novablast 4',
        ),
        // Warning shoe (550 / 650 = 84.6%)
        _makeActivity(
          id: 'warn_shoe',
          discipline: SportDiscipline.run,
          distanceKm: 550.0,
          timestamp: now,
          gearName: 'Saucony Endorphin Pro',
        ),
        // Replace shoe (700 / 650 = 107.7%)
        _makeActivity(
          id: 'replace_shoe',
          discipline: SportDiscipline.run,
          distanceKm: 700.0,
          timestamp: now,
          gearName: 'Brooks Ghost 16',
        ),
        // Replace bike with higher km than replace shoe (8200 / 8000 = 102.5%)
        _makeActivity(
          id: 'replace_bike',
          discipline: SportDiscipline.bike,
          distanceKm: 8200.0,
          timestamp: now,
          gearName: 'Canyon Aeroad',
        ),
      ];

      final items = GearTrackerService.computeGearInventory(
        activities,
        const {},
      );

      expect(
        items.map((i) => i.name).toList(),
        [
          'Canyon Aeroad', // replace, 8200 km
          'Brooks Ghost 16', // replace, 700 km
          'Saucony Endorphin Pro', // warning, 550 km
          'Cervélo P5', // ok, 2000 km
          'Asics Novablast 4', // ok, 200 km
        ],
      );
    });

    test('applies customMaxKm overrides', () {
      final now = DateTime.utc(2026, 11, 20);
      final activities = [
        _makeActivity(
          id: '1',
          discipline: SportDiscipline.run,
          distanceKm: 420.0,
          timestamp: now,
          gearName: 'Altra Escalante',
        ),
      ];

      final items = GearTrackerService.computeGearInventory(
        activities,
        const {},
        customMaxKm: {'Altra Escalante': 400.0},
      );

      expect(items.single.maxDistanceKm, 400.0);
      expect(items.single.alertLevel, GearAlertLevel.replace);
    });
  });

  group('GearTrackerCard widget', () {
    testWidgets('renders empty state with Connect Strava button when disconnected',
        (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GearTrackerCard(
              items: const [],
              unitSystem: UnitSystem.metric,
              isStravaConnected: false,
              onConnectStrava: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.text('Gear Mileage Tracker'), findsOneWidget);
      expect(find.text('No gear logged yet'), findsOneWidget);
      expect(find.text('Connect Strava'), findsOneWidget);

      await tester.tap(find.text('Connect Strava'));
      expect(tapped, isTrue);
    });

    testWidgets('renders gear items with alert badges and formatted distances',
        (tester) async {
      final items = [
        GearItem(
          id: 'gear_shoe_1',
          name: 'Nike Vaporfly 3',
          category: GearCategory.shoes,
          totalDistanceKm: 680.0,
          maxDistanceKm: 650.0,
          activityCount: 42,
          source: 'Strava',
        ),
        GearItem(
          id: 'gear_shoe_2',
          name: 'Hoka Clifton 9',
          category: GearCategory.shoes,
          totalDistanceKm: 550.0,
          maxDistanceKm: 650.0,
          activityCount: 31,
          source: 'Garmin + Strava',
        ),
        GearItem(
          id: 'gear_bike_1',
          name: 'Trek Madone',
          category: GearCategory.bike,
          totalDistanceKm: 1200.0,
          maxDistanceKm: 8000.0,
          activityCount: 18,
          source: 'Garmin',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: GearTrackerCard(
                items: items,
                unitSystem: UnitSystem.metric,
                isStravaConnected: true,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Nike Vaporfly 3'), findsOneWidget);
      expect(find.text('Replace Now'), findsOneWidget);
      expect(find.text('30.0 km over limit'), findsOneWidget);
      expect(find.text('42 sessions'), findsOneWidget);

      expect(find.text('Hoka Clifton 9'), findsOneWidget);
      expect(find.text('Replace Soon'), findsOneWidget);
      expect(find.text('100.0 km remaining'), findsOneWidget);

      expect(find.text('Trek Madone'), findsOneWidget);
      expect(find.text('1,200.0 km'), findsOneWidget);
      expect(find.text('2 Alerts'), findsOneWidget);
    });
  });
}
