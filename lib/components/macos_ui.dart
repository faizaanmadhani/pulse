import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// Native macOS inset grouped card with hairline border and subtle depth shadow.
class MacCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final Color? color;

  const MacCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = 10,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: AppColors.borderSubtle, width: 1),
        boxShadow: [
          BoxShadow(
            color: AppColors.cardShadow,
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Native macOS push button (accent-filled primary or bordered secondary).
class MacPushButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool isPrimary;
  final bool isDestructive;
  final bool isLoading;
  final EdgeInsetsGeometry padding;

  const MacPushButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.isPrimary = false,
    this.isDestructive = false,
    this.isLoading = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
  });

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null && !isLoading;
    final Color bgColor;
    final Color fgColor;
    final BorderSide? border;

    if (isPrimary) {
      bgColor = enabled
          ? (isDestructive ? AppColors.error : AppColors.accent)
          : AppColors.surfaceContainerHigh;
      fgColor = enabled ? Colors.white : AppColors.outline;
      border = null;
    } else {
      bgColor = AppColors.surfaceContainer;
      fgColor = isDestructive
          ? AppColors.error
          : (enabled ? AppColors.onSurface : AppColors.outline);
      border = BorderSide(color: AppColors.borderSubtle, width: 1);
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(6),
            border: border != null ? Border.fromBorderSide(border) : null,
            boxShadow: isPrimary && enabled
                ? [
                    BoxShadow(
                      color: bgColor.withOpacity(0.22),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: AppColors.cardShadow,
                      blurRadius: 2,
                      offset: const Offset(0, 0.5),
                    ),
                  ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isLoading) ...[
                SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    valueColor: AlwaysStoppedAnimation(fgColor),
                  ),
                ),
                const SizedBox(width: 6),
              ] else if (icon != null) ...[
                Icon(icon, size: 14, color: fgColor),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: AppTypography.headlineSm.copyWith(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: fgColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Native macOS segmented control bar.
class MacSegmentedControl<T> extends StatelessWidget {
  final List<T> items;
  final T selected;
  final String Function(T) labelBuilder;
  final Color? Function(T)? dotColorBuilder;
  final ValueChanged<T> onChanged;

  const MacSegmentedControl({
    super.key,
    required this.items,
    required this.selected,
    required this.labelBuilder,
    this.dotColorBuilder,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppColors.surfaceLow,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: AppColors.borderDivider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: items.map((item) {
          final isSelected = item == selected;
          final dotColor = dotColorBuilder?.call(item);
          return InkWell(
            onTap: () => onChanged(item),
            borderRadius: BorderRadius.circular(5),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.surfaceContainer : Colors.transparent,
                borderRadius: BorderRadius.circular(5),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: AppColors.cardShadow,
                          blurRadius: 3,
                          offset: const Offset(0, 1),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (dotColor != null) ...[
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: dotColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                  ],
                  Text(
                    labelBuilder(item),
                    style: AppTypography.bodySm.copyWith(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                      color: isSelected ? AppColors.onSurface : AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Soft macOS tinted pill badge.
class MacStatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const MacStatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withOpacity(AppColors.isDark ? 0.22 : 0.12),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              style: AppTypography.bodySm.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Clean macOS empty state panel with optional primary action.
class MacEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const MacEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: MacCard(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 24, color: AppColors.accent),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: AppTypography.headlineMd,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                message,
                style: AppTypography.bodyMd,
                textAlign: TextAlign.center,
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 18),
                MacPushButton(
                  label: actionLabel!,
                  icon: CupertinoIcons.person_crop_circle_badge_checkmark,
                  isPrimary: true,
                  onPressed: onAction,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
