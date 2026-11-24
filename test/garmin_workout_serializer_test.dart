import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pulse_training_hub/models/activity.dart';
import 'package:pulse_training_hub/models/training_plan.dart';
import 'package:pulse_training_hub/services/garmin_auth_store.dart';
import 'package:pulse_training_hub/services/garmin_service.dart';
import 'package:pulse_training_hub/services/garmin_workout_serializer.dart';

GarminSession _fakeGarminSession({String domain = 'garmin.com'}) => GarminSession(
      oauth1Token: 'o1_tok',
      oauth1TokenSecret: 'o1_sec',
      accessToken: 'bearer_garmin_123',
      expiresAt: DateTime.now().add(const Duration(hours: 2)),
      consumerKey: 'ck',
      consumerSecret: 'cs',
      domain: domain,
    );

void main() {
  group('GarminWorkoutSerializer.isGarminPushable & non-pushable rejection', () {
    test('truth table across archetypes and disciplines', () {
      PlannedWorkout makeWorkout({
        required SportDiscipline discipline,
        required WorkoutArchetype archetype,
        PlannedWorkout? brickRunLeg,
      }) {
        return PlannedWorkout(
          id: 'w_1',
          date: '2026-11-24',
          title: 'Test',
          discipline: discipline,
          archetype: archetype,
          estimatedDurationMinutes: 45,
          brickRunLeg: brickRunLeg,
        );
      }

      final runLeg = makeWorkout(
        discipline: SportDiscipline.run,
        archetype: WorkoutArchetype.easy,
      );

      expect(
        GarminWorkoutSerializer.isGarminPushable(
          makeWorkout(
            discipline: SportDiscipline.run,
            archetype: WorkoutArchetype.intervals,
          ),
        ),
        isTrue,
      );
      expect(
        GarminWorkoutSerializer.isGarminPushable(
          makeWorkout(
            discipline: SportDiscipline.swim,
            archetype: WorkoutArchetype.long,
          ),
        ),
        isTrue,
      );
      expect(
        GarminWorkoutSerializer.isGarminPushable(
          makeWorkout(
            discipline: SportDiscipline.bike,
            archetype: WorkoutArchetype.brick,
            brickRunLeg: runLeg,
          ),
        ),
        isTrue,
      );
      expect(
        GarminWorkoutSerializer.isGarminPushable(
          makeWorkout(
            discipline: SportDiscipline.bike,
            archetype: WorkoutArchetype.brick,
          ),
        ),
        isFalse,
      );
      expect(
        GarminWorkoutSerializer.isGarminPushable(
          makeWorkout(
            discipline: SportDiscipline.indoorBike,
            archetype: WorkoutArchetype.zwiftRide,
          ),
        ),
        isFalse,
      );
      expect(
        GarminWorkoutSerializer.isGarminPushable(
          makeWorkout(
            discipline: SportDiscipline.bike,
            archetype: WorkoutArchetype.easy,
          ),
        ),
        isFalse,
      );
      expect(
        GarminWorkoutSerializer.isGarminPushable(
          makeWorkout(
            discipline: SportDiscipline.strength,
            archetype: WorkoutArchetype.strength,
          ),
        ),
        isFalse,
      );
      expect(
        GarminWorkoutSerializer.isGarminPushable(
          makeWorkout(
            discipline: SportDiscipline.strength,
            archetype: WorkoutArchetype.rest,
          ),
        ),
        isFalse,
      );
    });

    test('serialize throws ArgumentError for zwiftRide, strength, rest, bike, and brick without run leg',
        () {
      for (final bad in [
        PlannedWorkout(
          id: 'zwift_1',
          date: '2026-11-24',
          title: 'Zwift Sweet Spot',
          discipline: SportDiscipline.indoorBike,
          archetype: WorkoutArchetype.zwiftRide,
          estimatedDurationMinutes: 60,
        ),
        PlannedWorkout(
          id: 'str_1',
          date: '2026-11-24',
          title: 'Core & Mobility',
          discipline: SportDiscipline.strength,
          archetype: WorkoutArchetype.strength,
          estimatedDurationMinutes: 30,
        ),
        PlannedWorkout(
          id: 'rest_1',
          date: '2026-11-24',
          title: 'Rest Day',
          discipline: SportDiscipline.strength,
          archetype: WorkoutArchetype.rest,
          estimatedDurationMinutes: 0,
        ),
        PlannedWorkout(
          id: 'bike_1',
          date: '2026-11-24',
          title: 'Outdoor Ride',
          discipline: SportDiscipline.bike,
          archetype: WorkoutArchetype.long,
          estimatedDurationMinutes: 120,
        ),
        PlannedWorkout(
          id: 'brick_no_leg',
          date: '2026-11-24',
          title: 'Brick No Leg',
          discipline: SportDiscipline.bike,
          archetype: WorkoutArchetype.brick,
          estimatedDurationMinutes: 90,
        ),
      ]) {
        expect(
          () => GarminWorkoutSerializer.serialize(bad),
          throwsArgumentError,
          reason: '${bad.id} should not serialize',
        );
      }
    });
  });

  group('GarminWorkoutSerializer Run, Swim & Brick serialization', () {
    test('Run Intervals: depth-first stepOrder 1..N, RepeatGroupDTO, pace.zone m/s & heart.rate.zone',
        () {
      final runIntervals = PlannedWorkout(
        id: 'run_int_1',
        date: '2026-11-24',
        title: '5x1km VO2max Track',
        discipline: SportDiscipline.run,
        archetype: WorkoutArchetype.intervals,
        estimatedDurationMinutes: 55,
        coachNotes: 'Controlled fast reps',
        blocks: const [
          WorkoutBlock(
            repeatCount: 1,
            step: WorkoutStep(
              kind: StepKind.warmup,
              endCondition: StepEndCondition.time,
              endValue: 600,
              targetKind: StepTargetKind.heartRateZone,
              targetLow: 1,
              targetHigh: 2,
              notes: 'Easy jog warmup',
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
                targetLow: 4.10,
                targetHigh: 4.35,
                notes: '5k pace',
              ),
              WorkoutStep(
                kind: StepKind.recovery,
                endCondition: StepEndCondition.time,
                endValue: 120,
                targetKind: StepTargetKind.none,
                notes: 'Walk/jog recovery',
              ),
            ],
          ),
          WorkoutBlock(
            repeatCount: 1,
            step: WorkoutStep(
              kind: StepKind.cooldown,
              endCondition: StepEndCondition.lapButton,
              targetKind: StepTargetKind.none,
            ),
          ),
        ],
      );

      final payload = GarminWorkoutSerializer.serialize(runIntervals);
      expect(payload['workoutName'], '5x1km VO2max Track');
      expect(payload['description'], 'Controlled fast reps');
      expect(payload['sportType'], {'sportTypeId': 1, 'sportTypeKey': 'running'});
      expect(payload.containsKey('poolLength'), isFalse);

      final segments = payload['workoutSegments'] as List;
      expect(segments, hasLength(1));
      final steps = (segments.first as Map)['workoutSteps'] as List;
      expect(steps, hasLength(3));

      // Step 1: Warmup
      final s1 = steps[0] as Map<String, dynamic>;
      expect(s1['type'], 'ExecutableStepDTO');
      expect(s1['stepOrder'], 1);
      expect(s1['stepType'], {'stepTypeId': 1, 'stepTypeKey': 'warmup'});
      expect(s1['endCondition'], {'conditionTypeId': 2, 'conditionTypeKey': 'time'});
      expect(s1['endConditionValue'], 600.0);
      expect(
        s1['targetType'],
        {'workoutTargetTypeId': 4, 'workoutTargetTypeKey': 'heart.rate.zone'},
      );
      expect(s1['zoneNumber'], 2);
      expect(s1['targetValueOne'], isNull);
      expect(s1['targetValueTwo'], isNull);

      // Step 2: RepeatGroupDTO (children 3 and 4)
      final s2 = steps[1] as Map<String, dynamic>;
      expect(s2['type'], 'RepeatGroupDTO');
      expect(s2['stepOrder'], 2);
      expect(s2['stepType'], {'stepTypeId': 6, 'stepTypeKey': 'repeat'});
      expect(s2['numberOfIterations'], 5);
      expect(
        s2['endCondition'],
        {'conditionTypeId': 7, 'conditionTypeKey': 'iterations'},
      );
      expect(s2['endConditionValue'], 5.0);
      expect(s2['smartRepeat'], isFalse);

      final children = s2['workoutSteps'] as List;
      expect(children, hasLength(2));

      final c1 = children[0] as Map<String, dynamic>;
      expect(c1['stepOrder'], 3);
      expect(c1['stepType'], {'stepTypeId': 3, 'stepTypeKey': 'interval'});
      expect(
        c1['endCondition'],
        {'conditionTypeId': 3, 'conditionTypeKey': 'distance'},
      );
      expect(c1['endConditionValue'], 1000.0);
      expect(
        c1['targetType'],
        {'workoutTargetTypeId': 6, 'workoutTargetTypeKey': 'pace.zone'},
      );
      expect(c1['targetValueOne'], 4.10);
      expect(c1['targetValueTwo'], 4.35);
      expect(c1['zoneNumber'], isNull);

      final c2 = children[1] as Map<String, dynamic>;
      expect(c2['stepOrder'], 4);
      expect(c2['stepType'], {'stepTypeId': 4, 'stepTypeKey': 'recovery'});
      expect(
        c2['targetType'],
        {'workoutTargetTypeId': 1, 'workoutTargetTypeKey': 'no.target'},
      );

      // Step 5: Cooldown
      final s5 = steps[2] as Map<String, dynamic>;
      expect(s5['stepOrder'], 5);
      expect(s5['stepType'], {'stepTypeId': 2, 'stepTypeKey': 'cooldown'});
      expect(
        s5['endCondition'],
        {'conditionTypeId': 1, 'conditionTypeKey': 'lap.button'},
      );
      expect(s5['endConditionValue'], isNull);
    });

    test('Run Threshold: steady stepType & heartRateBpm bounds + zones snapshot expansion',
        () {
      final threshold = PlannedWorkout(
        id: 'run_thr_1',
        date: '2026-11-25',
        title: 'Threshold Cruise',
        discipline: SportDiscipline.run,
        archetype: WorkoutArchetype.threshold,
        estimatedDurationMinutes: 45,
        blocks: const [
          WorkoutBlock(
            repeatCount: 1,
            step: WorkoutStep(
              kind: StepKind.warmup,
              endCondition: StepEndCondition.time,
              endValue: 600,
              targetKind: StepTargetKind.heartRateZone,
              targetLow: 1,
              targetHigh: 2,
            ),
          ),
          WorkoutBlock(
            repeatCount: 1,
            step: WorkoutStep(
              kind: StepKind.steady,
              endCondition: StepEndCondition.time,
              endValue: 1200,
              targetKind: StepTargetKind.heartRateBpm,
              // Intentionally inverted to verify normalization
              targetLow: 174,
              targetHigh: 165,
            ),
          ),
        ],
      );

      const zones = AthleteZonesSnapshot(
        maxHr: 190,
        lthr: 171,
        hrZones: [
          HrZoneRange(zone: 1, label: 'Recovery', lowBpm: 110, highBpm: 138),
          HrZoneRange(zone: 2, label: 'Aerobic', lowBpm: 139, highBpm: 152),
        ],
      );

      final payload = GarminWorkoutSerializer.serialize(threshold, zones: zones);
      final steps = (payload['workoutSegments'] as List).first['workoutSteps']
          as List;

      final warmup = steps[0] as Map<String, dynamic>;
      // With AthleteZonesSnapshot, zone 1..2 expands to exact BPM bounds and zoneNumber: null
      expect(warmup['targetValueOne'], 110.0);
      expect(warmup['targetValueTwo'], 152.0);
      expect(warmup['zoneNumber'], isNull);

      final main = steps[1] as Map<String, dynamic>;
      expect(main['stepOrder'], 2);
      expect(main['stepType'], {'stepTypeId': 3, 'stepTypeKey': 'interval'});
      expect(
        main['targetType'],
        {'workoutTargetTypeId': 4, 'workoutTargetTypeKey': 'heart.rate.zone'},
      );
      expect(main['targetValueOne'], 165.0);
      expect(main['targetValueTwo'], 174.0);
      expect(main['zoneNumber'], isNull);
    });

    test('Swim Long: poolLength, poolLengthUnit, strokeTypes & rest step', () {
      final swimLong = PlannedWorkout(
        id: 'swim_long_1',
        date: '2026-11-26',
        title: 'Aerobic Endurance Swim',
        discipline: SportDiscipline.swim,
        archetype: WorkoutArchetype.long,
        estimatedDurationMinutes: 60,
        estimatedDistanceKm: 3.0,
        blocks: const [
          WorkoutBlock(
            repeatCount: 1,
            step: WorkoutStep(
              kind: StepKind.warmup,
              endCondition: StepEndCondition.distance,
              endValue: 400,
              targetKind: StepTargetKind.none,
              strokeType: 'drill',
            ),
          ),
          WorkoutBlock(
            repeatCount: 4,
            steps: [
              WorkoutStep(
                kind: StepKind.steady,
                endCondition: StepEndCondition.distance,
                endValue: 500,
                targetKind: StepTargetKind.paceMps,
                targetLow: 0.90,
                targetHigh: 0.95,
                strokeType: 'freestyle',
              ),
              WorkoutStep(
                kind: StepKind.rest,
                endCondition: StepEndCondition.time,
                endValue: 20,
                targetKind: StepTargetKind.none,
              ),
            ],
          ),
        ],
      );

      final payload = GarminWorkoutSerializer.serialize(
        swimLong,
        poolLengthMeters: 50.0,
      );
      expect(payload['sportType'], {'sportTypeId': 4, 'sportTypeKey': 'swimming'});
      expect(payload['poolLength'], 50.0);
      expect(
        payload['poolLengthUnit'],
        {'unitId': 1, 'unitKey': 'meter', 'factor': 100.0},
      );

      final steps = (payload['workoutSegments'] as List).first['workoutSteps']
          as List;
      final s1 = steps[0] as Map<String, dynamic>;
      expect(s1['strokeType'], {'strokeTypeId': 4, 'strokeTypeKey': 'drill'});

      final repeat = steps[1] as Map<String, dynamic>;
      expect(repeat['stepOrder'], 2);
      final children = repeat['workoutSteps'] as List;
      expect(children[0]['stepOrder'], 3);
      expect(
        children[0]['strokeType'],
        {'strokeTypeId': 6, 'strokeTypeKey': 'free'},
      );
      expect(children[1]['stepOrder'], 4);
      expect(children[1]['stepType'], {'stepTypeId': 5, 'stepTypeKey': 'rest'});
      expect(
        children[1]['strokeType'],
        {'strokeTypeId': 0, 'strokeTypeKey': null},
      );
    });

    test('Brick Run-leg serialization handles empty blocks fallback and overrideWorkout',
        () {
      final brick = PlannedWorkout(
        id: 'brick_1',
        date: '2026-11-28',
        title: 'Saturday Brick',
        discipline: SportDiscipline.bike,
        archetype: WorkoutArchetype.brick,
        estimatedDurationMinutes: 110,
        brickRunLeg: PlannedWorkout(
          id: 'brick_1_run',
          date: '2026-11-28',
          title: 'T2 Transition Run',
          discipline: SportDiscipline.run,
          archetype: WorkoutArchetype.easy,
          estimatedDurationMinutes: 20,
          blocks: const [],
        ),
      );

      final payload = GarminWorkoutSerializer.serialize(brick);
      expect(payload['workoutName'], 'T2 Transition Run');
      expect(payload['sportType'], {'sportTypeId': 1, 'sportTypeKey': 'running'});
      final steps = (payload['workoutSegments'] as List).first['workoutSteps']
          as List;
      expect(steps, hasLength(1));
      expect(steps[0]['stepOrder'], 1);
      expect(
        steps[0]['endCondition'],
        {'conditionTypeId': 2, 'conditionTypeKey': 'time'},
      );
      expect(steps[0]['endConditionValue'], 1200.0);

      final customLeg = PlannedWorkout(
        id: 'override_leg',
        date: '2026-11-28',
        title: 'Custom Brick Run',
        discipline: SportDiscipline.run,
        archetype: WorkoutArchetype.threshold,
        estimatedDurationMinutes: 15,
        blocks: const [
          WorkoutBlock(
            repeatCount: 1,
            step: WorkoutStep(
              kind: StepKind.steady,
              endCondition: StepEndCondition.time,
              endValue: 900,
              targetKind: StepTargetKind.paceMps,
              targetLow: 3.9,
              targetHigh: 4.1,
            ),
          ),
        ],
      );
      final overridePayload = GarminWorkoutSerializer.serialize(
        brick,
        overrideWorkout: customLeg,
      );
      expect(overridePayload['workoutName'], 'Custom Brick Run');
      final overrideSteps = (overridePayload['workoutSegments'] as List)
          .first['workoutSteps'] as List;
      expect(overrideSteps[0]['endConditionValue'], 900.0);
    });
  });

  group('GarminService workout push endpoints (MockClient)', () {
    test('createWorkout sends POST JSON and extracts numeric workoutId', () async {
      final service = GarminService(
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(
            request.url.toString(),
            'https://connectapi.garmin.com/workout-service/workout',
          );
          expect(request.headers['Authorization'], 'Bearer bearer_garmin_123');
          expect(request.headers['DI-Backend'], 'connectapi.garmin.com');
          expect(request.headers['Content-Type'], startsWith('application/json'));
          final decoded = jsonDecode(request.body) as Map<String, dynamic>;
          expect(decoded['workoutName'], 'Threshold Run');
          return http.Response(jsonEncode({'workoutId': 987654321}), 200);
        }),
      );

      final id = await service.createWorkout(
        _fakeGarminSession(),
        {'workoutName': 'Threshold Run'},
      );
      expect(id, '987654321');
    });

    test('createWorkout throws GarminUnauthorizedException on 401 and GarminAuthException on 500 or missing ID',
        () async {
      final s401 = GarminService(
        client: MockClient((_) async => http.Response('Unauthorized', 401)),
      );
      await expectLater(
        s401.createWorkout(_fakeGarminSession(), {'workoutName': 'Test'}),
        throwsA(isA<GarminUnauthorizedException>()),
      );

      final s500 = GarminService(
        client: MockClient((_) async => http.Response('Server Error', 500)),
      );
      await expectLater(
        s500.createWorkout(_fakeGarminSession(), {'workoutName': 'Test'}),
        throwsA(isA<GarminAuthException>()),
      );

      final sMissing = GarminService(
        client: MockClient((_) async => http.Response(jsonEncode({}), 200)),
      );
      await expectLater(
        sMissing.createWorkout(_fakeGarminSession(), {'workoutName': 'Test'}),
        throwsA(isA<GarminAuthException>()),
      );
    });

    test('scheduleWorkout sends YYYY-MM-DD date payload and extracts workoutScheduleId',
        () async {
      final service = GarminService(
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(
            request.url.toString(),
            'https://connectapi.garmin.cn/workout-service/schedule/987654321',
          );
          expect(request.headers['Content-Type'], startsWith('application/json'));
          expect(request.headers['DI-Backend'], 'connectapi.garmin.cn');
          expect(jsonDecode(request.body), {'date': '2026-11-28'});
          return http.Response(
            jsonEncode({'workoutScheduleId': 555666777}),
            200,
          );
        }),
      );

      final scheduleId = await service.scheduleWorkout(
        _fakeGarminSession(domain: 'garmin.cn'),
        '987654321',
        DateTime(2026, 11, 28),
      );
      expect(scheduleId, '555666777');
    });

    test('scheduleWorkout handles 401, empty workoutId, and non-2xx errors',
        () async {
      final s401 = GarminService(
        client: MockClient((_) async => http.Response('Unauthorized', 401)),
      );
      await expectLater(
        s401.scheduleWorkout(_fakeGarminSession(), '123', DateTime(2026, 11, 28)),
        throwsA(isA<GarminUnauthorizedException>()),
      );
      await expectLater(
        s401.scheduleWorkout(_fakeGarminSession(), '  ', DateTime(2026, 11, 28)),
        throwsA(isA<GarminAuthException>()),
      );

      final s400 = GarminService(
        client: MockClient((_) async => http.Response('Bad Request', 400)),
      );
      await expectLater(
        s400.scheduleWorkout(_fakeGarminSession(), '123', DateTime(2026, 11, 28)),
        throwsA(isA<GarminAuthException>()),
      );
    });

    test('deleteScheduledWorkout deletes schedule then workout, ignores 404, and throws on 401/500',
        () async {
      final calls = <String>[];
      final service = GarminService(
        client: MockClient((request) async {
          calls.add('${request.method} ${request.url.path}');
          if (request.url.path.endsWith('/schedule/sched_1')) {
            return http.Response('', 204);
          }
          if (request.url.path.endsWith('/workout/wo_1')) {
            return http.Response('Not Found', 404);
          }
          return http.Response('Unexpected', 500);
        }),
      );

      // No-op when both null/empty
      await service.deleteScheduledWorkout(_fakeGarminSession());
      expect(calls, isEmpty);

      // Deletes schedule (204) and workout (404 idempotent)
      await service.deleteScheduledWorkout(
        _fakeGarminSession(),
        scheduleId: 'sched_1',
        workoutId: 'wo_1',
      );
      expect(calls, [
        'DELETE /workout-service/schedule/sched_1',
        'DELETE /workout-service/workout/wo_1',
      ]);

      final s401 = GarminService(
        client: MockClient((_) async => http.Response('', 401)),
      );
      await expectLater(
        s401.deleteScheduledWorkout(
          _fakeGarminSession(),
          scheduleId: 'sched_1',
        ),
        throwsA(isA<GarminUnauthorizedException>()),
      );

      final s500 = GarminService(
        client: MockClient((_) async => http.Response('', 500)),
      );
      await expectLater(
        s500.deleteScheduledWorkout(
          _fakeGarminSession(),
          workoutId: 'wo_1',
        ),
        throwsA(isA<GarminAuthException>()),
      );
    });
  });

  group('GarminWorkoutSerializer depth-first multi-repeat & edge cases', () {
    test('multi-repeat depth-first stepOrder 1..8 and target/endCondition fallbacks',
        () {
      final multiRepeat = PlannedWorkout(
        id: 'multi_rep_1',
        date: '2026-11-29',
        title: 'Pyramid Run',
        discipline: SportDiscipline.run,
        archetype: WorkoutArchetype.intervals,
        estimatedDurationMinutes: 60,
        blocks: const [
          WorkoutBlock(
            repeatCount: 1,
            step: WorkoutStep(
              kind: StepKind.warmup,
              endCondition: StepEndCondition.time,
              endValue: 0, // invalid <= 0 -> falls back to lap.button
              targetKind: StepTargetKind.none,
            ),
          ),
          WorkoutBlock(
            repeatCount: 3,
            steps: [
              WorkoutStep(
                kind: StepKind.interval,
                endCondition: StepEndCondition.distance,
                endValue: 400,
                targetKind: StepTargetKind.paceMps,
                // Single bound -> mirrored to both targetValueOne/Two
                targetLow: 4.5,
              ),
              WorkoutStep(
                kind: StepKind.recovery,
                endCondition: StepEndCondition.time,
                endValue: 90,
                targetKind: StepTargetKind.heartRateZone,
                targetLow: 1,
                targetHigh: 2,
              ),
            ],
          ),
          WorkoutBlock(
            repeatCount: 2,
            steps: [
              WorkoutStep(
                kind: StepKind.interval,
                endCondition: StepEndCondition.distance,
                endValue: 800,
                targetKind: StepTargetKind.paceMps,
                // Inverted bounds -> swapped
                targetLow: 4.3,
                targetHigh: 4.0,
              ),
              WorkoutStep(
                kind: StepKind.recovery,
                endCondition: StepEndCondition.time,
                endValue: 120,
                targetKind: StepTargetKind.heartRateBpm,
                // Missing bounds -> falls back to no.target
              ),
            ],
          ),
          WorkoutBlock(
            repeatCount: 1,
            step: WorkoutStep(
              kind: StepKind.cooldown,
              endCondition: StepEndCondition.lapButton,
              targetKind: StepTargetKind.none,
            ),
          ),
        ],
      );

      final payload = GarminWorkoutSerializer.serialize(multiRepeat);
      final steps = (payload['workoutSegments'] as List).first['workoutSteps']
          as List;
      expect(steps, hasLength(4));

      expect(steps[0]['stepOrder'], 1);
      expect(
        steps[0]['endCondition'],
        {'conditionTypeId': 1, 'conditionTypeKey': 'lap.button'},
      );
      expect(steps[0]['endConditionValue'], isNull);

      expect(steps[1]['stepOrder'], 2);
      expect(steps[1]['workoutSteps'][0]['stepOrder'], 3);
      expect(steps[1]['workoutSteps'][0]['targetValueOne'], 4.5);
      expect(steps[1]['workoutSteps'][0]['targetValueTwo'], 4.5);
      expect(steps[1]['workoutSteps'][1]['stepOrder'], 4);
      expect(steps[1]['workoutSteps'][1]['zoneNumber'], 2);
      expect(steps[1]['workoutSteps'][1]['targetValueOne'], isNull);

      expect(steps[2]['stepOrder'], 5);
      expect(steps[2]['workoutSteps'][0]['stepOrder'], 6);
      expect(steps[2]['workoutSteps'][0]['targetValueOne'], 4.0);
      expect(steps[2]['workoutSteps'][0]['targetValueTwo'], 4.3);
      expect(steps[2]['workoutSteps'][1]['stepOrder'], 7);
      expect(
        steps[2]['workoutSteps'][1]['targetType'],
        {'workoutTargetTypeId': 1, 'workoutTargetTypeKey': 'no.target'},
      );

      expect(steps[3]['stepOrder'], 8);
    });

    test('WorkoutBlock with repeatCount > 1 and single step emits RepeatGroupDTO',
        () {
      final singleStepRepeat = PlannedWorkout(
        id: 'single_step_repeat',
        date: '2026-11-29',
        title: '4x400m Strides',
        discipline: SportDiscipline.run,
        archetype: WorkoutArchetype.intervals,
        estimatedDurationMinutes: 25,
        blocks: const [
          WorkoutBlock(
            repeatCount: 4,
            step: WorkoutStep(
              kind: StepKind.interval,
              endCondition: StepEndCondition.distance,
              endValue: 400,
              targetKind: StepTargetKind.none,
            ),
          ),
        ],
      );

      final payload = GarminWorkoutSerializer.serialize(singleStepRepeat);
      final steps = (payload['workoutSegments'] as List).first['workoutSteps']
          as List;
      expect(steps, hasLength(1));

      final group = steps[0] as Map<String, dynamic>;
      expect(group['type'], 'RepeatGroupDTO');
      expect(group['stepOrder'], 1);
      expect(group['numberOfIterations'], 4);
      expect(group['endConditionValue'], 4.0);

      final children = group['workoutSteps'] as List;
      expect(children, hasLength(1));
      expect(children[0]['type'], 'ExecutableStepDTO');
      expect(children[0]['stepOrder'], 2);
      expect(children[0]['endConditionValue'], 400.0);
    });

    test('heartRateZone with zero or negative bounds falls back to no.target',
        () {
      final invalidZones = PlannedWorkout(
        id: 'hr_zone_invalid',
        date: '2026-11-29',
        title: 'HR Zone Bounds Check',
        discipline: SportDiscipline.run,
        archetype: WorkoutArchetype.easy,
        estimatedDurationMinutes: 30,
        blocks: const [
          WorkoutBlock(
            repeatCount: 1,
            step: WorkoutStep(
              kind: StepKind.steady,
              endCondition: StepEndCondition.time,
              endValue: 300,
              targetKind: StepTargetKind.heartRateZone,
              targetLow: -2,
              targetHigh: 0,
            ),
          ),
          WorkoutBlock(
            repeatCount: 1,
            step: WorkoutStep(
              kind: StepKind.steady,
              endCondition: StepEndCondition.time,
              endValue: 300,
              targetKind: StepTargetKind.heartRateZone,
              targetLow: 0,
              targetHigh: 2,
            ),
          ),
        ],
      );

      final payload = GarminWorkoutSerializer.serialize(invalidZones);
      final steps = (payload['workoutSegments'] as List).first['workoutSteps']
          as List;
      expect(steps, hasLength(2));

      expect(
        steps[0]['targetType'],
        {'workoutTargetTypeId': 1, 'workoutTargetTypeKey': 'no.target'},
      );
      expect(steps[0]['zoneNumber'], isNull);

      expect(
        steps[1]['targetType'],
        {'workoutTargetTypeId': 4, 'workoutTargetTypeKey': 'heart.rate.zone'},
      );
      expect(steps[1]['zoneNumber'], 2);
    });
  });
}
