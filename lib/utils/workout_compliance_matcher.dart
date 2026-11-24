import 'dart:math' as math;

import '../models/activity.dart';
import '../models/training_plan.dart';

class _MatchSlot {
  final int weekIdx;
  final int workoutIdx;
  final bool isBrickRunLeg;
  final int order;
  final String dateKey;
  final SportDiscipline discipline;
  final int plannedDurationMinutes;
  final double? plannedDistanceKm;
  final String? existingMatchedActivityId;

  const _MatchSlot({
    required this.weekIdx,
    required this.workoutIdx,
    required this.isBrickRunLeg,
    required this.order,
    required this.dateKey,
    required this.discipline,
    required this.plannedDurationMinutes,
    required this.plannedDistanceKm,
    required this.existingMatchedActivityId,
  });

  String get slotKey => '$weekIdx:$workoutIdx:${isBrickRunLeg ? 1 : 0}';
}

class _MatchCandidate {
  final _MatchSlot slot;
  final Activity activity;
  final double score;

  const _MatchCandidate({
    required this.slot,
    required this.activity,
    required this.score,
  });
}

class WorkoutComplianceMatcher {
  WorkoutComplianceMatcher._();

  static String localDateKey(DateTime dt) => PlannedWorkout.formatLocalDate(dt);

  static bool isSportCompatible(
    SportDiscipline planned,
    SportDiscipline actual,
  ) {
    if (planned == actual) return true;
    const bikeTypes = {SportDiscipline.bike, SportDiscipline.indoorBike};
    return bikeTypes.contains(planned) && bikeTypes.contains(actual);
  }

  static TrainingPlan matchPlan(TrainingPlan plan, List<Activity> activities) {
    final activitiesByDate = <String, List<Activity>>{};
    for (final act in activities) {
      final key = localDateKey(act.timestamp);
      activitiesByDate.putIfAbsent(key, () => []).add(act);
    }
    for (final dayActs in activitiesByDate.values) {
      dayActs.sort((a, b) {
        final cmp = a.timestamp.toLocal().compareTo(b.timestamp.toLocal());
        if (cmp != 0) return cmp;
        return a.id.compareTo(b.id);
      });
    }

    final slotsByDate = <String, List<_MatchSlot>>{};
    int orderCounter = 0;

    for (var wIdx = 0; wIdx < plan.weeks.length; wIdx++) {
      final week = plan.weeks[wIdx];
      for (var dIdx = 0; dIdx < week.workouts.length; dIdx++) {
        final workout = week.workouts[dIdx];
        if (workout.archetype == WorkoutArchetype.rest) continue;
        if (workout.status == WorkoutStatus.skipped) continue;
        if (workout.date.trim().isEmpty) continue;

        if (workout.archetype == WorkoutArchetype.brick) {
          final bikePlannedMin = _brickBikePlannedMinutes(workout);
          final bikeDiscipline =
              workout.discipline == SportDiscipline.indoorBike
                  ? SportDiscipline.indoorBike
                  : SportDiscipline.bike;

          slotsByDate.putIfAbsent(workout.date, () => []).add(
                _MatchSlot(
                  weekIdx: wIdx,
                  workoutIdx: dIdx,
                  isBrickRunLeg: false,
                  order: orderCounter++,
                  dateKey: workout.date,
                  discipline: bikeDiscipline,
                  plannedDurationMinutes: bikePlannedMin,
                  plannedDistanceKm: workout.estimatedDistanceKm,
                  existingMatchedActivityId: workout.matchedActivityId,
                ),
              );

          final runLeg = workout.brickRunLeg;
          if (runLeg != null && runLeg.status != WorkoutStatus.skipped) {
            final runDate =
                runLeg.date.trim().isNotEmpty ? runLeg.date : workout.date;
            slotsByDate.putIfAbsent(runDate, () => []).add(
                  _MatchSlot(
                    weekIdx: wIdx,
                    workoutIdx: dIdx,
                    isBrickRunLeg: true,
                    order: orderCounter++,
                    dateKey: runDate,
                    discipline: SportDiscipline.run,
                    plannedDurationMinutes: runLeg.estimatedDurationMinutes,
                    plannedDistanceKm: runLeg.estimatedDistanceKm,
                    existingMatchedActivityId: runLeg.matchedActivityId,
                  ),
                );
          }
        } else {
          slotsByDate.putIfAbsent(workout.date, () => []).add(
                _MatchSlot(
                  weekIdx: wIdx,
                  workoutIdx: dIdx,
                  isBrickRunLeg: false,
                  order: orderCounter++,
                  dateKey: workout.date,
                  discipline: workout.discipline,
                  plannedDurationMinutes: workout.estimatedDurationMinutes,
                  plannedDistanceKm: workout.estimatedDistanceKm,
                  existingMatchedActivityId: workout.matchedActivityId,
                ),
              );
        }
      }
    }

    final matchedBySlotKey = <String, Activity>{};
    final usedActivityIds = <String>{};

    for (final entry in slotsByDate.entries) {
      final dateKey = entry.key;
      final daySlots = entry.value;
      final dayActs = activitiesByDate[dateKey] ?? const <Activity>[];
      if (dayActs.isEmpty) continue;

      final candidates = <_MatchCandidate>[];
      for (final slot in daySlots) {
        for (final act in dayActs) {
          if (!isSportCompatible(slot.discipline, act.discipline)) continue;
          final score = _pairScore(slot, act);
          candidates.add(
            _MatchCandidate(slot: slot, activity: act, score: score),
          );
        }
      }

      candidates.sort((a, b) {
        final scoreCmp = a.score.compareTo(b.score);
        if (scoreCmp != 0) return scoreCmp;
        final orderCmp = a.slot.order.compareTo(b.slot.order);
        if (orderCmp != 0) return orderCmp;
        final tsCmp = a.activity.timestamp
            .toLocal()
            .compareTo(b.activity.timestamp.toLocal());
        if (tsCmp != 0) return tsCmp;
        return a.activity.id.compareTo(b.activity.id);
      });

      final usedSlots = <String>{};
      for (final cand in candidates) {
        if (usedSlots.contains(cand.slot.slotKey)) continue;
        if (usedActivityIds.contains(cand.activity.id)) continue;
        usedSlots.add(cand.slot.slotKey);
        usedActivityIds.add(cand.activity.id);
        matchedBySlotKey[cand.slot.slotKey] = cand.activity;
      }
    }

    final updatedWeeks = <TrainingWeek>[];
    for (var wIdx = 0; wIdx < plan.weeks.length; wIdx++) {
      final week = plan.weeks[wIdx];
      final updatedWorkouts = <PlannedWorkout>[];

      for (var dIdx = 0; dIdx < week.workouts.length; dIdx++) {
        final workout = week.workouts[dIdx];
        if (workout.archetype == WorkoutArchetype.rest ||
            workout.status == WorkoutStatus.skipped) {
          updatedWorkouts.add(workout);
          continue;
        }

        if (workout.archetype == WorkoutArchetype.brick) {
          updatedWorkouts.add(
            _applyBrickMatch(
              workout: workout,
              bikeAct: matchedBySlotKey['$wIdx:$dIdx:0'],
              runAct: matchedBySlotKey['$wIdx:$dIdx:1'],
            ),
          );
        } else {
          final matchedAct = matchedBySlotKey['$wIdx:$dIdx:0'];
          if (matchedAct != null) {
            final adherence = computeAdherencePercent(
              plannedDurationMinutes: workout.estimatedDurationMinutes,
              plannedDistanceKm: workout.estimatedDistanceKm,
              activity: matchedAct,
            );
            updatedWorkouts.add(
              workout.copyWith(
                status: WorkoutStatus.completed,
                matchedActivityId: matchedAct.id,
                adherencePercent: adherence,
              ),
            );
          } else if (workout.status == WorkoutStatus.completed &&
              workout.matchedActivityId == null) {
            updatedWorkouts.add(workout);
          } else {
            updatedWorkouts.add(
              workout.copyWith(
                status: WorkoutStatus.scheduled,
                clearMatchedActivityId: true,
                clearAdherencePercent: true,
              ),
            );
          }
        }
      }

      updatedWeeks.add(week.copyWith(workouts: updatedWorkouts));
    }

    return plan.copyWith(weeks: updatedWeeks);
  }

  static PlannedWorkout _applyBrickMatch({
    required PlannedWorkout workout,
    required Activity? bikeAct,
    required Activity? runAct,
  }) {
    final bikePlannedMin = _brickBikePlannedMinutes(workout);
    final runLeg = workout.brickRunLeg;

    if (runLeg == null || runLeg.status == WorkoutStatus.skipped) {
      if (bikeAct != null) {
        final bikeAdh = computeAdherencePercent(
          plannedDurationMinutes: bikePlannedMin,
          plannedDistanceKm: workout.estimatedDistanceKm,
          activity: bikeAct,
        );
        return workout.copyWith(
          status: WorkoutStatus.completed,
          matchedActivityId: bikeAct.id,
          adherencePercent: bikeAdh,
        );
      }
      if (workout.status == WorkoutStatus.completed &&
          workout.matchedActivityId == null) {
        return workout;
      }
      return workout.copyWith(
        status: WorkoutStatus.scheduled,
        clearMatchedActivityId: true,
        clearAdherencePercent: true,
      );
    }

    final double? runAdh = runAct != null
        ? computeAdherencePercent(
            plannedDurationMinutes: runLeg.estimatedDurationMinutes,
            plannedDistanceKm: runLeg.estimatedDistanceKm,
            activity: runAct,
          )
        : null;

    final PlannedWorkout updatedRunLeg;
    if (runAct != null) {
      updatedRunLeg = runLeg.copyWith(
        status: WorkoutStatus.completed,
        matchedActivityId: runAct.id,
        adherencePercent: runAdh,
      );
    } else if (runLeg.status == WorkoutStatus.completed &&
        runLeg.matchedActivityId == null) {
      updatedRunLeg = runLeg;
    } else {
      updatedRunLeg = runLeg.copyWith(
        status: WorkoutStatus.scheduled,
        clearMatchedActivityId: true,
        clearAdherencePercent: true,
      );
    }

    final bikeMatched = bikeAct != null;
    final runMatched = runAct != null;
    final bikeManualCompleted = !bikeMatched &&
        workout.status == WorkoutStatus.completed &&
        workout.matchedActivityId == null;
    final runManualCompleted = !runMatched &&
        updatedRunLeg.status == WorkoutStatus.completed &&
        updatedRunLeg.matchedActivityId == null;

    if (bikeMatched || runMatched) {
      final bikeAdh = bikeAct != null
          ? computeAdherencePercent(
              plannedDurationMinutes: bikePlannedMin,
              plannedDistanceKm: workout.estimatedDistanceKm,
              activity: bikeAct,
            )
          : (bikeManualCompleted ? 100.0 : 0.0);
      final double effectiveRunAdh;
      if (runAct != null) {
        effectiveRunAdh = runAdh!;
      } else if (runManualCompleted) {
        final manualRunAdh = updatedRunLeg.adherencePercent;
        effectiveRunAdh = (manualRunAdh != null && manualRunAdh.isFinite)
            ? manualRunAdh.clamp(0.0, 100.0).toDouble()
            : 100.0;
      } else {
        effectiveRunAdh = 0.0;
      }

      final bikeWeight = bikePlannedMin > 0 ? bikePlannedMin.toDouble() : 1.0;
      final runWeight = runLeg.estimatedDurationMinutes > 0
          ? runLeg.estimatedDurationMinutes.toDouble()
          : 1.0;
      final weighted =
          ((bikeAdh * bikeWeight) + (effectiveRunAdh * runWeight)) /
              (bikeWeight + runWeight);
      final clampedWeighted =
          double.parse(weighted.clamp(0.0, 100.0).toStringAsFixed(1));

      final bikeDone = bikeMatched || bikeManualCompleted;
      final runDone = runMatched || runManualCompleted;
      final topStatus = (bikeDone && runDone)
          ? WorkoutStatus.completed
          : WorkoutStatus.scheduled;

      return workout.copyWith(
        status: topStatus,
        matchedActivityId: bikeAct?.id,
        clearMatchedActivityId: bikeAct == null,
        adherencePercent: clampedWeighted,
        brickRunLeg: updatedRunLeg,
      );
    }

    if (workout.status == WorkoutStatus.completed &&
        workout.matchedActivityId == null) {
      if (runLeg.matchedActivityId == null) {
        return workout;
      }
      return workout.copyWith(
        status: WorkoutStatus.completed,
        clearMatchedActivityId: true,
        clearAdherencePercent: true,
        brickRunLeg: updatedRunLeg,
      );
    }

    return workout.copyWith(
      status: WorkoutStatus.scheduled,
      clearMatchedActivityId: true,
      clearAdherencePercent: true,
      brickRunLeg: updatedRunLeg,
    );
  }

  static int _brickBikePlannedMinutes(PlannedWorkout workout) {
    if (workout.zwiftPrescription != null &&
        workout.zwiftPrescription!.durationMinutes > 0) {
      return workout.zwiftPrescription!.durationMinutes;
    }
    final runMin = workout.brickRunLeg?.estimatedDurationMinutes ?? 0;
    if (runMin > 0 && workout.estimatedDurationMinutes > runMin) {
      return workout.estimatedDurationMinutes - runMin;
    }
    return workout.estimatedDurationMinutes;
  }

  static double _pairScore(_MatchSlot slot, Activity act) {
    final actualMin = _effectiveDurationSeconds(act) / 60.0;
    final plannedMin = math.max(slot.plannedDurationMinutes, 1).toDouble();
    final durDiff = (actualMin - plannedMin).abs() / plannedMin;

    double score = durDiff;
    final plannedDist = slot.plannedDistanceKm;
    if (plannedDist != null &&
        plannedDist.isFinite &&
        plannedDist > 0 &&
        act.distanceKm.isFinite &&
        act.distanceKm > 0) {
      final distDiff = (act.distanceKm - plannedDist).abs() / plannedDist;
      if (distDiff.isFinite) {
        score = (durDiff / 2.0) + (distDiff / 2.0);
      }
    }

    if (slot.existingMatchedActivityId == act.id) {
      score -= 1e-6;
    }
    return score;
  }

  static double computeAdherencePercent({
    required int plannedDurationMinutes,
    double? plannedDistanceKm,
    required Activity activity,
  }) {
    final actualMinutes = _effectiveDurationSeconds(activity) / 60.0;

    double? durRatio;
    if (plannedDurationMinutes > 0) {
      durRatio = (actualMinutes / plannedDurationMinutes).clamp(0.0, 1.0);
    }

    double? distRatio;
    if (plannedDistanceKm != null &&
        plannedDistanceKm.isFinite &&
        plannedDistanceKm > 0 &&
        activity.distanceKm.isFinite &&
        activity.distanceKm > 0) {
      distRatio = (activity.distanceKm / plannedDistanceKm).clamp(0.0, 1.0);
    }

    final double ratio;
    if (durRatio != null && distRatio != null) {
      ratio = (durRatio + distRatio) / 2.0;
    } else if (durRatio != null) {
      ratio = durRatio;
    } else if (distRatio != null) {
      ratio = distRatio;
    } else {
      ratio = actualMinutes > 0 ? 1.0 : 0.0;
    }

    return double.parse((ratio * 100.0).clamp(0.0, 100.0).toStringAsFixed(1));
  }

  static const double _maxDurationSeconds = 1e7;
  static final RegExp _plainDecimalPartRegex = RegExp(r'^\d+(?:\.\d+)?$');
  static final RegExp _unitDurationFullRegex = RegExp(
    r'^(?:\d+(?:\.\d+)?\s*(?:h|hr|hrs|m|min|mins|s|sec|secs)\b[\s,]*)+$',
    caseSensitive: false,
  );

  static double? computeWeekAdherencePercent(TrainingWeek week) {
    final values = <double>[];
    for (final w in week.workouts) {
      if (w.archetype == WorkoutArchetype.rest) continue;
      if (w.status == WorkoutStatus.skipped) continue;
      if (w.adherencePercent != null && w.adherencePercent!.isFinite) {
        values.add(w.adherencePercent!.clamp(0.0, 100.0).toDouble());
      } else if (w.status == WorkoutStatus.completed) {
        values.add(100.0);
      }
    }
    if (values.isEmpty) return null;
    final avg =
        (values.reduce((a, b) => a + b) / values.length).clamp(0.0, 100.0);
    return avg.isFinite ? double.parse(avg.toStringAsFixed(1)) : null;
  }

  static double? computePlanAdherencePercent(TrainingPlan plan) {
    final values = <double>[];
    for (final w in plan.allWorkouts) {
      if (w.archetype == WorkoutArchetype.rest) continue;
      if (w.status == WorkoutStatus.skipped) continue;
      if (w.adherencePercent != null && w.adherencePercent!.isFinite) {
        values.add(w.adherencePercent!.clamp(0.0, 100.0).toDouble());
      } else if (w.status == WorkoutStatus.completed) {
        values.add(100.0);
      }
    }
    if (values.isEmpty) return null;
    final avg =
        (values.reduce((a, b) => a + b) / values.length).clamp(0.0, 100.0);
    return avg.isFinite ? double.parse(avg.toStringAsFixed(1)) : null;
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
