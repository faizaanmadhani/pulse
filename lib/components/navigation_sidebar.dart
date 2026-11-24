import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../state/app_state.dart';
import 'garmin_sign_in_dialog.dart';

class NavigationSidebar extends StatelessWidget {
  final AppState appState;

  const NavigationSidebar({super.key, required this.appState});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 236,
      decoration: BoxDecoration(
        color: AppColors.sidebarBackground,
        border: Border(
          right: BorderSide(color: AppColors.borderSubtle),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top inset for native macOS window traffic lights
          const SizedBox(height: 40),

          // App Title Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Icon(
                    CupertinoIcons.waveform_path_ecg,
                    size: 15,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text('Pulse', style: AppTypography.headlineSm),
                ),
              ],
            ),
          ),

          // Section: Training
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
            child: Text('Training', style: AppTypography.labelCaps),
          ),

          _buildNavItem(
            index: 0,
            icon: CupertinoIcons.square_grid_2x2,
            selectedIcon: CupertinoIcons.square_grid_2x2_fill,
            label: 'Dashboard',
          ),
          _buildNavItem(
            index: 1,
            icon: CupertinoIcons.calendar,
            selectedIcon: CupertinoIcons.calendar_today,
            label: 'Calendar',
          ),
          _buildNavItem(
            index: 2,
            icon: CupertinoIcons.sparkles,
            selectedIcon: CupertinoIcons.sparkles,
            label: 'Training Plan',
          ),
          _buildNavItem(
            index: 3,
            icon: CupertinoIcons.chart_bar,
            selectedIcon: CupertinoIcons.chart_bar_fill,
            label: 'Analytics',
          ),
          _buildNavItem(
            index: 4,
            icon: CupertinoIcons.list_bullet,
            selectedIcon: CupertinoIcons.list_bullet,
            label: 'Activities',
            trailingCount: appState.isSignedIn ? appState.activities.length : null,
          ),
          _buildNavItem(
            index: 5,
            icon: CupertinoIcons.flame,
            selectedIcon: CupertinoIcons.flame_fill,
            label: 'Strength',
          ),

          const SizedBox(height: 12),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
            child: Text('Connections', style: AppTypography.labelCaps),
          ),
          _buildNavItem(
            index: 6,
            icon: CupertinoIcons.arrow_2_circlepath,
            selectedIcon: CupertinoIcons.arrow_2_circlepath_circle_fill,
            label: 'Garmin & Devices',
          ),

          const SizedBox(height: 18),

          // 7-Day Volume Summary (Computed from real Garmin data)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('Last 7 Days', style: AppTypography.labelCaps),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
              childAspectRatio: 2.05,
              children: [
                _buildVolumeTile('Swim', appState.swimVolume7d, AppColors.swimPrimary),
                _buildVolumeTile('Bike', appState.bikeVolume7d, AppColors.bikeSecondary),
                _buildVolumeTile('Run', appState.runVolume7d, AppColors.runTertiary),
                _buildVolumeTile('Strength', appState.strengthVolume7d, AppColors.strengthViolet),
              ],
            ),
          ),

          const Spacer(),

          // Bottom Garmin Account Card
          _buildAccountFooter(context),
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required IconData selectedIcon,
    required String label,
    int? trailingCount,
  }) {
    final bool isSelected = appState.currentNavIndex == index;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1.5),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            appState.selectPlannedWorkout(null);
            appState.setNavIndex(index);
            if (index == 4) {
              appState.setSelectedActivityId(null);
            }
          },
          borderRadius: BorderRadius.circular(7),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.accent.withOpacity(AppColors.isDark ? 0.24 : 0.13) : Colors.transparent,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Row(
              children: [
                Icon(
                  isSelected ? selectedIcon : icon,
                  size: 16,
                  color: isSelected ? AppColors.accent : AppColors.onSurfaceVariant,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    label,
                    style: AppTypography.bodyMd.copyWith(
                      color: isSelected ? AppColors.accent : AppColors.onSurface,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (trailingCount != null && trailingCount > 0)
                  Text(
                    '$trailingCount',
                    style: AppTypography.telemetrySm.copyWith(
                      fontSize: 11,
                      color: isSelected ? AppColors.accent : AppColors.outline,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVolumeTile(String label, String volume, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: AppColors.borderDivider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  label,
                  style: AppTypography.bodySm.copyWith(fontSize: 10.5),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            volume,
            style: AppTypography.telemetrySm.copyWith(
              color: AppColors.onSurface,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildAccountFooter(BuildContext context) {
    final profile = appState.userProfile;
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            appState.selectPlannedWorkout(null);
            if (appState.isSignedIn) {
              appState.setNavIndex(6);
            } else {
              showGarminSignInDialog(context, appState);
            }
          },
          borderRadius: BorderRadius.circular(9),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainer,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: AppColors.borderSubtle),
            ),
            child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: appState.isSignedIn
                    ? AppColors.accent.withOpacity(0.15)
                    : AppColors.surfaceLow,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: appState.isSignedIn
                    ? Text(
                        profile?.initials ?? 'G',
                        style: AppTypography.headlineSm.copyWith(
                          color: AppColors.accent,
                          fontSize: 12,
                        ),
                      )
                    : Icon(CupertinoIcons.person, size: 15, color: AppColors.outline),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appState.isSignedIn
                        ? (profile?.fullName.isNotEmpty == true
                            ? profile!.fullName
                            : (profile?.displayName ?? 'Garmin Account'))
                        : 'Sign in with Garmin',
                    style: AppTypography.headlineSm.copyWith(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: appState.isSignedIn ? AppColors.runTertiary : AppColors.outline,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          appState.lastSyncedLabel,
                          style: AppTypography.bodySm.copyWith(fontSize: 10.5),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Icon(CupertinoIcons.chevron_right, size: 13, color: AppColors.outline),
          ],
        ),
      ),
        ),
      ),
    );
  }
}
