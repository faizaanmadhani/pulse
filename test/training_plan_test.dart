import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_training_hub/models/activity.dart';
import 'package:pulse_training_hub/models/performance_metrics.dart';
import 'package:pulse_training_hub/models/training_block.dart' as legacy_block;
import 'package:pulse_training_hub/models/training_plan.dart';
import 'package:pulse_training_hub/services/training_plan_store.dart';
import 'package:pulse_training_hub/utils/athlete_context_builder.dart';
import 'package:pulse_training_hub/utils/unit_formatter.dart';
import 'package:pulse_training_hub/utils/workout_compliance_matcher.dart';

Activity _makeActivity({
  required String id,
  required SportDiscipline discipline,
  required DateTime timestamp,
  double distanceKm = 0.0,
  double durationSeconds = 0.0,
  String movingTime = '0:00',
  String elapsedTime = '0:00',
  int avgHr = 0,
  int maxHr = 0,
  int? avgPowerW,
  int? normPowerW,
  double? intensityFactor,
  double? tss,
  List<ActivitySplit> splits = const [],
  List<ErgStep> ergSteps = const [],
}) {
  return Activity(
    id: id,
    title: 'Test $id',
    description: '',
    discipline: discipline,
    timestamp: timestamp,
    formattedDate: '2026-11-20',
    location: 'Local',
    deviceHardware: 'Forerunner 970',
    sensorChain: 'HRM-Pro',
    distanceKm: distanceKm,
    durationSeconds: durationSeconds,
    movingTime: movingTime,
    elapsedTime: elapsedTime,
    avgSpeedOrPace: '—',
    maxSpeedOrPace: '—',
    avgHr: avgHr,
    maxHr: maxHr,
    elevationGainM: 0,
    elevationLossM: 0,
    avgPowerW: avgPowerW,
    normPowerW: normPowerW,
    intensityFactor: intensityFactor,
    tss: tss,
    calories: 400,
    splits: splits,
    ergSteps: ergSteps,
  );
}

TrainingPlan _samplePlan({
  List<TrainingWeek>? weeks,
}) {
  final now = DateTime.utc(2026, 11, 20, 12, 0);
  return TrainingPlan(
    id: 'plan_1',
    name: '70.3 Build Block',
    createdAt: now,
    updatedAt: now,
    coachOverview: 'Polarized 80/20 triathlon build focusing on swim CSS.',
    config: const TrainingPlanConfig(
      raceName: 'Oceanside 70.3',
      raceDistance: '70.3',
      raceDate: '2027-04-03',
      weeklyHoursBudget: 10.5,
      longRunDay: 'Sunday',
      longRideDay: 'Saturday',
      restDay: 'Friday',
      limiterSport: 'Swim',
      zones: AthleteZonesSnapshot(
        maxHr: 192,
        lthr: 173,
        hrZones: [
          HrZoneRange(zone: 1, label: 'Recovery', lowBpm: 96, highBpm: 140),
          HrZoneRange(zone: 2, label: 'Aerobic', lowBpm: 141, highBpm: 154),
          HrZoneRange(zone: 3, label: 'Tempo', lowBpm: 155, highBpm: 161),
          HrZoneRange(zone: 4, label: 'Threshold', lowBpm: 162, highBpm: 175),
          HrZoneRange(zone: 5, label: 'VO2 Max', lowBpm: 176, highBpm: 192),
        ],
        runThresholdPaceSecPerKm: 255.0,
        swimCssSecPer100m: 105.0,
        bikeFtpWatts: 275,
      ),
      additionalNotes: 'Prefer morning swims',
    ),
    weeks: weeks ??
        [
          TrainingWeek(
            weekNumber: 1,
            startDate: '2026-11-16',
            phaseName: 'Base',
            focusSummary: 'Aerobic durability + neuromuscular run speed',
            targetHours: 9.5,
            targetTss: 480,
            workouts: [
              PlannedWorkout(
                id: 'w1_run_intervals',
                date: '2026-11-17',
                title: 'Track 5x1km Intervals',
                discipline: SportDiscipline.run,
                archetype: WorkoutArchetype.intervals,
                estimatedDurationMinutes: 55,
                estimatedDistanceKm: 10.0,
                estimatedTss: 72,
                coachNotes: 'Smooth turnover, stay relaxed in Z4/Z5',
                rationale: 'VO2max stimulus',
                blocks: const [
                  WorkoutBlock(
                    step: WorkoutStep(
                      kind: StepKind.warmup,
                      endCondition: StepEndCondition.time,
                      endValue: 900,
                      targetKind: StepTargetKind.heartRateZone,
                      targetLow: 1,
                      targetHigh: 2,
                    ),
                  ),
                  WorkoutBlock(
                    repeatCount: 5,
                    steps: [
                      WorkoutStep(
                        kind: StepKind.interval,
                        endCondition: StepEndCondition.distance,
                        endValue: 1000,
                        targetKind: StepTargetKind.paceMps,
                        targetLow: 3.9,
                        targetHigh: 4.1,
                      ),
                      WorkoutStep(
                        kind: StepKind.recovery,
                        endCondition: StepEndCondition.time,
                        endValue: 120,
                        targetKind: StepTargetKind.none,
                      ),
                    ],
                  ),
                  WorkoutBlock(
                    step: WorkoutStep(
                      kind: StepKind.cooldown,
                      endCondition: StepEndCondition.lapButton,
                      targetKind: StepTargetKind.none,
                    ),
                  ),
                ],
              ),
              PlannedWorkout(
                id: 'w1_zwift_sweetspot',
                date: '2026-11-18',
                title: 'Zwift Sweet Spot',
                discipline: SportDiscipline.indoorBike,
                archetype: WorkoutArchetype.zwiftRide,
                estimatedDurationMinutes: 60,
                estimatedTss: 58,
                zwiftPrescription: const ZwiftPrescription(
                  durationMinutes: 60,
                  difficulty: 'Sweet Spot',
                  targetTss: 58,
                  zwiftCategory: 'Sweet Spot',
                  suggestedSearchTerms: ['SST Short', 'Carson'],
                  cadenceFocus: '85-95 rpm',
                  notes: 'Stay seated on climbs',
                ),
              ),
              PlannedWorkout(
                id: 'w1_swim_threshold',
                date: '2026-11-19',
                title: 'CSS 400m Repeats',
                discipline: SportDiscipline.swim,
                archetype: WorkoutArchetype.threshold,
                estimatedDurationMinutes: 45,
                estimatedDistanceKm: 2.4,
                estimatedTss: 48,
                blocks: const [
                  WorkoutBlock(
                    step: WorkoutStep(
                      kind: StepKind.warmup,
                      endCondition: StepEndCondition.distance,
                      endValue: 400,
                      strokeType: 'freestyle',
                    ),
                  ),
                ],
              ),
              PlannedWorkout(
                id: 'w1_rest',
                date: '2026-11-20',
                title: 'Rest & Mobility',
                discipline: SportDiscipline.strength,
                archetype: WorkoutArchetype.rest,
                estimatedDurationMinutes: 0,
              ),
              PlannedWorkout(
                id: 'w1_brick',
                date: '2026-11-21',
                title: 'Saturday Brick',
                discipline: SportDiscipline.bike,
                archetype: WorkoutArchetype.brick,
                estimatedDurationMinutes: 80,
                estimatedTss: 85,
                zwiftPrescription: const ZwiftPrescription(
                  durationMinutes: 60,
                  difficulty: 'Tempo',
                  targetTss: 60,
                  zwiftCategory: 'Tempo',
                  suggestedSearchTerms: ['Tempo'],
                ),
                brickRunLeg: PlannedWorkout(
                  id: 'w1_brick_run',
                  date: '2026-11-21',
                  title: 'Transition Run',
                  discipline: SportDiscipline.run,
                  archetype: WorkoutArchetype.easy,
                  estimatedDurationMinutes: 20,
                  estimatedDistanceKm: 4.0,
                ),
              ),
            ],
          ),
        ],
  );
}

void main() {
  group('Group 1 — TrainingPlan Models', () {
    test('full JSON round-trip preserves all models and helpers', () {
      final plan = _samplePlan();
      final msg = CoachMessage(
        id: 'm1',
        role: CoachMessageRole.assistant,
        content: 'Here is your plan.',
        createdAt: DateTime.utc(2026, 11, 20, 12, 5),
        proposedPlan: plan,
      );

      final decodedPlan = TrainingPlan.fromJson(plan.toJson());
      final decodedMsg = CoachMessage.fromJson(msg.toJson());

      expect(decodedPlan.id, plan.id);
      expect(decodedPlan.name, plan.name);
      expect(decodedPlan.config.raceDistance, '70.3');
      expect(decodedPlan.config.zones.maxHr, 192);
      expect(decodedPlan.config.zones.hrZones.length, 5);
      expect(decodedPlan.config.zones.runThresholdSpeedMps, closeTo(1000 / 255.0, 1e-6));
      expect(decodedPlan.config.zones.swimCssSecPer100yd, closeTo(105.0 / 1.09361, 1e-6));
      expect(decodedPlan.config.zones.bikeFtpWatts, 275);
      expect(decodedPlan.allWorkouts.length, 5);
      expect(
        decodedPlan.workoutsForDate(DateTime(2026, 11, 17)).map((w) => w.id),
        ['w1_run_intervals'],
      );

      final intervalWorkout = decodedPlan.allWorkouts.first;
      expect(intervalWorkout.blocks.length, 3);
      expect(intervalWorkout.blocks[1].isRepeat, isTrue);
      expect(intervalWorkout.blocks[1].repeatCount, 5);
      expect(intervalWorkout.blocks[1].effectiveSteps.length, 2);
      expect(intervalWorkout.isGarminPushable, isTrue);
      expect(intervalWorkout.scheduledDate, DateTime(2026, 11, 17));

      final zwiftWorkout = decodedPlan.allWorkouts[1];
      expect(zwiftWorkout.isGarminPushable, isFalse);
      expect(zwiftWorkout.zwiftPrescription?.suggestedSearchTerms,
          ['SST Short', 'Carson']);

      final restWorkout = decodedPlan.allWorkouts[3];
      expect(restWorkout.isGarminPushable, isFalse);

      final brickWorkout = decodedPlan.allWorkouts[4];
      expect(brickWorkout.isGarminPushable, isTrue);
      expect(brickWorkout.brickRunLeg?.estimatedDurationMinutes, 20);

      expect(decodedMsg.role, CoachMessageRole.assistant);
      expect(decodedMsg.proposedPlan?.id, plan.id);
    });

    test('defensive LLM JSON parsing handles aliases, coercion, and edge values', () {
      final rawJson = <String, dynamic>{
        'id': 42,
        'name': 'Messy LLM Plan',
        'createdAt': 'not-a-date',
        'config': {
          'weeklyHoursBudget': '12.5',
          'zones': {
            'maxHr': '188.4',
            'lthr': 170,
            'runThresholdPaceSecPerKm': '260',
            'swimCssSecPer100m': 110,
            'bikeFtpWatts': '265.2',
          },
        },
        'weeks': [
          {
            'weekNumber': '2',
            'startDate': '2026-11-23T08:30:00Z',
            'workouts': [
              {
                'id': 'llm_1',
                'date': '2026-11-24T15:00:00.000Z',
                'title': 'Weirdly Encoded Run',
                'discipline': 'RUNNING',
                'archetype': 'tempo',
                'estimatedDurationMinutes': '50',
                'status': 'unexpected_status',
                'adherencePercent': 140,
                'blocks': [
                  {
                    'repeatCount': 3,
                    'step': {
                      'kind': 'warm_up',
                      'endCondition': 'seconds',
                      'endValue': -15,
                      'targetKind': 'pace.zone',
                      'targetLow': 4.2,
                      'targetHigh': 3.8,
                    },
                  },
                  {
                    'repeatCount': 1,
                    'steps': [
                      {
                        'kind': 'cool_down',
                        'endCondition': 'lap.button',
                        'endValue': 999,
                        'targetKind': 'unknown_target',
                      },
                    ],
                  },
                ],
              },
            ],
          },
        ],
      };

      final parsed = TrainingPlan.fromJson(rawJson);
      expect(parsed.id, '42');
      expect(parsed.config.weeklyHoursBudget, 12.5);
      expect(parsed.config.zones.maxHr, 188);
      expect(parsed.config.zones.bikeFtpWatts, 265);
      expect(parsed.weeks.single.weekNumber, 2);
      expect(parsed.weeks.single.startDate, '2026-11-23');

      final w = parsed.allWorkouts.single;
      expect(w.date, '2026-11-24');
      expect(w.discipline, SportDiscipline.run);
      expect(w.archetype, WorkoutArchetype.threshold);
      expect(w.status, WorkoutStatus.scheduled);
      expect(w.adherencePercent, 100.0);

      // Repeat block promoted single step to steps list
      expect(w.blocks[0].isRepeat, isTrue);
      expect(w.blocks[0].step, isNull);
      expect(w.blocks[0].steps.length, 1);
      expect(w.blocks[0].steps.first.kind, StepKind.warmup);
      expect(w.blocks[0].steps.first.endValue, 0.0);
      expect(w.blocks[0].steps.first.targetKind, StepTargetKind.paceMps);
      expect(w.blocks[0].steps.first.targetLow, 3.8);
      expect(w.blocks[0].steps.first.targetHigh, 4.2);

      // Single-step repeatCount=1 block normalized into step
      expect(w.blocks[1].isRepeat, isFalse);
      expect(w.blocks[1].step?.kind, StepKind.cooldown);
      expect(w.blocks[1].step?.endCondition, StepEndCondition.lapButton);
      expect(w.blocks[1].step?.endValue, isNull);
      expect(w.blocks[1].step?.targetKind, StepTargetKind.none);
    });

    test('brickRunLeg enforces <= 30 min & SportDiscipline.run in ctor, fromJson, copyWith', () {
      // Constructor enforcement
      final constructed = PlannedWorkout(
        id: 'brick_ctor',
        date: '2026-11-21',
        title: 'Brick',
        discipline: SportDiscipline.bike,
        archetype: WorkoutArchetype.brick,
        estimatedDurationMinutes: 90,
        brickRunLeg: PlannedWorkout(
          id: '',
          date: '',
          title: 'Too Long Swim Leg',
          discipline: SportDiscipline.swim,
          archetype: WorkoutArchetype.easy,
          estimatedDurationMinutes: 55,
        ),
      );
      expect(constructed.brickRunLeg!.estimatedDurationMinutes, 30);
      expect(constructed.brickRunLeg!.discipline, SportDiscipline.run);
      expect(constructed.brickRunLeg!.id, 'brick_ctor_run');
      expect(constructed.brickRunLeg!.date, '2026-11-21');

      // fromJson enforcement
      final fromJson = PlannedWorkout.fromJson({
        'id': 'brick_json',
        'date': '2026-11-22',
        'title': 'Brick JSON',
        'discipline': 'bike',
        'archetype': 'brick',
        'estimatedDurationMinutes': 75,
        'brickRunLeg': {
          'id': 'leg_1',
          'date': '2026-11-22',
          'title': 'Overlong Leg',
          'discipline': 'indoorBike',
          'archetype': 'threshold',
          'estimatedDurationMinutes': 45,
        },
      });
      expect(fromJson.brickRunLeg!.estimatedDurationMinutes, 30);
      expect(fromJson.brickRunLeg!.discipline, SportDiscipline.run);

      // copyWith enforcement
      final copied = fromJson.copyWith(
        brickRunLeg: PlannedWorkout(
          id: 'leg_2',
          date: '2026-11-22',
          title: 'Copied Overlong',
          discipline: SportDiscipline.strength,
          archetype: WorkoutArchetype.intervals,
          estimatedDurationMinutes: 60,
        ),
      );
      expect(copied.brickRunLeg!.estimatedDurationMinutes, 30);
      expect(copied.brickRunLeg!.discipline, SportDiscipline.run);

      // Nullable clearing via copyWith
      final clearedZones = const AthleteZonesSnapshot(
        runThresholdPaceSecPerKm: 250,
        swimCssSecPer100m: 100,
        bikeFtpWatts: 280,
      ).copyWith(
        clearRunThresholdPace: true,
        clearSwimCss: true,
        clearBikeFtp: true,
      );
      expect(clearedZones.runThresholdPaceSecPerKm, isNull);
      expect(clearedZones.swimCssSecPer100m, isNull);
      expect(clearedZones.bikeFtpWatts, isNull);
    });

    test('coexists cleanly with legacy ScheduledWorkout', () {
      const legacy = legacy_block.ScheduledWorkout(
        id: 'legacy_1',
        title: 'Legacy Run',
        discipline: SportDiscipline.run,
        durationText: '45m',
        tss: 50,
        prescription: 'Easy Z2',
        isCompleted: false,
        adherencePercent: 0,
        dayOfWeek: 'Tue',
        dateText: 'Nov 17',
      );
      final planned = PlannedWorkout(
        id: 'planned_1',
        date: '2026-11-17',
        title: 'Planned Run',
        discipline: SportDiscipline.run,
        archetype: WorkoutArchetype.easy,
        estimatedDurationMinutes: 45,
      );
      expect(legacy.title, 'Legacy Run');
      expect(planned.title, 'Planned Run');
    });

    test('brickRunLeg date syncs on copyWith, ctor, and fromJson; empty parentId avoids _run', () {
      final baseBrick = PlannedWorkout(
        id: 'brick_sync',
        date: '2026-11-21',
        title: 'Sat Brick',
        discipline: SportDiscipline.bike,
        archetype: WorkoutArchetype.brick,
        estimatedDurationMinutes: 80,
        zwiftPrescription: const ZwiftPrescription(
          durationMinutes: 60,
          difficulty: 'Tempo',
          targetTss: 60,
          zwiftCategory: 'Tempo',
        ),
        brickRunLeg: PlannedWorkout(
          id: 'brick_sync_run',
          date: '2026-11-19', // intentionally mismatched in ctor
          title: 'T2 Run',
          discipline: SportDiscipline.run,
          archetype: WorkoutArchetype.easy,
          estimatedDurationMinutes: 20,
        ),
      );
      expect(baseBrick.brickRunLeg!.date, '2026-11-21');

      // Reschedule via copyWith(date: ...) updates brickRunLeg.date and matches run activity
      final rescheduled = baseBrick.copyWith(date: '2026-11-28');
      expect(rescheduled.date, '2026-11-28');
      expect(rescheduled.brickRunLeg!.date, '2026-11-28');

      final plan = _samplePlan(
        weeks: [
          TrainingWeek(
            weekNumber: 2,
            startDate: '2026-11-23',
            phaseName: 'Build',
            focusSummary: '',
            targetHours: 2.0,
            targetTss: 100,
            workouts: [rescheduled],
          ),
        ],
      );
      final runActOnNewDate = _makeActivity(
        id: 'run_nov28',
        discipline: SportDiscipline.run,
        timestamp: DateTime(2026, 11, 28, 9, 30),
        durationSeconds: 20 * 60.0,
      );
      final matched =
          WorkoutComplianceMatcher.matchPlan(plan, [runActOnNewDate]);
      expect(
        matched.allWorkouts.single.brickRunLeg!.status,
        WorkoutStatus.completed,
      );
      expect(
        matched.allWorkouts.single.brickRunLeg!.matchedActivityId,
        'run_nov28',
      );

      // Mismatched brickRunLeg.date in JSON is overwritten with parent date
      final fromMismatchedJson = PlannedWorkout.fromJson({
        'id': 'brick_j',
        'date': '2026-12-05',
        'title': 'JSON Brick',
        'discipline': 'bike',
        'archetype': 'brick',
        'estimatedDurationMinutes': 75,
        'brickRunLeg': {
          'id': '',
          'date': '2026-11-01',
          'title': '   ',
          'discipline': 'run',
          'archetype': 'easy',
          'estimatedDurationMinutes': 15,
        },
      });
      expect(fromMismatchedJson.brickRunLeg!.date, '2026-12-05');
      expect(fromMismatchedJson.brickRunLeg!.id, 'brick_j_run');
      expect(fromMismatchedJson.brickRunLeg!.title, 'Brick Transition Run');

      // Empty parentId does not produce '_run'
      final emptyParentIdBrick = PlannedWorkout(
        id: '   ',
        date: '2026-12-06',
        title: 'Brick',
        discipline: SportDiscipline.bike,
        archetype: WorkoutArchetype.brick,
        estimatedDurationMinutes: 60,
        brickRunLeg: PlannedWorkout(
          id: '',
          date: '',
          title: '',
          discipline: SportDiscipline.run,
          archetype: WorkoutArchetype.easy,
          estimatedDurationMinutes: 15,
        ),
      );
      expect(emptyParentIdBrick.brickRunLeg!.id, 'brick_run');
      expect(emptyParentIdBrick.brickRunLeg!.title, 'Brick Transition Run');
    });

    test('empty/whitespace IDs and required labels fall back while optional empty text is preserved', () {
      final parsedPlan = TrainingPlan.fromJson({
        'id': '   ',
        'name': '',
        'coachOverview': '',
        'config': {
          'raceName': '  ',
          'raceDistance': '',
          'longRunDay': '   ',
          'longRideDay': '',
          'restDay': '\t',
          'limiterSport': '',
          'zones': {
            'hrZones': [
              {'zone': 1, 'label': '   ', 'lowBpm': 100, 'highBpm': 130},
            ],
          },
        },
        'weeks': [
          {
            'weekNumber': 1,
            'startDate': '2026-11-16',
            'phaseName': '   ',
            'focusSummary': '',
            'workouts': [
              {
                'id': ' ',
                'date': '2026-11-17',
                'title': '  ',
                'archetype': 'zwiftRide',
                'zwiftPrescription': {
                  'difficulty': '',
                  'zwiftCategory': '   ',
                },
              },
            ],
          },
        ],
      });

      expect(parsedPlan.id, isNotEmpty);
      expect(parsedPlan.name, 'Triathlon Training Plan');
      expect(parsedPlan.coachOverview, '');
      expect(parsedPlan.config.raceName, 'Target Race');
      expect(parsedPlan.config.raceDistance, '70.3');
      expect(parsedPlan.config.longRunDay, 'Sunday');
      expect(parsedPlan.config.longRideDay, 'Saturday');
      expect(parsedPlan.config.restDay, 'Friday');
      expect(parsedPlan.config.limiterSport, 'Swim');
      expect(parsedPlan.config.zones.hrZones.single.label, 'Zone');
      expect(parsedPlan.weeks.single.phaseName, 'Base');
      expect(parsedPlan.weeks.single.focusSummary, '');
      expect(parsedPlan.allWorkouts.single.id, 'w1_d1');
      expect(parsedPlan.allWorkouts.single.title, 'Workout');
      expect(
        parsedPlan.allWorkouts.single.zwiftPrescription!.difficulty,
        'Endurance',
      );
      expect(
        parsedPlan.allWorkouts.single.zwiftPrescription!.zwiftCategory,
        'Endurance',
      );

      final standaloneWorkout = PlannedWorkout.fromJson({'id': '  ', 'title': ''});
      expect(standaloneWorkout.id, isNotEmpty);
      expect(standaloneWorkout.title, 'Workout');

      final msg = CoachMessage.fromJson({'id': '   ', 'content': ''});
      expect(msg.id, isNotEmpty);
      expect(msg.content, '');
    });

    test('WorkoutStep.fromJson clears targets for none & nulls negative bounds; toJson handles non-finite doubles', () {
      final noneWithTargets = WorkoutStep.fromJson({
        'kind': 'steady',
        'endCondition': 'time',
        'endValue': 300,
        'targetKind': 'none',
        'targetLow': 120,
        'targetHigh': 150,
      });
      expect(noneWithTargets.targetLow, isNull);
      expect(noneWithTargets.targetHigh, isNull);

      final oneNegative = WorkoutStep.fromJson({
        'kind': 'interval',
        'endCondition': 'time',
        'endValue': 120,
        'targetKind': 'heartRateBpm',
        'targetLow': 160,
        'targetHigh': -5,
      });
      expect(oneNegative.targetLow, 160.0);
      expect(oneNegative.targetHigh, isNull);

      final bothNegative = WorkoutStep.fromJson({
        'kind': 'interval',
        'endCondition': 'time',
        'endValue': 120,
        'targetKind': 'paceMps',
        'targetLow': -2.0,
        'targetHigh': -5.0,
      });
      expect(bothNegative.targetLow, isNull);
      expect(bothNegative.targetHigh, isNull);

      // Dart-constructed models with non-finite doubles must serialize cleanly
      final dirtyPlan = TrainingPlan(
        id: 'nan_plan',
        name: 'Non-finite Test',
        createdAt: DateTime.utc(2026, 11, 20),
        updatedAt: DateTime.utc(2026, 11, 20),
        coachOverview: '',
        config: const TrainingPlanConfig(
          raceName: 'Race',
          raceDistance: '70.3',
          raceDate: '2027-04-03',
          weeklyHoursBudget: double.nan,
          longRunDay: 'Sunday',
          longRideDay: 'Saturday',
          restDay: 'Friday',
          limiterSport: 'Swim',
          zones: AthleteZonesSnapshot(
            runThresholdPaceSecPerKm: double.infinity,
            swimCssSecPer100m: double.negativeInfinity,
          ),
        ),
        weeks: [
          TrainingWeek(
            weekNumber: 1,
            startDate: '2026-11-16',
            phaseName: 'Base',
            focusSummary: '',
            targetHours: double.infinity,
            targetTss: 100,
            workouts: [
              PlannedWorkout(
                id: 'dirty_w1',
                date: '2026-11-17',
                title: 'Dirty Run',
                discipline: SportDiscipline.run,
                archetype: WorkoutArchetype.easy,
                estimatedDurationMinutes: 40,
                estimatedDistanceKm: double.nan,
                estimatedTss: double.infinity,
                adherencePercent: double.nan,
                blocks: const [
                  WorkoutBlock(
                    step: WorkoutStep(
                      kind: StepKind.steady,
                      endCondition: StepEndCondition.time,
                      endValue: double.infinity,
                      targetKind: StepTargetKind.paceMps,
                      targetLow: double.nan,
                      targetHigh: double.negativeInfinity,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      );

      final encoded = jsonEncode(dirtyPlan.toJson());
      final decoded = TrainingPlan.fromJson(
        jsonDecode(encoded) as Map<String, dynamic>,
      );
      expect(decoded.config.weeklyHoursBudget, 8.0);
      expect(decoded.config.zones.runThresholdPaceSecPerKm, isNull);
      expect(decoded.config.zones.swimCssSecPer100m, isNull);
      expect(decoded.weeks.single.targetHours, 0.0);
      final dw = decoded.allWorkouts.single;
      expect(dw.estimatedDistanceKm, isNull);
      expect(dw.estimatedTss, isNull);
      expect(dw.adherencePercent, isNull);
      expect(dw.blocks.single.step!.endValue, isNull);
      expect(dw.blocks.single.step!.targetLow, isNull);
      expect(dw.blocks.single.step!.targetHigh, isNull);
    });

    test('brickRunLeg sanitizes strength archetype, bounds integer saturation, and validates calendar dates', () {
      // 1. brickRunLeg strength archetype -> easy so isGarminPushable stays consistent
      final brickFromJson = PlannedWorkout.fromJson({
        'id': 'b_str',
        'date': '2026-11-21',
        'title': 'Brick Strength Leg',
        'discipline': 'bike',
        'archetype': 'brick',
        'estimatedDurationMinutes': 75,
        'brickRunLeg': {
          'id': 'b_str_run',
          'archetype': 'strength',
          'estimatedDurationMinutes': 20,
        },
      });
      expect(brickFromJson.isGarminPushable, isTrue);
      expect(brickFromJson.brickRunLeg!.archetype, WorkoutArchetype.easy);
      expect(brickFromJson.brickRunLeg!.discipline, SportDiscipline.run);
      expect(brickFromJson.brickRunLeg!.isGarminPushable, isTrue);

      final brickCtor = PlannedWorkout(
        id: 'b_ctor_iso',
        date: '2026-11-21T15:00:00Z',
        title: 'Brick Ctor ISO',
        discipline: SportDiscipline.bike,
        archetype: WorkoutArchetype.brick,
        estimatedDurationMinutes: 90,
        brickRunLeg: PlannedWorkout(
          id: '',
          date: '2026-10-01',
          title: 'Strength Leg',
          discipline: SportDiscipline.strength,
          archetype: WorkoutArchetype.strength,
          estimatedDurationMinutes: 25,
        ),
      );
      expect(brickCtor.date, '2026-11-21');
      expect(brickCtor.brickRunLeg!.date, '2026-11-21');
      expect(brickCtor.brickRunLeg!.archetype, WorkoutArchetype.easy);
      expect(brickCtor.brickRunLeg!.isGarminPushable, isTrue);

      // 2. Integer bounds clamping against 1e308 / -1e308 saturation
      final saturatedPlan = TrainingPlan.fromJson({
        'config': {
          'zones': {
            'bikeFtpWatts': '1e308',
            'hrZones': [
              {'zone': 1, 'label': 'Neg', 'lowBpm': -20, 'highBpm': -5},
              {'zone': 2, 'label': 'SwappedSat', 'lowBpm': 1e308, 'highBpm': 150},
              {'zone': 3, 'label': 'BothSat', 'lowBpm': '-1e308', 'highBpm': '1e308'},
            ],
          },
        },
        'weeks': [
          {
            'weekNumber': 1,
            'startDate': '2026-11-16',
            'targetTss': 1e308,
            'workouts': [
              {
                'id': 'sat_w',
                'date': '2026-11-17',
                'estimatedDurationMinutes': '1e308',
                'blocks': [
                  {
                    'repeatCount': '1e308',
                    'step': {'kind': 'interval', 'endCondition': 'time', 'endValue': 60},
                  },
                ],
              },
              {
                'id': 'neg_w',
                'date': '2026-11-18',
                'estimatedDurationMinutes': '-1e308',
                'blocks': [
                  {
                    'repeatCount': '-1e308',
                    'step': {'kind': 'steady', 'endCondition': 'time', 'endValue': 60},
                  },
                ],
              },
            ],
          },
          {
            'weekNumber': 2,
            'startDate': '2026-11-23',
            'targetTss': '-1e308',
            'workouts': [],
          },
        ],
      });
      expect(saturatedPlan.config.zones.bikeFtpWatts, 1000);
      expect(saturatedPlan.config.zones.hrZones[0].lowBpm, 0);
      expect(saturatedPlan.config.zones.hrZones[0].highBpm, 0);
      expect(saturatedPlan.config.zones.hrZones[1].lowBpm, 150);
      expect(saturatedPlan.config.zones.hrZones[1].highBpm, 250);
      expect(saturatedPlan.config.zones.hrZones[2].lowBpm, 0);
      expect(saturatedPlan.config.zones.hrZones[2].highBpm, 250);
      expect(saturatedPlan.weeks[0].targetTss, 5000);
      expect(saturatedPlan.weeks[1].targetTss, 0);
      expect(saturatedPlan.weeks[0].workouts[0].estimatedDurationMinutes, 1440);
      expect(saturatedPlan.weeks[0].workouts[0].blocks.single.repeatCount, 100);
      expect(saturatedPlan.weeks[0].workouts[1].estimatedDurationMinutes, 0);
      expect(saturatedPlan.weeks[0].workouts[1].blocks.single.repeatCount, 1);

      final lowFtpZones = AthleteZonesSnapshot.fromJson({'bikeFtpWatts': 10});
      expect(lowFtpZones.bikeFtpWatts, 20);
      final negFtpZones = AthleteZonesSnapshot.fromJson({'bikeFtpWatts': '-1e308'});
      expect(negFtpZones.bikeFtpWatts, isNull);

      // 3. Calendar date validation & trailing boundary checks
      final feb30 = PlannedWorkout.fromJson({'id': 'd1', 'date': '2026-02-30'});
      expect(feb30.date, '');
      expect(feb30.scheduledDate, isNull);

      final month13 = PlannedWorkout.fromJson({'id': 'd2', 'date': '2026-13-01'});
      expect(month13.date, '');
      expect(month13.scheduledDate, isNull);

      final trailingDigits = PlannedWorkout.fromJson({'id': 'd3', 'date': '2026-11-21999'});
      expect(trailingDigits.date, '');
      expect(trailingDigits.scheduledDate, isNull);

      final leapYear = PlannedWorkout.fromJson({'id': 'd4', 'date': '2024-02-29T12:00:00Z'});
      expect(leapYear.date, '2024-02-29');
      expect(leapYear.scheduledDate, DateTime(2024, 2, 29));
    });
  });

  group('Group 2 — AthleteContextBuilder', () {
    test('derives HR zones, Run Threshold Pace, Swim CSS, and Bike FTP from activities', () {
      final now = DateTime(2026, 11, 20, 10, 0);
      final activities = [
        // 3 runs for MaxHR glitch guard (218 spike vs 192/190 real) & Run Threshold
        _makeActivity(
          id: 'r1',
          discipline: SportDiscipline.run,
          timestamp: now.subtract(const Duration(days: 5)),
          distanceKm: 10.0,
          durationSeconds: 2500, // 250 s/km (4:10/km)
          avgHr: 173,
          maxHr: 192,
        ),
        _makeActivity(
          id: 'r2',
          discipline: SportDiscipline.run,
          timestamp: now.subtract(const Duration(days: 12)),
          distanceKm: 8.0,
          durationSeconds: 2400,
          avgHr: 150,
          maxHr: 190,
        ),
        _makeActivity(
          id: 'r3_glitch',
          discipline: SportDiscipline.run,
          timestamp: now.subtract(const Duration(days: 20)),
          distanceKm: 5.0,
          durationSeconds: 1500,
          avgHr: 145,
          maxHr: 218, // optical HR glitch (>20 bpm above 192)
        ),
        // Swim for CSS
        _makeActivity(
          id: 's1',
          discipline: SportDiscipline.swim,
          timestamp: now.subtract(const Duration(days: 4)),
          distanceKm: 1.0, // 1000m
          durationSeconds: 1050, // 105s/100m
          avgHr: 148,
          maxHr: 165,
        ),
        // Indoor ride with normPowerW + intensityFactor (profile.ftpWatts is null)
        _makeActivity(
          id: 'b1',
          discipline: SportDiscipline.indoorBike,
          timestamp: now.subtract(const Duration(days: 3)),
          distanceKm: 35.0,
          durationSeconds: 3600,
          avgPowerW: 230,
          normPowerW: 240,
          intensityFactor: 0.80, // implies 300W FTP
        ),
      ];

      const profile = AthletePhysiologicalProfile(
        ctlFitness: 62.5,
        atlFatigue: 71.0,
        tsbForm: -8.5,
        acwrRatio: 1.14,
        acwrStatus: 'Optimal',
        restingHr: 48,
        hrvMs: 74,
        vo2MaxEst: 57.5,
        ftpWatts: null,
      );

      final ctx = AthleteContextBuilder.build(
        activities: activities,
        profile: profile,
        pmcSeries: const [],
        activePlan: _samplePlan(),
        now: now,
      );

      // Glitch guard ignores 218 and picks 192
      expect(ctx.zones.maxHr, 192);
      // 10k in 2500s (2100 < 2500 <= 3600) -> LTHR = 173
      expect(ctx.zones.lthr, 173);
      expect(ctx.zones.hrZones.length, 5);
      for (var i = 0; i < 4; i++) {
        expect(
          ctx.zones.hrZones[i].highBpm,
          lessThan(ctx.zones.hrZones[i + 1].lowBpm),
        );
      }
      expect(ctx.zones.runThresholdPaceSecPerKm, isNotNull);
      expect(ctx.zones.runThresholdPaceSecPerKm!, closeTo(252.7, 0.5));
      expect(ctx.zones.swimCssSecPer100m, closeTo(105.0, 0.1));
      expect(ctx.zones.swimCssSecPer100yd!, closeTo(105.0 / 1.09361, 0.1));
      expect(ctx.zones.bikeFtpWatts, 300);

      expect(ctx.avgWeeklyHours4w, greaterThan(0));
      expect(ctx.avgWeeklyHours12w, greaterThan(0));
      expect(ctx.longestRecentRun?.distanceKm, 10.0);
      expect(ctx.longestRecentBike?.distanceKm, 35.0);
      expect(ctx.longestRecentSwim?.distanceKm, 1.0);
      expect(ctx.adherenceSummary, isNotNull);
      expect(ctx.adherenceSummary!.totalDue, 3); // 17, 18, 19 (20 is rest)

      final promptMetric = ctx.toPromptPayload();
      expect(promptMetric, contains('CTL 62.5'));
      expect(promptMetric, contains('ATL 71.0'));
      expect(promptMetric, contains('TSB -8.5'));
      expect(promptMetric, contains('ACWR 1.14 (Optimal)'));
      expect(promptMetric, contains('Bike FTP: 300 W'));
      expect(promptMetric, contains('Weekly Volume (4w avg vs 12w avg)'));
      expect(promptMetric, contains('Longest Recent (180d)'));
      expect(promptMetric, contains('Current Plan Adherence'));
      expect(promptMetric, isNot(contains('NaN')));
      expect(promptMetric, isNot(contains('Infinity')));

      final promptImperial = ctx.toPromptPayload(
        unitSystem: UnitSystem.imperial,
      );
      expect(promptImperial, contains('/mi'));
      expect(promptImperial, contains('/100yd'));
    });

    test('falls back to ergSteps or profile.ftpWatts and handles empty history safely', () {
      final now = DateTime(2026, 11, 20, 10, 0);

      final emptyCtx = AthleteContextBuilder.build(
        activities: const [],
        profile: const AthletePhysiologicalProfile(),
        pmcSeries: [
          PmcDataPoint(
            date: DateTime(2026, 11, 19),
            ctl: 40.0,
            atl: 44.0,
            tsb: -4.0,
            dailyTss: 50.0,
          ),
        ],
        now: now,
      );
      expect(emptyCtx.zones.maxHr, 190);
      expect(emptyCtx.zones.hrZones.length, 5);
      expect(emptyCtx.zones.runThresholdPaceSecPerKm, isNull);
      expect(emptyCtx.zones.swimCssSecPer100m, isNull);
      expect(emptyCtx.zones.bikeFtpWatts, isNull);
      expect(emptyCtx.ctl, 40.0);
      expect(emptyCtx.acwr, closeTo(1.1, 0.01));
      final payload = emptyCtx.toPromptPayload(useImperial: true);
      expect(payload, isNot(contains('NaN')));
      expect(payload, isNot(contains('Infinity')));
      expect(payload, contains('Bike FTP: Not available'));

      final ergOnlyZones = AthleteContextBuilder.deriveZones(
        activities: [
          _makeActivity(
            id: 'erg_ride',
            discipline: SportDiscipline.indoorBike,
            timestamp: now.subtract(const Duration(days: 2)),
            durationSeconds: 3000, // 50 min -> * 0.98
            ergSteps: const [
              ErgStep(
                step: 1,
                name: 'Steady',
                duration: '50:00',
                targetWatts: 250,
                actualWatts: 250,
                deltaWatts: 0,
                avgCadence: 90,
                avgHr: 155,
                adherencePercent: 100,
              ),
            ],
          ),
        ],
        profile: const AthletePhysiologicalProfile(ftpWatts: 200),
        now: now,
      );
      expect(ergOnlyZones.bikeFtpWatts, 245); // derived from ergSteps first

      final profileFallbackZones = AthleteContextBuilder.deriveZones(
        activities: const [],
        profile: const AthletePhysiologicalProfile(ftpWatts: 260),
        now: now,
      );
      expect(profileFallbackZones.bikeFtpWatts, 260);
    });

    test('handles pathological duration strings, extreme ACWR/TSB, restingHr >= lthr, >180d fallback, and non-finite telemetry', () {
      final now = DateTime(2026, 11, 20, 10, 0);
      final badDurations = [
        'Infinity:00',
        'NaN:00',
        '1e309:00',
        '1e308:00',
        '${'9' * 310}h',
        '-5:00',
      ];

      for (final bad in badDurations) {
        final ctx = AthleteContextBuilder.build(
          activities: [
            _makeActivity(
              id: 'bad_bike_$bad',
              discipline: SportDiscipline.bike,
              timestamp: now.subtract(const Duration(days: 2)),
              durationSeconds: 0,
              movingTime: bad,
              elapsedTime: bad,
              splits: [
                ActivitySplit(
                  splitNumber: 1,
                  label: 'Lap 1',
                  time: bad,
                  distanceKm: 10.0,
                  paceOrSpeed: '30 km/h',
                  avgHr: 150,
                  avgPower: 250,
                ),
              ],
            ),
            // Also include a valid 20-min ride with pathological split.time so _deriveBikeFtp executes weighted split math
            _makeActivity(
              id: 'split_bike_$bad',
              discipline: SportDiscipline.bike,
              timestamp: now.subtract(const Duration(days: 1)),
              durationSeconds: 1800,
              splits: [
                ActivitySplit(
                  splitNumber: 1,
                  label: 'Split 1',
                  time: bad,
                  distanceKm: 12.0,
                  paceOrSpeed: '30 km/h',
                  avgHr: 155,
                  avgPower: 250,
                ),
              ],
            ),
          ],
          profile: const AthletePhysiologicalProfile(ftpWatts: 220),
          pmcSeries: const [],
          now: now,
        );

        expect(ctx.avgWeeklyHours4w, isNot(isNaN));
        expect(ctx.avgWeeklyHours4w.isFinite, isTrue);
        expect(ctx.avgWeeklyHours12w.isFinite, isTrue);
        // Only the 1800s activity contributes to volume -> 0.5h / 4w = 0.13h
        expect(ctx.avgWeeklyHours4w, closeTo(0.13, 0.01));
        expect(ctx.zones.bikeFtpWatts, isNotNull);
        final payload = ctx.toPromptPayload();
        expect(payload, isNot(contains('Infinity')));
        expect(payload, isNot(contains('NaN')));
      }

      // movingTime: 'Infinity:00' alone with no valid activities yields 0.0 volume
      final infOnlyCtx = AthleteContextBuilder.build(
        activities: [
          _makeActivity(
            id: 'inf_only',
            discipline: SportDiscipline.run,
            timestamp: now.subtract(const Duration(days: 1)),
            durationSeconds: 0,
            movingTime: 'Infinity:00',
            elapsedTime: 'NaN:00',
          ),
        ],
        profile: const AthletePhysiologicalProfile(),
        pmcSeries: const [],
        now: now,
      );
      expect(infOnlyCtx.avgWeeklyHours4w, 0.0);
      expect(infOnlyCtx.avgWeeklyHours12w, 0.0);
      expect(infOnlyCtx.toPromptPayload(), isNot(contains('Infinity')));
      expect(infOnlyCtx.toPromptPayload(), isNot(contains('NaN')));

      // Extreme ACWR and TSB overflow cases
      for (final profile in const [
        AthletePhysiologicalProfile(ctlFitness: 0.6, atlFatigue: 1e308),
        AthletePhysiologicalProfile(ctlFitness: 0.55, atlFatigue: 1e308),
        AthletePhysiologicalProfile(ctlFitness: 1e308, atlFatigue: -1e308),
      ]) {
        final ctx = AthleteContextBuilder.build(
          activities: const [],
          profile: profile,
          pmcSeries: const [],
          now: now,
        );
        expect(ctx.acwr, isNull);
        if (profile.ctlFitness == 1e308 && profile.atlFatigue == -1e308) {
          expect(ctx.tsb, isNull);
        }
        final payload = ctx.toPromptPayload();
        expect(payload, isNot(contains('Infinity')));
        expect(payload, isNot(contains('NaN')));
      }

      // restingHr >= lthr and low maxHr -> strictly contiguous non-inverted 5 HR zones
      final weirdHrZones = AthleteContextBuilder.deriveZones(
        activities: [
          _makeActivity(
            id: 'hr_low',
            discipline: SportDiscipline.run,
            timestamp: now.subtract(const Duration(days: 3)),
            durationSeconds: 2400,
            avgHr: 150,
            maxHr: 185,
          ),
        ],
        profile: const AthletePhysiologicalProfile(restingHr: 190),
        now: now,
      );
      expect(weirdHrZones.hrZones.length, 5);
      for (var i = 0; i < 5; i++) {
        expect(
          weirdHrZones.hrZones[i].lowBpm,
          lessThan(weirdHrZones.hrZones[i].highBpm),
        );
        if (i < 4) {
          expect(
            weirdHrZones.hrZones[i].highBpm,
            lessThan(weirdHrZones.hrZones[i + 1].lowBpm),
          );
        }
      }

      // Pathological Activity numeric fields (0, negative, NaN, Infinity, 1000 km/h, 1e308 swim distance)
      final pathologicalCtx = AthleteContextBuilder.build(
        activities: [
          _makeActivity(
            id: 'run_nan',
            discipline: SportDiscipline.run,
            timestamp: now.subtract(const Duration(days: 2)),
            distanceKm: double.nan,
            durationSeconds: double.infinity,
          ),
          _makeActivity(
            id: 'run_neg',
            discipline: SportDiscipline.run,
            timestamp: now.subtract(const Duration(days: 3)),
            distanceKm: -5.0,
            durationSeconds: -1200,
          ),
          _makeActivity(
            id: 'run_supersonic',
            discipline: SportDiscipline.run,
            timestamp: now.subtract(const Duration(days: 4)),
            distanceKm: 100.0,
            durationSeconds: 360, // 1000 km/h -> 3.6 s/km (<150 s/km guard)
          ),
          _makeActivity(
            id: 'swim_huge',
            discipline: SportDiscipline.swim,
            timestamp: now.subtract(const Duration(days: 5)),
            distanceKm: 1e308,
            durationSeconds: 1800,
          ),
        ],
        profile: const AthletePhysiologicalProfile(),
        pmcSeries: const [],
        now: now,
      );
      expect(pathologicalCtx.zones.runThresholdPaceSecPerKm, isNull);
      expect(pathologicalCtx.zones.swimCssSecPer100m, isNull);
      expect(pathologicalCtx.toPromptPayload(), isNot(contains('Infinity')));
      expect(pathologicalCtx.toPromptPayload(), isNot(contains('NaN')));

      // >180d fallback: recent volume is 0.0 while zones & longestRecent* still derive
      final oldCtx = AthleteContextBuilder.build(
        activities: [
          _makeActivity(
            id: 'old_run',
            discipline: SportDiscipline.run,
            timestamp: now.subtract(const Duration(days: 220)),
            distanceKm: 12.0,
            durationSeconds: 3000, // 250 s/km
            avgHr: 170,
            maxHr: 189,
          ),
        ],
        profile: const AthletePhysiologicalProfile(),
        pmcSeries: const [],
        now: now,
      );
      expect(oldCtx.avgWeeklyHours4w, 0.0);
      expect(oldCtx.avgWeeklyHours12w, 0.0);
      expect(oldCtx.zones.maxHr, 189);
      expect(oldCtx.zones.runThresholdPaceSecPerKm, isNotNull);
      expect(oldCtx.longestRecentRun?.distanceKm, 12.0);
    });

    test('bounds extreme ctl/atl/tsb/vo2MaxEst (profile and pmcSeries) and rejects scientific-notation durations', () {
      final now = DateTime(2026, 11, 20, 10, 0);
      final scientificExpRegex = RegExp(r'\d(?:e[+-]\d+)', caseSensitive: false);

      // Profile with 1e308 atlFatigue & vo2MaxEst -> bounded to null, zero scientific notation in prompt
      final extremeProfileCtx = AthleteContextBuilder.build(
        activities: const [],
        profile: const AthletePhysiologicalProfile(
          ctlFitness: 0.6,
          atlFatigue: 1e308,
          vo2MaxEst: 1e308,
        ),
        pmcSeries: const [],
        now: now,
      );
      expect(extremeProfileCtx.ctl, 0.6);
      expect(extremeProfileCtx.atl, isNull);
      expect(extremeProfileCtx.tsb, isNull);
      expect(extremeProfileCtx.acwr, isNull);
      expect(extremeProfileCtx.vo2MaxEst, isNull);
      final extremePrompt = extremeProfileCtx.toPromptPayload();
      expect(extremePrompt, contains('CTL 0.6'));
      expect(extremePrompt, isNot(contains('ATL')));
      expect(extremePrompt, isNot(contains('TSB')));
      expect(extremePrompt, isNot(contains('VO2max')));
      expect(scientificExpRegex.hasMatch(extremePrompt), isFalse);

      // Extreme pmcSeries fallback values are also rejected cleanly
      final extremePmcCtx = AthleteContextBuilder.build(
        activities: const [],
        profile: const AthletePhysiologicalProfile(),
        pmcSeries: [
          PmcDataPoint(
            date: now.subtract(const Duration(days: 1)),
            ctl: 1e308,
            atl: 1e308,
            tsb: -1e308,
            dailyTss: 0.0,
          ),
        ],
        now: now,
      );
      expect(extremePmcCtx.ctl, isNull);
      expect(extremePmcCtx.atl, isNull);
      expect(extremePmcCtx.tsb, isNull);
      expect(extremePmcCtx.acwr, isNull);
      final extremePmcPrompt = extremePmcCtx.toPromptPayload();
      expect(extremePmcPrompt, contains('No load/readiness metrics available yet'));
      expect(scientificExpRegex.hasMatch(extremePmcPrompt), isFalse);

      // Scientific-notation & over-cap duration strings rejected cleanly -> finite hours & bikeFtpWatts == 238
      for (final sciDur in const ['1e306:00', '1E5:30', '999999999:00', '999999999999h']) {
        final sciCtx = AthleteContextBuilder.build(
          activities: [
            _makeActivity(
              id: 'sci_run_$sciDur',
              discipline: SportDiscipline.run,
              timestamp: now.subtract(const Duration(days: 2)),
              durationSeconds: 0,
              movingTime: sciDur,
              elapsedTime: sciDur,
            ),
            _makeActivity(
              id: 'sci_bike_$sciDur',
              discipline: SportDiscipline.bike,
              timestamp: now.subtract(const Duration(days: 1)),
              durationSeconds: 1800,
              splits: [
                ActivitySplit(
                  splitNumber: 1,
                  label: 'Lap 1',
                  time: sciDur,
                  distanceKm: 12.0,
                  paceOrSpeed: '30 km/h',
                  avgHr: 155,
                  avgPower: 250,
                ),
              ],
            ),
          ],
          profile: const AthletePhysiologicalProfile(),
          pmcSeries: const [],
          now: now,
        );

        expect(sciCtx.avgWeeklyHours4w, closeTo(0.13, 0.01));
        expect(sciCtx.avgWeeklyHours12w, closeTo(0.04, 0.01));
        expect(sciCtx.zones.bikeFtpWatts, 238);
        for (final p in [
          sciCtx.toPromptPayload(),
          sciCtx.toPromptPayload(unitSystem: UnitSystem.imperial),
        ]) {
          expect(p, isNot(contains('Infinity')));
          expect(p, isNot(contains('NaN')));
          expect(scientificExpRegex.hasMatch(p), isFalse);
        }
      }
    });

    test('rejects partial unit-regex tokens, caps Activity.durationSeconds, and bounds direct AthleteContext prompt fields', () {
      final now = DateTime(2026, 11, 20, 10, 0);
      final scientificExpRegex = RegExp(r'\d(?:e[+-]\d+)', caseSensitive: false);

      // 1. Partial unit-regex strings ('1e7h', '1e306h', '-5h', '-30m') rejected, valid unit strings preserved
      for (final badUnit in const ['1e7h', '1e306h', '-5h', '-30m']) {
        final ctx = AthleteContextBuilder.build(
          activities: [
            _makeActivity(
              id: 'bad_unit_$badUnit',
              discipline: SportDiscipline.run,
              timestamp: now.subtract(const Duration(days: 1)),
              durationSeconds: 0,
              movingTime: badUnit,
              elapsedTime: badUnit,
            ),
          ],
          profile: const AthletePhysiologicalProfile(),
          pmcSeries: const [],
          now: now,
        );
        expect(ctx.avgWeeklyHours4w, 0.0);
        expect(ctx.avgWeeklyHours12w, 0.0);
      }

      final validUnitCtx = AthleteContextBuilder.build(
        activities: [
          _makeActivity(
            id: 'valid_unit_1',
            discipline: SportDiscipline.run,
            timestamp: now.subtract(const Duration(days: 1)),
            durationSeconds: 0,
            movingTime: '1h 30m',
          ),
          _makeActivity(
            id: 'valid_unit_2',
            discipline: SportDiscipline.bike,
            timestamp: now.subtract(const Duration(days: 2)),
            durationSeconds: 0,
            movingTime: '1.5h',
          ),
        ],
        profile: const AthletePhysiologicalProfile(),
        pmcSeries: const [],
        now: now,
      );
      expect(validUnitCtx.avgWeeklyHours4w, closeTo(0.76, 0.02));

      // 2. Activity.durationSeconds: 1e308 capped in _effectiveDurationSeconds
      final extremeDurCtx = AthleteContextBuilder.build(
        activities: [
          _makeActivity(
            id: 'huge_dur',
            discipline: SportDiscipline.run,
            timestamp: now.subtract(const Duration(days: 1)),
            distanceKm: 10.0,
            durationSeconds: 1e308,
          ),
        ],
        profile: const AthletePhysiologicalProfile(),
        pmcSeries: const [],
        now: now,
      );
      expect(extremeDurCtx.avgWeeklyHours4w, 0.0);
      expect(extremeDurCtx.avgWeeklyHours12w, 0.0);
      expect(extremeDurCtx.longestRecentRun?.durationSeconds, 0.0);
      final extremeDurPrompt = extremeDurCtx.toPromptPayload();
      expect(scientificExpRegex.hasMatch(extremeDurPrompt), isFalse);
      expect(extremeDurPrompt, contains('Total: 0.0 hrs/wk (4w) | 0.0 hrs/wk (12w)'));

      // 3. Direct AthleteContext construction with extreme hours & avgAdherencePercent
      final directExtremeCtx = AthleteContext(
        asOfDate: now,
        zones: const AthleteZonesSnapshot(),
        avgWeeklyHours4w: 1e308,
        avgWeeklyHours12w: 1e25,
        volume4w: const {
          SportDiscipline.run: SportVolumeSummary(
            avgWeeklyDistanceKm: 1e308,
            avgWeeklyHours: 1e308,
            sessionsCount: 2,
          ),
        },
        longestRecentRun: LongestSessionSummary(
          distanceKm: 1e308,
          durationSeconds: 1e308,
          date: now,
        ),
        adherenceSummary: const PlanAdherenceSummary(
          totalDue: 1,
          completed: 1,
          skipped: 0,
          missedOrPending: 0,
          avgAdherencePercent: 1e308,
        ),
      );
      final directPrompt = directExtremeCtx.toPromptPayload();
      expect(scientificExpRegex.hasMatch(directPrompt), isFalse);
      expect(directPrompt, isNot(contains('NaN')));
      expect(directPrompt, isNot(contains('Infinity')));
      expect(directPrompt, contains('Total: 0.0 hrs/wk (4w) | 0.0 hrs/wk (12w)'));
      expect(directPrompt, contains('(0.0% avg adherence)'));

      final clampedAdhCtx = AthleteContext(
        asOfDate: now,
        zones: const AthleteZonesSnapshot(),
        avgWeeklyHours4w: 4.5,
        avgWeeklyHours12w: 4.0,
        adherenceSummary: const PlanAdherenceSummary(
          totalDue: 2,
          completed: 2,
          skipped: 0,
          missedOrPending: 0,
          avgAdherencePercent: 150.0,
        ),
      );
      expect(clampedAdhCtx.toPromptPayload(), contains('(100.0% avg adherence)'));
    });
  });

  group('Group 3 — WorkoutComplianceMatcher', () {
    test('matches same-day same-sport, bike/indoorBike equivalence, and UTC-cached timestamps', () {
      final plan = _samplePlan();
      // Create evening local activity converted to UTC (simulating LocalDataCache)
      final localEvening = DateTime(2026, 11, 17, 21, 30);
      final utcCachedEvening = localEvening.toUtc();

      final activities = [
        _makeActivity(
          id: 'act_run',
          discipline: SportDiscipline.run,
          timestamp: utcCachedEvening,
          distanceKm: 10.0,
          durationSeconds: 55 * 60.0,
        ),
        // ZwiftRide (indoorBike) completed outdoors as SportDiscipline.bike
        _makeActivity(
          id: 'act_bike_outdoor',
          discipline: SportDiscipline.bike,
          timestamp: DateTime(2026, 11, 18, 7, 0).toUtc(),
          distanceKm: 32.0,
          durationSeconds: 60 * 60.0,
        ),
        // Mismatched sport on swim day -> should NOT match swim
        _makeActivity(
          id: 'act_wrong_sport',
          discipline: SportDiscipline.run,
          timestamp: DateTime(2026, 11, 19, 8, 0),
          distanceKm: 8.0,
          durationSeconds: 2400,
        ),
        // Activity on rest day -> rest must remain scheduled / never auto-completed
        _makeActivity(
          id: 'act_rest_day',
          discipline: SportDiscipline.run,
          timestamp: DateTime(2026, 11, 20, 8, 0),
          distanceKm: 3.0,
          durationSeconds: 1200,
        ),
      ];

      final matched = WorkoutComplianceMatcher.matchPlan(plan, activities);
      final workouts = matched.allWorkouts;

      expect(workouts[0].status, WorkoutStatus.completed);
      expect(workouts[0].matchedActivityId, 'act_run');
      expect(workouts[0].adherencePercent, 100.0);

      expect(workouts[1].status, WorkoutStatus.completed);
      expect(workouts[1].matchedActivityId, 'act_bike_outdoor');
      expect(workouts[1].adherencePercent, 100.0);

      expect(workouts[2].status, WorkoutStatus.scheduled);
      expect(workouts[2].matchedActivityId, isNull);

      expect(workouts[3].archetype, WorkoutArchetype.rest);
      expect(workouts[3].status, WorkoutStatus.scheduled);
      expect(workouts[3].matchedActivityId, isNull);
    });

    test('preserves skipped and manual completed workouts; deterministic best-fit 1-to-1 matching', () {
      final basePlan = _samplePlan(
        weeks: [
          TrainingWeek(
            weekNumber: 1,
            startDate: '2026-11-16',
            phaseName: 'Base',
            focusSummary: 'Multi-workout day',
            targetHours: 5,
            targetTss: 250,
            workouts: [
              PlannedWorkout(
                id: 'run_skipped',
                date: '2026-11-17',
                title: 'Skipped Morning Run',
                discipline: SportDiscipline.run,
                archetype: WorkoutArchetype.easy,
                estimatedDurationMinutes: 30,
                status: WorkoutStatus.skipped,
              ),
              PlannedWorkout(
                id: 'run_short',
                date: '2026-11-17',
                title: 'Short Shakeout',
                discipline: SportDiscipline.run,
                archetype: WorkoutArchetype.easy,
                estimatedDurationMinutes: 25,
              ),
              PlannedWorkout(
                id: 'run_tempo',
                date: '2026-11-17',
                title: 'Tempo Run',
                discipline: SportDiscipline.run,
                archetype: WorkoutArchetype.threshold,
                estimatedDurationMinutes: 60,
              ),
              PlannedWorkout(
                id: 'manual_done',
                date: '2026-11-18',
                title: 'Manual Strength',
                discipline: SportDiscipline.strength,
                archetype: WorkoutArchetype.strength,
                estimatedDurationMinutes: 40,
                status: WorkoutStatus.completed,
              ),
            ],
          ),
        ],
      );

      final activities = [
        // Only one 60m run -> should skip `run_skipped` AND best-fit match `run_tempo` (not `run_short`)
        _makeActivity(
          id: 'act_60m',
          discipline: SportDiscipline.run,
          timestamp: DateTime(2026, 11, 17, 17, 0),
          distanceKm: 12.0,
          durationSeconds: 3600,
        ),
      ];

      final matched = WorkoutComplianceMatcher.matchPlan(basePlan, activities);
      final w = matched.allWorkouts;

      expect(w[0].status, WorkoutStatus.skipped);
      expect(w[0].matchedActivityId, isNull);

      expect(w[1].status, WorkoutStatus.scheduled);
      expect(w[1].matchedActivityId, isNull);

      expect(w[2].status, WorkoutStatus.completed);
      expect(w[2].matchedActivityId, 'act_60m');
      expect(w[2].adherencePercent, 100.0);

      // Manual completed with no matching activity stays completed
      expect(w[3].status, WorkoutStatus.completed);
      expect(w[3].matchedActivityId, isNull);

      // Idempotent on re-run
      final rematch = WorkoutComplianceMatcher.matchPlan(matched, activities);
      expect(rematch.allWorkouts[2].matchedActivityId, 'act_60m');
    });

    test('brick matching handles full, bike-only, run-only, and skipped-run-leg cases + movingTime fallback', () {
      final brickWorkout = PlannedWorkout(
        id: 'brick_1',
        date: '2026-11-21',
        title: 'Sat Brick',
        discipline: SportDiscipline.bike,
        archetype: WorkoutArchetype.brick,
        estimatedDurationMinutes: 80,
        zwiftPrescription: const ZwiftPrescription(
          durationMinutes: 60,
          difficulty: 'Tempo',
          targetTss: 60,
          zwiftCategory: 'Tempo',
        ),
        brickRunLeg: PlannedWorkout(
          id: 'brick_1_run',
          date: '2026-11-21',
          title: 'T2 Run',
          discipline: SportDiscipline.run,
          archetype: WorkoutArchetype.easy,
          estimatedDurationMinutes: 20,
        ),
      );
      final plan = _samplePlan(
        weeks: [
          TrainingWeek(
            weekNumber: 1,
            startDate: '2026-11-16',
            phaseName: 'Build',
            focusSummary: 'Brick test',
            targetHours: 2,
            targetTss: 100,
            workouts: [brickWorkout],
          ),
        ],
      );

      final bikeAct = _makeActivity(
        id: 'bike_1',
        discipline: SportDiscipline.indoorBike,
        timestamp: DateTime(2026, 11, 21, 8, 0),
        distanceKm: 30.0,
        durationSeconds: 0, // tests movingTime fallback
        movingTime: '1:10:00', // > planned 60m -> adherence clamped to 100.0
      );
      final runAct = _makeActivity(
        id: 'run_1',
        discipline: SportDiscipline.run,
        timestamp: DateTime(2026, 11, 21, 9, 15),
        distanceKm: 4.0,
        durationSeconds: 20 * 60.0,
      );

      // Full match
      final full = WorkoutComplianceMatcher.matchPlan(plan, [bikeAct, runAct]);
      final fullBrick = full.allWorkouts.single;
      expect(fullBrick.status, WorkoutStatus.completed);
      expect(fullBrick.matchedActivityId, 'bike_1');
      expect(fullBrick.adherencePercent, 100.0);
      expect(fullBrick.brickRunLeg?.status, WorkoutStatus.completed);
      expect(fullBrick.brickRunLeg?.matchedActivityId, 'run_1');
      expect(fullBrick.brickRunLeg?.adherencePercent, 100.0);

      // Bike-only partial (60 / (60+20) = 75.0%)
      final bikeOnly = WorkoutComplianceMatcher.matchPlan(plan, [bikeAct]);
      final bikeOnlyBrick = bikeOnly.allWorkouts.single;
      expect(bikeOnlyBrick.status, WorkoutStatus.scheduled);
      expect(bikeOnlyBrick.matchedActivityId, 'bike_1');
      expect(bikeOnlyBrick.adherencePercent, 75.0);
      expect(bikeOnlyBrick.brickRunLeg?.status, WorkoutStatus.scheduled);

      // Run-only partial (20 / (60+20) = 25.0%)
      final runOnly = WorkoutComplianceMatcher.matchPlan(plan, [runAct]);
      final runOnlyBrick = runOnly.allWorkouts.single;
      expect(runOnlyBrick.status, WorkoutStatus.scheduled);
      expect(runOnlyBrick.matchedActivityId, isNull);
      expect(runOnlyBrick.adherencePercent, 25.0);
      expect(runOnlyBrick.brickRunLeg?.status, WorkoutStatus.completed);
      expect(runOnlyBrick.brickRunLeg?.matchedActivityId, 'run_1');

      // Skipped run leg + bike match -> top-level completed, skipped preserved
      final skippedLegPlan = plan.copyWith(
        weeks: [
          plan.weeks.single.copyWith(
            workouts: [
              brickWorkout.copyWith(
                brickRunLeg: brickWorkout.brickRunLeg!
                    .copyWith(status: WorkoutStatus.skipped),
              ),
            ],
          ),
        ],
      );
      final skippedLegMatched =
          WorkoutComplianceMatcher.matchPlan(skippedLegPlan, [bikeAct, runAct]);
      final skippedBrick = skippedLegMatched.allWorkouts.single;
      expect(skippedBrick.status, WorkoutStatus.completed);
      expect(skippedBrick.matchedActivityId, 'bike_1');
      expect(skippedBrick.adherencePercent, 100.0);
      expect(skippedBrick.brickRunLeg?.status, WorkoutStatus.skipped);
      expect(skippedBrick.brickRunLeg?.matchedActivityId, isNull);

      expect(
        WorkoutComplianceMatcher.computePlanAdherencePercent(full),
        100.0,
      );
      expect(
        WorkoutComplianceMatcher.computeWeekAdherencePercent(
          bikeOnly.weeks.single,
        ),
        75.0,
      );
    });

    test('handles non-finite/negative estimatedDistanceKm, pathological durations, duplicate IDs, and order independence', () {
      final plan = _samplePlan(
        weeks: [
          TrainingWeek(
            weekNumber: 1,
            startDate: '2026-11-16',
            phaseName: 'Base',
            focusSummary: '',
            targetHours: 3.0,
            targetTss: 150,
            workouts: [
              PlannedWorkout(
                id: 'run_25m_inf_dist',
                date: '2026-11-17',
                title: 'Short Run Inf Dist',
                discipline: SportDiscipline.run,
                archetype: WorkoutArchetype.easy,
                estimatedDurationMinutes: 25,
                estimatedDistanceKm: double.infinity,
              ),
              PlannedWorkout(
                id: 'run_60m',
                date: '2026-11-17',
                title: 'Longer Run',
                discipline: SportDiscipline.run,
                archetype: WorkoutArchetype.easy,
                estimatedDurationMinutes: 60,
                estimatedDistanceKm: 12.0,
              ),
              PlannedWorkout(
                id: 'run_nan_dist',
                date: '2026-11-18',
                title: 'NaN Dist Run',
                discipline: SportDiscipline.run,
                archetype: WorkoutArchetype.easy,
                estimatedDurationMinutes: 30,
                estimatedDistanceKm: double.nan,
              ),
              PlannedWorkout(
                id: 'run_neg_dist',
                date: '2026-11-19',
                title: 'Neg Dist Run',
                discipline: SportDiscipline.run,
                archetype: WorkoutArchetype.easy,
                estimatedDurationMinutes: 30,
                estimatedDistanceKm: -5.0,
              ),
            ],
          ),
        ],
      );

      final act25m = _makeActivity(
        id: 'act_25m',
        discipline: SportDiscipline.run,
        timestamp: DateTime(2026, 11, 17, 7, 0),
        distanceKm: 5.0,
        durationSeconds: 0,
        movingTime: '25:00',
      );
      final actBadDur = _makeActivity(
        id: 'act_bad_dur',
        discipline: SportDiscipline.run,
        timestamp: DateTime(2026, 11, 18, 7, 0),
        distanceKm: 0.0,
        durationSeconds: 0,
        movingTime: 'Infinity:00',
        elapsedTime: '1e309:00',
      );
      final actBadDur2 = _makeActivity(
        id: 'act_bad_dur_2',
        discipline: SportDiscipline.run,
        timestamp: DateTime(2026, 11, 19, 7, 0),
        distanceKm: 0.0,
        durationSeconds: 0,
        movingTime: '1e308:00',
        elapsedTime: '${'9' * 310}h',
      );
      final actBadDur3 = _makeActivity(
        id: 'act_bad_dur_3',
        discipline: SportDiscipline.run,
        timestamp: DateTime(2026, 11, 19, 8, 0),
        distanceKm: 0.0,
        durationSeconds: 0,
        movingTime: '-5:00',
        elapsedTime: 'NaN:00',
      );

      final matched = WorkoutComplianceMatcher.matchPlan(
        plan,
        [act25m, actBadDur, actBadDur2],
      );
      final w = matched.allWorkouts;
      // Duration-based best-fit selects run_25m_inf_dist (not poisoned by NaN score)
      expect(w[0].status, WorkoutStatus.completed);
      expect(w[0].matchedActivityId, 'act_25m');
      expect(w[0].adherencePercent, 100.0);
      expect(w[1].status, WorkoutStatus.scheduled);
      expect(w[1].matchedActivityId, isNull);

      expect(w[2].adherencePercent, 0.0);
      expect(w[3].adherencePercent, 0.0);
      expect(
        WorkoutComplianceMatcher.computeAdherencePercent(
          plannedDurationMinutes: 30,
          plannedDistanceKm: double.infinity,
          activity: actBadDur3,
        ),
        0.0,
      );

      // Duplicate Activity.id matches at most once; reversed activity order produces identical assignments
      final dupPlan = _samplePlan(
        weeks: [
          TrainingWeek(
            weekNumber: 1,
            startDate: '2026-11-16',
            phaseName: 'Base',
            focusSummary: '',
            targetHours: 2.0,
            targetTss: 100,
            workouts: [
              PlannedWorkout(
                id: 'r1',
                date: '2026-11-17',
                title: 'Run 1',
                discipline: SportDiscipline.run,
                archetype: WorkoutArchetype.easy,
                estimatedDurationMinutes: 30,
              ),
              PlannedWorkout(
                id: 'r2',
                date: '2026-11-17',
                title: 'Run 2',
                discipline: SportDiscipline.run,
                archetype: WorkoutArchetype.easy,
                estimatedDurationMinutes: 45,
              ),
            ],
          ),
        ],
      );
      final dupActA = _makeActivity(
        id: 'dup_id',
        discipline: SportDiscipline.run,
        timestamp: DateTime(2026, 11, 17, 7, 0),
        durationSeconds: 1800,
      );
      final dupActB = _makeActivity(
        id: 'dup_id',
        discipline: SportDiscipline.run,
        timestamp: DateTime(2026, 11, 17, 17, 0),
        durationSeconds: 2700,
      );
      final dupMatched =
          WorkoutComplianceMatcher.matchPlan(dupPlan, [dupActA, dupActB]);
      final matchedCount = dupMatched.allWorkouts
          .where((wo) => wo.matchedActivityId != null)
          .length;
      expect(matchedCount, 1);

      // Order independence with distinct activities
      final actA = _makeActivity(
        id: 'distinct_a',
        discipline: SportDiscipline.run,
        timestamp: DateTime(2026, 11, 17, 7, 0),
        durationSeconds: 1800,
      );
      final actB = _makeActivity(
        id: 'distinct_b',
        discipline: SportDiscipline.run,
        timestamp: DateTime(2026, 11, 17, 17, 0),
        durationSeconds: 2700,
      );
      final forward = WorkoutComplianceMatcher.matchPlan(dupPlan, [actA, actB]);
      final reversed = WorkoutComplianceMatcher.matchPlan(dupPlan, [actB, actA]);
      expect(
        reversed.allWorkouts.map((wo) => wo.matchedActivityId).toList(),
        forward.allWorkouts.map((wo) => wo.matchedActivityId).toList(),
      );
    });

    test('brick matching handles mixed manual + single-leg auto-match in both directions idempotently', () {
      final baseBrick = PlannedWorkout(
        id: 'brick_mixed',
        date: '2026-11-21',
        title: 'Mixed Brick',
        discipline: SportDiscipline.bike,
        archetype: WorkoutArchetype.brick,
        estimatedDurationMinutes: 80,
        zwiftPrescription: const ZwiftPrescription(
          durationMinutes: 60,
          difficulty: 'Tempo',
          targetTss: 60,
          zwiftCategory: 'Tempo',
        ),
        brickRunLeg: PlannedWorkout(
          id: 'brick_mixed_run',
          date: '2026-11-21',
          title: 'T2 Run',
          discipline: SportDiscipline.run,
          archetype: WorkoutArchetype.easy,
          estimatedDurationMinutes: 20,
        ),
      );
      final bikeAct = _makeActivity(
        id: 'bike_1',
        discipline: SportDiscipline.indoorBike,
        timestamp: DateTime(2026, 11, 21, 8, 0),
        durationSeconds: 60 * 60.0,
      );
      final runAct80 = _makeActivity(
        id: 'run_1',
        discipline: SportDiscipline.run,
        timestamp: DateTime(2026, 11, 21, 9, 15),
        durationSeconds: 16 * 60.0, // 16m of 20m = 80% adherence
      );

      // Subcase 1a: brickRunLeg manually completed (default 100%) + bikeAct auto-matched (100%)
      final manualRunPlan = _samplePlan(
        weeks: [
          TrainingWeek(
            weekNumber: 1,
            startDate: '2026-11-16',
            phaseName: 'Build',
            focusSummary: '',
            targetHours: 2,
            targetTss: 100,
            workouts: [
              baseBrick.copyWith(
                brickRunLeg: baseBrick.brickRunLeg!
                    .copyWith(status: WorkoutStatus.completed),
              ),
            ],
          ),
        ],
      );
      final matched1a =
          WorkoutComplianceMatcher.matchPlan(manualRunPlan, [bikeAct]);
      final b1a = matched1a.allWorkouts.single;
      expect(b1a.status, WorkoutStatus.completed);
      expect(b1a.matchedActivityId, 'bike_1');
      expect(b1a.adherencePercent, 100.0);
      expect(b1a.brickRunLeg!.status, WorkoutStatus.completed);
      expect(b1a.brickRunLeg!.matchedActivityId, isNull);

      // Subcase 1b: brickRunLeg manually completed with explicit adherence 80.0 + bikeAct 100% -> 95.0
      final manualRun80Plan = _samplePlan(
        weeks: [
          manualRunPlan.weeks.single.copyWith(
            workouts: [
              baseBrick.copyWith(
                brickRunLeg: baseBrick.brickRunLeg!.copyWith(
                  status: WorkoutStatus.completed,
                  adherencePercent: 80.0,
                ),
              ),
            ],
          ),
        ],
      );
      final matched1b =
          WorkoutComplianceMatcher.matchPlan(manualRun80Plan, [bikeAct]);
      final b1b = matched1b.allWorkouts.single;
      expect(b1b.status, WorkoutStatus.completed);
      expect(b1b.adherencePercent, 95.0);
      final rematch1b =
          WorkoutComplianceMatcher.matchPlan(matched1b, [bikeAct]);
      expect(rematch1b.allWorkouts.single.adherencePercent, 95.0);
      expect(rematch1b.allWorkouts.single.status, WorkoutStatus.completed);

      // Subcase 2: parent Brick manually completed + runAct 80% auto-matched -> stays completed at 95.0
      final manualBikePlan = _samplePlan(
        weeks: [
          manualRunPlan.weeks.single.copyWith(
            workouts: [
              baseBrick.copyWith(status: WorkoutStatus.completed),
            ],
          ),
        ],
      );
      final matched2 =
          WorkoutComplianceMatcher.matchPlan(manualBikePlan, [runAct80]);
      final b2 = matched2.allWorkouts.single;
      expect(b2.status, WorkoutStatus.completed);
      expect(b2.matchedActivityId, isNull);
      expect(b2.adherencePercent, 95.0);
      expect(b2.brickRunLeg!.status, WorkoutStatus.completed);
      expect(b2.brickRunLeg!.matchedActivityId, 'run_1');
      expect(b2.brickRunLeg!.adherencePercent, 80.0);

      // Idempotency: second pass preserves 95.0 with zero drift
      final rematch2 = WorkoutComplianceMatcher.matchPlan(matched2, [runAct80]);
      expect(rematch2.allWorkouts.single.status, WorkoutStatus.completed);
      expect(rematch2.allWorkouts.single.matchedActivityId, isNull);
      expect(rematch2.allWorkouts.single.adherencePercent, 95.0);
    });

    test('preserves manual parent Brick completion when auto-matched brickRunLeg loses activity, rejects sci-notation durations, and clamps adherence averages', () {
      final baseBrick = PlannedWorkout(
        id: 'brick_manual_parent',
        date: '2026-11-21',
        title: 'Manual Parent Brick',
        discipline: SportDiscipline.bike,
        archetype: WorkoutArchetype.brick,
        estimatedDurationMinutes: 80,
        zwiftPrescription: const ZwiftPrescription(
          durationMinutes: 60,
          difficulty: 'Tempo',
          targetTss: 60,
          zwiftCategory: 'Tempo',
        ),
        brickRunLeg: PlannedWorkout(
          id: 'brick_manual_parent_run',
          date: '2026-11-21',
          title: 'T2 Run',
          discipline: SportDiscipline.run,
          archetype: WorkoutArchetype.easy,
          estimatedDurationMinutes: 20,
        ),
      );
      final manualParentPlan = _samplePlan(
        weeks: [
          TrainingWeek(
            weekNumber: 1,
            startDate: '2026-11-16',
            phaseName: 'Build',
            focusSummary: '',
            targetHours: 2,
            targetTss: 100,
            workouts: [baseBrick.copyWith(status: WorkoutStatus.completed)],
          ),
        ],
      );
      final runAct80 = _makeActivity(
        id: 'run_1',
        discipline: SportDiscipline.run,
        timestamp: DateTime(2026, 11, 21, 9, 15),
        durationSeconds: 16 * 60.0,
      );

      // Step 1: brickRunLeg auto-matches run_1 while parent remains manually completed
      final withRun =
          WorkoutComplianceMatcher.matchPlan(manualParentPlan, [runAct80]);
      expect(withRun.allWorkouts.single.status, WorkoutStatus.completed);
      expect(withRun.allWorkouts.single.matchedActivityId, isNull);
      expect(withRun.allWorkouts.single.adherencePercent, 95.0);
      expect(withRun.allWorkouts.single.brickRunLeg!.matchedActivityId, 'run_1');

      // Step 2: run_1 disappears -> brickRunLeg resets, manual parent completion is preserved
      final withoutRun = WorkoutComplianceMatcher.matchPlan(withRun, const []);
      final preserved = withoutRun.allWorkouts.single;
      expect(preserved.status, WorkoutStatus.completed);
      expect(preserved.matchedActivityId, isNull);
      expect(preserved.adherencePercent, isNull);
      expect(preserved.brickRunLeg!.status, WorkoutStatus.scheduled);
      expect(preserved.brickRunLeg!.matchedActivityId, isNull);
      expect(preserved.brickRunLeg!.adherencePercent, isNull);

      // Step 3: idempotent on subsequent empty pass
      final withoutRunPass2 =
          WorkoutComplianceMatcher.matchPlan(withoutRun, const []);
      expect(withoutRunPass2.allWorkouts.single.status, WorkoutStatus.completed);
      expect(withoutRunPass2.allWorkouts.single.matchedActivityId, isNull);
      expect(withoutRunPass2.allWorkouts.single.adherencePercent, isNull);
      expect(
        withoutRunPass2.allWorkouts.single.brickRunLeg!.status,
        WorkoutStatus.scheduled,
      );

      // Step 4: both parent & brickRunLeg manually completed stays intact
      final bothManualPlan = _samplePlan(
        weeks: [
          manualParentPlan.weeks.single.copyWith(
            workouts: [
              baseBrick.copyWith(
                status: WorkoutStatus.completed,
                adherencePercent: 90.0,
                brickRunLeg: baseBrick.brickRunLeg!.copyWith(
                  status: WorkoutStatus.completed,
                  adherencePercent: 85.0,
                ),
              ),
            ],
          ),
        ],
      );
      final bothManualAfter =
          WorkoutComplianceMatcher.matchPlan(bothManualPlan, const []);
      expect(bothManualAfter.allWorkouts.single.status, WorkoutStatus.completed);
      expect(bothManualAfter.allWorkouts.single.adherencePercent, 90.0);
      expect(
        bothManualAfter.allWorkouts.single.brickRunLeg!.status,
        WorkoutStatus.completed,
      );
      expect(
        bothManualAfter.allWorkouts.single.brickRunLeg!.adherencePercent,
        85.0,
      );

      // Scientific-notation duration rejected in WorkoutComplianceMatcher
      final sciRunAct = _makeActivity(
        id: 'sci_act',
        discipline: SportDiscipline.run,
        timestamp: DateTime(2026, 11, 21, 7, 0),
        durationSeconds: 0,
        movingTime: '1e306:00',
        elapsedTime: '999999999:00',
      );
      expect(
        WorkoutComplianceMatcher.computeAdherencePercent(
          plannedDurationMinutes: 30,
          activity: sciRunAct,
        ),
        0.0,
      );

      // computeWeekAdherencePercent & computePlanAdherencePercent clamp out-of-range values to [0.0, 100.0]
      final outOfRangePlan = _samplePlan(
        weeks: [
          TrainingWeek(
            weekNumber: 1,
            startDate: '2026-11-16',
            phaseName: 'Base',
            focusSummary: '',
            targetHours: 2,
            targetTss: 100,
            workouts: [
              PlannedWorkout(
                id: 'w_over',
                date: '2026-11-17',
                title: 'Over 100',
                discipline: SportDiscipline.run,
                archetype: WorkoutArchetype.easy,
                estimatedDurationMinutes: 30,
                status: WorkoutStatus.completed,
                adherencePercent: 200.0,
              ),
            ],
          ),
          TrainingWeek(
            weekNumber: 2,
            startDate: '2026-11-23',
            phaseName: 'Base',
            focusSummary: '',
            targetHours: 2,
            targetTss: 100,
            workouts: [
              PlannedWorkout(
                id: 'w_under',
                date: '2026-11-24',
                title: 'Under 0',
                discipline: SportDiscipline.run,
                archetype: WorkoutArchetype.easy,
                estimatedDurationMinutes: 30,
                status: WorkoutStatus.completed,
                adherencePercent: -50.0,
              ),
            ],
          ),
        ],
      );
      expect(
        WorkoutComplianceMatcher.computeWeekAdherencePercent(
          outOfRangePlan.weeks[0],
        ),
        100.0,
      );
      expect(
        WorkoutComplianceMatcher.computeWeekAdherencePercent(
          outOfRangePlan.weeks[1],
        ),
        0.0,
      );
      expect(
        WorkoutComplianceMatcher.computePlanAdherencePercent(outOfRangePlan),
        50.0,
      );
    });

    test('rejects partial unit-regex tokens and caps extreme Activity.durationSeconds', () {
      final now = DateTime(2026, 11, 21, 9, 0);

      for (final badUnit in const ['1e7h', '1e306h', '-5h', '-30m']) {
        final act = _makeActivity(
          id: 'bad_$badUnit',
          discipline: SportDiscipline.run,
          timestamp: now,
          durationSeconds: 0,
          movingTime: badUnit,
          elapsedTime: badUnit,
        );
        expect(
          WorkoutComplianceMatcher.computeAdherencePercent(
            plannedDurationMinutes: 60,
            activity: act,
          ),
          0.0,
          reason: 'Expected 0.0 for malformed unit string $badUnit',
        );
      }

      // Valid unit strings still work
      expect(
        WorkoutComplianceMatcher.computeAdherencePercent(
          plannedDurationMinutes: 90,
          activity: _makeActivity(
            id: 'ok_1',
            discipline: SportDiscipline.run,
            timestamp: now,
            durationSeconds: 0,
            movingTime: '1h 30m',
          ),
        ),
        100.0,
      );
      expect(
        WorkoutComplianceMatcher.computeAdherencePercent(
          plannedDurationMinutes: 90,
          activity: _makeActivity(
            id: 'ok_2',
            discipline: SportDiscipline.run,
            timestamp: now,
            durationSeconds: 0,
            movingTime: '45m',
          ),
        ),
        50.0,
      );

      // Activity.durationSeconds: 1e308 capped cleanly
      expect(
        WorkoutComplianceMatcher.computeAdherencePercent(
          plannedDurationMinutes: 60,
          activity: _makeActivity(
            id: 'huge_dur',
            discipline: SportDiscipline.run,
            timestamp: now,
            durationSeconds: 1e308,
          ),
        ),
        0.0,
      );
    });
  });

  group('Group 4 — TrainingPlanStore', () {
    test('round-trips plan + messages atomically with 0600 permissions and clears cleanly', () async {
      final tempDir = await Directory.systemTemp.createTemp('plan_store_test_');
      addTearDown(() => tempDir.delete(recursive: true));
      final planFile = File('${tempDir.path}/training_plan.json');
      final store = TrainingPlanStore(customFilePath: planFile.path);

      final plan = _samplePlan();
      final messages = [
        CoachMessage(
          id: 'u1',
          role: CoachMessageRole.user,
          content: 'Build me a 70.3 plan.',
          createdAt: DateTime.utc(2026, 11, 20, 12, 0),
        ),
        CoachMessage(
          id: 'a1',
          role: CoachMessageRole.assistant,
          content: 'Ready!',
          createdAt: DateTime.utc(2026, 11, 20, 12, 1),
          proposedPlan: plan,
        ),
      ];

      await store.save(plan, messages);
      expect(await planFile.exists(), isTrue);
      expect(await File('${planFile.path}.tmp').exists(), isFalse);

      if (!Platform.isWindows) {
        final stat = await planFile.stat();
        expect(stat.mode & 0x1FF, 0x180); // 0600
      }

      final loaded = await store.load();
      expect(loaded, isNotNull);
      expect(loaded!.plan?.id, plan.id);
      expect(loaded.plan?.allWorkouts.length, 5);
      expect(loaded.messages.length, 2);
      expect(loaded.messages[1].proposedPlan?.id, plan.id);

      // Save pre-plan chat messages (plan == null)
      await store.save(null, [messages.first]);
      final chatOnly = await store.load();
      expect(chatOnly, isNotNull);
      expect(chatOnly!.plan, isNull);
      expect(chatOnly.messages.length, 1);

      // Clear deletes both main file and stale .tmp
      final staleTmp = File('${planFile.path}.tmp');
      await staleTmp.writeAsString('stale');
      await store.clear();
      expect(await planFile.exists(), isFalse);
      expect(await staleTmp.exists(), isFalse);
      // Idempotent second clear
      await store.clear();
    });

    test('load() returns null gracefully on missing, empty, corrupt, or wrong-shape JSON', () async {
      final tempDir = await Directory.systemTemp.createTemp('plan_store_bad_');
      addTearDown(() => tempDir.delete(recursive: true));
      final planFile = File('${tempDir.path}/training_plan.json');
      final store = TrainingPlanStore(customFilePath: planFile.path);

      // Missing
      expect(await store.load(), isNull);

      // Empty
      await planFile.writeAsString('   \n  ');
      expect(await store.load(), isNull);

      // Corrupt JSON
      await planFile.writeAsString('{corrupt json');
      expect(await store.load(), isNull);

      // Non-object JSON
      await planFile.writeAsString('[1, 2, 3]');
      expect(await store.load(), isNull);

      // Unrelated schema map
      await planFile.writeAsString('{"foo": "bar"}');
      expect(await store.load(), isNull);

      // Wrong field types
      await planFile.writeAsString('{"schemaVersion": 1, "plan": "bad"}');
      expect(await store.load(), isNull);
      await planFile.writeAsString('{"schemaVersion": 1, "messages": "bad"}');
      expect(await store.load(), isNull);
    });

    test('supports const constructor, concurrent saves, interleaved save/clear/save, and non-poisoning failures', () async {
      const defaultStore = TrainingPlanStore();
      expect(defaultStore.customFilePath, isNull);

      final tempDir = await Directory.systemTemp.createTemp('plan_store_conc_');
      addTearDown(() async {
        // Ensure writable before recursive delete
        if (!Platform.isWindows) {
          await Process.run('chmod', ['755', tempDir.path]);
        }
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final planFile = File('${tempDir.path}/training_plan.json');
      final store = TrainingPlanStore(customFilePath: planFile.path);
      final storeDup = TrainingPlanStore(customFilePath: planFile.path);
      final basePlan = _samplePlan();

      // 12 concurrent saves across two instances targeting the same file path
      await Future.wait([
        for (var i = 0; i < 12; i++)
          (i.isEven ? store : storeDup).save(
            basePlan.copyWith(name: 'Concurrent Plan $i'),
          ),
      ]);

      final afterConcurrent = await store.load();
      expect(afterConcurrent, isNotNull);
      expect(afterConcurrent!.plan?.name, startsWith('Concurrent Plan '));
      final leftoverTmps = tempDir
          .listSync()
          .where((e) => e.path.endsWith('.tmp'))
          .toList();
      expect(leftoverTmps, isEmpty);

      // Interleaved save -> clear -> save
      await Future.wait([
        store.save(basePlan.copyWith(name: 'First')),
        store.clear(),
        store.save(basePlan.copyWith(name: 'Second')),
      ]);
      final afterInterleave = await store.load();
      expect(afterInterleave, isNotNull);
      expect(afterInterleave!.plan?.name, 'Second');
      expect(
        tempDir.listSync().where((e) => e.path.endsWith('.tmp')),
        isEmpty,
      );

      // Failure mode 1: rename failure when target path is an existing directory
      final dirTarget = Directory('${tempDir.path}/dir_collision.json');
      await dirTarget.create();
      final collisionStore = TrainingPlanStore(customFilePath: dirTarget.path);
      await expectLater(
        collisionStore.save(basePlan),
        throwsA(isA<FileSystemException>()),
      );
      expect(
        tempDir.listSync().where((e) => e.path.endsWith('.tmp')),
        isEmpty,
      );
      // Lock is not poisoned after removing colliding dir
      await dirTarget.delete();
      await collisionStore.save(basePlan.copyWith(name: 'Recovered'));
      final recovered = await collisionStore.load();
      expect(recovered?.plan?.name, 'Recovered');

      // Failure mode 2: read-only parent directory (non-Windows)
      if (!Platform.isWindows) {
        final roDir = Directory('${tempDir.path}/ro_dir');
        await roDir.create();
        addTearDown(() async {
          await Process.run('chmod', ['755', roDir.path]);
        });
        await Process.run('chmod', ['555', roDir.path]);
        final roFile = File('${roDir.path}/training_plan.json');
        final roStore = TrainingPlanStore(customFilePath: roFile.path);
        await expectLater(
          roStore.save(basePlan),
          throwsA(isA<FileSystemException>()),
        );
        expect(
          roDir.listSync().where((e) => e.path.endsWith('.tmp')),
          isEmpty,
        );
        // Restore permissions and confirm lock is not poisoned
        await Process.run('chmod', ['755', roDir.path]);
        await roStore.save(basePlan.copyWith(name: 'After chmod'));
        expect((await roStore.load())?.plan?.name, 'After chmod');
      }
    });
  });
}
