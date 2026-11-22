import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../utils/physiological_metrics.dart';
import '../utils/unit_formatter.dart';
import 'macos_ui.dart';

enum _ZoneMode { hr, power }

/// Native macOS HIG card displaying Z1–Z5 Heart Rate and/or Power Time-in-Zone
/// breakdown with interactive hoverable horizontal bars and an optional
/// HR / Power segmented toggle.
class TimeInZoneCard extends StatefulWidget {
  final String title;
  final String? subtitle;
  final List<ZoneBucket> hrZones;
  final List<ZoneBucket> powerZones;
  final bool showToggle;

  const TimeInZoneCard({
    super.key,
    this.title = 'Time in Zones',
    this.subtitle,
    required this.hrZones,
    this.powerZones = const [],
    this.showToggle = true,
  });

  @override
  State<TimeInZoneCard> createState() => _TimeInZoneCardState();
}

class _TimeInZoneCardState extends State<TimeInZoneCard> {
  _ZoneMode _mode = _ZoneMode.hr;
  int? _hoveredZone;

  @override
  void initState() {
    super.initState();
    if (widget.hrZones.isEmpty && widget.powerZones.isNotEmpty) {
      _mode = _ZoneMode.power;
    }
  }

  @override
  void didUpdateWidget(covariant TimeInZoneCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_mode == _ZoneMode.power && widget.powerZones.isEmpty) {
      _mode = _ZoneMode.hr;
    } else if (_mode == _ZoneMode.hr &&
        widget.hrZones.isEmpty &&
        widget.powerZones.isNotEmpty) {
      _mode = _ZoneMode.power;
    }
  }

  bool get _canToggle =>
      widget.showToggle &&
      widget.hrZones.isNotEmpty &&
      widget.powerZones.isNotEmpty;

  List<ZoneBucket> get _activeZones {
    if (_mode == _ZoneMode.power && widget.powerZones.isNotEmpty) {
      return widget.powerZones;
    }
    if (widget.hrZones.isNotEmpty) {
      return widget.hrZones;
    }
    return widget.powerZones;
  }

  @override
  Widget build(BuildContext context) {
    final zones = _activeZones;
    final totalSeconds =
        zones.fold<double>(0.0, (sum, bucket) => sum + bucket.seconds);
    final isPowerMode = _mode == _ZoneMode.power && widget.powerZones.isNotEmpty;

    return MacCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header row
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isPowerMode
                        ? CupertinoIcons.bolt_fill
                        : CupertinoIcons.heart_fill,
                    size: 15,
                    color: isPowerMode
                        ? AppColors.bikeSecondary
                        : AppColors.error,
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.title, style: AppTypography.headlineMd),
                      if (widget.subtitle != null &&
                          widget.subtitle!.trim().isNotEmpty)
                        Text(widget.subtitle!, style: AppTypography.bodySm),
                    ],
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (totalSeconds > 0) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLow,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: AppColors.borderDivider),
                      ),
                      child: Text(
                        'Total ${formatZoneDuration(totalSeconds)}',
                        style: AppTypography.telemetrySm.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                  if (_canToggle) ...[
                    if (totalSeconds > 0) const SizedBox(width: 10),
                    MacSegmentedControl<_ZoneMode>(
                      items: const [_ZoneMode.hr, _ZoneMode.power],
                      selected: _mode,
                      labelBuilder: (m) =>
                          m == _ZoneMode.hr ? 'Heart Rate' : 'Power',
                      dotColorBuilder: (m) => m == _ZoneMode.hr
                          ? AppColors.error
                          : AppColors.bikeSecondary,
                      onChanged: (next) {
                        setState(() {
                          _mode = next;
                          _hoveredZone = null;
                        });
                      },
                    ),
                  ],
                ],
              ),
            ],
          ),

          const SizedBox(height: 14),

          if (zones.isEmpty || totalSeconds <= 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'No heart rate or power zone telemetry available.',
                style: AppTypography.bodyMd,
                textAlign: TextAlign.center,
              ),
            )
          else ...[
            // Compact stacked distribution summary bar
            _StackedZoneBar(
              zones: zones,
              hoveredZone: _hoveredZone,
            ),
            const SizedBox(height: 12),

            // Interactive hoverable Z1–Z5 horizontal bars
            ...zones.map(
              (bucket) => _ZoneBarRow(
                bucket: bucket,
                isHovered: _hoveredZone == bucket.zone,
                hasAnyHover: _hoveredZone != null,
                onHoverChanged: (hovering) {
                  setState(() {
                    _hoveredZone = hovering ? bucket.zone : null;
                  });
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StackedZoneBar extends StatelessWidget {
  final List<ZoneBucket> zones;
  final int? hoveredZone;

  const _StackedZoneBar({
    required this.zones,
    required this.hoveredZone,
  });

  @override
  Widget build(BuildContext context) {
    final active = zones.where((z) => z.percentage > 0).toList();
    if (active.isEmpty) return const SizedBox.shrink();

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 7,
        child: Row(
          children: active.map((bucket) {
            final flex = (bucket.percentage * 10).round().clamp(1, 1000);
            final dimmed = hoveredZone != null && hoveredZone != bucket.zone;
            return Expanded(
              flex: flex,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                margin: const EdgeInsets.only(right: 1),
                color: bucket.color.withOpacity(dimmed ? 0.25 : 0.92),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _ZoneBarRow extends StatelessWidget {
  final ZoneBucket bucket;
  final bool isHovered;
  final bool hasAnyHover;
  final ValueChanged<bool> onHoverChanged;

  const _ZoneBarRow({
    required this.bucket,
    required this.isHovered,
    required this.hasAnyHover,
    required this.onHoverChanged,
  });

  @override
  Widget build(BuildContext context) {
    final fraction = (bucket.percentage / 100.0).clamp(0.0, 1.0);
    final dimmed = hasAnyHover && !isHovered;

    return MouseRegion(
      onEnter: (_) => onHoverChanged(true),
      onExit: (_) => onHoverChanged(false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        margin: const EdgeInsets.only(bottom: 3),
        decoration: BoxDecoration(
          color: isHovered
              ? bucket.color.withOpacity(AppColors.isDark ? 0.14 : 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          children: [
            // Zone pill
            Container(
              width: 28,
              padding: const EdgeInsets.symmetric(vertical: 2),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: bucket.color.withOpacity(AppColors.isDark ? 0.24 : 0.14),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                'Z${bucket.zone}',
                style: AppTypography.telemetrySm.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: bucket.color,
                ),
              ),
            ),
            const SizedBox(width: 10),

            // Label & range
            SizedBox(
              width: 126,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    bucket.label,
                    style: AppTypography.headlineSm.copyWith(
                      fontSize: 12,
                      fontWeight: isHovered ? FontWeight.w600 : FontWeight.w500,
                      color: dimmed
                          ? AppColors.onSurfaceVariant
                          : AppColors.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    bucket.rangeText,
                    style: AppTypography.telemetrySm.copyWith(
                      fontSize: 10.5,
                      color: AppColors.outline,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),

            // Horizontal bar
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final maxW = constraints.maxWidth;
                  final barW = bucket.seconds > 0
                      ? (maxW * fraction).clamp(3.0, maxW)
                      : 0.0;
                  return Container(
                    height: isHovered ? 10 : 8,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLow,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    alignment: Alignment.centerLeft,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      width: barW,
                      height: isHovered ? 10 : 8,
                      decoration: BoxDecoration(
                        color: bucket.color.withOpacity(dimmed ? 0.45 : 0.92),
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),

            // Duration
            SizedBox(
              width: 64,
              child: Text(
                formatZoneDuration(bucket.seconds),
                textAlign: TextAlign.right,
                style: AppTypography.telemetrySm.copyWith(
                  fontSize: 12,
                  fontWeight: isHovered ? FontWeight.w600 : FontWeight.w500,
                  color: bucket.seconds > 0
                      ? AppColors.onSurface
                      : AppColors.outline,
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Percentage
            SizedBox(
              width: 44,
              child: Text(
                UnitFormatter.formatPercent(bucket.percentage),
                textAlign: TextAlign.right,
                style: AppTypography.telemetrySm.copyWith(
                  fontSize: 11.5,
                  fontWeight: isHovered ? FontWeight.w600 : FontWeight.w500,
                  color: isHovered ? bucket.color : AppColors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Native macOS HIG card presenting Cardiac Drift / Aerobic Decoupling
/// (`Pa:Hr` / `Pw:Hr` / `Spd:Hr`), semantic status badge, and 1st Half vs
/// 2nd Half comparison metrics.
class CardiacDriftCard extends StatelessWidget {
  final CardiacDriftResult result;
  final String title;

  const CardiacDriftCard({
    super.key,
    required this.result,
    this.title = 'Cardiac Drift & Decoupling',
  });

  Color get _statusColor {
    if (result.decouplingPercent < 5.0 - 1e-9) return AppColors.runTertiary;
    if (result.decouplingPercent <= 10.0 + 1e-9) return AppColors.bikeSecondary;
    return AppColors.error;
  }

  IconData get _statusIcon {
    if (result.decouplingPercent < 5.0 - 1e-9) {
      return CupertinoIcons.checkmark_circle_fill;
    }
    if (result.decouplingPercent <= 10.0 + 1e-9) {
      return CupertinoIcons.exclamationmark_triangle_fill;
    }
    return CupertinoIcons.flame_fill;
  }

  String get _interpretation {
    if (result.decouplingPercent < 5.0 - 1e-9) {
      return 'Strong aerobic durability — minimal cardiovascular drift across the session.';
    }
    if (result.decouplingPercent <= 10.0 + 1e-9) {
      return 'Moderate aerobic drift — steady endurance base is still developing at this duration.';
    }
    return 'Elevated cardiac drift — consider additional Zone 2 volume, pacing control, or hydration.';
  }

  String get _formattedDecoupling {
    final val = result.decouplingPercent;
    final sign = val >= 0 ? '+' : '';
    return '$sign${val.toStringAsFixed(1)}%';
  }

  String get _outputColumnLabel {
    if (result.metricLabel == 'Pw:Hr') return 'Avg Power';
    if (result.metricLabel == 'Pa:Hr') return 'Avg Pace';
    return 'Avg Speed';
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor;
    final hrDelta = result.secondHalfAvgHr - result.firstHalfAvgHr;
    final hrDeltaSign = hrDelta >= 0 ? '+' : '';
    final hrDeltaText = '$hrDeltaSign${hrDelta.round()} bpm';

    return MacCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
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
                    CupertinoIcons.waveform_path_ecg,
                    size: 16,
                    color: statusColor,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      title,
                      style: AppTypography.headlineMd,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLow,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppColors.borderDivider),
                    ),
                    child: Text(
                      result.metricLabel,
                      style: AppTypography.telemetrySm.copyWith(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              MacStatusBadge(
                label: result.statusLabel,
                color: statusColor,
                icon: _statusIcon,
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Hero Decoupling Value + Interpretation
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                _formattedDecoupling,
                style: AppTypography.telemetryHero.copyWith(
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Aerobic Decoupling',
                style: AppTypography.bodySm.copyWith(
                  fontWeight: FontWeight.w500,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _interpretation,
            style: AppTypography.bodySm.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),

          const SizedBox(height: 14),

          // 1st Half vs 2nd Half Comparison
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceLow,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.borderDivider),
            ),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  Expanded(
                    child: _HalfMetricsColumn(
                      heading: '1st Half',
                      avgHr: '${result.firstHalfAvgHr.round()} bpm',
                      outputLabel: _outputColumnLabel,
                      outputValue: result.firstHalfOutput,
                      efficiencyFactor: result.firstHalfEf.toStringAsFixed(2),
                    ),
                  ),
                  Container(
                    width: 1,
                    margin: const EdgeInsets.symmetric(horizontal: 14),
                    color: AppColors.borderSubtle,
                  ),
                  Expanded(
                    child: _HalfMetricsColumn(
                      heading: '2nd Half',
                      trailingPill: hrDeltaText,
                      trailingPillColor: statusColor,
                      avgHr: '${result.secondHalfAvgHr.round()} bpm',
                      outputLabel: _outputColumnLabel,
                      outputValue: result.secondHalfOutput,
                      efficiencyFactor: result.secondHalfEf.toStringAsFixed(2),
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
}

class _HalfMetricsColumn extends StatelessWidget {
  final String heading;
  final String? trailingPill;
  final Color? trailingPillColor;
  final String avgHr;
  final String outputLabel;
  final String outputValue;
  final String efficiencyFactor;

  const _HalfMetricsColumn({
    required this.heading,
    this.trailingPill,
    this.trailingPillColor,
    required this.avgHr,
    required this.outputLabel,
    required this.outputValue,
    required this.efficiencyFactor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              heading.toUpperCase(),
              style: AppTypography.labelCaps,
            ),
            if (trailingPill != null)
              Text(
                trailingPill!,
                style: AppTypography.telemetrySm.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: trailingPillColor ?? AppColors.onSurfaceVariant,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        _MetricLine(label: 'Avg HR', value: avgHr),
        const SizedBox(height: 5),
        _MetricLine(label: outputLabel, value: outputValue),
        const SizedBox(height: 5),
        _MetricLine(label: 'Efficiency (EF)', value: efficiencyFactor),
      ],
    );
  }
}

class _MetricLine extends StatelessWidget {
  final String label;
  final String value;

  const _MetricLine({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: AppTypography.bodySm,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: AppTypography.telemetryMd.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
