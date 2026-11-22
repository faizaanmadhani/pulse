import 'package:flutter/material.dart';

import '../models/activity.dart';
import 'unit_formatter.dart';

/// Represents one physiological intensity zone (Z1–Z5) and the accumulated
/// time spent in it.
class ZoneBucket {
  final int zone; // 1..5
  final String label;
  final String rangeText;
  final double seconds;
  final double percentage; // 0..100
  final Color color;

  const ZoneBucket({
    required this.zone,
    required this.label,
    required this.rangeText,
    required this.seconds,
    required this.percentage,
    required this.color,
  });
}

/// Aerobic decoupling / cardiac drift analysis comparing the 1st half and
/// 2nd half of an endurance session (after skipping the initial warmup).
class CardiacDriftResult {
  final double decouplingPercent;
  final double firstHalfEf;
  final double secondHalfEf;
  final double firstHalfAvgHr;
  final double secondHalfAvgHr;
  final String firstHalfOutput;
  final String secondHalfOutput;
  final String metricLabel; // e.g. 'Pa:Hr', 'Pw:Hr', 'Spd:Hr'
  final String statusLabel; // 'Excellent (<5%)' | 'Moderate (5–10%)' | 'High Drift (>10%)'
  final bool isLongSession;

  const CardiacDriftResult({
    required this.decouplingPercent,
    required this.firstHalfEf,
    required this.secondHalfEf,
    required this.firstHalfAvgHr,
    required this.secondHalfAvgHr,
    required this.firstHalfOutput,
    required this.secondHalfOutput,
    required this.metricLabel,
    required this.statusLabel,
    required this.isLongSession,
  });
}

/// Standard Apple Health / Fitness inspired colors for Zones 1–5.
const List<Color> _zoneColors = [
  Color(0xFF8E8E93), // Z1: Recovery (Cool Gray)
  Color(0xFF007AFF), // Z2: Aerobic / Endurance (Blue)
  Color(0xFF34C759), // Z3: Tempo (Green)
  Color(0xFFFF9500), // Z4: Threshold (Orange)
  Color(0xFFFF3B30), // Z5: VO2 Max (Red)
];

const List<String> _hrZoneLabels = [
  'Recovery',
  'Aerobic',
  'Tempo',
  'Threshold',
  'VO2 Max',
];

const List<String> _powerZoneLabels = [
  'Active Recovery',
  'Endurance',
  'Tempo',
  'Threshold',
  'VO2 Max+',
];

/// Formats a zone duration in seconds into a compact human-readable string
/// such as `'0s'`, `'45s'`, `'12m 30s'`, or `'1h 05m'`.
String formatZoneDuration(double seconds) {
  if (!seconds.isFinite || seconds <= 0) return '0s';
  final totalSeconds = seconds.round();
  if (totalSeconds < 60) {
    return '${totalSeconds}s';
  }
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final secs = totalSeconds % 60;
  if (hours > 0) {
    return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
  }
  if (secs == 0) {
    return '${minutes}m 00s';
  }
  return '${minutes}m ${secs.toString().padLeft(2, '0')}s';
}

/// Computes Z1–Z5 heart rate time-in-zone distribution for a single [activity].
///
/// Priority order for data sources:
/// 1. `activity.routePoints` (`heartRate` + `timeSec` deltas, or equal-weight if
///    `timeSec` is absent)
/// 2. `activity.splits` (`avgHr` + parsed `time`)
/// 3. `activity.avgHr` + effective duration fallback
///
/// Uses standard 5-zone %MaxHR bands:
/// - Z1: <60%
/// - Z2: 60–70%
/// - Z3: 70–80%
/// - Z4: 80–90%
/// - Z5: 90%+
///
/// Max HR is resolved via `maxHrOverride ?? (activity.maxHr > 140 ? activity.maxHr : 190)`.
/// Returns an empty list if the activity has no heart rate data.
List<ZoneBucket> computeActivityHrZones(
  Activity activity, {
  int? maxHrOverride,
}) {
  final int maxHr = (maxHrOverride != null && maxHrOverride > 0)
      ? maxHrOverride
      : (activity.maxHr > 140 ? activity.maxHr : 190);

  final zoneSeconds = List<double>.filled(5, 0.0);
  double totalSeconds = 0.0;

  // 1. Route points stream
  final hrPoints = activity.routePoints
      .where((p) => p.heartRate != null && p.heartRate! > 0)
      .toList();

  if (hrPoints.isNotEmpty) {
    final bool hasTimeStream =
        hrPoints.length >= 2 && hrPoints.every((p) => p.timeSec != null);

    if (hasTimeStream) {
      final firstTime = hrPoints.first.timeSec!;
      if (firstTime.isFinite && firstTime > 0) {
        final z = _hrZoneIndex(hrPoints.first.heartRate!, maxHr);
        zoneSeconds[z] += firstTime;
        totalSeconds += firstTime;
      }
      for (int i = 1; i < hrPoints.length; i++) {
        final dt = hrPoints[i].timeSec! - hrPoints[i - 1].timeSec!;
        if (dt.isFinite && dt > 0) {
          final z = _hrZoneIndex(hrPoints[i].heartRate!, maxHr);
          zoneSeconds[z] += dt;
          totalSeconds += dt;
        }
      }
    }

    // Fallback to equal-weight per point if timeSec was missing or zero-delta
    if (totalSeconds <= 0) {
      final duration = _effectiveDurationSeconds(activity);
      if (duration > 0) {
        final weight = duration / hrPoints.length;
        for (final p in hrPoints) {
          final z = _hrZoneIndex(p.heartRate!, maxHr);
          zoneSeconds[z] += weight;
          totalSeconds += weight;
        }
      }
    }
  }

  // 2. Fallback to splits
  if (totalSeconds <= 0 && activity.splits.isNotEmpty) {
    for (final split in activity.splits) {
      if (split.avgHr <= 0) continue;
      final splitSec = _parseDurationString(split.time);
      if (splitSec > 0) {
        final z = _hrZoneIndex(split.avgHr, maxHr);
        zoneSeconds[z] += splitSec;
        totalSeconds += splitSec;
      }
    }
  }

  // 3. Fallback to activity avgHr + duration
  if (totalSeconds <= 0 && activity.avgHr > 0) {
    final duration = _effectiveDurationSeconds(activity);
    if (duration > 0) {
      final z = _hrZoneIndex(activity.avgHr, maxHr);
      zoneSeconds[z] += duration;
      totalSeconds += duration;
    }
  }

  if (totalSeconds <= 0) {
    return const [];
  }

  return _buildHrZoneBuckets(zoneSeconds, totalSeconds, maxHr);
}

/// Computes Z1–Z5 Coggan power time-in-zone distribution for a single [activity].
///
/// Coggan %FTP bands:
/// - Z1: <55% FTP
/// - Z2: 56–75% FTP
/// - Z3: 76–90% FTP
/// - Z4: 91–105% FTP
/// - Z5: >105% FTP
///
/// Reads `routePoints` (`powerW`), falling back to `splits` (`avgPower`) or
/// `activity.avgPowerW` + duration. Returns an empty list if the activity has
/// no power data.
List<ZoneBucket> computeActivityPowerZones(
  Activity activity, {
  int ftpWatts = 250,
}) {
  final int effectiveFtp = ftpWatts > 0 ? ftpWatts : 250;
  final zoneSeconds = List<double>.filled(5, 0.0);
  double totalSeconds = 0.0;

  // 1. Route points stream
  final powerPoints = activity.routePoints
      .where((p) => p.powerW != null && p.powerW! > 0)
      .toList();

  if (powerPoints.isNotEmpty) {
    final bool hasTimeStream =
        powerPoints.length >= 2 && powerPoints.every((p) => p.timeSec != null);

    if (hasTimeStream) {
      final firstTime = powerPoints.first.timeSec!;
      if (firstTime.isFinite && firstTime > 0) {
        final z = _powerZoneIndex(powerPoints.first.powerW!, effectiveFtp);
        zoneSeconds[z] += firstTime;
        totalSeconds += firstTime;
      }
      for (int i = 1; i < powerPoints.length; i++) {
        final dt = powerPoints[i].timeSec! - powerPoints[i - 1].timeSec!;
        if (dt.isFinite && dt > 0) {
          final z = _powerZoneIndex(powerPoints[i].powerW!, effectiveFtp);
          zoneSeconds[z] += dt;
          totalSeconds += dt;
        }
      }
    }

    if (totalSeconds <= 0) {
      final duration = _effectiveDurationSeconds(activity);
      if (duration > 0) {
        final weight = duration / powerPoints.length;
        for (final p in powerPoints) {
          final z = _powerZoneIndex(p.powerW!, effectiveFtp);
          zoneSeconds[z] += weight;
          totalSeconds += weight;
        }
      }
    }
  }

  // 2. Fallback to splits
  if (totalSeconds <= 0 && activity.splits.isNotEmpty) {
    for (final split in activity.splits) {
      if (split.avgPower == null || split.avgPower! <= 0) continue;
      final splitSec = _parseDurationString(split.time);
      if (splitSec > 0) {
        final z = _powerZoneIndex(split.avgPower!, effectiveFtp);
        zoneSeconds[z] += splitSec;
        totalSeconds += splitSec;
      }
    }
  }

  // 3. Fallback to activity avgPowerW + duration
  if (totalSeconds <= 0 &&
      activity.avgPowerW != null &&
      activity.avgPowerW! > 0) {
    final duration = _effectiveDurationSeconds(activity);
    if (duration > 0) {
      final z = _powerZoneIndex(activity.avgPowerW!, effectiveFtp);
      zoneSeconds[z] += duration;
      totalSeconds += duration;
    }
  }

  if (totalSeconds <= 0) {
    return const [];
  }

  return _buildPowerZoneBuckets(zoneSeconds, totalSeconds, effectiveFtp);
}

/// Aggregates Z1–Z5 heart rate time across all [activities] occurring within
/// the last [days] days (relative to [now], which defaults to `DateTime.now()`).
List<ZoneBucket> computeWeeklyHrZones(
  List<Activity> activities, {
  int days = 7,
  int? maxHr,
  DateTime? now,
}) {
  if (activities.isEmpty || days <= 0) return const [];

  final referenceNow = now ?? DateTime.now();
  final cutoff = referenceNow.subtract(Duration(days: days));

  final inWindow = activities
      .where((a) => !a.timestamp.isBefore(cutoff))
      .toList();

  if (inWindow.isEmpty) return const [];

  int resolvedMaxHr = maxHr ?? 0;
  if (resolvedMaxHr <= 0) {
    int peak = 0;
    for (final a in inWindow) {
      if (a.maxHr > peak) peak = a.maxHr;
    }
    resolvedMaxHr = peak > 140 ? peak : 190;
  }

  final totals = List<double>.filled(5, 0.0);
  double grandTotal = 0.0;

  for (final activity in inWindow) {
    final buckets = computeActivityHrZones(
      activity,
      maxHrOverride: resolvedMaxHr,
    );
    for (final b in buckets) {
      final idx = b.zone - 1;
      if (idx >= 0 && idx < 5) {
        totals[idx] += b.seconds;
        grandTotal += b.seconds;
      }
    }
  }

  if (grandTotal <= 0) return const [];

  return _buildHrZoneBuckets(totals, grandTotal, resolvedMaxHr);
}

/// Computes Cardiac Drift / Aerobic Decoupling (`Pa:Hr`, `Pw:Hr`, or `Spd:Hr`)
/// for runs and rides of at least 60 minutes (`durationSeconds >= 3600`).
///
/// - Skips the initial ~10% warmup portion of the effort.
/// - Splits the remaining effort into 1st Half vs 2nd Half.
/// - Calculates Efficiency Factor (`EF = output / avgHr`) for each half.
/// - Computes `decouplingPercent = ((ef1 - ef2) / ef1) * 100`.
///
/// Returns `null` if the activity is not a run/ride, is shorter than 60 min,
/// or lacks sufficient HR and output (pace/speed/power) telemetry.
CardiacDriftResult? computeCardiacDrift(
  Activity activity, {
  UnitSystem unit = UnitSystem.metric,
}) {
  final isRun = activity.discipline == SportDiscipline.run;
  final isBike = activity.discipline == SportDiscipline.bike ||
      activity.discipline == SportDiscipline.indoorBike;
  if (!isRun && !isBike) return null;

  final duration = _effectiveDurationSeconds(activity);
  if (duration < 3600) return null;

  // Path 1: Route points (>= 10 valid points with HR & output)
  if (activity.routePoints.isNotEmpty) {
    if (isBike) {
      // Prefer Power (Pw:Hr) on rides
      final powerSamples = activity.routePoints
          .where((p) =>
              p.heartRate != null &&
              p.heartRate! > 0 &&
              p.powerW != null &&
              p.powerW! > 0)
          .toList();
      if (powerSamples.length >= 10) {
        return _computeDriftFromSamples(
          hrValues: powerSamples.map((p) => p.heartRate!.toDouble()).toList(),
          outputValues: powerSamples.map((p) => p.powerW!.toDouble()).toList(),
          efScale: 1.0, // Watts / bpm
          metricLabel: 'Pw:Hr',
          formatOutput: (val) => '${val.round()} W',
        );
      }

      // Fallback to Speed (Spd:Hr) on rides without power meter
      final speedSamples = activity.routePoints
          .where((p) =>
              p.heartRate != null &&
              p.heartRate! > 0 &&
              p.speedMps != null &&
              p.speedMps! > 0)
          .toList();
      if (speedSamples.length >= 10) {
        return _computeDriftFromSamples(
          hrValues: speedSamples.map((p) => p.heartRate!.toDouble()).toList(),
          outputValues: speedSamples.map((p) => p.speedMps!).toList(),
          efScale: 60.0, // (m/min) / bpm
          metricLabel: 'Spd:Hr',
          formatOutput: (val) =>
              UnitFormatter.formatPaceOrSpeed(activity.discipline, val, unit),
        );
      }
    } else {
      // Run: prefer Pace/Speed (Pa:Hr)
      final speedSamples = activity.routePoints
          .where((p) =>
              p.heartRate != null &&
              p.heartRate! > 0 &&
              p.speedMps != null &&
              p.speedMps! > 0)
          .toList();
      if (speedSamples.length >= 10) {
        return _computeDriftFromSamples(
          hrValues: speedSamples.map((p) => p.heartRate!.toDouble()).toList(),
          outputValues: speedSamples.map((p) => p.speedMps!).toList(),
          efScale: 60.0, // (m/min) / bpm
          metricLabel: 'Pa:Hr',
          formatOutput: (val) =>
              UnitFormatter.formatPaceOrSpeed(SportDiscipline.run, val, unit),
        );
      }

      // Fallback to Running Power (Pw:Hr) if speed stream absent
      final powerSamples = activity.routePoints
          .where((p) =>
              p.heartRate != null &&
              p.heartRate! > 0 &&
              p.powerW != null &&
              p.powerW! > 0)
          .toList();
      if (powerSamples.length >= 10) {
        return _computeDriftFromSamples(
          hrValues: powerSamples.map((p) => p.heartRate!.toDouble()).toList(),
          outputValues: powerSamples.map((p) => p.powerW!.toDouble()).toList(),
          efScale: 1.0,
          metricLabel: 'Pw:Hr',
          formatOutput: (val) => '${val.round()} W',
        );
      }
    }
  }

  // Path 2: Splits fallback (>= 4 valid splits with HR & output)
  if (activity.splits.length >= 4) {
    if (isBike) {
      final powerSplits = activity.splits
          .where((s) => s.avgHr > 0 && s.avgPower != null && s.avgPower! > 0)
          .toList();
      if (powerSplits.length >= 4) {
        return _computeDriftFromSamples(
          hrValues: powerSplits.map((s) => s.avgHr.toDouble()).toList(),
          outputValues: powerSplits.map((s) => s.avgPower!.toDouble()).toList(),
          efScale: 1.0,
          metricLabel: 'Pw:Hr',
          formatOutput: (val) => '${val.round()} W',
        );
      }
    }

    final speedSplits = <_SplitSpeedSample>[];
    for (final s in activity.splits) {
      if (s.avgHr <= 0) continue;
      final speedMps = _splitSpeedMps(s);
      if (speedMps != null && speedMps > 0) {
        speedSplits.add(_SplitSpeedSample(s.avgHr.toDouble(), speedMps));
      }
    }

    if (speedSplits.length >= 4) {
      return _computeDriftFromSamples(
        hrValues: speedSplits.map((s) => s.hr).toList(),
        outputValues: speedSplits.map((s) => s.speedMps).toList(),
        efScale: 60.0,
        metricLabel: isRun ? 'Pa:Hr' : 'Spd:Hr',
        formatOutput: (val) =>
            UnitFormatter.formatPaceOrSpeed(activity.discipline, val, unit),
      );
    }
  }

  return null;
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

class _SplitSpeedSample {
  final double hr;
  final double speedMps;
  const _SplitSpeedSample(this.hr, this.speedMps);
}

CardiacDriftResult? _computeDriftFromSamples({
  required List<double> hrValues,
  required List<double> outputValues,
  required double efScale,
  required String metricLabel,
  required String Function(double avgOutput) formatOutput,
}) {
  final n = hrValues.length;
  if (n < 4 || outputValues.length != n) return null;

  // Skip initial ~10% warmup
  final warmupCount = (n * 0.10).floor();
  final effortHr = hrValues.sublist(warmupCount);
  final effortOut = outputValues.sublist(warmupCount);
  if (effortHr.length < 2) return null;

  final mid = effortHr.length ~/ 2;
  final hr1 = _mean(effortHr.sublist(0, mid));
  final hr2 = _mean(effortHr.sublist(mid));
  final out1 = _mean(effortOut.sublist(0, mid));
  final out2 = _mean(effortOut.sublist(mid));

  if (hr1 <= 0 || hr2 <= 0 || out1 <= 0 || out2 <= 0) return null;

  final ef1 = (out1 * efScale) / hr1;
  final ef2 = (out2 * efScale) / hr2;
  if (!ef1.isFinite || !ef2.isFinite || ef1 <= 0) return null;

  final decoupling = ((ef1 - ef2) / ef1) * 100.0;
  final status = _driftStatusLabel(decoupling);

  return CardiacDriftResult(
    decouplingPercent: decoupling,
    firstHalfEf: ef1,
    secondHalfEf: ef2,
    firstHalfAvgHr: hr1,
    secondHalfAvgHr: hr2,
    firstHalfOutput: formatOutput(out1),
    secondHalfOutput: formatOutput(out2),
    metricLabel: metricLabel,
    statusLabel: status,
    isLongSession: true,
  );
}

String _driftStatusLabel(double decouplingPercent) {
  if (decouplingPercent < 5.0 - 1e-9) {
    return 'Excellent (<5%)';
  }
  if (decouplingPercent <= 10.0 + 1e-9) {
    return 'Moderate (5–10%)';
  }
  return 'High Drift (>10%)';
}

double _mean(List<double> values) {
  if (values.isEmpty) return 0.0;
  double sum = 0.0;
  for (final v in values) {
    sum += v;
  }
  return sum / values.length;
}

int _hrZoneIndex(int hr, int maxHr) {
  final pct = hr / maxHr;
  if (pct < 0.60) return 0; // Z1
  if (pct < 0.70) return 1; // Z2
  if (pct < 0.80) return 2; // Z3
  if (pct < 0.90) return 3; // Z4
  return 4; // Z5
}

int _powerZoneIndex(int watts, int ftpWatts) {
  final pct = watts / ftpWatts;
  if (pct < 0.55) return 0; // Z1 (<55%)
  if (pct <= 0.75) return 1; // Z2 (56–75%)
  if (pct <= 0.90) return 2; // Z3 (76–90%)
  if (pct <= 1.05) return 3; // Z4 (91–105%)
  return 4; // Z5 (>105%)
}

List<ZoneBucket> _buildHrZoneBuckets(
  List<double> zoneSeconds,
  double totalSeconds,
  int maxHr,
) {
  final z1Max = (maxHr * 0.60).round() - 1;
  final z2Min = z1Max + 1;
  final z2Max = (maxHr * 0.70).round() - 1;
  final z3Min = z2Max + 1;
  final z3Max = (maxHr * 0.80).round() - 1;
  final z4Min = z3Max + 1;
  final z4Max = (maxHr * 0.90).round() - 1;
  final z5Min = z4Max + 1;

  final ranges = [
    '< $z2Min bpm',
    '$z2Min–$z2Max bpm',
    '$z3Min–$z3Max bpm',
    '$z4Min–$z4Max bpm',
    '$z5Min+ bpm',
  ];

  return List<ZoneBucket>.generate(5, (i) {
    final sec = zoneSeconds[i];
    final pct = totalSeconds > 0 ? (sec / totalSeconds) * 100.0 : 0.0;
    return ZoneBucket(
      zone: i + 1,
      label: _hrZoneLabels[i],
      rangeText: ranges[i],
      seconds: sec,
      percentage: pct,
      color: _zoneColors[i],
    );
  });
}

List<ZoneBucket> _buildPowerZoneBuckets(
  List<double> zoneSeconds,
  double totalSeconds,
  int ftpWatts,
) {
  final z1Max = (ftpWatts * 0.55).round();
  final z2Max = (ftpWatts * 0.75).round();
  final z3Max = (ftpWatts * 0.90).round();
  final z4Max = (ftpWatts * 1.05).round();

  final ranges = [
    '< $z1Max W',
    '$z1Max–$z2Max W',
    '${z2Max + 1}–$z3Max W',
    '${z3Max + 1}–$z4Max W',
    '> $z4Max W',
  ];

  return List<ZoneBucket>.generate(5, (i) {
    final sec = zoneSeconds[i];
    final pct = totalSeconds > 0 ? (sec / totalSeconds) * 100.0 : 0.0;
    return ZoneBucket(
      zone: i + 1,
      label: _powerZoneLabels[i],
      rangeText: ranges[i],
      seconds: sec,
      percentage: pct,
      color: _zoneColors[i],
    );
  });
}

double _effectiveDurationSeconds(Activity activity) {
  if (activity.durationSeconds.isFinite && activity.durationSeconds > 0) {
    return activity.durationSeconds;
  }
  final parsedMoving = _parseDurationString(activity.movingTime);
  if (parsedMoving > 0) return parsedMoving;
  return _parseDurationString(activity.elapsedTime);
}

double? _splitSpeedMps(ActivitySplit split) {
  final sec = _parseDurationString(split.time);
  if (split.distanceKm > 0 && sec > 0) {
    return (split.distanceKm * 1000.0) / sec;
  }
  return null;
}

/// Parses common duration strings such as `'4:30'`, `'1:05:12'`, `'45m 30s'`,
/// `'1h 15m'`, or `'52s'` into seconds. Returns `0.0` if unparseable.
double _parseDurationString(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return 0.0;

  // Colon format: HH:MM:SS or MM:SS
  if (s.contains(':')) {
    final parts = s.split(':').map((p) => double.tryParse(p.trim())).toList();
    if (parts.every((p) => p != null)) {
      if (parts.length == 2) {
        return parts[0]! * 60.0 + parts[1]!;
      }
      if (parts.length == 3) {
        return parts[0]! * 3600.0 + parts[1]! * 60.0 + parts[2]!;
      }
    }
  }

  // Unit tokens format: e.g. '1h 12m 30s'
  double total = 0.0;
  bool matched = false;
  final regex = RegExp(r'(\d+(?:\.\d+)?)\s*(h|hr|hrs|m|min|mins|s|sec|secs)\b',
      caseSensitive: false);
  for (final m in regex.allMatches(s)) {
    final val = double.tryParse(m.group(1)!);
    final unit = m.group(2)!.toLowerCase();
    if (val == null) continue;
    matched = true;
    if (unit.startsWith('h')) {
      total += val * 3600.0;
    } else if (unit.startsWith('m')) {
      total += val * 60.0;
    } else {
      total += val;
    }
  }
  return matched ? total : 0.0;
}
