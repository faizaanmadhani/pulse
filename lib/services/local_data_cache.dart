import 'dart:convert';
import 'dart:io';

import '../models/activity.dart';
import '../models/device_status.dart';
import '../models/performance_metrics.dart';
import '../models/strava_enrichment.dart';

/// Immutable snapshot of all locally cached telemetry and enrichment data
/// required for instant app startup.
class CachedTelemetrySnapshot {
  final List<Activity> activities;
  final List<ConnectedDevice> connectedDevices;
  final AthletePhysiologicalProfile profile;
  final List<StravaActivityEnrichment> stravaActivities;
  final Map<String, StravaActivityEnrichment> stravaEnrichments;
  final DateTime? lastSyncedAt;

  const CachedTelemetrySnapshot({
    this.activities = const [],
    this.connectedDevices = const [],
    this.profile = const AthletePhysiologicalProfile(),
    this.stravaActivities = const [],
    this.stravaEnrichments = const {},
    this.lastSyncedAt,
  });
}

/// Persists synced Garmin activities, GPS routes, splits, devices, athlete
/// physiology profile, and Strava enrichments to local disk for instant startup.
class LocalDataCache {
  static const int schemaVersion = 1;

  final String? customFilePath;

  const LocalDataCache({this.customFilePath});

  File _getCacheFile() {
    if (customFilePath != null && customFilePath!.isNotEmpty) {
      return File(customFilePath!);
    }
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      return File(
        '$home/Library/Application Support/pulse_training_hub/telemetry_cache.json',
      );
    }
    return File(
      '${Directory.systemTemp.path}/pulse_training_hub_telemetry_cache.json',
    );
  }

  /// Atomically writes [snapshot] to disk via a `.tmp` file + rename and
  /// restricts permissions to owner-only (`0600`) on macOS/Linux.
  Future<void> save(CachedTelemetrySnapshot snapshot) async {
    final file = _getCacheFile();
    await file.parent.create(recursive: true);

    final encoded = jsonEncode(_encodeSnapshot(snapshot));
    final tmpFile = File('${file.path}.tmp');

    await tmpFile.writeAsString(encoded, flush: true);

    if (!Platform.isWindows) {
      try {
        await Process.run('chmod', ['600', tmpFile.path]);
      } catch (_) {}
    }

    await tmpFile.rename(file.path);

    if (!Platform.isWindows) {
      try {
        await Process.run('chmod', ['600', file.path]);
      } catch (_) {}
    }
  }

  /// Reads and deserializes the cached snapshot from disk.
  /// Returns `null` if the file is missing, empty, or corrupt (never throws).
  Future<CachedTelemetrySnapshot?> load() async {
    try {
      final file = _getCacheFile();
      if (!await file.exists()) return null;

      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return null;

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;

      final hasExpectedKey = decoded.containsKey('schemaVersion') ||
          decoded.containsKey('activities') ||
          decoded.containsKey('connectedDevices') ||
          decoded.containsKey('profile') ||
          decoded.containsKey('stravaActivities') ||
          decoded.containsKey('stravaEnrichments') ||
          decoded.containsKey('lastSyncedAt');
      if (!hasExpectedKey) return null;

      return _decodeSnapshot(decoded);
    } catch (_) {
      return null;
    }
  }

  /// Safely deletes the cache file (and any stale `.tmp` file) if present.
  Future<void> clear() async {
    try {
      final file = _getCacheFile();
      if (await file.exists()) {
        await file.delete();
      }
      final tmpFile = File('${file.path}.tmp');
      if (await tmpFile.exists()) {
        await tmpFile.delete();
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  static Map<String, dynamic> _encodeSnapshot(CachedTelemetrySnapshot s) {
    return {
      'schemaVersion': schemaVersion,
      'lastSyncedAt': s.lastSyncedAt?.toUtc().toIso8601String(),
      'activities': s.activities.map(_encodeActivity).toList(),
      'connectedDevices': s.connectedDevices.map(_encodeDevice).toList(),
      'profile': _encodeProfile(s.profile),
      'stravaActivities': s.stravaActivities.map((e) => e.toJson()).toList(),
      'stravaEnrichments': s.stravaEnrichments.map(
        (key, value) => MapEntry(key, value.toJson()),
      ),
    };
  }

  static Map<String, dynamic> _encodeActivity(Activity a) {
    return {
      'id': a.id,
      'title': a.title,
      'description': a.description,
      'discipline': a.discipline.name,
      'timestamp': a.timestamp.toUtc().toIso8601String(),
      'formattedDate': a.formattedDate,
      'location': a.location,
      'deviceHardware': a.deviceHardware,
      'sensorChain': a.sensorChain,
      'distanceKm': a.distanceKm,
      'durationSeconds': a.durationSeconds,
      'movingTime': a.movingTime,
      'elapsedTime': a.elapsedTime,
      'avgSpeedOrPace': a.avgSpeedOrPace,
      'maxSpeedOrPace': a.maxSpeedOrPace,
      'avgHr': a.avgHr,
      'maxHr': a.maxHr,
      'elevationGainM': a.elevationGainM,
      'elevationLossM': a.elevationLossM,
      'avgPowerW': a.avgPowerW,
      'normPowerW': a.normPowerW,
      'maxPowerW': a.maxPowerW,
      'variabilityIndex': a.variabilityIndex,
      'intensityFactor': a.intensityFactor,
      'tss': a.tss,
      'calories': a.calories,
      'avgCadence': a.avgCadence,
      'maxCadence': a.maxCadence,
      'startLatitude': a.startLatitude,
      'startLongitude': a.startLongitude,
      'routePoints': a.routePoints.map(_encodeGpsPoint).toList(),
      'runningDynamics': a.runningDynamics == null
          ? null
          : _encodeRunningDynamics(a.runningDynamics!),
      'splits': a.splits.map(_encodeSplit).toList(),
      'segments': a.segments.map(_encodeStarredSegment).toList(),
      'ergSteps': a.ergSteps.map(_encodeErgStep).toList(),
      'swimSets': a.swimSets.map(_encodeSwimIntervalSet).toList(),
      'ergAdherence': a.ergAdherence,
      'swolf': a.swolf,
      'gearName': a.gearName,
      'gearUsageKm': a.gearUsageKm,
    };
  }

  static Map<String, dynamic> _encodeGpsPoint(GpsPoint p) {
    return <String, dynamic>{
      'lat': p.lat,
      'lon': p.lon,
      if (p.speedMps != null) 'speedMps': p.speedMps,
      if (p.timeSec != null) 'timeSec': p.timeSec,
      if (p.distanceM != null) 'distanceM': p.distanceM,
      if (p.elevationM != null) 'elevationM': p.elevationM,
      if (p.heartRate != null) 'heartRate': p.heartRate,
      if (p.cadence != null) 'cadence': p.cadence,
      if (p.powerW != null) 'powerW': p.powerW,
      if (p.verticalOscillationCm != null)
        'verticalOscillationCm': p.verticalOscillationCm,
      if (p.groundContactTimeMs != null)
        'groundContactTimeMs': p.groundContactTimeMs,
    };
  }

  static Map<String, dynamic> _encodeSplit(ActivitySplit s) {
    return {
      'splitNumber': s.splitNumber,
      'label': s.label,
      'time': s.time,
      'distanceKm': s.distanceKm,
      'paceOrSpeed': s.paceOrSpeed,
      'avgHr': s.avgHr,
      'avgPower': s.avgPower,
      'elevationDeltaM': s.elevationDeltaM,
      'cadence': s.cadence,
      'gap': s.gap,
      'isFastest': s.isFastest,
    };
  }

  static Map<String, dynamic> _encodeRunningDynamics(RunningDynamics d) {
    return {
      'groundContactTimeMs': d.groundContactTimeMs,
      'leftBalancePercent': d.leftBalancePercent,
      'rightBalancePercent': d.rightBalancePercent,
      'verticalOscillationCm': d.verticalOscillationCm,
      'strideLengthM': d.strideLengthM,
      'runningPowerWatts': d.runningPowerWatts,
      'verticalRatioPercent': d.verticalRatioPercent,
    };
  }

  static Map<String, dynamic> _encodeStarredSegment(StarredSegment s) {
    return {
      'name': s.name,
      'distanceKm': s.distanceKm,
      'avgGradePercent': s.avgGradePercent,
      'time': s.time,
      'prDelta': s.prDelta,
      'avgWatts': s.avgWatts,
      'vam': s.vam,
      'isPr': s.isPr,
    };
  }

  static Map<String, dynamic> _encodeErgStep(ErgStep e) {
    return {
      'step': e.step,
      'name': e.name,
      'duration': e.duration,
      'targetWatts': e.targetWatts,
      'actualWatts': e.actualWatts,
      'deltaWatts': e.deltaWatts,
      'avgCadence': e.avgCadence,
      'avgHr': e.avgHr,
      'adherencePercent': e.adherencePercent,
    };
  }

  static Map<String, dynamic> _encodeSwimIntervalSet(SwimIntervalSet s) {
    return {
      'phase': s.phase,
      'distanceM': s.distanceM,
      'repsDescription': s.repsDescription,
      'avgPacePer100m': s.avgPacePer100m,
      'swolf': s.swolf,
      'cadenceSpm': s.cadenceSpm,
      'restInterval': s.restInterval,
    };
  }

  static Map<String, dynamic> _encodeDevice(ConnectedDevice d) {
    return {
      'id': d.id,
      'name': d.name,
      'category': d.category,
      'protocol': d.protocol,
      'state': d.state.name,
      'batteryPercent': d.batteryPercent,
      'lastSyncTime': d.lastSyncTime,
      'firmwareVersion': d.firmwareVersion,
      'telemetryChannels': d.telemetryChannels,
    };
  }

  static Map<String, dynamic> _encodeProfile(AthletePhysiologicalProfile p) {
    return {
      'acwrRatio': p.acwrRatio,
      'acwrStatus': p.acwrStatus,
      'ctlFitness': p.ctlFitness,
      'atlFatigue': p.atlFatigue,
      'tsbForm': p.tsbForm,
      'restingHr': p.restingHr,
      'hrvMs': p.hrvMs,
      'ftpWatts': p.ftpWatts,
      'weightKg': p.weightKg,
      'vo2MaxEst': p.vo2MaxEst,
      'enduranceScore': p.enduranceScore,
      'hillScore': p.hillScore,
      'dailySteps': p.dailySteps,
      'activeCalories': p.activeCalories,
    };
  }

  // ---------------------------------------------------------------------------
  // Deserialization
  // ---------------------------------------------------------------------------

  static CachedTelemetrySnapshot _decodeSnapshot(Map<String, dynamic> json) {
    final rawActivities = json['activities'];
    if (rawActivities != null && rawActivities is! List) {
      throw const FormatException('Invalid activities field');
    }
    final activities = (rawActivities as List? ?? const [])
        .map((item) => _decodeActivity(_requireMap(item, 'activity')))
        .toList();

    final rawDevices = json['connectedDevices'];
    if (rawDevices != null && rawDevices is! List) {
      throw const FormatException('Invalid connectedDevices field');
    }
    final connectedDevices = (rawDevices as List? ?? const [])
        .map((item) => _decodeDevice(_requireMap(item, 'connectedDevice')))
        .toList();

    final rawProfile = json['profile'];
    if (rawProfile != null && rawProfile is! Map<String, dynamic>) {
      throw const FormatException('Invalid profile field');
    }
    final profile = rawProfile is Map<String, dynamic>
        ? _decodeProfile(rawProfile)
        : const AthletePhysiologicalProfile();

    final rawStravaActivities = json['stravaActivities'];
    if (rawStravaActivities != null && rawStravaActivities is! List) {
      throw const FormatException('Invalid stravaActivities field');
    }
    final stravaActivities = (rawStravaActivities as List? ?? const [])
        .map(
          (item) => StravaActivityEnrichment.fromJson(
            _requireMap(item, 'stravaActivity'),
          ),
        )
        .toList();

    final rawStravaEnrichments = json['stravaEnrichments'];
    if (rawStravaEnrichments != null &&
        rawStravaEnrichments is! Map<String, dynamic>) {
      throw const FormatException('Invalid stravaEnrichments field');
    }
    final stravaEnrichments = <String, StravaActivityEnrichment>{};
    if (rawStravaEnrichments is Map<String, dynamic>) {
      for (final entry in rawStravaEnrichments.entries) {
        stravaEnrichments[entry.key] = StravaActivityEnrichment.fromJson(
          _requireMap(entry.value, 'stravaEnrichment'),
        );
      }
    }

    final rawLastSyncedAt = json['lastSyncedAt'];
    DateTime? lastSyncedAt;
    if (rawLastSyncedAt is String && rawLastSyncedAt.isNotEmpty) {
      lastSyncedAt = DateTime.tryParse(rawLastSyncedAt);
    } else if (rawLastSyncedAt != null) {
      throw const FormatException('Invalid lastSyncedAt field');
    }

    return CachedTelemetrySnapshot(
      activities: activities,
      connectedDevices: connectedDevices,
      profile: profile,
      stravaActivities: stravaActivities,
      stravaEnrichments: stravaEnrichments,
      lastSyncedAt: lastSyncedAt,
    );
  }

  static Map<String, dynamic> _requireMap(Object? value, String label) {
    if (value is Map<String, dynamic>) return value;
    throw FormatException('Expected object for $label');
  }

  static SportDiscipline _decodeDiscipline(Object? value) {
    final name = value as String?;
    if (name == null) return SportDiscipline.run;
    for (final d in SportDiscipline.values) {
      if (d.name == name) return d;
    }
    return SportDiscipline.run;
  }

  static DeviceConnectionState _decodeDeviceState(Object? value) {
    final name = value as String?;
    if (name == null) return DeviceConnectionState.offline;
    for (final s in DeviceConnectionState.values) {
      if (s.name == name) return s;
    }
    return DeviceConnectionState.offline;
  }

  static Activity _decodeActivity(Map<String, dynamic> json) {
    final rawDynamics = json['runningDynamics'];
    final RunningDynamics? runningDynamics = rawDynamics is Map<String, dynamic>
        ? _decodeRunningDynamics(rawDynamics)
        : null;

    final routePoints = (json['routePoints'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_decodeGpsPoint)
        .toList();

    final splits = (json['splits'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_decodeSplit)
        .toList();

    final segments = (json['segments'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_decodeStarredSegment)
        .toList();

    final ergSteps = (json['ergSteps'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_decodeErgStep)
        .toList();

    final swimSets = (json['swimSets'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_decodeSwimIntervalSet)
        .toList();

    return Activity(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
      discipline: _decodeDiscipline(json['discipline']),
      timestamp: DateTime.parse(json['timestamp'] as String),
      formattedDate: (json['formattedDate'] as String?) ?? '',
      location: (json['location'] as String?) ?? '',
      deviceHardware: (json['deviceHardware'] as String?) ?? '',
      sensorChain: (json['sensorChain'] as String?) ?? '',
      distanceKm: (json['distanceKm'] as num?)?.toDouble() ?? 0.0,
      durationSeconds: (json['durationSeconds'] as num?)?.toDouble() ?? 0.0,
      movingTime: (json['movingTime'] as String?) ?? '',
      elapsedTime: (json['elapsedTime'] as String?) ?? '',
      avgSpeedOrPace: (json['avgSpeedOrPace'] as String?) ?? '',
      maxSpeedOrPace: (json['maxSpeedOrPace'] as String?) ?? '',
      avgHr: (json['avgHr'] as num?)?.toInt() ?? 0,
      maxHr: (json['maxHr'] as num?)?.toInt() ?? 0,
      elevationGainM: (json['elevationGainM'] as num?)?.toDouble() ?? 0.0,
      elevationLossM: (json['elevationLossM'] as num?)?.toDouble() ?? 0.0,
      avgPowerW: (json['avgPowerW'] as num?)?.toInt(),
      normPowerW: (json['normPowerW'] as num?)?.toInt(),
      maxPowerW: (json['maxPowerW'] as num?)?.toInt(),
      variabilityIndex: (json['variabilityIndex'] as num?)?.toDouble(),
      intensityFactor: (json['intensityFactor'] as num?)?.toDouble(),
      tss: (json['tss'] as num?)?.toDouble(),
      calories: (json['calories'] as num?)?.toInt() ?? 0,
      avgCadence: (json['avgCadence'] as num?)?.toInt(),
      maxCadence: (json['maxCadence'] as num?)?.toInt(),
      startLatitude: (json['startLatitude'] as num?)?.toDouble(),
      startLongitude: (json['startLongitude'] as num?)?.toDouble(),
      routePoints: routePoints,
      runningDynamics: runningDynamics,
      splits: splits,
      segments: segments,
      ergSteps: ergSteps,
      swimSets: swimSets,
      ergAdherence: (json['ergAdherence'] as num?)?.toDouble(),
      swolf: (json['swolf'] as num?)?.toInt(),
      gearName: json['gearName'] as String?,
      gearUsageKm: (json['gearUsageKm'] as num?)?.toDouble(),
    );
  }

  static GpsPoint _decodeGpsPoint(Map<String, dynamic> json) {
    return GpsPoint(
      (json['lat'] as num).toDouble(),
      (json['lon'] as num).toDouble(),
      speedMps: (json['speedMps'] as num?)?.toDouble(),
      timeSec: (json['timeSec'] as num?)?.toDouble(),
      distanceM: (json['distanceM'] as num?)?.toDouble(),
      elevationM: (json['elevationM'] as num?)?.toDouble(),
      heartRate: (json['heartRate'] as num?)?.toInt(),
      cadence: (json['cadence'] as num?)?.toInt(),
      powerW: (json['powerW'] as num?)?.toInt(),
      verticalOscillationCm:
          (json['verticalOscillationCm'] as num?)?.toDouble(),
      groundContactTimeMs: (json['groundContactTimeMs'] as num?)?.toInt(),
    );
  }

  static ActivitySplit _decodeSplit(Map<String, dynamic> json) {
    return ActivitySplit(
      splitNumber: (json['splitNumber'] as num?)?.toInt() ?? 0,
      label: (json['label'] as String?) ?? '',
      time: (json['time'] as String?) ?? '',
      distanceKm: (json['distanceKm'] as num?)?.toDouble() ?? 0.0,
      paceOrSpeed: (json['paceOrSpeed'] as String?) ?? '',
      avgHr: (json['avgHr'] as num?)?.toInt() ?? 0,
      avgPower: (json['avgPower'] as num?)?.toInt(),
      elevationDeltaM: (json['elevationDeltaM'] as num?)?.toDouble(),
      cadence: (json['cadence'] as num?)?.toInt(),
      gap: json['gap'] as String?,
      isFastest: (json['isFastest'] as bool?) ?? false,
    );
  }

  static RunningDynamics _decodeRunningDynamics(Map<String, dynamic> json) {
    return RunningDynamics(
      groundContactTimeMs: (json['groundContactTimeMs'] as num?)?.toInt() ?? 0,
      leftBalancePercent:
          (json['leftBalancePercent'] as num?)?.toDouble() ?? 0.0,
      rightBalancePercent:
          (json['rightBalancePercent'] as num?)?.toDouble() ?? 0.0,
      verticalOscillationCm:
          (json['verticalOscillationCm'] as num?)?.toDouble() ?? 0.0,
      strideLengthM: (json['strideLengthM'] as num?)?.toDouble() ?? 0.0,
      runningPowerWatts: (json['runningPowerWatts'] as num?)?.toInt() ?? 0,
      verticalRatioPercent:
          (json['verticalRatioPercent'] as num?)?.toDouble() ?? 0.0,
    );
  }

  static StarredSegment _decodeStarredSegment(Map<String, dynamic> json) {
    return StarredSegment(
      name: (json['name'] as String?) ?? '',
      distanceKm: (json['distanceKm'] as num?)?.toDouble() ?? 0.0,
      avgGradePercent: (json['avgGradePercent'] as num?)?.toDouble() ?? 0.0,
      time: (json['time'] as String?) ?? '',
      prDelta: (json['prDelta'] as String?) ?? '',
      avgWatts: (json['avgWatts'] as num?)?.toInt() ?? 0,
      vam: (json['vam'] as num?)?.toInt() ?? 0,
      isPr: (json['isPr'] as bool?) ?? false,
    );
  }

  static ErgStep _decodeErgStep(Map<String, dynamic> json) {
    return ErgStep(
      step: (json['step'] as num?)?.toInt() ?? 0,
      name: (json['name'] as String?) ?? '',
      duration: (json['duration'] as String?) ?? '',
      targetWatts: (json['targetWatts'] as num?)?.toInt() ?? 0,
      actualWatts: (json['actualWatts'] as num?)?.toInt() ?? 0,
      deltaWatts: (json['deltaWatts'] as num?)?.toInt() ?? 0,
      avgCadence: (json['avgCadence'] as num?)?.toInt() ?? 0,
      avgHr: (json['avgHr'] as num?)?.toInt() ?? 0,
      adherencePercent: (json['adherencePercent'] as num?)?.toDouble() ?? 0.0,
    );
  }

  static SwimIntervalSet _decodeSwimIntervalSet(Map<String, dynamic> json) {
    return SwimIntervalSet(
      phase: (json['phase'] as String?) ?? '',
      distanceM: (json['distanceM'] as num?)?.toInt() ?? 0,
      repsDescription: (json['repsDescription'] as String?) ?? '',
      avgPacePer100m: (json['avgPacePer100m'] as String?) ?? '',
      swolf: (json['swolf'] as num?)?.toInt() ?? 0,
      cadenceSpm: (json['cadenceSpm'] as num?)?.toInt() ?? 0,
      restInterval: (json['restInterval'] as String?) ?? '',
    );
  }

  static ConnectedDevice _decodeDevice(Map<String, dynamic> json) {
    return ConnectedDevice(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] as String?) ?? '',
      category: (json['category'] as String?) ?? '',
      protocol: (json['protocol'] as String?) ?? '',
      state: _decodeDeviceState(json['state']),
      batteryPercent: (json['batteryPercent'] as num?)?.toInt() ?? 0,
      lastSyncTime: (json['lastSyncTime'] as String?) ?? '',
      firmwareVersion: (json['firmwareVersion'] as String?) ?? '',
      telemetryChannels: (json['telemetryChannels'] as String?) ?? '',
    );
  }

  static AthletePhysiologicalProfile _decodeProfile(Map<String, dynamic> json) {
    return AthletePhysiologicalProfile(
      acwrRatio: (json['acwrRatio'] as num?)?.toDouble(),
      acwrStatus: json['acwrStatus'] as String?,
      ctlFitness: (json['ctlFitness'] as num?)?.toDouble(),
      atlFatigue: (json['atlFatigue'] as num?)?.toDouble(),
      tsbForm: (json['tsbForm'] as num?)?.toDouble(),
      restingHr: (json['restingHr'] as num?)?.toInt(),
      hrvMs: (json['hrvMs'] as num?)?.toInt(),
      ftpWatts: (json['ftpWatts'] as num?)?.toInt(),
      weightKg: (json['weightKg'] as num?)?.toDouble(),
      vo2MaxEst: (json['vo2MaxEst'] as num?)?.toDouble(),
      enduranceScore: (json['enduranceScore'] as num?)?.toInt(),
      hillScore: (json['hillScore'] as num?)?.toInt(),
      dailySteps: (json['dailySteps'] as num?)?.toInt(),
      activeCalories: (json['activeCalories'] as num?)?.toInt(),
    );
  }
}
