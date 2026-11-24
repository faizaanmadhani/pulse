import 'dart:math' as math;

import '../models/activity.dart';
import '../models/performance_metrics.dart';
import '../models/training_plan.dart';
import 'unit_formatter.dart';

class SportVolumeSummary {
  final double avgWeeklyDistanceKm;
  final double avgWeeklyHours;
  final int sessionsCount;

  const SportVolumeSummary({
    required this.avgWeeklyDistanceKm,
    required this.avgWeeklyHours,
    required this.sessionsCount,
  });
}

class LongestSessionSummary {
  final double distanceKm;
  final double durationSeconds;
  final DateTime date;

  const LongestSessionSummary({
    required this.distanceKm,
    required this.durationSeconds,
    required this.date,
  });
}

class PlanAdherenceSummary {
  final int totalDue;
  final int completed;
  final int skipped;
  final int missedOrPending;
  final double avgAdherencePercent;
  final List<String> recentMissedSummaries;

  const PlanAdherenceSummary({
    required this.totalDue,
    required this.completed,
    required this.skipped,
    required this.missedOrPending,
    required this.avgAdherencePercent,
    this.recentMissedSummaries = const [],
  });
}

class AthleteContext {
  final DateTime asOfDate;
  final AthleteZonesSnapshot zones;
  final double? ctl;
  final double? atl;
  final double? tsb;
  final double? acwr;
  final String? acwrStatus;
  final int? restingHr;
  final int? hrvMs;
  final double? vo2MaxEst;
  final double avgWeeklyHours4w;
  final double avgWeeklyHours12w;
  final Map<SportDiscipline, SportVolumeSummary> volume4w;
  final Map<SportDiscipline, SportVolumeSummary> volume12w;
  final LongestSessionSummary? longestRecentRun;
  final LongestSessionSummary? longestRecentBike;
  final LongestSessionSummary? longestRecentSwim;
  final PlanAdherenceSummary? adherenceSummary;

  const AthleteContext({
    required this.asOfDate,
    required this.zones,
    this.ctl,
    this.atl,
    this.tsb,
    this.acwr,
    this.acwrStatus,
    this.restingHr,
    this.hrvMs,
    this.vo2MaxEst,
    required this.avgWeeklyHours4w,
    required this.avgWeeklyHours12w,
    this.volume4w = const {},
    this.volume12w = const {},
    this.longestRecentRun,
    this.longestRecentBike,
    this.longestRecentSwim,
    this.adherenceSummary,
  });

  String toPromptPayload({
    UnitSystem? unitSystem,
    bool useImperial = false,
  }) {
    final unit =
        unitSystem ?? (useImperial ? UnitSystem.imperial : UnitSystem.metric);
    final dateStr = PlannedWorkout.formatLocalDate(asOfDate);

    final lines = <String>[
      'ATHLETE TELEMETRY SUMMARY (as of $dateStr):',
    ];

    final loadParts = <String>[];
    if (_isFinite(ctl)) loadParts.add('CTL ${ctl!.toStringAsFixed(1)}');
    if (_isFinite(atl)) loadParts.add('ATL ${atl!.toStringAsFixed(1)}');
    if (_isFinite(tsb)) loadParts.add('TSB ${tsb!.toStringAsFixed(1)}');
    if (_isFinite(acwr)) {
      final statusSuffix = (acwrStatus != null && acwrStatus!.trim().isNotEmpty)
          ? ' (${acwrStatus!.trim()})'
          : '';
      loadParts.add('ACWR ${acwr!.toStringAsFixed(2)}$statusSuffix');
    }
    if (restingHr != null && restingHr! > 0) {
      loadParts.add('RHR $restingHr bpm');
    }
    if (hrvMs != null && hrvMs! > 0) {
      loadParts.add('HRV $hrvMs ms');
    }
    if (_isFinite(vo2MaxEst)) {
      loadParts.add('VO2max ${vo2MaxEst!.toStringAsFixed(1)}');
    }
    if (loadParts.isEmpty) {
      loadParts.add('No load/readiness metrics available yet');
    }
    lines.add('- Load & Readiness: ${loadParts.join(' | ')}');

    lines.add('- Derived Zones:');
    final hrZonesText = zones.hrZones
        .map((z) => 'Z${z.zone} ${z.lowBpm}-${z.highBpm}')
        .join(', ');
    lines.add(
      '  - HR: Max ${zones.maxHr} bpm, LTHR ${zones.lthr} bpm'
      '${hrZonesText.isNotEmpty ? ' | $hrZonesText bpm' : ''}',
    );

    if (zones.runThresholdPaceSecPerKm != null &&
        zones.runThresholdPaceSecPerKm!.isFinite &&
        zones.runThresholdPaceSecPerKm! > 0) {
      final secKm = zones.runThresholdPaceSecPerKm!;
      final secMi = secKm / UnitFormatter.kmToMiles;
      final primary = unit == UnitSystem.metric
          ? '${_formatMmSs(secKm)}/km (${_formatMmSs(secMi)}/mi)'
          : '${_formatMmSs(secMi)}/mi (${_formatMmSs(secKm)}/km)';
      lines.add('  - Run Threshold Pace: $primary');
    } else {
      lines.add('  - Run Threshold Pace: Not available');
    }

    if (zones.swimCssSecPer100m != null &&
        zones.swimCssSecPer100m!.isFinite &&
        zones.swimCssSecPer100m! > 0) {
      final sec100m = zones.swimCssSecPer100m!;
      final sec100yd = zones.swimCssSecPer100yd!;
      final primary = unit == UnitSystem.metric
          ? '${_formatMmSs(sec100m)}/100m (${_formatMmSs(sec100yd)}/100yd)'
          : '${_formatMmSs(sec100yd)}/100yd (${_formatMmSs(sec100m)}/100m)';
      lines.add('  - Swim CSS: $primary');
    } else {
      lines.add('  - Swim CSS: Not available');
    }

    lines.add(
      '  - Bike FTP: '
      '${zones.bikeFtpWatts != null && zones.bikeFtpWatts! > 0 ? '${zones.bikeFtpWatts} W' : 'Not available'}',
    );

    lines.add('- Weekly Volume (4w avg vs 12w avg):');
    lines.add(
      '  - Total: ${_formatFixed(avgWeeklyHours4w, 1)} hrs/wk (4w) | '
      '${_formatFixed(avgWeeklyHours12w, 1)} hrs/wk (12w)',
    );

    for (final sport in const [
      SportDiscipline.swim,
      SportDiscipline.bike,
      SportDiscipline.run,
      SportDiscipline.strength,
    ]) {
      final v4 = volume4w[sport] ??
          const SportVolumeSummary(
            avgWeeklyDistanceKm: 0,
            avgWeeklyHours: 0,
            sessionsCount: 0,
          );
      final v12 = volume12w[sport] ??
          const SportVolumeSummary(
            avgWeeklyDistanceKm: 0,
            avgWeeklyHours: 0,
            sessionsCount: 0,
          );
      if (sport == SportDiscipline.strength) {
        final s4 = (v4.sessionsCount / 4.0).toStringAsFixed(1);
        final s12 = (v12.sessionsCount / 12.0).toStringAsFixed(1);
        lines.add(
          '  - Strength: $s4/wk (${_formatFixed(v4.avgWeeklyHours, 1)}h) | '
          '12w: $s12/wk (${_formatFixed(v12.avgWeeklyHours, 1)}h)',
        );
      } else {
        final label = switch (sport) {
          SportDiscipline.swim => 'Swim',
          SportDiscipline.bike => 'Bike',
          SportDiscipline.run => 'Run',
          _ => sport.name,
        };
        final d4 = UnitFormatter.formatDistance(
          _safeNonNegative(v4.avgWeeklyDistanceKm),
          unit,
          discipline: sport,
          decimals: 1,
        );
        final d12 = UnitFormatter.formatDistance(
          _safeNonNegative(v12.avgWeeklyDistanceKm),
          unit,
          discipline: sport,
          decimals: 1,
        );
        lines.add(
          '  - $label: $d4/wk (${_formatFixed(v4.avgWeeklyHours, 1)}h) | '
          '12w: $d12/wk (${_formatFixed(v12.avgWeeklyHours, 1)}h)',
        );
      }
    }

    final longestParts = <String>[];
    if (longestRecentRun != null) {
      final dist = UnitFormatter.formatDistance(
        _safeNonNegative(longestRecentRun!.distanceKm),
        unit,
        discipline: SportDiscipline.run,
        decimals: 1,
      );
      longestParts
          .add('Run $dist (${_formatDurationCompact(longestRecentRun!.durationSeconds)})');
    }
    if (longestRecentBike != null) {
      final dist = UnitFormatter.formatDistance(
        _safeNonNegative(longestRecentBike!.distanceKm),
        unit,
        discipline: SportDiscipline.bike,
        decimals: 1,
      );
      longestParts
          .add('Bike $dist (${_formatDurationCompact(longestRecentBike!.durationSeconds)})');
    }
    if (longestRecentSwim != null) {
      final dist = UnitFormatter.formatDistance(
        _safeNonNegative(longestRecentSwim!.distanceKm),
        unit,
        discipline: SportDiscipline.swim,
        decimals: 0,
      );
      longestParts
          .add('Swim $dist (${_formatDurationCompact(longestRecentSwim!.durationSeconds)})');
    }
    lines.add(
      '- Longest Recent (180d): '
      '${longestParts.isNotEmpty ? longestParts.join(' | ') : 'None recorded'}',
    );

    if (adherenceSummary != null) {
      final a = adherenceSummary!;
      final safeAvgAdherence = _isFinite(a.avgAdherencePercent)
          ? a.avgAdherencePercent.clamp(0.0, 100.0).toDouble()
          : 0.0;
      final missedDetail = a.recentMissedSummaries.isNotEmpty
          ? ' | Recent missed: ${a.recentMissedSummaries.join('; ')}'
          : '';
      lines.add(
        '- Current Plan Adherence: ${a.completed}/${a.totalDue} due sessions completed '
        '(${_formatFixed(safeAvgAdherence, 1)}% avg adherence), '
        '${a.skipped} skipped, ${a.missedOrPending} missed/pending$missedDetail',
      );
    }

    return lines.join('\n');
  }

  static bool _isFinite(double? v) => v != null && v.isFinite && v.abs() < 1e6;

  static double _safeNonNegative(double v) =>
      (_isFinite(v) && v >= 0) ? v : 0.0;

  static String _formatFixed(double v, int decimals) =>
      (_isFinite(v) && v >= 0 ? v : 0.0).toStringAsFixed(decimals);

  static String _formatMmSs(double totalSeconds) {
    if (!totalSeconds.isFinite || totalSeconds <= 0 || totalSeconds >= 1e6) {
      return '0:00';
    }
    final rounded = totalSeconds.round();
    final mins = rounded ~/ 60;
    final secs = rounded % 60;
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  static String _formatDurationCompact(double seconds) {
    if (!seconds.isFinite || seconds <= 0 || seconds > 1e7) return '0m';
    final totalMinutes = (seconds / 60.0).round();
    final hours = totalMinutes ~/ 60;
    final mins = totalMinutes % 60;
    if (hours > 0) {
      return mins == 0 ? '${hours}h' : '${hours}h${mins}m';
    }
    return '${mins}m';
  }
}

class AthleteContextBuilder {
  AthleteContextBuilder._();

  static const List<String> _hrZoneLabels = [
    'Recovery',
    'Aerobic',
    'Tempo',
    'Threshold',
    'VO2 Max',
  ];

  static AthleteContext build({
    required List<Activity> activities,
    required AthletePhysiologicalProfile profile,
    required List<PmcDataPoint> pmcSeries,
    TrainingPlan? activePlan,
    DateTime? now,
  }) {
    final referenceNow = (now ?? DateTime.now()).toLocal();
    final zones = deriveZones(
      activities: activities,
      profile: profile,
      now: referenceNow,
    );

    final latestPmc = _latestPmcPoint(pmcSeries);
    final ctl = _finiteOrNull(profile.ctlFitness) ?? _finiteOrNull(latestPmc?.ctl);
    final atl = _finiteOrNull(profile.atlFatigue) ?? _finiteOrNull(latestPmc?.atl);
    final tsb = _finiteOrNull(profile.tsbForm) ??
        _finiteOrNull(latestPmc?.tsb) ??
        ((ctl != null && atl != null) ? _finiteOrNull(ctl - atl) : null);
    final profileAcwr = _finiteOrNull(profile.acwrRatio);
    final validProfileAcwr =
        (profileAcwr != null && profileAcwr >= 0 && profileAcwr < 1e6)
            ? profileAcwr
            : null;
    final acwr = validProfileAcwr ?? _computeAcwr(ctl, atl);

    final vol4w = _computeVolume(activities, referenceNow, weeks: 4);
    final vol12w = _computeVolume(activities, referenceNow, weeks: 12);

    final totalHours4w = vol4w.values.fold<double>(
      0.0,
      (sum, v) => sum + v.avgWeeklyHours,
    );
    final totalHours12w = vol12w.values.fold<double>(
      0.0,
      (sum, v) => sum + v.avgWeeklyHours,
    );

    final cutoff180d = referenceNow.subtract(const Duration(days: 180));
    final recent180 = activities
        .where((a) => !a.timestamp.toLocal().isBefore(cutoff180d))
        .toList();
    final poolForLongest = recent180.isNotEmpty ? recent180 : activities;

    return AthleteContext(
      asOfDate: referenceNow,
      zones: zones,
      ctl: ctl,
      atl: atl,
      tsb: tsb,
      acwr: acwr,
      acwrStatus: profile.acwrStatus,
      restingHr: profile.restingHr,
      hrvMs: profile.hrvMs,
      vo2MaxEst: _finiteOrNull(profile.vo2MaxEst),
      avgWeeklyHours4w: double.parse(_finiteOrZero(totalHours4w).toStringAsFixed(2)),
      avgWeeklyHours12w: double.parse(_finiteOrZero(totalHours12w).toStringAsFixed(2)),
      volume4w: vol4w,
      volume12w: vol12w,
      longestRecentRun: _longestSession(
        poolForLongest,
        const {SportDiscipline.run},
      ),
      longestRecentBike: _longestSession(
        poolForLongest,
        const {SportDiscipline.bike, SportDiscipline.indoorBike},
      ),
      longestRecentSwim: _longestSession(
        poolForLongest,
        const {SportDiscipline.swim},
      ),
      adherenceSummary: activePlan != null
          ? _computeAdherenceSummary(activePlan, referenceNow)
          : null,
    );
  }

  static AthleteZonesSnapshot deriveZones({
    required List<Activity> activities,
    required AthletePhysiologicalProfile profile,
    DateTime? now,
  }) {
    final referenceNow = (now ?? DateTime.now()).toLocal();
    final cutoff180d = referenceNow.subtract(const Duration(days: 180));
    final recent = activities
        .where((a) => !a.timestamp.toLocal().isBefore(cutoff180d))
        .toList();
    final primaryPool = recent.isNotEmpty ? recent : activities;

    final maxHr = _deriveMaxHr(primaryPool, activities);
    final lthr = _deriveLthr(primaryPool, activities, profile, maxHr);
    final hrZones = _buildFrielHrZones(maxHr, lthr, profile.restingHr);

    final runThreshold = _deriveRunThresholdPace(primaryPool, activities);
    final swimCss = _deriveSwimCss(primaryPool, activities);
    final bikeFtp = _deriveBikeFtp(primaryPool, activities, profile);

    return AthleteZonesSnapshot(
      maxHr: maxHr,
      lthr: lthr,
      hrZones: hrZones,
      runThresholdPaceSecPerKm: runThreshold,
      swimCssSecPer100m: swimCss,
      bikeFtpWatts: bikeFtp,
    );
  }

  static int _deriveMaxHr(List<Activity> recent, List<Activity> all) {
    List<int> collectMaxHrs(List<Activity> source) => source
        .map((a) => a.maxHr)
        .where((hr) => hr >= 130 && hr <= 225)
        .toList()
      ..sort((a, b) => b.compareTo(a));

    var maxHrs = collectMaxHrs(recent);
    if (maxHrs.isEmpty) {
      maxHrs = collectMaxHrs(all);
    }

    if (maxHrs.isNotEmpty) {
      if (maxHrs.length >= 3 && (maxHrs[0] - maxHrs[1]) > 20) {
        return maxHrs[1];
      }
      return maxHrs[0];
    }

    final avgHrs = (recent.isNotEmpty ? recent : all)
        .map((a) => a.avgHr)
        .where((hr) => hr >= 100 && hr <= 210)
        .toList();
    if (avgHrs.isNotEmpty) {
      final peakAvg = avgHrs.reduce(math.max);
      if (peakAvg > 165) {
        return (peakAvg / 0.88).round().clamp(150, 220);
      }
      return math.max(190, (peakAvg / 0.85).round().clamp(140, 220));
    }

    return 190;
  }

  static int _deriveLthr(
    List<Activity> recent,
    List<Activity> all,
    AthletePhysiologicalProfile profile,
    int maxHr,
  ) {
    final lowerBound = (maxHr * 0.80).round();
    final upperBound = (maxHr * 0.95).round();

    int? scan(List<Activity> source) {
      int? best;
      for (final a in source) {
        if (a.discipline != SportDiscipline.run &&
            a.discipline != SportDiscipline.bike &&
            a.discipline != SportDiscipline.indoorBike) {
          continue;
        }
        final dur = _effectiveDurationSeconds(a);
        if (dur < 1200 || dur > 5400) continue;
        if (a.avgHr < (maxHr * 0.78).round() || a.avgHr > maxHr) continue;

        final int est;
        if (dur <= 2100) {
          est = (a.avgHr * 0.96).round();
        } else if (dur <= 3600) {
          est = a.avgHr;
        } else {
          est = (a.avgHr * 1.02).round();
        }
        if (best == null || est > best) {
          best = est;
        }
      }
      return best;
    }

    final candidate = scan(recent) ?? scan(all);
    if (candidate != null) {
      return candidate.clamp(lowerBound, upperBound);
    }

    if (profile.restingHr != null &&
        profile.restingHr! > 30 &&
        profile.restingHr! < maxHr - 40) {
      final karvonen =
          (profile.restingHr! + 0.85 * (maxHr - profile.restingHr!)).round();
      return karvonen.clamp(lowerBound, upperBound);
    }

    return (maxHr * 0.88).round().clamp(lowerBound, upperBound);
  }

  static List<HrZoneRange> _buildFrielHrZones(
    int maxHr,
    int lthr,
    int? restingHr,
  ) {
    final z1Low = (restingHr != null && restingHr > 30 && restingHr < lthr - 30)
        ? restingHr
        : (maxHr * 0.50).round();
    final z1High = (lthr * 0.81).round().clamp(z1Low + 5, lthr - 20);
    final z2Low = z1High + 1;
    final z2High = (lthr * 0.89).round().clamp(z2Low + 2, lthr - 12);
    final z3Low = z2High + 1;
    final z3High = (lthr * 0.93).round().clamp(z3Low + 2, lthr - 6);
    final z4Low = z3High + 1;
    final z4High = (lthr * 1.01).round().clamp(z4Low + 2, maxHr - 3);
    final z5Low = z4High + 1;
    final z5High = math.max(z5Low + 1, maxHr);

    final bounds = <(int, int)>[
      (z1Low, z1High),
      (z2Low, z2High),
      (z3Low, z3High),
      (z4Low, z4High),
      (z5Low, z5High),
    ];

    return List<HrZoneRange>.generate(5, (i) {
      return HrZoneRange(
        zone: i + 1,
        label: _hrZoneLabels[i],
        lowBpm: bounds[i].$1,
        highBpm: bounds[i].$2,
      );
    });
  }

  static double? _deriveRunThresholdPace(
    List<Activity> recent,
    List<Activity> all,
  ) {
    double? scan(List<Activity> source, double minKm, double minSec) {
      double? best;
      for (final a in source) {
        if (a.discipline != SportDiscipline.run) continue;
        final dur = _effectiveDurationSeconds(a);
        if (!a.distanceKm.isFinite ||
            a.distanceKm < minKm ||
            !dur.isFinite ||
            dur < minSec) {
          continue;
        }
        final paceSecPerKm = dur / a.distanceKm;
        if (paceSecPerKm < 150.0 || paceSecPerKm > 600.0) continue;

        final scale = math.pow(3000.0 / dur, 0.06).toDouble().clamp(0.92, 1.08);
        final candidate = paceSecPerKm * scale;
        if (candidate.isFinite && (best == null || candidate < best)) {
          best = candidate;
        }
      }
      return best;
    }

    final result = scan(recent, 3.0, 720) ??
        scan(recent, 1.5, 360) ??
        scan(all, 3.0, 720) ??
        scan(all, 1.5, 360);
    if (result == null || !result.isFinite) return null;
    return double.parse(result.toStringAsFixed(1));
  }

  static double? _deriveSwimCss(
    List<Activity> recent,
    List<Activity> all,
  ) {
    double? scan(List<Activity> source, double minKm, double minSec) {
      double? best;
      for (final a in source) {
        if (a.discipline != SportDiscipline.swim) continue;
        final dur = _effectiveDurationSeconds(a);
        if (!a.distanceKm.isFinite ||
            a.distanceKm < minKm ||
            !dur.isFinite ||
            dur < minSec) {
          continue;
        }
        final secPer100m = dur / (a.distanceKm * 10.0);
        if (secPer100m < 50.0 || secPer100m > 240.0) continue;

        final distanceM = a.distanceKm * 1000.0;
        final scale =
            math.pow(1000.0 / distanceM, 0.03).toDouble().clamp(0.95, 1.05);
        final candidate = secPer100m * scale;
        if (candidate.isFinite && (best == null || candidate < best)) {
          best = candidate;
        }
      }
      return best;
    }

    final result = scan(recent, 0.4, 240) ??
        scan(recent, 0.2, 120) ??
        scan(all, 0.4, 240) ??
        scan(all, 0.2, 120);
    if (result == null || !result.isFinite) return null;
    return double.parse(result.toStringAsFixed(1));
  }

  static int? _deriveBikeFtp(
    List<Activity> recent,
    List<Activity> all,
    AthletePhysiologicalProfile profile,
  ) {
    int? scan(List<Activity> source) {
      int? best;
      for (final a in source) {
        if (a.discipline != SportDiscipline.bike &&
            a.discipline != SportDiscipline.indoorBike) {
          continue;
        }
        final dur = _effectiveDurationSeconds(a);
        if (!dur.isFinite || dur < 300) continue;

        var power = (a.normPowerW != null && a.normPowerW! > 0)
            ? a.normPowerW!
            : ((a.avgPowerW != null && a.avgPowerW! > 0) ? a.avgPowerW! : 0);

        if (power <= 0 && a.splits.isNotEmpty) {
          final powerSplits =
              a.splits.where((s) => s.avgPower != null && s.avgPower! > 0);
          if (powerSplits.isNotEmpty) {
            double weightedSum = 0;
            double totalSec = 0;
            for (final s in powerSplits) {
              final sSec = _parseDurationString(s.time);
              final w = (sSec.isFinite && sSec > 0) ? sSec : 1.0;
              weightedSum += s.avgPower! * w;
              totalSec += w;
            }
            if (totalSec.isFinite && totalSec > 0 && weightedSum.isFinite) {
              final avg = weightedSum / totalSec;
              if (avg.isFinite) {
                power = avg.round();
              }
            }
          }
        }

        if (power <= 0 && a.ergSteps.isNotEmpty) {
          final validSteps = a.ergSteps.where((e) => e.actualWatts > 0).toList();
          if (validSteps.isNotEmpty) {
            final totalW =
                validSteps.fold<int>(0, (sum, e) => sum + e.actualWatts);
            power = (totalW / validSteps.length).round();
          }
        }

        if (power <= 0) continue;

        final int candidate;
        if (a.normPowerW != null &&
            a.normPowerW! > 0 &&
            a.intensityFactor != null &&
            a.intensityFactor!.isFinite &&
            a.intensityFactor! >= 0.5 &&
            a.intensityFactor! <= 1.25) {
          candidate = (a.normPowerW! / a.intensityFactor!).round();
        } else if (dur >= 1200 && dur <= 2100) {
          candidate = (power * 0.95).round();
        } else if (dur > 2100 && dur <= 4500) {
          candidate = (power * 0.98).round();
        } else if (dur > 4500) {
          candidate = power;
        } else {
          candidate = (power * 0.88).round();
        }

        if (candidate >= 50 && candidate <= 600) {
          if (best == null || candidate > best) {
            best = candidate;
          }
        }
      }
      return best;
    }

    final fromActivities = scan(recent) ?? scan(all);
    if (fromActivities != null) return fromActivities;
    if (profile.ftpWatts != null && profile.ftpWatts! > 0) {
      return profile.ftpWatts;
    }
    return null;
  }

  static Map<SportDiscipline, SportVolumeSummary> _computeVolume(
    List<Activity> activities,
    DateTime referenceNow, {
    required int weeks,
  }) {
    final cutoff = referenceNow.subtract(Duration(days: weeks * 7));
    final distances = <SportDiscipline, double>{
      SportDiscipline.swim: 0.0,
      SportDiscipline.bike: 0.0,
      SportDiscipline.run: 0.0,
      SportDiscipline.strength: 0.0,
    };
    final seconds = <SportDiscipline, double>{
      SportDiscipline.swim: 0.0,
      SportDiscipline.bike: 0.0,
      SportDiscipline.run: 0.0,
      SportDiscipline.strength: 0.0,
    };
    final counts = <SportDiscipline, int>{
      SportDiscipline.swim: 0,
      SportDiscipline.bike: 0,
      SportDiscipline.run: 0,
      SportDiscipline.strength: 0,
    };

    for (final a in activities) {
      final localTs = a.timestamp.toLocal();
      if (localTs.isBefore(cutoff) || localTs.isAfter(referenceNow)) continue;

      final key = a.discipline == SportDiscipline.indoorBike
          ? SportDiscipline.bike
          : a.discipline;
      if (!distances.containsKey(key)) continue;

      final dist =
          (a.distanceKm.isFinite && a.distanceKm > 0 && a.distanceKm <= 1e9)
              ? a.distanceKm
              : 0.0;
      final rawDur = _effectiveDurationSeconds(a);
      final dur = (rawDur.isFinite && rawDur > 0) ? rawDur : 0.0;
      distances[key] = distances[key]! + dist;
      seconds[key] = seconds[key]! + dur;
      counts[key] = counts[key]! + 1;
    }

    return {
      for (final sport in distances.keys)
        sport: SportVolumeSummary(
          avgWeeklyDistanceKm: double.parse(
            _finiteOrZero(distances[sport]! / weeks).toStringAsFixed(2),
          ),
          avgWeeklyHours: double.parse(
            _finiteOrZero((seconds[sport]! / 3600.0) / weeks)
                .toStringAsFixed(2),
          ),
          sessionsCount: counts[sport]!,
        ),
    };
  }

  static LongestSessionSummary? _longestSession(
    List<Activity> activities,
    Set<SportDiscipline> disciplines,
  ) {
    Activity? best;
    double bestMetric = -1;
    for (final a in activities) {
      if (!disciplines.contains(a.discipline)) continue;
      final rawDur = _effectiveDurationSeconds(a);
      final dur = (rawDur.isFinite && rawDur > 0) ? rawDur : 0.0;
      final dist =
          (a.distanceKm.isFinite && a.distanceKm > 0 && a.distanceKm <= 1e9)
              ? a.distanceKm
              : 0.0;
      final score = dist > 0 ? dist : (dur / 3600.0);
      if (!score.isFinite || score <= 0) continue;
      if (best == null || score > bestMetric) {
        best = a;
        bestMetric = score;
      }
    }
    if (best == null) return null;
    final bestDur = _effectiveDurationSeconds(best);
    return LongestSessionSummary(
      distanceKm: (best.distanceKm.isFinite &&
              best.distanceKm > 0 &&
              best.distanceKm <= 1e9)
          ? best.distanceKm
          : 0.0,
      durationSeconds: (bestDur.isFinite && bestDur > 0) ? bestDur : 0.0,
      date: best.timestamp.toLocal(),
    );
  }

  static PlanAdherenceSummary _computeAdherenceSummary(
    TrainingPlan plan,
    DateTime referenceNow,
  ) {
    final todayKey = PlannedWorkout.formatLocalDate(referenceNow);
    int totalDue = 0;
    int completed = 0;
    int skipped = 0;
    int missedOrPending = 0;
    final adherenceValues = <double>[];
    final missedSummaries = <String>[];

    for (final w in plan.allWorkouts) {
      if (w.archetype == WorkoutArchetype.rest) continue;
      if (w.date.isEmpty || w.date.compareTo(todayKey) > 0) continue;

      totalDue++;
      if (w.status == WorkoutStatus.completed) {
        completed++;
        final rawAdh = w.adherencePercent;
        final adh = (rawAdh != null && rawAdh.isFinite)
            ? rawAdh.clamp(0.0, 100.0).toDouble()
            : 100.0;
        adherenceValues.add(adh);
      } else if (w.status == WorkoutStatus.skipped) {
        skipped++;
      } else {
        missedOrPending++;
        if (missedSummaries.length < 5) {
          missedSummaries.add('${w.date} ${w.title}');
        }
      }
    }

    final avgAdherence = adherenceValues.isEmpty
        ? 0.0
        : double.parse(
            _finiteOrZero(
              adherenceValues.reduce((a, b) => a + b) / adherenceValues.length,
            ).toStringAsFixed(1),
          );

    return PlanAdherenceSummary(
      totalDue: totalDue,
      completed: completed,
      skipped: skipped,
      missedOrPending: missedOrPending,
      avgAdherencePercent: avgAdherence,
      recentMissedSummaries: missedSummaries,
    );
  }

  static PmcDataPoint? _latestPmcPoint(List<PmcDataPoint> pmcSeries) {
    if (pmcSeries.isEmpty) return null;
    PmcDataPoint latest = pmcSeries.first;
    for (final pt in pmcSeries.skip(1)) {
      if (pt.date.isAfter(latest.date)) {
        latest = pt;
      }
    }
    return latest;
  }

  static const double _maxDurationSeconds = 1e7;
  static final RegExp _plainDecimalPartRegex = RegExp(r'^\d+(?:\.\d+)?$');
  static final RegExp _unitDurationFullRegex = RegExp(
    r'^(?:\d+(?:\.\d+)?\s*(?:h|hr|hrs|m|min|mins|s|sec|secs)\b[\s,]*)+$',
    caseSensitive: false,
  );

  static double? _finiteOrNull(double? v) =>
      (v != null && v.isFinite && v.abs() < 1e6) ? v : null;

  static double _finiteOrZero(double v) =>
      (v.isFinite && v >= 0) ? v : 0.0;

  static double? _computeAcwr(double? ctl, double? atl) {
    if (ctl == null || atl == null || !ctl.isFinite || !atl.isFinite) {
      return null;
    }
    if (ctl <= 0.5 || atl < 0) return null;
    final ratio = atl / ctl;
    if (!ratio.isFinite || ratio >= 1e6) return null;
    return double.parse(ratio.toStringAsFixed(2));
  }

  static double _effectiveDurationSeconds(Activity activity) {
    if (activity.durationSeconds.isFinite &&
        activity.durationSeconds > 0 &&
        activity.durationSeconds <= _maxDurationSeconds) {
      return activity.durationSeconds;
    }
    final parsedMoving = _parseDurationString(activity.movingTime);
    if (parsedMoving.isFinite &&
        parsedMoving > 0 &&
        parsedMoving <= _maxDurationSeconds) {
      return parsedMoving;
    }
    final parsedElapsed = _parseDurationString(activity.elapsedTime);
    return (parsedElapsed.isFinite &&
            parsedElapsed > 0 &&
            parsedElapsed <= _maxDurationSeconds)
        ? parsedElapsed
        : 0.0;
  }

  static double _parseDurationString(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return 0.0;

    if (s.contains(':')) {
      final rawParts = s.split(':').map((p) => p.trim()).toList();
      if (rawParts.length == 2 || rawParts.length == 3) {
        if (!rawParts.every(_plainDecimalPartRegex.hasMatch)) {
          return 0.0;
        }
        final parts = rawParts.map(double.tryParse).toList();
        if (parts.every((p) => p != null && p.isFinite && p >= 0)) {
          final colonTotal = parts.length == 2
              ? parts[0]! * 60.0 + parts[1]!
              : parts[0]! * 3600.0 + parts[1]! * 60.0 + parts[2]!;
          return (colonTotal.isFinite &&
                  colonTotal >= 0 &&
                  colonTotal <= _maxDurationSeconds)
              ? colonTotal
              : 0.0;
        }
        return 0.0;
      }
    }

    if (!_unitDurationFullRegex.hasMatch(s)) return 0.0;

    double total = 0.0;
    bool matched = false;
    final regex = RegExp(
      r'(\d+(?:\.\d+)?)\s*(h|hr|hrs|m|min|mins|s|sec|secs)\b',
      caseSensitive: false,
    );
    for (final m in regex.allMatches(s)) {
      final val = double.tryParse(m.group(1)!);
      final unit = m.group(2)!.toLowerCase();
      if (val == null || !val.isFinite || val < 0) continue;
      matched = true;
      final double increment;
      if (unit.startsWith('h')) {
        increment = val * 3600.0;
      } else if (unit.startsWith('m')) {
        increment = val * 60.0;
      } else {
        increment = val;
      }
      if (!increment.isFinite ||
          increment < 0 ||
          increment > _maxDurationSeconds) {
        return 0.0;
      }
      total += increment;
      if (!total.isFinite || total < 0 || total > _maxDurationSeconds) {
        return 0.0;
      }
    }
    return (matched &&
            total.isFinite &&
            total >= 0 &&
            total <= _maxDurationSeconds)
        ? total
        : 0.0;
  }
}
