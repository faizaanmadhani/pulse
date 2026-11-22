import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../state/app_state.dart';
import '../models/activity.dart';
import '../models/performance_metrics.dart';
import '../components/chart_painters.dart';
import '../components/garmin_sign_in_dialog.dart';
import '../components/macos_ui.dart';

class AnalyticsView extends StatefulWidget {
  final AppState appState;

  const AnalyticsView({super.key, required this.appState});

  @override
  State<AnalyticsView> createState() => _AnalyticsViewState();
}

class _AnalyticsViewState extends State<AnalyticsView> {
  String _selectedWindow = '12W';
  String? _selectedKpi; // 'ctl', 'atl', 'tsb', 'acwr'
  String _volumeMetric = 'Distance'; // 'Distance', 'Hours'
  String _prSportFilter = 'All'; // 'All', 'Running', 'Cycling', 'Swimming'
  String _distanceSport = 'Running'; // 'Running', 'Cycling'
  String _efficiencySport = 'Running'; // 'Running', 'Cycling'

  final GlobalKey _pmcSectionKey = GlobalKey();

  void _scrollToPmc() {
    final ctx = _pmcSectionKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }
  }

  double _activityTss(Activity a) {
    if (a.tss != null && a.tss! > 0) return a.tss!;
    return (a.durationSeconds / 3600.0) * 50.0;
  }

  String _formatPaceMinPerKm(double secPerKm) {
    if (!secPerKm.isFinite || secPerKm <= 0) return '—';
    final totalSec = secPerKm.round();
    final min = totalSec ~/ 60;
    final sec = totalSec % 60;
    return '$min:${sec.toString().padLeft(2, '0')} /km';
  }

  String _formatPacePer100m(double secPer100m) {
    if (!secPer100m.isFinite || secPer100m <= 0) return '—';
    final totalSec = secPer100m.round();
    final min = totalSec ~/ 60;
    final sec = totalSec % 60;
    return '$min:${sec.toString().padLeft(2, '0')} /100m';
  }

  String _formatDurationClock(double seconds) {
    if (seconds <= 0) return '0:00';
    final totalSec = seconds.round();
    final h = totalSec ~/ 3600;
    final m = (totalSec % 3600) ~/ 60;
    final s = totalSec % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
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

  String _tsbReadinessZone(double? tsb) {
    if (tsb == null) return 'No data';
    if (tsb > 15) return 'Transition / Detraining';
    if (tsb > 5) return 'Fresh / Race Ready';
    if (tsb >= -10) return 'Optimal / Neutral';
    if (tsb >= -25) return 'Productive Overload';
    return 'High Fatigue';
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.appState.isSignedIn) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: MacEmptyState(
          icon: CupertinoIcons.chart_bar,
          title: 'Performance Analytics',
          message:
              'Sign in with Garmin Connect to calculate your real Fitness (CTL), Fatigue (ATL), Form (TSB), ACWR, weekly volume, personal records, and aerobic efficiency.',
          actionLabel: 'Sign in with Garmin',
          onAction: () => showGarminSignInDialog(context, widget.appState),
        ),
      );
    }

    final p = widget.appState.profile;
    final pmc = widget.appState.pmcSeries;
    final sliceLen = switch (_selectedWindow) {
      '4W' => 28,
      '12W' => 84,
      '6M' => 180,
      '1Y' => 365,
      _ => pmc.length,
    };
    final visiblePmc = pmc.length > sliceLen ? pmc.sublist(pmc.length - sliceLen) : pmc;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Controls Bar
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 10,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Training Load & Fitness', style: AppTypography.headlineMd),
                  const SizedBox(height: 2),
                  Text(
                    'Computed from ${widget.appState.activities.length} synced Garmin activities • Click any KPI card for breakdown',
                    style: AppTypography.bodySm,
                  ),
                ],
              ),
              MacSegmentedControl<String>(
                items: const ['4W', '12W', '6M', '1Y', 'ALL'],
                selected: _selectedWindow,
                labelBuilder: (s) => s,
                onChanged: (val) => setState(() => _selectedWindow = val),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 4 Interactive KPI Cards with Mini Graphics & Derivation Details
          _buildKpiCardsSection(p, pmc),

          // Expandable Metric Deep-Dive Panel when a KPI card is selected
          if (_selectedKpi != null) ...[
            const SizedBox(height: 12),
            _buildKpiDeepDivePanel(_selectedKpi!, p, pmc),
          ],

          const SizedBox(height: 16),

          // Performance Management Chart
          Container(
            key: _pmcSectionKey,
            child: _buildPmcCard(visiblePmc),
          ),

          const SizedBox(height: 16),

          // Weekly Volume Stacked Bar Chart (Last 12 Weeks)
          _buildWeeklyVolumeCard(),

          const SizedBox(height: 16),

          // Personal Records & Best Efforts (Real Synced Activities Only)
          _buildPersonalRecordsCard(),

          const SizedBox(height: 16),

          // Performance by Distance Table & Bars
          _buildPerformanceByDistanceCard(),

          const SizedBox(height: 16),

          // Aerobic Efficiency Trend
          _buildAerobicEfficiencyCard(),

          const SizedBox(height: 16),

          // Sport Volume Totals (from synced activities)
          _buildDisciplineTotalsCard(),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 1. TOP 4 KPI CARDS WITH MINI GRAPHICS + GRANULAR DERIVATION + DRILL-DOWN
  // ---------------------------------------------------------------------------
  Widget _buildKpiCardsSection(AthletePhysiologicalProfile p, List<PmcDataPoint> pmc) {
    final tail14 = pmc.length > 14 ? pmc.sublist(pmc.length - 14) : pmc;
    final tail7 = pmc.length > 7 ? pmc.sublist(pmc.length - 7) : pmc;
    final tail42 = pmc.length > 42 ? pmc.sublist(pmc.length - 42) : pmc;

    final ctl14 = tail14.map((e) => e.ctl).toList();
    final atl14 = tail14.map((e) => e.atl).toList();
    final tsb14 = tail14.map((e) => e.tsb).toList();

    final ctl7dDelta = pmc.length >= 8 ? (pmc.last.ctl - pmc[pmc.length - 8].ctl) : null;
    final avgTss42 = tail42.isNotEmpty
        ? tail42.fold<double>(0, (s, e) => s + e.dailyTss) / tail42.length
        : 0.0;
    final totalTss7 = tail7.fold<double>(0, (s, e) => s + e.dailyTss);
    final avgTss7 = tail7.isNotEmpty ? totalTss7 / tail7.length : 0.0;

    final ctlStr = p.ctlFitness != null ? p.ctlFitness!.toStringAsFixed(1) : '—';
    final atlStr = p.atlFatigue != null ? p.atlFatigue!.toStringAsFixed(1) : '—';
    final tsbStr = p.tsbForm != null
        ? '${p.tsbForm! >= 0 ? '+' : ''}${p.tsbForm!.toStringAsFixed(1)}'
        : '—';
    final acwrStr = p.acwrRatio != null ? p.acwrRatio!.toStringAsFixed(2) : '—';

    final cards = [
      _kpiCard(
        id: 'ctl',
        title: 'Fitness (CTL)',
        value: ctlStr,
        accent: AppColors.swimPrimary,
        badge: ctl7dDelta != null
            ? '${ctl7dDelta >= 0 ? '+' : ''}${ctl7dDelta.toStringAsFixed(1)} (7d)'
            : '42d EWMA',
        miniChart: SizedBox(
          height: 34,
          width: double.infinity,
          child: CustomPaint(
            painter: _MiniSparklinePainter(
              values: ctl14,
              color: AppColors.swimPrimary,
            ),
          ),
        ),
        derivationLine1: '42d avg: ${avgTss42.toStringAsFixed(0)} TSS/day',
        derivationLine2: ctl7dDelta != null
            ? '7-day delta: ${ctl7dDelta >= 0 ? '+' : ''}${ctl7dDelta.toStringAsFixed(1)} pts'
            : 'Chronic training load',
      ),
      _kpiCard(
        id: 'atl',
        title: 'Fatigue (ATL)',
        value: atlStr,
        accent: AppColors.bikeSecondary,
        badge: '${totalTss7.round()} TSS (7d)',
        miniChart: SizedBox(
          height: 34,
          width: double.infinity,
          child: CustomPaint(
            painter: _MiniSparklinePainter(
              values: atl14,
              color: AppColors.bikeSecondary,
            ),
          ),
        ),
        derivationLine1: '7d total: ${totalTss7.round()} TSS',
        derivationLine2: '7d daily avg: ${avgTss7.toStringAsFixed(0)} TSS/day',
      ),
      _kpiCard(
        id: 'tsb',
        title: 'Form (TSB)',
        value: tsbStr,
        accent: AppColors.runTertiary,
        badge: _tsbReadinessZone(p.tsbForm),
        miniChart: SizedBox(
          height: 34,
          width: double.infinity,
          child: CustomPaint(
            painter: _MiniDivergingTsbPainter(values: tsb14),
          ),
        ),
        derivationLine1: 'CTL ($ctlStr) − ATL ($atlStr)',
        derivationLine2: 'Zone: ${_tsbReadinessZone(p.tsbForm)}',
      ),
      _kpiCard(
        id: 'acwr',
        title: 'ACWR Ratio',
        value: acwrStr,
        accent: AppColors.accent,
        badge: p.acwrStatus ?? '0.8 – 1.3',
        miniChart: SizedBox(
          height: 34,
          width: double.infinity,
          child: CustomPaint(
            painter: _AcwrZoneGaugePainter(acwr: p.acwrRatio),
          ),
        ),
        derivationLine1: 'ATL ($atlStr) ÷ CTL ($ctlStr)',
        derivationLine2: 'Sweet spot: 0.80 – 1.30',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final useFourCols = constraints.maxWidth >= 780;
        if (useFourCols) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (int i = 0; i < cards.length; i++) ...[
                Expanded(child: cards[i]),
                if (i < cards.length - 1) const SizedBox(width: 12),
              ],
            ],
          );
        }
        return Column(
          children: [
            Row(
              children: [
                Expanded(child: cards[0]),
                const SizedBox(width: 12),
                Expanded(child: cards[1]),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: cards[2]),
                const SizedBox(width: 12),
                Expanded(child: cards[3]),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _kpiCard({
    required String id,
    required String title,
    required String value,
    required Color accent,
    required String badge,
    required Widget miniChart,
    required String derivationLine1,
    required String derivationLine2,
  }) {
    final isSelected = _selectedKpi == id;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _selectedKpi = isSelected ? null : id),
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainer,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? accent : AppColors.borderSubtle,
              width: isSelected ? 1.8 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: isSelected ? accent.withOpacity(0.14) : AppColors.cardShadow,
                blurRadius: isSelected ? 10 : 6,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      title,
                      style: AppTypography.bodySm.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    isSelected ? CupertinoIcons.chevron_up : CupertinoIcons.chevron_down,
                    size: 11,
                    color: isSelected ? accent : AppColors.outline,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(value, style: AppTypography.telemetryHero),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      badge,
                      style: AppTypography.bodySm.copyWith(
                        fontSize: 10.5,
                        color: accent,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              miniChart,
              const SizedBox(height: 8),
              Text(
                derivationLine1,
                style: AppTypography.telemetrySm.copyWith(fontSize: 10.5),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                derivationLine2,
                style: AppTypography.bodySm.copyWith(fontSize: 10.5),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKpiDeepDivePanel(
    String kpiId,
    AthletePhysiologicalProfile p,
    List<PmcDataPoint> pmc,
  ) {
    final cutoff7 = DateTime.now().subtract(const Duration(days: 7));
    final recent7Acts = widget.appState.activities
        .where((a) => a.timestamp.isAfter(cutoff7))
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final tail7 = pmc.length > 7 ? pmc.sublist(pmc.length - 7) : pmc;
    final tail42 = pmc.length > 42 ? pmc.sublist(pmc.length - 42) : pmc;
    final totalTss7 = tail7.fold<double>(0, (s, e) => s + e.dailyTss);
    final totalTss42 = tail42.fold<double>(0, (s, e) => s + e.dailyTss);

    final (title, color, formula, explanation) = switch (kpiId) {
      'ctl' => (
          'Fitness (CTL) Deep Dive',
          AppColors.swimPrimary,
          'CTL = 42-day Exponentially Weighted Moving Average of Daily TSS',
          'Your Chronic Training Load reflects long-term aerobic fitness built over the past 6 weeks '
              '(42-day total: ${totalTss42.round()} TSS, avg ${(tail42.isNotEmpty ? totalTss42 / tail42.length : 0).toStringAsFixed(1)} TSS/day). '
              'Sustainable ramp rate is typically +3 to +6 CTL points per week.',
        ),
      'atl' => (
          'Fatigue (ATL) Deep Dive',
          AppColors.bikeSecondary,
          'ATL = 7-day Exponentially Weighted Moving Average of Daily TSS',
          'Your Acute Training Load captures short-term physiological fatigue from the last 7 days '
              '(7-day total: ${totalTss7.round()} TSS across ${recent7Acts.length} activities). '
              'Spikes above CTL signal heavy training blocks that require recovery.',
        ),
      'tsb' => (
          'Form (TSB) Deep Dive',
          AppColors.runTertiary,
          'TSB = CTL (${p.ctlFitness?.toStringAsFixed(1) ?? '—'}) − ATL (${p.atlFatigue?.toStringAsFixed(1) ?? '—'})',
          'Training Stress Balance measures readiness. Positive values (+5 to +20) indicate freshness '
              'for racing; −10 to −25 represents productive overload during build phases. '
              'Current zone: ${_tsbReadinessZone(p.tsbForm)}.',
        ),
      _ => (
          'ACWR Ratio Deep Dive',
          AppColors.accent,
          'ACWR = ATL (${p.atlFatigue?.toStringAsFixed(1) ?? '—'}) ÷ CTL (${p.ctlFitness?.toStringAsFixed(1) ?? '—'})',
          'Acute-to-Chronic Workload Ratio tracks injury & overreaching risk. '
              'Undertraining (<0.80), Sweet Spot (0.80–1.30), Building (1.30–1.50), Overreaching (>1.50). '
              'Current status: ${p.acwrStatus ?? '—'}.',
        ),
    };

    return MacCard(
      color: AppColors.surfaceContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title, style: AppTypography.headlineMd, overflow: TextOverflow.ellipsis),
              ),
              MacPushButton(
                label: 'Jump to PMC Chart',
                icon: CupertinoIcons.graph_square,
                onPressed: _scrollToPmc,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(CupertinoIcons.xmark, size: 14, color: AppColors.outline),
                onPressed: () => setState(() => _selectedKpi = null),
                tooltip: 'Close breakdown',
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.surfaceLowest,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: AppColors.borderDivider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formula,
                  style: AppTypography.telemetrySm.copyWith(
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(explanation, style: AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '7-Day Contributing Activities (${recent7Acts.length})',
            style: AppTypography.headlineSm,
          ),
          const SizedBox(height: 6),
          if (recent7Acts.isEmpty)
            Text(
              'No synced activities in the past 7 days.',
              style: AppTypography.bodySm,
            )
          else
            ...recent7Acts.take(6).map((a) {
              final actColor = _disciplineColor(a.discipline);
              final tss = _activityTss(a);
              return InkWell(
                onTap: () => widget.appState.setSelectedActivityId(a.id),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLowest,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.borderDivider),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(color: actColor, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 56,
                        child: Text(
                          DateFormat('MMM d').format(a.timestamp),
                          style: AppTypography.telemetrySm,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          a.title,
                          style: AppTypography.headlineSm.copyWith(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        a.distanceKm > 0
                            ? '${a.distanceKm.toStringAsFixed(1)} km • ${a.movingTime}'
                            : a.movingTime,
                        style: AppTypography.telemetrySm,
                      ),
                      const SizedBox(width: 12),
                      MacStatusBadge(
                        label: '${tss.round()} TSS',
                        color: actColor,
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

  // ---------------------------------------------------------------------------
  // 2. PERFORMANCE MANAGEMENT CHART
  // ---------------------------------------------------------------------------
  Widget _buildPmcCard(List<PmcDataPoint> visiblePmc) {
    final dateFmt = visiblePmc.length > 180 ? DateFormat('MMM d, yy') : DateFormat('MMM d');
    final focusedLabel = switch (_selectedKpi) {
      'ctl' => 'Fitness (CTL)',
      'atl' => 'Fatigue (ATL)',
      'tsb' => 'Form (TSB)',
      'acwr' => 'ACWR (ATL ÷ CTL)',
      _ => null,
    };

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
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Performance Management Chart', style: AppTypography.headlineMd),
                  if (focusedLabel != null) ...[
                    const SizedBox(width: 8),
                    MacStatusBadge(label: 'Focused: $focusedLabel', color: AppColors.accent),
                  ],
                ],
              ),
              Wrap(
                spacing: 14,
                runSpacing: 6,
                children: [
                  _legendDot('Fitness (CTL)', AppColors.swimPrimary),
                  _legendDot('Fatigue (ATL)', AppColors.bikeSecondary),
                  _legendDot('Form (TSB)', AppColors.runTertiary),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (visiblePmc.length < 2)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Text(
                  'Sync at least a few Garmin activities to render your Fitness & Fatigue curve.',
                  style: AppTypography.bodyMd,
                ),
              ),
            )
          else ...[
            InteractivePmcChart(
              points: visiblePmc,
              height: 220,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(dateFmt.format(visiblePmc.first.date), style: AppTypography.bodySm),
                Text(
                  dateFmt.format(visiblePmc[visiblePmc.length ~/ 2].date),
                  style: AppTypography.bodySm,
                ),
                Text(dateFmt.format(visiblePmc.last.date), style: AppTypography.bodySm),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 3. WEEKLY VOLUME STACKED BAR CHART (LAST 12 WEEKS)
  // ---------------------------------------------------------------------------
  List<_WeeklyVolumeBucket> _computeWeeklyVolumes() {
    final now = DateTime.now();
    final currentMonday =
        DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    const numWeeks = 12;

    final buckets = List.generate(numWeeks, (i) {
      final weekStart = currentMonday.subtract(Duration(days: (numWeeks - 1 - i) * 7));
      return _WeeklyVolumeBucket(weekStart: weekStart);
    });

    final earliest = buckets.first.weekStart;
    final latestEnd = currentMonday.add(const Duration(days: 7));

    for (final act in widget.appState.activities) {
      final t = DateTime(act.timestamp.year, act.timestamp.month, act.timestamp.day);
      if (t.isBefore(earliest) || !t.isBefore(latestEnd)) continue;
      final weekIdx = t.difference(earliest).inDays ~/ 7;
      if (weekIdx < 0 || weekIdx >= numWeeks) continue;

      final b = buckets[weekIdx];
      b.sessions++;
      final hrs = act.durationSeconds / 3600.0;
      switch (act.discipline) {
        case SportDiscipline.swim:
          b.swimKm += act.distanceKm;
          b.swimHrs += hrs;
        case SportDiscipline.bike:
        case SportDiscipline.indoorBike:
          b.bikeKm += act.distanceKm;
          b.bikeHrs += hrs;
        case SportDiscipline.run:
          b.runKm += act.distanceKm;
          b.runHrs += hrs;
        case SportDiscipline.strength:
          b.strengthHrs += hrs;
      }
    }
    return buckets;
  }

  Widget _buildWeeklyVolumeCard() {
    final buckets = _computeWeeklyVolumes();
    final isHours = _volumeMetric == 'Hours';
    final total12w = buckets.fold<double>(
      0,
      (s, b) => s + (isHours ? b.totalHrs : b.totalKm),
    );

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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Weekly Volume (Last 12 Weeks)', style: AppTypography.headlineMd),
                  const SizedBox(height: 2),
                  Text(
                    isHours
                        ? '12-week total: ${total12w.toStringAsFixed(1)} hrs across Swim, Bike, Run & Strength'
                        : '12-week total: ${total12w.toStringAsFixed(1)} km across Swim, Bike & Run',
                    style: AppTypography.bodySm,
                  ),
                ],
              ),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 14,
                runSpacing: 6,
                children: [
                  _legendDot('Swim', AppColors.swimPrimary),
                  _legendDot('Bike', AppColors.bikeSecondary),
                  _legendDot('Run', AppColors.runTertiary),
                  if (isHours) _legendDot('Strength', AppColors.strengthViolet),
                  MacSegmentedControl<String>(
                    items: const ['Distance', 'Hours'],
                    selected: _volumeMetric,
                    labelBuilder: (s) => s,
                    onChanged: (v) => setState(() => _volumeMetric = v),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          _InteractiveWeeklyVolumeChart(
            buckets: buckets,
            showHours: isHours,
            height: 200,
          ),
          const SizedBox(height: 8),
          Row(
            children: buckets.asMap().entries.map((entry) {
              final idx = entry.key;
              final b = entry.value;
              final showLabel = idx == 0 || idx == 3 || idx == 6 || idx == 9 || idx == 11;
              return Expanded(
                child: Text(
                  showLabel ? DateFormat('MMM d').format(b.weekStart) : '',
                  style: AppTypography.bodySm.copyWith(fontSize: 10.5),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 4. PERSONAL RECORDS & BEST EFFORTS (ZERO FAKE DATA)
  // ---------------------------------------------------------------------------
  List<_PrEntry> _computePersonalRecords() {
    final acts = widget.appState.activities;
    final runs = acts.where((a) => a.discipline == SportDiscipline.run).toList();
    final rides = acts
        .where((a) => a.discipline == SportDiscipline.bike || a.discipline == SportDiscipline.indoorBike)
        .toList();
    final swims = acts.where((a) => a.discipline == SportDiscipline.swim).toList();

    Activity? fastestInRange(List<Activity> list, double minKm, double maxKm) {
      final matching = list
          .where((a) => a.distanceKm >= minKm && a.distanceKm <= maxKm && a.durationSeconds > 0)
          .toList();
      if (matching.isEmpty) return null;
      matching.sort((a, b) => a.durationSeconds.compareTo(b.durationSeconds));
      return matching.first;
    }

    Activity? maxBy(List<Activity> list, double Function(Activity) selector) {
      final valid = list.where((a) => selector(a) > 0).toList();
      if (valid.isEmpty) return null;
      valid.sort((a, b) => selector(b).compareTo(selector(a)));
      return valid.first;
    }

    // Running PRs
    final pr5k = fastestInRange(runs, 4.8, 5.5);
    final pr10k = fastestInRange(runs, 9.7, 10.6);
    final prHalf = fastestInRange(runs, 20.5, 22.0);
    final longestRun = maxBy(runs, (a) => a.distanceKm);
    final highestElevRun = maxBy(runs, (a) => a.elevationGainM);

    // Cycling PRs
    final longestRide = maxBy(rides, (a) => a.distanceKm);
    final biggestClimb = maxBy(rides, (a) => a.elevationGainM);
    final bestPowerRide = maxBy(rides, (a) => (a.avgPowerW ?? 0).toDouble());
    final speedCandidates = rides.where((a) => a.distanceKm >= 5.0 && a.durationSeconds > 0).toList();
    final fastestSpeedRide = maxBy(
      speedCandidates.isNotEmpty ? speedCandidates : rides.where((a) => a.distanceKm > 0 && a.durationSeconds > 0).toList(),
      (a) => a.distanceKm / (a.durationSeconds / 3600.0),
    );

    // Swimming PRs
    final longestSwim = maxBy(swims, (a) => a.distanceKm);
    final validSwims = swims.where((a) => a.distanceKm > 0 && a.durationSeconds > 0).toList();
    Activity? fastestSwim;
    if (validSwims.isNotEmpty) {
      validSwims.sort((a, b) {
        final paceA = a.durationSeconds / (a.distanceKm * 10.0);
        final paceB = b.durationSeconds / (b.distanceKm * 10.0);
        return paceA.compareTo(paceB);
      });
      fastestSwim = validSwims.first;
    }

    return [
      _PrEntry(
        sport: 'Running',
        label: 'Fastest ~5K',
        value: pr5k != null ? _formatDurationClock(pr5k.durationSeconds) : '—',
        subtext: pr5k != null
            ? '${pr5k.distanceKm.toStringAsFixed(2)} km • ${_formatPaceMinPerKm(pr5k.durationSeconds / pr5k.distanceKm)}'
            : 'No 4.8–5.5 km run synced',
        activity: pr5k,
        color: AppColors.runTertiary,
      ),
      _PrEntry(
        sport: 'Running',
        label: 'Fastest ~10K',
        value: pr10k != null ? _formatDurationClock(pr10k.durationSeconds) : '—',
        subtext: pr10k != null
            ? '${pr10k.distanceKm.toStringAsFixed(2)} km • ${_formatPaceMinPerKm(pr10k.durationSeconds / pr10k.distanceKm)}'
            : 'No 9.7–10.6 km run synced',
        activity: pr10k,
        color: AppColors.runTertiary,
      ),
      _PrEntry(
        sport: 'Running',
        label: 'Fastest ~Half Marathon',
        value: prHalf != null ? _formatDurationClock(prHalf.durationSeconds) : '—',
        subtext: prHalf != null
            ? '${prHalf.distanceKm.toStringAsFixed(2)} km • ${_formatPaceMinPerKm(prHalf.durationSeconds / prHalf.distanceKm)}'
            : 'No 20.5–22 km run synced',
        activity: prHalf,
        color: AppColors.runTertiary,
      ),
      _PrEntry(
        sport: 'Running',
        label: 'Longest Run',
        value: longestRun != null ? '${longestRun.distanceKm.toStringAsFixed(2)} km' : '—',
        subtext: longestRun != null ? longestRun.movingTime : 'No runs synced',
        activity: longestRun,
        color: AppColors.runTertiary,
      ),
      _PrEntry(
        sport: 'Running',
        label: 'Highest Elevation Run',
        value: highestElevRun != null ? '${highestElevRun.elevationGainM.round()} m' : '—',
        subtext: highestElevRun != null
            ? '${highestElevRun.distanceKm.toStringAsFixed(1)} km'
            : 'No elevation data',
        activity: highestElevRun,
        color: AppColors.runTertiary,
      ),
      _PrEntry(
        sport: 'Cycling',
        label: 'Longest Ride',
        value: longestRide != null ? '${longestRide.distanceKm.toStringAsFixed(1)} km' : '—',
        subtext: longestRide != null ? longestRide.movingTime : 'No rides synced',
        activity: longestRide,
        color: AppColors.bikeSecondary,
      ),
      _PrEntry(
        sport: 'Cycling',
        label: 'Biggest Climb',
        value: biggestClimb != null ? '${biggestClimb.elevationGainM.round()} m' : '—',
        subtext: biggestClimb != null
            ? '${biggestClimb.distanceKm.toStringAsFixed(1)} km'
            : 'No elevation data',
        activity: biggestClimb,
        color: AppColors.bikeSecondary,
      ),
      _PrEntry(
        sport: 'Cycling',
        label: 'Best Avg Power Ride',
        value: bestPowerRide != null ? '${bestPowerRide.avgPowerW} W' : '—',
        subtext: bestPowerRide != null
            ? '${bestPowerRide.distanceKm.toStringAsFixed(1)} km • ${bestPowerRide.movingTime}'
            : 'No power meter data',
        activity: bestPowerRide,
        color: AppColors.bikeSecondary,
      ),
      _PrEntry(
        sport: 'Cycling',
        label: 'Fastest Avg Speed Ride',
        value: fastestSpeedRide != null
            ? '${(fastestSpeedRide.distanceKm / (fastestSpeedRide.durationSeconds / 3600.0)).toStringAsFixed(1)} km/h'
            : '—',
        subtext: fastestSpeedRide != null
            ? '${fastestSpeedRide.distanceKm.toStringAsFixed(1)} km • ${fastestSpeedRide.movingTime}'
            : 'No rides synced',
        activity: fastestSpeedRide,
        color: AppColors.bikeSecondary,
      ),
      _PrEntry(
        sport: 'Swimming',
        label: 'Longest Swim',
        value: longestSwim != null
            ? '${NumberFormat('#,###').format((longestSwim.distanceKm * 1000).round())} m'
            : '—',
        subtext: longestSwim != null ? longestSwim.movingTime : 'No swims synced',
        activity: longestSwim,
        color: AppColors.swimPrimary,
      ),
      _PrEntry(
        sport: 'Swimming',
        label: 'Fastest Avg Pace Swim',
        value: fastestSwim != null
            ? _formatPacePer100m(fastestSwim.durationSeconds / (fastestSwim.distanceKm * 10.0))
            : '—',
        subtext: fastestSwim != null
            ? '${(fastestSwim.distanceKm * 1000).round()} m • ${fastestSwim.movingTime}'
            : 'No swims synced',
        activity: fastestSwim,
        color: AppColors.swimPrimary,
      ),
    ];
  }

  Widget _buildPersonalRecordsCard() {
    final allPrs = _computePersonalRecords();
    final filtered = _prSportFilter == 'All'
        ? allPrs
        : allPrs.where((pr) => pr.sport == _prSportFilter).toList();

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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Personal Records & Best Efforts', style: AppTypography.headlineMd),
                  const SizedBox(height: 2),
                  Text(
                    'All-time highs from your synced Garmin history • Click any record to inspect',
                    style: AppTypography.bodySm,
                  ),
                ],
              ),
              MacSegmentedControl<String>(
                items: const ['All', 'Running', 'Cycling', 'Swimming'],
                selected: _prSportFilter,
                labelBuilder: (s) => s,
                onChanged: (v) => setState(() => _prSportFilter = v),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final cols = constraints.maxWidth >= 900
                  ? 4
                  : constraints.maxWidth >= 600
                      ? 3
                      : 2;
              const spacing = 10.0;
              final itemWidth = (constraints.maxWidth - (cols - 1) * spacing) / cols;

              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: filtered.map((pr) {
                  return SizedBox(
                    width: itemWidth,
                    child: _buildPrTile(pr),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPrTile(_PrEntry pr) {
    final hasAct = pr.activity != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: hasAct ? () => widget.appState.setSelectedActivityId(pr.activity!.id) : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surfaceLowest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: hasAct ? AppColors.borderSubtle : AppColors.borderDivider,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: hasAct ? pr.color : AppColors.outline.withOpacity(0.4),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      pr.label,
                      style: AppTypography.bodySm.copyWith(
                        fontWeight: FontWeight.w600,
                        color: hasAct ? AppColors.onSurface : AppColors.outline,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (hasAct)
                    Icon(CupertinoIcons.chevron_right, size: 11, color: AppColors.outline),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                pr.value,
                style: AppTypography.telemetryLg.copyWith(
                  color: hasAct ? AppColors.onSurface : AppColors.outline,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              Text(
                pr.subtext,
                style: AppTypography.bodySm.copyWith(fontSize: 10.5),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (hasAct) ...[
                const SizedBox(height: 4),
                Text(
                  '${DateFormat('MMM d, y').format(pr.activity!.timestamp)} • ${pr.activity!.title}',
                  style: AppTypography.bodySm.copyWith(
                    fontSize: 10,
                    color: pr.color,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 5. PERFORMANCE BY DISTANCE TABLE & BAR VISUAL
  // ---------------------------------------------------------------------------
  List<_DistanceBucketStats> _computeDistanceBuckets(bool isRun) {
    final acts = widget.appState.activities.where((a) {
      if (a.distanceKm <= 0 || a.durationSeconds <= 0) return false;
      return isRun
          ? a.discipline == SportDiscipline.run
          : (a.discipline == SportDiscipline.bike || a.discipline == SportDiscipline.indoorBike);
    }).toList();

    final defs = isRun
        ? const [
            ('< 5 km', 0.0, 5.0),
            ('5 – 10 km', 5.0, 10.0),
            ('10 – 15 km', 10.0, 15.0),
            ('15 – 21 km', 15.0, 21.0),
            ('21+ km', 21.0, double.infinity),
          ]
        : const [
            ('< 25 km', 0.0, 25.0),
            ('25 – 50 km', 25.0, 50.0),
            ('50 – 100 km', 50.0, 100.0),
            ('100+ km', 100.0, double.infinity),
          ];

    return defs.map((def) {
      final (label, minD, maxD) = def;
      final group = acts.where((a) => a.distanceKm >= minD && a.distanceKm < maxD).toList();
      if (group.isEmpty) {
        return _DistanceBucketStats(
          label: label,
          count: 0,
          avgMetricText: '—',
          bestMetricText: '—',
          avgHrText: '—',
        );
      }

      final hrList = group.where((a) => a.avgHr > 0).map((a) => a.avgHr).toList();
      final avgHrText = hrList.isNotEmpty
          ? '${(hrList.reduce((a, b) => a + b) / hrList.length).round()} bpm'
          : '—';

      if (isRun) {
        final totalDist = group.fold<double>(0, (s, a) => s + a.distanceKm);
        final totalSec = group.fold<double>(0, (s, a) => s + a.durationSeconds);
        final avgPace = totalSec / totalDist;
        final bestPace = group
            .map((a) => a.durationSeconds / a.distanceKm)
            .reduce(math.min);
        return _DistanceBucketStats(
          label: label,
          count: group.length,
          avgMetricText: _formatPaceMinPerKm(avgPace),
          bestMetricText: _formatPaceMinPerKm(bestPace),
          avgHrText: avgHrText,
        );
      } else {
        final totalDist = group.fold<double>(0, (s, a) => s + a.distanceKm);
        final totalHrs = group.fold<double>(0, (s, a) => s + a.durationSeconds) / 3600.0;
        final avgSpeed = totalDist / totalHrs;
        final bestSpeed = group
            .map((a) => a.distanceKm / (a.durationSeconds / 3600.0))
            .reduce(math.max);
        return _DistanceBucketStats(
          label: label,
          count: group.length,
          avgMetricText: '${avgSpeed.toStringAsFixed(1)} km/h',
          bestMetricText: '${bestSpeed.toStringAsFixed(1)} km/h',
          avgHrText: avgHrText,
        );
      }
    }).toList();
  }

  Widget _buildPerformanceByDistanceCard() {
    final isRun = _distanceSport == 'Running';
    final accent = isRun ? AppColors.runTertiary : AppColors.bikeSecondary;
    final rows = _computeDistanceBuckets(isRun);
    final maxCount = rows.fold<int>(1, (m, r) => math.max(m, r.count));

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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Performance by Distance', style: AppTypography.headlineMd),
                  const SizedBox(height: 2),
                  Text(
                    isRun
                        ? 'Pace and heart rate grouped by run distance bucket'
                        : 'Speed and heart rate grouped by ride distance bucket',
                    style: AppTypography.bodySm,
                  ),
                ],
              ),
              MacSegmentedControl<String>(
                items: const ['Running', 'Cycling'],
                selected: _distanceSport,
                labelBuilder: (s) => s,
                onChanged: (v) => setState(() => _distanceSport = v),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Table header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surfaceLow,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              border: Border.all(color: AppColors.borderDivider),
            ),
            child: Row(
              children: [
                Expanded(flex: 2, child: Text('Distance', style: AppTypography.labelCaps)),
                Expanded(flex: 3, child: Text('Sessions', style: AppTypography.labelCaps)),
                Expanded(
                  flex: 2,
                  child: Text(
                    isRun ? 'Avg Pace' : 'Avg Speed',
                    style: AppTypography.labelCaps,
                    textAlign: TextAlign.right,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    isRun ? 'Best Pace' : 'Best Speed',
                    style: AppTypography.labelCaps,
                    textAlign: TextAlign.right,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Avg HR',
                    style: AppTypography.labelCaps,
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
          // Table rows
          Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceLowest,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
              border: Border(
                left: BorderSide(color: AppColors.borderDivider),
                right: BorderSide(color: AppColors.borderDivider),
                bottom: BorderSide(color: AppColors.borderDivider),
              ),
            ),
            child: Column(
              children: rows.asMap().entries.map((entry) {
                final idx = entry.key;
                final r = entry.value;
                final frac = r.count / maxCount;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    border: idx < rows.length - 1
                        ? Border(bottom: BorderSide(color: AppColors.borderDivider))
                        : null,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(
                          r.label,
                          style: AppTypography.headlineSm.copyWith(fontSize: 12.5),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Row(
                          children: [
                            SizedBox(
                              width: 28,
                              child: Text(
                                '${r.count}',
                                style: AppTypography.telemetryMd.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: r.count > 0 ? AppColors.onSurface : AppColors.outline,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: Container(
                                  height: 8,
                                  color: AppColors.surfaceContainerHigh,
                                  alignment: Alignment.centerLeft,
                                  child: FractionallySizedBox(
                                    widthFactor: r.count > 0 ? frac.clamp(0.06, 1.0) : 0,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: accent,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          r.avgMetricText,
                          style: AppTypography.telemetryMd,
                          textAlign: TextAlign.right,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          r.bestMetricText,
                          style: AppTypography.telemetryMd.copyWith(
                            fontWeight: FontWeight.w600,
                            color: r.count > 0 ? accent : AppColors.outline,
                          ),
                          textAlign: TextAlign.right,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          r.avgHrText,
                          style: AppTypography.telemetryMd,
                          textAlign: TextAlign.right,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 6. AEROBIC EFFICIENCY TREND (SPEED / AVG HR x 100)
  // ---------------------------------------------------------------------------
  List<_EfficiencyPoint> _computeEfficiencySeries(bool isRun) {
    final matching = widget.appState.activities.where((a) {
      if (a.distanceKm <= 0 || a.durationSeconds <= 0 || a.avgHr <= 0) return false;
      return isRun
          ? a.discipline == SportDiscipline.run
          : (a.discipline == SportDiscipline.bike || a.discipline == SportDiscipline.indoorBike);
    }).toList();

    // Prefer aerobic efforts >= 15 min when enough exist, otherwise include all valid
    final aerobic = matching.where((a) => a.durationSeconds >= 900 && a.avgHr >= 90).toList();
    final source = aerobic.length >= 2 ? aerobic : matching;
    source.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final recent = source.length > 30 ? source.sublist(source.length - 30) : source;
    return recent.map((a) {
      final speedKmh = a.distanceKm / (a.durationSeconds / 3600.0);
      final efficiency = (speedKmh / a.avgHr) * 100.0;
      return _EfficiencyPoint(
        activity: a,
        efficiency: efficiency,
        speedKmh: speedKmh,
      );
    }).toList();
  }

  Widget _buildAerobicEfficiencyCard() {
    final isRun = _efficiencySport == 'Running';
    final accent = isRun ? AppColors.runTertiary : AppColors.bikeSecondary;
    final pts = _computeEfficiencySeries(isRun);

    double? trendPct;
    if (pts.length >= 4) {
      final half = pts.length ~/ 2;
      final firstAvg = pts.take(half).fold<double>(0, (s, p) => s + p.efficiency) / half;
      final secondAvg =
          pts.skip(pts.length - half).fold<double>(0, (s, p) => s + p.efficiency) / half;
      if (firstAvg > 0) {
        trendPct = ((secondAvg - firstAvg) / firstAvg) * 100.0;
      }
    }

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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Aerobic Efficiency Trend', style: AppTypography.headlineMd),
                      if (trendPct != null) ...[
                        const SizedBox(width: 8),
                        MacStatusBadge(
                          label:
                              '${trendPct >= 0 ? '+' : ''}${trendPct.toStringAsFixed(1)}% ${trendPct >= 0 ? 'improving' : 'dipping'}',
                          color: trendPct >= 0 ? AppColors.runTertiary : AppColors.bikeSecondary,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Speed (km/h) ÷ Avg HR × 100 over recent ${isRun ? 'runs' : 'rides'} • Higher = faster at the same heart rate',
                    style: AppTypography.bodySm,
                  ),
                ],
              ),
              MacSegmentedControl<String>(
                items: const ['Running', 'Cycling'],
                selected: _efficiencySport,
                labelBuilder: (s) => s,
                onChanged: (v) => setState(() => _efficiencySport = v),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (pts.length < 2)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(
                  'Sync at least 2 ${isRun ? 'runs' : 'rides'} with heart rate data to plot your Aerobic Efficiency trend.',
                  style: AppTypography.bodyMd,
                ),
              ),
            )
          else ...[
            _InteractiveEfficiencyChart(
              points: pts,
              color: accent,
              isRun: isRun,
              height: 200,
              onSelectActivity: (id) => widget.appState.setSelectedActivityId(id),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(DateFormat('MMM d, y').format(pts.first.activity.timestamp), style: AppTypography.bodySm),
                Text(
                  DateFormat('MMM d, y').format(pts[pts.length ~/ 2].activity.timestamp),
                  style: AppTypography.bodySm,
                ),
                Text(DateFormat('MMM d, y').format(pts.last.activity.timestamp), style: AppTypography.bodySm),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 7. TOTALS ACROSS SYNCED ACTIVITIES
  // ---------------------------------------------------------------------------
  Widget _legendDot(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label, style: AppTypography.bodySm),
      ],
    );
  }

  Widget _buildDisciplineTotalsCard() {
    final acts = widget.appState.activities;
    final stats = [
      (
        'Running',
        acts.where((a) => a.discipline == SportDiscipline.run).toList(),
        AppColors.runTertiary,
      ),
      (
        'Cycling',
        acts
            .where((a) => a.discipline == SportDiscipline.bike || a.discipline == SportDiscipline.indoorBike)
            .toList(),
        AppColors.bikeSecondary,
      ),
      (
        'Swimming',
        acts.where((a) => a.discipline == SportDiscipline.swim).toList(),
        AppColors.swimPrimary,
      ),
      (
        'Strength',
        acts.where((a) => a.discipline == SportDiscipline.strength).toList(),
        AppColors.strengthViolet,
      ),
    ];

    return MacCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Totals Across Synced Activities', style: AppTypography.headlineMd),
          const SizedBox(height: 12),
          Row(
            children: stats.asMap().entries.map((mapEntry) {
              final isLast = mapEntry.key == stats.length - 1;
              final (name, list, color) = mapEntry.value;
              final totalKm = list.fold<double>(0, (s, a) => s + a.distanceKm);
              final totalHours = list.fold<double>(0, (s, a) => s + a.durationSeconds) / 3600.0;
              final totalElev = list.fold<double>(0, (s, a) => s + a.elevationGainM);
              return Expanded(
                child: Container(
                  margin: EdgeInsets.only(right: isLast ? 0 : 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLowest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.borderDivider),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MacStatusBadge(label: name, color: color),
                      const SizedBox(height: 8),
                      Text(
                        totalKm > 0 ? '${totalKm.toStringAsFixed(1)} km' : '${list.length} sessions',
                        style: AppTypography.telemetryLg,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${totalHours.toStringAsFixed(1)} hrs • ${totalElev.round()} m elev',
                        style: AppTypography.bodySm,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// INTERNAL DATA MODELS & CUSTOM PAINTERS
// =============================================================================

class _WeeklyVolumeBucket {
  final DateTime weekStart;
  double swimKm = 0;
  double bikeKm = 0;
  double runKm = 0;
  double swimHrs = 0;
  double bikeHrs = 0;
  double runHrs = 0;
  double strengthHrs = 0;
  int sessions = 0;

  _WeeklyVolumeBucket({required this.weekStart});

  double get totalKm => swimKm + bikeKm + runKm;
  double get totalHrs => swimHrs + bikeHrs + runHrs + strengthHrs;
}

class _PrEntry {
  final String sport;
  final String label;
  final String value;
  final String subtext;
  final Activity? activity;
  final Color color;

  const _PrEntry({
    required this.sport,
    required this.label,
    required this.value,
    required this.subtext,
    required this.activity,
    required this.color,
  });
}

class _DistanceBucketStats {
  final String label;
  final int count;
  final String avgMetricText;
  final String bestMetricText;
  final String avgHrText;

  const _DistanceBucketStats({
    required this.label,
    required this.count,
    required this.avgMetricText,
    required this.bestMetricText,
    required this.avgHrText,
  });
}

class _EfficiencyPoint {
  final Activity activity;
  final double efficiency;
  final double speedKmh;

  const _EfficiencyPoint({
    required this.activity,
    required this.efficiency,
    required this.speedKmh,
  });
}

/// 14-day mini sparkline for CTL / ATL KPI cards.
class _MiniSparklinePainter extends CustomPainter {
  final List<double> values;
  final Color color;

  _MiniSparklinePainter({required this.values, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) {
      canvas.drawLine(
        Offset(0, size.height * 0.65),
        Offset(size.width, size.height * 0.65),
        Paint()
          ..color = AppColors.borderDivider
          ..strokeWidth = 1.2,
      );
      return;
    }

    final minV = values.reduce(math.min);
    final maxV = values.reduce(math.max);
    final pad = math.max(1.0, (maxV - minV) * 0.15);
    final lo = minV - pad;
    final hi = maxV + pad;
    final range = math.max(0.1, hi - lo);
    final dx = size.width / (values.length - 1);

    final path = Path();
    final fill = Path();
    Offset? lastPt;

    for (int i = 0; i < values.length; i++) {
      final x = i * dx;
      final y = size.height - ((values[i] - lo) / range) * (size.height - 4) - 2;
      if (i == 0) {
        path.moveTo(x, y);
        fill.moveTo(x, size.height);
        fill.lineTo(x, y);
      } else {
        final prevX = (i - 1) * dx;
        final prevY = size.height - ((values[i - 1] - lo) / range) * (size.height - 4) - 2;
        final midX = (prevX + x) / 2;
        path.cubicTo(midX, prevY, midX, y, x, y);
        fill.cubicTo(midX, prevY, midX, y, x, y);
      }
      lastPt = Offset(x, y);
    }
    fill.lineTo(size.width, size.height);
    fill.close();

    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withOpacity(0.22), color.withOpacity(0.0)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    if (lastPt != null) {
      canvas.drawCircle(lastPt, 2.8, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _MiniSparklinePainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}

/// 14-day diverging bar chart around 0 for Form (TSB) KPI card.
class _MiniDivergingTsbPainter extends CustomPainter {
  final List<double> values;

  _MiniDivergingTsbPainter({required this.values});

  @override
  void paint(Canvas canvas, Size size) {
    final zeroY = size.height / 2;
    canvas.drawLine(
      Offset(0, zeroY),
      Offset(size.width, zeroY),
      Paint()
        ..color = AppColors.outline.withOpacity(0.35)
        ..strokeWidth = 1.0,
    );
    if (values.isEmpty) return;

    final maxAbs = math.max(5.0, values.map((v) => v.abs()).reduce(math.max));
    final slotW = size.width / values.length;
    final barW = math.max(2.5, slotW * 0.56);

    for (int i = 0; i < values.length; i++) {
      final v = values[i];
      final h = ((v.abs() / maxAbs) * (size.height / 2 - 2)).clamp(1.5, size.height / 2 - 2);
      final left = i * slotW + (slotW - barW) / 2;
      final isPos = v >= 0;
      final rect = isPos
          ? Rect.fromLTWH(left, zeroY - h, barW, h)
          : Rect.fromLTWH(left, zeroY, barW, h);
      final barColor = isPos
          ? AppColors.runTertiary
          : (v < -20 ? AppColors.error : AppColors.bikeSecondary);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        Paint()..color = barColor.withOpacity(0.85),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MiniDivergingTsbPainter oldDelegate) => oldDelegate.values != values;
}

/// Horizontal ACWR zone gauge bar (<0.8, 0.8-1.3, 1.3-1.5, >1.5) with live marker.
class _AcwrZoneGaugePainter extends CustomPainter {
  final double? acwr;

  _AcwrZoneGaugePainter({required this.acwr});

  @override
  void paint(Canvas canvas, Size size) {
    const double maxScale = 2.0;
    const double barH = 8.0;
    final double barTop = (size.height - barH) / 2 - 3;

    double xFor(double v) => (v.clamp(0.0, maxScale) / maxScale) * size.width;

    final segments = [
      (0.0, 0.8, AppColors.swimPrimary.withOpacity(0.55)),
      (0.8, 1.3, AppColors.runTertiary),
      (1.3, 1.5, AppColors.bikeSecondary),
      (1.5, 2.0, AppColors.error),
    ];

    for (int i = 0; i < segments.length; i++) {
      final (start, end, col) = segments[i];
      final x1 = xFor(start);
      final x2 = xFor(end);
      final r = Rect.fromLTRB(x1 + (i == 0 ? 0 : 1), barTop, x2 - (i == segments.length - 1 ? 0 : 1), barTop + barH);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          r,
          topLeft: i == 0 ? const Radius.circular(4) : Radius.zero,
          bottomLeft: i == 0 ? const Radius.circular(4) : Radius.zero,
          topRight: i == segments.length - 1 ? const Radius.circular(4) : Radius.zero,
          bottomRight: i == segments.length - 1 ? const Radius.circular(4) : Radius.zero,
        ),
        Paint()..color = col,
      );
    }

    // Subtle threshold tick marks
    for (final tick in [0.8, 1.3, 1.5]) {
      final tx = xFor(tick);
      final tp = TextPainter(
        text: TextSpan(
          text: tick.toStringAsFixed(1),
          style: TextStyle(
            fontSize: 8.5,
            color: AppColors.outline,
            fontFamily: AppTypography.systemFont,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset((tx - tp.width / 2).clamp(0, size.width - tp.width), barTop + barH + 3));
    }

    // Live indicator marker
    if (acwr != null) {
      final mx = xFor(acwr!);
      final cy = barTop + barH / 2;
      canvas.drawCircle(Offset(mx, cy), 6.0, Paint()..color = AppColors.surfaceContainer);
      canvas.drawCircle(Offset(mx, cy), 4.2, Paint()..color = AppColors.onSurface);
    }
  }

  @override
  bool shouldRepaint(covariant _AcwrZoneGaugePainter oldDelegate) => oldDelegate.acwr != acwr;
}

/// Interactive Stacked Weekly Volume Bar Chart (Last 12 Weeks).
class _InteractiveWeeklyVolumeChart extends StatefulWidget {
  final List<_WeeklyVolumeBucket> buckets;
  final bool showHours;
  final double height;

  const _InteractiveWeeklyVolumeChart({
    required this.buckets,
    required this.showHours,
    this.height = 200,
  });

  @override
  State<_InteractiveWeeklyVolumeChart> createState() => _InteractiveWeeklyVolumeChartState();
}

class _InteractiveWeeklyVolumeChartState extends State<_InteractiveWeeklyVolumeChart> {
  int? _hoveredIndex;

  @override
  Widget build(BuildContext context) {
    if (widget.buckets.isEmpty) return SizedBox(height: widget.height);

    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final idx = _hoveredIndex?.clamp(0, widget.buckets.length - 1);
          final slotW = w / widget.buckets.length;
          const tooltipW = 184.0;
          final centerX = idx != null ? (idx + 0.5) * slotW : 0.0;
          final tooltipLeft =
              (centerX - tooltipW / 2).clamp(6.0, math.max(6.0, w - tooltipW - 6)).toDouble();
          final hovered = idx != null ? widget.buckets[idx] : null;

          return MouseRegion(
            cursor: SystemMouseCursors.precise,
            onHover: (event) {
              final next = (event.localPosition.dx / math.max(1.0, slotW))
                  .floor()
                  .clamp(0, widget.buckets.length - 1);
              if (next != _hoveredIndex) {
                setState(() => _hoveredIndex = next);
              }
            },
            onExit: (_) {
              if (_hoveredIndex != null) setState(() => _hoveredIndex = null);
            },
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _WeeklyVolumePainter(
                      buckets: widget.buckets,
                      showHours: widget.showHours,
                      hoveredIndex: idx,
                    ),
                  ),
                ),
                if (hovered != null)
                  Positioned(
                    top: 6,
                    left: tooltipLeft,
                    child: IgnorePointer(
                      child: Container(
                        width: tooltipW,
                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainer.withOpacity(0.96),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.borderSubtle),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.cardShadow,
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${DateFormat('MMM d').format(hovered.weekStart)} – ${DateFormat('MMM d').format(hovered.weekStart.add(const Duration(days: 6)))}',
                              style: AppTypography.bodySm.copyWith(
                                fontWeight: FontWeight.w600,
                                color: AppColors.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.showHours
                                  ? '${hovered.totalHrs.toStringAsFixed(1)} hrs • ${hovered.sessions} sessions'
                                  : '${hovered.totalKm.toStringAsFixed(1)} km • ${hovered.sessions} sessions',
                              style: AppTypography.telemetrySm.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppColors.onSurface,
                              ),
                            ),
                            const SizedBox(height: 6),
                            _tipRow(
                              'Run',
                              widget.showHours
                                  ? '${hovered.runHrs.toStringAsFixed(1)} h'
                                  : '${hovered.runKm.toStringAsFixed(1)} km',
                              AppColors.runTertiary,
                            ),
                            const SizedBox(height: 2),
                            _tipRow(
                              'Bike',
                              widget.showHours
                                  ? '${hovered.bikeHrs.toStringAsFixed(1)} h'
                                  : '${hovered.bikeKm.toStringAsFixed(1)} km',
                              AppColors.bikeSecondary,
                            ),
                            const SizedBox(height: 2),
                            _tipRow(
                              'Swim',
                              widget.showHours
                                  ? '${hovered.swimHrs.toStringAsFixed(1)} h'
                                  : '${(hovered.swimKm * 1000).round()} m',
                              AppColors.swimPrimary,
                            ),
                            if (widget.showHours) ...[
                              const SizedBox(height: 2),
                              _tipRow(
                                'Strength',
                                '${hovered.strengthHrs.toStringAsFixed(1)} h',
                                AppColors.strengthViolet,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _tipRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(label, style: AppTypography.bodySm.copyWith(fontSize: 11)),
          ],
        ),
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
}

class _WeeklyVolumePainter extends CustomPainter {
  final List<_WeeklyVolumeBucket> buckets;
  final bool showHours;
  final int? hoveredIndex;

  _WeeklyVolumePainter({
    required this.buckets,
    required this.showHours,
    this.hoveredIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (buckets.isEmpty) return;

    final gridPaint = Paint()
      ..color = AppColors.borderDivider
      ..strokeWidth = 1.0;

    for (int i = 0; i <= 4; i++) {
      final y = (size.height / 4) * i;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final maxVal = math.max(
      1.0,
      buckets.map((b) => showHours ? b.totalHrs : b.totalKm).reduce(math.max),
    );
    final slotW = size.width / buckets.length;
    final barW = math.min(34.0, slotW * 0.56);

    for (int i = 0; i < buckets.length; i++) {
      final b = buckets[i];
      final isHovered = hoveredIndex == i;
      final dimmed = hoveredIndex != null && !isHovered;
      final opacity = dimmed ? 0.42 : 1.0;
      final left = i * slotW + (slotW - barW) / 2;

      if (isHovered) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(i * slotW + 2, 0, slotW - 4, size.height),
            const Radius.circular(6),
          ),
          Paint()..color = AppColors.accent.withOpacity(0.07),
        );
      }

      final segments = showHours
          ? [
              (b.swimHrs, AppColors.swimPrimary),
              (b.bikeHrs, AppColors.bikeSecondary),
              (b.runHrs, AppColors.runTertiary),
              (b.strengthHrs, AppColors.strengthViolet),
            ]
          : [
              (b.swimKm, AppColors.swimPrimary),
              (b.bikeKm, AppColors.bikeSecondary),
              (b.runKm, AppColors.runTertiary),
            ];

      final activeSegments = segments.where((s) => s.$1 > 0).toList();
      if (activeSegments.isEmpty) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(left, size.height - 3, barW, 3),
            const Radius.circular(2),
          ),
          Paint()..color = AppColors.surfaceContainerHigh,
        );
        continue;
      }

      double currentBottom = size.height;
      for (int sIdx = 0; sIdx < activeSegments.length; sIdx++) {
        final (val, col) = activeSegments[sIdx];
        final segH = ((val / maxVal) * (size.height - 10)).clamp(3.0, size.height - 10);
        final top = math.max(0.0, currentBottom - segH);
        final isTop = sIdx == activeSegments.length - 1;

        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTWH(left, top, barW, currentBottom - top),
            topLeft: isTop ? const Radius.circular(4) : Radius.zero,
            topRight: isTop ? const Radius.circular(4) : Radius.zero,
          ),
          Paint()..color = col.withOpacity(opacity),
        );
        currentBottom = top;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WeeklyVolumePainter oldDelegate) =>
      oldDelegate.buckets != buckets ||
      oldDelegate.showHours != showHours ||
      oldDelegate.hoveredIndex != hoveredIndex;
}

/// Interactive Hoverable Aerobic Efficiency Line Chart.
class _InteractiveEfficiencyChart extends StatefulWidget {
  final List<_EfficiencyPoint> points;
  final Color color;
  final bool isRun;
  final double height;
  final ValueChanged<String> onSelectActivity;

  const _InteractiveEfficiencyChart({
    required this.points,
    required this.color,
    required this.isRun,
    required this.onSelectActivity,
    this.height = 200,
  });

  @override
  State<_InteractiveEfficiencyChart> createState() => _InteractiveEfficiencyChartState();
}

class _InteractiveEfficiencyChartState extends State<_InteractiveEfficiencyChart> {
  int? _hoveredIndex;

  String _formatPace(double speedKmh) {
    if (speedKmh <= 0) return '—';
    final secPerKm = 3600.0 / speedKmh;
    final total = secPerKm.round();
    return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')} /km';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.points.length < 2) return const SizedBox.shrink();

    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final idx = _hoveredIndex?.clamp(0, widget.points.length - 1);
          final hovered = idx != null ? widget.points[idx] : null;
          final hoverX = idx != null ? (idx / (widget.points.length - 1)) * w : 0.0;
          const tooltipW = 196.0;
          final showLeft = hoverX > w - tooltipW - 18;
          final tooltipLeft = showLeft
              ? math.max(8.0, hoverX - tooltipW - 12)
              : math.min(w - tooltipW - 8, hoverX + 12);

          return MouseRegion(
            cursor: SystemMouseCursors.click,
            onHover: (event) {
              final frac = (event.localPosition.dx / math.max(1.0, w)).clamp(0.0, 1.0);
              final next = (frac * (widget.points.length - 1)).round();
              if (next != _hoveredIndex) {
                setState(() => _hoveredIndex = next);
              }
            },
            onExit: (_) {
              if (_hoveredIndex != null) setState(() => _hoveredIndex = null);
            },
            child: GestureDetector(
              onTap: () {
                if (hovered != null) {
                  widget.onSelectActivity(hovered.activity.id);
                }
              },
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _EfficiencyChartPainter(
                        values: widget.points.map((p) => p.efficiency).toList(),
                        color: widget.color,
                        hoveredIndex: idx,
                      ),
                    ),
                  ),
                  if (hovered != null)
                    Positioned(
                      top: 8,
                      left: tooltipLeft,
                      child: IgnorePointer(
                        child: Container(
                          width: tooltipW,
                          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainer.withOpacity(0.96),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.borderSubtle),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.cardShadow,
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                DateFormat('EEE, MMM d, y').format(hovered.activity.timestamp),
                                style: AppTypography.bodySm.copyWith(fontSize: 10.5),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                hovered.activity.title,
                                style: AppTypography.headlineSm.copyWith(fontSize: 11.5),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 5),
                              Text(
                                'Efficiency: ${hovered.efficiency.toStringAsFixed(2)}',
                                style: AppTypography.telemetryMd.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: widget.color,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.isRun
                                    ? '${_formatPace(hovered.speedKmh)} • ${hovered.activity.avgHr} bpm'
                                    : '${hovered.speedKmh.toStringAsFixed(1)} km/h • ${hovered.activity.avgHr} bpm',
                                style: AppTypography.telemetrySm,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _EfficiencyChartPainter extends CustomPainter {
  final List<double> values;
  final Color color;
  final int? hoveredIndex;

  _EfficiencyChartPainter({
    required this.values,
    required this.color,
    this.hoveredIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;

    final gridPaint = Paint()
      ..color = AppColors.borderDivider
      ..strokeWidth = 1.0;

    for (int i = 0; i <= 4; i++) {
      final y = (size.height / 4) * i;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final minV = values.reduce(math.min);
    final maxV = values.reduce(math.max);
    final pad = math.max(0.5, (maxV - minV) * 0.2);
    final lo = minV - pad;
    final hi = maxV + pad;
    final range = math.max(0.1, hi - lo);
    final dx = size.width / (values.length - 1);

    double yFor(double v) => size.height - ((v - lo) / range) * (size.height - 16) - 8;

    // Linear regression trendline
    final n = values.length;
    double sumX = 0, sumY = 0, sumXY = 0, sumXX = 0;
    for (int i = 0; i < n; i++) {
      sumX += i;
      sumY += values[i];
      sumXY += i * values[i];
      sumXX += i * i;
    }
    final denom = (n * sumXX - sumX * sumX);
    if (denom.abs() > 1e-6) {
      final slope = (n * sumXY - sumX * sumY) / denom;
      final intercept = (sumY - slope * sumX) / n;
      final yStart = yFor(intercept);
      final yEnd = yFor(intercept + slope * (n - 1));
      final dashPaint = Paint()
        ..color = AppColors.outline.withOpacity(0.5)
        ..strokeWidth = 1.2;
      const dashLen = 5.0;
      const gapLen = 4.0;
      final totalLen = math.sqrt(math.pow(size.width, 2) + math.pow(yEnd - yStart, 2));
      double dist = 0;
      while (dist < totalLen) {
        final t1 = (dist / totalLen).clamp(0.0, 1.0);
        final t2 = ((dist + dashLen) / totalLen).clamp(0.0, 1.0);
        canvas.drawLine(
          Offset(size.width * t1, yStart + (yEnd - yStart) * t1),
          Offset(size.width * t2, yStart + (yEnd - yStart) * t2),
          dashPaint,
        );
        dist += dashLen + gapLen;
      }
    }

    // Smooth curve + area fill
    final path = Path();
    final fill = Path();
    final pts = <Offset>[];
    for (int i = 0; i < values.length; i++) {
      final x = i * dx;
      final y = yFor(values[i]);
      pts.add(Offset(x, y));
      if (i == 0) {
        path.moveTo(x, y);
        fill.moveTo(x, size.height);
        fill.lineTo(x, y);
      } else {
        final prev = pts[i - 1];
        final midX = (prev.dx + x) / 2;
        path.cubicTo(midX, prev.dy, midX, y, x, y);
        fill.cubicTo(midX, prev.dy, midX, y, x, y);
      }
    }
    fill.lineTo(size.width, size.height);
    fill.close();

    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withOpacity(0.18), color.withOpacity(0.0)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // Subtle dots on each session
    for (int i = 0; i < pts.length; i++) {
      canvas.drawCircle(pts[i], 3.0, Paint()..color = color);
    }

    // Hovered crosshair + highlight dot
    if (hoveredIndex != null && hoveredIndex! >= 0 && hoveredIndex! < pts.length) {
      final pt = pts[hoveredIndex!];
      canvas.drawLine(
        Offset(pt.dx, 0),
        Offset(pt.dx, size.height),
        Paint()
          ..color = AppColors.outline.withOpacity(0.55)
          ..strokeWidth = 1.0,
      );
      canvas.drawCircle(pt, 5.5, Paint()..color = color);
      canvas.drawCircle(
        pt,
        5.5,
        Paint()
          ..color = AppColors.surfaceContainer
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EfficiencyChartPainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.color != color ||
      oldDelegate.hoveredIndex != hoveredIndex;
}
