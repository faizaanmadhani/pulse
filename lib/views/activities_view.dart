import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../state/app_state.dart';
import '../models/activity.dart';
import '../components/garmin_sign_in_dialog.dart';
import '../components/macos_ui.dart';
import 'activity_detail_view.dart';

class ActivitiesView extends StatefulWidget {
  final AppState appState;

  const ActivitiesView({super.key, required this.appState});

  @override
  State<ActivitiesView> createState() => _ActivitiesViewState();
}

class _ActivitiesViewState extends State<ActivitiesView> {
  String _activeDisciplineFilter = 'All';

  @override
  Widget build(BuildContext context) {
    if (!widget.appState.isSignedIn) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: MacEmptyState(
          icon: CupertinoIcons.list_bullet,
          title: 'Your Garmin Activities',
          message: 'Sign in with Garmin Connect to browse, search, and inspect all of your synced workouts and lap splits.',
          actionLabel: 'Sign in with Garmin',
          onAction: () => showGarminSignInDialog(context, widget.appState),
        ),
      );
    }

    final selectedId = widget.appState.selectedActivityId;
    if (selectedId != null && widget.appState.activities.isNotEmpty) {
      final act = widget.appState.activities.firstWhere(
        (a) => a.id == selectedId,
        orElse: () => widget.appState.activities.first,
      );
      return ActivityDetailView(activity: act, appState: widget.appState);
    }

    return _buildMasterActivityLog();
  }

  Widget _buildMasterActivityLog() {
    final query = widget.appState.searchQuery.toLowerCase();
    final filtered = widget.appState.activities.where((act) {
      if (_activeDisciplineFilter == 'Bike' &&
          act.discipline != SportDiscipline.bike &&
          act.discipline != SportDiscipline.indoorBike) {
        return false;
      }
      if (_activeDisciplineFilter == 'Run' && act.discipline != SportDiscipline.run) return false;
      if (_activeDisciplineFilter == 'Swim' && act.discipline != SportDiscipline.swim) return false;
      if (_activeDisciplineFilter == 'Strength' && act.discipline != SportDiscipline.strength) return false;
      if (_activeDisciplineFilter == 'Indoor' && act.discipline != SportDiscipline.indoorBike) return false;

      if (query.isNotEmpty) {
        return act.title.toLowerCase().contains(query) ||
            act.location.toLowerCase().contains(query) ||
            act.id.toLowerCase().contains(query);
      }
      return true;
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Filter bar
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              MacSegmentedControl<String>(
                items: const ['All', 'Run', 'Bike', 'Swim', 'Strength', 'Indoor'],
                selected: _activeDisciplineFilter,
                labelBuilder: (s) => s,
                dotColorBuilder: (s) => switch (s) {
                  'Bike' || 'Indoor' => AppColors.bikeSecondary,
                  'Run' => AppColors.runTertiary,
                  'Swim' => AppColors.swimPrimary,
                  'Strength' => AppColors.strengthViolet,
                  _ => null,
                },
                onChanged: (val) => setState(() => _activeDisciplineFilter = val),
              ),
              Text(
                'Showing ${filtered.length} of ${widget.appState.activities.length} activities',
                style: AppTypography.bodySm,
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Activities Table Card
          MacCard(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLowest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      SizedBox(width: 108, child: Text('Sport', style: AppTypography.labelCaps)),
                      Expanded(flex: 3, child: Text('Activity', style: AppTypography.labelCaps)),
                      Expanded(flex: 2, child: Text('Date', style: AppTypography.labelCaps)),
                      Expanded(child: Text('Distance', style: AppTypography.labelCaps)),
                      Expanded(child: Text('Time', style: AppTypography.labelCaps)),
                      Expanded(child: Text('Pace / Speed', style: AppTypography.labelCaps)),
                      Expanded(child: Text('Avg HR', style: AppTypography.labelCaps)),
                      const SizedBox(width: 24),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                if (filtered.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 36),
                    child: Center(
                      child: Text(
                        widget.appState.activities.isEmpty
                            ? 'No activities synced from Garmin Connect yet.'
                            : 'No activities match the current filter.',
                        style: AppTypography.bodyMd,
                      ),
                    ),
                  )
                else
                  ...filtered.asMap().entries.map((entry) {
                    final isLast = entry.key == filtered.length - 1;
                    return Column(
                      children: [
                        _buildActivityRow(entry.value),
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

  Widget _buildActivityRow(Activity act) {
    final (String label, Color color) = switch (act.discipline) {
      SportDiscipline.bike => ('Bike', AppColors.bikeSecondary),
      SportDiscipline.indoorBike => ('Indoor', AppColors.bikeSecondary),
      SportDiscipline.run => ('Run', AppColors.runTertiary),
      SportDiscipline.swim => ('Swim', AppColors.swimPrimary),
      SportDiscipline.strength => ('Strength', AppColors.strengthViolet),
    };

    return InkWell(
      onTap: () => widget.appState.setSelectedActivityId(act.id),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 108,
              child: Align(
                alignment: Alignment.centerLeft,
                child: MacStatusBadge(label: label, color: color),
              ),
            ),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          widget.appState.displayTitleFor(act),
                          style: AppTypography.headlineSm,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (widget.appState.stravaEnrichmentFor(act.id) != null) ...[
                        const SizedBox(width: 5),
                        const Icon(
                          CupertinoIcons.flame_fill,
                          size: 11,
                          color: Color(0xFFFC4C02),
                        ),
                      ],
                    ],
                  ),
                  if (act.location.isNotEmpty)
                    Text(
                      act.location,
                      style: AppTypography.bodySm,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                act.formattedDate.split('•').first.trim(),
                style: AppTypography.telemetrySm,
              ),
            ),
            Expanded(
              child: Text(
                widget.appState.formatActivityDistance(act),
                style: AppTypography.telemetrySm.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurface,
                ),
              ),
            ),
            Expanded(child: Text(act.movingTime, style: AppTypography.telemetrySm)),
            Expanded(
              child: Text(
                act.normPowerW != null
                    ? '${act.normPowerW} W'
                    : widget.appState.formatActivityPaceOrSpeed(act),
                style: AppTypography.telemetrySm.copyWith(color: color, fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(
              child: Text(
                act.avgHr > 0 ? '${act.avgHr} bpm' : '—',
                style: AppTypography.telemetrySm,
              ),
            ),
            SizedBox(
              width: 24,
              child: Icon(CupertinoIcons.chevron_right, size: 14, color: AppColors.outline),
            ),
          ],
        ),
      ),
    );
  }
}
