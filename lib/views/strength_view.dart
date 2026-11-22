import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../state/app_state.dart';
import '../models/activity.dart';
import '../components/garmin_sign_in_dialog.dart';
import '../components/macos_ui.dart';

class StrengthView extends StatelessWidget {
  final AppState appState;

  const StrengthView({super.key, required this.appState});

  @override
  Widget build(BuildContext context) {
    if (!appState.isSignedIn) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: MacEmptyState(
          icon: CupertinoIcons.flame,
          title: 'Strength & Conditioning',
          message: 'Sign in with Garmin Connect to view your synced strength training sessions, duration, heart rate, and calories.',
          actionLabel: 'Sign in with Garmin',
          onAction: () => showGarminSignInDialog(context, appState),
        ),
      );
    }

    final strengthSessions = appState.activities
        .where((a) => a.discipline == SportDiscipline.strength)
        .toList();

    final totalSeconds = strengthSessions.fold<double>(0, (s, a) => s + a.durationSeconds);
    final totalCalories = strengthSessions.fold<int>(0, (s, a) => s + a.calories);
    final avgHrList = strengthSessions.where((a) => a.avgHr > 0).map((a) => a.avgHr).toList();
    final avgHr = avgHrList.isEmpty
        ? null
        : (avgHrList.reduce((a, b) => a + b) / avgHrList.length).round();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Summary Row
          Row(
            children: [
              Expanded(
                child: MacCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Synced Sessions', style: AppTypography.bodySm),
                      const SizedBox(height: 4),
                      Text('${strengthSessions.length}', style: AppTypography.telemetryHero),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: MacCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Total Time', style: AppTypography.bodySm),
                      const SizedBox(height: 4),
                      Text('${(totalSeconds / 3600.0).toStringAsFixed(1)} hrs', style: AppTypography.telemetryHero),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: MacCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Avg Heart Rate', style: AppTypography.bodySm),
                      const SizedBox(height: 4),
                      Text(avgHr != null ? '$avgHr bpm' : '—', style: AppTypography.telemetryHero),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: MacCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Total Calories', style: AppTypography.bodySm),
                      const SizedBox(height: 4),
                      Text('$totalCalories kcal', style: AppTypography.telemetryHero),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Strength Sessions List
          MacCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Garmin Strength Sessions', style: AppTypography.headlineMd),
                const SizedBox(height: 12),
                if (strengthSessions.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text(
                        'No strength training activities found in your recent Garmin Connect history.',
                        style: AppTypography.bodyMd,
                      ),
                    ),
                  )
                else
                  ...strengthSessions.asMap().entries.map((entry) {
                    final act = entry.value;
                    final isLast = entry.key == strengthSessions.length - 1;
                    return Column(
                      children: [
                        InkWell(
                          onTap: () => appState.setSelectedActivityId(act.id),
                          borderRadius: BorderRadius.circular(7),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                            child: Row(
                              children: [
                                Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: AppColors.strengthViolet.withOpacity(0.14),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    CupertinoIcons.flame_fill,
                                    size: 16,
                                    color: AppColors.strengthViolet,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(act.title, style: AppTypography.headlineSm),
                                      Text(act.formattedDate, style: AppTypography.bodySm),
                                    ],
                                  ),
                                ),
                                Text(act.movingTime, style: AppTypography.telemetryMd),
                                const SizedBox(width: 20),
                                Text(
                                  act.avgHr > 0 ? '${act.avgHr} bpm' : '—',
                                  style: AppTypography.telemetrySm,
                                ),
                                const SizedBox(width: 20),
                                Text('${act.calories} kcal', style: AppTypography.telemetrySm),
                                const SizedBox(width: 10),
                                Icon(CupertinoIcons.chevron_right, size: 14, color: AppColors.outline),
                              ],
                            ),
                          ),
                        ),
                        if (!isLast) Divider(height: 1, color: AppColors.borderDivider),
                      ],
                    );
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
