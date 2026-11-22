import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../state/app_state.dart';
import '../models/device_status.dart';
import '../components/garmin_sign_in_dialog.dart';
import '../components/gear_tracker_card.dart';
import '../components/strava_connect_dialog.dart';
import '../components/macos_ui.dart';

class DeviceSyncView extends StatelessWidget {
  final AppState appState;

  const DeviceSyncView({super.key, required this.appState});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Garmin Connect Account Connection Card
          _buildGarminAccountCard(context),

          const SizedBox(height: 16),

          // Strava Account & Activity Enrichment Card
          _buildStravaAccountCard(context),

          const SizedBox(height: 16),

          // Paired Garmin Devices (Real from Garmin Connect)
          _buildPairedDevicesSection(context),

          const SizedBox(height: 16),

          // Gear Mileage Tracker (Shoes & Bikes synced from Garmin + Strava)
          GearTrackerCard(
            items: appState.gearInventory,
            unitSystem: appState.unitSystem,
            isStravaConnected: appState.isStravaConnected,
            onConnectStrava: () {
              showStravaConnectDialog(
                context,
                onConnectOAuth: ({required clientId, required clientSecret}) =>
                    appState.connectStravaOAuth(
                  clientId: clientId,
                  clientSecret: clientSecret,
                ),
                onConnectAccessToken: (token) => appState.connectStravaAccessToken(token),
                initialError: appState.stravaError,
              );
            },
          ),

          const SizedBox(height: 16),

          // Synced Data Summary
          _buildSyncSummaryCard(),
        ],
      ),
    );
  }

  Widget _buildGarminAccountCard(BuildContext context) {
    final profile = appState.userProfile;
    return MacCard(
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: appState.isSignedIn
                  ? AppColors.accent.withOpacity(0.14)
                  : AppColors.surfaceLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: appState.isSignedIn
                  ? Text(
                      profile?.initials ?? 'G',
                      style: AppTypography.headlineLg.copyWith(color: AppColors.accent),
                    )
                  : Icon(CupertinoIcons.person_crop_circle, size: 26, color: AppColors.outline),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        appState.isSignedIn
                            ? (profile?.fullName.isNotEmpty == true
                                ? profile!.fullName
                                : (profile?.displayName ?? 'Garmin Connect Account'))
                            : 'Garmin Connect',
                        style: AppTypography.headlineMd,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    MacStatusBadge(
                      label: appState.isSignedIn ? 'Connected' : 'Not Connected',
                      color: appState.isSignedIn ? AppColors.runTertiary : AppColors.outline,
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  appState.isSignedIn
                      ? '${appState.lastSyncedLabel} • ${appState.activities.length} activities loaded'
                      : 'Sign in with your Garmin Connect account to pull your real activities, devices, and health metrics.',
                  style: AppTypography.bodySm,
                ),
                if (appState.syncError != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    appState.syncError!,
                    style: AppTypography.bodySm.copyWith(color: AppColors.error),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (appState.isSignedIn) ...[
            MacPushButton(
              label: appState.isSyncing ? 'Syncing...' : 'Sync Now',
              icon: CupertinoIcons.arrow_2_circlepath,
              isPrimary: true,
              isLoading: appState.isSyncing,
              onPressed: appState.isSyncing ? null : () => appState.syncFromGarmin(),
            ),
            const SizedBox(width: 8),
            MacPushButton(
              label: 'Sign Out',
              isDestructive: true,
              onPressed: () => appState.signOutGarmin(),
            ),
          ] else
            MacPushButton(
              label: 'Sign in with Garmin',
              icon: CupertinoIcons.person_crop_circle_badge_checkmark,
              isPrimary: true,
              onPressed: () => showGarminSignInDialog(context, appState),
            ),
        ],
      ),
    );
  }

  Widget _buildStravaAccountCard(BuildContext context) {
    const stravaOrange = Color(0xFFFC4C02);
    final isConnected = appState.isStravaConnected;
    final athleteName = appState.stravaSession?.athleteName;

    return MacCard(
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isConnected ? stravaOrange.withOpacity(0.14) : AppColors.surfaceLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Icon(
                CupertinoIcons.flame_fill,
                size: 24,
                color: isConnected ? stravaOrange : AppColors.outline,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        isConnected
                            ? (athleteName != null && athleteName.isNotEmpty
                                ? 'Strava • $athleteName'
                                : 'Strava Connected')
                            : 'Strava Enrichment',
                        style: AppTypography.headlineMd,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    MacStatusBadge(
                      label: isConnected ? 'Connected' : 'Not Connected',
                      color: isConnected ? stravaOrange : AppColors.outline,
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  isConnected
                      ? '${appState.stravaMatchedCount} Garmin activities joined with Strava titles, descriptions, kudos, comments & segment PRs'
                      : 'Connect Strava to join your Garmin workouts with Strava titles, descriptions, kudos, comments, and segment PRs.',
                  style: AppTypography.bodySm,
                ),
                if (appState.stravaError != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    appState.stravaError!,
                    style: AppTypography.bodySm.copyWith(color: AppColors.error),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (isConnected) ...[
            MacPushButton(
              label: appState.isSyncingStrava ? 'Syncing' : 'Sync Strava',
              icon: CupertinoIcons.arrow_2_circlepath,
              isLoading: appState.isSyncingStrava,
              onPressed: appState.isSyncingStrava ? null : () => appState.syncFromStrava(),
            ),
            const SizedBox(width: 8),
            MacPushButton(
              label: 'Disconnect',
              isDestructive: true,
              onPressed: () => appState.disconnectStrava(),
            ),
          ] else
            MacPushButton(
              label: 'Connect Strava',
              icon: CupertinoIcons.link,
              isPrimary: true,
              onPressed: () {
                showStravaConnectDialog(
                  context,
                  onConnectOAuth: ({required clientId, required clientSecret}) =>
                      appState.connectStravaOAuth(
                    clientId: clientId,
                    clientSecret: clientSecret,
                  ),
                  onConnectAccessToken: (token) => appState.connectStravaAccessToken(token),
                  initialError: appState.stravaError,
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildPairedDevicesSection(BuildContext context) {
    return MacCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Registered Garmin Devices', style: AppTypography.headlineMd),
              Text(
                '${appState.connectedDevices.length} device(s)',
                style: AppTypography.bodySm,
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (!appState.isSignedIn)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'Sign in with Garmin Connect to view your paired watches, bike computers, and sensors.',
                  style: AppTypography.bodyMd,
                ),
              ),
            )
          else if (appState.connectedDevices.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  appState.isSyncing
                      ? 'Fetching your registered Garmin devices...'
                      : 'No registered devices returned by Garmin Connect.',
                  style: AppTypography.bodyMd,
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final cols = constraints.maxWidth > 900 ? 3 : 2;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: appState.connectedDevices.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 2.35,
                  ),
                  itemBuilder: (context, index) => _buildDeviceTile(appState.connectedDevices[index]),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildDeviceTile(ConnectedDevice dev) {
    final isBike = dev.name.toLowerCase().contains('edge') || dev.category.toLowerCase().contains('bike');
    final icon = isBike ? Icons.directions_bike_rounded : CupertinoIcons.clock;
    final accent = isBike ? AppColors.bikeSecondary : AppColors.accent;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderDivider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: accent),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  dev.name,
                  style: AppTypography.headlineSm,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Text(
            '${dev.category} • ${dev.firmwareVersion}',
            style: AppTypography.bodySm,
            overflow: TextOverflow.ellipsis,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  dev.lastSyncTime,
                  style: AppTypography.bodySm.copyWith(fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              MacStatusBadge(label: 'Paired', color: AppColors.runTertiary),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSyncSummaryCard() {
    return MacCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Data Privacy & Local Storage', style: AppTypography.headlineMd),
          const SizedBox(height: 8),
          Text(
            'All Garmin API requests are sent directly from your Mac to Garmin Connect. Your password is never saved; only your OAuth session token is stored locally in macOS Application Support with user-only permissions.',
            style: AppTypography.bodyMd,
          ),
        ],
      ),
    );
  }
}
