enum SportDiscipline {
  swim,
  bike,
  run,
  strength,
  indoorBike,
}

class GpsPoint {
  final double lat;
  final double lon;
  final double? speedMps;
  final double? timeSec;
  final double? distanceM;
  final double? elevationM;
  final int? heartRate;
  final int? cadence;
  final int? powerW;
  final double? verticalOscillationCm;
  final int? groundContactTimeMs;

  const GpsPoint(
    this.lat,
    this.lon, {
    this.speedMps,
    this.timeSec,
    this.distanceM,
    this.elevationM,
    this.heartRate,
    this.cadence,
    this.powerW,
    this.verticalOscillationCm,
    this.groundContactTimeMs,
  });
}

class ActivitySplit {
  final int splitNumber;
  final String label;
  final String time;
  final double distanceKm;
  final String paceOrSpeed;
  final int avgHr;
  final int? avgPower;
  final double? elevationDeltaM;
  final int? cadence;
  final String? gap; // Grade-Adjusted Pace
  final bool isFastest;

  const ActivitySplit({
    required this.splitNumber,
    required this.label,
    required this.time,
    required this.distanceKm,
    required this.paceOrSpeed,
    required this.avgHr,
    this.avgPower,
    this.elevationDeltaM,
    this.cadence,
    this.gap,
    this.isFastest = false,
  });
}

class StarredSegment {
  final String name;
  final double distanceKm;
  final double avgGradePercent;
  final String time;
  final String prDelta;
  final int avgWatts;
  final int vam; // Vertical Ascent Meters/hr
  final bool isPr;

  const StarredSegment({
    required this.name,
    required this.distanceKm,
    required this.avgGradePercent,
    required this.time,
    required this.prDelta,
    required this.avgWatts,
    required this.vam,
    this.isPr = false,
  });
}

class ErgStep {
  final int step;
  final String name;
  final String duration;
  final int targetWatts;
  final int actualWatts;
  final int deltaWatts;
  final int avgCadence;
  final int avgHr;
  final double adherencePercent;

  const ErgStep({
    required this.step,
    required this.name,
    required this.duration,
    required this.targetWatts,
    required this.actualWatts,
    required this.deltaWatts,
    required this.avgCadence,
    required this.avgHr,
    required this.adherencePercent,
  });
}

class SwimIntervalSet {
  final String phase;
  final int distanceM;
  final String repsDescription;
  final String avgPacePer100m;
  final int swolf;
  final int cadenceSpm;
  final String restInterval;

  const SwimIntervalSet({
    required this.phase,
    required this.distanceM,
    required this.repsDescription,
    required this.avgPacePer100m,
    required this.swolf,
    required this.cadenceSpm,
    required this.restInterval,
  });
}

class RunningDynamics {
  final int groundContactTimeMs; // e.g. 218 ms
  final double leftBalancePercent; // e.g. 49.6%
  final double rightBalancePercent; // e.g. 50.4%
  final double verticalOscillationCm; // e.g. 7.8 cm
  final double strideLengthM; // e.g. 1.24 m
  final int runningPowerWatts; // e.g. 342 W
  final double verticalRatioPercent; // e.g. 6.2%

  const RunningDynamics({
    required this.groundContactTimeMs,
    required this.leftBalancePercent,
    required this.rightBalancePercent,
    required this.verticalOscillationCm,
    required this.strideLengthM,
    required this.runningPowerWatts,
    required this.verticalRatioPercent,
  });
}

class Activity {
  final String id;
  final String title;
  final String description;
  final SportDiscipline discipline;
  final DateTime timestamp;
  final String formattedDate;
  final String location;
  final String deviceHardware;
  final String sensorChain;

  // Primary Telemetry
  final double distanceKm;
  final double durationSeconds;
  final String movingTime;
  final String elapsedTime;
  final String avgSpeedOrPace;
  final String maxSpeedOrPace;
  final int avgHr;
  final int maxHr;
  final double elevationGainM;
  final double elevationLossM;
  final int? avgPowerW;
  final int? normPowerW;
  final int? maxPowerW;
  final double? variabilityIndex;
  final double? intensityFactor;
  final double? tss;
  final int calories;
  final int? avgCadence;
  final int? maxCadence;
  final double? startLatitude;
  final double? startLongitude;
  final List<GpsPoint> routePoints;

  // Specific Sport Modules
  final RunningDynamics? runningDynamics;
  final List<ActivitySplit> splits;
  final List<StarredSegment> segments;
  final List<ErgStep> ergSteps;
  final List<SwimIntervalSet> swimSets;
  final double? ergAdherence;
  final int? swolf;
  final String? gearName;
  final double? gearUsageKm;

  const Activity({
    required this.id,
    required this.title,
    required this.description,
    required this.discipline,
    required this.timestamp,
    required this.formattedDate,
    required this.location,
    required this.deviceHardware,
    required this.sensorChain,
    required this.distanceKm,
    this.durationSeconds = 0,
    required this.movingTime,
    required this.elapsedTime,
    required this.avgSpeedOrPace,
    required this.maxSpeedOrPace,
    required this.avgHr,
    required this.maxHr,
    required this.elevationGainM,
    required this.elevationLossM,
    this.avgPowerW,
    this.normPowerW,
    this.maxPowerW,
    this.variabilityIndex,
    this.intensityFactor,
    this.tss,
    required this.calories,
    this.avgCadence,
    this.maxCadence,
    this.startLatitude,
    this.startLongitude,
    this.routePoints = const [],
    this.runningDynamics,
    this.splits = const [],
    this.segments = const [],
    this.ergSteps = const [],
    this.swimSets = const [],
    this.ergAdherence,
    this.swolf,
    this.gearName,
    this.gearUsageKm,
  });

  Activity copyWith({
    List<ActivitySplit>? splits,
    List<GpsPoint>? routePoints,
    String? deviceHardware,
  }) {
    return Activity(
      id: id,
      title: title,
      description: description,
      discipline: discipline,
      timestamp: timestamp,
      formattedDate: formattedDate,
      location: location,
      deviceHardware: deviceHardware ?? this.deviceHardware,
      sensorChain: sensorChain,
      distanceKm: distanceKm,
      durationSeconds: durationSeconds,
      movingTime: movingTime,
      elapsedTime: elapsedTime,
      avgSpeedOrPace: avgSpeedOrPace,
      maxSpeedOrPace: maxSpeedOrPace,
      avgHr: avgHr,
      maxHr: maxHr,
      elevationGainM: elevationGainM,
      elevationLossM: elevationLossM,
      avgPowerW: avgPowerW,
      normPowerW: normPowerW,
      maxPowerW: maxPowerW,
      variabilityIndex: variabilityIndex,
      intensityFactor: intensityFactor,
      tss: tss,
      calories: calories,
      avgCadence: avgCadence,
      maxCadence: maxCadence,
      startLatitude: startLatitude,
      startLongitude: startLongitude,
      routePoints: routePoints ?? this.routePoints,
      runningDynamics: runningDynamics,
      splits: splits ?? this.splits,
      segments: segments,
      ergSteps: ergSteps,
      swimSets: swimSets,
      ergAdherence: ergAdherence,
      swolf: swolf,
      gearName: gearName,
      gearUsageKm: gearUsageKm,
    );
  }
}
