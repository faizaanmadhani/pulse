import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/gear_item.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../utils/unit_formatter.dart';
import 'macos_ui.dart';

/// Native macOS HIG card displaying shoe and bike mileage totals, wear
/// progress bars, and replacement alerts synced from Garmin and Strava.
class GearTrackerCard extends StatelessWidget {
  final List<GearItem> items;
  final UnitSystem unitSystem;
  final bool isStravaConnected;
  final VoidCallback? onConnectStrava;

  const GearTrackerCard({
    super.key,
    required this.items,
    required this.unitSystem,
    required this.isStravaConnected,
    this.onConnectStrava,
  });

  @override
  Widget build(BuildContext context) {
    final alertCount =
        items.where((item) => item.alertLevel != GearAlertLevel.ok).length;

    return MacCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(alertCount),
          const SizedBox(height: 14),
          if (items.isEmpty)
            _buildEmptyState()
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < items.length; i++) ...[
                  if (i > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Divider(
                        height: 1,
                        thickness: 1,
                        color: AppColors.borderDivider,
                      ),
                    ),
                  _GearItemRow(
                    item: items[i],
                    unitSystem: unitSystem,
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildHeader(int alertCount) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: AppColors.accent.withOpacity(0.12),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(
            CupertinoIcons.gauge,
            size: 16,
            color: AppColors.accent,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Gear Mileage Tracker',
                style: AppTypography.headlineMd,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                items.isEmpty
                    ? 'Shoes & bikes synced from Garmin & Strava'
                    : '${items.length} ${items.length == 1 ? 'item' : 'items'} tracked',
                style: AppTypography.bodySm,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (alertCount > 0) ...[
          const SizedBox(width: 8),
          MacStatusBadge(
            label: '$alertCount ${alertCount == 1 ? 'Alert' : 'Alerts'}',
            color: items.any((i) => i.alertLevel == GearAlertLevel.replace)
                ? AppColors.error
                : AppColors.bikeSecondary,
            icon: CupertinoIcons.exclamationmark_triangle_fill,
          ),
        ],
      ],
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: AppColors.surfaceLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderDivider),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.directions_run_rounded,
            size: 24,
            color: AppColors.outline,
          ),
          const SizedBox(height: 8),
          Text(
            'No gear logged yet',
            style: AppTypography.headlineSm,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            'Shoe and bike mileage is automatically tracked from your Garmin & Strava activities with replacement alerts.',
            style: AppTypography.bodySm.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          if (!isStravaConnected && onConnectStrava != null) ...[
            const SizedBox(height: 14),
            MacPushButton(
              label: 'Connect Strava',
              icon: CupertinoIcons.link,
              isPrimary: true,
              onPressed: onConnectStrava,
            ),
          ],
        ],
      ),
    );
  }
}

class _GearItemRow extends StatelessWidget {
  final GearItem item;
  final UnitSystem unitSystem;

  const _GearItemRow({
    required this.item,
    required this.unitSystem,
  });

  @override
  Widget build(BuildContext context) {
    final progressColor = _progressColor(item);
    final progressValue = item.usageFraction.clamp(0.0, 1.0);
    final percentText =
        UnitFormatter.formatPercent(item.usageFraction * 100.0, decimals: 0);
    final totalFormatted =
        UnitFormatter.formatDistance(item.totalDistanceKm, unitSystem);
    final maxFormatted = UnitFormatter.formatDistance(
      item.maxDistanceKm,
      unitSystem,
      decimals: 0,
    );
    final remainingLabel = item.overdueKm > 0
        ? '${UnitFormatter.formatDistance(item.overdueKm, unitSystem)} over limit'
        : '${UnitFormatter.formatDistance(item.remainingKm, unitSystem)} remaining';
    final sessionLabel =
        '${item.activityCount} ${item.activityCount == 1 ? 'session' : 'sessions'}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: progressColor.withOpacity(AppColors.isDark ? 0.20 : 0.12),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(
                _categoryIcon(item.category),
                size: 16,
                color: progressColor,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: AppTypography.headlineSm,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      MacStatusBadge(
                        label: item.source,
                        color: _sourceColor(item.source),
                      ),
                      if (item.alertLevel == GearAlertLevel.replace)
                        MacStatusBadge(
                          label: 'Replace Now',
                          color: AppColors.error,
                          icon: CupertinoIcons.exclamationmark_circle_fill,
                        )
                      else if (item.alertLevel == GearAlertLevel.warning)
                        MacStatusBadge(
                          label: 'Replace Soon',
                          color: AppColors.bikeSecondary,
                          icon: CupertinoIcons.exclamationmark_triangle_fill,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  totalFormatted,
                  style: AppTypography.telemetryMd.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'of $maxFormatted ($percentText)',
                  style: AppTypography.telemetrySm,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progressValue,
            minHeight: 6,
            backgroundColor: AppColors.surfaceContainerHigh,
            valueColor: AlwaysStoppedAnimation<Color>(progressColor),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                remainingLabel,
                style: AppTypography.bodySm.copyWith(
                  color: item.alertLevel == GearAlertLevel.replace
                      ? AppColors.error
                      : (item.alertLevel == GearAlertLevel.warning
                          ? AppColors.bikeSecondary
                          : AppColors.onSurfaceVariant),
                  fontWeight: item.alertLevel == GearAlertLevel.ok
                      ? FontWeight.w400
                      : FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              sessionLabel,
              style: AppTypography.telemetrySm,
            ),
          ],
        ),
      ],
    );
  }

  static IconData _categoryIcon(GearCategory category) {
    switch (category) {
      case GearCategory.shoes:
        return Icons.directions_run_rounded;
      case GearCategory.bike:
        return Icons.directions_bike_rounded;
      case GearCategory.other:
        return CupertinoIcons.wrench_fill;
    }
  }

  static Color _progressColor(GearItem item) {
    switch (item.alertLevel) {
      case GearAlertLevel.replace:
        return AppColors.error;
      case GearAlertLevel.warning:
        return AppColors.bikeSecondary;
      case GearAlertLevel.ok:
        return item.category == GearCategory.shoes
            ? AppColors.runTertiary
            : AppColors.accent;
    }
  }

  static Color _sourceColor(String source) {
    if (source == 'Strava') {
      return const Color(0xFFFC4C02);
    }
    if (source == 'Garmin + Strava') {
      return AppColors.strengthViolet;
    }
    return AppColors.accent;
  }
}
