import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../components/macos_ui.dart';
import '../models/activity.dart';
import '../models/training_plan.dart';
import '../services/garmin_workout_serializer.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../utils/physiological_metrics.dart';
import '../utils/unit_formatter.dart';

class ScheduledWorkoutDetailView extends StatefulWidget {
  final PlannedWorkout workout;
  final AppState appState;

  const ScheduledWorkoutDetailView({
    super.key,
    required this.workout,
    required this.appState,
  });

  @override
  State<ScheduledWorkoutDetailView> createState() =>
      _ScheduledWorkoutDetailViewState();
}

class _ScheduledWorkoutDetailViewState
    extends State<ScheduledWorkoutDetailView> {
  int? _hoveredSegmentIndex;
  int? _hoveredBrickSegmentIndex;
  String? _copiedTerm;

  PlannedWorkout get workout => widget.workout;
  AppState get appState => widget.appState;

  @override
  void didUpdateWidget(covariant ScheduledWorkoutDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.workout.id != oldWidget.workout.id) {
      _hoveredSegmentIndex = null;
      _hoveredBrickSegmentIndex = null;
      _copiedTerm = null;
    }
  }

  static const List<Color> _zoneColors = [
    Color(0xFF8E8E93), // Z1
    Color(0xFF007AFF), // Z2
    Color(0xFF34C759), // Z3
    Color(0xFFFF9500), // Z4
    Color(0xFFFF3B30), // Z5
  ];

  static const List<String> _zoneNames = [
    'Recovery',
    'Aerobic',
    'Tempo',
    'Threshold',
    'VO2 Max',
  ];

  static const List<double> _zoneHeights = [0.38, 0.54, 0.70, 0.85, 1.0];

  @override
  Widget build(BuildContext context) {
    final unit = appState.unitSystem;
    final zones =
        appState.activeTrainingPlan?.config.zones ?? appState.deriveAthleteZones();
    final (sportLabel, sportColor, sportIcon) = _sportMeta(workout.discipline);
    final (archetypeLabel, archetypeColor) = _archetypeMeta(workout.archetype);
    final (statusLabel, statusColor, statusIcon) = _statusMeta(workout.status);

    final primaryMatched = _findActivityById(workout.matchedActivityId);
    final brickLegMatched =
        _findActivityById(workout.brickRunLeg?.matchedActivityId);
    final showPlannedVsActual = workout.status == WorkoutStatus.completed ||
        workout.matchedActivityId != null ||
        workout.brickRunLeg?.matchedActivityId != null ||
        primaryMatched != null ||
        brickLegMatched != null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTopActionBar(
            context,
            sportLabel: sportLabel,
            sportColor: sportColor,
            sportIcon: sportIcon,
            archetypeLabel: archetypeLabel,
            archetypeColor: archetypeColor,
            statusLabel: statusLabel,
            statusColor: statusColor,
            statusIcon: statusIcon,
          ),
          if (appState.planError != null) ...[
            const SizedBox(height: 12),
            _buildErrorBanner(appState.planError!),
          ],
          const SizedBox(height: 16),
          _buildHeaderCard(unit),
          if (workout.blocks.isNotEmpty) ...[
            const SizedBox(height: 16),
            _WorkoutStructureCard(
              title: 'Workout Structure & Steps',
              targetWorkout: workout,
              zones: zones,
              unit: unit,
              hoveredIndex: _hoveredSegmentIndex,
              onHoverChanged: (idx) {
                if (idx != _hoveredSegmentIndex) {
                  setState(() => _hoveredSegmentIndex = idx);
                }
              },
            ),
          ],
          if (workout.zwiftPrescription != null) ...[
            const SizedBox(height: 16),
            _buildZwiftCard(workout.zwiftPrescription!),
          ],
          if (workout.brickRunLeg != null) ...[
            const SizedBox(height: 16),
            _buildBrickRunLegCard(workout.brickRunLeg!, zones, unit),
          ],
          if (showPlannedVsActual) ...[
            const SizedBox(height: 16),
            _buildPlannedVsActualCard(
              unit: unit,
              primaryMatched: primaryMatched,
              brickLegMatched: brickLegMatched,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTopActionBar(
    BuildContext context, {
    required String sportLabel,
    required Color sportColor,
    required IconData sportIcon,
    required String archetypeLabel,
    required Color archetypeColor,
    required String statusLabel,
    required Color statusColor,
    required IconData statusIcon,
  }) {
    final isPushable = GarminWorkoutSerializer.isGarminPushable(workout);
    final isBrick = workout.archetype == WorkoutArchetype.brick;
    final backLabel = switch (appState.currentNavIndex) {
      0 => 'Dashboard',
      1 => 'Calendar',
      2 => 'Training Plan',
      _ => 'Back',
    };

    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 10,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            MacPushButton(
              label: backLabel,
              icon: CupertinoIcons.chevron_back,
              onPressed: () => appState.selectPlannedWorkout(null),
            ),
            MacStatusBadge(
              label: sportLabel,
              color: sportColor,
              icon: sportIcon,
            ),
            MacStatusBadge(
              label: archetypeLabel,
              color: archetypeColor,
            ),
            MacStatusBadge(
              label: statusLabel,
              color: statusColor,
              icon: statusIcon,
            ),
          ],
        ),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            if (isPushable) ...[
              if (!workout.isSyncedToGarmin)
                MacPushButton(
                  label: isBrick ? 'Send Run Leg to Garmin' : 'Send to Garmin',
                  icon: CupertinoIcons.arrow_up_circle,
                  isPrimary: true,
                  isLoading: appState.isSyncingGarminWorkouts,
                  onPressed:
                      appState.isSignedIn && !appState.isSyncingGarminWorkouts
                          ? () => appState.syncWorkoutToGarmin(workout.id)
                          : null,
                )
              else ...[
                MacStatusBadge(
                  label: 'Synced to Garmin ✓',
                  color: AppColors.runTertiary,
                  icon: CupertinoIcons.checkmark_shield_fill,
                ),
                MacPushButton(
                  label: 'Remove from Garmin',
                  icon: CupertinoIcons.trash,
                  isDestructive: true,
                  isLoading: appState.isSyncingGarminWorkouts,
                  onPressed:
                      appState.isSignedIn && !appState.isSyncingGarminWorkouts
                          ? () => appState.removeWorkoutFromGarmin(workout.id)
                          : null,
                ),
              ],
            ] else
              MacStatusBadge(
                label: workout.archetype == WorkoutArchetype.zwiftRide
                    ? 'Zwift Suggestion — Not pushed to Garmin'
                    : 'Not pushed to Garmin',
                color: workout.archetype == WorkoutArchetype.zwiftRide
                    ? AppColors.bikeSecondary
                    : AppColors.outline,
                icon: workout.archetype == WorkoutArchetype.zwiftRide
                    ? CupertinoIcons.bolt_fill
                    : CupertinoIcons.minus_circle,
              ),
            if (workout.status != WorkoutStatus.completed)
              MacPushButton(
                label: 'Mark Done',
                icon: CupertinoIcons.checkmark_circle,
                onPressed: () => appState.updatePlannedWorkoutStatus(
                  workout.id,
                  WorkoutStatus.completed,
                ),
              ),
            if (workout.status != WorkoutStatus.skipped)
              MacPushButton(
                label: 'Skip',
                icon: CupertinoIcons.xmark_circle,
                onPressed: () => appState.updatePlannedWorkoutStatus(
                  workout.id,
                  WorkoutStatus.skipped,
                ),
              ),
            if (workout.status != WorkoutStatus.scheduled)
              MacPushButton(
                label: 'Reopen',
                icon: CupertinoIcons.arrow_uturn_left,
                onPressed: () => appState.updatePlannedWorkoutStatus(
                  workout.id,
                  WorkoutStatus.scheduled,
                ),
              ),
            MacPushButton(
              label: 'Reschedule',
              icon: CupertinoIcons.calendar,
              onPressed: () => _handleReschedule(context),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildErrorBanner(String error) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.errorContainer,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.error.withOpacity(0.32)),
      ),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.exclamationmark_triangle_fill,
            size: 16,
            color: AppColors.error,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              error,
              style: AppTypography.bodySm.copyWith(color: AppColors.error),
            ),
          ),
          const SizedBox(width: 8),
          MacPushButton(
            label: 'Dismiss',
            onPressed: appState.clearPlanError,
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCard(UnitSystem unit) {
    final dt = workout.scheduledDate;
    final dateDisplay = dt != null
        ? DateFormat('EEEE, MMM d, yyyy').format(dt)
        : (workout.date.isNotEmpty ? workout.date : 'Unscheduled');
    final durationDisplay = _formatMinutes(workout.estimatedDurationMinutes);
    final distKm = workout.estimatedDistanceKm;
    final hasDistance = distKm != null && distKm.isFinite && distKm > 0;
    final distanceDisplay = hasDistance
        ? UnitFormatter.formatDistance(
            distKm,
            unit,
            discipline: workout.discipline,
            decimals: workout.discipline == SportDiscipline.swim ? 0 : 1,
          )
        : null;
    final tss = workout.estimatedTss;
    final hasTss = tss != null && tss.isFinite && tss > 0;
    final adherence = workout.adherencePercent;
    final coachNotes = workout.coachNotes?.trim() ?? '';
    final rationale = workout.rationale?.trim() ?? '';

    return MacCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(workout.title, style: AppTypography.headlineLg),
          const SizedBox(height: 4),
          Text(
            dateDisplay,
            style: AppTypography.bodyMd,
          ),
          const SizedBox(height: 16),
          Divider(height: 1, color: AppColors.borderDivider),
          const SizedBox(height: 14),
          Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [
              _kpi('Planned Duration', durationDisplay),
              if (distanceDisplay != null)
                _kpi('Planned Distance', distanceDisplay),
              if (hasTss) _kpi('Target TSS', '${tss.round()}'),
              if (adherence != null && adherence.isFinite)
                _kpi('Adherence', '${adherence.round()}%'),
              if (workout.isSyncedToGarmin)
                _kpi(
                  'Garmin Watch Sync',
                  workout.garminSyncedAt != null
                      ? DateFormat('MMM d, h:mm a')
                          .format(workout.garminSyncedAt!.toLocal())
                      : 'Scheduled on Calendar',
                ),
            ],
          ),
          if (coachNotes.isNotEmpty || rationale.isNotEmpty) ...[
            const SizedBox(height: 16),
            Divider(height: 1, color: AppColors.borderDivider),
            const SizedBox(height: 12),
            if (coachNotes.isNotEmpty) ...[
              Text('Coach Notes', style: AppTypography.headlineSm),
              const SizedBox(height: 4),
              Text(
                coachNotes,
                style: AppTypography.bodyMd.copyWith(color: AppColors.onSurface),
              ),
            ],
            if (coachNotes.isNotEmpty && rationale.isNotEmpty)
              const SizedBox(height: 10),
            if (rationale.isNotEmpty) ...[
              Text('Training Rationale', style: AppTypography.headlineSm),
              const SizedBox(height: 4),
              Text(rationale, style: AppTypography.bodyMd),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildZwiftCard(ZwiftPrescription zp) {
    final notes = zp.notes?.trim() ?? '';
    final cadence = zp.cadenceFocus?.trim() ?? '';
    return MacCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.bikeSecondary.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      CupertinoIcons.bolt_fill,
                      size: 16,
                      color: AppColors.bikeSecondary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Zwift Cycling Prescription',
                    style: AppTypography.headlineMd,
                  ),
                ],
              ),
              MacStatusBadge(
                label: 'Zwift Suggestion — Not pushed to Garmin',
                color: AppColors.bikeSecondary,
                icon: CupertinoIcons.info_circle,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [
              _kpi('Bike Duration', _formatMinutes(zp.durationMinutes)),
              _kpi('Difficulty', zp.difficulty),
              _kpi('Target TSS', '${zp.targetTss} TSS'),
              _kpi('Zwift Category', zp.zwiftCategory),
              if (cadence.isNotEmpty) _kpi('Cadence Focus', cadence),
            ],
          ),
          if (zp.suggestedSearchTerms.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Suggested Zwift Search Terms',
              style: AppTypography.headlineSm,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: zp.suggestedSearchTerms.map((term) {
                final isCopied = _copiedTerm == term;
                return InkWell(
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: term));
                    if (!mounted) return;
                    setState(() => _copiedTerm = term);
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLowest,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.borderSubtle),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isCopied
                              ? CupertinoIcons.checkmark_alt
                              : CupertinoIcons.search,
                          size: 12,
                          color: isCopied
                              ? AppColors.runTertiary
                              : AppColors.bikeSecondary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isCopied ? '$term (Copied)' : term,
                          style: AppTypography.bodySm.copyWith(
                            color: AppColors.onSurface,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(notes, style: AppTypography.bodyMd),
          ],
        ],
      ),
    );
  }

  Widget _buildBrickRunLegCard(
    PlannedWorkout leg,
    AthleteZonesSnapshot zones,
    UnitSystem unit,
  ) {
    final (legArchetypeLabel, legArchetypeColor) = _archetypeMeta(leg.archetype);
    final legDist = leg.estimatedDistanceKm;
    final hasDist = legDist != null && legDist.isFinite && legDist > 0;
    final legNotes = leg.coachNotes?.trim() ?? '';

    return MacCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.runTertiary.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          CupertinoIcons.arrow_right_circle_fill,
                          size: 13,
                          color: AppColors.runTertiary,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'T2 → Run',
                          style: AppTypography.headlineSm.copyWith(
                            color: AppColors.runTertiary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(leg.title, style: AppTypography.headlineMd),
                  MacStatusBadge(
                    label: '<= 30 min',
                    color: AppColors.accent,
                    icon: CupertinoIcons.timer,
                  ),
                  MacStatusBadge(
                    label: legArchetypeLabel,
                    color: legArchetypeColor,
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (!workout.isSyncedToGarmin)
                    MacPushButton(
                      label: 'Send Run Leg to Garmin',
                      icon: CupertinoIcons.arrow_up_circle,
                      isPrimary: true,
                      isLoading: appState.isSyncingGarminWorkouts,
                      onPressed: appState.isSignedIn &&
                              !appState.isSyncingGarminWorkouts
                          ? () => appState.syncWorkoutToGarmin(workout.id)
                          : null,
                    )
                  else ...[
                    MacStatusBadge(
                      label: 'Run Leg Synced ✓',
                      color: AppColors.runTertiary,
                      icon: CupertinoIcons.checkmark_shield_fill,
                    ),
                    MacPushButton(
                      label: 'Remove from Garmin',
                      icon: CupertinoIcons.trash,
                      isDestructive: true,
                      isLoading: appState.isSyncingGarminWorkouts,
                      onPressed: appState.isSignedIn &&
                              !appState.isSyncingGarminWorkouts
                          ? () => appState.removeWorkoutFromGarmin(workout.id)
                          : null,
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 24,
            runSpacing: 10,
            children: [
              _kpi('Run Leg Duration', _formatMinutes(leg.estimatedDurationMinutes)),
              if (hasDist)
                _kpi(
                  'Run Leg Distance',
                  UnitFormatter.formatDistance(
                    legDist,
                    unit,
                    discipline: SportDiscipline.run,
                    decimals: 1,
                  ),
                ),
              if (leg.estimatedTss != null &&
                  leg.estimatedTss!.isFinite &&
                  leg.estimatedTss! > 0)
                _kpi('Run Leg TSS', '${leg.estimatedTss!.round()}'),
            ],
          ),
          if (legNotes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(legNotes, style: AppTypography.bodyMd),
          ],
          if (leg.blocks.isNotEmpty) ...[
            const SizedBox(height: 16),
            Divider(height: 1, color: AppColors.borderDivider),
            const SizedBox(height: 14),
            _WorkoutStructureBody(
              targetWorkout: leg,
              zones: zones,
              unit: unit,
              hoveredIndex: _hoveredBrickSegmentIndex,
              onHoverChanged: (idx) {
                if (idx != _hoveredBrickSegmentIndex) {
                  setState(() => _hoveredBrickSegmentIndex = idx);
                }
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPlannedVsActualCard({
    required UnitSystem unit,
    required Activity? primaryMatched,
    required Activity? brickLegMatched,
  }) {
    final missingMatchedId =
        workout.matchedActivityId ?? workout.brickRunLeg?.matchedActivityId;

    return MacCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    CupertinoIcons.checkmark_seal_fill,
                    size: 16,
                    color: AppColors.runTertiary,
                  ),
                  const SizedBox(width: 8),
                  Text('Planned vs Actual', style: AppTypography.headlineMd),
                ],
              ),
              if (workout.adherencePercent != null &&
                  workout.adherencePercent!.isFinite)
                MacStatusBadge(
                  label: '${workout.adherencePercent!.round()}% Adherence',
                  color: workout.adherencePercent! >= 85
                      ? AppColors.runTertiary
                      : AppColors.bikeSecondary,
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (primaryMatched == null && brickLegMatched == null)
            Text(
              missingMatchedId != null
                  ? 'Marked completed (matched activity #$missingMatchedId is not currently loaded in local history).'
                  : 'Marked completed manually without a linked Garmin activity.',
              style: AppTypography.bodyMd,
            )
          else ...[
            if (primaryMatched != null)
              _buildComparisonBlock(
                planned: workout,
                actual: primaryMatched,
                unit: unit,
                heading: workout.archetype == WorkoutArchetype.brick
                    ? 'Bike Leg Comparison'
                    : 'Session Comparison',
              ),
            if (primaryMatched != null && brickLegMatched != null)
              const SizedBox(height: 14),
            if (brickLegMatched != null && workout.brickRunLeg != null)
              _buildComparisonBlock(
                planned: workout.brickRunLeg!,
                actual: brickLegMatched,
                unit: unit,
                heading: 'Brick Run Leg Comparison',
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildComparisonBlock({
    required PlannedWorkout planned,
    required Activity actual,
    required UnitSystem unit,
    required String heading,
  }) {
    final plannedDist = planned.estimatedDistanceKm;
    final plannedDistText =
        (plannedDist != null && plannedDist.isFinite && plannedDist > 0)
            ? UnitFormatter.formatDistance(
                plannedDist,
                unit,
                discipline: planned.discipline,
                decimals: planned.discipline == SportDiscipline.swim ? 0 : 1,
              )
            : '—';
    final actualDistText =
        actual.distanceKm.isFinite && actual.distanceKm > 0
            ? appState.formatActivityDistance(actual, decimals: 1)
            : '—';
    final actualPaceText = appState.formatActivityPaceOrSpeed(actual);
    final actualHrText = actual.avgHr > 0 ? '${actual.avgHr} bpm' : '—';
    final plannedTss = planned.estimatedTss;
    final plannedTssText =
        (plannedTss != null && plannedTss.isFinite) ? '${plannedTss.round()}' : '—';
    final adherence = planned.adherencePercent;
    final adherenceText =
        (adherence != null && adherence.isFinite) ? '${adherence.round()}%' : '—';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderDivider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(heading, style: AppTypography.labelCaps),
                  const SizedBox(height: 2),
                  Text(
                    appState.displayTitleFor(actual),
                    style: AppTypography.headlineSm,
                  ),
                ],
              ),
              MacPushButton(
                label: 'Open Activity Details',
                icon: CupertinoIcons.arrow_up_right_square,
                onPressed: () => appState.setSelectedActivityId(actual.id),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final sideBySide = constraints.maxWidth >= 520;
              final plannedCol = _comparisonColumn(
                title: 'PLANNED',
                rows: [
                  ('Duration', _formatMinutes(planned.estimatedDurationMinutes)),
                  ('Distance', plannedDistText),
                  (
                    'Target TSS',
                    plannedTssText,
                  ),
                ],
              );
              final actualCol = _comparisonColumn(
                title: 'ACTUAL',
                rows: [
                  ('Duration', actual.movingTime),
                  ('Distance', actualDistText),
                  ('Avg Pace / Speed', actualPaceText),
                  ('Avg HR', actualHrText),
                  ('Adherence', adherenceText),
                ],
              );

              if (sideBySide) {
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: plannedCol),
                      Container(
                        width: 1,
                        margin: const EdgeInsets.symmetric(horizontal: 14),
                        color: AppColors.borderDivider,
                      ),
                      Expanded(child: actualCol),
                    ],
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  plannedCol,
                  const SizedBox(height: 12),
                  Divider(height: 1, color: AppColors.borderDivider),
                  const SizedBox(height: 12),
                  actualCol,
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _comparisonColumn({
    required String title,
    required List<(String, String)> rows,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTypography.labelCaps),
        const SizedBox(height: 8),
        for (var i = 0; i < rows.length; i++) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  rows[i].$1,
                  style: AppTypography.bodySm,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                rows[i].$2,
                style: AppTypography.telemetryMd.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (i < rows.length - 1) const SizedBox(height: 6),
        ],
      ],
    );
  }

  Future<void> _handleReschedule(BuildContext context) async {
    final firstDate = DateTime(2020);
    final lastDate = DateTime(2100);
    DateTime initial = workout.scheduledDate ?? DateTime.now();
    if (initial.isBefore(firstDate)) {
      initial = firstDate;
    } else if (initial.isAfter(lastDate)) {
      initial = lastDate;
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    if (picked != null && mounted) {
      await appState.reschedulePlannedWorkout(workout.id, picked);
    }
  }

  Activity? _findActivityById(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final a in appState.activities) {
      if (a.id == id) return a;
    }
    return null;
  }

  Widget _kpi(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: AppTypography.bodySm),
        const SizedBox(height: 2),
        Text(value, style: AppTypography.telemetryLg),
      ],
    );
  }

  static String _formatMinutes(int minutes) {
    if (minutes <= 0) return '0 min';
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  static (String, Color, IconData) _sportMeta(SportDiscipline d) {
    return switch (d) {
      SportDiscipline.run => (
          'Run',
          AppColors.runTertiary,
          CupertinoIcons.flame,
        ),
      SportDiscipline.swim => (
          'Swim',
          AppColors.swimPrimary,
          CupertinoIcons.drop_fill,
        ),
      SportDiscipline.bike => (
          'Bike',
          AppColors.bikeSecondary,
          CupertinoIcons.speedometer,
        ),
      SportDiscipline.indoorBike => (
          'Indoor Bike',
          AppColors.bikeSecondary,
          CupertinoIcons.bolt_fill,
        ),
      SportDiscipline.strength => (
          'Strength',
          AppColors.strengthViolet,
          CupertinoIcons.sportscourt,
        ),
    };
  }

  static (String, Color) _archetypeMeta(WorkoutArchetype a) {
    return switch (a) {
      WorkoutArchetype.intervals => ('Intervals', AppColors.error),
      WorkoutArchetype.threshold => ('Threshold', AppColors.bikeSecondary),
      WorkoutArchetype.easy => ('Easy', AppColors.runTertiary),
      WorkoutArchetype.long => ('Long', AppColors.accent),
      WorkoutArchetype.zwiftRide => ('Zwift Ride', AppColors.bikeSecondary),
      WorkoutArchetype.brick => ('Brick', AppColors.strengthViolet),
      WorkoutArchetype.strength => ('Strength', AppColors.strengthViolet),
      WorkoutArchetype.rest => ('Rest', AppColors.outline),
    };
  }

  static (String, Color, IconData) _statusMeta(WorkoutStatus s) {
    return switch (s) {
      WorkoutStatus.scheduled => (
          'Scheduled',
          AppColors.accent,
          CupertinoIcons.calendar,
        ),
      WorkoutStatus.completed => (
          'Completed',
          AppColors.runTertiary,
          CupertinoIcons.checkmark_circle_fill,
        ),
      WorkoutStatus.skipped => (
          'Skipped',
          AppColors.outline,
          CupertinoIcons.xmark_circle,
        ),
    };
  }
}

class _WorkoutStructureCard extends StatelessWidget {
  final String title;
  final PlannedWorkout targetWorkout;
  final AthleteZonesSnapshot zones;
  final UnitSystem unit;
  final int? hoveredIndex;
  final ValueChanged<int?> onHoverChanged;

  const _WorkoutStructureCard({
    required this.title,
    required this.targetWorkout,
    required this.zones,
    required this.unit,
    required this.hoveredIndex,
    required this.onHoverChanged,
  });

  @override
  Widget build(BuildContext context) {
    return MacCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: AppTypography.headlineMd),
          const SizedBox(height: 14),
          _WorkoutStructureBody(
            targetWorkout: targetWorkout,
            zones: zones,
            unit: unit,
            hoveredIndex: hoveredIndex,
            onHoverChanged: onHoverChanged,
          ),
        ],
      ),
    );
  }
}

class _VisualSegment {
  final int zone;
  final double estimatedSeconds;
  final String label;
  final String tooltip;

  const _VisualSegment({
    required this.zone,
    required this.estimatedSeconds,
    required this.label,
    required this.tooltip,
  });
}

class _WorkoutStructureBody extends StatelessWidget {
  final PlannedWorkout targetWorkout;
  final AthleteZonesSnapshot zones;
  final UnitSystem unit;
  final int? hoveredIndex;
  final ValueChanged<int?> onHoverChanged;

  const _WorkoutStructureBody({
    required this.targetWorkout,
    required this.zones,
    required this.unit,
    required this.hoveredIndex,
    required this.onHoverChanged,
  });

  @override
  Widget build(BuildContext context) {
    final segments = _flattenSegments();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (segments.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.surfaceLowest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.borderDivider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 76,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (var i = 0; i < segments.length; i++)
                          _buildBarSegment(
                            segments[i],
                            i,
                            i == segments.length - 1,
                            totalSegments: segments.length,
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 14,
                  runSpacing: 6,
                  children: List.generate(5, (index) {
                    final zone = index + 1;
                    final color =
                        _ScheduledWorkoutDetailViewState._zoneColors[index];
                    final name =
                        _ScheduledWorkoutDetailViewState._zoneNames[index];
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'Z$zone $name',
                          style: AppTypography.bodySm.copyWith(
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    );
                  }),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        _buildStepsTable(),
      ],
    );
  }

  Widget _buildBarSegment(
    _VisualSegment seg,
    int index,
    bool isLast, {
    required int totalSegments,
  }) {
    final color = _ScheduledWorkoutDetailViewState._zoneColors[seg.zone - 1];
    final heightFactor =
        _ScheduledWorkoutDetailViewState._zoneHeights[seg.zone - 1];
    final weight = seg.estimatedSeconds.isFinite
        ? seg.estimatedSeconds.round().clamp(1, 100000)
        : 60;
    final isHovered = hoveredIndex == index;
    final hasHover = hoveredIndex != null;
    final opacity = hasHover ? (isHovered ? 1.0 : 0.45) : 0.9;

    return Expanded(
      flex: weight,
      child: Tooltip(
        message: seg.tooltip,
        child: MouseRegion(
          onEnter: (_) => onHoverChanged(index),
          onExit: (_) => onHoverChanged(null),
          child: Container(
            height: 76 * heightFactor,
            margin: EdgeInsets.only(
              right: isLast || totalSegments > 120 ? 0 : 1.5,
            ),
            decoration: BoxDecoration(
              color: color.withOpacity(opacity),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepsTable() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: AppColors.surfaceLowest,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 112,
                child: Text(
                  'Step',
                  style: AppTypography.labelCaps,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  'Duration / Dist',
                  style: AppTypography.labelCaps,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  'Target',
                  style: AppTypography.labelCaps,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  'Notes',
                  style: AppTypography.labelCaps,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < targetWorkout.blocks.length; i++) ...[
          _buildBlockWidget(targetWorkout.blocks[i]),
          if (i < targetWorkout.blocks.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _buildBlockWidget(WorkoutBlock block) {
    final steps = block.effectiveSteps;
    if (steps.isEmpty) return const SizedBox.shrink();

    final isRepeatBlock = block.repeatCount > 1 && steps.isNotEmpty;
    if (isRepeatBlock) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surfaceLowest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                MacStatusBadge(
                  label: '${block.repeatCount}× Repeat',
                  color: AppColors.accent,
                  icon: CupertinoIcons.repeat,
                ),
                const SizedBox(width: 8),
                Text(
                  '${steps.length} ${steps.length == 1 ? 'step' : 'steps'} per set',
                  style: AppTypography.bodySm,
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (var j = 0; j < steps.length; j++) ...[
              _buildStepRow(steps[j], indented: true),
              if (j < steps.length - 1) const SizedBox(height: 6),
            ],
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var j = 0; j < steps.length; j++) ...[
          _buildStepRow(steps[j]),
          if (j < steps.length - 1) const SizedBox(height: 6),
        ],
      ],
    );
  }

  Widget _buildStepRow(WorkoutStep step, {bool indented = false}) {
    final zone = _inferZone(step);
    final zoneColor = _ScheduledWorkoutDetailViewState._zoneColors[zone - 1];
    final kindLabel = _stepKindLabel(step.kind);
    final endText = _formatStepEndCondition(step);
    final targetText = _formatStepTarget(step);
    final stroke = step.strokeType?.trim() ?? '';
    final notes = step.notes?.trim() ?? '';

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: indented ? 8 : 10,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: indented ? AppColors.surfaceContainer : AppColors.surfaceLowest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.borderDivider),
      ),
      child: Row(
        children: [
          SizedBox(
            width: indented ? 104 : 112,
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 16,
                  decoration: BoxDecoration(
                    color: zoneColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    kindLabel,
                    style: AppTypography.headlineSm.copyWith(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              endText,
              style: AppTypography.telemetryMd.copyWith(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 3,
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  targetText,
                  style: AppTypography.telemetrySm.copyWith(
                    color: AppColors.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (stroke.isNotEmpty)
                  MacStatusBadge(
                    label: stroke,
                    color: AppColors.swimPrimary,
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              notes.isNotEmpty ? notes : '—',
              style: AppTypography.bodySm.copyWith(
                color: notes.isNotEmpty
                    ? AppColors.onSurfaceVariant
                    : AppColors.outline,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }

  List<_VisualSegment> _flattenSegments() {
    final result = <_VisualSegment>[];
    for (final block in targetWorkout.blocks) {
      final steps = block.effectiveSteps;
      if (steps.isEmpty) continue;
      final reps =
          (block.repeatCount > 1 && block.effectiveSteps.isNotEmpty)
              ? block.repeatCount
              : 1;
      for (var r = 0; r < reps; r++) {
        for (final step in steps) {
          final zone = _inferZone(step);
          final seconds = _estimateStepSeconds(step);
          final kindLabel = _stepKindLabel(step.kind);
          final endText = _formatStepEndCondition(step);
          final targetText = _formatStepTarget(step);
          final repPrefix = reps > 1 ? '[${r + 1}/$reps] ' : '';
          result.add(
            _VisualSegment(
              zone: zone,
              estimatedSeconds: seconds,
              label: kindLabel,
              tooltip: '$repPrefix$kindLabel • $endText • $targetText (Z$zone)',
            ),
          );
        }
      }
    }
    return result;
  }

  double _estimateStepSeconds(WorkoutStep step) {
    final val = step.endValue;
    if (step.endCondition == StepEndCondition.time &&
        val != null &&
        val.isFinite &&
        val > 0) {
      return val;
    }
    if (step.endCondition == StepEndCondition.distance &&
        val != null &&
        val.isFinite &&
        val > 0) {
      double? paceSpeed;
      if (step.targetKind == StepTargetKind.paceMps) {
        final low = step.targetLow;
        final high = step.targetHigh;
        final validLow = (low != null && low.isFinite && low > 0) ? low : null;
        final validHigh =
            (high != null && high.isFinite && high > 0) ? high : null;
        if (validLow != null && validHigh != null) {
          paceSpeed = (validLow + validHigh) / 2.0;
        } else {
          paceSpeed = validLow ?? validHigh;
        }
      }
      final double fallbackSpeed;
      if (targetWorkout.discipline == SportDiscipline.swim) {
        final css = zones.swimCssSecPer100m;
        fallbackSpeed = (css != null && css.isFinite && css > 0)
            ? (100.0 / css)
            : (100.0 / 110.0);
      } else {
        fallbackSpeed = zones.runThresholdSpeedMps ?? (1000.0 / 300.0);
      }
      final speed = (paceSpeed != null && paceSpeed > 0)
          ? paceSpeed
          : fallbackSpeed;
      return (val / speed).clamp(15.0, 14400.0);
    }
    // lapButton or missing endValue
    if (step.kind == StepKind.rest || step.kind == StepKind.recovery) {
      return 60.0;
    }
    return 300.0;
  }

  int _inferZone(WorkoutStep step) {
    if (step.targetKind == StepTargetKind.heartRateZone) {
      final low = step.targetLow;
      final high = step.targetHigh;
      final z = high ?? low;
      if (z != null && z.isFinite) {
        return z.round().clamp(1, 5);
      }
    }

    if (step.targetKind == StepTargetKind.heartRateBpm) {
      final low = step.targetLow;
      final high = step.targetHigh;
      final mid = (low != null && high != null)
          ? (low + high) / 2.0
          : (low ?? high);
      if (mid != null && mid.isFinite && mid > 0) {
        if (zones.hrZones.isNotEmpty) {
          for (final zr in zones.hrZones) {
            if (mid <= zr.highBpm) {
              return zr.zone.clamp(1, 5);
            }
          }
          return 5;
        }
        final pctMax = mid / zones.maxHr;
        if (pctMax < 0.65) return 1;
        if (pctMax < 0.77) return 2;
        if (pctMax < 0.85) return 3;
        if (pctMax < 0.93) return 4;
        return 5;
      }
    }

    if (step.targetKind == StepTargetKind.paceMps) {
      final low = step.targetLow;
      final high = step.targetHigh;
      final mid = (low != null && high != null)
          ? (low + high) / 2.0
          : (low ?? high);
      if (mid != null && mid.isFinite && mid > 0) {
        final double? thresholdSpeed;
        if (targetWorkout.discipline == SportDiscipline.swim) {
          final css = zones.swimCssSecPer100m;
          thresholdSpeed =
              (css != null && css.isFinite && css > 0) ? 100.0 / css : null;
        } else {
          thresholdSpeed = zones.runThresholdSpeedMps;
        }
        if (thresholdSpeed != null &&
            thresholdSpeed.isFinite &&
            thresholdSpeed > 0) {
          final ratio = mid / thresholdSpeed;
          if (ratio < 0.78) return 1;
          if (ratio < 0.90) return 2;
          if (ratio < 0.98) return 3;
          if (ratio < 1.05) return 4;
          return 5;
        }
      }
    }

    return switch (step.kind) {
      StepKind.rest || StepKind.recovery => 1,
      StepKind.warmup || StepKind.cooldown || StepKind.steady => 2,
      StepKind.interval => 4,
    };
  }

  String _formatStepEndCondition(WorkoutStep step) {
    final val = step.endValue;
    switch (step.endCondition) {
      case StepEndCondition.time:
        return formatZoneDuration(val ?? 0);
      case StepEndCondition.distance:
        final meters = (val != null && val.isFinite && val > 0) ? val : 0.0;
        if (targetWorkout.discipline == SportDiscipline.swim) {
          return UnitFormatter.formatDistance(
            meters / 1000.0,
            unit,
            discipline: SportDiscipline.swim,
          );
        }
        if (unit == UnitSystem.metric && meters < 1000) {
          return '${meters.round()} m';
        }
        return UnitFormatter.formatDistance(
          meters / 1000.0,
          unit,
          discipline: targetWorkout.discipline,
          decimals: 2,
        );
      case StepEndCondition.lapButton:
        return 'Lap Button';
    }
  }

  String _formatStepTarget(WorkoutStep step) {
    switch (step.targetKind) {
      case StepTargetKind.none:
        return 'Open / Easy Effort';

      case StepTargetKind.heartRateZone:
        final rawLow = step.targetLow;
        final rawHigh = step.targetHigh;
        final validLow = (rawLow != null && rawLow.isFinite) ? rawLow : null;
        final validHigh =
            (rawHigh != null && rawHigh.isFinite) ? rawHigh : null;
        final lowZ = (validLow ?? validHigh)?.round().clamp(1, 5);
        final highZ = (validHigh ?? validLow)?.round().clamp(1, 5);
        if (lowZ == null || highZ == null) return 'HR Zone';
        final minZ = lowZ <= highZ ? lowZ : highZ;
        final maxZ = lowZ <= highZ ? highZ : lowZ;
        final zLabel = minZ == maxZ ? 'Z$minZ' : 'Z$minZ–Z$maxZ';

        if (zones.hrZones.isNotEmpty) {
          HrZoneRange? rLow;
          HrZoneRange? rHigh;
          for (final zr in zones.hrZones) {
            if (zr.zone == minZ) rLow = zr;
            if (zr.zone == maxZ) rHigh = zr;
          }
          if (rLow != null && rHigh != null) {
            return '$zLabel (${rLow.lowBpm}–${rHigh.highBpm} bpm)';
          }
        }
        return zLabel;

      case StepTargetKind.heartRateBpm:
        final rawLow = step.targetLow;
        final rawHigh = step.targetHigh;
        final low = (rawLow != null && rawLow.isFinite) ? rawLow : null;
        final high = (rawHigh != null && rawHigh.isFinite) ? rawHigh : null;
        if (low != null && high != null) {
          if (low.round() == high.round()) return '${low.round()} bpm';
          return '${low.round()}–${high.round()} bpm';
        }
        final single = low ?? high;
        return single != null ? '${single.round()} bpm' : 'HR Target';

      case StepTargetKind.paceMps:
        final rawLow = step.targetLow;
        final rawHigh = step.targetHigh;
        final low = (rawLow != null && rawLow.isFinite && rawLow > 0)
            ? rawLow
            : null;
        final high = (rawHigh != null && rawHigh.isFinite && rawHigh > 0)
            ? rawHigh
            : null;
        if (low != null && high != null) {
          final slowText = UnitFormatter.formatPaceOrSpeed(
            targetWorkout.discipline,
            low,
            unit,
          );
          final fastText = UnitFormatter.formatPaceOrSpeed(
            targetWorkout.discipline,
            high,
            unit,
          );
          if (slowText == fastText) return fastText;
          return '$fastText – $slowText';
        }
        final single = low ?? high;
        if (single != null) {
          return UnitFormatter.formatPaceOrSpeed(
            targetWorkout.discipline,
            single,
            unit,
          );
        }
        return 'Pace Target';
    }
  }

  static String _stepKindLabel(StepKind kind) {
    return switch (kind) {
      StepKind.warmup => 'Warmup',
      StepKind.interval => 'Interval',
      StepKind.recovery => 'Recovery',
      StepKind.cooldown => 'Cooldown',
      StepKind.rest => 'Rest',
      StepKind.steady => 'Steady',
    };
  }
}
