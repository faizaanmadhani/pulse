import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../state/app_state.dart';
import '../models/activity.dart';
import '../utils/unit_formatter.dart';
import '../components/chart_painters.dart';
import '../components/garmin_sign_in_dialog.dart';
import '../components/macos_heatmap_view.dart';
import '../components/macos_ui.dart';
import 'activities_view.dart';

class DashboardView extends StatelessWidget {
  final AppState appState;

  const DashboardView({super.key, required this.appState});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!appState.isSignedIn) ...[
            _buildConnectGarminBanner(context),
            const SizedBox(height: 16),
          ],

          if (appState.isSignedIn && appState.syncError != null) ...[
            _buildSyncErrorBanner(),
            const SizedBox(height: 14),
          ],

          // Row 1: Hero 3-Card Strip (Race Targets, Physiological Readiness & ACWR, Garmin Health Indices)
          _buildHeroTopStrip(context),

          const SizedBox(height: 16),

          // Row 2: Main 50% / 50% Split (Square-like GPS Heatmap on left, 2x2 Sport Cards + Charts on right)
          _buildMainSplitSection(context),

          const SizedBox(height: 18),

          // Row 3: Recent Garmin Activities (Strava-style feed cards with mini maps & telemetry)
          _buildRecentActivitiesCard(context),
        ],
      ),
    );
  }

  Widget _buildMainSplitSection(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final mapCanvasHeight = (screenHeight * 0.48).clamp(395.0, 480.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 960;
        final heatmap = MacosHeatmapView(
          activities: appState.activities,
          activeFilter: appState.mapLayerFilter,
          onFilterChanged: appState.setMapLayerFilter,
          isSignedIn: appState.isSignedIn,
          isLoadingRoutes: appState.isLoadingPolylines,
          isImperial: appState.isImperial,
          height: isWide ? mapCanvasHeight : 360,
        );

        final rightColumn = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildMultiSportStrip(),
            const SizedBox(height: 12),
            _buildTrainingOverviewRow(),
          ],
        );

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 1, child: heatmap),
              const SizedBox(width: 14),
              Expanded(flex: 1, child: rightColumn),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            heatmap,
            const SizedBox(height: 14),
            rightColumn,
          ],
        );
      },
    );
  }

  Widget _buildConnectGarminBanner(BuildContext context) {
    return MacCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 12,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  CupertinoIcons.waveform_path_ecg,
                  size: 20,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(width: 14),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 580),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Connect Your Garmin Account', style: AppTypography.headlineMd),
                    const SizedBox(height: 2),
                    Text(
                      'Sign in with Garmin Connect to populate your GPS heatmap, multi-sport totals, training load, HRV, and activities with live data.',
                      style: AppTypography.bodySm,
                    ),
                  ],
                ),
              ),
            ],
          ),
          MacPushButton(
            label: 'Sign in with Garmin',
            icon: CupertinoIcons.person_crop_circle,
            isPrimary: true,
            onPressed: () => showGarminSignInDialog(context, appState),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncErrorBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.errorContainer,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.error.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(CupertinoIcons.exclamationmark_triangle_fill, size: 16, color: AppColors.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Garmin sync warning: ${appState.syncError}',
              style: AppTypography.bodySm.copyWith(color: AppColors.error),
            ),
          ),
          MacPushButton(
            label: 'Retry',
            onPressed: appState.isSyncing ? null : () => appState.syncFromGarmin(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroTopStrip(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 980;
        final raceCard = _buildRaceTargetsCard();
        final acwrCard = _buildAcwrReadinessCard();
        final healthCard = _buildHealthIndicesCard();

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 4, child: raceCard),
              const SizedBox(width: 12),
              Expanded(flex: 5, child: acwrCard),
              const SizedBox(width: 12),
              Expanded(flex: 4, child: healthCard),
            ],
          );
        }

        return Column(
          children: [
            acwrCard,
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: raceCard),
                const SizedBox(width: 12),
                Expanded(child: healthCard),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildRaceTargetsCard() {
    final upcoming = appState.raceTargets.take(2).toList();

    return MacCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(CupertinoIcons.flag_fill, size: 14, color: AppColors.bikeSecondary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Race Horizon',
                        style: AppTypography.headlineSm,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: () => appState.setNavIndex(1),
                borderRadius: BorderRadius.circular(5),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Text(
                    upcoming.isEmpty ? '+ Add Race' : 'Calendar',
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (upcoming.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surfaceLowest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.borderDivider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No race goals scheduled',
                    style: AppTypography.bodyMd.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Add an A/B/C race in Calendar to track countdowns and multi-event blocks.',
                    style: AppTypography.bodySm,
                  ),
                ],
              ),
            )
          else
            ...upcoming.asMap().entries.map((entry) {
              final target = entry.value;
              return Padding(
                padding: EdgeInsets.only(bottom: entry.key == upcoming.length - 1 ? 0 : 10),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLowest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.borderDivider),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              target.name,
                              style: AppTypography.headlineSm,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              DateFormat('MMM d, y').format(target.raceDate),
                              style: AppTypography.bodySm,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${target.daysRemaining}',
                            style: AppTypography.telemetryLg.copyWith(
                              color: target.badgeColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text('days', style: AppTypography.bodySm.copyWith(fontSize: 10)),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildAcwrReadinessCard() {
    final p = appState.profile;
    final trend = appState.acwrTrend14d;
    final statusLabel = p.acwrStatus ?? (appState.isSignedIn ? 'Building' : 'Not Synced');
    final statusColor = switch (p.acwrStatus) {
      'Optimal' || 'Sweet Spot' => AppColors.runTertiary,
      'High Load' || 'Overreaching' => AppColors.error,
      'Building' => AppColors.bikeSecondary,
      _ => AppColors.outline,
    };

    return MacCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(CupertinoIcons.gauge, size: 14, color: statusColor),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Training Readiness (ACWR)',
                        style: AppTypography.headlineSm,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    MacStatusBadge(label: statusLabel, color: statusColor),
                  ],
                ),
              ),
              if (p.tsbForm != null)
                Text(
                  'Form ${p.tsbForm! >= 0 ? '+' : ''}${p.tsbForm!.toStringAsFixed(0)}',
                  style: AppTypography.telemetrySm.copyWith(
                    color: p.tsbForm! >= 0 ? AppColors.runTertiary : AppColors.bikeSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          p.acwrRatio != null ? p.acwrRatio!.toStringAsFixed(2) : '—',
                          style: AppTypography.displayHero,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Target 0.8 – 1.3',
                            style: AppTypography.bodySm,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      appState.isSignedIn
                          ? 'Acute-to-Chronic Workload Ratio from Garmin sessions'
                          : 'Sign in to compute Fitness, Fatigue & ACWR',
                      style: AppTypography.bodySm,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SizedBox(
                    width: 96,
                    height: 36,
                    child: trend.length >= 2
                        ? InteractiveAcwrSparkline(
                            values: trend,
                            labels: appState.pmcSeries.length >= trend.length
                                ? appState.pmcSeries
                                    .sublist(appState.pmcSeries.length - trend.length)
                                    .map((pt) => DateFormat('MMM d').format(pt.date))
                                    .toList()
                                : null,
                          )
                        : Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppColors.surfaceLowest,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text('14d trend', style: AppTypography.bodySm.copyWith(fontSize: 10)),
                          ),
                  ),
                  const SizedBox(height: 2),
                  Text('14-Day Trend', style: AppTypography.bodySm.copyWith(fontSize: 10)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _miniStatTile(
                  'Fitness (CTL)',
                  p.ctlFitness != null ? p.ctlFitness!.toStringAsFixed(0) : '—',
                  AppColors.swimPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _miniStatTile(
                  'Fatigue (ATL)',
                  p.atlFatigue != null ? p.atlFatigue!.toStringAsFixed(0) : '—',
                  AppColors.bikeSecondary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _miniStatTile(
                  'Rest HR / HRV',
                  p.restingHr != null || p.hrvMs != null
                      ? '${p.restingHr ?? '—'} / ${p.hrvMs != null ? '${p.hrvMs}ms' : '—'}'
                      : '—',
                  AppColors.runTertiary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStatTile(String label, String value, Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceLowest,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: AppColors.borderDivider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTypography.bodySm.copyWith(fontSize: 10),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: AppTypography.telemetryMd.copyWith(
              color: accent,
              fontWeight: FontWeight.w700,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildHealthIndicesCard() {
    final p = appState.profile;
    return MacCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Garmin Biometrics',
                  style: AppTypography.headlineSm,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              MacStatusBadge(
                label: appState.isSignedIn ? '${appState.activities.length} synced' : 'Offline',
                color: appState.isSignedIn ? AppColors.accent : AppColors.outline,
              ),
            ],
          ),
          const SizedBox(height: 10),
          _indexRow(
            icon: CupertinoIcons.wind,
            color: AppColors.swimPrimary,
            label: 'VO2 Max',
            value: p.vo2MaxEst != null ? p.vo2MaxEst!.toStringAsFixed(1) : '—',
            unit: 'mL/kg',
          ),
          const SizedBox(height: 6),
          _indexRow(
            icon: CupertinoIcons.heart_fill,
            color: AppColors.error,
            label: 'Resting Heart Rate',
            value: p.restingHr != null ? '${p.restingHr}' : '—',
            unit: 'bpm',
          ),
          const SizedBox(height: 6),
          _indexRow(
            icon: CupertinoIcons.flame_fill,
            color: AppColors.bikeSecondary,
            label: 'Daily Steps',
            value: p.dailySteps != null ? NumberFormat.decimalPattern().format(p.dailySteps) : '—',
            unit: 'steps',
          ),
          const SizedBox(height: 6),
          _indexRow(
            icon: CupertinoIcons.device_laptop,
            color: AppColors.runTertiary,
            label: 'Paired Devices',
            value: appState.isSignedIn ? '${appState.connectedDevices.length}' : '—',
            unit: 'Garmin',
          ),
        ],
      ),
    );
  }

  Widget _indexRow({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
    required String unit,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceLowest,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: AppColors.borderDivider),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: AppTypography.bodySm.copyWith(color: AppColors.onSurface),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            value,
            style: AppTypography.telemetryMd.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 4),
          Text(unit, style: AppTypography.bodySm.copyWith(fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildMultiSportStrip() {
    final cutoff30 = DateTime.now().subtract(const Duration(days: 30));
    final recent30 = appState.activities.where((a) => a.timestamp.isAfter(cutoff30)).toList();

    List<Activity> ofSport(bool Function(Activity) test) => recent30.where(test).toList();

    final swims = ofSport((a) => a.discipline == SportDiscipline.swim);
    final bikes = ofSport(
      (a) => a.discipline == SportDiscipline.bike || a.discipline == SportDiscipline.indoorBike,
    );
    final runs = ofSport((a) => a.discipline == SportDiscipline.run);
    final strengths = ofSport((a) => a.discipline == SportDiscipline.strength);

    final unit = appState.unitSystem;

    String fmtDuration(List<Activity> list) {
      final sec = list.fold<double>(0, (s, a) => s + a.durationSeconds);
      return UnitFormatter.formatStrengthDuration(sec);
    }

    final runCard = _buildSportCard(
      title: 'Running',
      icon: CupertinoIcons.flame_fill,
      color: AppColors.runTertiary,
      volume7d: appState.runVolume7d,
      stat30d: appState.isSignedIn
          ? '30d: ${UnitFormatter.formatDistance(runs.fold<double>(0, (s, a) => s + a.distanceKm), unit)} • ${runs.length} runs'
          : '7d & 30d road / trail runs',
      meta: appState.isSignedIn
          ? '${UnitFormatter.formatElevation(runs.fold<double>(0, (s, a) => s + a.elevationGainM), unit)} elev'
          : '—',
      onTap: () => appState.setNavIndex(3),
    );

    final bikeCard = _buildSportCard(
      title: 'Cycling',
      icon: Icons.directions_bike_rounded,
      color: AppColors.bikeSecondary,
      volume7d: appState.bikeVolume7d,
      stat30d: appState.isSignedIn
          ? '30d: ${UnitFormatter.formatDistance(bikes.fold<double>(0, (s, a) => s + a.distanceKm), unit)} • ${bikes.length} rides'
          : '7d & 30d road / indoor trainer',
      meta: appState.isSignedIn
          ? '${UnitFormatter.formatElevation(bikes.fold<double>(0, (s, a) => s + a.elevationGainM), unit)} elev'
          : '—',
      onTap: () => appState.setNavIndex(3),
    );

    final swimCard = _buildSportCard(
      title: 'Swimming',
      icon: CupertinoIcons.drop_fill,
      color: AppColors.swimPrimary,
      volume7d: appState.swimVolume7d,
      stat30d: appState.isSignedIn
          ? '30d: ${UnitFormatter.formatDistance(swims.fold<double>(0, (s, a) => s + a.distanceKm), unit, discipline: SportDiscipline.swim)} • ${swims.length} sessions'
          : '7d & 30d pool / open water',
      meta: appState.isSignedIn ? fmtDuration(swims) : '—',
      onTap: () => appState.setNavIndex(3),
    );

    final strengthCard = _buildSportCard(
      title: 'Strength',
      icon: CupertinoIcons.sportscourt_fill,
      color: AppColors.strengthViolet,
      volume7d: appState.strengthVolume7d,
      stat30d: appState.isSignedIn
          ? '30d: ${fmtDuration(strengths)} • ${strengths.length} workouts'
          : '7d & 30d strength & mobility',
      meta: appState.isSignedIn
          ? '${strengths.fold<int>(0, (s, a) => s + a.calories)} kcal'
          : '—',
      onTap: () => appState.setNavIndex(4),
    );

    // Compact 2x2 grid in exact order: Running, Cycling, Swimming, Strength
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(child: runCard),
            const SizedBox(width: 10),
            Expanded(child: bikeCard),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: swimCard),
            const SizedBox(width: 10),
            Expanded(child: strengthCard),
          ],
        ),
      ],
    );
  }

  Widget _buildSportCard({
    required String title,
    required IconData icon,
    required Color color,
    required String volume7d,
    required String stat30d,
    required String meta,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: MacCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(icon, size: 12, color: color),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          title,
                          style: AppTypography.headlineSm,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  meta,
                  style: AppTypography.telemetrySm.copyWith(color: AppColors.outline),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(volume7d, style: AppTypography.telemetryHero),
                const SizedBox(width: 5),
                Text('7d', style: AppTypography.bodySm),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              stat30d,
              style: AppTypography.bodySm,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrainingOverviewRow() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dailyKm = <double>[];
    final dayLabels = <String>[];

    for (int i = 13; i >= 0; i--) {
      final day = today.subtract(Duration(days: i));
      final km = appState.activities
          .where((a) =>
              a.timestamp.year == day.year &&
              a.timestamp.month == day.month &&
              a.timestamp.day == day.day)
          .fold<double>(0, (sum, a) => sum + a.distanceKm);
      dailyKm.add(km);
      dayLabels.add(DateFormat('MMM d').format(day));
    }

    final unit = appState.unitSystem;
    final unitLabel = UnitFormatter.distanceUnitLabel(unit);
    final dailyDisplay = dailyKm
        .map((km) => UnitFormatter.convertDistance(km, unit))
        .toList();
    final total14dKm = dailyKm.fold<double>(0, (a, b) => a + b);
    int countOf(SportDiscipline d) => appState.activities.where((a) => a.discipline == d).length;
    final totalActs = appState.activities.isEmpty ? 1 : appState.activities.length;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 6,
            child: MacCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('14-Day Activity Distance', style: AppTypography.headlineMd),
                            const SizedBox(height: 2),
                            Text(
                              appState.isSignedIn
                                  ? '${UnitFormatter.formatDistance(total14dKm, unit)} across recent sessions'
                                  : 'Daily volume across all synced sports',
                              style: AppTypography.bodySm,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      MacStatusBadge(label: 'Garmin', color: AppColors.accent),
                    ],
                  ),
                  const SizedBox(height: 12),
                  InteractiveDailyBarChart(
                    values: dailyDisplay,
                    labels: dayLabels,
                    barColor: AppColors.accent,
                    unit: unitLabel,
                    height: 125,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(dayLabels.first, style: AppTypography.bodySm),
                      Text(dayLabels[dayLabels.length ~/ 2], style: AppTypography.bodySm),
                      Text('Today', style: AppTypography.bodySm),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 5,
            child: MacCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Multi-Sport Mix', style: AppTypography.headlineMd),
                      const SizedBox(height: 2),
                      Text('Synced session share', style: AppTypography.bodySm),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _buildSportMixRow('Running', countOf(SportDiscipline.run), totalActs, AppColors.runTertiary),
                  const SizedBox(height: 8),
                  _buildSportMixRow(
                    'Cycling',
                    countOf(SportDiscipline.bike) + countOf(SportDiscipline.indoorBike),
                    totalActs,
                    AppColors.bikeSecondary,
                  ),
                  const SizedBox(height: 8),
                  _buildSportMixRow('Swimming', countOf(SportDiscipline.swim), totalActs, AppColors.swimPrimary),
                  const SizedBox(height: 8),
                  _buildSportMixRow('Strength', countOf(SportDiscipline.strength), totalActs, AppColors.strengthViolet),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSportMixRow(String label, int count, int total, Color color) {
    final fraction = appState.activities.isNotEmpty ? count / total : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 7),
                Text(label, style: AppTypography.bodyMd.copyWith(color: AppColors.onSurface)),
              ],
            ),
            Text(
              appState.isSignedIn ? '$count (${(fraction * 100).round()}%)' : '—',
              style: AppTypography.telemetrySm,
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 5,
            backgroundColor: AppColors.surfaceLow,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }

  Widget _buildRecentActivitiesCard(BuildContext context) {
    final recent = appState.activities.take(6).toList();

    // Lazily fetch GPS route polylines for recent feed cards on the Dashboard
    if (recent.isNotEmpty) {
      final idsToEnsure = recent
          .where((a) => a.routePoints.isEmpty && a.startLatitude != null)
          .map((a) => a.id)
          .toList();
      if (idsToEnsure.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          appState.ensurePolylinesLoaded(idsToEnsure);
        });
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Recent Activities', style: AppTypography.headlineMd),
            if (appState.activities.isNotEmpty)
              InkWell(
                onTap: () => appState.setNavIndex(3),
                borderRadius: BorderRadius.circular(5),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  child: Text(
                    'View All (${appState.activities.length})',
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (recent.isEmpty)
          MacCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  !appState.isSignedIn
                      ? 'Sign in with Garmin Connect to view your recent Swim, Bike, Run, and Strength sessions.'
                      : appState.isSyncing
                          ? 'Pulling your activities from Garmin Connect...'
                          : 'No activities found in your Garmin Connect account yet.',
                  style: AppTypography.bodyMd,
                ),
              ),
            ),
          )
        else
          ActivityFeedGrid(activities: recent, appState: appState),
      ],
    );
  }
}
