import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../state/app_state.dart';
import 'garmin_sign_in_dialog.dart';
import 'macos_ui.dart';

class TopHud extends StatefulWidget {
  final AppState appState;

  const TopHud({super.key, required this.appState});

  @override
  State<TopHud> createState() => _TopHudState();
}

class _TopHudState extends State<TopHud> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.appState.searchQuery);
  }

  @override
  void didUpdateWidget(covariant TopHud oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_searchController.text != widget.appState.searchQuery) {
      _searchController.value = TextEditingValue(
        text: widget.appState.searchQuery,
        selection: TextSelection.collapsed(offset: widget.appState.searchQuery.length),
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String get _sectionTitle {
    switch (widget.appState.currentNavIndex) {
      case 0:
        return 'Dashboard';
      case 1:
        return 'Calendar';
      case 2:
        return 'Analytics';
      case 3:
        return widget.appState.selectedActivityId != null ? 'Activity Details' : 'Activities';
      case 4:
        return 'Strength';
      case 5:
        return 'Garmin & Devices';
      default:
        return 'Dashboard';
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = widget.appState;
    if (_searchController.text != appState.searchQuery) {
      _searchController.value = TextEditingValue(
        text: appState.searchQuery,
        selection: TextSelection.collapsed(offset: appState.searchQuery.length),
      );
    }

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: AppColors.toolbarBackground,
        border: Border(
          bottom: BorderSide(color: AppColors.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          // Section Title
          Flexible(
            child: Text(
              _sectionTitle,
              style: AppTypography.headlineMd.copyWith(fontSize: 16),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          const SizedBox(width: 10),

          // Live Garmin Sync Status Pill
          if (appState.isSignedIn)
            MacStatusBadge(
              label: appState.lastSyncedLabel,
              color: appState.syncError != null ? AppColors.error : AppColors.runTertiary,
              icon: appState.isSyncing
                  ? CupertinoIcons.arrow_2_circlepath
                  : CupertinoIcons.checkmark_circle_fill,
            ),

          const Spacer(),

          // Native macOS Search Field
          SizedBox(
            width: 175,
            height: 30,
            child: TextField(
              controller: _searchController,
              onChanged: appState.setSearchQuery,
              style: AppTypography.bodyMd.copyWith(color: AppColors.onSurface, fontSize: 12.5),
              cursorColor: AppColors.accent,
              decoration: InputDecoration(
                hintText: 'Search activities...',
                hintStyle: AppTypography.bodySm.copyWith(color: AppColors.outline),
                prefixIcon: Icon(
                  CupertinoIcons.search,
                  size: 14,
                  color: AppColors.outline,
                ),
                prefixIconConstraints: const BoxConstraints(minWidth: 30),
                suffixIcon: appState.searchQuery.isNotEmpty
                    ? IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                        icon: Icon(
                          CupertinoIcons.xmark_circle_fill,
                          size: 13,
                          color: AppColors.outline,
                        ),
                        onPressed: () {
                          _searchController.clear();
                          appState.setSearchQuery('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: AppColors.surfaceLowest,
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(7),
                  borderSide: BorderSide(color: AppColors.borderSubtle),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(7),
                  borderSide: BorderSide(color: AppColors.borderSubtle),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(7),
                  borderSide: BorderSide(color: AppColors.accent, width: 1.4),
                ),
              ),
            ),
          ),

          const SizedBox(width: 10),

          // Sync or Sign In Button
          if (appState.isSignedIn)
            MacPushButton(
              label: appState.isSyncing ? 'Syncing' : 'Sync Garmin',
              icon: CupertinoIcons.arrow_2_circlepath,
              isLoading: appState.isSyncing,
              onPressed: appState.isSyncing ? null : () => appState.syncFromGarmin(),
            )
          else
            MacPushButton(
              label: 'Sign in with Garmin',
              icon: CupertinoIcons.person_crop_circle,
              isPrimary: true,
              onPressed: () => showGarminSignInDialog(context, appState),
            ),

          const SizedBox(width: 8),

          // Unit System Toggle (Metric km/m vs Imperial mi/ft)
          Tooltip(
            message: appState.isImperial
                ? 'Switch to Metric (km, m)'
                : 'Switch to Imperial (mi, ft)',
            child: InkWell(
              onTap: appState.toggleUnitSystem,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainer,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.borderSubtle),
                ),
                alignment: Alignment.center,
                child: Text(
                  appState.isImperial ? 'MI / FT' : 'KM / M',
                  style: AppTypography.telemetrySm.copyWith(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(width: 6),

          // Appearance Toggle (Light / Dark macOS Mode)
          Tooltip(
            message: appState.isDarkMode ? 'Switch to Light Mode' : 'Switch to Dark Mode',
            child: InkWell(
              onTap: appState.toggleDarkMode,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainer,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.borderSubtle),
                ),
                child: Icon(
                  appState.isDarkMode ? CupertinoIcons.sun_max : CupertinoIcons.moon,
                  size: 15,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
