import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../components/chatgpt_connect_dialog.dart';
import '../components/macos_ui.dart';
import '../models/activity.dart';
import '../models/training_plan.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../utils/athlete_context_builder.dart';
import '../utils/unit_formatter.dart';

class TrainingPlanView extends StatefulWidget {
  final AppState appState;

  const TrainingPlanView({super.key, required this.appState});

  @override
  State<TrainingPlanView> createState() => _TrainingPlanViewState();
}

class _TrainingPlanViewState extends State<TrainingPlanView> {
  static const List<String> _raceDistances = [
    'Sprint',
    'Olympic',
    '70.3',
    '140.6',
    'Marathon',
    'Custom',
  ];
  static const List<String> _daysOfWeek = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const List<String> _limiterSports = [
    'Swim',
    'Bike',
    'Run',
    'None',
  ];
  static const List<String> _hrZoneLabels = [
    'Recovery',
    'Aerobic',
    'Tempo',
    'Threshold',
    'VO2 Max',
  ];

  AppState get appState => widget.appState;

  late final TextEditingController _raceNameController;
  late final TextEditingController _customDistanceController;
  late final TextEditingController _additionalNotesController;
  late final TextEditingController _maxHrController;
  late final TextEditingController _lthrController;
  late final TextEditingController _runPaceController;
  late final TextEditingController _swimCssController;
  late final TextEditingController _bikeFtpController;
  late final TextEditingController _chatInputController;
  late final ScrollController _chatScrollController;

  String _raceDistance = '70.3';
  String _raceDate = '';
  double _weeklyHoursBudget = 8.0;
  String _longRunDay = 'Sunday';
  String _longRideDay = 'Saturday';
  String _restDay = 'Friday';
  String _limiterSport = 'Swim';

  bool _showBuilderMode = false;
  bool _isZonesDirty = false;
  bool _seededFromPlan = false;
  late UnitSystem _lastUnitSystem;
  late AthleteZonesSnapshot _baseZones;
  double? _canonicalRunPaceSecPerKm;
  double? _canonicalSwimCssSecPer100m;

  String? _formValidationError;
  TrainingPlan? _draftPreviewPlan;
  final Set<int> _expandedWeeks = <int>{};
  String? _expandedWeeksPlanId;

  @override
  void initState() {
    super.initState();
    _lastUnitSystem = appState.unitSystem;
    _raceNameController = TextEditingController(text: 'Target Triathlon');
    _customDistanceController = TextEditingController();
    _additionalNotesController = TextEditingController();
    _maxHrController = TextEditingController();
    _lthrController = TextEditingController();
    _runPaceController = TextEditingController();
    _swimCssController = TextEditingController();
    _bikeFtpController = TextEditingController();
    _chatInputController = TextEditingController();
    _chatScrollController = ScrollController();

    final plan = appState.activeTrainingPlan;
    if (plan != null) {
      _populateFromConfig(plan.config);
      _seededFromPlan = true;
      _syncExpandedWeeksForPlan(plan);
    } else {
      _applyDerivedZones(appState.deriveAthleteZones());
    }
  }

  @override
  void didUpdateWidget(covariant TrainingPlanView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (appState.unitSystem != _lastUnitSystem) {
      // Preserve valid typed pace/CSS under the previous unit before switching.
      final prevRun = _parsePaceInputToCanonical(
        _runPaceController.text,
        unit: _lastUnitSystem,
        isSwim: false,
      );
      if (_runPaceController.text.trim().isEmpty) {
        _canonicalRunPaceSecPerKm = null;
      } else if (prevRun != null) {
        _canonicalRunPaceSecPerKm = prevRun;
      }

      final prevSwim = _parsePaceInputToCanonical(
        _swimCssController.text,
        unit: _lastUnitSystem,
        isSwim: true,
      );
      if (_swimCssController.text.trim().isEmpty) {
        _canonicalSwimCssSecPer100m = null;
      } else if (prevSwim != null) {
        _canonicalSwimCssSecPer100m = prevSwim;
      }

      _lastUnitSystem = appState.unitSystem;
      _runPaceController.text =
          _formatCanonicalPace(_canonicalRunPaceSecPerKm, isSwim: false);
      _swimCssController.text =
          _formatCanonicalPace(_canonicalSwimCssSecPer100m, isSwim: true);
    }

    final plan = appState.activeTrainingPlan;
    if (plan != null) {
      _syncExpandedWeeksForPlan(plan);
      if (!_seededFromPlan && !_showBuilderMode && !_isZonesDirty) {
        _populateFromConfig(plan.config);
        _seededFromPlan = true;
      }
    } else {
      _seededFromPlan = false;
      if (!_isZonesDirty) {
        final latestDerived = appState.deriveAthleteZones();
        if (!_zonesEqual(_baseZones, latestDerived)) {
          _applyDerivedZones(latestDerived);
        }
      }
    }
  }

  @override
  void dispose() {
    _raceNameController.dispose();
    _customDistanceController.dispose();
    _additionalNotesController.dispose();
    _maxHrController.dispose();
    _lthrController.dispose();
    _runPaceController.dispose();
    _swimCssController.dispose();
    _bikeFtpController.dispose();
    _chatInputController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  void _syncExpandedWeeksForPlan(TrainingPlan plan) {
    if (_expandedWeeksPlanId == plan.id) return;
    _expandedWeeksPlanId = plan.id;
    _expandedWeeks.clear();
    if (plan.weeks.isEmpty) return;

    final todayKey = PlannedWorkout.formatLocalDate(DateTime.now());
    int? currentWeekNum;
    for (final week in plan.weeks) {
      if (week.workouts.any((w) => w.date == todayKey)) {
        currentWeekNum = week.weekNumber;
        break;
      }
    }
    _expandedWeeks.add(plan.weeks.first.weekNumber);
    if (currentWeekNum != null) {
      _expandedWeeks.add(currentWeekNum);
    }
  }

  void _populateFromConfig(TrainingPlanConfig config) {
    _raceNameController.text =
        config.raceName.trim().isNotEmpty ? config.raceName : 'Target Triathlon';
    if (_raceDistances.contains(config.raceDistance) &&
        config.raceDistance != 'Custom') {
      _raceDistance = config.raceDistance;
      _customDistanceController.text = '';
    } else {
      _raceDistance = 'Custom';
      _customDistanceController.text = config.raceDistance;
    }
    _raceDate = config.raceDate;
    _weeklyHoursBudget = config.weeklyHoursBudget.isFinite
        ? config.weeklyHoursBudget.clamp(2.0, 30.0).toDouble()
        : 8.0;
    _longRunDay = _daysOfWeek.contains(config.longRunDay)
        ? config.longRunDay
        : 'Sunday';
    _longRideDay = _daysOfWeek.contains(config.longRideDay)
        ? config.longRideDay
        : 'Saturday';
    _restDay =
        _daysOfWeek.contains(config.restDay) ? config.restDay : 'Friday';
    _limiterSport = _limiterSports.contains(config.limiterSport)
        ? config.limiterSport
        : 'None';
    _additionalNotesController.text = config.additionalNotes ?? '';
    _applyDerivedZones(config.zones);
  }

  void _applyDerivedZones(AthleteZonesSnapshot zones) {
    _baseZones = zones;
    _canonicalRunPaceSecPerKm = zones.runThresholdPaceSecPerKm;
    _canonicalSwimCssSecPer100m = zones.swimCssSecPer100m;
    _maxHrController.text = zones.maxHr.toString();
    _lthrController.text = zones.lthr.toString();
    _runPaceController.text =
        _formatCanonicalPace(_canonicalRunPaceSecPerKm, isSwim: false);
    _swimCssController.text =
        _formatCanonicalPace(_canonicalSwimCssSecPer100m, isSwim: true);
    _bikeFtpController.text =
        zones.bikeFtpWatts != null ? zones.bikeFtpWatts.toString() : '';
  }

  void _handleResetToDerived() {
    setState(() {
      _isZonesDirty = false;
      _formValidationError = null;
      _applyDerivedZones(appState.deriveAthleteZones());
    });
  }

  bool _zonesEqual(AthleteZonesSnapshot a, AthleteZonesSnapshot b) {
    return a.maxHr == b.maxHr &&
        a.lthr == b.lthr &&
        a.runThresholdPaceSecPerKm == b.runThresholdPaceSecPerKm &&
        a.swimCssSecPer100m == b.swimCssSecPer100m &&
        a.bikeFtpWatts == b.bikeFtpWatts;
  }

  @override
  Widget build(BuildContext context) {
    final plan = appState.activeTrainingPlan;
    final zones = appState.deriveAthleteZones();
    final athleteContext = appState.deriveAthleteContext();
    final showBuilder = plan == null || _showBuilderMode;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!appState.isChatGptConnected) ...[
            _buildChatGptBanner(context),
            const SizedBox(height: 16),
          ],
          if (appState.planError != null) ...[
            _buildErrorBanner(appState.planError!),
            const SizedBox(height: 16),
          ],
          if (showBuilder)
            _buildMode1BuilderAndCoach(
              context,
              derivedZones: zones,
              athleteContext: athleteContext,
              hasActivePlan: plan != null,
            )
          else
            _buildMode2ActivePlanOverview(
              context,
              plan: plan,
              derivedZones: zones,
              athleteContext: athleteContext,
            ),
        ],
      ),
    );
  }

  Widget _buildChatGptBanner(BuildContext context) {
    return MacCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 12,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: ChatGptConnectDialog.chatGptTeal.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  CupertinoIcons.sparkles,
                  size: 20,
                  color: ChatGptConnectDialog.chatGptTeal,
                ),
              ),
              const SizedBox(width: 14),
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Connect ChatGPT for AI Triathlon Coaching',
                        style: AppTypography.headlineMd,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Sign in with ChatGPT (OAuth 2.0 + PKCE) to build, adapt, and push personalized Swim, Bike, Run & Brick plans to your Garmin watch.',
                        style: AppTypography.bodySm,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          MacPushButton(
            label: 'Connect ChatGPT',
            icon: CupertinoIcons.sparkles,
            isPrimary: true,
            onPressed: () => showChatGptConnectDialog(context, appState),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(String error) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.errorContainer,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.error.withOpacity(0.32)),
      ),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.exclamationmark_triangle_fill,
            size: 16,
            color: AppColors.error,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              error,
              style: AppTypography.bodySm.copyWith(color: AppColors.error),
            ),
          ),
          const SizedBox(width: 8),
          MacPushButton(
            label: 'Dismiss',
            onPressed: appState.clearPlanError,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Mode 1: Plan Builder / AI Coach
  // ---------------------------------------------------------------------------

  Widget _buildMode1BuilderAndCoach(
    BuildContext context, {
    required AthleteZonesSnapshot derivedZones,
    required AthleteContext athleteContext,
    required bool hasActivePlan,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasActivePlan) ...[
          MacCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      CupertinoIcons.sparkles,
                      size: 16,
                      color: ChatGptConnectDialog.chatGptTeal,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Coach & Plan Builder',
                      style: AppTypography.headlineMd,
                    ),
                  ],
                ),
                MacPushButton(
                  label: 'Back to Active Plan',
                  icon: CupertinoIcons.chevron_back,
                  onPressed: () {
                    setState(() {
                      _showBuilderMode = false;
                      _formValidationError = null;
                      _draftPreviewPlan = null;
                    });
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 900;
            final leftPane = _buildSetupAndZonesPane(context, derivedZones);
            final rightPane = _buildCoachChatAndPreviewPane(
              context,
              derivedZones: derivedZones,
              athleteContext: athleteContext,
            );

            if (isWide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 6, child: leftPane),
                  const SizedBox(width: 16),
                  Expanded(flex: 5, child: rightPane),
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                leftPane,
                const SizedBox(height: 16),
                rightPane,
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildSetupAndZonesPane(
    BuildContext context,
    AthleteZonesSnapshot derivedZones,
  ) {
    final unit = appState.unitSystem;
    final runUnitLabel = UnitFormatter.paceUnitLabel(unit, isSwim: false);
    final swimUnitLabel = UnitFormatter.paceUnitLabel(unit, isSwim: true);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MacCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    CupertinoIcons.slider_horizontal_3,
                    size: 16,
                    color: AppColors.accent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Plan Setup & Schedule',
                      style: AppTypography.headlineMd,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text('Target Event Name', style: AppTypography.headlineSm),
              const SizedBox(height: 6),
              TextField(
                controller: _raceNameController,
                style: AppTypography.bodyLg,
                decoration: _inputDecoration('Target Triathlon'),
              ),
              const SizedBox(height: 14),
              Text('Goal Race / Distance', style: AppTypography.headlineSm),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _raceDistances.map((dist) {
                  final selected = _raceDistance == dist;
                  return _choiceChip(
                    label: dist,
                    selected: selected,
                    onTap: () => setState(() => _raceDistance = dist),
                  );
                }).toList(),
              ),
              if (_raceDistance == 'Custom') ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _customDistanceController,
                  style: AppTypography.bodyLg,
                  decoration:
                      _inputDecoration('e.g. 50K Ultra or Gravel Century'),
                ),
              ],
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isTwoCol = constraints.maxWidth >= 580;
                  final dateField = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Target Race Date', style: AppTypography.headlineSm),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          MacPushButton(
                            label: _raceDate.isNotEmpty
                                ? _raceDate
                                : 'Flexible (8 Weeks)',
                            icon: CupertinoIcons.calendar,
                            onPressed: () => _pickRaceDate(context),
                          ),
                          if (_raceDate.isNotEmpty)
                            MacPushButton(
                              label: 'Flexible',
                              onPressed: () => setState(() => _raceDate = ''),
                            ),
                        ],
                      ),
                    ],
                  );

                  final hoursField = Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Text(
                            'Weekly Hours Budget',
                            style: AppTypography.headlineSm,
                          ),
                          Text(
                            '${_weeklyHoursBudget.toStringAsFixed(1)} hrs/wk',
                            style: AppTypography.telemetryMd.copyWith(
                              color: AppColors.accent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: _weeklyHoursBudget.clamp(2.0, 25.0),
                        min: 2.0,
                        max: 25.0,
                        divisions: 46,
                        activeColor: AppColors.accent,
                        onChanged: (v) {
                          setState(() {
                            _weeklyHoursBudget =
                                (v * 2).roundToDouble() / 2.0;
                          });
                        },
                      ),
                    ],
                  );

                  if (isTwoCol) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: dateField),
                        const SizedBox(width: 14),
                        Expanded(child: hoursField),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      dateField,
                      const SizedBox(height: 12),
                      hoursField,
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final threeCol = constraints.maxWidth >= 460;
                  final longRun = _dayDropdown(
                    label: 'Long Run Day',
                    value: _longRunDay,
                    onChanged: (v) {
                      if (v != null) setState(() => _longRunDay = v);
                    },
                  );
                  final longRide = _dayDropdown(
                    label: 'Long Ride Day',
                    value: _longRideDay,
                    onChanged: (v) {
                      if (v != null) setState(() => _longRideDay = v);
                    },
                  );
                  final restDay = _dayDropdown(
                    label: 'Rest Day',
                    value: _restDay,
                    onChanged: (v) {
                      if (v != null) setState(() => _restDay = v);
                    },
                  );

                  if (threeCol) {
                    return Row(
                      children: [
                        Expanded(child: longRun),
                        const SizedBox(width: 10),
                        Expanded(child: longRide),
                        const SizedBox(width: 10),
                        Expanded(child: restDay),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      longRun,
                      const SizedBox(height: 10),
                      longRide,
                      const SizedBox(height: 10),
                      restDay,
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),
              Text('Limiter / Priority Sport', style: AppTypography.headlineSm),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _limiterSports.map((sport) {
                  return _choiceChip(
                    label: sport,
                    selected: _limiterSport == sport,
                    onTap: () => setState(() => _limiterSport = sport),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              Text(
                'Additional Coach Notes (optional)',
                style: AppTypography.headlineSm,
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _additionalNotesController,
                maxLines: 2,
                style: AppTypography.bodyMd.copyWith(color: AppColors.onSurface),
                decoration: _inputDecoration(
                  'e.g. Pool access Mon/Wed/Fri, Zwift trainer indoors Tue/Thu',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        MacCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                runSpacing: 8,
                children: [
                  Text(
                    'Derived Athlete Telemetry & Zones',
                    style: AppTypography.headlineMd,
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      MacStatusBadge(
                        label: appState.isSignedIn ? 'Garmin Ready' : 'Defaults',
                        color: appState.isSignedIn
                            ? AppColors.runTertiary
                            : AppColors.outline,
                      ),
                      MacPushButton(
                        label: 'Reset to Derived',
                        icon: CupertinoIcons.arrow_counterclockwise,
                        onPressed: _handleResetToDerived,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Auto-derived from Garmin history. Edit any threshold below before generating your plan.',
                style: AppTypography.bodySm,
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final twoCol = constraints.maxWidth >= 420;
                  final fields = [
                    _zoneField(
                      label: 'Max HR (bpm)',
                      controller: _maxHrController,
                      hint: '${derivedZones.maxHr}',
                    ),
                    _zoneField(
                      label: 'LTHR (bpm)',
                      controller: _lthrController,
                      hint: '${derivedZones.lthr}',
                    ),
                    _zoneField(
                      label: 'Run Threshold ($runUnitLabel)',
                      controller: _runPaceController,
                      hint: 'e.g. 4:30',
                    ),
                    _zoneField(
                      label: 'Swim CSS ($swimUnitLabel)',
                      controller: _swimCssController,
                      hint: 'e.g. 1:45',
                    ),
                    _zoneField(
                      label: 'Bike FTP (W)',
                      controller: _bikeFtpController,
                      hint: 'Optional',
                    ),
                  ];

                  if (twoCol) {
                    return Column(
                      children: [
                        Row(
                          children: [
                            Expanded(child: fields[0]),
                            const SizedBox(width: 10),
                            Expanded(child: fields[1]),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(child: fields[2]),
                            const SizedBox(width: 10),
                            Expanded(child: fields[3]),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(child: fields[4]),
                            const SizedBox(width: 10),
                            const Expanded(child: SizedBox.shrink()),
                          ],
                        ),
                      ],
                    );
                  }

                  return Column(
                    children: [
                      for (var i = 0; i < fields.length; i++) ...[
                        fields[i],
                        if (i < fields.length - 1) const SizedBox(height: 10),
                      ],
                    ],
                  );
                },
              ),
              if (_formValidationError != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.errorContainer,
                    borderRadius: BorderRadius.circular(7),
                    border:
                        Border.all(color: AppColors.error.withOpacity(0.32)),
                  ),
                  child: Text(
                    _formValidationError!,
                    style: AppTypography.bodySm.copyWith(color: AppColors.error),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  MacPushButton(
                    label: appState.isGeneratingPlan
                        ? 'Generating Plan…'
                        : 'Generate Plan',
                    icon: CupertinoIcons.sparkles,
                    isPrimary: true,
                    isLoading: appState.isGeneratingPlan,
                    onPressed: appState.isGeneratingPlan
                        ? null
                        : () => _handleGeneratePlan(context),
                  ),
                  if (!appState.isChatGptConnected)
                    Text(
                      'Connects ChatGPT via OAuth before generating.',
                      style: AppTypography.bodySm,
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCoachChatAndPreviewPane(
    BuildContext context, {
    required AthleteZonesSnapshot derivedZones,
    required AthleteContext athleteContext,
  }) {
    final unit = appState.unitSystem;
    final runPace = derivedZones.runThresholdPaceSecPerKm;
    final swimCss = derivedZones.swimCssSecPer100m;
    final runPaceText = runPace != null && runPace.isFinite && runPace > 0
        ? UnitFormatter.formatPaceOrSpeed(
            SportDiscipline.run,
            1000.0 / runPace,
            unit,
          )
        : '—';
    final swimCssText = swimCss != null && swimCss.isFinite && swimCss > 0
        ? UnitFormatter.formatPaceOrSpeed(
            SportDiscipline.swim,
            100.0 / swimCss,
            unit,
          )
        : '—';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Grounded Athlete Telemetry Summary Card
        MacCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    CupertinoIcons.waveform_path_ecg,
                    size: 16,
                    color: AppColors.accent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Grounded Garmin Fitness Context',
                      style: AppTypography.headlineMd,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _metricTile(
                    'CTL / ATL / TSB',
                    '${athleteContext.ctl != null && athleteContext.ctl!.isFinite ? athleteContext.ctl!.toStringAsFixed(0) : '—'} / '
                        '${athleteContext.atl != null && athleteContext.atl!.isFinite ? athleteContext.atl!.toStringAsFixed(0) : '—'} / '
                        '${athleteContext.tsb != null && athleteContext.tsb!.isFinite ? athleteContext.tsb!.toStringAsFixed(0) : '—'}',
                    AppColors.accent,
                  ),
                  _metricTile(
                    '4w / 12w Volume',
                    '${athleteContext.avgWeeklyHours4w.isFinite ? athleteContext.avgWeeklyHours4w.toStringAsFixed(1) : '0.0'}h / '
                        '${athleteContext.avgWeeklyHours12w.isFinite ? athleteContext.avgWeeklyHours12w.toStringAsFixed(1) : '0.0'}h',
                    AppColors.runTertiary,
                  ),
                  _metricTile(
                    'Run / Swim / FTP',
                    '$runPaceText • $swimCssText • '
                        '${derivedZones.bikeFtpWatts != null ? '${derivedZones.bikeFtpWatts}W' : '—'}',
                    AppColors.swimPrimary,
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_draftPreviewPlan != null) ...[
          const SizedBox(height: 16),
          _buildPlanPreviewCard(_draftPreviewPlan!),
        ],
        const SizedBox(height: 16),
        _buildCoachChatCard(context),
      ],
    );
  }

  Widget _buildPlanPreviewCard(TrainingPlan preview) {
    final totalSessions = preview.allWorkouts
        .where((w) => w.archetype != WorkoutArchetype.rest)
        .length;

    return MacCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    CupertinoIcons.checkmark_seal_fill,
                    size: 16,
                    color: ChatGptConnectDialog.chatGptTeal,
                  ),
                  const SizedBox(width: 8),
                  Text('Generated Plan Preview', style: AppTypography.headlineMd),
                ],
              ),
              MacStatusBadge(
                label: '${preview.weeks.length} Weeks • $totalSessions Sessions',
                color: ChatGptConnectDialog.chatGptTeal,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(preview.name, style: AppTypography.headlineLg),
          if (preview.coachOverview.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(preview.coachOverview, style: AppTypography.bodyMd),
          ],
          const SizedBox(height: 12),
          for (final w in preview.weeks.take(4)) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.surfaceLowest,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: AppColors.borderDivider),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Week ${w.weekNumber} • ${w.phaseName}',
                      style: AppTypography.headlineSm.copyWith(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${w.targetHours.isFinite ? w.targetHours.toStringAsFixed(1) : '0.0'}h • ${w.targetTss} TSS',
                    style: AppTypography.telemetrySm,
                  ),
                ],
              ),
            ),
          ],
          if (preview.weeks.length > 4)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '+ ${preview.weeks.length - 4} more weeks included',
                style: AppTypography.bodySm,
              ),
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              MacPushButton(
                label: 'Apply Plan to Calendar',
                icon: CupertinoIcons.checkmark_circle_fill,
                isPrimary: true,
                onPressed: () async {
                  await appState.applyGeneratedPlan(preview);
                  if (!mounted) return;
                  setState(() {
                    _draftPreviewPlan = null;
                    _showBuilderMode = false;
                    _seededFromPlan = true;
                    _isZonesDirty = false;
                  });
                },
              ),
              MacPushButton(
                label: 'Discard',
                isDestructive: true,
                onPressed: () => setState(() => _draftPreviewPlan = null),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCoachChatCard(BuildContext context) {
    final messages = appState.coachMessages;
    final starterPrompts = [
      'Prioritize swim CSS twice weekly',
      'Keep weekday sessions under 60 min',
      'Include a Saturday brick session',
    ];

    return MacCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    CupertinoIcons.chat_bubble_2_fill,
                    size: 16,
                    color: ChatGptConnectDialog.chatGptTeal,
                  ),
                  const SizedBox(width: 8),
                  Text('AI Triathlon Coach Chat', style: AppTypography.headlineMd),
                ],
              ),
              if (appState.isSendingCoachMessage)
                const CupertinoActivityIndicator(radius: 7),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 340,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.surfaceLowest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.borderDivider),
            ),
            child: messages.isEmpty
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        CupertinoIcons.sparkles,
                        size: 24,
                        color: ChatGptConnectDialog.chatGptTeal,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Collaborate with your ChatGPT Coach before generating your plan.',
                        style: AppTypography.bodyMd,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: starterPrompts.map((prompt) {
                          return InkWell(
                            onTap: () => _handleSendCoachMessage(
                              context,
                              overrideText: prompt,
                            ),
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceContainer,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppColors.borderSubtle),
                              ),
                              child: Text(
                                prompt,
                                style: AppTypography.bodySm.copyWith(
                                  color: AppColors.onSurface,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  )
                : ListView.separated(
                    controller: _chatScrollController,
                    physics: const ClampingScrollPhysics(),
                    itemCount: messages.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      return _buildChatBubble(msg);
                    },
                  ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _chatInputController,
                  enabled: !appState.isSendingCoachMessage,
                  style: AppTypography.bodyMd.copyWith(color: AppColors.onSurface),
                  decoration: _inputDecoration(
                    'Ask the coach to adjust volume, brick timing, or swim focus…',
                  ),
                  onSubmitted: (_) => _handleSendCoachMessage(context),
                ),
              ),
              const SizedBox(width: 8),
              MacPushButton(
                label: 'Send',
                icon: CupertinoIcons.paperplane_fill,
                isPrimary: true,
                isLoading: appState.isSendingCoachMessage,
                onPressed: appState.isSendingCoachMessage
                    ? null
                    : () => _handleSendCoachMessage(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChatBubble(CoachMessage msg) {
    final isUser = msg.role == CoachMessageRole.user;
    final align = isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final bgColor = isUser
        ? AppColors.accent.withOpacity(AppColors.isDark ? 0.24 : 0.12)
        : AppColors.surfaceContainer;
    final borderColor = isUser
        ? AppColors.accent.withOpacity(0.35)
        : AppColors.borderDivider;

    return Column(
      crossAxisAlignment: align,
      children: [
        Container(
          constraints: const BoxConstraints(maxWidth: 460),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isUser ? 'You' : 'ChatGPT Coach',
                style: AppTypography.labelCaps.copyWith(
                  color: isUser
                      ? AppColors.accent
                      : ChatGptConnectDialog.chatGptTeal,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                msg.content,
                style: AppTypography.bodyMd.copyWith(color: AppColors.onSurface),
              ),
              if (msg.proposedPlan != null) ...[
                const SizedBox(height: 10),
                MacPushButton(
                  label: 'Apply Plan to Calendar',
                  icon: CupertinoIcons.checkmark_circle_fill,
                  isPrimary: true,
                  onPressed: () async {
                    await appState.applyGeneratedPlan(msg.proposedPlan!);
                    if (!mounted) return;
                    setState(() {
                      _draftPreviewPlan = null;
                      _showBuilderMode = false;
                      _seededFromPlan = true;
                      _isZonesDirty = false;
                    });
                  },
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Mode 2: Active Plan Overview
  // ---------------------------------------------------------------------------

  Widget _buildMode2ActivePlanOverview(
    BuildContext context, {
    required TrainingPlan plan,
    required AthleteZonesSnapshot derivedZones,
    required AthleteContext athleteContext,
  }) {
    final allWorkouts = plan.allWorkouts;
    final nonRest =
        allWorkouts.where((w) => w.archetype != WorkoutArchetype.rest).toList();
    final completedList =
        nonRest.where((w) => w.status == WorkoutStatus.completed).toList();
    final syncedCount = allWorkouts.where((w) => w.isSyncedToGarmin).length;
    final adherenceValues = completedList
        .map((w) => w.adherencePercent)
        .whereType<double>()
        .where((v) => v.isFinite)
        .toList();
    final avgAdherence = adherenceValues.isNotEmpty
        ? adherenceValues.reduce((a, b) => a + b) / adherenceValues.length
        : null;

    final currentPhase = _resolveCurrentPhase(plan);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MacCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.start,
                spacing: 12,
                runSpacing: 10,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(plan.name, style: AppTypography.headlineLg),
                        const SizedBox(height: 4),
                        Text(
                          '${plan.config.raceName} • ${plan.config.raceDistance}'
                          '${plan.config.raceDate.isNotEmpty ? ' • Race ${plan.config.raceDate}' : ''}'
                          ' • ${plan.config.weeklyHoursBudget.isFinite ? plan.config.weeklyHoursBudget.toStringAsFixed(1) : '0.0'} hrs/wk',
                          style: AppTypography.bodyMd,
                        ),
                      ],
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      MacPushButton(
                        label: appState.isSyncingGarminWorkouts
                            ? 'Syncing…'
                            : 'Sync Next 2 Weeks to Garmin',
                        icon: CupertinoIcons.arrow_2_circlepath,
                        isPrimary: true,
                        isLoading: appState.isSyncingGarminWorkouts,
                        onPressed: appState.isSignedIn &&
                                !appState.isSyncingGarminWorkouts
                            ? () => appState.syncUpcomingWorkoutsToGarmin(
                                  days: 14,
                                )
                            : null,
                      ),
                      MacPushButton(
                        label: 'Adapt Remaining Plan',
                        icon: CupertinoIcons.wand_stars,
                        isLoading: appState.isGeneratingPlan,
                        onPressed: appState.isGeneratingPlan
                            ? null
                            : () => _openAdaptDialog(context),
                      ),
                      MacPushButton(
                        label: 'Coach & Plan Builder',
                        icon: CupertinoIcons.sparkles,
                        onPressed: () {
                          setState(() {
                            _populateFromConfig(plan.config);
                            _isZonesDirty = false;
                            _showBuilderMode = true;
                          });
                        },
                      ),
                    ],
                  ),
                ],
              ),
              if (plan.coachOverview.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(plan.coachOverview, style: AppTypography.bodyMd),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  MacStatusBadge(
                    label: '$currentPhase Phase',
                    color: AppColors.strengthViolet,
                  ),
                  MacStatusBadge(
                    label: '${plan.weeks.length} Weeks',
                    color: AppColors.accent,
                  ),
                  MacStatusBadge(
                    label: '${completedList.length} / ${nonRest.length} Completed',
                    color: AppColors.runTertiary,
                  ),
                  if (avgAdherence != null && avgAdherence.isFinite)
                    MacStatusBadge(
                      label: '${avgAdherence.round()}% Avg Adherence',
                      color: avgAdherence >= 85
                          ? AppColors.runTertiary
                          : AppColors.bikeSecondary,
                    ),
                  MacStatusBadge(
                    label: '$syncedCount Synced to Watch',
                    color: AppColors.swimPrimary,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildDerivedTelemetrySummaryCard(
          plan.config.zones,
          ctl: athleteContext.ctl,
          avgHours4w: athleteContext.avgWeeklyHours4w,
        ),
        const SizedBox(height: 16),
        for (final week in plan.weeks) ...[
          _buildWeekCard(week),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildDerivedTelemetrySummaryCard(
    AthleteZonesSnapshot zones, {
    double? ctl,
    double avgHours4w = 0.0,
  }) {
    final unit = appState.unitSystem;
    final runPace = zones.runThresholdPaceSecPerKm;
    final swimCss = zones.swimCssSecPer100m;
    final runPaceText = runPace != null && runPace.isFinite && runPace > 0
        ? UnitFormatter.formatPaceOrSpeed(
            SportDiscipline.run,
            1000.0 / runPace,
            unit,
          )
        : '—';
    final swimCssText = swimCss != null && swimCss.isFinite && swimCss > 0
        ? UnitFormatter.formatPaceOrSpeed(
            SportDiscipline.swim,
            100.0 / swimCss,
            unit,
          )
        : '—';

    return MacCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Derived Athlete Telemetry & Zones',
                  style: AppTypography.headlineMd,
                ),
              ),
              MacStatusBadge(
                label: appState.isSignedIn ? 'Garmin Ready' : 'Defaults',
                color: appState.isSignedIn
                    ? AppColors.runTertiary
                    : AppColors.outline,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _metricTile(
                'LTHR / Max HR',
                '${zones.lthr} / ${zones.maxHr} bpm',
                AppColors.error,
              ),
              _metricTile(
                'Run Threshold',
                runPaceText,
                AppColors.runTertiary,
              ),
              _metricTile(
                'Swim CSS',
                swimCssText,
                AppColors.swimPrimary,
              ),
              _metricTile(
                'Bike FTP',
                zones.bikeFtpWatts != null ? '${zones.bikeFtpWatts} W' : '—',
                AppColors.bikeSecondary,
              ),
              _metricTile(
                '4w Volume / CTL',
                '${avgHours4w.isFinite ? avgHours4w.toStringAsFixed(1) : '0.0'}h/wk • ${ctl != null && ctl.isFinite ? ctl.toStringAsFixed(0) : '—'}',
                AppColors.accent,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWeekCard(TrainingWeek week) {
    final isExpanded = _expandedWeeks.contains(week.weekNumber);
    final dateRangeText = _formatWeekDateRange(week);

    return MacCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedWeeks.remove(week.weekNumber);
                } else {
                  _expandedWeeks.add(week.weekNumber);
                }
              });
            },
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Week ${week.weekNumber} • ${week.phaseName}',
                          style: AppTypography.headlineMd,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (dateRangeText.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(dateRangeText, style: AppTypography.bodySm),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${week.targetHours.isFinite ? week.targetHours.toStringAsFixed(1) : '0.0'}h • ${week.targetTss} TSS',
                    style: AppTypography.telemetrySm,
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    isExpanded
                        ? CupertinoIcons.chevron_up
                        : CupertinoIcons.chevron_down,
                    size: 15,
                    color: AppColors.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            if (week.focusSummary.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(week.focusSummary, style: AppTypography.bodySm),
            ],
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                const spacing = 10.0;
                final cols = constraints.maxWidth >= 900
                    ? 3
                    : (constraints.maxWidth >= 520 ? 2 : 1);
                final itemWidth =
                    (constraints.maxWidth - spacing * (cols - 1)) / cols;
                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: week.workouts.map((w) {
                    return SizedBox(
                      width: itemWidth,
                      child: _buildWorkoutCard(w),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWorkoutCard(PlannedWorkout w) {
    final (sportColor, sportIcon) = _sportVisual(w.discipline);
    final archetypeLabel = _archetypeLabel(w.archetype);
    final unit = appState.unitSystem;
    final dt = w.scheduledDate;
    final dateStr = dt != null ? DateFormat('EEE, MMM d').format(dt) : w.date;
    final hasDist = w.estimatedDistanceKm != null &&
        w.estimatedDistanceKm!.isFinite &&
        w.estimatedDistanceKm! > 0;
    final distStr = hasDist
        ? UnitFormatter.formatDistance(
            w.estimatedDistanceKm!,
            unit,
            discipline: w.discipline,
            decimals: w.discipline == SportDiscipline.swim ? 0 : 1,
          )
        : null;

    return InkWell(
      onTap: () => appState.selectPlannedWorkout(w),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: AppColors.surfaceLowest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: w.status == WorkoutStatus.completed
                ? AppColors.runTertiary.withOpacity(0.42)
                : AppColors.borderDivider,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(sportIcon, size: 14, color: sportColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    dateStr,
                    style: AppTypography.bodySm,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (w.isSyncedToGarmin) ...[
                  const SizedBox(width: 4),
                  Tooltip(
                    message: 'Synced to Garmin Watch',
                    child: Icon(
                      CupertinoIcons.checkmark_shield_fill,
                      size: 13,
                      color: AppColors.runTertiary,
                    ),
                  ),
                ],
                if (w.status == WorkoutStatus.completed) ...[
                  const SizedBox(width: 4),
                  Icon(
                    CupertinoIcons.checkmark_circle_fill,
                    size: 13,
                    color: AppColors.runTertiary,
                  ),
                ] else if (w.status == WorkoutStatus.skipped) ...[
                  const SizedBox(width: 4),
                  Icon(
                    CupertinoIcons.xmark_circle,
                    size: 13,
                    color: AppColors.outline,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text(
              w.title,
              style: AppTypography.headlineSm.copyWith(fontSize: 12.5),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                MacStatusBadge(label: archetypeLabel, color: sportColor),
                if (w.archetype == WorkoutArchetype.brick &&
                    w.brickRunLeg != null)
                  MacStatusBadge(
                    label: '+ ${w.brickRunLeg!.estimatedDurationMinutes}m Run',
                    color: AppColors.runTertiary,
                  ),
                Text(
                  '${w.estimatedDurationMinutes}m'
                  '${distStr != null ? ' • $distStr' : ''}'
                  '${w.estimatedTss != null && w.estimatedTss!.isFinite && w.estimatedTss! > 0 ? ' • ${w.estimatedTss!.round()} TSS' : ''}',
                  style: AppTypography.telemetrySm,
                ),
                if (w.adherencePercent != null && w.adherencePercent!.isFinite)
                  MacStatusBadge(
                    label: '${w.adherencePercent!.round()}%',
                    color: w.adherencePercent! >= 85
                        ? AppColors.runTertiary
                        : AppColors.bikeSecondary,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Actions & Helpers
  // ---------------------------------------------------------------------------

  Future<void> _pickRaceDate(BuildContext context) async {
    final firstDate = DateTime(2020);
    final lastDate = DateTime(2100);
    DateTime initial = DateTime.now().add(const Duration(days: 84));
    if (_raceDate.isNotEmpty) {
      final parsed = DateTime.tryParse(_raceDate);
      if (parsed != null) initial = parsed;
    }
    if (initial.isBefore(firstDate)) {
      initial = firstDate;
    } else if (initial.isAfter(lastDate)) {
      initial = lastDate;
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    if (picked != null && mounted) {
      setState(() {
        _raceDate = PlannedWorkout.formatLocalDate(picked);
      });
    }
  }

  Future<void> _handleGeneratePlan(BuildContext context) async {
    if (!appState.isChatGptConnected) {
      await showChatGptConnectDialog(context, appState);
      return;
    }
    final config = _validateAndBuildConfig();
    if (config == null) return;

    final preview = await appState.generateTrainingPlan(
      config,
      applyImmediately: false,
    );
    if (!mounted || preview == null) return;
    setState(() {
      _draftPreviewPlan = preview;
    });
  }

  Future<void> _handleSendCoachMessage(
    BuildContext context, {
    String? overrideText,
  }) async {
    if (!appState.isChatGptConnected) {
      await showChatGptConnectDialog(context, appState);
      return;
    }
    final text = (overrideText ?? _chatInputController.text).trim();
    if (text.isEmpty) return;

    final config = _tryBuildConfigQuietly();
    if (overrideText == null) {
      _chatInputController.clear();
    }
    final ok = await appState.sendCoachChatMessage(text, config: config);
    if (!mounted || !ok) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _openAdaptDialog(BuildContext context) async {
    if (!appState.isChatGptConnected) {
      await showChatGptConnectDialog(context, appState);
      return;
    }
    appState.clearPlanError();
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => _AdaptPlanDialog(
        appState: appState,
        inputDecoration: _inputDecoration(
          'e.g. Missed Thursday run due to travel; shift intensity to next week.',
        ),
      ),
    );
    if (ok != true) {
      appState.clearPlanError();
    }
    if (ok == true && mounted) {
      setState(() {});
    }
  }

  TrainingPlanConfig? _tryBuildConfigQuietly() {
    final raceName = _raceNameController.text.trim().isNotEmpty
        ? _raceNameController.text.trim()
        : 'Target Triathlon';
    final effectiveDistance = _raceDistance == 'Custom'
        ? (_customDistanceController.text.trim().isNotEmpty
            ? _customDistanceController.text.trim()
            : 'Custom')
        : _raceDistance;
    final notes = _additionalNotesController.text.trim();
    return TrainingPlanConfig(
      raceName: raceName,
      raceDistance: effectiveDistance,
      raceDate: _raceDate,
      weeklyHoursBudget: _weeklyHoursBudget,
      longRunDay: _longRunDay,
      longRideDay: _longRideDay,
      restDay: _restDay,
      limiterSport: _limiterSport,
      zones: _buildCurrentZonesSnapshotQuietly(),
      additionalNotes: notes.isEmpty ? null : notes,
    );
  }

  AthleteZonesSnapshot _buildCurrentZonesSnapshotQuietly() {
    final maxHr =
        (int.tryParse(_maxHrController.text.trim()) ?? _baseZones.maxHr)
            .clamp(110, 230);
    final lthr =
        (int.tryParse(_lthrController.text.trim()) ?? _baseZones.lthr)
            .clamp(90, math.min(220, maxHr))
            .toInt();
    final runPace = _parsePaceInputToCanonical(
          _runPaceController.text,
          unit: appState.unitSystem,
          isSwim: false,
        ) ??
        _canonicalRunPaceSecPerKm;
    final swimCss = _parsePaceInputToCanonical(
          _swimCssController.text,
          unit: appState.unitSystem,
          isSwim: true,
        ) ??
        _canonicalSwimCssSecPer100m;
    final ftpRaw = int.tryParse(_bikeFtpController.text.trim());
    final ftp =
        (ftpRaw != null && ftpRaw >= 20 && ftpRaw <= 1000) ? ftpRaw : null;

    return AthleteZonesSnapshot(
      maxHr: maxHr,
      lthr: lthr,
      hrZones: _recomputeOrKeepHrZones(maxHr, lthr),
      runThresholdPaceSecPerKm: runPace,
      swimCssSecPer100m: swimCss,
      bikeFtpWatts: ftp,
    );
  }

  TrainingPlanConfig? _validateAndBuildConfig() {
    final raceName = _raceNameController.text.trim().isNotEmpty
        ? _raceNameController.text.trim()
        : 'Target Triathlon';
    final effectiveDistance = _raceDistance == 'Custom'
        ? _customDistanceController.text.trim()
        : _raceDistance;
    if (_raceDistance == 'Custom' && effectiveDistance.isEmpty) {
      setState(() {
        _formValidationError = 'Enter a custom race or event distance.';
      });
      return null;
    }

    final maxHr = int.tryParse(_maxHrController.text.trim());
    if (maxHr == null || maxHr < 110 || maxHr > 230) {
      setState(() {
        _formValidationError = 'Max HR must be between 110 and 230 bpm.';
      });
      return null;
    }

    final lthr = int.tryParse(_lthrController.text.trim());
    if (lthr == null || lthr < 90 || lthr > 220 || lthr > maxHr) {
      setState(() {
        _formValidationError =
            'LTHR must be between 90 and 220 bpm and cannot exceed Max HR.';
      });
      return null;
    }

    final runRaw = _runPaceController.text.trim();
    double? runCanonical;
    if (runRaw.isNotEmpty) {
      runCanonical = _parsePaceInputToCanonical(
        runRaw,
        unit: appState.unitSystem,
        isSwim: false,
      );
      if (runCanonical == null || runCanonical < 120 || runCanonical > 720) {
        setState(() {
          _formValidationError =
              'Run Threshold Pace must be formatted as m:ss (e.g. 4:30 /km or 7:15 /mi).';
        });
        return null;
      }
    }

    final swimRaw = _swimCssController.text.trim();
    double? swimCanonical;
    if (swimRaw.isNotEmpty) {
      swimCanonical = _parsePaceInputToCanonical(
        swimRaw,
        unit: appState.unitSystem,
        isSwim: true,
      );
      if (swimCanonical == null || swimCanonical < 40 || swimCanonical > 300) {
        setState(() {
          _formValidationError =
              'Swim CSS must be formatted as m:ss (e.g. 1:45 /100m or 1:36 /100yd).';
        });
        return null;
      }
    }

    final ftpRaw = _bikeFtpController.text.trim();
    int? ftpWatts;
    if (ftpRaw.isNotEmpty) {
      final parsedFtp = int.tryParse(ftpRaw);
      if (parsedFtp == null || parsedFtp < 20 || parsedFtp > 1000) {
        setState(() {
          _formValidationError = 'Bike FTP must be between 20 and 1000 W.';
        });
        return null;
      }
      ftpWatts = parsedFtp;
    }

    setState(() {
      _formValidationError = null;
      _canonicalRunPaceSecPerKm = runCanonical;
      _canonicalSwimCssSecPer100m = swimCanonical;
    });

    final zones = AthleteZonesSnapshot(
      maxHr: maxHr,
      lthr: lthr,
      hrZones: _recomputeOrKeepHrZones(maxHr, lthr),
      runThresholdPaceSecPerKm: runCanonical,
      swimCssSecPer100m: swimCanonical,
      bikeFtpWatts: ftpWatts,
    );

    final notes = _additionalNotesController.text.trim();
    return TrainingPlanConfig(
      raceName: raceName,
      raceDistance: effectiveDistance,
      raceDate: _raceDate,
      weeklyHoursBudget: _weeklyHoursBudget,
      longRunDay: _longRunDay,
      longRideDay: _longRideDay,
      restDay: _restDay,
      limiterSport: _limiterSport,
      zones: zones,
      additionalNotes: notes.isEmpty ? null : notes,
    );
  }

  List<HrZoneRange> _recomputeOrKeepHrZones(int maxHr, int lthr) {
    if (_baseZones.hrZones.length == 5 &&
        maxHr == _baseZones.maxHr &&
        lthr == _baseZones.lthr) {
      return _baseZones.hrZones;
    }
    return _buildFrielHrZones(maxHr, lthr);
  }

  static List<HrZoneRange> _buildFrielHrZones(int maxHr, int lthr) {
    final z1Low = math.min((maxHr * 0.50).round(), math.max(40, lthr - 25));
    final z1High = (lthr * 0.81)
        .round()
        .clamp(z1Low + 5, math.max(z1Low + 5, lthr - 20))
        .toInt();
    final z2Low = z1High + 1;
    final z2High = (lthr * 0.89)
        .round()
        .clamp(z2Low + 2, math.max(z2Low + 2, lthr - 12))
        .toInt();
    final z3Low = z2High + 1;
    final z3High = (lthr * 0.93)
        .round()
        .clamp(z3Low + 2, math.max(z3Low + 2, lthr - 6))
        .toInt();
    final z4Low = z3High + 1;
    final z4High = (lthr * 1.01)
        .round()
        .clamp(z4Low + 2, math.max(z4Low + 2, maxHr - 3))
        .toInt();
    final z5Low = z4High + 1;
    final z5High = math.max(z5Low + 1, maxHr);

    final bounds = <(int, int)>[
      (z1Low, z1High),
      (z2Low, z2High),
      (z3Low, z3High),
      (z4Low, z4High),
      (z5Low, z5High),
    ];

    return List<HrZoneRange>.generate(5, (i) {
      return HrZoneRange(
        zone: i + 1,
        label: _hrZoneLabels[i],
        lowBpm: bounds[i].$1,
        highBpm: bounds[i].$2,
      );
    });
  }

  double? _parsePaceInputToCanonical(
    String raw, {
    required UnitSystem unit,
    required bool isSwim,
  }) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    double? displaySeconds;
    if (trimmed.contains(':')) {
      final parts = trimmed.split(':');
      if (parts.length != 2) return null;
      final mins = int.tryParse(parts[0].trim());
      final secs = int.tryParse(parts[1].trim());
      if (mins == null || secs == null || mins < 0 || secs < 0 || secs >= 60) {
        return null;
      }
      displaySeconds = mins * 60.0 + secs.toDouble();
    } else {
      final rawSec = double.tryParse(trimmed);
      if (rawSec == null || !rawSec.isFinite || rawSec < 40) return null;
      displaySeconds = rawSec;
    }

    if (displaySeconds <= 0) return null;

    if (isSwim) {
      final canonical = unit == UnitSystem.imperial
          ? displaySeconds * AthleteZonesSnapshot.metersToYards
          : displaySeconds;
      return double.parse(canonical.toStringAsFixed(1));
    }

    final canonical = unit == UnitSystem.imperial
        ? displaySeconds * UnitFormatter.kmToMiles
        : displaySeconds;
    return double.parse(canonical.toStringAsFixed(1));
  }

  String _formatCanonicalPace(double? canonicalSec, {required bool isSwim}) {
    if (canonicalSec == null || !canonicalSec.isFinite || canonicalSec <= 0) {
      return '';
    }
    final unit = appState.unitSystem;
    final double displaySec;
    if (isSwim) {
      displaySec = unit == UnitSystem.imperial
          ? canonicalSec / AthleteZonesSnapshot.metersToYards
          : canonicalSec;
    } else {
      displaySec = unit == UnitSystem.imperial
          ? canonicalSec / UnitFormatter.kmToMiles
          : canonicalSec;
    }
    final rounded = displaySec.round();
    final mins = rounded ~/ 60;
    final secs = rounded % 60;
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  String _resolveCurrentPhase(TrainingPlan plan) {
    if (plan.weeks.isEmpty) return 'Base';
    final todayKey = PlannedWorkout.formatLocalDate(DateTime.now());
    for (final week in plan.weeks) {
      if (week.workouts.any((w) => w.date == todayKey)) {
        return week.phaseName;
      }
    }
    return plan.weeks.first.phaseName;
  }

  String _formatWeekDateRange(TrainingWeek week) {
    DateTime? start = DateTime.tryParse(week.startDate);
    if (start == null && week.workouts.isNotEmpty) {
      start = week.workouts.first.scheduledDate;
    }
    if (start == null) return '';
    final end = start.add(const Duration(days: 6));
    final fmt = DateFormat('MMM d');
    return '${fmt.format(start)} – ${fmt.format(end)}';
  }

  // ---------------------------------------------------------------------------
  // Reusable UI Building Blocks
  // ---------------------------------------------------------------------------

  Widget _zoneField({
    required String label,
    required TextEditingController controller,
    required String hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.headlineSm.copyWith(fontSize: 12)),
        const SizedBox(height: 5),
        TextField(
          controller: controller,
          style: AppTypography.telemetryMd,
          decoration: _inputDecoration(hint),
          onChanged: (_) {
            _isZonesDirty = true;
          },
        ),
      ],
    );
  }

  Widget _dayDropdown({
    required String label,
    required String value,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.headlineSm.copyWith(fontSize: 12)),
        const SizedBox(height: 5),
        DropdownButtonFormField<String>(
          value: value,
          isExpanded: true,
          dropdownColor: AppColors.surfaceContainer,
          style: AppTypography.bodyMd.copyWith(color: AppColors.onSurface),
          decoration: _inputDecoration(label),
          items: _daysOfWeek
              .map(
                (day) => DropdownMenuItem<String>(
                  value: day,
                  child: Text(day, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _choiceChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accent.withOpacity(AppColors.isDark ? 0.24 : 0.12)
              : AppColors.surfaceLowest,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.borderSubtle,
          ),
        ),
        child: Text(
          label,
          style: AppTypography.bodySm.copyWith(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? AppColors.accent : AppColors.onSurface,
          ),
        ),
      ),
    );
  }

  Widget _metricTile(String label, String value, Color accent) {
    return Container(
      constraints: const BoxConstraints(minWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderDivider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: AppTypography.bodySm),
          const SizedBox(height: 4),
          Text(
            value,
            style: AppTypography.telemetryMd.copyWith(
              color: accent,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: AppTypography.bodyMd.copyWith(color: AppColors.outline),
      filled: true,
      fillColor: AppColors.surfaceLowest,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
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
        borderSide: BorderSide(color: AppColors.accent, width: 1.5),
      ),
    );
  }

  static (Color, IconData) _sportVisual(SportDiscipline d) {
    return switch (d) {
      SportDiscipline.run => (AppColors.runTertiary, CupertinoIcons.flame),
      SportDiscipline.swim => (
          AppColors.swimPrimary,
          CupertinoIcons.drop_fill,
        ),
      SportDiscipline.bike => (
          AppColors.bikeSecondary,
          CupertinoIcons.speedometer,
        ),
      SportDiscipline.indoorBike => (
          AppColors.bikeSecondary,
          CupertinoIcons.bolt_fill,
        ),
      SportDiscipline.strength => (
          AppColors.strengthViolet,
          CupertinoIcons.sportscourt,
        ),
    };
  }

  static String _archetypeLabel(WorkoutArchetype a) {
    return switch (a) {
      WorkoutArchetype.intervals => 'Intervals',
      WorkoutArchetype.threshold => 'Threshold',
      WorkoutArchetype.easy => 'Easy',
      WorkoutArchetype.long => 'Long',
      WorkoutArchetype.zwiftRide => 'Zwift',
      WorkoutArchetype.brick => 'Brick',
      WorkoutArchetype.strength => 'Strength',
      WorkoutArchetype.rest => 'Rest',
    };
  }
}

class _AdaptPlanDialog extends StatefulWidget {
  final AppState appState;
  final InputDecoration inputDecoration;

  const _AdaptPlanDialog({
    required this.appState,
    required this.inputDecoration,
  });

  @override
  State<_AdaptPlanDialog> createState() => _AdaptPlanDialogState();
}

class _AdaptPlanDialogState extends State<_AdaptPlanDialog> {
  final _feedbackController = TextEditingController();

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.appState,
      builder: (context, _) {
        final isGenerating = widget.appState.isGeneratingPlan;
        return Dialog(
          backgroundColor: AppColors.surfaceContainer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: AppColors.borderSubtle),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(
                        CupertinoIcons.wand_stars,
                        size: 18,
                        color: ChatGptConnectDialog.chatGptTeal,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Adapt Remaining Plan',
                        style: AppTypography.headlineMd,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'ChatGPT will rebalance upcoming sessions using your adherence, completed/skipped days, and current CTL/ATL/TSB while keeping past workouts intact.',
                    style: AppTypography.bodyMd,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Adaptation Feedback (optional)',
                    style: AppTypography.headlineSm,
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _feedbackController,
                    enabled: !isGenerating,
                    maxLines: 3,
                    style:
                        AppTypography.bodyMd.copyWith(color: AppColors.onSurface),
                    decoration: widget.inputDecoration,
                  ),
                  if (widget.appState.planError != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.errorContainer,
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                          color: AppColors.error.withOpacity(0.32),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            CupertinoIcons.exclamationmark_triangle_fill,
                            size: 14,
                            color: AppColors.error,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.appState.planError!,
                              style: AppTypography.bodySm.copyWith(
                                color: AppColors.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      MacPushButton(
                        label: 'Cancel',
                        onPressed: isGenerating
                            ? null
                            : () {
                                widget.appState.clearPlanError();
                                Navigator.of(context).pop(false);
                              },
                      ),
                      const SizedBox(width: 8),
                      MacPushButton(
                        label: isGenerating ? 'Adapting…' : 'Adapt Plan',
                        icon: CupertinoIcons.wand_stars,
                        isPrimary: true,
                        isLoading: isGenerating,
                        onPressed: isGenerating
                            ? null
                            : () async {
                                final success =
                                    await widget.appState.adaptRemainingPlan(
                                  userFeedback: _feedbackController.text.trim(),
                                );
                                if (context.mounted && success) {
                                  Navigator.of(context).pop(true);
                                }
                              },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
