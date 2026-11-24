import 'activity.dart';

enum WorkoutArchetype {
  intervals,
  threshold,
  easy,
  long,
  zwiftRide,
  brick,
  strength,
  rest,
}

enum WorkoutStatus {
  scheduled,
  completed,
  skipped,
}

enum StepKind {
  warmup,
  interval,
  recovery,
  cooldown,
  rest,
  steady,
}

enum StepEndCondition {
  time,
  distance,
  lapButton,
}

enum StepTargetKind {
  none,
  heartRateBpm,
  heartRateZone,
  paceMps,
}

enum CoachMessageRole {
  user,
  assistant,
  system,
}

// ---------------------------------------------------------------------------
// Defensive JSON parsing helpers (tolerant of LLM output variations)
// ---------------------------------------------------------------------------

double? _asDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) {
    final d = v.toDouble();
    return d.isFinite ? d : null;
  }
  if (v is String) {
    final parsed = double.tryParse(v.trim());
    if (parsed != null && parsed.isFinite) return parsed;
  }
  return null;
}

double? _finiteOrNull(double? v) => (v != null && v.isFinite) ? v : null;

double _finiteOrDefault(double v, double fallback) =>
    v.isFinite ? v : fallback;

int? _asInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) {
    final d = v.toDouble();
    return d.isFinite ? d.round() : null;
  }
  if (v is String) {
    final trimmed = v.trim();
    final asInt = int.tryParse(trimmed);
    if (asInt != null) return asInt;
    final asDouble = double.tryParse(trimmed);
    if (asDouble != null && asDouble.isFinite) return asDouble.round();
  }
  return null;
}

String _asString(dynamic v, [String fallback = '']) {
  if (v == null) return fallback;
  if (v is String) return v;
  return v.toString();
}

String _asNonEmptyString(dynamic v, [String fallback = '']) {
  if (v == null) return fallback;
  final s = (v is String ? v : v.toString()).trim();
  return s.isEmpty ? fallback : s;
}

String? _asNullableString(dynamic v) {
  if (v == null) return null;
  final s = v is String ? v : v.toString();
  final trimmed = s.trim();
  return trimmed.isEmpty ? null : trimmed;
}

List<String> _asStringList(dynamic v) {
  if (v is! List) return const [];
  final result = <String>[];
  for (final item in v) {
    if (item == null) continue;
    final s = item.toString().trim();
    if (s.isNotEmpty) result.add(s);
  }
  return result;
}

List<Map<String, dynamic>> _asMapList(dynamic v) {
  if (v is! List) return const [];
  final result = <Map<String, dynamic>>[];
  for (final item in v) {
    if (item is Map<String, dynamic>) {
      result.add(item);
    } else if (item is Map) {
      result.add(Map<String, dynamic>.from(item));
    }
  }
  return result;
}

Map<String, dynamic>? _asMap(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return Map<String, dynamic>.from(v);
  return null;
}

String _normalizeEnumToken(String raw) {
  return raw
      .trim()
      .toLowerCase()
      .replaceAll('_', '')
      .replaceAll('-', '')
      .replaceAll('.', '')
      .replaceAll(' ', '');
}

T _parseEnum<T extends Enum>(
  dynamic v,
  List<T> values,
  T fallback, {
  Map<String, T> aliases = const {},
}) {
  if (v == null) return fallback;
  final token = _normalizeEnumToken(v.toString());
  if (token.isEmpty) return fallback;

  for (final value in values) {
    if (_normalizeEnumToken(value.name) == token) {
      return value;
    }
  }

  for (final entry in aliases.entries) {
    if (_normalizeEnumToken(entry.key) == token) {
      return entry.value;
    }
  }

  return fallback;
}

String _normalizeDate(dynamic v, [String fallback = '']) {
  if (v == null) return fallback;
  final raw = v.toString().trim();
  if (raw.isEmpty) return fallback;

  final match =
      RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})(?:$|[^\d])').firstMatch(raw);
  if (match != null) {
    final year = int.tryParse(match.group(1)!);
    final month = int.tryParse(match.group(2)!);
    final day = int.tryParse(match.group(3)!);
    if (year != null &&
        month != null &&
        day != null &&
        month >= 1 &&
        month <= 12 &&
        day >= 1 &&
        day <= 31) {
      final dt = DateTime(year, month, day);
      if (dt.year == year && dt.month == month && dt.day == day) {
        return '${year.toString().padLeft(4, '0')}-'
            '${month.toString().padLeft(2, '0')}-'
            '${day.toString().padLeft(2, '0')}';
      }
    }
    return fallback;
  }

  final parsed = DateTime.tryParse(raw);
  if (parsed != null) {
    return PlannedWorkout.formatLocalDate(parsed);
  }
  return fallback;
}

DateTime _parseDateTime(dynamic v, DateTime fallback) {
  if (v is DateTime) return v;
  if (v is String && v.trim().isNotEmpty) {
    final parsed = DateTime.tryParse(v.trim());
    if (parsed != null) return parsed;
  }
  return fallback;
}

DateTime? _parseNullableDateTime(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is String && v.trim().isNotEmpty) {
    return DateTime.tryParse(v.trim());
  }
  return null;
}

SportDiscipline _parseDiscipline(dynamic v,
    {SportDiscipline fallback = SportDiscipline.run}) {
  return _parseEnum<SportDiscipline>(
    v,
    SportDiscipline.values,
    fallback,
    aliases: const {
      'swimming': SportDiscipline.swim,
      'poolswim': SportDiscipline.swim,
      'openwater': SportDiscipline.swim,
      'openwaterswim': SportDiscipline.swim,
      'cycling': SportDiscipline.bike,
      'biking': SportDiscipline.bike,
      'roadbike': SportDiscipline.bike,
      'indoorcycling': SportDiscipline.indoorBike,
      'virtualride': SportDiscipline.indoorBike,
      'zwift': SportDiscipline.indoorBike,
      'zwiftride': SportDiscipline.indoorBike,
      'trainer': SportDiscipline.indoorBike,
      'running': SportDiscipline.run,
      'treadmill': SportDiscipline.run,
      'trailrun': SportDiscipline.run,
      'weights': SportDiscipline.strength,
      'gym': SportDiscipline.strength,
      'mobility': SportDiscipline.strength,
    },
  );
}

WorkoutArchetype _parseArchetype(dynamic v,
    {WorkoutArchetype fallback = WorkoutArchetype.easy}) {
  return _parseEnum<WorkoutArchetype>(
    v,
    WorkoutArchetype.values,
    fallback,
    aliases: const {
      'interval': WorkoutArchetype.intervals,
      'vo2': WorkoutArchetype.intervals,
      'vo2max': WorkoutArchetype.intervals,
      'speed': WorkoutArchetype.intervals,
      'tempo': WorkoutArchetype.threshold,
      'lt': WorkoutArchetype.threshold,
      'lactatethreshold': WorkoutArchetype.threshold,
      'recovery': WorkoutArchetype.easy,
      'aerobic': WorkoutArchetype.easy,
      'endurance': WorkoutArchetype.easy,
      'longrun': WorkoutArchetype.long,
      'longride': WorkoutArchetype.long,
      'longswim': WorkoutArchetype.long,
      'zwift': WorkoutArchetype.zwiftRide,
      'cycling': WorkoutArchetype.zwiftRide,
      'bike': WorkoutArchetype.zwiftRide,
      'ride': WorkoutArchetype.zwiftRide,
      'indoorbike': WorkoutArchetype.zwiftRide,
      'bikerun': WorkoutArchetype.brick,
      'restday': WorkoutArchetype.rest,
      'off': WorkoutArchetype.rest,
    },
  );
}

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

class HrZoneRange {
  final int zone;
  final String label;
  final int lowBpm;
  final int highBpm;

  const HrZoneRange({
    required this.zone,
    required this.label,
    required this.lowBpm,
    required this.highBpm,
  });

  HrZoneRange copyWith({
    int? zone,
    String? label,
    int? lowBpm,
    int? highBpm,
  }) {
    return HrZoneRange(
      zone: zone ?? this.zone,
      label: label ?? this.label,
      lowBpm: lowBpm ?? this.lowBpm,
      highBpm: highBpm ?? this.highBpm,
    );
  }

  Map<String, dynamic> toJson() => {
        'zone': zone,
        'label': label,
        'lowBpm': lowBpm,
        'highBpm': highBpm,
      };

  factory HrZoneRange.fromJson(Map<String, dynamic> json) {
    final clampedLow = (_asInt(json['lowBpm']) ?? 0).clamp(0, 250);
    final clampedHigh =
        (_asInt(json['highBpm']) ?? clampedLow).clamp(0, 250);
    final low = clampedLow <= clampedHigh ? clampedLow : clampedHigh;
    final high = clampedLow <= clampedHigh ? clampedHigh : clampedLow;
    return HrZoneRange(
      zone: (_asInt(json['zone']) ?? 1).clamp(1, 5),
      label: _asNonEmptyString(json['label'], 'Zone'),
      lowBpm: low,
      highBpm: high,
    );
  }
}

class AthleteZonesSnapshot {
  static const double metersToYards = 1.09361;

  final int maxHr;
  final int lthr;
  final List<HrZoneRange> hrZones;
  final double? runThresholdPaceSecPerKm;
  final double? swimCssSecPer100m;
  final int? bikeFtpWatts;

  const AthleteZonesSnapshot({
    this.maxHr = 190,
    this.lthr = 171,
    this.hrZones = const [],
    this.runThresholdPaceSecPerKm,
    this.swimCssSecPer100m,
    this.bikeFtpWatts,
  });

  double? get runThresholdSpeedMps {
    final pace = runThresholdPaceSecPerKm;
    if (pace == null || !pace.isFinite || pace <= 0) return null;
    return 1000.0 / pace;
  }

  double? get swimCssSecPer100yd {
    final css = swimCssSecPer100m;
    if (css == null || !css.isFinite || css <= 0) return null;
    return css / metersToYards;
  }

  AthleteZonesSnapshot copyWith({
    int? maxHr,
    int? lthr,
    List<HrZoneRange>? hrZones,
    double? runThresholdPaceSecPerKm,
    bool clearRunThresholdPace = false,
    double? swimCssSecPer100m,
    bool clearSwimCss = false,
    int? bikeFtpWatts,
    bool clearBikeFtp = false,
  }) {
    return AthleteZonesSnapshot(
      maxHr: maxHr ?? this.maxHr,
      lthr: lthr ?? this.lthr,
      hrZones: hrZones ?? this.hrZones,
      runThresholdPaceSecPerKm: clearRunThresholdPace
          ? null
          : (runThresholdPaceSecPerKm ?? this.runThresholdPaceSecPerKm),
      swimCssSecPer100m:
          clearSwimCss ? null : (swimCssSecPer100m ?? this.swimCssSecPer100m),
      bikeFtpWatts: clearBikeFtp ? null : (bikeFtpWatts ?? this.bikeFtpWatts),
    );
  }

  Map<String, dynamic> toJson() => {
        'maxHr': maxHr,
        'lthr': lthr,
        'hrZones': hrZones.map((z) => z.toJson()).toList(),
        'runThresholdPaceSecPerKm': _finiteOrNull(runThresholdPaceSecPerKm),
        'swimCssSecPer100m': _finiteOrNull(swimCssSecPer100m),
        'bikeFtpWatts': bikeFtpWatts,
      };

  factory AthleteZonesSnapshot.fromJson(Map<String, dynamic> json) {
    final parsedMaxHr = (_asInt(json['maxHr']) ?? 190).clamp(110, 230);
    final parsedLthr =
        (_asInt(json['lthr']) ?? (parsedMaxHr * 0.88).round()).clamp(90, 220);
    final runPace = _asDouble(json['runThresholdPaceSecPerKm']);
    final swimCss = _asDouble(json['swimCssSecPer100m']);
    final ftp = _asInt(json['bikeFtpWatts']);

    return AthleteZonesSnapshot(
      maxHr: parsedMaxHr,
      lthr: parsedLthr,
      hrZones: _asMapList(json['hrZones']).map(HrZoneRange.fromJson).toList(),
      runThresholdPaceSecPerKm:
          (runPace != null && runPace > 0) ? runPace : null,
      swimCssSecPer100m: (swimCss != null && swimCss > 0) ? swimCss : null,
      bikeFtpWatts: (ftp != null && ftp > 0) ? ftp.clamp(20, 1000) : null,
    );
  }
}

class WorkoutStep {
  final StepKind kind;
  final StepEndCondition endCondition;
  final double? endValue;
  final StepTargetKind targetKind;
  final double? targetLow;
  final double? targetHigh;
  final String? notes;
  final String? strokeType;

  const WorkoutStep({
    required this.kind,
    required this.endCondition,
    this.endValue,
    this.targetKind = StepTargetKind.none,
    this.targetLow,
    this.targetHigh,
    this.notes,
    this.strokeType,
  });

  WorkoutStep copyWith({
    StepKind? kind,
    StepEndCondition? endCondition,
    double? endValue,
    bool clearEndValue = false,
    StepTargetKind? targetKind,
    double? targetLow,
    bool clearTargetLow = false,
    double? targetHigh,
    bool clearTargetHigh = false,
    String? notes,
    bool clearNotes = false,
    String? strokeType,
    bool clearStrokeType = false,
  }) {
    return WorkoutStep(
      kind: kind ?? this.kind,
      endCondition: endCondition ?? this.endCondition,
      endValue: clearEndValue ? null : (endValue ?? this.endValue),
      targetKind: targetKind ?? this.targetKind,
      targetLow: clearTargetLow ? null : (targetLow ?? this.targetLow),
      targetHigh: clearTargetHigh ? null : (targetHigh ?? this.targetHigh),
      notes: clearNotes ? null : (notes ?? this.notes),
      strokeType: clearStrokeType ? null : (strokeType ?? this.strokeType),
    );
  }

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'endCondition': endCondition.name,
        'endValue': _finiteOrNull(endValue),
        'targetKind': targetKind.name,
        'targetLow': _finiteOrNull(targetLow),
        'targetHigh': _finiteOrNull(targetHigh),
        'notes': notes,
        'strokeType': strokeType,
      };

  factory WorkoutStep.fromJson(Map<String, dynamic> json) {
    final kind = _parseEnum<StepKind>(
      json['kind'],
      StepKind.values,
      StepKind.steady,
      aliases: const {
        'warmup': StepKind.warmup,
        'warm': StepKind.warmup,
        'cooldown': StepKind.cooldown,
        'cool': StepKind.cooldown,
        'work': StepKind.interval,
        'active': StepKind.interval,
        'main': StepKind.interval,
        'endurance': StepKind.steady,
        'easy': StepKind.steady,
      },
    );

    final endCondition = _parseEnum<StepEndCondition>(
      json['endCondition'],
      StepEndCondition.values,
      StepEndCondition.time,
      aliases: const {
        'duration': StepEndCondition.time,
        'seconds': StepEndCondition.time,
        'lapbutton': StepEndCondition.lapButton,
        'open': StepEndCondition.lapButton,
        'meters': StepEndCondition.distance,
        'distancem': StepEndCondition.distance,
      },
    );

    final rawEndValue = _asDouble(json['endValue']);
    final double? endValue;
    if (endCondition == StepEndCondition.lapButton) {
      endValue = null;
    } else if (rawEndValue != null) {
      endValue = rawEndValue < 0 ? 0.0 : rawEndValue;
    } else {
      endValue = null;
    }

    final targetKind = _parseEnum<StepTargetKind>(
      json['targetKind'],
      StepTargetKind.values,
      StepTargetKind.none,
      aliases: const {
        'notarget': StepTargetKind.none,
        'open': StepTargetKind.none,
        'heartratebpm': StepTargetKind.heartRateBpm,
        'hrbpm': StepTargetKind.heartRateBpm,
        'hr': StepTargetKind.heartRateBpm,
        'heartrate': StepTargetKind.heartRateBpm,
        'heartratezone': StepTargetKind.heartRateZone,
        'hrzone': StepTargetKind.heartRateZone,
        'zone': StepTargetKind.heartRateZone,
        'pacemps': StepTargetKind.paceMps,
        'pacezone': StepTargetKind.paceMps,
        'pace': StepTargetKind.paceMps,
        'speed': StepTargetKind.paceMps,
      },
    );

    var targetLow = _asDouble(json['targetLow']);
    var targetHigh = _asDouble(json['targetHigh']);
    if (targetKind == StepTargetKind.none) {
      targetLow = null;
      targetHigh = null;
    } else {
      if (targetLow != null && targetLow < 0) targetLow = null;
      if (targetHigh != null && targetHigh < 0) targetHigh = null;
      if (targetLow != null && targetHigh != null && targetLow > targetHigh) {
        final tmp = targetLow;
        targetLow = targetHigh;
        targetHigh = tmp;
      }
    }

    return WorkoutStep(
      kind: kind,
      endCondition: endCondition,
      endValue: endValue,
      targetKind: targetKind,
      targetLow: targetLow,
      targetHigh: targetHigh,
      notes: _asNullableString(json['notes']),
      strokeType: _asNullableString(json['strokeType']),
    );
  }
}

class WorkoutBlock {
  final int repeatCount;
  final WorkoutStep? step;
  final List<WorkoutStep> steps;

  const WorkoutBlock({
    this.repeatCount = 1,
    this.step,
    this.steps = const [],
  });

  bool get isRepeat => repeatCount > 1 && steps.isNotEmpty;

  List<WorkoutStep> get effectiveSteps {
    if (step != null) return [step!];
    return steps;
  }

  WorkoutBlock copyWith({
    int? repeatCount,
    WorkoutStep? step,
    bool clearStep = false,
    List<WorkoutStep>? steps,
  }) {
    return WorkoutBlock(
      repeatCount: repeatCount ?? this.repeatCount,
      step: clearStep ? null : (step ?? this.step),
      steps: steps ?? this.steps,
    );
  }

  Map<String, dynamic> toJson() => {
        'repeatCount': repeatCount,
        'step': step?.toJson(),
        'steps': steps.map((s) => s.toJson()).toList(),
      };

  factory WorkoutBlock.fromJson(Map<String, dynamic> json) {
    final repeatCount = (_asInt(json['repeatCount']) ?? 1).clamp(1, 100);

    final stepMap = _asMap(json['step']);
    WorkoutStep? singleStep =
        stepMap != null ? WorkoutStep.fromJson(stepMap) : null;
    var groupSteps =
        _asMapList(json['steps']).map(WorkoutStep.fromJson).toList();

    if (repeatCount > 1 && groupSteps.isEmpty && singleStep != null) {
      groupSteps = [singleStep];
      singleStep = null;
    } else if (repeatCount == 1 &&
        singleStep == null &&
        groupSteps.length == 1) {
      singleStep = groupSteps.first;
      groupSteps = const [];
    } else if (repeatCount > 1 && groupSteps.isNotEmpty) {
      singleStep = null;
    }

    return WorkoutBlock(
      repeatCount: repeatCount,
      step: singleStep,
      steps: groupSteps,
    );
  }
}

class ZwiftPrescription {
  final int durationMinutes;
  final String difficulty;
  final int targetTss;
  final String zwiftCategory;
  final List<String> suggestedSearchTerms;
  final String? cadenceFocus;
  final String? notes;

  const ZwiftPrescription({
    required this.durationMinutes,
    required this.difficulty,
    required this.targetTss,
    required this.zwiftCategory,
    this.suggestedSearchTerms = const [],
    this.cadenceFocus,
    this.notes,
  });

  ZwiftPrescription copyWith({
    int? durationMinutes,
    String? difficulty,
    int? targetTss,
    String? zwiftCategory,
    List<String>? suggestedSearchTerms,
    String? cadenceFocus,
    bool clearCadenceFocus = false,
    String? notes,
    bool clearNotes = false,
  }) {
    return ZwiftPrescription(
      durationMinutes: durationMinutes ?? this.durationMinutes,
      difficulty: difficulty ?? this.difficulty,
      targetTss: targetTss ?? this.targetTss,
      zwiftCategory: zwiftCategory ?? this.zwiftCategory,
      suggestedSearchTerms: suggestedSearchTerms ?? this.suggestedSearchTerms,
      cadenceFocus:
          clearCadenceFocus ? null : (cadenceFocus ?? this.cadenceFocus),
      notes: clearNotes ? null : (notes ?? this.notes),
    );
  }

  Map<String, dynamic> toJson() => {
        'durationMinutes': durationMinutes,
        'difficulty': difficulty,
        'targetTss': targetTss,
        'zwiftCategory': zwiftCategory,
        'suggestedSearchTerms': suggestedSearchTerms,
        'cadenceFocus': cadenceFocus,
        'notes': notes,
      };

  factory ZwiftPrescription.fromJson(Map<String, dynamic> json) {
    final duration = (_asInt(json['durationMinutes']) ?? 60).clamp(1, 600);
    final tss = (_asInt(json['targetTss']) ?? 50).clamp(0, 1000);
    return ZwiftPrescription(
      durationMinutes: duration,
      difficulty: _asNonEmptyString(json['difficulty'], 'Endurance'),
      targetTss: tss,
      zwiftCategory: _asNonEmptyString(json['zwiftCategory'], 'Endurance'),
      suggestedSearchTerms: _asStringList(json['suggestedSearchTerms']),
      cadenceFocus: _asNullableString(json['cadenceFocus']),
      notes: _asNullableString(json['notes']),
    );
  }
}

class PlannedWorkout {
  final String id;
  final String date;
  final String title;
  final SportDiscipline discipline;
  final WorkoutArchetype archetype;
  final int estimatedDurationMinutes;
  final double? estimatedDistanceKm;
  final double? estimatedTss;
  final String? coachNotes;
  final String? rationale;
  final List<WorkoutBlock> blocks;
  final ZwiftPrescription? zwiftPrescription;
  final PlannedWorkout? brickRunLeg;
  final WorkoutStatus status;
  final String? matchedActivityId;
  final double? adherencePercent;
  final String? garminWorkoutId;
  final String? garminScheduleId;
  final DateTime? garminSyncedAt;

  PlannedWorkout({
    required this.id,
    required String date,
    required this.title,
    required this.discipline,
    required this.archetype,
    required int estimatedDurationMinutes,
    this.estimatedDistanceKm,
    this.estimatedTss,
    this.coachNotes,
    this.rationale,
    this.blocks = const [],
    this.zwiftPrescription,
    PlannedWorkout? brickRunLeg,
    this.status = WorkoutStatus.scheduled,
    this.matchedActivityId,
    this.adherencePercent,
    this.garminWorkoutId,
    this.garminScheduleId,
    this.garminSyncedAt,
  })  : date = _normalizeDate(date),
        estimatedDurationMinutes = estimatedDurationMinutes.clamp(0, 1440),
        brickRunLeg =
            _normalizeBrickRunLeg(id, _normalizeDate(date), brickRunLeg);

  static PlannedWorkout? _normalizeBrickRunLeg(
    String parentId,
    String parentDate,
    PlannedWorkout? leg,
  ) {
    if (leg == null) return null;
    final clampedMinutes = leg.estimatedDurationMinutes.clamp(0, 30);
    final trimmedParentId = parentId.trim();
    final fallbackLegId =
        trimmedParentId.isEmpty ? 'brick_run' : '${trimmedParentId}_run';
    final normalizedId =
        leg.id.trim().isEmpty ? fallbackLegId : leg.id.trim();
    final normalizedDate = _normalizeDate(parentDate);
    final normalizedTitle =
        leg.title.trim().isEmpty ? 'Brick Transition Run' : leg.title.trim();
    final normalizedArchetype = leg.archetype == WorkoutArchetype.brick ||
            leg.archetype == WorkoutArchetype.zwiftRide ||
            leg.archetype == WorkoutArchetype.strength ||
            leg.archetype == WorkoutArchetype.rest
        ? WorkoutArchetype.easy
        : leg.archetype;

    return PlannedWorkout._raw(
      id: normalizedId,
      date: normalizedDate,
      title: normalizedTitle,
      discipline: SportDiscipline.run,
      archetype: normalizedArchetype,
      estimatedDurationMinutes: clampedMinutes,
      estimatedDistanceKm: leg.estimatedDistanceKm,
      estimatedTss: leg.estimatedTss,
      coachNotes: leg.coachNotes,
      rationale: leg.rationale,
      blocks: leg.blocks,
      zwiftPrescription: null,
      brickRunLeg: null,
      status: leg.status,
      matchedActivityId: leg.matchedActivityId,
      adherencePercent: leg.adherencePercent,
      garminWorkoutId: leg.garminWorkoutId,
      garminScheduleId: leg.garminScheduleId,
      garminSyncedAt: leg.garminSyncedAt,
    );
  }

  const PlannedWorkout._raw({
    required this.id,
    required this.date,
    required this.title,
    required this.discipline,
    required this.archetype,
    required this.estimatedDurationMinutes,
    this.estimatedDistanceKm,
    this.estimatedTss,
    this.coachNotes,
    this.rationale,
    this.blocks = const [],
    this.zwiftPrescription,
    this.brickRunLeg,
    this.status = WorkoutStatus.scheduled,
    this.matchedActivityId,
    this.adherencePercent,
    this.garminWorkoutId,
    this.garminScheduleId,
    this.garminSyncedAt,
  });

  DateTime? get scheduledDate {
    final normalized = _normalizeDate(date);
    final parts = normalized.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    final dt = DateTime(y, m, d);
    if (dt.year != y || dt.month != m || dt.day != d) return null;
    return dt;
  }

  bool get isSyncedToGarmin =>
      garminWorkoutId != null && garminWorkoutId!.isNotEmpty;

  bool get isGarminPushable {
    if (archetype == WorkoutArchetype.zwiftRide ||
        archetype == WorkoutArchetype.strength ||
        archetype == WorkoutArchetype.rest) {
      return false;
    }
    if (archetype == WorkoutArchetype.brick) {
      return brickRunLeg != null;
    }
    return discipline == SportDiscipline.run ||
        discipline == SportDiscipline.swim;
  }

  static String formatLocalDate(DateTime dt) {
    final local = dt.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  PlannedWorkout copyWith({
    String? id,
    String? date,
    String? title,
    SportDiscipline? discipline,
    WorkoutArchetype? archetype,
    int? estimatedDurationMinutes,
    double? estimatedDistanceKm,
    bool clearEstimatedDistanceKm = false,
    double? estimatedTss,
    bool clearEstimatedTss = false,
    String? coachNotes,
    bool clearCoachNotes = false,
    String? rationale,
    bool clearRationale = false,
    List<WorkoutBlock>? blocks,
    ZwiftPrescription? zwiftPrescription,
    bool clearZwiftPrescription = false,
    PlannedWorkout? brickRunLeg,
    bool clearBrickRunLeg = false,
    WorkoutStatus? status,
    String? matchedActivityId,
    bool clearMatchedActivityId = false,
    double? adherencePercent,
    bool clearAdherencePercent = false,
    String? garminWorkoutId,
    bool clearGarminWorkoutId = false,
    String? garminScheduleId,
    bool clearGarminScheduleId = false,
    DateTime? garminSyncedAt,
    bool clearGarminSyncedAt = false,
  }) {
    return PlannedWorkout(
      id: id ?? this.id,
      date: date ?? this.date,
      title: title ?? this.title,
      discipline: discipline ?? this.discipline,
      archetype: archetype ?? this.archetype,
      estimatedDurationMinutes:
          estimatedDurationMinutes ?? this.estimatedDurationMinutes,
      estimatedDistanceKm: clearEstimatedDistanceKm
          ? null
          : (estimatedDistanceKm ?? this.estimatedDistanceKm),
      estimatedTss:
          clearEstimatedTss ? null : (estimatedTss ?? this.estimatedTss),
      coachNotes: clearCoachNotes ? null : (coachNotes ?? this.coachNotes),
      rationale: clearRationale ? null : (rationale ?? this.rationale),
      blocks: blocks ?? this.blocks,
      zwiftPrescription: clearZwiftPrescription
          ? null
          : (zwiftPrescription ?? this.zwiftPrescription),
      brickRunLeg:
          clearBrickRunLeg ? null : (brickRunLeg ?? this.brickRunLeg),
      status: status ?? this.status,
      matchedActivityId: clearMatchedActivityId
          ? null
          : (matchedActivityId ?? this.matchedActivityId),
      adherencePercent: clearAdherencePercent
          ? null
          : (adherencePercent ?? this.adherencePercent),
      garminWorkoutId: clearGarminWorkoutId
          ? null
          : (garminWorkoutId ?? this.garminWorkoutId),
      garminScheduleId: clearGarminScheduleId
          ? null
          : (garminScheduleId ?? this.garminScheduleId),
      garminSyncedAt: clearGarminSyncedAt
          ? null
          : (garminSyncedAt ?? this.garminSyncedAt),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date,
        'title': title,
        'discipline': discipline.name,
        'archetype': archetype.name,
        'estimatedDurationMinutes': estimatedDurationMinutes,
        'estimatedDistanceKm': _finiteOrNull(estimatedDistanceKm),
        'estimatedTss': _finiteOrNull(estimatedTss),
        'coachNotes': coachNotes,
        'rationale': rationale,
        'blocks': blocks.map((b) => b.toJson()).toList(),
        'zwiftPrescription': zwiftPrescription?.toJson(),
        'brickRunLeg': brickRunLeg?.toJson(),
        'status': status.name,
        'matchedActivityId': matchedActivityId,
        'adherencePercent': _finiteOrNull(adherencePercent),
        'garminWorkoutId': garminWorkoutId,
        'garminScheduleId': garminScheduleId,
        'garminSyncedAt': garminSyncedAt?.toUtc().toIso8601String(),
      };

  factory PlannedWorkout.fromJson(
    Map<String, dynamic> json, {
    String fallbackDate = '',
    String fallbackId = '',
    String fallbackTitle = 'Workout',
  }) {
    final effectiveFallbackId = fallbackId.trim().isNotEmpty
        ? fallbackId.trim()
        : 'wo_${DateTime.now().microsecondsSinceEpoch}';
    final id = _asNonEmptyString(json['id'], effectiveFallbackId);
    final date = _normalizeDate(json['date'], fallbackDate);
    final archetype = _parseArchetype(json['archetype']);

    final defaultDiscipline = switch (archetype) {
      WorkoutArchetype.zwiftRide => SportDiscipline.indoorBike,
      WorkoutArchetype.brick => SportDiscipline.bike,
      WorkoutArchetype.strength => SportDiscipline.strength,
      _ => SportDiscipline.run,
    };
    final discipline =
        _parseDiscipline(json['discipline'], fallback: defaultDiscipline);

    final zwiftMap = _asMap(json['zwiftPrescription']);
    final brickLegMap = _asMap(json['brickRunLeg']);
    final rawDuration =
        (_asInt(json['estimatedDurationMinutes']) ?? 0).clamp(0, 1440);
    final rawDistance = _asDouble(json['estimatedDistanceKm']);
    final rawTss = _asDouble(json['estimatedTss']);
    final rawAdherence = _asDouble(json['adherencePercent']);

    return PlannedWorkout(
      id: id,
      date: date,
      title: _asNonEmptyString(json['title'], fallbackTitle),
      discipline: discipline,
      archetype: archetype,
      estimatedDurationMinutes: rawDuration,
      estimatedDistanceKm:
          (rawDistance != null && rawDistance >= 0) ? rawDistance : null,
      estimatedTss: (rawTss != null && rawTss >= 0) ? rawTss : null,
      coachNotes: _asNullableString(json['coachNotes']),
      rationale: _asNullableString(json['rationale']),
      blocks: _asMapList(json['blocks']).map(WorkoutBlock.fromJson).toList(),
      zwiftPrescription:
          zwiftMap != null ? ZwiftPrescription.fromJson(zwiftMap) : null,
      brickRunLeg: brickLegMap != null
          ? PlannedWorkout.fromJson(
              brickLegMap,
              fallbackDate: date,
              fallbackId: '${id}_run',
              fallbackTitle: 'Brick Transition Run',
            )
          : null,
      status: _parseEnum<WorkoutStatus>(
        json['status'],
        WorkoutStatus.values,
        WorkoutStatus.scheduled,
        aliases: const {
          'done': WorkoutStatus.completed,
          'complete': WorkoutStatus.completed,
          'planned': WorkoutStatus.scheduled,
          'upcoming': WorkoutStatus.scheduled,
          'pending': WorkoutStatus.scheduled,
        },
      ),
      matchedActivityId: _asNullableString(json['matchedActivityId']),
      adherencePercent: rawAdherence?.clamp(0.0, 100.0).toDouble(),
      garminWorkoutId: _asNullableString(json['garminWorkoutId']),
      garminScheduleId: _asNullableString(json['garminScheduleId']),
      garminSyncedAt: _parseNullableDateTime(json['garminSyncedAt']),
    );
  }
}

class TrainingPlanConfig {
  final String raceName;
  final String raceDistance;
  final String raceDate;
  final double weeklyHoursBudget;
  final String longRunDay;
  final String longRideDay;
  final String restDay;
  final String limiterSport;
  final AthleteZonesSnapshot zones;
  final String? additionalNotes;

  const TrainingPlanConfig({
    required this.raceName,
    required this.raceDistance,
    required this.raceDate,
    required this.weeklyHoursBudget,
    required this.longRunDay,
    required this.longRideDay,
    required this.restDay,
    required this.limiterSport,
    this.zones = const AthleteZonesSnapshot(),
    this.additionalNotes,
  });

  TrainingPlanConfig copyWith({
    String? raceName,
    String? raceDistance,
    String? raceDate,
    double? weeklyHoursBudget,
    String? longRunDay,
    String? longRideDay,
    String? restDay,
    String? limiterSport,
    AthleteZonesSnapshot? zones,
    String? additionalNotes,
    bool clearAdditionalNotes = false,
  }) {
    return TrainingPlanConfig(
      raceName: raceName ?? this.raceName,
      raceDistance: raceDistance ?? this.raceDistance,
      raceDate: raceDate ?? this.raceDate,
      weeklyHoursBudget: weeklyHoursBudget ?? this.weeklyHoursBudget,
      longRunDay: longRunDay ?? this.longRunDay,
      longRideDay: longRideDay ?? this.longRideDay,
      restDay: restDay ?? this.restDay,
      limiterSport: limiterSport ?? this.limiterSport,
      zones: zones ?? this.zones,
      additionalNotes: clearAdditionalNotes
          ? null
          : (additionalNotes ?? this.additionalNotes),
    );
  }

  Map<String, dynamic> toJson() => {
        'raceName': raceName,
        'raceDistance': raceDistance,
        'raceDate': raceDate,
        'weeklyHoursBudget': _finiteOrDefault(weeklyHoursBudget, 8.0),
        'longRunDay': longRunDay,
        'longRideDay': longRideDay,
        'restDay': restDay,
        'limiterSport': limiterSport,
        'zones': zones.toJson(),
        'additionalNotes': additionalNotes,
      };

  factory TrainingPlanConfig.fromJson(Map<String, dynamic> json) {
    final zonesMap = _asMap(json['zones']);
    final hours = _asDouble(json['weeklyHoursBudget']) ?? 8.0;
    return TrainingPlanConfig(
      raceName: _asNonEmptyString(json['raceName'], 'Target Race'),
      raceDistance: _asNonEmptyString(json['raceDistance'], '70.3'),
      raceDate: _normalizeDate(json['raceDate']),
      weeklyHoursBudget: hours.clamp(1.0, 40.0).toDouble(),
      longRunDay: _asNonEmptyString(json['longRunDay'], 'Sunday'),
      longRideDay: _asNonEmptyString(json['longRideDay'], 'Saturday'),
      restDay: _asNonEmptyString(json['restDay'], 'Friday'),
      limiterSport: _asNonEmptyString(json['limiterSport'], 'Swim'),
      zones: zonesMap != null
          ? AthleteZonesSnapshot.fromJson(zonesMap)
          : const AthleteZonesSnapshot(),
      additionalNotes: _asNullableString(json['additionalNotes']),
    );
  }
}

class TrainingWeek {
  final int weekNumber;
  final String startDate;
  final String phaseName;
  final String focusSummary;
  final double targetHours;
  final int targetTss;
  final List<PlannedWorkout> workouts;

  const TrainingWeek({
    required this.weekNumber,
    required this.startDate,
    required this.phaseName,
    required this.focusSummary,
    required this.targetHours,
    required this.targetTss,
    this.workouts = const [],
  });

  TrainingWeek copyWith({
    int? weekNumber,
    String? startDate,
    String? phaseName,
    String? focusSummary,
    double? targetHours,
    int? targetTss,
    List<PlannedWorkout>? workouts,
  }) {
    return TrainingWeek(
      weekNumber: weekNumber ?? this.weekNumber,
      startDate: startDate ?? this.startDate,
      phaseName: phaseName ?? this.phaseName,
      focusSummary: focusSummary ?? this.focusSummary,
      targetHours: targetHours ?? this.targetHours,
      targetTss: targetTss ?? this.targetTss,
      workouts: workouts ?? this.workouts,
    );
  }

  Map<String, dynamic> toJson() => {
        'weekNumber': weekNumber,
        'startDate': startDate,
        'phaseName': phaseName,
        'focusSummary': focusSummary,
        'targetHours': _finiteOrDefault(targetHours, 0.0),
        'targetTss': targetTss,
        'workouts': workouts.map((w) => w.toJson()).toList(),
      };

  factory TrainingWeek.fromJson(Map<String, dynamic> json) {
    final weekNumber = (_asInt(json['weekNumber']) ?? 1).clamp(1, 104);
    final startDate = _normalizeDate(json['startDate']);
    final hours = _asDouble(json['targetHours']) ?? 0.0;
    final tss = (_asInt(json['targetTss']) ?? 0).clamp(0, 5000);

    final rawWorkouts = _asMapList(json['workouts']);
    final workouts = <PlannedWorkout>[];
    for (var i = 0; i < rawWorkouts.length; i++) {
      workouts.add(
        PlannedWorkout.fromJson(
          rawWorkouts[i],
          fallbackDate: startDate,
          fallbackId: 'w${weekNumber}_d${i + 1}',
        ),
      );
    }

    return TrainingWeek(
      weekNumber: weekNumber,
      startDate: startDate,
      phaseName: _asNonEmptyString(json['phaseName'], 'Base'),
      focusSummary: _asString(json['focusSummary']),
      targetHours: hours < 0 ? 0.0 : hours,
      targetTss: tss,
      workouts: workouts,
    );
  }
}

class CoachMessage {
  final String id;
  final CoachMessageRole role;
  final String content;
  final DateTime createdAt;
  final TrainingPlan? proposedPlan;

  const CoachMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.proposedPlan,
  });

  CoachMessage copyWith({
    String? id,
    CoachMessageRole? role,
    String? content,
    DateTime? createdAt,
    TrainingPlan? proposedPlan,
    bool clearProposedPlan = false,
  }) {
    return CoachMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      proposedPlan:
          clearProposedPlan ? null : (proposedPlan ?? this.proposedPlan),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role.name,
        'content': content,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'proposedPlan': proposedPlan?.toJson(),
      };

  factory CoachMessage.fromJson(Map<String, dynamic> json) {
    final planMap = _asMap(json['proposedPlan']);
    final fallbackNow = DateTime.now().toUtc();
    return CoachMessage(
      id: _asNonEmptyString(
        json['id'],
        'msg_${fallbackNow.microsecondsSinceEpoch}',
      ),
      role: _parseEnum<CoachMessageRole>(
        json['role'],
        CoachMessageRole.values,
        CoachMessageRole.assistant,
        aliases: const {
          'coach': CoachMessageRole.assistant,
          'model': CoachMessageRole.assistant,
          'athlete': CoachMessageRole.user,
        },
      ),
      content: _asString(json['content']),
      createdAt: _parseDateTime(json['createdAt'], fallbackNow),
      proposedPlan: planMap != null ? TrainingPlan.fromJson(planMap) : null,
    );
  }
}

class TrainingPlan {
  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final TrainingPlanConfig config;
  final String coachOverview;
  final List<TrainingWeek> weeks;

  const TrainingPlan({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.config,
    required this.coachOverview,
    this.weeks = const [],
  });

  List<PlannedWorkout> get allWorkouts =>
      [for (final week in weeks) ...week.workouts];

  List<PlannedWorkout> workoutsForDate(DateTime localDate) {
    final targetKey = PlannedWorkout.formatLocalDate(localDate);
    return allWorkouts.where((w) => w.date == targetKey).toList();
  }

  TrainingPlan copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
    DateTime? updatedAt,
    TrainingPlanConfig? config,
    String? coachOverview,
    List<TrainingWeek>? weeks,
  }) {
    return TrainingPlan(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      config: config ?? this.config,
      coachOverview: coachOverview ?? this.coachOverview,
      weeks: weeks ?? this.weeks,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'config': config.toJson(),
        'coachOverview': coachOverview,
        'weeks': weeks.map((w) => w.toJson()).toList(),
      };

  factory TrainingPlan.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now().toUtc();
    final configMap = _asMap(json['config']) ?? const <String, dynamic>{};
    return TrainingPlan(
      id: _asNonEmptyString(json['id'], 'plan_${now.millisecondsSinceEpoch}'),
      name: _asNonEmptyString(json['name'], 'Triathlon Training Plan'),
      createdAt: _parseDateTime(json['createdAt'], now),
      updatedAt: _parseDateTime(json['updatedAt'], now),
      config: TrainingPlanConfig.fromJson(configMap),
      coachOverview: _asString(json['coachOverview']),
      weeks: _asMapList(json['weeks']).map(TrainingWeek.fromJson).toList(),
    );
  }
}
