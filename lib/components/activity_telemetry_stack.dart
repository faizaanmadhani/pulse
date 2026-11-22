import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../models/activity.dart';
import '../services/garmin_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import 'macos_ui.dart';

/// Synchronized intervals.icu-style vertical stack of interactive telemetry charts.
/// Hovering or dragging on any chart updates [onHoverIndexChanged] so all charts
/// and the linked [MacosHeatmapView] scrub together in lockstep.
class ActivityTelemetryStack extends StatelessWidget {
  final Activity activity;
  final int? hoveredIndex;
  final ValueChanged<int?> onHoverIndexChanged;
  final bool isImperial;

  const ActivityTelemetryStack({
    super.key,
    required this.activity,
    required this.hoveredIndex,
    required this.onHoverIndexChanged,
    this.isImperial = false,
  });

  static const double _leftAxisPad = 56.0;
  static const double _rightPad = 14.0;
  static const double _topPad = 6.0;
  static const double _bottomPad = 6.0;

  static bool hasStreams(Activity activity) {
    final pts = activity.routePoints;
    if (pts.length < 2) return false;
    bool hasAtLeastTwo(bool Function(GpsPoint p) pred) {
      int count = 0;
      for (final p in pts) {
        if (pred(p)) {
          count++;
          if (count >= 2) return true;
        }
      }
      return false;
    }

    return hasAtLeastTwo((p) => p.speedMps != null && p.speedMps!.isFinite && p.speedMps! > 0.2) ||
        hasAtLeastTwo((p) => p.heartRate != null && p.heartRate! > 20) ||
        hasAtLeastTwo((p) => p.elevationM != null && p.elevationM!.isFinite) ||
        hasAtLeastTwo((p) => p.cadence != null && p.cadence! > 0) ||
        hasAtLeastTwo((p) => p.powerW != null && p.powerW! > 0) ||
        hasAtLeastTwo((p) => p.verticalOscillationCm != null && p.verticalOscillationCm!.isFinite && p.verticalOscillationCm! > 0) ||
        hasAtLeastTwo((p) => p.groundContactTimeMs != null && p.groundContactTimeMs! > 0);
  }

  bool get _isBike =>
      activity.discipline == SportDiscipline.bike ||
      activity.discipline == SportDiscipline.indoorBike;

  bool get _isSwim => activity.discipline == SportDiscipline.swim;

  List<double> _computeXFractions(List<GpsPoint> pts) {
    final n = pts.length;
    if (n <= 1) return [0.0];

    double maxDist = 0.0;
    int validDistCount = 0;
    for (final pt in pts) {
      if (pt.distanceM != null && pt.distanceM!.isFinite && pt.distanceM! >= 0) {
        validDistCount++;
        if (pt.distanceM! > maxDist) maxDist = pt.distanceM!;
      }
    }

    if (validDistCount >= 2 && maxDist > 1.0) {
      final result = List<double>.filled(n, 0.0);
      double lastGood = 0.0;
      for (int i = 0; i < n; i++) {
        final d = pts[i].distanceM;
        if (d != null && d.isFinite && d >= 0) {
          lastGood = math.max(lastGood, d);
        }
        result[i] = (lastGood / maxDist).clamp(0.0, 1.0);
      }
      return result;
    }

    return List<double>.generate(n, (i) => i / (n - 1));
  }

  double _totalDistanceMeters(List<GpsPoint> pts) {
    double maxDist = 0.0;
    for (final pt in pts) {
      if (pt.distanceM != null && pt.distanceM!.isFinite && pt.distanceM! > maxDist) {
        maxDist = pt.distanceM!;
      }
    }
    if (maxDist > 1.0) return maxDist;
    return activity.distanceKm * 1000.0;
  }

  double _distanceAtIndex(List<GpsPoint> pts, List<double> xFractions, int index) {
    final pt = pts[index];
    if (pt.distanceM != null && pt.distanceM!.isFinite && pt.distanceM! >= 0) {
      return pt.distanceM!;
    }
    return xFractions[index] * _totalDistanceMeters(pts);
  }

  String _formatDistanceMeters(double meters, {int decimals = 2}) {
    if (_isSwim) {
      if (isImperial) {
        return '${(meters * 1.09361).round()} yd';
      }
      return '${meters.round()} m';
    }
    if (isImperial) {
      final miles = (meters / 1000.0) * 0.621371;
      return '${miles.toStringAsFixed(decimals)} mi';
    }
    final km = meters / 1000.0;
    return '${km.toStringAsFixed(decimals)} km';
  }

  String _formatPaceOrSpeed(double speedMps) {
    if (speedMps <= 0.05) return '—';
    if (!isImperial) {
      return GarminService.formatMetricForDiscipline(activity.discipline, speedMps);
    }
    if (_isBike) {
      final mph = speedMps * 2.23693629;
      return '${mph.toStringAsFixed(1)} mph';
    }
    if (_isSwim) {
      final secPer100yd = (91.44 / speedMps).round();
      final min = secPer100yd ~/ 60;
      final sec = secPer100yd % 60;
      return '$min:${sec.toString().padLeft(2, '0')} /100yd';
    }
    final secPerMi = (1609.344 / speedMps).round();
    final min = secPerMi ~/ 60;
    final sec = secPerMi % 60;
    return '$min:${sec.toString().padLeft(2, '0')} /mi';
  }

  String _formatCompactPaceOrSpeed(double speedMps) {
    if (speedMps <= 0.05) return '—';
    if (_isBike) {
      final val = isImperial ? speedMps * 2.23693629 : speedMps * 3.6;
      return val.toStringAsFixed(1);
    }
    if (_isSwim) {
      final sec = ((isImperial ? 91.44 : 100.0) / speedMps).round();
      return '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}';
    }
    final sec = ((isImperial ? 1609.344 : 1000.0) / speedMps).round();
    return '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}';
  }

  List<_TelemetryStreamSpec> _buildStreams(List<GpsPoint> pts) {
    final specs = <_TelemetryStreamSpec>[];

    // 1. Pace / Speed
    final speedValues = pts
        .map((p) => (p.speedMps != null && p.speedMps!.isFinite && p.speedMps! > 0.2)
            ? p.speedMps
            : null)
        .toList();
    if (_validCount(speedValues) >= 2) {
      final speedRange = _percentileRange(speedValues, lowPct: 0.02, highPct: 0.98);
      specs.add(
        _TelemetryStreamSpec(
          title: _isBike ? 'Speed' : 'Pace',
          unitLabel: _isBike
              ? (isImperial ? 'mph' : 'km/h')
              : _isSwim
                  ? (isImperial ? '/100yd' : '/100m')
                  : (isImperial ? '/mi' : '/km'),
          color: _isBike
              ? AppColors.bikeSecondary
              : _isSwim
                  ? AppColors.swimPrimary
                  : AppColors.accent,
          values: speedValues,
          minVal: speedRange.min,
          maxVal: speedRange.max,
          formatValue: _formatPaceOrSpeed,
          formatAxisTick: _formatCompactPaceOrSpeed,
          fillOpacity: 0.14,
          height: 76,
        ),
      );
    }

    // 2. Elevation (filled area profile)
    final elevValues = pts
        .map((p) => (p.elevationM != null && p.elevationM!.isFinite)
            ? (isImperial ? p.elevationM! * 3.28084 : p.elevationM!)
            : null)
        .toList();
    if (_validCount(elevValues) >= 2) {
      final range = _minMaxRange(elevValues, minSpan: isImperial ? 20.0 : 6.0);
      final unit = isImperial ? 'ft' : 'm';
      specs.add(
        _TelemetryStreamSpec(
          title: 'Elevation',
          unitLabel: unit,
          color: AppColors.isDark ? const Color(0xFF98989D) : const Color(0xFF636366),
          values: elevValues,
          minVal: range.min,
          maxVal: range.max,
          formatValue: (v) => '${v.round()} $unit',
          formatAxisTick: (v) => '${v.round()}',
          fillOpacity: 0.28,
          height: 72,
        ),
      );
    }

    // 3. Heart Rate
    final hrValues = pts
        .map((p) => (p.heartRate != null && p.heartRate! > 20)
            ? p.heartRate!.toDouble()
            : null)
        .toList();
    if (_validCount(hrValues) >= 2) {
      final range = _minMaxRange(hrValues, minSpan: 10.0);
      specs.add(
        _TelemetryStreamSpec(
          title: 'Heart Rate',
          unitLabel: 'bpm',
          color: AppColors.error,
          values: hrValues,
          minVal: range.min,
          maxVal: range.max,
          formatValue: (v) => '${v.round()} bpm',
          formatAxisTick: (v) => '${v.round()}',
          fillOpacity: 0.14,
          height: 72,
        ),
      );
    }

    // 4. Cadence
    final cadValues = pts
        .map((p) => (p.cadence != null && p.cadence! > 0) ? p.cadence!.toDouble() : null)
        .toList();
    if (_validCount(cadValues) >= 2) {
      final range = _percentileRange(cadValues, lowPct: 0.02, highPct: 0.98, minSpan: 10.0);
      final unit = _isBike ? 'rpm' : 'spm';
      specs.add(
        _TelemetryStreamSpec(
          title: 'Cadence',
          unitLabel: unit,
          color: AppColors.runTertiary,
          values: cadValues,
          minVal: range.min,
          maxVal: range.max,
          formatValue: (v) => '${v.round()} $unit',
          formatAxisTick: (v) => '${v.round()}',
          fillOpacity: 0.12,
          height: 64,
        ),
      );
    }

    // 5. Power (shown when present)
    final pwrValues = pts
        .map((p) => (p.powerW != null && p.powerW! > 0) ? p.powerW!.toDouble() : null)
        .toList();
    if (_validCount(pwrValues) >= 2) {
      final range = _percentileRange(pwrValues, lowPct: 0.01, highPct: 0.99, minSpan: 20.0);
      specs.add(
        _TelemetryStreamSpec(
          title: 'Power',
          unitLabel: 'W',
          color: AppColors.strengthViolet,
          values: pwrValues,
          minVal: range.min,
          maxVal: range.max,
          formatValue: (v) => '${v.round()} W',
          formatAxisTick: (v) => '${v.round()}',
          fillOpacity: 0.14,
          height: 68,
        ),
      );
    }

    // 6. Vertical Oscillation (shown when present)
    final voValues = pts
        .map((p) => (p.verticalOscillationCm != null &&
                p.verticalOscillationCm!.isFinite &&
                p.verticalOscillationCm! > 0)
            ? p.verticalOscillationCm!
            : null)
        .toList();
    if (_validCount(voValues) >= 2) {
      final range = _minMaxRange(voValues, minSpan: 1.0);
      specs.add(
        _TelemetryStreamSpec(
          title: 'Vertical Oscillation',
          unitLabel: 'cm',
          color: const Color(0xFF32ADE6),
          values: voValues,
          minVal: range.min,
          maxVal: range.max,
          formatValue: (v) => '${v.toStringAsFixed(1)} cm',
          formatAxisTick: (v) => v.toStringAsFixed(1),
          fillOpacity: 0.12,
          height: 62,
        ),
      );
    }

    // 7. Ground Contact Time (shown when present)
    final gctValues = pts
        .map((p) => (p.groundContactTimeMs != null && p.groundContactTimeMs! > 0)
            ? p.groundContactTimeMs!.toDouble()
            : null)
        .toList();
    if (_validCount(gctValues) >= 2) {
      final range = _minMaxRange(gctValues, minSpan: 15.0);
      specs.add(
        _TelemetryStreamSpec(
          title: 'Ground Contact Time',
          unitLabel: 'ms',
          color: AppColors.warningGold,
          values: gctValues,
          minVal: range.min,
          maxVal: range.max,
          formatValue: (v) => '${v.round()} ms',
          formatAxisTick: (v) => '${v.round()}',
          fillOpacity: 0.12,
          height: 62,
        ),
      );
    }

    return specs;
  }

  int _validCount(List<double?> vals) {
    int count = 0;
    for (final v in vals) {
      if (v != null && v.isFinite) count++;
    }
    return count;
  }

  ({double min, double max}) _minMaxRange(List<double?> vals, {double minSpan = 1.0}) {
    double lo = double.infinity;
    double hi = -double.infinity;
    for (final v in vals) {
      if (v == null || !v.isFinite) continue;
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    if (lo == double.infinity) return (min: 0, max: minSpan);
    if ((hi - lo) < minSpan) {
      final mid = (lo + hi) / 2;
      lo = mid - minSpan / 2;
      hi = mid + minSpan / 2;
    } else {
      final pad = (hi - lo) * 0.08;
      lo -= pad;
      hi += pad;
    }
    return (min: lo, max: hi);
  }

  ({double min, double max}) _percentileRange(
    List<double?> vals, {
    double lowPct = 0.02,
    double highPct = 0.98,
    double minSpan = 0.5,
  }) {
    final valid = <double>[];
    for (final v in vals) {
      if (v != null && v.isFinite) valid.add(v);
    }
    if (valid.length < 2) return (min: 0, max: minSpan);
    valid.sort();
    double lo = valid[(valid.length * lowPct).floor().clamp(0, valid.length - 1)];
    double hi = valid[(valid.length * highPct).floor().clamp(0, valid.length - 1)];
    if ((hi - lo) < minSpan) {
      final mid = (lo + hi) / 2;
      lo = math.max(0.0, mid - minSpan / 2);
      hi = mid + minSpan / 2;
    } else {
      final pad = (hi - lo) * 0.08;
      lo = math.max(0.0, lo - pad);
      hi += pad;
    }
    return (min: lo, max: hi);
  }

  int _indexForLocalDx(double dx, double width, List<double> xFractions) {
    final plotW = math.max(1.0, width - _leftAxisPad - _rightPad);
    final frac = ((dx - _leftAxisPad) / plotW).clamp(0.0, 1.0);

    // Binary search nearest point in monotonic xFractions
    int lo = 0;
    int hi = xFractions.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (xFractions[mid] < frac) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    if (lo > 0 && (xFractions[lo] - frac).abs() > (xFractions[lo - 1] - frac).abs()) {
      return lo - 1;
    }
    return lo;
  }

  @override
  Widget build(BuildContext context) {
    final pts = activity.routePoints;
    if (pts.length < 2) return const SizedBox.shrink();

    final streams = _buildStreams(pts);
    if (streams.isEmpty) return const SizedBox.shrink();

    final xFractions = _computeXFractions(pts);
    final totalDistM = _totalDistanceMeters(pts);
    final validIdx = (hoveredIndex != null && hoveredIndex! >= 0 && hoveredIndex! < pts.length)
        ? hoveredIndex!
        : null;

    final cursorDistText = validIdx != null
        ? _formatDistanceMeters(_distanceAtIndex(pts, xFractions, validIdx))
        : null;
    final cursorTimeText = (validIdx != null && pts[validIdx].timeSec != null)
        ? GarminService.formatDurationSeconds(pts[validIdx].timeSec!)
        : null;

    return MacCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Header Toolbar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 6,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      CupertinoIcons.waveform_path_ecg,
                      size: 16,
                      color: AppColors.accent,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Synchronized Telemetry',
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: AppTypography.headlineMd,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${streams.length} streams',
                      style: AppTypography.bodySm.copyWith(color: AppColors.outline),
                    ),
                  ],
                ),
                if (cursorDistText != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.accent.withOpacity(0.28)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(CupertinoIcons.location_fill, size: 11, color: AppColors.accent),
                        const SizedBox(width: 5),
                        Text(
                          cursorTimeText != null
                              ? '$cursorDistText  •  $cursorTimeText'
                              : cursorDistText,
                          style: AppTypography.telemetrySm.copyWith(
                            color: AppColors.accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Text(
                    'Hover or drag any chart to scrub route & metrics',
                    style: AppTypography.bodySm.copyWith(
                      fontSize: 11,
                      color: AppColors.outline,
                    ),
                  ),
              ],
            ),
          ),

          Divider(height: 1, color: AppColors.borderDivider),

          // Synchronized Vertical Stack of Charts
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int i = 0; i < streams.length; i++) ...[
                  if (i > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Divider(height: 1, color: AppColors.borderDivider),
                    ),
                  _buildStreamRow(
                    stream: streams[i],
                    xFractions: xFractions,
                    validHoverIdx: validIdx,
                    cursorDistText: cursorDistText,
                  ),
                ],
                const SizedBox(height: 6),
                _buildSharedDistanceAxis(totalDistM),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStreamRow({
    required _TelemetryStreamSpec stream,
    required List<double> xFractions,
    required int? validHoverIdx,
    required String? cursorDistText,
  }) {
    final hoveredVal =
        (validHoverIdx != null && validHoverIdx < stream.values.length)
            ? stream.values[validHoverIdx]
            : null;
    final avgVal = stream.averageValue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Stream Header with Live Value at Cursor
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 4),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: stream.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        stream.title,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: AppTypography.bodySm.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '(${stream.unitLabel})',
                      style: AppTypography.bodySm.copyWith(
                        fontSize: 10,
                        color: AppColors.outline,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (hoveredVal != null) ...[
                Text(
                  stream.formatValue(hoveredVal),
                  style: AppTypography.telemetrySm.copyWith(
                    fontWeight: FontWeight.w700,
                    color: stream.color,
                    fontSize: 12,
                  ),
                ),
                if (cursorDistText != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    '@ $cursorDistText',
                    style: AppTypography.telemetrySm.copyWith(
                      fontSize: 10,
                      color: AppColors.outline,
                    ),
                  ),
                ],
              ] else if (avgVal != null)
                Text(
                  'Avg ${stream.formatValue(avgVal)}',
                  style: AppTypography.telemetrySm.copyWith(
                    fontSize: 11,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),

        // Interactive Chart Canvas
        SizedBox(
          height: stream.height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              return MouseRegion(
                cursor: SystemMouseCursors.precise,
                onHover: (event) {
                  final idx = _indexForLocalDx(event.localPosition.dx, width, xFractions);
                  if (idx != hoveredIndex) {
                    onHoverIndexChanged(idx);
                  }
                },
                onExit: (_) {
                  if (hoveredIndex != null) {
                    onHoverIndexChanged(null);
                  }
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) {
                    final idx = _indexForLocalDx(details.localPosition.dx, width, xFractions);
                    onHoverIndexChanged(idx);
                  },
                  onHorizontalDragUpdate: (details) {
                    final idx = _indexForLocalDx(details.localPosition.dx, width, xFractions);
                    if (idx != hoveredIndex) {
                      onHoverIndexChanged(idx);
                    }
                  },
                  child: CustomPaint(
                    size: Size(width, stream.height),
                    painter: _TelemetryStreamPainter(
                      stream: stream,
                      xFractions: xFractions,
                      hoveredIndex: validHoverIdx,
                      isDark: AppColors.isDark,
                      gridColor: AppColors.borderDivider,
                      axisTextColor: AppColors.outline,
                      crosshairColor: AppColors.onSurfaceVariant,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSharedDistanceAxis(double totalDistM) {
    const tickCount = 5;
    final ticks = List<String>.generate(tickCount, (i) {
      final frac = i / (tickCount - 1);
      final d = totalDistM * frac;
      return _formatDistanceMeters(d, decimals: 1);
    });

    return Padding(
      padding: const EdgeInsets.only(left: _leftAxisPad, right: _rightPad),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (final label in ticks)
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: AppTypography.telemetrySm.copyWith(
                  fontSize: 10,
                  color: AppColors.outline,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TelemetryStreamSpec {
  final String title;
  final String unitLabel;
  final Color color;
  final List<double?> values;
  final double minVal;
  final double maxVal;
  final String Function(double) formatValue;
  final String Function(double) formatAxisTick;
  final double fillOpacity;
  final double height;

  const _TelemetryStreamSpec({
    required this.title,
    required this.unitLabel,
    required this.color,
    required this.values,
    required this.minVal,
    required this.maxVal,
    required this.formatValue,
    required this.formatAxisTick,
    required this.fillOpacity,
    required this.height,
  });

  double? get averageValue {
    double sum = 0;
    int count = 0;
    for (final v in values) {
      if (v != null && v.isFinite) {
        sum += v;
        count++;
      }
    }
    return count > 0 ? sum / count : null;
  }
}

class _TelemetryStreamPainter extends CustomPainter {
  final _TelemetryStreamSpec stream;
  final List<double> xFractions;
  final int? hoveredIndex;
  final bool isDark;
  final Color gridColor;
  final Color axisTextColor;
  final Color crosshairColor;

  _TelemetryStreamPainter({
    required this.stream,
    required this.xFractions,
    required this.hoveredIndex,
    required this.isDark,
    required this.gridColor,
    required this.axisTextColor,
    required this.crosshairColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const leftPad = ActivityTelemetryStack._leftAxisPad;
    const rightPad = ActivityTelemetryStack._rightPad;
    const topPad = ActivityTelemetryStack._topPad;
    const bottomPad = ActivityTelemetryStack._bottomPad;

    final plotW = math.max(1.0, size.width - leftPad - rightPad);
    final plotH = math.max(1.0, size.height - topPad - bottomPad);
    final span = math.max(1e-6, stream.maxVal - stream.minVal);

    double xForIndex(int i) => leftPad + xFractions[i] * plotW;
    double yForValue(double v) {
      final norm = ((v - stream.minVal) / span).clamp(0.0, 1.0);
      return topPad + plotH * (1.0 - norm);
    }

    // 1. Subtle horizontal gridlines (top, mid, bottom)
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1.0;

    for (final frac in const [0.0, 0.5, 1.0]) {
      final y = topPad + plotH * frac;
      canvas.drawLine(Offset(leftPad, y), Offset(leftPad + plotW, y), gridPaint);
    }

    // 2. Left Y-axis tick labels (max & min)
    _drawAxisLabel(
      canvas,
      stream.formatAxisTick(stream.maxVal),
      const Offset(leftPad - 6, topPad - 1),
      alignTop: true,
    );
    _drawAxisLabel(
      canvas,
      stream.formatAxisTick(stream.minVal),
      Offset(leftPad - 6, topPad + plotH + 1),
      alignTop: false,
    );

    // 3. Plot line & filled area (handling null gaps gracefully)
    final linePath = Path();
    final fillPath = Path();
    bool inSegment = false;
    double segStartX = leftPad;
    double lastX = leftPad;
    final baselineY = topPad + plotH;

    for (int i = 0; i < stream.values.length; i++) {
      final v = stream.values[i];
      if (v == null || !v.isFinite) {
        if (inSegment) {
          fillPath.lineTo(lastX, baselineY);
          fillPath.lineTo(segStartX, baselineY);
          fillPath.close();
          inSegment = false;
        }
        continue;
      }
      final x = xForIndex(i);
      final y = yForValue(v);
      if (!inSegment) {
        linePath.moveTo(x, y);
        fillPath.moveTo(x, baselineY);
        fillPath.lineTo(x, y);
        segStartX = x;
        inSegment = true;
      } else {
        linePath.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
      lastX = x;
    }

    if (inSegment) {
      fillPath.lineTo(lastX, baselineY);
      fillPath.lineTo(segStartX, baselineY);
      fillPath.close();
    }

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          stream.color.withOpacity(stream.fillOpacity),
          stream.color.withOpacity(0.02),
        ],
      ).createShader(Rect.fromLTWH(leftPad, topPad, plotW, plotH))
      ..style = PaintingStyle.fill;
    canvas.drawPath(fillPath, fillPaint);

    final linePaint = Paint()
      ..color = stream.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(linePath, linePaint);

    // 4. Synchronized Crosshair & Ringed Dot
    if (hoveredIndex != null &&
        hoveredIndex! >= 0 &&
        hoveredIndex! < xFractions.length) {
      final cx = xForIndex(hoveredIndex!);
      canvas.drawLine(
        Offset(cx, topPad),
        Offset(cx, baselineY),
        Paint()
          ..color = crosshairColor.withOpacity(0.55)
          ..strokeWidth = 1.0,
      );

      final hv = hoveredIndex! < stream.values.length
          ? stream.values[hoveredIndex!]
          : null;
      if (hv != null && hv.isFinite) {
        final cy = yForValue(hv);
        // Outer halo
        canvas.drawCircle(
          Offset(cx, cy),
          7.0,
          Paint()..color = stream.color.withOpacity(0.22),
        );
        // Ringed dot
        canvas.drawCircle(
          Offset(cx, cy),
          4.2,
          Paint()..color = stream.color,
        );
        canvas.drawCircle(
          Offset(cx, cy),
          4.2,
          Paint()
            ..color = isDark ? const Color(0xFF1C1C1E) : Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8,
        );
      }
    }
  }

  void _drawAxisLabel(
    Canvas canvas,
    String text,
    Offset rightAnchor, {
    required bool alignTop,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 9.5,
          color: axisTextColor,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: ActivityTelemetryStack._leftAxisPad - 8);

    final dy = alignTop ? rightAnchor.dy : rightAnchor.dy - tp.height;
    tp.paint(canvas, Offset(rightAnchor.dx - tp.width, dy));
  }

  @override
  bool shouldRepaint(covariant _TelemetryStreamPainter oldDelegate) {
    return oldDelegate.hoveredIndex != hoveredIndex ||
        oldDelegate.isDark != isDark ||
        oldDelegate.stream.values != stream.values ||
        oldDelegate.stream.minVal != stream.minVal ||
        oldDelegate.stream.maxVal != stream.maxVal;
  }
}
