import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/activity.dart';
import '../models/strava_enrichment.dart';
import '../services/url_opener.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../utils/physiological_metrics.dart';
import '../utils/unit_formatter.dart';
import '../components/activity_telemetry_stack.dart';
import '../components/macos_heatmap_view.dart';
import '../components/macos_ui.dart';
import '../components/zones_and_drift_cards.dart';

/// Unified native macOS Activity Detail view with:
/// - "View in Garmin" and "View in Strava" links
/// - Synced Strava title, description, kudos, comments, and segment PRs
/// - Linked intervals.icu-style Map <-> Stacked Telemetry Scrubber (no overlap)
/// - Imperial / Metric unit support and clean decimal formatting
class ActivityDetailView extends StatefulWidget {
  final Activity activity;
  final AppState appState;

  const ActivityDetailView({
    super.key,
    required this.activity,
    required this.appState,
  });

  @override
  State<ActivityDetailView> createState() => _ActivityDetailViewState();
}

class _ActivityDetailViewState extends State<ActivityDetailView> {
  int? _hoveredRouteIndex;

  Activity get activity => widget.activity;
  AppState get appState => widget.appState;

  (String, Color, IconData) get _sportMeta => switch (activity.discipline) {
        SportDiscipline.bike => ('Cycling', AppColors.bikeSecondary, Icons.directions_bike_rounded),
        SportDiscipline.indoorBike => ('Indoor Cycling', AppColors.bikeSecondary, CupertinoIcons.bolt_fill),
        SportDiscipline.run => ('Running', AppColors.runTertiary, CupertinoIcons.flame),
        SportDiscipline.swim => ('Swimming', AppColors.swimPrimary, CupertinoIcons.drop_fill),
        SportDiscipline.strength => ('Strength', AppColors.strengthViolet, CupertinoIcons.sportscourt),
      };

  @override
  Widget build(BuildContext context) {
    final (sportLabel, sportColor, sportIcon) = _sportMeta;
    final strava = appState.stravaEnrichmentFor(activity.id);
    final displayTitle = appState.displayTitleFor(activity);
    final stravaDesc = strava?.description?.trim() ?? '';
    final effectiveDescription =
        stravaDesc.isNotEmpty ? stravaDesc : activity.description;
    final effectiveGear = strava?.gearName ?? activity.gearName;
    final unit = appState.unitSystem;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Back navigation breadcrumb + External Links (View in Garmin / View in Strava)
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  MacPushButton(
                    label: 'All Activities',
                    icon: CupertinoIcons.chevron_back,
                    onPressed: () => appState.setSelectedActivityId(null),
                  ),
                  const SizedBox(width: 12),
                  MacStatusBadge(label: sportLabel, color: sportColor, icon: sportIcon),
                  const SizedBox(width: 10),
                  Text(
                    'ID ${activity.id}',
                    style: AppTypography.telemetrySm.copyWith(color: AppColors.outline),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  MacPushButton(
                    label: 'View in Garmin',
                    icon: CupertinoIcons.arrow_up_right_square,
                    onPressed: () => UrlOpener.openUrl(UrlOpener.garminActivityUrl(activity.id)),
                  ),
                  if (strava != null) ...[
                    const SizedBox(width: 8),
                    MacPushButton(
                      label: 'View in Strava',
                      icon: CupertinoIcons.flame_fill,
                      isPrimary: true,
                      onPressed: () => UrlOpener.openUrl(strava.stravaUrl),
                    ),
                  ],
                ],
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Header Card
          MacCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(displayTitle, style: AppTypography.headlineLg),
                    ),
                    if (strava != null) ...[
                      const SizedBox(width: 10),
                      MacStatusBadge(
                        label: '${strava.kudosCount} kudos',
                        color: const Color(0xFFFC4C02),
                        icon: CupertinoIcons.hand_thumbsup_fill,
                      ),
                      if (strava.commentCount > 0) ...[
                        const SizedBox(width: 6),
                        MacStatusBadge(
                          label: '${strava.commentCount} comments',
                          color: AppColors.accent,
                          icon: CupertinoIcons.chat_bubble_fill,
                        ),
                      ],
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${activity.formattedDate}'
                  '${activity.location.isNotEmpty ? ' • ${activity.location}' : ''}'
                  '${effectiveGear != null && effectiveGear.isNotEmpty ? ' • $effectiveGear' : ''}',
                  style: AppTypography.bodyMd,
                ),
                if (effectiveDescription.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(effectiveDescription, style: AppTypography.bodyLg),
                ],
                const SizedBox(height: 16),
                Divider(height: 1, color: AppColors.borderDivider),
                const SizedBox(height: 14),

                // Primary Metrics Grid (respects Imperial / Metric switcher)
                Wrap(
                  spacing: 24,
                  runSpacing: 14,
                  children: [
                    if (activity.distanceKm > 0)
                      _kpi('Distance', appState.formatActivityDistance(activity, decimals: 2)),
                    _kpi('Moving Time', activity.movingTime),
                    _kpi('Elapsed Time', activity.elapsedTime),
                    if (activity.avgSpeedOrPace != '—')
                      _kpi(
                        activity.discipline == SportDiscipline.bike ||
                                activity.discipline == SportDiscipline.indoorBike
                            ? 'Avg Speed'
                            : 'Avg Pace',
                        appState.formatActivityPaceOrSpeed(activity),
                      ),
                    if (activity.avgHr > 0) _kpi('Avg HR', '${activity.avgHr} bpm'),
                    if (activity.maxHr > 0) _kpi('Max HR', '${activity.maxHr} bpm'),
                    if (activity.elevationGainM > 0)
                      _kpi('Elevation Gain', appState.formatActivityElevation(activity.elevationGainM)),
                    if (activity.avgPowerW != null) _kpi('Avg Power', '${activity.avgPowerW} W'),
                    if (activity.normPowerW != null) _kpi('Normalized Power', '${activity.normPowerW} W'),
                    if (activity.tss != null) _kpi('Training Load', '${activity.tss!.round()}'),
                    if (strava?.sufferScore != null) _kpi('Relative Effort', '${strava!.sufferScore}'),
                    if (activity.avgCadence != null)
                      _kpi(
                        'Avg Cadence',
                        activity.discipline == SportDiscipline.run
                            ? '${activity.avgCadence} spm'
                            : '${activity.avgCadence} rpm',
                      ),
                    if (activity.swolf != null) _kpi('SWOLF', '${activity.swolf}'),
                    if (activity.calories > 0) _kpi('Calories', '${activity.calories} kcal'),
                  ],
                ),
              ],
            ),
          ),

          // Interactive GPS Route & Pace Heat Map (Large, no overlap with charts)
          if (activity.routePoints.isNotEmpty ||
              (activity.startLatitude != null && activity.startLongitude != null)) ...[
            const SizedBox(height: 16),
            MacosHeatmapView(
              activities: [activity],
              height: 340,
              titleOverride: 'Route & Pace Heat Map',
              showFilterBar: false,
              colorByPace: true,
              isImperial: appState.isImperial,
              highlightedPointIndex: _hoveredRouteIndex,
              onPointHovered: (idx) {
                if (idx != _hoveredRouteIndex) {
                  setState(() => _hoveredRouteIndex = idx);
                }
              },
              isSignedIn: appState.isSignedIn,
              isLoadingRoutes:
                  (appState.isLoadingPolylines || appState.isLoadingSplits) &&
                  activity.routePoints.isEmpty,
            ),
          ],

          // Linked intervals.icu-style Synchronized Telemetry Chart Stack (right below map, zero overlap)
          if (activity.routePoints.length >= 2) ...[
            const SizedBox(height: 16),
            ActivityTelemetryStack(
              activity: activity,
              hoveredIndex: _hoveredRouteIndex,
              onHoverIndexChanged: (idx) {
                if (idx != _hoveredRouteIndex) {
                  setState(() => _hoveredRouteIndex = idx);
                }
              },
              isImperial: appState.isImperial,
            ),
          ],

          // Heart Rate & Power Time-in-Zone Breakdown + Cardiac Drift (for 60+ min sessions)
          ..._buildZonesAndDriftWidgets(unit),

          // Strava Comments & Segment Efforts (when joined with Strava)
          if (strava != null) ...[
            const SizedBox(height: 16),
            _buildStravaEnrichmentCard(strava, unit),
          ],

          // Running Dynamics (only if Garmin returned them for this activity)
          if (activity.runningDynamics != null) ...[
            const SizedBox(height: 16),
            _buildRunningDynamicsCard(activity.runningDynamics!),
          ],

          const SizedBox(height: 16),

          // Live Garmin Lap Splits Table
          _buildSplitsCard(unit),
        ],
      ),
    );
  }

  List<Widget> _buildZonesAndDriftWidgets(UnitSystem unit) {
    final hrZones = computeActivityHrZones(activity);
    final powerZones = computeActivityPowerZones(activity);
    final drift = computeCardiacDrift(activity, unit: unit);
    final widgets = <Widget>[];

    if (hrZones.isNotEmpty || powerZones.isNotEmpty) {
      widgets.add(const SizedBox(height: 16));
      widgets.add(
        TimeInZoneCard(
          title: 'Time in Zone',
          subtitle: powerZones.isNotEmpty
              ? 'Z1–Z5 Heart Rate & Power distribution'
              : 'Z1–Z5 Heart Rate distribution',
          hrZones: hrZones,
          powerZones: powerZones,
        ),
      );
    }

    if (drift != null) {
      widgets.add(const SizedBox(height: 16));
      widgets.add(
        CardiacDriftCard(
          result: drift,
          title: 'Cardiac Drift & Aerobic Decoupling (${drift.metricLabel})',
        ),
      );
    }

    return widgets;
  }

  Widget _buildStravaEnrichmentCard(StravaActivityEnrichment strava, UnitSystem unit) {
    const stravaOrange = Color(0xFFFC4C02);
    return MacCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(CupertinoIcons.flame_fill, size: 16, color: stravaOrange),
                  const SizedBox(width: 8),
                  Text('Strava Social & Segments', style: AppTypography.headlineMd),
                ],
              ),
              if (appState.isLoadingStravaDetail)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CupertinoActivityIndicator(radius: 7),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Segment Efforts / PRs
          if (strava.segmentEfforts.isNotEmpty) ...[
            Text('Segment Efforts', style: AppTypography.headlineSm),
            const SizedBox(height: 8),
            ...strava.segmentEfforts.take(8).map((seg) {
              final distStr = UnitFormatter.formatDistance(seg.distanceM / 1000.0, unit, decimals: 2);
              final mins = seg.elapsedSec ~/ 60;
              final secs = seg.elapsedSec % 60;
              final timeStr = '$mins:${secs.toString().padLeft(2, '0')}';
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLowest,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: AppColors.borderDivider),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              seg.name,
                              style: AppTypography.bodyMd.copyWith(
                                fontWeight: FontWeight.w600,
                                color: AppColors.onSurface,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '$distStr • ${seg.avgGrade.toStringAsFixed(1)}% grade'
                              '${seg.avgWatts != null ? ' • ${seg.avgWatts} W' : ''}',
                              style: AppTypography.bodySm,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (seg.isKom)
                        const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: MacStatusBadge(label: 'KOM / CR', color: stravaOrange),
                        )
                      else if (seg.prRank != null && seg.prRank! <= 3)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: MacStatusBadge(
                            label: seg.prRank == 1 ? 'PR' : '#${seg.prRank} Best',
                            color: AppColors.runTertiary,
                          ),
                        ),
                      Text(
                        timeStr,
                        style: AppTypography.telemetryMd.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 10),
          ],

          // Comments
          if (strava.comments.isNotEmpty) ...[
            Text('Comments (${strava.comments.length})', style: AppTypography.headlineSm),
            const SizedBox(height: 8),
            ...strava.comments.map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLowest,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.borderDivider),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              c.authorName,
                              style: AppTypography.bodySm.copyWith(
                                fontWeight: FontWeight.w600,
                                color: AppColors.onSurface,
                              ),
                            ),
                            Text(
                              DateFormat('MMM d, h:mm a').format(c.createdAt.toLocal()),
                              style: AppTypography.bodySm.copyWith(fontSize: 10),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(c.text, style: AppTypography.bodyMd.copyWith(color: AppColors.onSurface)),
                      ],
                    ),
                  ),
                )),
          ] else if (!appState.isLoadingStravaDetail && strava.segmentEfforts.isEmpty)
            Text(
              'Joined with Strava activity #${strava.stravaId} • ${strava.kudosCount} kudos',
              style: AppTypography.bodySm,
            ),
        ],
      ),
    );
  }

  Widget _kpi(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.bodySm),
        const SizedBox(height: 2),
        Text(value, style: AppTypography.telemetryLg),
      ],
    );
  }

  Widget _buildRunningDynamicsCard(RunningDynamics rd) {
    return MacCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Running Dynamics', style: AppTypography.headlineMd),
          const SizedBox(height: 12),
          Wrap(
            spacing: 28,
            runSpacing: 12,
            children: [
              if (rd.groundContactTimeMs > 0)
                _kpi('Ground Contact Time', '${rd.groundContactTimeMs} ms'),
              if (rd.leftBalancePercent > 0)
                _kpi(
                  'L / R Balance',
                  '${rd.leftBalancePercent.toStringAsFixed(1)}% / ${rd.rightBalancePercent.toStringAsFixed(1)}%',
                ),
              if (rd.verticalOscillationCm > 0)
                _kpi('Vertical Oscillation', '${rd.verticalOscillationCm.toStringAsFixed(1)} cm'),
              if (rd.strideLengthM > 0)
                _kpi('Stride Length', '${rd.strideLengthM.toStringAsFixed(2)} m'),
              if (rd.verticalRatioPercent > 0)
                _kpi('Vertical Ratio', UnitFormatter.formatPercent(rd.verticalRatioPercent)),
              if (rd.runningPowerWatts > 0)
                _kpi('Running Power', '${rd.runningPowerWatts} W'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSplitsCard(UnitSystem unit) {
    final splits = activity.splits;
    final isSpeedDiscipline =
        activity.discipline == SportDiscipline.bike ||
        activity.discipline == SportDiscipline.indoorBike;

    return MacCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Lap Splits', style: AppTypography.headlineMd),
              if (appState.isLoadingSplits)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CupertinoActivityIndicator(radius: 7),
                )
              else
                Text('${splits.length} laps', style: AppTypography.bodySm),
            ],
          ),
          const SizedBox(height: 12),
          if (appState.isLoadingSplits && splits.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(child: CupertinoActivityIndicator()),
            )
          else if (splits.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'No lap splits were recorded for this activity in Garmin Connect.',
                  style: AppTypography.bodyMd,
                ),
              ),
            )
          else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.surfaceLowest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  SizedBox(width: 64, child: Text('Lap', style: AppTypography.labelCaps)),
                  Expanded(child: Text('Distance', style: AppTypography.labelCaps)),
                  Expanded(child: Text('Time', style: AppTypography.labelCaps)),
                  Expanded(
                    child: Text(
                      isSpeedDiscipline ? 'Speed' : 'Pace',
                      style: AppTypography.labelCaps,
                    ),
                  ),
                  Expanded(child: Text('Avg HR', style: AppTypography.labelCaps)),
                  Expanded(child: Text('Power / Elev', style: AppTypography.labelCaps)),
                ],
              ),
            ),
            const SizedBox(height: 6),
            ...splits.map((s) {
              final distStr = s.distanceKm > 0
                  ? UnitFormatter.formatDistance(
                      s.distanceKm,
                      unit,
                      discipline: activity.discipline,
                      decimals: 2,
                    )
                  : '—';
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 64,
                      child: Text(
                        s.label,
                        style: AppTypography.bodyMd.copyWith(
                          color: AppColors.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(child: Text(distStr, style: AppTypography.telemetrySm)),
                    Expanded(child: Text(s.time, style: AppTypography.telemetrySm)),
                    Expanded(
                      child: Text(
                        s.paceOrSpeed,
                        style: AppTypography.telemetrySm.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        s.avgHr > 0 ? '${s.avgHr} bpm' : '—',
                        style: AppTypography.telemetrySm,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        s.avgPower != null
                            ? '${s.avgPower} W'
                            : (s.elevationDeltaM != null
                                ? '+${UnitFormatter.formatElevation(s.elevationDeltaM!, unit)}'
                                : '—'),
                        style: AppTypography.telemetrySm,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}
