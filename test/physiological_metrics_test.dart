import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_training_hub/components/zones_and_drift_cards.dart';
import 'package:pulse_training_hub/models/activity.dart';
import 'package:pulse_training_hub/utils/physiological_metrics.dart';
import 'package:pulse_training_hub/utils/unit_formatter.dart';

Activity _makeActivity({
  String id = 'act-1',
  SportDiscipline discipline = SportDiscipline.run,
  DateTime? timestamp,
  double distanceKm = 15.0,
  double durationSeconds = 4200,
  String movingTime = '1:10:00',
  int avgHr = 150,
  int maxHr = 190,
  int? avgPowerW,
  List<GpsPoint> routePoints = const [],
  List<ActivitySplit> splits = const [],
}) {
  return Activity(
    id: id,
    title: 'Test Session',
    description: '',
    discipline: discipline,
    timestamp: timestamp ?? DateTime(2026, 11, 20, 8, 0),
    formattedDate: 'Nov 20',
    location: 'Test',
    deviceHardware: 'Garmin Forerunner 965',
    sensorChain: 'HRM-Pro',
    distanceKm: distanceKm,
    durationSeconds: durationSeconds,
    movingTime: movingTime,
    elapsedTime: movingTime,
    avgSpeedOrPace: '4:40 /km',
    maxSpeedOrPace: '4:00 /km',
    avgHr: avgHr,
    maxHr: maxHr,
    elevationGainM: 100,
    elevationLossM: 100,
    avgPowerW: avgPowerW,
    calories: 800,
    routePoints: routePoints,
    splits: splits,
  );
}

void main() {
  group('computeActivityHrZones', () {
    test('computes Z1–Z5 distribution from routePoints with timeSec deltas', () {
      // maxHr = 200 -> Z1 <120, Z2 120-139, Z3 140-159, Z4 160-179, Z5 >=180
      final points = <GpsPoint>[
        const GpsPoint(0, 0, timeSec: 0, heartRate: 110),
        const GpsPoint(0, 0, timeSec: 100, heartRate: 110), // +100s Z1
        const GpsPoint(0, 0, timeSec: 300, heartRate: 130), // +200s Z2
        const GpsPoint(0, 0, timeSec: 600, heartRate: 150), // +300s Z3
        const GpsPoint(0, 0, timeSec: 850, heartRate: 170), // +250s Z4
        const GpsPoint(0, 0, timeSec: 1000, heartRate: 185), // +150s Z5
      ];
      final activity = _makeActivity(
        maxHr: 200,
        durationSeconds: 1000,
        routePoints: points,
      );

      final zones = computeActivityHrZones(activity);
      expect(zones, hasLength(5));
      expect(zones[0].zone, 1);
      expect(zones[0].seconds, closeTo(100, 1e-6));
      expect(zones[0].percentage, closeTo(10.0, 1e-6));

      expect(zones[1].zone, 2);
      expect(zones[1].seconds, closeTo(200, 1e-6));
      expect(zones[1].percentage, closeTo(20.0, 1e-6));

      expect(zones[2].zone, 3);
      expect(zones[2].seconds, closeTo(300, 1e-6));
      expect(zones[2].percentage, closeTo(30.0, 1e-6));

      expect(zones[3].zone, 4);
      expect(zones[3].seconds, closeTo(250, 1e-6));
      expect(zones[3].percentage, closeTo(25.0, 1e-6));

      expect(zones[4].zone, 5);
      expect(zones[4].seconds, closeTo(150, 1e-6));
      expect(zones[4].percentage, closeTo(15.0, 1e-6));

      final sumPct = zones.fold<double>(0, (s, b) => s + b.percentage);
      expect(sumPct, closeTo(100.0, 1e-6));
    });

    test('uses maxHrOverride and defaults to 190 when activity.maxHr <= 140', () {
      // With default maxHr = 190, 152 bpm is 80.0% -> Z4
      final lowMaxActivity = _makeActivity(
        avgHr: 152,
        maxHr: 130, // <= 140 -> should fallback to 190
        durationSeconds: 600,
      );
      final defaultZones = computeActivityHrZones(lowMaxActivity);
      expect(defaultZones[3].seconds, closeTo(600, 1e-6)); // Z4
      expect(defaultZones[3].percentage, closeTo(100.0, 1e-6));

      // With maxHrOverride = 200, 152 bpm is 76% -> Z3
      final overrideZones = computeActivityHrZones(
        lowMaxActivity,
        maxHrOverride: 200,
      );
      expect(overrideZones[2].seconds, closeTo(600, 1e-6)); // Z3
      expect(overrideZones[2].percentage, closeTo(100.0, 1e-6));
    });

    test('falls back to splits when routePoints are absent', () {
      final activity = _makeActivity(
        maxHr: 200,
        durationSeconds: 600,
        splits: const [
          ActivitySplit(
            splitNumber: 1,
            label: 'Km 1',
            time: '5:00',
            distanceKm: 1.0,
            paceOrSpeed: '5:00 /km',
            avgHr: 130, // Z2
          ),
          ActivitySplit(
            splitNumber: 2,
            label: 'Km 2',
            time: '5:00',
            distanceKm: 1.0,
            paceOrSpeed: '5:00 /km',
            avgHr: 170, // Z4
          ),
        ],
      );

      final zones = computeActivityHrZones(activity);
      expect(zones, hasLength(5));
      expect(zones[1].seconds, closeTo(300, 1e-6));
      expect(zones[1].percentage, closeTo(50.0, 1e-6));
      expect(zones[3].seconds, closeTo(300, 1e-6));
      expect(zones[3].percentage, closeTo(50.0, 1e-6));
    });

    test('returns empty list when activity has no HR telemetry', () {
      final activity = _makeActivity(avgHr: 0, maxHr: 0, durationSeconds: 1800);
      expect(computeActivityHrZones(activity), isEmpty);
    });
  });

  group('computeActivityPowerZones', () {
    test('computes Coggan Z1–Z5 power zones from routePoints', () {
      // FTP = 250 W:
      // Z1 <55% (<137.5), Z2 56-75% (<=187.5), Z3 76-90% (<=225),
      // Z4 91-105% (<=262.5), Z5 >105% (>262.5)
      final points = <GpsPoint>[
        const GpsPoint(0, 0, timeSec: 0, powerW: 120),
        const GpsPoint(0, 0, timeSec: 100, powerW: 120), // +100s Z1
        const GpsPoint(0, 0, timeSec: 300, powerW: 170), // +200s Z2
        const GpsPoint(0, 0, timeSec: 600, powerW: 210), // +300s Z3
        const GpsPoint(0, 0, timeSec: 800, powerW: 250), // +200s Z4
        const GpsPoint(0, 0, timeSec: 1000, powerW: 310), // +200s Z5
      ];
      final ride = _makeActivity(
        discipline: SportDiscipline.bike,
        durationSeconds: 1000,
        routePoints: points,
      );

      final zones = computeActivityPowerZones(ride, ftpWatts: 250);
      expect(zones, hasLength(5));
      expect(zones[0].seconds, closeTo(100, 1e-6));
      expect(zones[1].seconds, closeTo(200, 1e-6));
      expect(zones[2].seconds, closeTo(300, 1e-6));
      expect(zones[3].seconds, closeTo(200, 1e-6));
      expect(zones[4].seconds, closeTo(200, 1e-6));
      expect(zones[3].percentage, closeTo(20.0, 1e-6));
      expect(zones[4].percentage, closeTo(20.0, 1e-6));
    });

    test('falls back to splits avgPower when routePoints lack power', () {
      final ride = _makeActivity(
        discipline: SportDiscipline.bike,
        durationSeconds: 1200,
        splits: const [
          ActivitySplit(
            splitNumber: 1,
            label: 'Lap 1',
            time: '10:00',
            distanceKm: 5.0,
            paceOrSpeed: '30.0 km/h',
            avgHr: 140,
            avgPower: 175, // 70% of 250 -> Z2
          ),
          ActivitySplit(
            splitNumber: 2,
            label: 'Lap 2',
            time: '10:00',
            distanceKm: 5.5,
            paceOrSpeed: '33.0 km/h',
            avgHr: 165,
            avgPower: 250, // 100% of 250 -> Z4
          ),
        ],
      );

      final zones = computeActivityPowerZones(ride, ftpWatts: 250);
      expect(zones, hasLength(5));
      expect(zones[1].seconds, closeTo(600, 1e-6));
      expect(zones[3].seconds, closeTo(600, 1e-6));
    });

    test('returns empty list when activity has no power data', () {
      final run = _makeActivity(
        discipline: SportDiscipline.run,
        avgPowerW: null,
        routePoints: const [
          GpsPoint(0, 0, timeSec: 0, heartRate: 140),
          GpsPoint(0, 0, timeSec: 60, heartRate: 145),
        ],
      );
      expect(computeActivityPowerZones(run), isEmpty);
    });
  });

  group('computeWeeklyHrZones', () {
    test('aggregates HR zones only for activities within the last N days', () {
      final now = DateTime(2026, 11, 22, 12, 0);

      final recent1 = _makeActivity(
        id: 'recent-1',
        timestamp: now.subtract(const Duration(days: 1)),
        avgHr: 130, // 65% of 200 -> Z2
        maxHr: 200,
        durationSeconds: 1800, // 30m
      );
      final recent2 = _makeActivity(
        id: 'recent-2',
        timestamp: now.subtract(const Duration(days: 5)),
        avgHr: 170, // 85% of 200 -> Z4
        maxHr: 200,
        durationSeconds: 600, // 10m
      );
      final tooOld = _makeActivity(
        id: 'old-1',
        timestamp: now.subtract(const Duration(days: 10)),
        avgHr: 185, // Z5 — should be excluded
        maxHr: 200,
        durationSeconds: 3600,
      );

      final weekly = computeWeeklyHrZones(
        [recent1, recent2, tooOld],
        days: 7,
        maxHr: 200,
        now: now,
      );

      expect(weekly, hasLength(5));
      expect(weekly[1].seconds, closeTo(1800, 1e-6));
      expect(weekly[1].percentage, closeTo(75.0, 1e-6));
      expect(weekly[3].seconds, closeTo(600, 1e-6));
      expect(weekly[3].percentage, closeTo(25.0, 1e-6));
      expect(weekly[4].seconds, closeTo(0, 1e-6));
    });
  });

  group('computeCardiacDrift', () {
    test('returns null for sessions shorter than 60 minutes', () {
      final shortRun = _makeActivity(
        discipline: SportDiscipline.run,
        durationSeconds: 3599,
        movingTime: '59:59',
        routePoints: List.generate(
          20,
          (i) => GpsPoint(
            0,
            0,
            timeSec: i * 180.0,
            heartRate: 145 + (i ~/ 2),
            speedMps: 3.3,
          ),
        ),
      );
      expect(computeCardiacDrift(shortRun), isNull);
    });

    test('returns null for non-run/bike disciplines such as swim or strength', () {
      final longSwim = _makeActivity(
        discipline: SportDiscipline.swim,
        durationSeconds: 4000,
        routePoints: List.generate(
          20,
          (i) => GpsPoint(0, 0, timeSec: i * 200.0, heartRate: 140, speedMps: 1.3),
        ),
      );
      expect(computeCardiacDrift(longSwim), isNull);
    });

    test('computes Pa:Hr decoupling accurately for a 70-min run with warmup skip', () {
      // 20 points total -> warmup skips first 2 points (10%).
      // Remaining 18 points split into 9 (1st half) and 9 (2nd half).
      // Make warmup points wild (HR 100, speed 2.0) to verify they are skipped.
      final points = <GpsPoint>[
        const GpsPoint(0, 0, timeSec: 0, heartRate: 100, speedMps: 2.0),
        const GpsPoint(0, 0, timeSec: 210, heartRate: 105, speedMps: 2.2),
        // 1st half (9 points): constant speed 3.333 m/s (5:00 /km), HR 150
        for (int i = 0; i < 9; i++)
          GpsPoint(0, 0, timeSec: 420.0 + i * 210, heartRate: 150, speedMps: 10.0 / 3.0),
        // 2nd half (9 points): same speed 3.333 m/s, HR drifts to 156 (+4% HR -> ~3.85% decoupling)
        for (int i = 0; i < 9; i++)
          GpsPoint(0, 0, timeSec: 2310.0 + i * 210, heartRate: 156, speedMps: 10.0 / 3.0),
      ];

      final longRun = _makeActivity(
        discipline: SportDiscipline.run,
        durationSeconds: 4200,
        routePoints: points,
      );

      final result = computeCardiacDrift(longRun, unit: UnitSystem.metric);
      expect(result, isNotNull);
      expect(result!.metricLabel, 'Pa:Hr');
      expect(result.isLongSession, isTrue);
      expect(result.firstHalfAvgHr, closeTo(150.0, 1e-6));
      expect(result.secondHalfAvgHr, closeTo(156.0, 1e-6));

      // EF1 = (3.3333 * 60) / 150 = 200 / 150 = 1.3333
      // EF2 = (3.3333 * 60) / 156 = 200 / 156 = 1.28205
      // Decoupling = ((1.3333 - 1.28205) / 1.3333) * 100 = 3.846%
      expect(result.firstHalfEf, closeTo(200.0 / 150.0, 1e-4));
      expect(result.secondHalfEf, closeTo(200.0 / 156.0, 1e-4));
      expect(result.decouplingPercent, closeTo(3.84615, 1e-3));
      expect(result.statusLabel, 'Excellent (<5%)');
      expect(result.firstHalfOutput, '5:00 /km');
      expect(result.secondHalfOutput, '5:00 /km');

      // Imperial formatting check
      final imperialResult =
          computeCardiacDrift(longRun, unit: UnitSystem.imperial);
      expect(imperialResult!.firstHalfOutput, contains('/mi'));
    });

    test('computes Pw:Hr decoupling and status badges for a 90-min bike ride', () {
      // 20 points -> skip 2 warmup -> 9 first half, 9 second half
      // 1st half: 250 W @ 150 bpm -> EF1 = 1.6667
      // 2nd half: 240 W @ 160 bpm -> EF2 = 1.5000
      // Decoupling = ((1.6667 - 1.5) / 1.6667) * 100 = 10.0% -> Moderate (5–10%)
      final moderateRide = _makeActivity(
        discipline: SportDiscipline.bike,
        durationSeconds: 5400,
        routePoints: [
          const GpsPoint(0, 0, timeSec: 0, heartRate: 110, powerW: 150),
          const GpsPoint(0, 0, timeSec: 270, heartRate: 120, powerW: 180),
          for (int i = 0; i < 9; i++)
            GpsPoint(0, 0, timeSec: 540.0 + i * 270, heartRate: 150, powerW: 250),
          for (int i = 0; i < 9; i++)
            GpsPoint(0, 0, timeSec: 2970.0 + i * 270, heartRate: 160, powerW: 240),
        ],
      );

      final res = computeCardiacDrift(moderateRide);
      expect(res, isNotNull);
      expect(res!.metricLabel, 'Pw:Hr');
      expect(res.firstHalfOutput, '250 W');
      expect(res.secondHalfOutput, '240 W');
      expect(res.decouplingPercent, closeTo(10.0, 1e-3));
      expect(res.statusLabel, 'Moderate (5–10%)');

      // High drift (>10%): 2nd half drops to 220 W @ 165 bpm -> EF2 = 1.3333 -> 20% drift
      final highDriftRide = _makeActivity(
        discipline: SportDiscipline.indoorBike,
        durationSeconds: 5400,
        routePoints: [
          const GpsPoint(0, 0, timeSec: 0, heartRate: 110, powerW: 150),
          const GpsPoint(0, 0, timeSec: 270, heartRate: 120, powerW: 180),
          for (int i = 0; i < 9; i++)
            GpsPoint(0, 0, timeSec: 540.0 + i * 270, heartRate: 150, powerW: 250),
          for (int i = 0; i < 9; i++)
            GpsPoint(0, 0, timeSec: 2970.0 + i * 270, heartRate: 165, powerW: 220),
        ],
      );

      final highRes = computeCardiacDrift(highDriftRide);
      expect(highRes, isNotNull);
      expect(highRes!.decouplingPercent, closeTo(20.0, 1e-3));
      expect(highRes.statusLabel, 'High Drift (>10%)');
    });

    test('falls back to splits (>= 4) when routePoints are absent', () {
      final splitRun = _makeActivity(
        discipline: SportDiscipline.run,
        durationSeconds: 3600,
        splits: const [
          ActivitySplit(
            splitNumber: 1,
            label: 'Km 1',
            time: '5:00',
            distanceKm: 1.0,
            paceOrSpeed: '5:00 /km',
            avgHr: 145,
          ),
          ActivitySplit(
            splitNumber: 2,
            label: 'Km 2',
            time: '5:00',
            distanceKm: 1.0,
            paceOrSpeed: '5:00 /km',
            avgHr: 145,
          ),
          ActivitySplit(
            splitNumber: 3,
            label: 'Km 3',
            time: '5:00',
            distanceKm: 1.0,
            paceOrSpeed: '5:00 /km',
            avgHr: 150,
          ),
          ActivitySplit(
            splitNumber: 4,
            label: 'Km 4',
            time: '5:00',
            distanceKm: 1.0,
            paceOrSpeed: '5:00 /km',
            avgHr: 150,
          ),
        ],
      );

      final res = computeCardiacDrift(splitRun);
      expect(res, isNotNull);
      expect(res!.metricLabel, 'Pa:Hr');
      expect(res.firstHalfAvgHr, closeTo(145.0, 1e-6));
      expect(res.secondHalfAvgHr, closeTo(150.0, 1e-6));
      expect(res.decouplingPercent, closeTo(((150 - 145) / 150) * 100.0, 1e-3));
      expect(res.statusLabel, 'Excellent (<5%)');
    });
  });

  group('Zones & Drift UI cards', () {
    testWidgets('TimeInZoneCard renders HR zones and toggles to Power zones',
        (tester) async {
      final activity = _makeActivity(
        discipline: SportDiscipline.bike,
        maxHr: 200,
        durationSeconds: 1000,
        routePoints: const [
          GpsPoint(0, 0, timeSec: 0, heartRate: 130, powerW: 170),
          GpsPoint(0, 0, timeSec: 500, heartRate: 130, powerW: 170),
          GpsPoint(0, 0, timeSec: 1000, heartRate: 170, powerW: 250),
        ],
      );

      final hrZones = computeActivityHrZones(activity);
      final powerZones = computeActivityPowerZones(activity, ftpWatts: 250);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: 600,
                child: TimeInZoneCard(
                  title: 'Zone Distribution',
                  subtitle: 'Session breakdown',
                  hrZones: hrZones,
                  powerZones: powerZones,
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Zone Distribution'), findsOneWidget);
      expect(find.text('Heart Rate'), findsOneWidget);
      expect(find.text('Power'), findsOneWidget);
      expect(find.text('Aerobic'), findsOneWidget);

      await tester.tap(find.text('Power'));
      await tester.pumpAndSettle();

      expect(find.text('Endurance'), findsOneWidget);
    });

    testWidgets('CardiacDriftCard renders decoupling percentage and halves',
        (tester) async {
      const sampleResult = CardiacDriftResult(
        decouplingPercent: 3.8,
        firstHalfEf: 1.42,
        secondHalfEf: 1.37,
        firstHalfAvgHr: 148,
        secondHalfAvgHr: 154,
        firstHalfOutput: '4:52 /km',
        secondHalfOutput: '4:55 /km',
        metricLabel: 'Pa:Hr',
        statusLabel: 'Excellent (<5%)',
        isLongSession: true,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 520,
              child: CardiacDriftCard(result: sampleResult),
            ),
          ),
        ),
      );

      expect(find.text('+3.8%'), findsOneWidget);
      expect(find.text('Pa:Hr'), findsOneWidget);
      expect(find.text('Excellent (<5%)'), findsOneWidget);
      expect(find.text('148 bpm'), findsOneWidget);
      expect(find.text('154 bpm'), findsOneWidget);
      expect(find.text('4:52 /km'), findsOneWidget);
      expect(find.text('4:55 /km'), findsOneWidget);
    });
  });
}
