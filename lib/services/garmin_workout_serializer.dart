import '../models/activity.dart';
import '../models/training_plan.dart';

class GarminWorkoutSerializer {
  GarminWorkoutSerializer._();

  static bool isGarminPushable(PlannedWorkout workout) =>
      workout.isGarminPushable;

  static Map<String, dynamic> serialize(
    PlannedWorkout workout, {
    PlannedWorkout? overrideWorkout,
    AthleteZonesSnapshot? zones,
    double poolLengthMeters = 25.0,
  }) {
    if (overrideWorkout == null && !isGarminPushable(workout)) {
      throw ArgumentError(
        'Workout "${workout.title}" (${workout.archetype.name}/${workout.discipline.name}) '
        'is not Garmin-pushable.',
      );
    }

    PlannedWorkout? candidate = overrideWorkout ??
        (workout.archetype == WorkoutArchetype.brick
            ? workout.brickRunLeg
            : workout);

    if (candidate == null) {
      throw ArgumentError(
        'Brick workout "${workout.title}" does not have a run leg to serialize.',
      );
    }

    if (candidate.archetype == WorkoutArchetype.brick) {
      candidate = candidate.brickRunLeg;
      if (candidate == null) {
        throw ArgumentError(
          'Brick workout "${workout.title}" does not have a run leg to serialize.',
        );
      }
    }

    if (!isGarminPushable(candidate) ||
        (candidate.discipline != SportDiscipline.run &&
            candidate.discipline != SportDiscipline.swim)) {
      throw ArgumentError(
        'Workout "${candidate.title}" (${candidate.archetype.name}/${candidate.discipline.name}) '
        'cannot be serialized for Garmin workout-service.',
      );
    }

    final resolved = candidate;
    final sportType = _sportTypeFor(resolved.discipline);
    final serializedSteps = _serializeBlocks(
      resolved,
      zones: zones,
    );

    final resolvedNotes = resolved.coachNotes?.trim();
    final parentNotes = workout.coachNotes?.trim();
    final description = (resolvedNotes != null && resolvedNotes.isNotEmpty)
        ? resolvedNotes
        : (parentNotes != null && parentNotes.isNotEmpty ? parentNotes : null);

    final payload = <String, dynamic>{
      'workoutName': resolved.title.trim().isNotEmpty
          ? resolved.title.trim()
          : 'Pulse Workout',
      'description': description,
      'sportType': sportType,
      if (resolved.discipline == SportDiscipline.swim) ...{
        'poolLength': (poolLengthMeters.isFinite && poolLengthMeters > 0)
            ? poolLengthMeters
            : 25.0,
        'poolLengthUnit': const {
          'unitId': 1,
          'unitKey': 'meter',
          'factor': 100.0,
        },
      },
      'workoutSegments': [
        {
          'segmentOrder': 1,
          'sportType': sportType,
          'workoutSteps': serializedSteps,
        },
      ],
    };

    return payload;
  }

  static Map<String, dynamic> _sportTypeFor(SportDiscipline discipline) {
    return switch (discipline) {
      SportDiscipline.run => const {
          'sportTypeId': 1,
          'sportTypeKey': 'running',
        },
      SportDiscipline.swim => const {
          'sportTypeId': 4,
          'sportTypeKey': 'swimming',
        },
      _ => throw ArgumentError(
          'Unsupported Garmin workout discipline: ${discipline.name}',
        ),
    };
  }

  static List<Map<String, dynamic>> _serializeBlocks(
    PlannedWorkout resolved, {
    AthleteZonesSnapshot? zones,
  }) {
    var nextOrder = 1;
    final serialized = <Map<String, dynamic>>[];

    for (final block in resolved.blocks) {
      final children = block.effectiveSteps;
      if (block.repeatCount > 1 && children.isNotEmpty) {
        final groupOrder = nextOrder++;
        final childDtos = <Map<String, dynamic>>[];
        for (final child in children) {
          childDtos.add(
            _serializeStep(
              child,
              stepOrder: nextOrder++,
              discipline: resolved.discipline,
              zones: zones,
            ),
          );
        }
        serialized.add({
          'type': 'RepeatGroupDTO',
          'stepId': null,
          'stepOrder': groupOrder,
          'stepType': const {
            'stepTypeId': 6,
            'stepTypeKey': 'repeat',
          },
          'numberOfIterations': block.repeatCount,
          'endCondition': const {
            'conditionTypeId': 7,
            'conditionTypeKey': 'iterations',
          },
          'endConditionValue': block.repeatCount.toDouble(),
          'smartRepeat': false,
          'workoutSteps': childDtos,
        });
      } else {
        for (final step in children) {
          serialized.add(
            _serializeStep(
              step,
              stepOrder: nextOrder++,
              discipline: resolved.discipline,
              zones: zones,
            ),
          );
        }
      }
    }

    if (serialized.isEmpty) {
      final StepEndCondition fallbackEndCondition;
      final double? fallbackEndValue;
      if (resolved.estimatedDurationMinutes > 0) {
        fallbackEndCondition = StepEndCondition.time;
        fallbackEndValue = resolved.estimatedDurationMinutes * 60.0;
      } else if (resolved.estimatedDistanceKm != null &&
          resolved.estimatedDistanceKm!.isFinite &&
          resolved.estimatedDistanceKm! > 0) {
        fallbackEndCondition = StepEndCondition.distance;
        fallbackEndValue = resolved.estimatedDistanceKm! * 1000.0;
      } else {
        fallbackEndCondition = StepEndCondition.lapButton;
        fallbackEndValue = null;
      }

      serialized.add(
        _serializeStep(
          WorkoutStep(
            kind: StepKind.steady,
            endCondition: fallbackEndCondition,
            endValue: fallbackEndValue,
            targetKind: StepTargetKind.none,
            notes: resolved.coachNotes,
          ),
          stepOrder: 1,
          discipline: resolved.discipline,
          zones: zones,
        ),
      );
    }

    return serialized;
  }

  static Map<String, dynamic> _serializeStep(
    WorkoutStep step, {
    required int stepOrder,
    required SportDiscipline discipline,
    AthleteZonesSnapshot? zones,
  }) {
    final stepType = _stepTypeFor(step.kind);
    final endMapping = _endConditionFor(step.endCondition, step.endValue);
    final targetMapping = _targetFor(step, zones: zones);
    final notes = step.notes?.trim();

    return {
      'type': 'ExecutableStepDTO',
      'stepId': null,
      'stepOrder': stepOrder,
      'stepType': stepType,
      'endCondition': endMapping.endCondition,
      'endConditionValue': endMapping.endConditionValue,
      'targetType': targetMapping.targetType,
      'targetValueOne': targetMapping.targetValueOne,
      'targetValueTwo': targetMapping.targetValueTwo,
      'zoneNumber': targetMapping.zoneNumber,
      'description': (notes != null && notes.isNotEmpty) ? notes : null,
      if (discipline == SportDiscipline.swim)
        'strokeType': _strokeTypeFor(step),
    };
  }

  static Map<String, dynamic> _stepTypeFor(StepKind kind) {
    return switch (kind) {
      StepKind.warmup => const {
          'stepTypeId': 1,
          'stepTypeKey': 'warmup',
        },
      StepKind.cooldown => const {
          'stepTypeId': 2,
          'stepTypeKey': 'cooldown',
        },
      StepKind.interval || StepKind.steady => const {
          'stepTypeId': 3,
          'stepTypeKey': 'interval',
        },
      StepKind.recovery => const {
          'stepTypeId': 4,
          'stepTypeKey': 'recovery',
        },
      StepKind.rest => const {
          'stepTypeId': 5,
          'stepTypeKey': 'rest',
        },
    };
  }

  static ({
    Map<String, dynamic> endCondition,
    double? endConditionValue,
  }) _endConditionFor(StepEndCondition condition, double? endValue) {
    final validValue =
        (endValue != null && endValue.isFinite && endValue > 0) ? endValue : null;

    switch (condition) {
      case StepEndCondition.time:
        if (validValue != null) {
          return (
            endCondition: const {
              'conditionTypeId': 2,
              'conditionTypeKey': 'time',
            },
            endConditionValue: validValue.toDouble(),
          );
        }
        break;
      case StepEndCondition.distance:
        if (validValue != null) {
          return (
            endCondition: const {
              'conditionTypeId': 3,
              'conditionTypeKey': 'distance',
            },
            endConditionValue: validValue.toDouble(),
          );
        }
        break;
      case StepEndCondition.lapButton:
        break;
    }

    return (
      endCondition: const {
        'conditionTypeId': 1,
        'conditionTypeKey': 'lap.button',
      },
      endConditionValue: null,
    );
  }

  static ({
    Map<String, dynamic> targetType,
    double? targetValueOne,
    double? targetValueTwo,
    int? zoneNumber,
  }) _targetFor(
    WorkoutStep step, {
    AthleteZonesSnapshot? zones,
  }) {
    const noTarget = (
      targetType: {
        'workoutTargetTypeId': 1,
        'workoutTargetTypeKey': 'no.target',
      },
      targetValueOne: null,
      targetValueTwo: null,
      zoneNumber: null,
    );

    switch (step.targetKind) {
      case StepTargetKind.none:
        return noTarget;

      case StepTargetKind.paceMps:
        final bounds = _normalizedBounds(step.targetLow, step.targetHigh);
        if (bounds == null) return noTarget;
        return (
          targetType: const {
            'workoutTargetTypeId': 6,
            'workoutTargetTypeKey': 'pace.zone',
          },
          targetValueOne: bounds.low,
          targetValueTwo: bounds.high,
          zoneNumber: null,
        );

      case StepTargetKind.heartRateBpm:
        final bounds = _normalizedBounds(step.targetLow, step.targetHigh);
        if (bounds == null) return noTarget;
        return (
          targetType: const {
            'workoutTargetTypeId': 4,
            'workoutTargetTypeKey': 'heart.rate.zone',
          },
          targetValueOne: bounds.low.roundToDouble(),
          targetValueTwo: bounds.high.roundToDouble(),
          zoneNumber: null,
        );

      case StepTargetKind.heartRateZone:
        final rawLow = (step.targetLow != null &&
                step.targetLow!.isFinite &&
                step.targetLow! > 0)
            ? step.targetLow
            : null;
        final rawHigh = (step.targetHigh != null &&
                step.targetHigh!.isFinite &&
                step.targetHigh! > 0)
            ? step.targetHigh
            : null;
        if (rawLow == null && rawHigh == null) return noTarget;

        final lowZ = (rawLow ?? rawHigh)!.round().clamp(1, 5);
        final highZ = (rawHigh ?? rawLow)!.round().clamp(1, 5);
        final minZone = lowZ <= highZ ? lowZ : highZ;
        final maxZone = lowZ <= highZ ? highZ : lowZ;

        if (zones != null && zones.hrZones.isNotEmpty) {
          HrZoneRange? lowRange;
          HrZoneRange? highRange;
          for (final z in zones.hrZones) {
            if (z.zone == minZone) lowRange = z;
            if (z.zone == maxZone) highRange = z;
          }
          if (lowRange != null && highRange != null) {
            final lowBpm = lowRange.lowBpm.toDouble();
            final highBpm = highRange.highBpm.toDouble();
            return (
              targetType: const {
                'workoutTargetTypeId': 4,
                'workoutTargetTypeKey': 'heart.rate.zone',
              },
              targetValueOne: lowBpm <= highBpm ? lowBpm : highBpm,
              targetValueTwo: lowBpm <= highBpm ? highBpm : lowBpm,
              zoneNumber: null,
            );
          }
        }

        return (
          targetType: const {
            'workoutTargetTypeId': 4,
            'workoutTargetTypeKey': 'heart.rate.zone',
          },
          targetValueOne: null,
          targetValueTwo: null,
          zoneNumber: maxZone,
        );
    }
  }

  static ({double low, double high})? _normalizedBounds(
    double? rawLow,
    double? rawHigh,
  ) {
    final validLow =
        (rawLow != null && rawLow.isFinite && rawLow > 0) ? rawLow : null;
    final validHigh =
        (rawHigh != null && rawHigh.isFinite && rawHigh > 0) ? rawHigh : null;
    if (validLow == null && validHigh == null) return null;
    final a = validLow ?? validHigh!;
    final b = validHigh ?? validLow!;
    return a <= b ? (low: a, high: b) : (low: b, high: a);
  }

  static Map<String, dynamic> _strokeTypeFor(WorkoutStep step) {
    if (step.kind == StepKind.rest) {
      return const {
        'strokeTypeId': 0,
        'strokeTypeKey': null,
      };
    }
    final normalized = step.strokeType?.trim().toLowerCase() ?? '';
    return switch (normalized) {
      '' || 'free' || 'freestyle' => const {
          'strokeTypeId': 6,
          'strokeTypeKey': 'free',
        },
      'back' || 'backstroke' => const {
          'strokeTypeId': 2,
          'strokeTypeKey': 'backstroke',
        },
      'breast' || 'breaststroke' => const {
          'strokeTypeId': 3,
          'strokeTypeKey': 'breaststroke',
        },
      'drill' => const {
          'strokeTypeId': 4,
          'strokeTypeKey': 'drill',
        },
      'fly' || 'butterfly' => const {
          'strokeTypeId': 5,
          'strokeTypeKey': 'fly',
        },
      'im' || 'individual_medley' || 'individualmedley' => const {
          'strokeTypeId': 7,
          'strokeTypeKey': 'im',
        },
      'mixed' => const {
          'strokeTypeId': 8,
          'strokeTypeKey': 'mixed',
        },
      _ => const {
          'strokeTypeId': 1,
          'strokeTypeKey': 'any_stroke',
        },
    };
  }
}
