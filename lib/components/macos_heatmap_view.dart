import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/activity.dart';
import '../services/garmin_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import 'macos_ui.dart';

/// Native macOS Apple Maps–styled GPS Activity Heatmap & Single-Activity Pace Heat Map.
/// Plots real Garmin Connect GPS polylines over interactive CartoDB map tiles via flutter_map,
/// with smart home-cluster centering, discipline filtering, and per-segment pace heat coloring.
class MacosHeatmapView extends StatefulWidget {
  final List<Activity> activities;
  final String activeFilter; // 'all', 'run', 'bike', 'swim'
  final ValueChanged<String>? onFilterChanged;
  final bool isSignedIn;
  final bool isLoadingRoutes;
  final double height;
  final String? titleOverride;
  final bool showFilterBar;
  final bool colorByPace;
  final bool isImperial;
  final int? highlightedPointIndex;
  final ValueChanged<int?>? onPointHovered;

  const MacosHeatmapView({
    super.key,
    required this.activities,
    this.activeFilter = 'all',
    this.onFilterChanged,
    this.isSignedIn = true,
    this.isLoadingRoutes = false,
    this.height = 360,
    this.titleOverride,
    this.showFilterBar = true,
    this.colorByPace = false,
    this.isImperial = false,
    this.highlightedPointIndex,
    this.onPointHovered,
  });

  @override
  State<MacosHeatmapView> createState() => _MacosHeatmapViewState();
}

class _MacosHeatmapViewState extends State<MacosHeatmapView> {
  static const LatLng _defaultCenter = LatLng(37.7749, -122.4194);
  static const double _defaultZoom = 11.0;
  static const double _minZoom = 2.0;
  static const double _maxZoom = 18.0;
  static const double _homeClusterRadiusDeg = 1.5;

  final MapController _mapController = MapController();
  bool _mapReady = false;
  bool _fitAllMode = false;
  int? _lastHoveredIdx;
  late bool _paceHeatActive;

  @override
  void initState() {
    super.initState();
    _paceHeatActive = widget.colorByPace;
  }

  @override
  void didUpdateWidget(covariant MacosHeatmapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.colorByPace != widget.colorByPace) {
      _paceHeatActive = widget.colorByPace;
    }

    final oldSig = _gpsSignature(oldWidget.activities, oldWidget.activeFilter);
    final newSig = _gpsSignature(widget.activities, widget.activeFilter);
    if (oldSig != newSig || oldWidget.colorByPace != widget.colorByPace) {
      _scheduleFitCurrentBounds();
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  String _gpsSignature(List<Activity> activities, String filter) {
    final filtered = _filterGpsActivities(activities, filter);
    final totalPts = filtered.fold<int>(0, (sum, a) => sum + a.routePoints.length);
    final ids = filtered.map((a) => a.id).join(',');
    return '$filter|$ids|$totalPts';
  }

  List<Activity> get _filteredGpsActivities =>
      _filterGpsActivities(widget.activities, widget.activeFilter);

  List<Activity> _filterGpsActivities(List<Activity> activities, String filter) {
    return activities.where((a) {
      final hasGps = _hasValidGps(a);
      if (!hasGps) return false;
      switch (filter) {
        case 'run':
          return a.discipline == SportDiscipline.run;
        case 'bike':
          return a.discipline == SportDiscipline.bike ||
              a.discipline == SportDiscipline.indoorBike;
        case 'swim':
          return a.discipline == SportDiscipline.swim;
        default:
          return true;
      }
    }).toList();
  }

  bool _isValidCoord(double lat, double lon) {
    if (lat.isNaN || lon.isNaN || !lat.isFinite || !lon.isFinite) return false;
    if (lat.abs() > 90.0 || lon.abs() > 180.0) return false;
    if (lat == 0.0 && lon == 0.0) return false;
    return true;
  }

  bool _hasValidGps(Activity a) {
    for (final pt in a.routePoints) {
      if (_isValidCoord(pt.lat, pt.lon)) return true;
    }
    return a.startLatitude != null &&
        a.startLongitude != null &&
        _isValidCoord(a.startLatitude!, a.startLongitude!);
  }

  LatLng? _representativePoint(Activity a) {
    for (final pt in a.routePoints) {
      if (_isValidCoord(pt.lat, pt.lon)) {
        return LatLng(pt.lat, pt.lon);
      }
    }
    if (a.startLatitude != null &&
        a.startLongitude != null &&
        _isValidCoord(a.startLatitude!, a.startLongitude!)) {
      return LatLng(a.startLatitude!, a.startLongitude!);
    }
    return null;
  }

  /// For multi-activity maps in Home Cluster mode, computes the median (lat, lon)
  /// across all GPS activities and selects those within ~1.5 degrees (~150km)
  /// so a single outlier trip doesn't zoom the dashboard out to the ocean.
  List<Activity> _selectBoundsActivities(List<Activity> gpsActivities) {
    if (widget.colorByPace || gpsActivities.length <= 1 || _fitAllMode) {
      return gpsActivities;
    }

    final reps = <({Activity activity, LatLng point})>[];
    for (final a in gpsActivities) {
      final rep = _representativePoint(a);
      if (rep != null) {
        reps.add((activity: a, point: rep));
      }
    }
    if (reps.length <= 1) return gpsActivities;

    final lats = reps.map((r) => r.point.latitude).toList()..sort();
    final lons = reps.map((r) => r.point.longitude).toList()..sort();
    final medianLat = lats[lats.length ~/ 2];
    final medianLon = lons[lons.length ~/ 2];

    final cluster = reps.where((r) {
      final dLat = r.point.latitude - medianLat;
      final dLon = r.point.longitude - medianLon;
      return math.sqrt(dLat * dLat + dLon * dLon) <= _homeClusterRadiusDeg;
    }).map((r) => r.activity).toList();

    return cluster.isNotEmpty ? cluster : gpsActivities;
  }

  LatLngBounds? _computeBounds(List<Activity> acts) {
    double minLat = double.infinity;
    double maxLat = -double.infinity;
    double minLon = double.infinity;
    double maxLon = -double.infinity;

    for (final a in acts) {
      bool addedFromRoute = false;
      for (final pt in a.routePoints) {
        if (!_isValidCoord(pt.lat, pt.lon)) continue;
        addedFromRoute = true;
        if (pt.lat < minLat) minLat = pt.lat;
        if (pt.lat > maxLat) maxLat = pt.lat;
        if (pt.lon < minLon) minLon = pt.lon;
        if (pt.lon > maxLon) maxLon = pt.lon;
      }
      if (!addedFromRoute &&
          a.startLatitude != null &&
          a.startLongitude != null &&
          _isValidCoord(a.startLatitude!, a.startLongitude!)) {
        final lat = a.startLatitude!;
        final lon = a.startLongitude!;
        if (lat < minLat) minLat = lat;
        if (lat > maxLat) maxLat = lat;
        if (lon < minLon) minLon = lon;
        if (lon > maxLon) maxLon = lon;
      }
    }

    if (minLat == double.infinity) return null;

    // Ensure non-degenerate bounds for single-point or ultra-short tracks
    if ((maxLat - minLat).abs() < 0.004) {
      final mid = (minLat + maxLat) / 2;
      minLat = (mid - 0.003).clamp(-85.0, 85.0);
      maxLat = (mid + 0.003).clamp(-85.0, 85.0);
    }
    if ((maxLon - minLon).abs() < 0.004) {
      final mid = (minLon + maxLon) / 2;
      minLon = (mid - 0.003).clamp(-180.0, 180.0);
      maxLon = (mid + 0.003).clamp(-180.0, 180.0);
    }

    return LatLngBounds(LatLng(minLat, minLon), LatLng(maxLat, maxLon));
  }

  CameraFit _cameraFitForBounds(LatLngBounds bounds) {
    return CameraFit.bounds(
      bounds: bounds,
      padding: const EdgeInsets.fromLTRB(40, 40, 40, 76),
      maxZoom: 16.5,
      minZoom: _minZoom,
    );
  }

  void _scheduleFitCurrentBounds() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_mapReady) return;
      _fitCurrentBounds();
    });
  }

  void _fitCurrentBounds() {
    if (!_mapReady || !mounted) return;
    final gpsActivities = _filteredGpsActivities;
    final targetActs = _selectBoundsActivities(gpsActivities);
    final bounds = _computeBounds(targetActs);
    if (bounds == null) return;
    try {
      _mapController.fitCamera(_cameraFitForBounds(bounds));
    } catch (_) {
      // Guard against transient layout states during widget rebuilds/tests
    }
  }

  void _zoomBy(double delta) {
    if (!_mapReady || !mounted) return;
    try {
      final camera = _mapController.camera;
      final nextZoom = (camera.zoom + delta).clamp(_minZoom, _maxZoom);
      _mapController.move(camera.center, nextZoom);
    } catch (_) {
      // Guard against uninitialized camera in headless tests
    }
  }

  void _toggleClusterMode() {
    setState(() => _fitAllMode = !_fitAllMode);
    _scheduleFitCurrentBounds();
  }

  void _handleMapHover(Offset localPosition, List<GpsPoint> routePoints) {
    if (!_mapReady || !mounted || widget.onPointHovered == null || routePoints.isEmpty) {
      return;
    }
    try {
      final camera = _mapController.camera;
      // Validate pointer maps to a valid coordinate on the map
      camera.pointToLatLng(math.Point<double>(localPosition.dx, localPosition.dy));

      const double hitThresholdPx = 30.0;
      const double hitThresholdSq = hitThresholdPx * hitThresholdPx;
      int? bestIdx;
      double bestDistSq = hitThresholdSq;

      for (int i = 0; i < routePoints.length; i++) {
        final pt = routePoints[i];
        if (!_isValidCoord(pt.lat, pt.lon)) continue;
        final screenPt = camera.latLngToScreenPoint(LatLng(pt.lat, pt.lon));
        final dx = screenPt.x - localPosition.dx;
        final dy = screenPt.y - localPosition.dy;
        final distSq = dx * dx + dy * dy;
        if (distSq < bestDistSq) {
          bestDistSq = distSq;
          bestIdx = i;
        }
      }

      if (bestIdx != _lastHoveredIdx) {
        _lastHoveredIdx = bestIdx;
        widget.onPointHovered?.call(bestIdx);
      }
    } catch (_) {
      // Guard against transient camera states during layout/tests
    }
  }

  void _clearMapHover() {
    if (_lastHoveredIdx != null) {
      _lastHoveredIdx = null;
      widget.onPointHovered?.call(null);
    }
  }

  ({double minSpeed, double maxSpeed})? _computeSpeedRange(List<Activity> acts) {
    final speeds = <double>[];
    for (final a in acts) {
      for (final pt in a.routePoints) {
        if (pt.speedMps != null && pt.speedMps! > 0.2) {
          speeds.add(pt.speedMps!);
        }
      }
    }
    if (speeds.length < 2) return null;
    speeds.sort();
    final lowIdx = (speeds.length * 0.05).floor().clamp(0, speeds.length - 1);
    final highIdx = (speeds.length * 0.95).floor().clamp(0, speeds.length - 1);
    final minS = speeds[lowIdx];
    final maxS = speeds[highIdx];
    if ((maxS - minS).abs() < 0.05) {
      return (minSpeed: math.max(0.1, minS - 0.5), maxSpeed: maxS + 0.5);
    }
    return (minSpeed: minS, maxSpeed: maxS);
  }

  Color _colorForDiscipline(SportDiscipline d) {
    return switch (d) {
      SportDiscipline.run => AppColors.runTertiary,
      SportDiscipline.bike || SportDiscipline.indoorBike => AppColors.bikeSecondary,
      SportDiscipline.swim => AppColors.swimPrimary,
      SportDiscipline.strength => AppColors.strengthViolet,
    };
  }

  /// Maps normalized speed [0.0..1.0] across an Apple-style pace heat gradient:
  /// Blue (Easy) -> Green (Aerobic) -> Orange (Tempo) -> Red (Fast/Surge).
  Color _paceHeatColor(double t) {
    final c = t.clamp(0.0, 1.0);
    const blue = Color(0xFF007AFF);
    const green = Color(0xFF34C759);
    const orange = Color(0xFFFF9500);
    const red = Color(0xFFFF3B30);
    if (c < 0.33) {
      return Color.lerp(blue, green, c / 0.33)!;
    } else if (c < 0.66) {
      return Color.lerp(green, orange, (c - 0.33) / 0.33)!;
    } else {
      return Color.lerp(orange, red, (c - 0.66) / 0.34)!;
    }
  }

  List<Polyline> _buildPolylines(
    List<Activity> gpsActivities,
    ({double minSpeed, double maxSpeed})? speedRange,
    bool isDark,
  ) {
    final glowLines = <Polyline>[];
    final coreLines = <Polyline>[];

    for (final act in gpsActivities) {
      final validPts = act.routePoints
          .where((pt) => _isValidCoord(pt.lat, pt.lon))
          .toList();
      if (validPts.length < 2) continue;

      if (_paceHeatActive && speedRange != null) {
        final minS = speedRange.minSpeed;
        final spanS = math.max(0.05, speedRange.maxSpeed - minS);

        for (int i = 0; i < validPts.length - 1; i++) {
          final p1 = validPts[i];
          final p2 = validPts[i + 1];
          final segSpeed = p2.speedMps ?? p1.speedMps ?? minS;
          final t = ((segSpeed - minS) / spanS).clamp(0.0, 1.0);
          final segColor = _paceHeatColor(t);
          final segCoords = [LatLng(p1.lat, p1.lon), LatLng(p2.lat, p2.lon)];

          glowLines.add(
            Polyline(
              points: segCoords,
              strokeWidth: 9.0,
              color: segColor.withOpacity(isDark ? 0.30 : 0.24),
              strokeCap: StrokeCap.round,
              strokeJoin: StrokeJoin.round,
            ),
          );
          coreLines.add(
            Polyline(
              points: segCoords,
              strokeWidth: 3.8,
              color: segColor,
              strokeCap: StrokeCap.round,
              strokeJoin: StrokeJoin.round,
            ),
          );
        }
      } else {
        final sportColor = _colorForDiscipline(act.discipline);
        final coords = validPts.map((pt) => LatLng(pt.lat, pt.lon)).toList();

        glowLines.add(
          Polyline(
            points: coords,
            strokeWidth: 7.0,
            color: sportColor.withOpacity(isDark ? 0.28 : 0.22),
            strokeCap: StrokeCap.round,
            strokeJoin: StrokeJoin.round,
          ),
        );
        coreLines.add(
          Polyline(
            points: coords,
            strokeWidth: 2.8,
            color: sportColor.withOpacity(0.92),
            strokeCap: StrokeCap.round,
            strokeJoin: StrokeJoin.round,
          ),
        );
      }
    }

    return [...glowLines, ...coreLines];
  }

  List<Marker> _buildMarkers(List<Activity> gpsActivities, bool isDark) {
    final markers = <Marker>[];
    final isSingleRoute = widget.colorByPace || gpsActivities.length == 1;

    for (final act in gpsActivities) {
      final validPts = act.routePoints
          .where((pt) => _isValidCoord(pt.lat, pt.lon))
          .toList();
      final sportColor = _colorForDiscipline(act.discipline);

      if (validPts.length >= 2) {
        final first = LatLng(validPts.first.lat, validPts.first.lon);
        final last = LatLng(validPts.last.lat, validPts.last.lon);

        if (isSingleRoute) {
          // Start (Green) & Finish (Red) pins
          markers.add(
            Marker(
              point: first,
              width: 18,
              height: 18,
              child: _routePinWidget(
                fill: const Color(0xFF34C759),
                isDark: isDark,
                size: 14,
              ),
            ),
          );
          markers.add(
            Marker(
              point: last,
              width: 18,
              height: 18,
              child: _routePinWidget(
                fill: const Color(0xFFFF3B30),
                isDark: isDark,
                size: 14,
              ),
            ),
          );
        }
      } else if (isSingleRoute &&
          act.startLatitude != null &&
          act.startLongitude != null &&
          _isValidCoord(act.startLatitude!, act.startLongitude!)) {
        // Fallback start-location marker ONLY for single-activity view before polyline loads
        markers.add(
          Marker(
            point: LatLng(act.startLatitude!, act.startLongitude!),
            width: 24,
            height: 24,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: sportColor.withOpacity(0.22),
                    shape: BoxShape.circle,
                  ),
                ),
                _routePinWidget(
                  fill: sportColor,
                  isDark: isDark,
                  size: 10,
                  borderWidth: 1.6,
                ),
              ],
            ),
          ),
        );
      }
    }

    // Prominent live Course Tracer Marker when scrubbing map or telemetry charts
    final highlightIdx = widget.highlightedPointIndex;
    if (highlightIdx != null && widget.activities.length == 1) {
      final pts = widget.activities.first.routePoints;
      if (highlightIdx >= 0 && highlightIdx < pts.length) {
        final pt = pts[highlightIdx];
        if (_isValidCoord(pt.lat, pt.lon)) {
          markers.add(
            Marker(
              point: LatLng(pt.lat, pt.lon),
              width: 28,
              height: 28,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: const Color(0xFF007AFF).withOpacity(0.26),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF007AFF).withOpacity(0.65),
                        width: 1.4,
                      ),
                    ),
                  ),
                  Container(
                    width: 13,
                    height: 13,
                    decoration: BoxDecoration(
                      color: const Color(0xFF007AFF),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white,
                        width: 2.4,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.35),
                          blurRadius: 5,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      }
    }

    return markers;
  }

  Widget _routePinWidget({
    required Color fill,
    required bool isDark,
    double size = 12,
    double borderWidth = 2.0,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          width: borderWidth,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.28),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
    );
  }

  String _formatDistance(double km, {required bool detailed}) {
    if (widget.isImperial) {
      final miles = km * 0.621371;
      return '${miles.toStringAsFixed(detailed ? 2 : 1)} mi';
    }
    return '${km.toStringAsFixed(detailed ? 2 : 1)} km';
  }

  String _formatElevation(double meters) {
    if (widget.isImperial) {
      final feet = (meters * 3.28084).round();
      return '$feet ft elev';
    }
    return '${meters.round()} m elev';
  }

  String _formatSpeedForLegend(SportDiscipline discipline, double speedMps) {
    if (!widget.isImperial) {
      return GarminService.formatMetricForDiscipline(discipline, speedMps);
    }
    if (speedMps <= 0.01) return '—';
    switch (discipline) {
      case SportDiscipline.bike:
      case SportDiscipline.indoorBike:
        final mph = speedMps * 2.23693629;
        return '${mph.toStringAsFixed(1)} mph';
      case SportDiscipline.swim:
        final secPer100yd = (91.44 / speedMps).round();
        final min = secPer100yd ~/ 60;
        final sec = secPer100yd % 60;
        return '$min:${sec.toString().padLeft(2, '0')} /100yd';
      case SportDiscipline.run:
        final secPerMi = (1609.344 / speedMps).round();
        final min = secPerMi ~/ 60;
        final sec = secPerMi % 60;
        return '$min:${sec.toString().padLeft(2, '0')} /mi';
      case SportDiscipline.strength:
        return '—';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark;
    final gpsActivities = _filteredGpsActivities;
    final polylineCount = gpsActivities.where((a) => a.routePoints.length >= 2).length;
    final totalKm = gpsActivities.fold<double>(0, (sum, a) => sum + a.distanceKm);
    final totalElevM = gpsActivities.fold<double>(0, (sum, a) => sum + a.elevationGainM);

    final boundsActivities = _selectBoundsActivities(gpsActivities);
    final activeBounds = _computeBounds(boundsActivities);
    final speedRange = _paceHeatActive ? _computeSpeedRange(gpsActivities) : null;
    final primaryDiscipline =
        gpsActivities.isNotEmpty ? gpsActivities.first.discipline : SportDiscipline.run;

    final polylines = _buildPolylines(gpsActivities, speedRange, isDark);
    final markers = _buildMarkers(gpsActivities, isDark);

    const tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

    final distText = _formatDistance(totalKm, detailed: widget.colorByPace);
    final elevText = totalElevM > 0 ? ' • ${_formatElevation(totalElevM)}' : '';

    return MacCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Toolbar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(CupertinoIcons.map_fill, size: 16, color: AppColors.accent),
                    const SizedBox(width: 8),
                    Text(
                      widget.titleOverride ?? 'Activity GPS Heatmap',
                      style: AppTypography.headlineMd,
                    ),
                    if (widget.isLoadingRoutes) ...[
                      const SizedBox(width: 10),
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CupertinoActivityIndicator(radius: 6),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Loading GPS tracks...',
                        style: AppTypography.bodySm.copyWith(fontSize: 11),
                      ),
                    ],
                  ],
                ),
                if (widget.colorByPace)
                  MacSegmentedControl<bool>(
                    items: const [true, false],
                    selected: _paceHeatActive,
                    labelBuilder: (isPace) => isPace ? 'Pace Heat' : 'Route Color',
                    onChanged: (val) => setState(() => _paceHeatActive = val),
                  )
                else if (widget.showFilterBar && widget.onFilterChanged != null)
                  MacSegmentedControl<String>(
                    items: const ['all', 'run', 'bike', 'swim'],
                    selected: widget.activeFilter,
                    labelBuilder: (val) => switch (val) {
                      'run' => 'Run',
                      'bike' => 'Bike',
                      'swim' => 'Swim',
                      _ => 'All Sports',
                    },
                    onChanged: widget.onFilterChanged!,
                  ),
              ],
            ),
          ),

          Divider(height: 1, color: AppColors.borderDivider),

          // Interactive FlutterMap Canvas
          SizedBox(
            height: widget.height,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10)),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      color: isDark
                          ? const Color(0xFF1A2029)
                          : const Color(0xFFEFF3F7),
                      child: MouseRegion(
                        onHover: widget.activities.length == 1 &&
                                widget.activities.first.routePoints.isNotEmpty &&
                                widget.onPointHovered != null
                            ? (event) => _handleMapHover(
                                  event.localPosition,
                                  widget.activities.first.routePoints,
                                )
                            : null,
                        onExit: widget.activities.length == 1 &&
                                widget.activities.first.routePoints.isNotEmpty &&
                                widget.onPointHovered != null
                            ? (_) => _clearMapHover()
                            : null,
                        child: FlutterMap(
                          mapController: _mapController,
                          options: MapOptions(
                            initialCenter: activeBounds?.center ?? _defaultCenter,
                            initialZoom: _defaultZoom,
                            initialCameraFit: activeBounds != null
                                ? _cameraFitForBounds(activeBounds)
                                : null,
                            minZoom: _minZoom,
                            maxZoom: _maxZoom,
                            backgroundColor: isDark
                                ? const Color(0xFF1A2029)
                                : const Color(0xFFEFF3F7),
                            interactionOptions: const InteractionOptions(
                              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                            ),
                            onMapReady: () {
                              _mapReady = true;
                              _scheduleFitCurrentBounds();
                            },
                          ),
                          children: [
                            TileLayer(
                              key: ValueKey(isDark ? 'osm-dark' : 'osm-light'),
                              urlTemplate: tileUrl,
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
                            if (polylines.isNotEmpty)
                              PolylineLayer(polylines: polylines),
                            if (markers.isNotEmpty)
                              MarkerLayer(markers: markers),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Empty / Sign-In Overlay when no GPS data yet
                  if (!widget.isSignedIn || gpsActivities.isEmpty)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainer.withOpacity(0.92),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.borderSubtle),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.cardShadow,
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              widget.isSignedIn
                                  ? CupertinoIcons.location_slash
                                  : CupertinoIcons.map,
                              size: 16,
                              color: AppColors.outline,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              !widget.isSignedIn
                                  ? 'Sign in with Garmin Connect to plot your real GPS routes'
                                  : widget.isLoadingRoutes
                                      ? 'Fetching GPS tracks from Garmin Connect...'
                                      : 'No GPS routes found for this sport filter',
                              style: AppTypography.bodyMd.copyWith(color: AppColors.onSurface),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Top-right macOS Floating Controls (Home Cluster / Fit All + Zoom)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!widget.colorByPace) ...[
                          _buildClusterToggleButton(),
                          const SizedBox(width: 8),
                        ],
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainer.withOpacity(0.94),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.borderSubtle),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.cardShadow,
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _mapControlBtn(CupertinoIcons.plus, () => _zoomBy(1.0)),
                              Container(width: 24, height: 1, color: AppColors.borderDivider),
                              _mapControlBtn(CupertinoIcons.minus, () => _zoomBy(-1.0)),
                              Container(width: 24, height: 1, color: AppColors.borderDivider),
                              _mapControlBtn(CupertinoIcons.location, _fitCurrentBounds),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Bottom Legend & Telemetry Summary Bar
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainer.withOpacity(0.92),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.borderSubtle),
                      ),
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 14,
                        runSpacing: 6,
                        children: [
                          if (_paceHeatActive)
                            _buildPaceLegend(primaryDiscipline, speedRange)
                          else
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _legendDot('Run', AppColors.runTertiary),
                                const SizedBox(width: 12),
                                _legendDot('Bike', AppColors.bikeSecondary),
                                const SizedBox(width: 12),
                                _legendDot('Swim', AppColors.swimPrimary),
                              ],
                            ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.colorByPace
                                    ? '$distText$elevText'
                                    : '${gpsActivities.length} GPS sessions'
                                        '${polylineCount > 0 ? ' ($polylineCount tracks)' : ''}'
                                        ' • $distText$elevText',
                                style: AppTypography.telemetrySm.copyWith(
                                  color: AppColors.onSurfaceVariant,
                                ),
                              ),
                              if (activeBounds != null) ...[
                                const SizedBox(width: 10),
                                Text(
                                  '${activeBounds.center.latitude.toStringAsFixed(3)}°, '
                                  '${activeBounds.center.longitude.toStringAsFixed(3)}°',
                                  style: AppTypography.telemetrySm.copyWith(
                                    color: AppColors.outline,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClusterToggleButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _toggleClusterMode,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainer.withOpacity(0.94),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.borderSubtle),
            boxShadow: [
              BoxShadow(
                color: AppColors.cardShadow,
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _fitAllMode ? CupertinoIcons.globe : CupertinoIcons.house_fill,
                size: 13,
                color: AppColors.accent,
              ),
              const SizedBox(width: 6),
              Text(
                _fitAllMode ? 'Fit All' : 'Home Cluster',
                style: AppTypography.bodySm.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPaceLegend(
    SportDiscipline discipline,
    ({double minSpeed, double maxSpeed})? range,
  ) {
    final slowLabel = range != null
        ? _formatSpeedForLegend(discipline, range.minSpeed)
        : 'Slower';
    final fastLabel = range != null
        ? _formatSpeedForLegend(discipline, range.maxSpeed)
        : 'Faster';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          slowLabel,
          style: AppTypography.telemetrySm.copyWith(
            fontSize: 10,
            color: AppColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          width: 96,
          height: 7,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            gradient: const LinearGradient(
              colors: [
                Color(0xFF007AFF), // Easy / Blue
                Color(0xFF34C759), // Aerobic / Green
                Color(0xFFFF9500), // Tempo / Orange
                Color(0xFFFF3B30), // Fast / Red
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          fastLabel,
          style: AppTypography.telemetrySm.copyWith(
            fontSize: 10,
            color: AppColors.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _mapControlBtn(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 30,
          height: 28,
          child: Icon(icon, size: 14, color: AppColors.onSurface),
        ),
      ),
    );
  }

  Widget _legendDot(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label, style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.w500)),
      ],
    );
  }
}
