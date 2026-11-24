import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../state/app_state.dart';
import '../models/activity.dart';
import '../models/training_block.dart';
import '../models/training_plan.dart';
import '../utils/unit_formatter.dart';
import '../components/garmin_sign_in_dialog.dart';
import '../components/macos_ui.dart';

class CalendarView extends StatefulWidget {
  final AppState appState;

  const CalendarView({super.key, required this.appState});

  @override
  State<CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends State<CalendarView> {
  String _granularity = 'Month'; // 'Day', 'Week', 'Month'
  late DateTime _focusedDate;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _focusedDate = DateTime(now.year, now.month, now.day);
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime _addDays(DateTime d, int offset) =>
      DateTime(d.year, d.month, d.day + offset);

  String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  DateTime _mondayOf(DateTime d) {
    final norm = _dateOnly(d);
    return _addDays(norm, -(norm.weekday - 1));
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _navigatePrevious() {
    setState(() {
      switch (_granularity) {
        case 'Day':
          _focusedDate = _addDays(_focusedDate, -1);
        case 'Week':
          _focusedDate = _addDays(_focusedDate, -7);
        case 'Month':
          _focusedDate = DateTime(_focusedDate.year, _focusedDate.month - 1, 1);
      }
    });
  }

  void _navigateNext() {
    setState(() {
      switch (_granularity) {
        case 'Day':
          _focusedDate = _addDays(_focusedDate, 1);
        case 'Week':
          _focusedDate = _addDays(_focusedDate, 7);
        case 'Month':
          _focusedDate = DateTime(_focusedDate.year, _focusedDate.month + 1, 1);
      }
    });
  }

  void _navigateToday() {
    final now = DateTime.now();
    setState(() {
      _focusedDate = DateTime(now.year, now.month, now.day);
    });
  }

  void _drillIntoDay(DateTime date) {
    setState(() {
      _focusedDate = _dateOnly(date);
      _granularity = 'Day';
    });
  }

  Color _disciplineColor(SportDiscipline d) {
    switch (d) {
      case SportDiscipline.swim:
        return AppColors.swimPrimary;
      case SportDiscipline.bike:
      case SportDiscipline.indoorBike:
        return AppColors.bikeSecondary;
      case SportDiscipline.run:
        return AppColors.runTertiary;
      case SportDiscipline.strength:
        return AppColors.strengthViolet;
    }
  }

  String _disciplineLabel(SportDiscipline d) {
    switch (d) {
      case SportDiscipline.swim:
        return 'Swim';
      case SportDiscipline.bike:
        return 'Bike';
      case SportDiscipline.indoorBike:
        return 'Indoor Bike';
      case SportDiscipline.run:
        return 'Run';
      case SportDiscipline.strength:
        return 'Strength';
    }
  }

  IconData _disciplineIcon(SportDiscipline d) {
    switch (d) {
      case SportDiscipline.swim:
        return CupertinoIcons.drop_fill;
      case SportDiscipline.bike:
      case SportDiscipline.indoorBike:
        return CupertinoIcons.speedometer;
      case SportDiscipline.run:
        return CupertinoIcons.flame_fill;
      case SportDiscipline.strength:
        return CupertinoIcons.bolt_fill;
    }
  }

  String _formatDuration(double seconds) {
    if (!seconds.isFinite || seconds <= 0) return '0m';
    final totalMin = (seconds / 60).round();
    final h = totalMin ~/ 60;
    final m = totalMin % 60;
    if (h > 0 && m > 0) return '${h}h ${m}m';
    if (h > 0) return '${h}h';
    return '${m}m';
  }

  String _formatDistanceShort(Activity a) {
    if (!a.distanceKm.isFinite || a.distanceKm <= 0) {
      return _formatDuration(a.durationSeconds);
    }
    return widget.appState.formatActivityDistance(a);
  }

  (String, Color) _archetypeMeta(WorkoutArchetype a) {
    return switch (a) {
      WorkoutArchetype.intervals => ('Intervals', AppColors.error),
      WorkoutArchetype.threshold => ('Threshold', AppColors.bikeSecondary),
      WorkoutArchetype.easy => ('Easy', AppColors.runTertiary),
      WorkoutArchetype.long => ('Long', AppColors.accent),
      WorkoutArchetype.zwiftRide => ('Zwift', AppColors.bikeSecondary),
      WorkoutArchetype.brick => ('Brick', AppColors.strengthViolet),
      WorkoutArchetype.strength => ('Strength', AppColors.strengthViolet),
      WorkoutArchetype.rest => ('Rest', AppColors.outline),
    };
  }

  bool _isGarminSynced(PlannedWorkout w) =>
      w.isSyncedToGarmin || (w.brickRunLeg?.isSyncedToGarmin ?? false);

  String? _formatPlannedDistance(PlannedWorkout w) {
    final d = w.estimatedDistanceKm;
    if (d == null || !d.isFinite || d <= 0) return null;
    return UnitFormatter.formatDistance(
      d,
      widget.appState.unitSystem,
      discipline: w.discipline,
      decimals: w.discipline == SportDiscipline.swim ? 0 : 1,
    );
  }

  String? _formatPlannedTss(double? tss) {
    if (tss == null || !tss.isFinite || tss <= 0) return null;
    return '${tss.round()} TSS';
  }

  double? _validAdherence(double? adh) {
    if (adh == null || !adh.isFinite || adh < 0) return null;
    return adh.clamp(0.0, 100.0).toDouble();
  }

  Map<DateTime, List<Activity>> _groupActivitiesByDay() {
    final map = <DateTime, List<Activity>>{};
    for (final act in widget.appState.activities) {
      final key = _dateOnly(act.timestamp.toLocal());
      map.putIfAbsent(key, () => []).add(act);
    }
    for (final list in map.values) {
      list.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    }
    return map;
  }

  Map<String, List<PlannedWorkout>> _groupPlannedWorkoutsByDay() {
    final plan = widget.appState.activeTrainingPlan;
    if (plan == null || plan.weeks.isEmpty) return const {};

    final grouped = <String, List<PlannedWorkout>>{};
    for (final week in plan.weeks) {
      for (final w in week.workouts) {
        if (w.date.trim().isEmpty || w.scheduledDate == null) continue;
        grouped.putIfAbsent(w.date, () => []).add(w);
      }
    }

    int tierOf(PlannedWorkout w) {
      if (w.archetype == WorkoutArchetype.rest) return 2;
      if (w.status == WorkoutStatus.skipped) return 1;
      return 0;
    }

    for (final entry in grouped.entries) {
      final list = entry.value;
      if (list.length <= 1) continue;
      final indexed = list.asMap().entries.toList()
        ..sort((a, b) {
          final cmp = tierOf(a.value).compareTo(tierOf(b.value));
          if (cmp != 0) return cmp;
          return a.key.compareTo(b.key);
        });
      grouped[entry.key] = [for (final e in indexed) e.value];
    }
    return grouped;
  }

  Set<String> _collectMatchedActivityIds(TrainingPlan? plan) {
    if (plan == null) return const {};
    final ids = <String>{};
    for (final w in plan.allWorkouts) {
      if (w.status != WorkoutStatus.skipped &&
          w.matchedActivityId != null &&
          w.matchedActivityId!.trim().isNotEmpty) {
        ids.add(w.matchedActivityId!.trim());
      }
      final leg = w.brickRunLeg;
      if (leg != null &&
          leg.status != WorkoutStatus.skipped &&
          leg.matchedActivityId != null &&
          leg.matchedActivityId!.trim().isNotEmpty) {
        ids.add(leg.matchedActivityId!.trim());
      }
    }
    return ids;
  }

  Map<DateTime, List<RaceTarget>> _groupGoalsByDay() {
    final map = <DateTime, List<RaceTarget>>{};
    for (final target in widget.appState.raceTargets) {
      final key = _dateOnly(target.raceDate);
      map.putIfAbsent(key, () => []).add(target);
    }
    return map;
  }

  String _headerTitle() {
    switch (_granularity) {
      case 'Day':
        return DateFormat('EEEE, MMMM d, yyyy').format(_focusedDate);
      case 'Week':
        final mon = _mondayOf(_focusedDate);
        final sun = _addDays(mon, 6);
        if (mon.year == sun.year) {
          return '${DateFormat('MMM d').format(mon)} – ${DateFormat('MMM d, yyyy').format(sun)}';
        }
        return '${DateFormat('MMM d, yyyy').format(mon)} – ${DateFormat('MMM d, yyyy').format(sun)}';
      case 'Month':
      default:
        return DateFormat('MMMM yyyy').format(_focusedDate);
    }
  }

  String _periodSummary(
    Map<DateTime, List<Activity>> byDay,
    Map<String, List<PlannedWorkout>> plannedByDay,
  ) {
    final List<Activity> periodActs = [];
    final List<PlannedWorkout> periodPlanned = [];
    if (_granularity == 'Day') {
      periodActs.addAll(byDay[_focusedDate] ?? const []);
      periodPlanned.addAll(plannedByDay[_dateKey(_focusedDate)] ?? const []);
    } else if (_granularity == 'Week') {
      final mon = _mondayOf(_focusedDate);
      for (int i = 0; i < 7; i++) {
        final d = _addDays(mon, i);
        periodActs.addAll(byDay[d] ?? const []);
        periodPlanned.addAll(plannedByDay[_dateKey(d)] ?? const []);
      }
    } else {
      final daysInMonth =
          DateUtils.getDaysInMonth(_focusedDate.year, _focusedDate.month);
      for (int d = 1; d <= daysInMonth; d++) {
        final day = DateTime(_focusedDate.year, _focusedDate.month, d);
        periodActs.addAll(byDay[day] ?? const []);
        periodPlanned.addAll(plannedByDay[_dateKey(day)] ?? const []);
      }
    }

    final plannedNonRestCount = periodPlanned
        .where((w) => w.archetype != WorkoutArchetype.rest)
        .length;

    if (periodActs.isEmpty && plannedNonRestCount == 0) {
      return widget.appState.isSignedIn
          ? 'No synced activities in this period'
          : 'Sign in to view Garmin activities';
    }
    if (periodActs.isEmpty && plannedNonRestCount > 0) {
      return '$plannedNonRestCount planned ${plannedNonRestCount == 1 ? 'workout' : 'workouts'}';
    }

    final totalKm = periodActs.fold<double>(
      0,
      (s, a) => s + (a.distanceKm.isFinite && a.distanceKm > 0 ? a.distanceKm : 0),
    );
    final totalSec = periodActs.fold<double>(
      0,
      (s, a) =>
          s + (a.durationSeconds.isFinite && a.durationSeconds > 0 ? a.durationSeconds : 0),
    );
    final countLabel =
        '${periodActs.length} ${periodActs.length == 1 ? 'activity' : 'activities'}';
    final distPart = totalKm > 0
        ? ' • ${UnitFormatter.formatDistance(totalKm, widget.appState.unitSystem)}'
        : '';
    final durPart = totalSec > 0 ? ' • ${_formatDuration(totalSec)}' : '';
    final plannedPart =
        plannedNonRestCount > 0 ? ' • $plannedNonRestCount planned' : '';
    return '$countLabel$distPart$durPart$plannedPart';
  }

  Future<void> _showAddGoalDialog() async {
    final nameController = TextEditingController();
    final notesController = TextEditingController();
    RaceTier tier = RaceTier.tierA;
    DateTime raceDate = DateTime.now().add(const Duration(days: 60));

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          backgroundColor: AppColors.surfaceContainer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: AppColors.borderSubtle),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Add Race or Goal', style: AppTypography.headlineMd),
                  const SizedBox(height: 14),
                  Text('Event Name', style: AppTypography.headlineSm),
                  const SizedBox(height: 6),
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    style: AppTypography.bodyLg,
                    decoration: InputDecoration(
                      hintText: 'e.g. Half Marathon, 70.3, Century Ride',
                      hintStyle: AppTypography.bodyMd.copyWith(color: AppColors.outline),
                      filled: true,
                      fillColor: AppColors.surfaceLowest,
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(7),
                        borderSide: BorderSide(color: AppColors.borderSubtle),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Priority', style: AppTypography.headlineSm),
                      MacSegmentedControl<RaceTier>(
                        items: RaceTier.values,
                        selected: tier,
                        labelBuilder: (t) => switch (t) {
                          RaceTier.tierA => 'A-Race',
                          RaceTier.tierB => 'B-Race',
                          RaceTier.tierC => 'C-Race',
                        },
                        onChanged: (t) => setDialogState(() => tier = t),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Target Date', style: AppTypography.headlineSm),
                      MacPushButton(
                        label: DateFormat('MMM d, yyyy').format(raceDate),
                        icon: CupertinoIcons.calendar,
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: raceDate,
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(const Duration(days: 730)),
                          );
                          if (picked != null) {
                            setDialogState(() => raceDate = picked);
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('Notes (optional)', style: AppTypography.headlineSm),
                  const SizedBox(height: 6),
                  TextField(
                    controller: notesController,
                    style: AppTypography.bodyMd.copyWith(color: AppColors.onSurface),
                    decoration: InputDecoration(
                      hintText: 'Target pace, taper plan, etc.',
                      hintStyle: AppTypography.bodySm,
                      filled: true,
                      fillColor: AppColors.surfaceLowest,
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(7),
                        borderSide: BorderSide(color: AppColors.borderSubtle),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      MacPushButton(
                        label: 'Cancel',
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                      const SizedBox(width: 8),
                      MacPushButton(
                        label: 'Add Goal',
                        isPrimary: true,
                        onPressed: () {
                          if (nameController.text.trim().isEmpty) return;
                          widget.appState.addRaceTarget(
                            name: nameController.text,
                            tier: tier,
                            raceDate: raceDate,
                            focusDescription: notesController.text,
                          );
                          Navigator.of(ctx).pop();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    nameController.dispose();
    notesController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final byDay = _groupActivitiesByDay();
    final goalsByDay = _groupGoalsByDay();
    final plannedByDay = _groupPlannedWorkoutsByDay();
    final matchedActivityIds =
        _collectMatchedActivityIds(widget.appState.activeTrainingPlan);
    final activitiesById = <String, Activity>{
      for (final a in widget.appState.activities) a.id: a,
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Section 1: Training Calendar (Day / Week / Month)
          MacCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildCalendarToolbar(byDay, plannedByDay),
                const SizedBox(height: 14),
                if (_granularity == 'Month')
                  _buildMonthGrid(
                    byDay,
                    goalsByDay,
                    plannedByDay,
                    matchedActivityIds,
                  )
                else if (_granularity == 'Week')
                  _buildWeekGrid(
                    byDay,
                    goalsByDay,
                    plannedByDay,
                    matchedActivityIds,
                    activitiesById,
                  )
                else
                  _buildDayAgenda(
                    byDay,
                    goalsByDay,
                    plannedByDay,
                    matchedActivityIds,
                    activitiesById,
                  ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Section 2: Race & Event Goals (User-defined, never fake)
          MacCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Upcoming Race Goals', style: AppTypography.headlineMd),
                          const SizedBox(height: 2),
                          Text(
                            'Add your own target events to track countdowns',
                            style: AppTypography.bodySm,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    MacPushButton(
                      label: 'Add Goal',
                      icon: CupertinoIcons.add,
                      isPrimary: true,
                      onPressed: _showAddGoalDialog,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (widget.appState.raceTargets.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text(
                        'No race goals added yet. Click "Add Goal" to set a target event.',
                        style: AppTypography.bodyMd,
                      ),
                    ),
                  )
                else
                  ...widget.appState.raceTargets.map(_buildGoalRow),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarToolbar(
    Map<DateTime, List<Activity>> byDay,
    Map<String, List<PlannedWorkout>> plannedByDay,
  ) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 10,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_headerTitle(), style: AppTypography.headlineLg),
            const SizedBox(height: 2),
            Text(_periodSummary(byDay, plannedByDay), style: AppTypography.bodySm),
          ],
        ),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          runSpacing: 8,
          children: [
            // Granularity switcher
            MacSegmentedControl<String>(
              items: const ['Day', 'Week', 'Month'],
              selected: _granularity,
              labelBuilder: (s) => s,
              onChanged: (val) => setState(() => _granularity = val),
            ),

            // Prev / Today / Next navigation cluster
            Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceLow,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: AppColors.borderDivider),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _navIconButton(
                    icon: CupertinoIcons.chevron_left,
                    tooltip: 'Previous $_granularity',
                    onTap: _navigatePrevious,
                  ),
                  Container(width: 1, height: 18, color: AppColors.borderDivider),
                  InkWell(
                    onTap: _navigateToday,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: Text(
                        'Today',
                        style: AppTypography.bodySm.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.onSurface,
                        ),
                      ),
                    ),
                  ),
                  Container(width: 1, height: 18, color: AppColors.borderDivider),
                  _navIconButton(
                    icon: CupertinoIcons.chevron_right,
                    tooltip: 'Next $_granularity',
                    onTap: _navigateNext,
                  ),
                ],
              ),
            ),

            if (!widget.appState.isSignedIn)
              MacPushButton(
                label: 'Sign in with Garmin',
                icon: CupertinoIcons.person_crop_circle,
                onPressed: () => showGarminSignInDialog(context, widget.appState),
              ),
          ],
        ),
      ],
    );
  }

  Widget _navIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Icon(icon, size: 13, color: AppColors.onSurface),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // MONTH VIEW
  // ---------------------------------------------------------------------------
  Widget _buildMonthGrid(
    Map<DateTime, List<Activity>> byDay,
    Map<DateTime, List<RaceTarget>> goalsByDay,
    Map<String, List<PlannedWorkout>> plannedByDay,
    Set<String> matchedActivityIds,
  ) {
    final now = _dateOnly(DateTime.now());
    final firstOfMonth = DateTime(_focusedDate.year, _focusedDate.month, 1);
    final leadingDays = firstOfMonth.weekday - 1; // Mon = 1 -> 0 leading
    final daysInMonth = DateUtils.getDaysInMonth(_focusedDate.year, _focusedDate.month);
    final totalCells = ((leadingDays + daysInMonth + 6) ~/ 7) * 7;
    final numRows = totalCells ~/ 7;
    final gridStart = _addDays(firstOfMonth, -leadingDays);
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Weekday header row
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: weekdays.map((day) {
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    day,
                    style: AppTypography.labelCaps,
                    textAlign: TextAlign.left,
                  ),
                ),
              );
            }).toList(),
          ),
        ),

        // Calendar grid container
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.borderDivider),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: List.generate(numRows, (rowIdx) {
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: List.generate(7, (colIdx) {
                    final cellDate = _addDays(gridStart, rowIdx * 7 + colIdx);
                    final dateKey = _dateKey(cellDate);
                    final inMonth = cellDate.month == _focusedDate.month;
                    final isToday = _isSameDay(cellDate, now);
                    final acts = byDay[cellDate] ?? const <Activity>[];
                    final goals = goalsByDay[cellDate] ?? const <RaceTarget>[];
                    final planned =
                        plannedByDay[dateKey] ?? const <PlannedWorkout>[];

                    return Expanded(
                      child: _buildMonthCell(
                        date: cellDate,
                        dateKey: dateKey,
                        inMonth: inMonth,
                        isToday: isToday,
                        activities: acts,
                        goals: goals,
                        plannedWorkouts: planned,
                        matchedActivityIds: matchedActivityIds,
                        isLastCol: colIdx == 6,
                        isLastRow: rowIdx == numRows - 1,
                      ),
                    );
                  }),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildMonthCell({
    required DateTime date,
    required String dateKey,
    required bool inMonth,
    required bool isToday,
    required List<Activity> activities,
    required List<RaceTarget> goals,
    required List<PlannedWorkout> plannedWorkouts,
    required Set<String> matchedActivityIds,
    required bool isLastCol,
    required bool isLastRow,
  }) {
    final totalKm = activities.fold<double>(
      0,
      (s, a) => s + (a.distanceKm.isFinite && a.distanceKm > 0 ? a.distanceKm : 0),
    );
    final unmatchedActs = activities
        .where((a) => !matchedActivityIds.contains(a.id))
        .toList();

    final maxPills = goals.isNotEmpty ? 2 : 3;
    final visiblePlanned = plannedWorkouts.take(maxPills).toList();
    final remainingSlots = maxPills - visiblePlanned.length;
    final visibleUnmatchedActs = remainingSlots > 0
        ? unmatchedActs.take(remainingSlots).toList()
        : const <Activity>[];
    final totalItems = plannedWorkouts.length + unmatchedActs.length;
    final visibleCount = visiblePlanned.length + visibleUnmatchedActs.length;
    final extraGoals = goals.length > 1 ? goals.length - 1 : 0;
    final overflowCount = (totalItems - visibleCount) + extraGoals;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        key: ValueKey('calendar_month_cell_$dateKey'),
        behavior: HitTestBehavior.opaque,
        onTap: () => _drillIntoDay(date),
        child: Container(
          constraints: const BoxConstraints(minHeight: 112),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isToday
                ? AppColors.accent.withOpacity(AppColors.isDark ? 0.10 : 0.05)
                : (inMonth ? AppColors.surfaceLowest : AppColors.surfaceLow.withOpacity(0.5)),
            border: Border(
              right: isLastCol ? BorderSide.none : BorderSide(color: AppColors.borderDivider),
              bottom: isLastRow ? BorderSide.none : BorderSide(color: AppColors.borderDivider),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Day number + optional distance total
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: isToday
                        ? BoxDecoration(
                            color: AppColors.accent,
                            shape: BoxShape.circle,
                          )
                        : null,
                    child: Text(
                      '${date.day}',
                      style: AppTypography.telemetrySm.copyWith(
                        fontSize: 11,
                        fontWeight: isToday ? FontWeight.w700 : FontWeight.w600,
                        color: isToday
                            ? Colors.white
                            : (inMonth ? AppColors.onSurface : AppColors.outline.withOpacity(0.55)),
                      ),
                    ),
                  ),
                  if (totalKm > 0)
                    Flexible(
                      child: Text(
                        UnitFormatter.formatDistance(totalKm, widget.appState.unitSystem),
                        style: AppTypography.telemetrySm.copyWith(
                          fontSize: 10,
                          color: AppColors.outline,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              // Race goal marker if any
              if (goals.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 3),
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: goals.first.badgeColor.withOpacity(AppColors.isDark ? 0.25 : 0.16),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '⚑ ${goals.first.name}',
                    style: AppTypography.bodySm.copyWith(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: goals.first.badgeColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              // Planned workout pills
              ...visiblePlanned.map(_buildMonthPlannedPill),
              // Unmatched activity pills
              ...visibleUnmatchedActs.map(_buildMonthActivityPill),
              if (overflowCount > 0)
                Text(
                  '+$overflowCount more',
                  style: AppTypography.bodySm.copyWith(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.accent,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMonthPlannedPill(PlannedWorkout w) {
    final sportColor = _disciplineColor(w.discipline);
    final (archetypeLabel, archetypeColor) = _archetypeMeta(w.archetype);
    final isCompleted = w.status == WorkoutStatus.completed;
    final isSkipped = w.status == WorkoutStatus.skipped;
    final isScheduled = w.status == WorkoutStatus.scheduled;
    final isSynced = _isGarminSynced(w);
    final adh = _validAdherence(w.adherencePercent);

    final Color bgColor;
    if (isSkipped) {
      bgColor = AppColors.surfaceLow.withOpacity(AppColors.isDark ? 0.55 : 0.75);
    } else if (isCompleted) {
      bgColor = sportColor.withOpacity(AppColors.isDark ? 0.22 : 0.13);
    } else {
      bgColor = sportColor.withOpacity(AppColors.isDark ? 0.14 : 0.08);
    }

    final String metaText;
    if (adh != null && (isCompleted || w.matchedActivityId != null || w.brickRunLeg?.matchedActivityId != null)) {
      metaText = '${adh.round()}%';
    } else if (isSkipped) {
      metaText = 'Skipped';
    } else {
      metaText = '${w.estimatedDurationMinutes}m';
    }

    final pillBody = Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4.5),
        border: isScheduled
            ? null
            : Border.all(
                color: isSkipped
                    ? AppColors.borderDivider
                    : sportColor.withOpacity(0.55),
                width: 1.0,
              ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _disciplineIcon(w.discipline),
                size: 9.5,
                color: isSkipped ? AppColors.outline : sportColor,
              ),
              const SizedBox(width: 3),
              Expanded(
                child: Text(
                  w.title,
                  style: AppTypography.bodySm.copyWith(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    color: isSkipped ? AppColors.outline : AppColors.onSurface,
                    decoration: isSkipped ? TextDecoration.lineThrough : null,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isSynced) ...[
                const SizedBox(width: 2),
                Tooltip(
                  message: 'Synced to Garmin Watch',
                  child: Icon(
                    CupertinoIcons.checkmark_shield_fill,
                    size: 9.5,
                    color: AppColors.runTertiary,
                  ),
                ),
              ],
              if (isCompleted) ...[
                const SizedBox(width: 2),
                Icon(
                  CupertinoIcons.checkmark_circle_fill,
                  size: 9.5,
                  color: AppColors.runTertiary,
                ),
              ] else if (isSkipped) ...[
                const SizedBox(width: 2),
                Icon(
                  CupertinoIcons.xmark_circle,
                  size: 9.5,
                  color: AppColors.outline,
                ),
              ],
            ],
          ),
          const SizedBox(height: 1.5),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 3.5, vertical: 0.5),
                  decoration: BoxDecoration(
                    color: (isSkipped ? AppColors.outline : archetypeColor)
                        .withOpacity(AppColors.isDark ? 0.22 : 0.14),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    archetypeLabel,
                    style: AppTypography.bodySm.copyWith(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w600,
                      color: isSkipped ? AppColors.outline : archetypeColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  metaText,
                  style: AppTypography.telemetrySm.copyWith(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w600,
                    color: isSkipped
                        ? AppColors.outline
                        : (adh != null ? AppColors.runTertiary : AppColors.onSurfaceVariant),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: ValueKey('calendar_planned_${w.id}'),
            onTap: () => widget.appState.selectPlannedWorkout(w),
            borderRadius: BorderRadius.circular(4.5),
            child: isScheduled
                ? CustomPaint(
                    foregroundPainter: _DashedRRectPainter(
                      color: sportColor.withOpacity(0.75),
                      strokeWidth: 1.0,
                      borderRadius: 4.5,
                      dashLength: 3.5,
                      gapLength: 2.5,
                    ),
                    child: pillBody,
                  )
                : pillBody,
          ),
        ),
      ),
    );
  }

  Widget _buildMonthActivityPill(Activity a) {
    final color = _disciplineColor(a.discipline);
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: ValueKey('calendar_activity_${a.id}'),
            onTap: () => widget.appState.setSelectedActivityId(a.id),
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: color.withOpacity(AppColors.isDark ? 0.22 : 0.13),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${_formatDistanceShort(a)} ${a.title}',
                      style: AppTypography.bodySm.copyWith(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: AppColors.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // WEEK VIEW
  // ---------------------------------------------------------------------------
  Widget _buildWeekGrid(
    Map<DateTime, List<Activity>> byDay,
    Map<DateTime, List<RaceTarget>> goalsByDay,
    Map<String, List<PlannedWorkout>> plannedByDay,
    Set<String> matchedActivityIds,
    Map<String, Activity> activitiesById,
  ) {
    final now = _dateOnly(DateTime.now());
    final monday = _mondayOf(_focusedDate);

    // Weekly aggregate stats
    final weekActs = <Activity>[];
    final weekPlannedNonRest = <PlannedWorkout>[];
    for (int i = 0; i < 7; i++) {
      final dayDate = _addDays(monday, i);
      weekActs.addAll(byDay[dayDate] ?? const []);
      weekPlannedNonRest.addAll(
        (plannedByDay[_dateKey(dayDate)] ?? const [])
            .where((w) => w.archetype != WorkoutArchetype.rest),
      );
    }
    final weekDist = weekActs.fold<double>(
      0,
      (s, a) => s + (a.distanceKm.isFinite && a.distanceKm > 0 ? a.distanceKm : 0),
    );
    final weekSec = weekActs.fold<double>(
      0,
      (s, a) =>
          s + (a.durationSeconds.isFinite && a.durationSeconds > 0 ? a.durationSeconds : 0),
    );
    final weekElev = weekActs.fold<double>(
      0,
      (s, a) =>
          s + (a.elevationGainM.isFinite && a.elevationGainM > 0 ? a.elevationGainM : 0),
    );
    final weekPlannedCompleted = weekPlannedNonRest
        .where((w) => w.status == WorkoutStatus.completed)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Compact weekly summary strip
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceLowest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.borderDivider),
          ),
          child: Wrap(
            spacing: 20,
            runSpacing: 6,
            children: [
              _inlineStat('Sessions', '${weekActs.length}'),
              _inlineStat('Distance', UnitFormatter.formatDistance(weekDist, widget.appState.unitSystem)),
              _inlineStat('Duration', _formatDuration(weekSec)),
              _inlineStat('Elevation', UnitFormatter.formatElevation(weekElev, widget.appState.unitSystem)),
              if (weekPlannedNonRest.isNotEmpty)
                _inlineStat(
                  'Planned',
                  '$weekPlannedCompleted/${weekPlannedNonRest.length}',
                ),
            ],
          ),
        ),

        // 7-column microcycle grid
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: List.generate(7, (i) {
            final dayDate = _addDays(monday, i);
            final dateKey = _dateKey(dayDate);
            final isToday = _isSameDay(dayDate, now);
            final acts = byDay[dayDate] ?? const <Activity>[];
            final unmatchedActs =
                acts.where((a) => !matchedActivityIds.contains(a.id)).toList();
            final goals = goalsByDay[dayDate] ?? const <RaceTarget>[];
            final planned =
                plannedByDay[dateKey] ?? const <PlannedWorkout>[];
            final dayDist = acts.fold<double>(
              0,
              (s, a) => s + (a.distanceKm.isFinite && a.distanceKm > 0 ? a.distanceKm : 0),
            );
            final daySec = acts.fold<double>(
              0,
              (s, a) =>
                  s + (a.durationSeconds.isFinite && a.durationSeconds > 0 ? a.durationSeconds : 0),
            );

            return Expanded(
              child: Container(
                key: ValueKey('calendar_week_day_$dateKey'),
                margin: EdgeInsets.only(right: i < 6 ? 8 : 0),
                padding: const EdgeInsets.all(8),
                constraints: const BoxConstraints(minHeight: 220),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLowest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isToday ? AppColors.accent.withOpacity(0.6) : AppColors.borderDivider,
                    width: isToday ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Clickable day header -> drills into Day View
                    InkWell(
                      onTap: () => _drillIntoDay(dayDate),
                      borderRadius: BorderRadius.circular(5),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Text(
                                DateFormat('EEE').format(dayDate),
                                style: AppTypography.headlineSm.copyWith(
                                  color: isToday ? AppColors.accent : AppColors.onSurface,
                                  fontSize: 12,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: isToday
                                  ? BoxDecoration(
                                      color: AppColors.accent,
                                      borderRadius: BorderRadius.circular(10),
                                    )
                                  : null,
                              child: Text(
                                DateFormat('d').format(dayDate),
                                style: AppTypography.telemetrySm.copyWith(
                                  fontSize: 11,
                                  fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                                  color: isToday ? Colors.white : AppColors.outline,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Per-day totals subtitle
                    if (acts.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        dayDist > 0
                            ? '${UnitFormatter.formatDistance(dayDist, widget.appState.unitSystem)} • ${_formatDuration(daySec)}'
                            : _formatDuration(daySec),
                        style: AppTypography.telemetrySm.copyWith(
                          fontSize: 10,
                          color: AppColors.outline,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 8),

                    // Race goal badge if scheduled on this day
                    ...goals.map((g) => Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          decoration: BoxDecoration(
                            color: g.badgeColor.withOpacity(AppColors.isDark ? 0.22 : 0.14),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '⚑ ${g.name}',
                            style: AppTypography.bodySm.copyWith(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: g.badgeColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        )),

                    if (planned.isEmpty && unmatchedActs.isEmpty && goals.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 42),
                        child: Center(
                          child: Text(
                            'Rest',
                            style: AppTypography.bodySm.copyWith(color: AppColors.outline),
                          ),
                        ),
                      )
                    else ...[
                      ...planned.map((w) => _buildWeekPlannedWorkoutCard(
                            w,
                            matchedAct: w.matchedActivityId != null
                                ? activitiesById[w.matchedActivityId!]
                                : null,
                            brickRunAct: w.brickRunLeg?.matchedActivityId != null
                                ? activitiesById[w.brickRunLeg!.matchedActivityId!]
                                : null,
                          )),
                      ...unmatchedActs.map(_buildWeekActivityCard),
                    ],
                  ],
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildWeekPlannedWorkoutCard(
    PlannedWorkout w, {
    Activity? matchedAct,
    Activity? brickRunAct,
  }) {
    final sportColor = _disciplineColor(w.discipline);
    final (archetypeLabel, archetypeColor) = _archetypeMeta(w.archetype);
    final isCompleted = w.status == WorkoutStatus.completed;
    final isSkipped = w.status == WorkoutStatus.skipped;
    final isScheduled = w.status == WorkoutStatus.scheduled;
    final isSynced = _isGarminSynced(w);
    final adh = _validAdherence(w.adherencePercent);
    final distStr = _formatPlannedDistance(w);
    final tssStr = _formatPlannedTss(w.estimatedTss);

    final metricsParts = <String>[
      '${w.estimatedDurationMinutes}m',
      if (distStr != null) distStr,
      if (tssStr != null) tssStr,
    ];

    final Color bgColor;
    if (isSkipped) {
      bgColor = AppColors.surfaceLow.withOpacity(AppColors.isDark ? 0.55 : 0.75);
    } else if (isCompleted) {
      bgColor = AppColors.surfaceContainer;
    } else {
      bgColor = sportColor.withOpacity(AppColors.isDark ? 0.14 : 0.08);
    }

    final cardContent = Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(7),
        border: isScheduled
            ? null
            : Border.all(
                color: isSkipped
                    ? AppColors.borderDivider
                    : sportColor.withOpacity(0.55),
                width: 1.0,
              ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1.5),
                child: Icon(
                  _disciplineIcon(w.discipline),
                  size: 11,
                  color: isSkipped ? AppColors.outline : sportColor,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  w.title,
                  style: AppTypography.headlineSm.copyWith(
                    fontSize: 11,
                    color: isSkipped ? AppColors.outline : AppColors.onSurface,
                    decoration: isSkipped ? TextDecoration.lineThrough : null,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isSynced) ...[
                const SizedBox(width: 2),
                Tooltip(
                  message: 'Synced to Garmin Watch',
                  child: Icon(
                    CupertinoIcons.checkmark_shield_fill,
                    size: 11,
                    color: AppColors.runTertiary,
                  ),
                ),
              ],
              if (isCompleted) ...[
                const SizedBox(width: 2),
                Icon(
                  CupertinoIcons.checkmark_circle_fill,
                  size: 11,
                  color: AppColors.runTertiary,
                ),
              ] else if (isSkipped) ...[
                const SizedBox(width: 2),
                Icon(
                  CupertinoIcons.xmark_circle,
                  size: 11,
                  color: AppColors.outline,
                ),
              ],
            ],
          ),
          const SizedBox(height: 5),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _compactWeekPill(
                label: archetypeLabel,
                color: isSkipped ? AppColors.outline : archetypeColor,
              ),
              if (isSkipped)
                _compactWeekPill(
                  label: 'Skipped',
                  color: AppColors.outline,
                ),
              if (adh != null &&
                  (isCompleted ||
                      w.matchedActivityId != null ||
                      w.brickRunLeg?.matchedActivityId != null))
                _compactWeekPill(
                  label: '${adh.round()}%',
                  color: adh >= 85
                      ? AppColors.runTertiary
                      : AppColors.bikeSecondary,
                ),
              if (w.archetype == WorkoutArchetype.brick && w.brickRunLeg != null)
                _compactWeekPill(
                  label: '+ ${w.brickRunLeg!.estimatedDurationMinutes}m Run',
                  color: isSkipped ? AppColors.outline : AppColors.runTertiary,
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            metricsParts.join(' • '),
            style: AppTypography.telemetrySm.copyWith(
              fontSize: 10,
              color: isSkipped ? AppColors.outline : AppColors.onSurfaceVariant,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (matchedAct != null || brickRunAct != null) ...[
            const SizedBox(height: 3),
            Text(
              matchedAct != null && brickRunAct != null
                  ? '${widget.appState.displayTitleFor(matchedAct)} + ${widget.appState.displayTitleFor(brickRunAct)}'
                  : widget.appState.displayTitleFor(matchedAct ?? brickRunAct!),
              style: AppTypography.bodySm.copyWith(
                fontSize: 9.5,
                color: AppColors.runTertiary,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: ValueKey('calendar_planned_${w.id}'),
          onTap: () => widget.appState.selectPlannedWorkout(w),
          borderRadius: BorderRadius.circular(7),
          child: isScheduled
              ? CustomPaint(
                  foregroundPainter: _DashedRRectPainter(
                    color: sportColor.withOpacity(0.75),
                    strokeWidth: 1.2,
                    borderRadius: 7.0,
                    dashLength: 4.5,
                    gapLength: 3.0,
                  ),
                  child: cardContent,
                )
              : cardContent,
        ),
      ),
    );
  }

  Widget _compactWeekPill({required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withOpacity(AppColors.isDark ? 0.22 : 0.13),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: AppTypography.bodySm.copyWith(
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
          color: color,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildWeekActivityCard(Activity a) {
    final color = _disciplineColor(a.discipline);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: ValueKey('calendar_activity_${a.id}'),
          onTap: () => widget.appState.setSelectedActivityId(a.id),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainer,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.borderSubtle),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        a.title,
                        style: AppTypography.headlineSm.copyWith(fontSize: 11.5),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  a.distanceKm.isFinite && a.distanceKm > 0
                      ? '${_formatDistanceShort(a)} • ${a.movingTime}'
                      : a.movingTime,
                  style: AppTypography.telemetrySm.copyWith(fontSize: 10.5),
                  overflow: TextOverflow.ellipsis,
                ),
                if (a.avgHr > 0 || widget.appState.formatActivityPaceOrSpeed(a) != '—') ...[
                  const SizedBox(height: 2),
                  Text(
                    a.avgHr > 0 ? '${a.avgHr} bpm' : widget.appState.formatActivityPaceOrSpeed(a),
                    style: AppTypography.bodySm.copyWith(fontSize: 10),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // DAY VIEW
  // ---------------------------------------------------------------------------
  Widget _buildDayAgenda(
    Map<DateTime, List<Activity>> byDay,
    Map<DateTime, List<RaceTarget>> goalsByDay,
    Map<String, List<PlannedWorkout>> plannedByDay,
    Set<String> matchedActivityIds,
    Map<String, Activity> activitiesById,
  ) {
    final acts = byDay[_focusedDate] ?? const <Activity>[];
    final unmatchedActs =
        acts.where((a) => !matchedActivityIds.contains(a.id)).toList();
    final goals = goalsByDay[_focusedDate] ?? const <RaceTarget>[];
    final planned = plannedByDay[_dateKey(_focusedDate)] ?? const <PlannedWorkout>[];

    final totalDist = acts.fold<double>(
      0,
      (s, a) => s + (a.distanceKm.isFinite && a.distanceKm > 0 ? a.distanceKm : 0),
    );
    final totalSec = acts.fold<double>(
      0,
      (s, a) =>
          s + (a.durationSeconds.isFinite && a.durationSeconds > 0 ? a.durationSeconds : 0),
    );
    final totalElev = acts.fold<double>(
      0,
      (s, a) =>
          s + (a.elevationGainM.isFinite && a.elevationGainM > 0 ? a.elevationGainM : 0),
    );
    final totalCals = acts.fold<int>(0, (s, a) => s + (a.calories > 0 ? a.calories : 0));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Day summary metrics strip
        Row(
          children: [
            Expanded(
              child: _dayStatTile(
                'Distance',
                UnitFormatter.formatDistance(totalDist, widget.appState.unitSystem),
                CupertinoIcons.map,
                AppColors.runTertiary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _dayStatTile(
                'Duration',
                _formatDuration(totalSec),
                CupertinoIcons.time,
                AppColors.swimPrimary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _dayStatTile(
                'Elevation',
                UnitFormatter.formatElevation(totalElev, widget.appState.unitSystem),
                CupertinoIcons.arrow_up_right,
                AppColors.bikeSecondary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _dayStatTile(
                'Calories',
                totalCals > 0 ? '${NumberFormat('#,###').format(totalCals)} kcal' : '0 kcal',
                CupertinoIcons.flame,
                AppColors.strengthViolet,
              ),
            ),
          ],
        ),

        if (goals.isNotEmpty) ...[
          const SizedBox(height: 12),
          ...goals.map((g) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: g.badgeColor.withOpacity(AppColors.isDark ? 0.18 : 0.10),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: g.badgeColor.withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    Icon(CupertinoIcons.flag_fill, size: 15, color: g.badgeColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Race Goal: ${g.name} — ${g.focusDescription}',
                        style: AppTypography.headlineSm.copyWith(color: AppColors.onSurface),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              )),
        ],

        const SizedBox(height: 14),

        if (planned.isEmpty && unmatchedActs.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 20),
            decoration: BoxDecoration(
              color: AppColors.surfaceLowest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.borderDivider),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(CupertinoIcons.moon_stars, size: 28, color: AppColors.outline),
                const SizedBox(height: 10),
                Text('Rest Day', style: AppTypography.headlineMd),
                const SizedBox(height: 4),
                Text(
                  widget.appState.isSignedIn
                      ? 'No Garmin activities recorded on ${DateFormat('MMMM d, yyyy').format(_focusedDate)}.'
                      : 'Sign in with Garmin Connect to view your activities for this day.',
                  style: AppTypography.bodyMd,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          )
        else ...[
          if (planned.isNotEmpty) ...[
            Text('Planned Workouts', style: AppTypography.labelCaps),
            const SizedBox(height: 8),
            ...planned.map((w) => _buildDayPlannedWorkoutCard(
                  w,
                  matchedAct: w.matchedActivityId != null
                      ? activitiesById[w.matchedActivityId!]
                      : null,
                  brickRunAct: w.brickRunLeg?.matchedActivityId != null
                      ? activitiesById[w.brickRunLeg!.matchedActivityId!]
                      : null,
                )),
          ],
          if (unmatchedActs.isNotEmpty) ...[
            if (planned.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Completed Activities', style: AppTypography.labelCaps),
              const SizedBox(height: 8),
            ],
            ...unmatchedActs.map(_buildDayActivityCard),
          ],
        ],
      ],
    );
  }

  Widget _buildDayPlannedWorkoutCard(
    PlannedWorkout w, {
    Activity? matchedAct,
    Activity? brickRunAct,
  }) {
    final sportColor = _disciplineColor(w.discipline);
    final (archetypeLabel, archetypeColor) = _archetypeMeta(w.archetype);
    final isCompleted = w.status == WorkoutStatus.completed;
    final isSkipped = w.status == WorkoutStatus.skipped;
    final isScheduled = w.status == WorkoutStatus.scheduled;
    final isSynced = _isGarminSynced(w);
    final adh = _validAdherence(w.adherencePercent);
    final distStr = _formatPlannedDistance(w);
    final tssStr = _formatPlannedTss(w.estimatedTss);
    final zp = w.zwiftPrescription;
    final leg = w.brickRunLeg;

    final Color bgColor;
    if (isSkipped) {
      bgColor = AppColors.surfaceLow.withOpacity(AppColors.isDark ? 0.55 : 0.75);
    } else if (isCompleted) {
      bgColor = AppColors.surfaceLowest;
    } else {
      bgColor = sportColor.withOpacity(AppColors.isDark ? 0.14 : 0.08);
    }

    final (statusLabel, statusColor) = switch (w.status) {
      WorkoutStatus.scheduled => ('Scheduled', AppColors.accent),
      WorkoutStatus.completed => ('Completed', AppColors.runTertiary),
      WorkoutStatus.skipped => ('Skipped', AppColors.outline),
    };

    final cardBody = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: isScheduled
            ? null
            : Border.all(
                color: isSkipped
                    ? AppColors.borderDivider
                    : sportColor.withOpacity(0.55),
                width: 1.0,
              ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: (isSkipped ? AppColors.outline : sportColor)
                  .withOpacity(AppColors.isDark ? 0.22 : 0.13),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _disciplineIcon(w.discipline),
              size: 20,
              color: isSkipped ? AppColors.outline : sportColor,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      w.title,
                      style: AppTypography.headlineMd.copyWith(
                        color: isSkipped ? AppColors.outline : AppColors.onSurface,
                        decoration: isSkipped ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    MacStatusBadge(
                      label: _disciplineLabel(w.discipline),
                      color: isSkipped ? AppColors.outline : sportColor,
                    ),
                    MacStatusBadge(
                      label: archetypeLabel,
                      color: isSkipped ? AppColors.outline : archetypeColor,
                    ),
                    MacStatusBadge(
                      label: statusLabel,
                      color: statusColor,
                      icon: isCompleted
                          ? CupertinoIcons.checkmark_circle_fill
                          : (isSkipped ? CupertinoIcons.xmark_circle : null),
                    ),
                    if (isSynced)
                      Tooltip(
                        message: 'Synced to Garmin Watch',
                        child: MacStatusBadge(
                          label: 'Synced to Watch',
                          color: AppColors.runTertiary,
                          icon: CupertinoIcons.checkmark_shield_fill,
                        ),
                      ),
                    if (adh != null &&
                        (isCompleted ||
                            w.matchedActivityId != null ||
                            w.brickRunLeg?.matchedActivityId != null))
                      MacStatusBadge(
                        label: '${adh.round()}%',
                        color: adh >= 85
                            ? AppColors.runTertiary
                            : AppColors.bikeSecondary,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 16,
                  runSpacing: 6,
                  children: [
                    _inlineStat('Duration', '${w.estimatedDurationMinutes} min'),
                    if (distStr != null) _inlineStat('Distance', distStr),
                    if (tssStr != null) _inlineStat('Target TSS', tssStr.replaceAll(' TSS', '')),
                    if (zp != null)
                      _inlineStat('Zwift', '${zp.difficulty} • ${zp.targetTss} TSS'),
                    if (w.archetype == WorkoutArchetype.brick && leg != null)
                      _inlineStat(
                        'Brick Run',
                        'T2 -> ${leg.estimatedDurationMinutes}m Run (<=30m)',
                      ),
                  ],
                ),
                if (matchedAct != null || brickRunAct != null) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 14,
                    runSpacing: 4,
                    children: [
                      if (matchedAct != null)
                        Text(
                          'Matched: ${widget.appState.displayTitleFor(matchedAct)} (${matchedAct.movingTime})',
                          style: AppTypography.bodySm.copyWith(
                            color: AppColors.runTertiary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      if (brickRunAct != null)
                        Text(
                          'Run Leg: ${widget.appState.displayTitleFor(brickRunAct)} (${brickRunAct.movingTime})',
                          style: AppTypography.bodySm.copyWith(
                            color: AppColors.runTertiary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(CupertinoIcons.chevron_right, size: 15, color: AppColors.outline),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: ValueKey('calendar_planned_${w.id}'),
          onTap: () => widget.appState.selectPlannedWorkout(w),
          borderRadius: BorderRadius.circular(8),
          child: isScheduled
              ? CustomPaint(
                  foregroundPainter: _DashedRRectPainter(
                    color: sportColor.withOpacity(0.75),
                    strokeWidth: 1.2,
                    borderRadius: 8.0,
                    dashLength: 5.0,
                    gapLength: 3.5,
                  ),
                  child: cardBody,
                )
              : cardBody,
        ),
      ),
    );
  }

  Widget _dayStatTile(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderDivider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  label,
                  style: AppTypography.bodySm,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: AppTypography.telemetryLg,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildDayActivityCard(Activity a) {
    final color = _disciplineColor(a.discipline);
    final timeLabel = DateFormat('h:mm a').format(a.timestamp);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: ValueKey('calendar_activity_${a.id}'),
          onTap: () => widget.appState.setSelectedActivityId(a.id),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceLowest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.borderSubtle),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withOpacity(AppColors.isDark ? 0.22 : 0.13),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(_disciplineIcon(a.discipline), size: 20, color: color),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              a.title,
                              style: AppTypography.headlineMd,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          MacStatusBadge(label: _disciplineLabel(a.discipline), color: color),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        a.location.isNotEmpty ? '$timeLabel • ${a.location}' : timeLabel,
                        style: AppTypography.bodySm,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 16,
                        runSpacing: 6,
                        children: [
                          if (a.distanceKm.isFinite && a.distanceKm > 0)
                            _inlineStat('Distance', _formatDistanceShort(a)),
                          _inlineStat('Time', a.movingTime),
                          if (widget.appState.formatActivityPaceOrSpeed(a) != '—')
                            _inlineStat(
                              a.discipline == SportDiscipline.bike || a.discipline == SportDiscipline.indoorBike
                                  ? 'Avg Speed'
                                  : 'Avg Pace',
                              widget.appState.formatActivityPaceOrSpeed(a),
                            ),
                          if (a.avgHr > 0) _inlineStat('Avg HR', '${a.avgHr} bpm'),
                          if (a.elevationGainM.isFinite && a.elevationGainM > 0)
                            _inlineStat('Elev Gain', widget.appState.formatActivityElevation(a.elevationGainM)),
                          if (a.avgPowerW != null && a.avgPowerW! > 0)
                            _inlineStat('Avg Power', '${a.avgPowerW} W'),
                          if (a.calories > 0) _inlineStat('Calories', '${a.calories} kcal'),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(CupertinoIcons.chevron_right, size: 15, color: AppColors.outline),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _inlineStat(String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label: ', style: AppTypography.bodySm),
        Text(
          value,
          style: AppTypography.telemetrySm.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.onSurface,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // RACE GOALS ROW
  // ---------------------------------------------------------------------------
  Widget _buildGoalRow(RaceTarget target) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderDivider),
      ),
      child: Row(
        children: [
          MacStatusBadge(
            label: switch (target.tier) {
              RaceTier.tierA => 'A-Race',
              RaceTier.tierB => 'B-Race',
              RaceTier.tierC => 'C-Race',
            },
            color: target.badgeColor,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(target.name, style: AppTypography.headlineSm, overflow: TextOverflow.ellipsis),
                Text(target.focusDescription, style: AppTypography.bodySm, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          Text(
            target.countdownText,
            style: AppTypography.telemetryMd.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 10),
          IconButton(
            icon: Icon(CupertinoIcons.trash, size: 15, color: AppColors.outline),
            onPressed: () => widget.appState.removeRaceTarget(target.id),
            tooltip: 'Remove goal',
          ),
        ],
      ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double borderRadius;
  final double dashLength;
  final double gapLength;

  const _DashedRRectPainter({
    required this.color,
    this.strokeWidth = 1.0,
    this.borderRadius = 4.5,
    this.dashLength = 4.0,
    this.gapLength = 3.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final rect = (Offset.zero & size).deflate(strokeWidth / 2);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(borderRadius));
    final path = Path()..addRRect(rrect);

    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final next = (distance + dashLength).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance += dashLength + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) =>
      color != oldDelegate.color ||
      strokeWidth != oldDelegate.strokeWidth ||
      borderRadius != oldDelegate.borderRadius ||
      dashLength != oldDelegate.dashLength ||
      gapLength != oldDelegate.gapLength;
}
