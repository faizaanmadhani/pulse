import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/performance_metrics.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// Clean Apple Health–style sparkline with optional hover crosshair & marker.
class AcwrSparklinePainter extends CustomPainter {
  final List<double> values;
  final Color? lineColor;
  final bool showZones;
  final int? hoveredIndex;

  AcwrSparklinePainter({
    required this.values,
    this.lineColor,
    this.showZones = false,
    this.hoveredIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;

    final color = lineColor ?? AppColors.accent;
    final double minVal = values.reduce(math.min) * 0.9;
    final double maxVal = math.max(values.reduce(math.max) * 1.1, minVal + 0.1);
    final double dx = size.width / (values.length - 1);

    final Path path = Path();
    final Path fillPath = Path();
    final points = <Offset>[];

    for (int i = 0; i < values.length; i++) {
      final normalized = (values[i] - minVal) / (maxVal - minVal);
      final y = size.height - (normalized * size.height).clamp(2.0, size.height - 2.0);
      final x = i * dx;
      points.add(Offset(x, y));
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        final prev = points[i - 1];
        final midX = (prev.dx + x) / 2;
        path.cubicTo(midX, prev.dy, midX, y, x, y);
        fillPath.cubicTo(midX, prev.dy, midX, y, x, y);
      }
    }
    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withOpacity(0.18),
          color.withOpacity(0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fillPath, fillPaint);

    final strokePaint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, strokePaint);

    if (hoveredIndex != null && hoveredIndex! >= 0 && hoveredIndex! < points.length) {
      final pt = points[hoveredIndex!];
      canvas.drawLine(
        Offset(pt.dx, 0),
        Offset(pt.dx, size.height),
        Paint()
          ..color = AppColors.outline.withOpacity(0.45)
          ..strokeWidth = 1.0,
      );
      canvas.drawCircle(pt, 4.5, Paint()..color = color);
      canvas.drawCircle(
        pt,
        4.5,
        Paint()
          ..color = AppColors.surfaceContainer
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    } else {
      final last = points.last;
      canvas.drawCircle(last, 3.0, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant AcwrSparklinePainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.hoveredIndex != hoveredIndex ||
      oldDelegate.lineColor != lineColor;
}

/// Interactive hoverable wrapper for the 14-day ACWR sparkline.
class InteractiveAcwrSparkline extends StatefulWidget {
  final List<double> values;
  final List<String>? labels;
  final Color? lineColor;

  const InteractiveAcwrSparkline({
    super.key,
    required this.values,
    this.labels,
    this.lineColor,
  });

  @override
  State<InteractiveAcwrSparkline> createState() => _InteractiveAcwrSparklineState();
}

class _InteractiveAcwrSparklineState extends State<InteractiveAcwrSparkline> {
  int? _hoveredIndex;

  @override
  Widget build(BuildContext context) {
    if (widget.values.length < 2) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final idx = _hoveredIndex;

        return MouseRegion(
          cursor: SystemMouseCursors.precise,
          onHover: (event) {
            final fraction = (event.localPosition.dx / math.max(1.0, w)).clamp(0.0, 1.0);
            final next = (fraction * (widget.values.length - 1)).round();
            if (next != _hoveredIndex) {
              setState(() => _hoveredIndex = next);
            }
          },
          onExit: (_) {
            if (_hoveredIndex != null) setState(() => _hoveredIndex = null);
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: AcwrSparklinePainter(
                    values: widget.values,
                    lineColor: widget.lineColor,
                    hoveredIndex: idx,
                  ),
                ),
              ),
              if (idx != null && idx >= 0 && idx < widget.values.length)
                Positioned(
                  top: -28,
                  right: 0,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainer,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: AppColors.borderSubtle),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.cardShadow,
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        '${widget.labels != null && idx < widget.labels!.length ? '${widget.labels![idx]} • ' : ''}${widget.values[idx].toStringAsFixed(2)}',
                        style: AppTypography.telemetrySm.copyWith(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: AppColors.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
              SizedBox(width: w, height: h),
            ],
          ),
        );
      },
    );
  }
}

/// Clean macOS Performance Management Chart (CTL, ATL, TSB) with hover crosshair & dots.
class PmcChartPainter extends CustomPainter {
  final List<double> ctlValues;
  final List<double> atlValues;
  final List<double> tsbValues;
  final int? hoveredIndex;

  PmcChartPainter({
    required this.ctlValues,
    required this.atlValues,
    required this.tsbValues,
    this.hoveredIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (ctlValues.length < 2) return;

    final gridPaint = Paint()
      ..color = AppColors.borderDivider
      ..strokeWidth = 1.0;

    for (int i = 0; i <= 4; i++) {
      final y = (size.height / 4) * i;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final all = [...ctlValues, ...atlValues, ...tsbValues];
    final minVal = math.min(0.0, all.reduce(math.min)) - 5;
    final maxVal = math.max(10.0, all.reduce(math.max)) + 5;
    final range = (maxVal - minVal).abs() < 1 ? 1.0 : (maxVal - minVal);

    double yFor(double v) => size.height - ((v - minVal) / range) * size.height;

    final dx = size.width / (ctlValues.length - 1);

    // Zero baseline
    final zeroY = yFor(0);
    canvas.drawLine(
      Offset(0, zeroY),
      Offset(size.width, zeroY),
      Paint()
        ..color = AppColors.outline.withOpacity(0.35)
        ..strokeWidth = 1.0,
    );

    // TSB area fill
    final tsbFill = Path()..moveTo(0, zeroY);
    for (int i = 0; i < tsbValues.length; i++) {
      tsbFill.lineTo(i * dx, yFor(tsbValues[i]));
    }
    tsbFill.lineTo(size.width, zeroY);
    tsbFill.close();
    canvas.drawPath(
      tsbFill,
      Paint()..color = AppColors.runTertiary.withOpacity(0.12),
    );

    void drawSeries(List<double> data, Color color, double strokeWidth) {
      final path = Path();
      for (int i = 0; i < data.length; i++) {
        final x = i * dx;
        final y = yFor(data[i]);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          final prevX = (i - 1) * dx;
          final prevY = yFor(data[i - 1]);
          final midX = (prevX + x) / 2;
          path.cubicTo(midX, prevY, midX, y, x, y);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = strokeWidth
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
    }

    drawSeries(tsbValues, AppColors.runTertiary, 1.6);
    drawSeries(atlValues, AppColors.bikeSecondary, 2.0);
    drawSeries(ctlValues, AppColors.swimPrimary, 2.4);

    // Interactive crosshair + snapped data dots
    if (hoveredIndex != null && hoveredIndex! >= 0 && hoveredIndex! < ctlValues.length) {
      final i = hoveredIndex!;
      final x = i * dx;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = AppColors.outline.withOpacity(0.55)
          ..strokeWidth = 1.0,
      );

      void drawDot(double value, Color color) {
        final pt = Offset(x, yFor(value));
        canvas.drawCircle(pt, 5.0, Paint()..color = color);
        canvas.drawCircle(
          pt,
          5.0,
          Paint()
            ..color = AppColors.surfaceContainer
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8,
        );
      }

      drawDot(tsbValues[i], AppColors.runTertiary);
      drawDot(atlValues[i], AppColors.bikeSecondary);
      drawDot(ctlValues[i], AppColors.swimPrimary);
    }
  }

  @override
  bool shouldRepaint(covariant PmcChartPainter oldDelegate) =>
      oldDelegate.hoveredIndex != hoveredIndex ||
      oldDelegate.ctlValues != ctlValues ||
      oldDelegate.atlValues != atlValues ||
      oldDelegate.tsbValues != tsbValues;
}

/// Interactive Performance Management Chart with hover crosshair & floating macOS tooltip.
class InteractivePmcChart extends StatefulWidget {
  final List<PmcDataPoint> points;
  final double height;

  const InteractivePmcChart({
    super.key,
    required this.points,
    this.height = 220,
  });

  @override
  State<InteractivePmcChart> createState() => _InteractivePmcChartState();
}

class _InteractivePmcChartState extends State<InteractivePmcChart> {
  int? _hoveredIndex;

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
          final hoveredPoint = idx != null ? widget.points[idx] : null;
          final hoverX = idx != null ? (idx / (widget.points.length - 1)) * w : 0.0;
          const tooltipWidth = 176.0;
          final showLeft = hoverX > w - tooltipWidth - 18;
          final tooltipLeft = showLeft
              ? math.max(8.0, hoverX - tooltipWidth - 12)
              : math.min(w - tooltipWidth - 8, hoverX + 12);

          return MouseRegion(
            cursor: SystemMouseCursors.precise,
            onHover: (event) {
              final fraction = (event.localPosition.dx / math.max(1.0, w)).clamp(0.0, 1.0);
              final next = (fraction * (widget.points.length - 1)).round();
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
                    painter: PmcChartPainter(
                      ctlValues: widget.points.map((e) => e.ctl).toList(),
                      atlValues: widget.points.map((e) => e.atl).toList(),
                      tsbValues: widget.points.map((e) => e.tsb).toList(),
                      hoveredIndex: idx,
                    ),
                  ),
                ),
                if (hoveredPoint != null)
                  Positioned(
                    top: 8,
                    left: tooltipLeft,
                    child: IgnorePointer(
                      child: Container(
                        width: tooltipWidth,
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
                              DateFormat('EEE, MMM d, y').format(hoveredPoint.date),
                              style: AppTypography.bodySm.copyWith(
                                fontWeight: FontWeight.w600,
                                color: AppColors.onSurface,
                              ),
                            ),
                            const SizedBox(height: 6),
                            _tooltipRow('Fitness (CTL)', hoveredPoint.ctl.toStringAsFixed(1), AppColors.swimPrimary),
                            const SizedBox(height: 3),
                            _tooltipRow('Fatigue (ATL)', hoveredPoint.atl.toStringAsFixed(1), AppColors.bikeSecondary),
                            const SizedBox(height: 3),
                            _tooltipRow(
                              'Form (TSB)',
                              '${hoveredPoint.tsb >= 0 ? '+' : ''}${hoveredPoint.tsb.toStringAsFixed(1)}',
                              AppColors.runTertiary,
                            ),
                            if (hoveredPoint.dailyTss > 0) ...[
                              const SizedBox(height: 4),
                              Divider(height: 1, color: AppColors.borderDivider),
                              const SizedBox(height: 4),
                              _tooltipRow('Daily Load', '${hoveredPoint.dailyTss.round()} TSS', AppColors.outline),
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

  Widget _tooltipRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(label, style: AppTypography.bodySm.copyWith(fontSize: 11)),
          ],
        ),
        Text(
          value,
          style: AppTypography.telemetrySm.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.onSurface,
          ),
        ),
      ],
    );
  }
}

/// Clean Apple Fitness–style rounded bar chart with hover highlight support.
class DailyBarChartPainter extends CustomPainter {
  final List<double> values;
  final Color barColor;
  final int? hoveredIndex;

  DailyBarChartPainter({
    required this.values,
    required this.barColor,
    this.hoveredIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final gridPaint = Paint()
      ..color = AppColors.borderDivider
      ..strokeWidth = 1.0;

    for (int i = 0; i <= 3; i++) {
      final y = (size.height / 3) * i;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final maxVal = math.max(1.0, values.reduce(math.max));
    final slotWidth = size.width / values.length;
    final barWidth = math.min(26.0, slotWidth * 0.56);

    for (int i = 0; i < values.length; i++) {
      final v = values[i];
      final h = ((v / maxVal) * (size.height - 8)).clamp(v > 0 ? 4.0 : 2.0, size.height - 8);
      final left = i * slotWidth + (slotWidth - barWidth) / 2;
      final top = size.height - h;
      final isHovered = hoveredIndex == i;

      if (isHovered) {
        final colRect = Rect.fromLTWH(i * slotWidth + 2, 0, slotWidth - 4, size.height);
        canvas.drawRRect(
          RRect.fromRectAndRadius(colRect, const Radius.circular(6)),
          Paint()..color = barColor.withOpacity(0.08),
        );
      }

      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(left, top, barWidth, h),
        topLeft: const Radius.circular(4),
        topRight: const Radius.circular(4),
      );
      final fillColor = v > 0
          ? (hoveredIndex == null || isHovered ? barColor : barColor.withOpacity(0.45))
          : AppColors.surfaceContainerHigh;
      canvas.drawRRect(rect, Paint()..color = fillColor);
    }
  }

  @override
  bool shouldRepaint(covariant DailyBarChartPainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.hoveredIndex != hoveredIndex ||
      oldDelegate.barColor != barColor;
}

/// Interactive hoverable daily bar chart with macOS floating date & distance tooltip.
class InteractiveDailyBarChart extends StatefulWidget {
  final List<double> values;
  final List<String> labels;
  final Color barColor;
  final String unit;
  final double height;

  const InteractiveDailyBarChart({
    super.key,
    required this.values,
    required this.labels,
    required this.barColor,
    this.unit = 'km',
    this.height = 140,
  });

  @override
  State<InteractiveDailyBarChart> createState() => _InteractiveDailyBarChartState();
}

class _InteractiveDailyBarChartState extends State<InteractiveDailyBarChart> {
  int? _hoveredIndex;

  @override
  Widget build(BuildContext context) {
    if (widget.values.isEmpty) return SizedBox(height: widget.height);

    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final idx = _hoveredIndex?.clamp(0, widget.values.length - 1);
          final slotW = w / widget.values.length;
          const tooltipWidth = 128.0;
          final centerX = idx != null ? (idx + 0.5) * slotW : 0.0;
          final tooltipLeft =
              (centerX - tooltipWidth / 2).clamp(4.0, math.max(4.0, w - tooltipWidth - 4)).toDouble();

          return MouseRegion(
            cursor: SystemMouseCursors.precise,
            onHover: (event) {
              final next = (event.localPosition.dx / math.max(1.0, slotW))
                  .floor()
                  .clamp(0, widget.values.length - 1);
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
                    painter: DailyBarChartPainter(
                      values: widget.values,
                      barColor: widget.barColor,
                      hoveredIndex: idx,
                    ),
                  ),
                ),
                if (idx != null)
                  Positioned(
                    top: 6,
                    left: tooltipLeft,
                    child: IgnorePointer(
                      child: Container(
                        width: tooltipWidth,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainer.withOpacity(0.96),
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(color: AppColors.borderSubtle),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.cardShadow,
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              idx < widget.labels.length ? widget.labels[idx] : 'Day ${idx + 1}',
                              style: AppTypography.bodySm.copyWith(fontSize: 10),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${widget.values[idx].toStringAsFixed(1)} ${widget.unit}',
                              style: AppTypography.telemetryMd.copyWith(
                                fontWeight: FontWeight.w700,
                                color: widget.values[idx] > 0
                                    ? widget.barColor
                                    : AppColors.outline,
                              ),
                            ),
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
}
