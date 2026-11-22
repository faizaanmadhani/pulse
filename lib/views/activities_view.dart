import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../state/app_state.dart';
import '../models/activity.dart';
import '../components/garmin_sign_in_dialog.dart';
import '../components/macos_ui.dart';
import 'activity_detail_view.dart';

class ActivitiesView extends StatefulWidget {
  final AppState appState;

  const ActivitiesView({super.key, required this.appState});

  @override
  State<ActivitiesView> createState() => _ActivitiesViewState();
}

class _ActivitiesViewState extends State<ActivitiesView> {
  static const int _pageSize = 12;

  String _activeDisciplineFilter = 'ALL';
  String _viewMode = 'Feed'; // 'Feed' (Strava-style cards) or 'Table'
  int _visibleCount = _pageSize;

  @override
  Widget build(BuildContext context) {
    if (!widget.appState.isSignedIn) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: MacEmptyState(
          icon: CupertinoIcons.list_bullet,
          title: 'Your Garmin Activities',
          message:
              'Sign in with your Garmin Connect account to browse your runs, rides, swims, and strength workouts with route maps and telemetry.',
          actionLabel: 'Sign in with Garmin',
          onAction: () => showGarminSignInDialog(context, widget.appState),
        ),
      );
    }

    final selectedId = widget.appState.selectedActivityId;
    if (selectedId != null && widget.appState.activities.isNotEmpty) {
      final act = widget.appState.activities.firstWhere(
        (a) => a.id == selectedId,
        orElse: () => widget.appState.activities.first,
      );
      return ActivityDetailView(activity: act, appState: widget.appState);
    }

    return _buildActivitiesBrowser();
  }

  List<Activity> _getFilteredActivities() {
    final query = widget.appState.searchQuery.toLowerCase();
    return widget.appState.activities.where((act) {
      if (_activeDisciplineFilter == 'BIKE' &&
          act.discipline != SportDiscipline.bike &&
          act.discipline != SportDiscipline.indoorBike) {
        return false;
      }
      if (_activeDisciplineFilter == 'RUN' && act.discipline != SportDiscipline.run) return false;
      if (_activeDisciplineFilter == 'SWIM' && act.discipline != SportDiscipline.swim) return false;
      if (_activeDisciplineFilter == 'STRENGTH' && act.discipline != SportDiscipline.strength) {
        return false;
      }
      if (_activeDisciplineFilter == 'INDOOR' && act.discipline != SportDiscipline.indoorBike) {
        return false;
      }

      if (query.isNotEmpty) {
        final title = widget.appState.displayTitleFor(act).toLowerCase();
        return title.contains(query) ||
            act.location.toLowerCase().contains(query) ||
            act.id.toLowerCase().contains(query);
      }
      return true;
    }).toList();
  }

  Widget _buildActivitiesBrowser() {
    final filtered = _getFilteredActivities();
    final displayed = filtered.take(_visibleCount).toList();
    final hasMore = filtered.length > displayed.length;

    // Lazily fetch GPS route polylines for currently visible feed cards
    if (_viewMode == 'Feed' && displayed.isNotEmpty) {
      final idsToEnsure = displayed
          .where((a) => a.routePoints.isEmpty && a.startLatitude != null)
          .map((a) => a.id)
          .toList();
      if (idsToEnsure.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            widget.appState.ensurePolylinesLoaded(idsToEnsure);
          }
        });
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Filter + Feed/Table Mode Bar
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 10,
            children: [
              MacSegmentedControl<String>(
                items: const ['ALL', 'RUN', 'BIKE', 'SWIM', 'STRENGTH', 'INDOOR'],
                selected: _activeDisciplineFilter,
                labelBuilder: (val) => switch (val) {
                  'ALL' => 'All',
                  'RUN' => 'Run',
                  'BIKE' => 'Bike',
                  'SWIM' => 'Swim',
                  'STRENGTH' => 'Strength',
                  'INDOOR' => 'Indoor',
                  _ => val,
                },
                dotColorBuilder: (val) => switch (val) {
                  'RUN' => AppColors.runTertiary,
                  'BIKE' => AppColors.bikeSecondary,
                  'SWIM' => AppColors.swimPrimary,
                  'STRENGTH' => AppColors.strengthViolet,
                  'INDOOR' => AppColors.bikeSecondary,
                  _ => null,
                },
                onChanged: (val) => setState(() {
                  _activeDisciplineFilter = val;
                  _visibleCount = _pageSize;
                }),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Showing ${displayed.length} of ${filtered.length}',
                    style: AppTypography.bodySm,
                  ),
                  const SizedBox(width: 12),
                  MacSegmentedControl<String>(
                    items: const ['Feed', 'Table'],
                    selected: _viewMode,
                    labelBuilder: (m) => m,
                    onChanged: (val) => setState(() => _viewMode = val),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 16),

          if (filtered.isEmpty)
            MacCard(
              padding: const EdgeInsets.symmetric(vertical: 42),
              child: Center(
                child: Text(
                  widget.appState.activities.isEmpty
                      ? 'No Garmin activities synced yet.'
                      : 'No activities match your current filter or search.',
                  style: AppTypography.bodyMd,
                ),
              ),
            )
          else if (_viewMode == 'Feed')
            ActivityFeedGrid(activities: displayed, appState: widget.appState)
          else
            _buildTableView(displayed),

          // Pagination Load More Bar
          if (hasMore) ...[
            const SizedBox(height: 16),
            Center(
              child: MacPushButton(
                label:
                    'Load More Activities (${math.min(_pageSize, filtered.length - displayed.length)} more)',
                icon: CupertinoIcons.arrow_down_circle,
                onPressed: () => setState(() => _visibleCount += _pageSize),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTableView(List<Activity> items) {
    return MacCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surfaceLowest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                SizedBox(width: 108, child: Text('Sport', style: AppTypography.labelCaps)),
                Expanded(flex: 3, child: Text('Activity', style: AppTypography.labelCaps)),
                Expanded(flex: 2, child: Text('Date', style: AppTypography.labelCaps)),
                Expanded(child: Text('Distance', style: AppTypography.labelCaps)),
                Expanded(child: Text('Time', style: AppTypography.labelCaps)),
                Expanded(child: Text('Pace / Speed', style: AppTypography.labelCaps)),
                Expanded(child: Text('Avg HR', style: AppTypography.labelCaps)),
                const SizedBox(width: 24),
              ],
            ),
          ),
          const SizedBox(height: 6),
          ...items.asMap().entries.map((entry) {
            final isLast = entry.key == items.length - 1;
            return Column(
              children: [
                _buildTableRow(entry.value),
                if (!isLast) Divider(height: 1, color: AppColors.borderDivider),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTableRow(Activity act) {
    final (label, color, _) = _sportStyle(act.discipline);

    return InkWell(
      onTap: () => widget.appState.setSelectedActivityId(act.id),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 108,
              child: Align(
                alignment: Alignment.centerLeft,
                child: MacStatusBadge(label: label, color: color),
              ),
            ),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          widget.appState.displayTitleFor(act),
                          style: AppTypography.headlineSm,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (widget.appState.stravaEnrichmentFor(act.id) != null) ...[
                        const SizedBox(width: 5),
                        const Icon(
                          CupertinoIcons.flame_fill,
                          size: 11,
                          color: Color(0xFFFC4C02),
                        ),
                      ],
                    ],
                  ),
                  if (act.location.isNotEmpty)
                    Text(
                      act.location,
                      style: AppTypography.bodySm,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                act.formattedDate.split('•').first.trim(),
                style: AppTypography.telemetrySm,
              ),
            ),
            Expanded(
              child: Text(
                widget.appState.formatActivityDistance(act),
                style: AppTypography.telemetrySm.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurface,
                ),
              ),
            ),
            Expanded(child: Text(act.movingTime, style: AppTypography.telemetrySm)),
            Expanded(
              child: Text(
                widget.appState.formatActivityPaceOrSpeed(act),
                style: AppTypography.telemetrySm.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: Text(
                act.avgHr > 0 ? '${act.avgHr} bpm' : '—',
                style: AppTypography.telemetrySm,
              ),
            ),
            SizedBox(
              width: 24,
              child: Icon(CupertinoIcons.chevron_right, size: 14, color: AppColors.outline),
            ),
          ],
        ),
      ),
    );
  }

  (String, Color, IconData) _sportStyle(SportDiscipline d) => _activitySportStyle(d);
}

(String, Color, IconData) _activitySportStyle(SportDiscipline d) => switch (d) {
      SportDiscipline.bike => ('Cycling', AppColors.bikeSecondary, Icons.directions_bike_rounded),
      SportDiscipline.indoorBike => ('Indoor Bike', AppColors.bikeSecondary, CupertinoIcons.bolt_fill),
      SportDiscipline.run => ('Run', AppColors.runTertiary, CupertinoIcons.flame_fill),
      SportDiscipline.swim => ('Swim', AppColors.swimPrimary, CupertinoIcons.drop_fill),
      SportDiscipline.strength => ('Strength', AppColors.strengthViolet, CupertinoIcons.sportscourt_fill),
    };

/// Responsive 1- or 2-column Strava-style feed grid of [ActivityFeedCard]s.
class ActivityFeedGrid extends StatelessWidget {
  final List<Activity> activities;
  final AppState appState;

  const ActivityFeedGrid({
    super.key,
    required this.activities,
    required this.appState,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useTwoColumns = constraints.maxWidth > 1060;
        if (!useTwoColumns) {
          return Column(
            children: activities
                .map((act) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: ActivityFeedCard(activity: act, appState: appState),
                    ))
                .toList(),
          );
        }

        final rows = <Widget>[];
        for (int i = 0; i < activities.length; i += 2) {
          final left = activities[i];
          final right = i + 1 < activities.length ? activities[i + 1] : null;
          rows.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: ActivityFeedCard(activity: left, appState: appState)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: right != null
                        ? ActivityFeedCard(activity: right, appState: appState)
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          );
        }
        return Column(children: rows);
      },
    );
  }
}

/// Reusable Strava-style activity feed card with mini route map, telemetry, and stream sparkline.
class ActivityFeedCard extends StatelessWidget {
  final Activity activity;
  final AppState appState;

  const ActivityFeedCard({
    super.key,
    required this.activity,
    required this.appState,
  });

  @override
  Widget build(BuildContext context) {
    final act = activity;
    final (label, color, icon) = _activitySportStyle(act.discipline);
    final strava = appState.stravaEnrichmentFor(act.id);
    final title = appState.displayTitleFor(act);
    final desc = (strava?.description?.trim().isNotEmpty == true)
        ? strava!.description!.trim()
        : act.description;
    final hasRoute = act.routePoints.length >= 2;
    final hasHrOrElev = act.routePoints.any((p) => p.heartRate != null || p.elevationM != null);
    final paceOrSpeed = appState.formatActivityPaceOrSpeed(act);

    return InkWell(
      onTap: () => appState.setSelectedActivityId(act.id),
      borderRadius: BorderRadius.circular(10),
      child: MacCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Header: Sport icon, Title, Date/Location, Strava Kudos/Comments
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(icon, size: 16, color: color),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    title,
                                    style: AppTypography.headlineMd,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (strava != null) ...[
                                  const SizedBox(width: 6),
                                  const Icon(
                                    CupertinoIcons.flame_fill,
                                    size: 13,
                                    color: Color(0xFFFC4C02),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${act.formattedDate}${act.location.isNotEmpty ? ' • ${act.location}' : ''}',
                              style: AppTypography.bodySm,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      MacStatusBadge(label: label, color: color),
                    ],
                  ),
                  if (desc.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      desc,
                      style: AppTypography.bodyMd,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 12),

                  // Strava-style Key Telemetry Strip
                  Row(
                    children: [
                      Expanded(
                        child: _feedMetric(
                          'Distance',
                          appState.formatActivityDistance(act),
                        ),
                      ),
                      Expanded(
                        child: _feedMetric('Time', act.movingTime),
                      ),
                      Expanded(
                        child: _feedMetric(
                          act.discipline == SportDiscipline.bike ||
                                  act.discipline == SportDiscipline.indoorBike
                              ? 'Avg Speed'
                              : 'Pace',
                          paceOrSpeed,
                          valueColor: color,
                        ),
                      ),
                      if (act.elevationGainM > 0)
                        Expanded(
                          child: _feedMetric(
                            'Elevation',
                            appState.formatActivityElevation(act.elevationGainM),
                          ),
                        )
                      else if (act.avgHr > 0)
                        Expanded(
                          child: _feedMetric('Avg HR', '${act.avgHr} bpm'),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            // Visual Map Preview (for GPS tracks) or Mini Telemetry Sparkline
            if (hasRoute)
              _buildFeedMiniMap(act, color)
            else if (act.startLatitude != null && act.startLongitude != null)
              Container(
                height: 96,
                color: AppColors.surfaceLowest,
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(CupertinoIcons.map, size: 15, color: AppColors.outline),
                    const SizedBox(width: 8),
                    Text('GPS route synced • tap to inspect', style: AppTypography.bodySm),
                  ],
                ),
              ),

            // Mini HR / Elevation Sparkline Strip when telemetry stream is available
            if (hasHrOrElev)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: SizedBox(
                  height: 36,
                  child: CustomPaint(
                    painter: _FeedMiniStreamPainter(
                      points: act.routePoints,
                      color: color,
                    ),
                  ),
                ),
              ),

            // Footer: Avg HR, Power, Kudos/Comments, Open link
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (act.avgHr > 0)
                        _footerPill(CupertinoIcons.heart_fill, '${act.avgHr} bpm', AppColors.error),
                      if (act.avgPowerW != null &&
                          (act.discipline == SportDiscipline.bike ||
                              act.discipline == SportDiscipline.indoorBike))
                        _footerPill(CupertinoIcons.bolt_fill, '${act.avgPowerW} W', AppColors.bikeSecondary),
                      if (strava != null && strava.kudosCount > 0)
                        _footerPill(
                          CupertinoIcons.hand_thumbsup_fill,
                          '${strava.kudosCount} kudos',
                          const Color(0xFFFC4C02),
                        ),
                      if (strava != null && strava.commentCount > 0)
                        _footerPill(
                          CupertinoIcons.chat_bubble_fill,
                          '${strava.commentCount}',
                          AppColors.accent,
                        ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Inspect',
                        style: AppTypography.bodySm.copyWith(
                          color: AppColors.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Icon(CupertinoIcons.chevron_right, size: 12, color: AppColors.accent),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeedMiniMap(Activity act, Color sportColor) {
    final pts = act.routePoints
        .where((p) => p.lat.isFinite && p.lon.isFinite && p.lat.abs() <= 85 && p.lon.abs() <= 180)
        .map((p) => LatLng(p.lat, p.lon))
        .toList();
    if (pts.length < 2) return const SizedBox.shrink();

    double minLat = double.infinity, maxLat = -double.infinity;
    double minLon = double.infinity, maxLon = -double.infinity;
    for (final p in pts) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLon) minLon = p.longitude;
      if (p.longitude > maxLon) maxLon = p.longitude;
    }
    if ((maxLat - minLat).abs() < 0.002) {
      minLat -= 0.002;
      maxLat += 0.002;
    }
    if ((maxLon - minLon).abs() < 0.002) {
      minLon -= 0.002;
      maxLon += 0.002;
    }
    final bounds = LatLngBounds(LatLng(minLat, minLon), LatLng(maxLat, maxLon));
    final isDark = AppColors.isDark;

    return SizedBox(
      height: 155,
      child: IgnorePointer(
        child: FlutterMap(
          options: MapOptions(
            initialCameraFit: CameraFit.bounds(
              bounds: bounds,
              padding: const EdgeInsets.all(18),
              maxZoom: 15.5,
            ),
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.pulse.training',
              tileBuilder: isDark
                  ? (context, tileWidget, tile) => ColorFiltered(
                        colorFilter: const ColorFilter.matrix([
                          -0.85, 0, 0, 0, 235,
                          0, -0.85, 0, 0, 238,
                          0, 0, -0.85, 0, 245,
                          0, 0, 0, 1, 0,
                        ]),
                        child: tileWidget,
                      )
                  : null,
              errorTileCallback: (tile, error, stackTrace) {},
            ),
            PolylineLayer(
              polylines: [
                Polyline(
                  points: pts,
                  strokeWidth: 5.5,
                  color: sportColor.withOpacity(0.25),
                ),
                Polyline(
                  points: pts,
                  strokeWidth: 2.8,
                  color: sportColor,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _feedMetric(String label, String value, {Color? valueColor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.bodySm.copyWith(fontSize: 10)),
        const SizedBox(height: 1),
        Text(
          value,
          style: AppTypography.telemetryMd.copyWith(
            fontWeight: FontWeight.w700,
            color: valueColor ?? AppColors.onSurface,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _footerPill(IconData icon, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: AppTypography.telemetrySm.copyWith(
            fontSize: 11,
            color: AppColors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Compact dual-stream sparkline (elevation fill + HR line) shown inside feed cards.
class _FeedMiniStreamPainter extends CustomPainter {
  final List<GpsPoint> points;
  final Color color;

  _FeedMiniStreamPainter({required this.points, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final elevs = points.map((p) => p.elevationM).whereType<double>().toList();
    if (elevs.length >= 2) {
      final minE = elevs.reduce(math.min);
      final maxE = math.max(minE + 1.0, elevs.reduce(math.max));
      final fillPath = Path()..moveTo(0, size.height);
      final dx = size.width / (points.length - 1);
      for (int i = 0; i < points.length; i++) {
        final e = points[i].elevationM ?? minE;
        final y = size.height - ((e - minE) / (maxE - minE)) * (size.height * 0.85);
        fillPath.lineTo(i * dx, y);
      }
      fillPath.lineTo(size.width, size.height);
      fillPath.close();
      canvas.drawPath(fillPath, Paint()..color = AppColors.outline.withOpacity(0.14));
    }

    final hrs = points.map((p) => p.heartRate).whereType<int>().toList();
    if (hrs.length >= 2) {
      final minH = hrs.reduce(math.min).toDouble() - 5;
      final maxH = math.max(minH + 10.0, hrs.reduce(math.max).toDouble() + 5);
      final linePath = Path();
      final dx = size.width / (points.length - 1);
      bool started = false;
      for (int i = 0; i < points.length; i++) {
        final hr = points[i].heartRate;
        if (hr == null) continue;
        final y = size.height - ((hr - minH) / (maxH - minH)) * (size.height * 0.85);
        if (!started) {
          linePath.moveTo(i * dx, y);
          started = true;
        } else {
          linePath.lineTo(i * dx, y);
        }
      }
      canvas.drawPath(
        linePath,
        Paint()
          ..color = color.withOpacity(0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FeedMiniStreamPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.color != color;
}
