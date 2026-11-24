import 'package:flutter/material.dart';
import 'theme/app_colors.dart';
import 'state/app_state.dart';
import 'components/top_hud.dart';
import 'components/navigation_sidebar.dart';
import 'views/dashboard_view.dart';
import 'views/calendar_view.dart';
import 'views/training_plan_view.dart';
import 'views/scheduled_workout_detail_view.dart';
import 'views/analytics_view.dart';
import 'views/activities_view.dart';
import 'views/strength_view.dart';
import 'views/device_sync_view.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PulseTrainingApp());
}

class PulseTrainingApp extends StatefulWidget {
  final AppState? appState;

  const PulseTrainingApp({super.key, this.appState});

  @override
  State<PulseTrainingApp> createState() => _PulseTrainingAppState();
}

class _PulseTrainingAppState extends State<PulseTrainingApp> {
  late final AppState _appState;

  @override
  void initState() {
    super.initState();
    _appState = widget.appState ?? AppState();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _appState,
      builder: (context, _) {
        final isDark = _appState.isDarkMode;
        final baseTheme = isDark ? ThemeData.dark() : ThemeData.light();

        return MaterialApp(
          title: 'Pulse Training',
          debugShowCheckedModeBanner: false,
          theme: baseTheme.copyWith(
            scaffoldBackgroundColor: AppColors.surfaceLowest,
            colorScheme: (isDark ? const ColorScheme.dark() : const ColorScheme.light()).copyWith(
              surface: AppColors.surfaceContainer,
              primary: AppColors.accent,
              secondary: AppColors.bikeSecondary,
              tertiary: AppColors.runTertiary,
              error: AppColors.error,
              onSurface: AppColors.onSurface,
            ),
            dividerColor: AppColors.borderDivider,
            scrollbarTheme: ScrollbarThemeData(
              thumbColor: WidgetStateProperty.all(AppColors.outline.withOpacity(0.35)),
              radius: const Radius.circular(4),
              thickness: WidgetStateProperty.all(6),
            ),
          ),
          home: Scaffold(
            backgroundColor: AppColors.surfaceLowest,
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Native macOS full-height Sidebar
                NavigationSidebar(appState: _appState),

                // Right Content Column: Unified Toolbar + Main View
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TopHud(appState: _appState),
                      Expanded(
                        child: Container(
                          color: AppColors.surfaceLowest,
                          child: _buildActiveView(_appState.currentNavIndex),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildActiveView(int index) {
    final selectedPlannedWorkout = _appState.selectedPlannedWorkout;
    if (selectedPlannedWorkout != null) {
      return ScheduledWorkoutDetailView(
        workout: selectedPlannedWorkout,
        appState: _appState,
      );
    }

    switch (index) {
      case 0:
        return DashboardView(appState: _appState);
      case 1:
        return CalendarView(appState: _appState);
      case 2:
        return TrainingPlanView(appState: _appState);
      case 3:
        return AnalyticsView(appState: _appState);
      case 4:
        return ActivitiesView(appState: _appState);
      case 5:
        return StrengthView(appState: _appState);
      case 6:
        return DeviceSyncView(appState: _appState);
      default:
        return DashboardView(appState: _appState);
    }
  }
}
