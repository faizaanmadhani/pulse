import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_training_hub/models/activity.dart';
import 'package:pulse_training_hub/models/device_status.dart';
import 'package:pulse_training_hub/models/performance_metrics.dart';
import 'package:pulse_training_hub/models/strava_enrichment.dart';
import 'package:pulse_training_hub/services/local_data_cache.dart';

void main() {
  late Directory tempDir;
  late String cachePath;
  late LocalDataCache cache;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pulse_local_cache_test_');
    cachePath = '${tempDir.path}/nested/telemetry_cache.json';
    cache = LocalDataCache(customFilePath: cachePath);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  CachedTelemetrySnapshot buildRichSnapshot() {
    final activityTimestamp = DateTime.utc(2026, 11, 20, 7, 15, 30);
    final stravaStartDate = DateTime.utc(2026, 11, 20, 7, 15, 42);
    final commentTime = DateTime.utc(2026, 11, 20, 9, 5, 0);
    final lastSyncedAt = DateTime.utc(2026, 11, 22, 6, 30, 0);

    final runActivity = Activity(
      id: 'garmin-run-101',
      title: 'Charles River Tempo Run',
      description: 'Progressive marathon-pace blocks along the river.',
      discipline: SportDiscipline.run,
      timestamp: activityTimestamp,
      formattedDate: 'Nov 20, 2026 • 7:15 AM',
      location: 'Boston, MA',
      deviceHardware: 'Garmin Forerunner 965',
      sensorChain: 'HRM-Pro Plus • Stryd Pod',
      distanceKm: 16.42,
      durationSeconds: 4125.5,
      movingTime: '1:08:45',
      elapsedTime: '1:09:30',
      avgSpeedOrPace: '4:11 /km',
      maxSpeedOrPace: '3:38 /km',
      avgHr: 161,
      maxHr: 179,
      elevationGainM: 124.5,
      elevationLossM: 121.0,
      avgPowerW: 332,
      normPowerW: 341,
      maxPowerW: 455,
      variabilityIndex: 1.03,
      intensityFactor: 0.91,
      tss: 89.4,
      calories: 1142,
      avgCadence: 182,
      maxCadence: 196,
      startLatitude: 42.3601,
      startLongitude: -71.0589,
      routePoints: const [
        GpsPoint(
          42.3601,
          -71.0589,
          speedMps: 4.02,
          timeSec: 0.0,
          distanceM: 0.0,
          elevationM: 12.4,
          heartRate: 142,
          cadence: 178,
          powerW: 315,
          verticalOscillationCm: 7.9,
          groundContactTimeMs: 222,
        ),
        GpsPoint(
          42.3612,
          -71.0604,
          speedMps: 4.18,
          timeSec: 30.0,
          distanceM: 125.4,
          elevationM: 14.1,
          heartRate: 158,
          cadence: 184,
          powerW: 342,
          verticalOscillationCm: 7.6,
          groundContactTimeMs: 214,
        ),
        GpsPoint(42.3625, -71.0620),
      ],
      runningDynamics: const RunningDynamics(
        groundContactTimeMs: 218,
        leftBalancePercent: 49.6,
        rightBalancePercent: 50.4,
        verticalOscillationCm: 7.8,
        strideLengthM: 1.24,
        runningPowerWatts: 342,
        verticalRatioPercent: 6.2,
      ),
      splits: const [
        ActivitySplit(
          splitNumber: 1,
          label: 'KM 1',
          time: '4:18',
          distanceKm: 1.0,
          paceOrSpeed: '4:18 /km',
          avgHr: 152,
          avgPower: 320,
          elevationDeltaM: 4.5,
          cadence: 180,
          gap: '4:15 /km',
          isFastest: false,
        ),
        ActivitySplit(
          splitNumber: 2,
          label: 'KM 2',
          time: '4:02',
          distanceKm: 1.0,
          paceOrSpeed: '4:02 /km',
          avgHr: 165,
          avgPower: 348,
          elevationDeltaM: -2.0,
          cadence: 185,
          gap: '4:04 /km',
          isFastest: true,
        ),
      ],
      segments: const [
        StarredSegment(
          name: 'Weeks Bridge Sprint',
          distanceKm: 0.85,
          avgGradePercent: 1.2,
          time: '3:08',
          prDelta: '-4s',
          avgWatts: 385,
          vam: 420,
          isPr: true,
        ),
      ],
      ergSteps: const [
        ErgStep(
          step: 1,
          name: 'Warmup',
          duration: '10:00',
          targetWatts: 220,
          actualWatts: 219,
          deltaWatts: -1,
          avgCadence: 90,
          avgHr: 132,
          adherencePercent: 99.5,
        ),
      ],
      swimSets: const [
        SwimIntervalSet(
          phase: 'Main Set',
          distanceM: 1000,
          repsDescription: '10x100m',
          avgPacePer100m: '1:28',
          swolf: 34,
          cadenceSpm: 32,
          restInterval: '15s',
        ),
      ],
      ergAdherence: 98.4,
      swolf: 34,
      gearName: 'Nike Vaporfly 3',
      gearUsageKm: 312.8,
    );

    const devices = [
      ConnectedDevice(
        id: 'dev-fr965',
        name: 'Garmin Forerunner 965',
        category: 'GPS Watch',
        protocol: 'Bluetooth BLE',
        state: DeviceConnectionState.connected,
        batteryPercent: 84,
        lastSyncTime: '2m ago',
        firmwareVersion: '20.32',
        telemetryChannels: 'GPS, HR, Running Dynamics, Power',
      ),
      ConnectedDevice(
        id: 'dev-kickr',
        name: 'Wahoo KICKR v6',
        category: 'Smart Trainer',
        protocol: 'ANT+ FE-C',
        state: DeviceConnectionState.standby,
        batteryPercent: 100,
        lastSyncTime: 'Yesterday',
        firmwareVersion: '5.2.14',
        telemetryChannels: 'Power, Cadence, ERG',
      ),
    ];

    const profile = AthletePhysiologicalProfile(
      acwrRatio: 1.12,
      acwrStatus: 'Optimal',
      ctlFitness: 78.5,
      atlFatigue: 84.2,
      tsbForm: -5.7,
      restingHr: 46,
      hrvMs: 79,
      ftpWatts: 315,
      weightKg: 68.4,
      vo2MaxEst: 61.5,
      enduranceScore: 8420,
      hillScore: 78,
      dailySteps: 14250,
      activeCalories: 1380,
    );

    final stravaEnrichment = StravaActivityEnrichment(
      stravaId: '9876543210',
      title: 'Morning Charles River Cruise',
      description: 'Felt super smooth on the return leg.',
      kudosCount: 24,
      commentCount: 2,
      comments: [
        StravaComment(
          id: 'c-1',
          authorName: 'Alex Rivera',
          text: 'Flying out there!',
          createdAt: commentTime,
        ),
        StravaComment(
          id: 'c-2',
          authorName: 'Sam Chen',
          text: 'Strong negative split.',
          createdAt: commentTime.add(const Duration(minutes: 12)),
        ),
      ],
      segmentEfforts: const [
        StravaSegmentEffort(
          id: 'seg-42',
          name: 'Harvard Bridge Straight',
          distanceM: 640.5,
          elapsedSec: 142,
          avgGrade: 0.4,
          prRank: 1,
          isKom: true,
          avgWatts: 365.5,
        ),
      ],
      bestEfforts: const [
        StravaBestEffort(
          name: '5k',
          distanceM: 5000.0,
          elapsedSec: 1185,
        ),
      ],
      sufferScore: 112.0,
      gearName: 'Nike Vaporfly 3',
      sportType: 'Run',
      startDate: stravaStartDate,
      distanceM: 16420.0,
      movingTimeSec: 4125,
    );

    return CachedTelemetrySnapshot(
      activities: [runActivity],
      connectedDevices: devices,
      profile: profile,
      stravaActivities: [stravaEnrichment],
      stravaEnrichments: {runActivity.id: stravaEnrichment},
      lastSyncedAt: lastSyncedAt,
    );
  }

  group('LocalDataCache', () {
    test('round-trips full snapshot with all nested models and telemetry',
        () async {
      final original = buildRichSnapshot();
      await cache.save(original);

      final loaded = await cache.load();
      expect(loaded, isNotNull);

      // lastSyncedAt
      expect(loaded!.lastSyncedAt, equals(original.lastSyncedAt));

      // Activity & primary telemetry
      expect(loaded.activities, hasLength(1));
      final origAct = original.activities.first;
      final loadedAct = loaded.activities.first;
      expect(loadedAct.id, equals(origAct.id));
      expect(loadedAct.title, equals(origAct.title));
      expect(loadedAct.description, equals(origAct.description));
      expect(loadedAct.discipline, equals(SportDiscipline.run));
      expect(loadedAct.timestamp, equals(origAct.timestamp));
      expect(loadedAct.formattedDate, equals(origAct.formattedDate));
      expect(loadedAct.location, equals(origAct.location));
      expect(loadedAct.deviceHardware, equals(origAct.deviceHardware));
      expect(loadedAct.sensorChain, equals(origAct.sensorChain));
      expect(loadedAct.distanceKm, equals(origAct.distanceKm));
      expect(loadedAct.durationSeconds, equals(origAct.durationSeconds));
      expect(loadedAct.movingTime, equals(origAct.movingTime));
      expect(loadedAct.elapsedTime, equals(origAct.elapsedTime));
      expect(loadedAct.avgSpeedOrPace, equals(origAct.avgSpeedOrPace));
      expect(loadedAct.maxSpeedOrPace, equals(origAct.maxSpeedOrPace));
      expect(loadedAct.avgHr, equals(origAct.avgHr));
      expect(loadedAct.maxHr, equals(origAct.maxHr));
      expect(loadedAct.elevationGainM, equals(origAct.elevationGainM));
      expect(loadedAct.elevationLossM, equals(origAct.elevationLossM));
      expect(loadedAct.avgPowerW, equals(origAct.avgPowerW));
      expect(loadedAct.normPowerW, equals(origAct.normPowerW));
      expect(loadedAct.maxPowerW, equals(origAct.maxPowerW));
      expect(loadedAct.variabilityIndex, equals(origAct.variabilityIndex));
      expect(loadedAct.intensityFactor, equals(origAct.intensityFactor));
      expect(loadedAct.tss, equals(origAct.tss));
      expect(loadedAct.calories, equals(origAct.calories));
      expect(loadedAct.avgCadence, equals(origAct.avgCadence));
      expect(loadedAct.maxCadence, equals(origAct.maxCadence));
      expect(loadedAct.startLatitude, equals(origAct.startLatitude));
      expect(loadedAct.startLongitude, equals(origAct.startLongitude));
      expect(loadedAct.ergAdherence, equals(origAct.ergAdherence));
      expect(loadedAct.swolf, equals(origAct.swolf));
      expect(loadedAct.gearName, equals(origAct.gearName));
      expect(loadedAct.gearUsageKm, equals(origAct.gearUsageKm));

      // GpsPoint full telemetry + minimal point
      expect(loadedAct.routePoints, hasLength(3));
      final p0 = loadedAct.routePoints[0];
      expect(p0.lat, equals(42.3601));
      expect(p0.lon, equals(-71.0589));
      expect(p0.speedMps, equals(4.02));
      expect(p0.timeSec, equals(0.0));
      expect(p0.distanceM, equals(0.0));
      expect(p0.elevationM, equals(12.4));
      expect(p0.heartRate, equals(142));
      expect(p0.cadence, equals(178));
      expect(p0.powerW, equals(315));
      expect(p0.verticalOscillationCm, equals(7.9));
      expect(p0.groundContactTimeMs, equals(222));

      final p2 = loadedAct.routePoints[2];
      expect(p2.lat, equals(42.3625));
      expect(p2.lon, equals(-71.0620));
      expect(p2.heartRate, isNull);
      expect(p2.powerW, isNull);
      expect(p2.groundContactTimeMs, isNull);

      // RunningDynamics
      final rd = loadedAct.runningDynamics;
      expect(rd, isNotNull);
      expect(rd!.groundContactTimeMs, equals(218));
      expect(rd.leftBalancePercent, equals(49.6));
      expect(rd.rightBalancePercent, equals(50.4));
      expect(rd.verticalOscillationCm, equals(7.8));
      expect(rd.strideLengthM, equals(1.24));
      expect(rd.runningPowerWatts, equals(342));
      expect(rd.verticalRatioPercent, equals(6.2));

      // ActivitySplit
      expect(loadedAct.splits, hasLength(2));
      expect(loadedAct.splits[0].splitNumber, equals(1));
      expect(loadedAct.splits[0].label, equals('KM 1'));
      expect(loadedAct.splits[0].avgPower, equals(320));
      expect(loadedAct.splits[0].elevationDeltaM, equals(4.5));
      expect(loadedAct.splits[0].cadence, equals(180));
      expect(loadedAct.splits[0].gap, equals('4:15 /km'));
      expect(loadedAct.splits[0].isFastest, isFalse);
      expect(loadedAct.splits[1].isFastest, isTrue);

      // StarredSegment, ErgStep, SwimIntervalSet
      expect(loadedAct.segments, hasLength(1));
      expect(loadedAct.segments.first.name, equals('Weeks Bridge Sprint'));
      expect(loadedAct.segments.first.isPr, isTrue);
      expect(loadedAct.ergSteps, hasLength(1));
      expect(loadedAct.ergSteps.first.adherencePercent, equals(99.5));
      expect(loadedAct.swimSets, hasLength(1));
      expect(loadedAct.swimSets.first.swolf, equals(34));

      // ConnectedDevice
      expect(loaded.connectedDevices, hasLength(2));
      expect(loaded.connectedDevices[0].id, equals('dev-fr965'));
      expect(loaded.connectedDevices[0].state,
          equals(DeviceConnectionState.connected));
      expect(loaded.connectedDevices[0].batteryPercent, equals(84));
      expect(loaded.connectedDevices[1].state,
          equals(DeviceConnectionState.standby));

      // AthletePhysiologicalProfile
      final prof = loaded.profile;
      expect(prof.acwrRatio, equals(1.12));
      expect(prof.acwrStatus, equals('Optimal'));
      expect(prof.ctlFitness, equals(78.5));
      expect(prof.atlFatigue, equals(84.2));
      expect(prof.tsbForm, equals(-5.7));
      expect(prof.restingHr, equals(46));
      expect(prof.hrvMs, equals(79));
      expect(prof.ftpWatts, equals(315));
      expect(prof.weightKg, equals(68.4));
      expect(prof.vo2MaxEst, equals(61.5));
      expect(prof.enduranceScore, equals(8420));
      expect(prof.hillScore, equals(78));
      expect(prof.dailySteps, equals(14250));
      expect(prof.activeCalories, equals(1380));

      // StravaActivityEnrichment (list + map + comments + segmentEfforts + bestEfforts)
      expect(loaded.stravaActivities, hasLength(1));
      expect(loaded.stravaEnrichments, contains('garmin-run-101'));
      final se = loaded.stravaEnrichments['garmin-run-101']!;
      expect(se.stravaId, equals('9876543210'));
      expect(se.title, equals('Morning Charles River Cruise'));
      expect(se.description, equals('Felt super smooth on the return leg.'));
      expect(se.kudosCount, equals(24));
      expect(se.commentCount, equals(2));
      expect(se.sufferScore, equals(112.0));
      expect(se.gearName, equals('Nike Vaporfly 3'));
      expect(se.sportType, equals('Run'));
      expect(se.distanceM, equals(16420.0));
      expect(se.movingTimeSec, equals(4125));
      expect(se.comments, hasLength(2));
      expect(se.comments.first.authorName, equals('Alex Rivera'));
      expect(se.comments.first.text, equals('Flying out there!'));
      expect(se.segmentEfforts, hasLength(1));
      expect(se.segmentEfforts.first.name, equals('Harvard Bridge Straight'));
      expect(se.segmentEfforts.first.isKom, isTrue);
      expect(se.segmentEfforts.first.prRank, equals(1));
      expect(se.segmentEfforts.first.avgWatts, equals(365.5));
      expect(se.bestEfforts, hasLength(1));
      expect(se.bestEfforts.first.name, equals('5k'));
      expect(se.bestEfforts.first.elapsedSec, equals(1185));
    });

    test('writes atomically without leaving .tmp file and sets 0600 on Unix',
        () async {
      await cache.save(buildRichSnapshot());

      final file = File(cachePath);
      final tmpFile = File('$cachePath.tmp');
      expect(await file.exists(), isTrue);
      expect(await tmpFile.exists(), isFalse);

      if (!Platform.isWindows) {
        final stat = await file.stat();
        expect(stat.mode & 0x1FF, equals(0x180)); // 0600 octal == 0x180
      }
    });

    test('returns null when cache file does not exist', () async {
      final loaded = await cache.load();
      expect(loaded, isNull);
    });

    test('returns null safely on corrupt or invalid cache files', () async {
      final file = File(cachePath);
      await file.parent.create(recursive: true);

      // Truncated / malformed JSON
      await file.writeAsString('{ "activities": [ { "id": "broken"');
      expect(await cache.load(), isNull);

      // Empty file
      await file.writeAsString('   ');
      expect(await cache.load(), isNull);

      // Non-object JSON
      await file.writeAsString('[1, 2, 3]');
      expect(await cache.load(), isNull);

      // Wrong field types
      await file.writeAsString('{"schemaVersion": 1, "activities": "invalid"}');
      expect(await cache.load(), isNull);

      // Unrelated JSON object
      await file.writeAsString('{"unexpected": true}');
      expect(await cache.load(), isNull);
    });

    test('clear deletes cache file and is idempotent when missing', () async {
      // Calling clear before file exists should not throw.
      await cache.clear();

      await cache.save(buildRichSnapshot());
      expect(await File(cachePath).exists(), isTrue);
      expect(await cache.load(), isNotNull);

      await cache.clear();
      expect(await File(cachePath).exists(), isFalse);
      expect(await cache.load(), isNull);

      // Second clear should also not throw.
      await cache.clear();
    });

    test('overwrites existing snapshot cleanly on subsequent save', () async {
      await cache.save(buildRichSnapshot());
      expect((await cache.load())!.activities, hasLength(1));

      const emptySnapshot = CachedTelemetrySnapshot();
      await cache.save(emptySnapshot);

      final loaded = await cache.load();
      expect(loaded, isNotNull);
      expect(loaded!.activities, isEmpty);
      expect(loaded.connectedDevices, isEmpty);
      expect(loaded.stravaActivities, isEmpty);
      expect(loaded.stravaEnrichments, isEmpty);
      expect(loaded.lastSyncedAt, isNull);
      expect(loaded.profile.hasAnyMetric, isFalse);
    });
  });
}
