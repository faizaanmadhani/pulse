import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/activity.dart';
import '../models/gear_item.dart';
import '../models/strava_enrichment.dart';
import '../models/training_block.dart';
import '../models/performance_metrics.dart';
import '../models/device_status.dart';
import '../services/garmin_auth_store.dart';
import '../services/garmin_service.dart';
import '../services/garmin_web_auth.dart';
import '../services/gear_tracker_service.dart';
import '../services/local_data_cache.dart';
import '../services/strava_auth_store.dart';
import '../services/strava_service.dart';
import '../services/url_opener.dart';
import '../theme/app_colors.dart';
import '../utils/unit_formatter.dart';

class AppState extends ChangeNotifier {
  final GarminService _garminService;
  final GarminAuthStore _authStore;
  final GarminWebAuth _webAuth;
  final StravaService _stravaService;
  final StravaAuthStore _stravaStore;
  final LocalDataCache _dataCache;

  int _currentNavIndex = 0;
  String _searchQuery = '';
  String? _selectedActivityId;
  String _selectedTimeWindow = '6W';
  String _mapLayerFilter = 'all';
  bool _isDarkMode = false;
  UnitSystem _unitSystem = UnitSystem.metric;

  // Garmin authentication & sync state
  GarminSession? _session;
  GarminUserProfile? _userProfile;
  GarminMfaChallenge? _pendingMfa;
  bool _isAuthenticating = false;
  bool _isSyncing = false;
  String? _authError;
  String? _syncError;
  DateTime? _lastSyncedAt;

  // Strava authentication & enrichment state
  StravaSession? _stravaSession;
  bool _isSyncingStrava = false;
  String? _stravaError;
  List<StravaActivityEnrichment> _stravaActivities = [];
  Map<String, StravaActivityEnrichment> _stravaEnrichments = {};
  final Set<String> _loadedStravaDetailIds = {};
  bool _isLoadingStravaDetail = false;

  // Real synced Garmin data (empty until user signs in and syncs)
  List<Activity> activities = [];
  List<ConnectedDevice> connectedDevices = [];
  List<PmcDataPoint> pmcSeries = [];
  AthletePhysiologicalProfile profile = const AthletePhysiologicalProfile();
  List<RaceTarget> raceTargets = [];
  List<ScheduledWorkout> scheduledWorkouts = [];
  final Set<String> _loadedSplitIds = {};
  final Set<String> _loadedPolylineIds = {};
  bool _isLoadingSplits = false;
  bool _isLoadingPolylines = false;
  bool _isBackfilling = false;
  bool _backfillComplete = false;
  int _backfillGeneration = 0;

  AppState({
    GarminService? garminService,
    GarminAuthStore? authStore,
    GarminWebAuth? webAuth,
    StravaService? stravaService,
    StravaAuthStore? stravaStore,
    LocalDataCache? dataCache,
    bool autoRestoreSession = true,
  })  : _garminService = garminService ?? GarminService(),
        _authStore = authStore ?? const GarminAuthStore(),
        _webAuth = webAuth ?? const GarminWebAuth(),
        _stravaService = stravaService ?? StravaService(),
        _stravaStore = stravaStore ?? const StravaAuthStore(),
        _dataCache = dataCache ?? const LocalDataCache() {
    AppColors.isDark = _isDarkMode;
    if (autoRestoreSession) {
      restoreSession();
    }
  }

  // Getters
  int get currentNavIndex => _currentNavIndex;
  String get searchQuery => _searchQuery;
  String? get selectedActivityId => _selectedActivityId;
  String get selectedTimeWindow => _selectedTimeWindow;
  String get mapLayerFilter => _mapLayerFilter;
  bool get isDarkMode => _isDarkMode;
  UnitSystem get unitSystem => _unitSystem;
  bool get isImperial => _unitSystem == UnitSystem.imperial;

  // Strava getters
  bool get isStravaConnected => _stravaSession != null;
  bool get isSyncingStrava => _isSyncingStrava;
  bool get isLoadingStravaDetail => _isLoadingStravaDetail;
  String? get stravaError => _stravaError;
  StravaSession? get stravaSession => _stravaSession;
  int get stravaMatchedCount => _stravaEnrichments.length;

  List<GearItem> get gearInventory =>
      GearTrackerService.computeGearInventory(activities, _stravaEnrichments);

  StravaActivityEnrichment? stravaEnrichmentFor(String garminActivityId) =>
      _stravaEnrichments[garminActivityId];

  String displayTitleFor(Activity activity) {
    final strava = _stravaEnrichments[activity.id];
    if (strava != null && strava.title.trim().isNotEmpty) {
      return strava.title.trim();
    }
    return activity.title;
  }

  String formatActivityDistance(Activity activity, {int decimals = 1}) {
    if (activity.distanceKm <= 0) return '—';
    return UnitFormatter.formatDistance(
      activity.distanceKm,
      _unitSystem,
      discipline: activity.discipline,
      decimals: decimals,
    );
  }

  String formatActivityElevation(double meters) {
    return UnitFormatter.formatElevation(meters, _unitSystem);
  }

  String formatActivityPaceOrSpeed(Activity activity) {
    if (activity.distanceKm > 0 && activity.durationSeconds > 0) {
      return UnitFormatter.formatPaceFromDistanceAndDuration(
        activity.discipline,
        activity.distanceKm,
        activity.durationSeconds,
        _unitSystem,
      );
    }
    return activity.avgSpeedOrPace;
  }

  /// Collects all Strava segment PRs (rank 1-3 or KOM) across joined activities.
  List<({String activityId, String activityTitle, StravaSegmentEffort effort})>
      get stravaSegmentPrs {
    final prs = <({String activityId, String activityTitle, StravaSegmentEffort effort})>[];
    for (final entry in _stravaEnrichments.entries) {
      for (final seg in entry.value.segmentEfforts) {
        if (seg.isKom || (seg.prRank != null && seg.prRank! <= 3)) {
          prs.add((
            activityId: entry.key,
            activityTitle: entry.value.title,
            effort: seg,
          ));
        }
      }
    }
    prs.sort((a, b) {
      final aRank = a.effort.isKom ? 0 : (a.effort.prRank ?? 99);
      final bRank = b.effort.isKom ? 0 : (b.effort.prRank ?? 99);
      return aRank.compareTo(bRank);
    });
    return prs;
  }

  bool get isSignedIn => _session != null;
  bool get isAuthenticating => _isAuthenticating;
  bool get isSyncing => _isSyncing;
  bool get isLoadingSplits => _isLoadingSplits;
  bool get isLoadingPolylines => _isLoadingPolylines;
  bool get isBackfilling => _isBackfilling;
  bool get backfillComplete => _backfillComplete;

  /// Computes up to 14 daily ACWR values from the real PMC series for sparklines.
  List<double> get acwrTrend14d {
    if (pmcSeries.isEmpty) return const [];
    final tail = pmcSeries.length > 14 ? pmcSeries.sublist(pmcSeries.length - 14) : pmcSeries;
    return tail.map((pt) => pt.ctl > 0.5 ? (pt.atl / pt.ctl).clamp(0.4, 2.2) : 0.0).toList();
  }
  String? get authError => _authError;
  String? get syncError => _syncError;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  GarminUserProfile? get userProfile => _userProfile;
  GarminMfaChallenge? get pendingMfa => _pendingMfa;

  String get lastSyncedLabel {
    if (_isSyncing) return 'Syncing...';
    if (_isBackfilling) return 'Backfilling (${activities.length})...';
    if (_lastSyncedAt == null) return isSignedIn ? 'Connected' : 'Not signed in';
    final diff = DateTime.now().difference(_lastSyncedAt!);
    if (diff.inMinutes < 1) return 'Synced just now';
    if (diff.inMinutes < 60) return 'Synced ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return 'Synced ${diff.inHours}h ago';
    return 'Synced ${DateFormat('MMM d').format(_lastSyncedAt!)}';
  }

  // Real 7-day discipline volumes computed from synced Garmin activities
  List<Activity> get _last7DaysActivities {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    return activities.where((a) => a.timestamp.isAfter(cutoff)).toList();
  }

  String get swimVolume7d {
    if (!isSignedIn) return '—';
    final km = _last7DaysActivities
        .where((a) => a.discipline == SportDiscipline.swim)
        .fold<double>(0, (sum, a) => sum + a.distanceKm);
    return UnitFormatter.formatDistance(km, _unitSystem, discipline: SportDiscipline.swim);
  }

  String get bikeVolume7d {
    if (!isSignedIn) return '—';
    final km = _last7DaysActivities
        .where((a) => a.discipline == SportDiscipline.bike || a.discipline == SportDiscipline.indoorBike)
        .fold<double>(0, (sum, a) => sum + a.distanceKm);
    return UnitFormatter.formatDistance(km, _unitSystem);
  }

  String get runVolume7d {
    if (!isSignedIn) return '—';
    final km = _last7DaysActivities
        .where((a) => a.discipline == SportDiscipline.run)
        .fold<double>(0, (sum, a) => sum + a.distanceKm);
    return UnitFormatter.formatDistance(km, _unitSystem);
  }

  String get strengthVolume7d {
    if (!isSignedIn) return '—';
    final sec = _last7DaysActivities
        .where((a) => a.discipline == SportDiscipline.strength)
        .fold<double>(0, (sum, a) => sum + a.durationSeconds);
    return UnitFormatter.formatStrengthDuration(sec);
  }

  // Navigation & UI state
  void setNavIndex(int index) {
    _currentNavIndex = index;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    if (query.trim().isNotEmpty && isSignedIn) {
      _currentNavIndex = 3;
      _selectedActivityId = null;
    }
    notifyListeners();
  }

  void setSelectedActivityId(String? id) {
    _selectedActivityId = id;
    if (id != null) {
      if (_currentNavIndex != 3) {
        _currentNavIndex = 3;
      }
      loadActivitySplits(id);
      loadStravaEnrichmentDetail(id);
    }
    notifyListeners();
  }

  void setUnitSystem(UnitSystem system) {
    if (_unitSystem == system) return;
    _unitSystem = system;
    notifyListeners();
  }

  void toggleUnitSystem() {
    _unitSystem = _unitSystem == UnitSystem.metric ? UnitSystem.imperial : UnitSystem.metric;
    notifyListeners();
  }

  void setTimeWindow(String window) {
    _selectedTimeWindow = window;
    notifyListeners();
  }

  void setMapLayerFilter(String filter) {
    _mapLayerFilter = filter;
    notifyListeners();
  }

  void toggleDarkMode() {
    _isDarkMode = !_isDarkMode;
    AppColors.isDark = _isDarkMode;
    notifyListeners();
  }

  void clearAuthError() {
    _authError = null;
    notifyListeners();
  }

  void cancelMfa() {
    _pendingMfa = null;
    _authError = null;
    notifyListeners();
  }

  /// Attempts to restore previously saved Garmin & Strava sessions, local disk cache,
  /// and race goals for instant startup before refreshing in the background.
  Future<void> restoreSession() async {
    await _loadSavedRaceGoals();
    final storedStrava = await _stravaStore.load();
    if (storedStrava != null) {
      _stravaSession = storedStrava;
    }
    final stored = await _authStore.load();
    if (stored == null) {
      if (storedStrava != null) {
        notifyListeners();
      }
      return;
    }
    _session = stored.session;
    _userProfile = stored.profile;

    // Hydrate instantly from local disk cache if available
    final cached = await _dataCache.load();
    if (cached != null && cached.activities.isNotEmpty) {
      activities = cached.activities;
      connectedDevices = cached.connectedDevices;
      profile = cached.profile;
      _stravaActivities = cached.stravaActivities;
      _stravaEnrichments = Map<String, StravaActivityEnrichment>.from(cached.stravaEnrichments);
      _lastSyncedAt = cached.lastSyncedAt;
      final loadStats = TrainingLoadCalculator.computeFromActivities(activities);
      pmcSeries = loadStats.pmcSeries;
      _rebuildWeeklyScheduleFromActivities();
    }

    notifyListeners();
    await syncFromGarmin();
    if (_stravaSession != null) {
      await syncFromStrava();
    }
  }

  Future<void> _persistLocalCache() async {
    if (_session == null) return;
    try {
      await _dataCache.save(
        CachedTelemetrySnapshot(
          activities: activities,
          connectedDevices: connectedDevices,
          profile: profile,
          stravaActivities: _stravaActivities,
          stravaEnrichments: _stravaEnrichments,
          lastSyncedAt: _lastSyncedAt,
        ),
      );
    } catch (_) {
      // Non-fatal cache write failure
    }
  }

  /// Signs in to Garmin Connect using the native macOS WebKit browser window.
  /// Avoids Cloudflare blocks on sso.garmin.com and handles 2FA/MFA natively.
  Future<bool> signInWithGarminBrowser({String domain = 'garmin.com'}) async {
    if (_isAuthenticating) return false;
    _isAuthenticating = true;
    _authError = null;
    _pendingMfa = null;
    notifyListeners();

    try {
      final ticket = await _webAuth.signInWithWebView(domain: domain);
      if (ticket == null) {
        _isAuthenticating = false;
        notifyListeners();
        return false;
      }

      final session = await _garminService.loginWithTicket(
        ticket: ticket,
        domain: domain,
      );
      _session = session;
      await _authStore.save(_session!);
      await syncFromGarmin();
      _isAuthenticating = false;
      notifyListeners();
      return true;
    } catch (e) {
      _authError = e.toString();
      _isAuthenticating = false;
      notifyListeners();
      return false;
    }
  }

  /// Signs in to Garmin Connect with email & password.
  /// Returns true if fully authenticated, false if MFA is required or an error occurred.
  Future<bool> signInWithGarmin({
    required String email,
    required String password,
    String domain = 'garmin.com',
  }) async {
    if (_isAuthenticating) return false;
    _isAuthenticating = true;
    _authError = null;
    _pendingMfa = null;
    notifyListeners();

    try {
      final result = await _garminService.login(
        email: email,
        password: password,
        domain: domain,
      );

      if (result.requiresMfa) {
        _pendingMfa = result.mfaChallenge;
        _isAuthenticating = false;
        notifyListeners();
        return false;
      }

      _session = result.session;
      await _authStore.save(_session!);
      await syncFromGarmin();
      _isAuthenticating = false;
      notifyListeners();
      return true;
    } catch (e) {
      _authError = e.toString();
      _isAuthenticating = false;
      notifyListeners();
      return false;
    }
  }

  /// Completes Garmin 2FA/MFA verification with a 6-digit code.
  Future<bool> submitGarminMfa(String code) async {
    final challenge = _pendingMfa;
    if (challenge == null || _isAuthenticating) return false;

    _isAuthenticating = true;
    _authError = null;
    notifyListeners();

    try {
      final session = await _garminService.submitMfaCode(
        challenge: challenge,
        mfaCode: code,
      );
      _session = session;
      _pendingMfa = null;
      await _authStore.save(_session!);
      await syncFromGarmin();
      _isAuthenticating = false;
      notifyListeners();
      return true;
    } catch (e) {
      _authError = e.toString();
      _isAuthenticating = false;
      notifyListeners();
      return false;
    }
  }

  /// Pulls live profile, activities, devices, and health stats from Garmin Connect.
  Future<void> syncFromGarmin() async {
    if (_session == null || _isSyncing) return;

    _isSyncing = true;
    _syncError = null;
    notifyListeners();

    try {
      await _performGarminSync(allowUnauthorizedRetry: true);
    } catch (e) {
      _syncError = e.toString();
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<void> _performGarminSync({required bool allowUnauthorizedRetry}) async {
    try {
      // Refresh OAuth2 access token if near expiry
      if (_session!.isExpired) {
        _session = await _garminService.refreshOAuth2Token(_session!);
      }

      final activeSession = _session!;
      final fetchedProfile = await _garminService.fetchUserProfile(activeSession);
      _userProfile = fetchedProfile;
      await _authStore.save(activeSession, profile: fetchedProfile);

      final results = await Future.wait([
        _garminService.fetchActivities(activeSession, limit: 100),
        _garminService.fetchDevices(activeSession),
        _garminService.fetchDailyStats(activeSession, fetchedProfile.displayName, DateTime.now()),
      ]);

      final freshBatch = results[0] as List<Activity>;
      final existingById = {for (final a in activities) a.id: a};
      final mergedFresh = freshBatch.map((a) {
        final prev = existingById[a.id];
        if (prev == null) return a;
        return a.copyWith(
          splits: a.splits.isEmpty ? prev.splits : a.splits,
          routePoints: a.routePoints.isEmpty ? prev.routePoints : a.routePoints,
          deviceHardware: a.deviceHardware.isEmpty ? prev.deviceHardware : a.deviceHardware,
        );
      }).toList();

      if (freshBatch.length >= 100 && activities.isNotEmpty) {
        final freshIds = freshBatch.map((a) => a.id).toSet();
        final olderCached = activities.where((a) => !freshIds.contains(a.id)).toList();
        activities = [...mergedFresh, ...olderCached]
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      } else {
        activities = mergedFresh;
      }

      connectedDevices = results[1] as List<ConnectedDevice>;
      final dailyStats = results[2] as GarminDailyStats;

      final loadStats = TrainingLoadCalculator.computeFromActivities(activities);
      pmcSeries = loadStats.pmcSeries;

      profile = AthletePhysiologicalProfile(
        acwrRatio: loadStats.acwr,
        acwrStatus: loadStats.acwrStatus,
        ctlFitness: loadStats.ctl,
        atlFatigue: loadStats.atl,
        tsbForm: loadStats.tsb,
        restingHr: dailyStats.restingHr,
        hrvMs: dailyStats.hrvMs,
        vo2MaxEst: dailyStats.vo2Max,
        dailySteps: dailyStats.dailySteps,
        activeCalories: dailyStats.activeCalories,
      );

      _rebuildWeeklyScheduleFromActivities();
      _rematchStravaActivities();
      _loadedSplitIds.clear();
      _loadedPolylineIds.clear();
      _lastSyncedAt = DateTime.now();
      _backfillGeneration++;
      _backfillComplete = freshBatch.length < 100;
      _persistLocalCache();

      // Kick off non-blocking background fetch of GPS route polylines for the heatmap
      _prefetchRecentPolylines(activeSession);

      // If the initial batch returned a full page (100 activities), backfill the rest in the background
      if (!_backfillComplete) {
        _runBackgroundActivityBackfill(
          generation: _backfillGeneration,
          initialOffset: freshBatch.length,
        );
      }
    } on GarminUnauthorizedException {
      if (allowUnauthorizedRetry && _session != null) {
        _session = await _garminService.refreshOAuth2Token(_session!);
        await _performGarminSync(allowUnauthorizedRetry: false);
        return;
      }
      rethrow;
    }
  }

  /// Background batch runner that paginates through the user's entire Garmin Connect
  /// activity history in polite batches of 100 without blocking the UI.
  Future<void> _runBackgroundActivityBackfill({
    required int generation,
    required int initialOffset,
  }) async {
    const int pageSize = 100;
    int offset = initialOffset;
    _isBackfilling = true;
    notifyListeners();

    try {
      final seenIds = activities.map((a) => a.id).toSet();

      while (_session != null && generation == _backfillGeneration) {
        await Future.delayed(const Duration(milliseconds: 350));
        if (_session == null || generation != _backfillGeneration) break;

        if (_session!.isExpired) {
          _session = await _garminService.refreshOAuth2Token(_session!);
        }

        List<Activity> batch;
        try {
          batch = await _garminService.fetchActivities(
            _session!,
            start: offset,
            limit: pageSize,
          );
        } on GarminUnauthorizedException {
          if (_session == null || generation != _backfillGeneration) break;
          _session = await _garminService.refreshOAuth2Token(_session!);
          batch = await _garminService.fetchActivities(
            _session!,
            start: offset,
            limit: pageSize,
          );
        }

        if (_session == null || generation != _backfillGeneration) break;
        if (batch.isEmpty) {
          _backfillComplete = true;
          break;
        }

        final fresh = batch.where((a) => seenIds.add(a.id)).toList();
        if (fresh.isNotEmpty) {
          activities = [...activities, ...fresh]
            ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
          final loadStats = TrainingLoadCalculator.computeFromActivities(activities);
          pmcSeries = loadStats.pmcSeries;
          profile = AthletePhysiologicalProfile(
            acwrRatio: loadStats.acwr,
            acwrStatus: loadStats.acwrStatus,
            ctlFitness: loadStats.ctl,
            atlFatigue: loadStats.atl,
            tsbForm: loadStats.tsb,
            restingHr: profile.restingHr,
            hrvMs: profile.hrvMs,
            vo2MaxEst: profile.vo2MaxEst,
            dailySteps: profile.dailySteps,
            activeCalories: profile.activeCalories,
          );
          _rebuildWeeklyScheduleFromActivities();
          _rematchStravaActivities();
          _lastSyncedAt = DateTime.now();
          _persistLocalCache();
          notifyListeners();
        }

        offset += batch.length;
        if (batch.length < pageSize) {
          _backfillComplete = true;
          break;
        }
      }
    } catch (_) {
      // Non-fatal: keep all activities fetched so far
    } finally {
      if (generation == _backfillGeneration) {
        _isBackfilling = false;
        notifyListeners();
      }
    }
  }

  /// Fetches real GPS polylines in small parallel batches for recent GPS activities
  /// so the Dashboard Activity Heatmap renders actual Garmin routes.
  Future<void> _prefetchRecentPolylines(GarminSession session) async {
    if (_isLoadingPolylines) return;
    final candidates = activities
        .where((a) =>
            a.startLatitude != null &&
            a.startLongitude != null &&
            a.routePoints.isEmpty &&
            !_loadedPolylineIds.contains(a.id))
        .take(80)
        .toList();
    if (candidates.isEmpty) return;

    _isLoadingPolylines = true;
    notifyListeners();

    try {
      const batchSize = 4;
      for (int i = 0; i < candidates.length; i += batchSize) {
        if (_session == null) break;
        final batch = candidates.skip(i).take(batchSize).toList();
        final fetched = await Future.wait(
          batch.map((act) async {
            try {
              final pts = await _garminService.fetchActivityPolyline(session, act.id);
              return (act.id, pts);
            } catch (_) {
              return (act.id, const <GpsPoint>[]);
            }
          }),
        );

        bool changed = false;
        for (final (id, pts) in fetched) {
          _loadedPolylineIds.add(id);
          if (pts.isEmpty) continue;
          final idx = activities.indexWhere((a) => a.id == id);
          if (idx >= 0) {
            activities[idx] = activities[idx].copyWith(routePoints: pts);
            changed = true;
          }
        }
        if (changed) {
          _persistLocalCache();
          notifyListeners();
        }
      }
    } finally {
      _isLoadingPolylines = false;
      notifyListeners();
    }
  }

  /// Lazily loads missing GPS polylines for a page of visible feed activities.
  Future<void> ensurePolylinesLoaded(List<String> activityIds) async {
    final session = _session;
    if (session == null || activityIds.isEmpty) return;
    final missing = activityIds.where((id) {
      if (_loadedPolylineIds.contains(id)) return false;
      final idx = activities.indexWhere((a) => a.id == id);
      if (idx < 0) return false;
      final act = activities[idx];
      return act.routePoints.isEmpty && act.startLatitude != null && act.startLongitude != null;
    }).take(6).toList();
    if (missing.isEmpty) return;

    for (final id in missing) {
      _loadedPolylineIds.add(id);
    }

    final fetched = await Future.wait(
      missing.map((id) async {
        try {
          final pts = await _garminService.fetchActivityPolyline(
            session,
            id,
            maxPolylineSize: 120,
          );
          return (id, pts);
        } catch (_) {
          return (id, const <GpsPoint>[]);
        }
      }),
    );

    bool changed = false;
    for (final (id, pts) in fetched) {
      if (pts.isEmpty) continue;
      final idx = activities.indexWhere((a) => a.id == id);
      if (idx >= 0) {
        activities[idx] = activities[idx].copyWith(routePoints: pts);
        changed = true;
      }
    }
    if (changed) {
      _persistLocalCache();
      notifyListeners();
    }
  }

  /// Lazily fetches real lap splits from Garmin Connect when inspecting an activity.
  Future<void> loadActivitySplits(String activityId) async {
    if (_session == null || _loadedSplitIds.contains(activityId)) return;
    final idx = activities.indexWhere((a) => a.id == activityId);
    if (idx < 0) return;

    final discipline = activities[idx].discipline;
    _isLoadingSplits = true;
    notifyListeners();

    try {
      if (_session!.isExpired) {
        _session = await _garminService.refreshOAuth2Token(_session!);
      }
      List<ActivitySplit> splits;
      try {
        splits = await _garminService.fetchActivitySplits(
          _session!,
          activityId,
          discipline: discipline,
        );
      } on GarminUnauthorizedException {
        _session = await _garminService.refreshOAuth2Token(_session!);
        splits = await _garminService.fetchActivitySplits(
          _session!,
          activityId,
          discipline: discipline,
        );
      }
      _loadedSplitIds.add(activityId);
      final currentIdx = activities.indexWhere((a) => a.id == activityId);
      if (currentIdx >= 0) {
        activities[currentIdx] = activities[currentIdx].copyWith(splits: splits);
      }

      // Also load high-resolution GPS route polyline for pace-heat map if missing
      if (currentIdx >= 0 &&
          activities[currentIdx].routePoints.isEmpty &&
          activities[currentIdx].startLatitude != null &&
          !_loadedPolylineIds.contains(activityId)) {
        try {
          final pts = await _garminService.fetchActivityPolyline(
            _session!,
            activityId,
            maxPolylineSize: 240,
          );
          _loadedPolylineIds.add(activityId);
          final refreshedIdx = activities.indexWhere((a) => a.id == activityId);
          if (refreshedIdx >= 0 && pts.isNotEmpty) {
            activities[refreshedIdx] = activities[refreshedIdx].copyWith(routePoints: pts);
          }
        } catch (_) {
          // Non-fatal
        }
      }

      // Also load Garmin's real HR & Power time-in-zone telemetry if missing
      final zoneIdx = activities.indexWhere((a) => a.id == activityId);
      if (zoneIdx >= 0 &&
          activities[zoneIdx].garminHrZones == null &&
          activities[zoneIdx].garminPowerZones == null) {
        try {
          final zones = await _garminService.fetchActivityTimeInZones(
            _session!,
            activityId,
          );
          final refreshedIdx = activities.indexWhere((a) => a.id == activityId);
          if (refreshedIdx >= 0 &&
              (zones.hrZones.isNotEmpty || zones.powerZones.isNotEmpty)) {
            activities[refreshedIdx] = activities[refreshedIdx].copyWith(
              garminHrZones: zones.hrZones.isNotEmpty ? zones.hrZones : null,
              garminPowerZones:
                  zones.powerZones.isNotEmpty ? zones.powerZones : null,
            );
          }
        } catch (_) {
          // Non-fatal
        }
      }
    } catch (_) {
      // Non-fatal: activity still renders without lap splits
    } finally {
      _isLoadingSplits = false;
      notifyListeners();
    }
  }

  // ── Strava OAuth2 & Activity Enrichment ──────────────────────────────────

  void _rematchStravaActivities() {
    if (_stravaActivities.isEmpty || activities.isEmpty) return;
    final matched = StravaService.matchStravaToGarmin(activities, _stravaActivities);
    // Preserve already-fetched detail/comments on matched entries
    final merged = <String, StravaActivityEnrichment>{};
    for (final entry in matched.entries) {
      final existing = _stravaEnrichments[entry.key];
      if (existing != null &&
          existing.stravaId == entry.value.stravaId &&
          _loadedStravaDetailIds.contains(entry.key)) {
        merged[entry.key] = existing;
      } else {
        merged[entry.key] = entry.value;
      }
    }
    _stravaEnrichments = merged;
  }

  /// Connects Strava via OAuth 2.0 using a localhost callback server (`127.0.0.1:8765`).
  Future<bool> connectStravaOAuth({
    required String clientId,
    required String clientSecret,
  }) async {
    _stravaError = null;
    notifyListeners();

    try {
      const redirectUri = 'http://127.0.0.1:8765/callback';
      final authUrl = _stravaService.buildAuthorizeUrl(clientId, redirectUri);

      final code = await _stravaService.waitForOAuthCode(
        port: 8765,
        timeout: const Duration(minutes: 3),
        onServerReady: (_) async {
          await UrlOpener.openUrl(authUrl);
        },
      );

      final session = await _stravaService.exchangeAuthorizationCode(
        clientId,
        clientSecret,
        code,
      );
      _stravaSession = session;
      await _stravaStore.save(session);
      notifyListeners();
      await syncFromStrava();
      return true;
    } catch (e) {
      _stravaError = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Connects Strava directly with a personal Access Token.
  Future<bool> connectStravaAccessToken(String accessToken) async {
    final trimmed = accessToken.trim();
    if (trimmed.isEmpty) {
      _stravaError = 'Please enter a valid Strava access token.';
      notifyListeners();
      return false;
    }
    _stravaError = null;
    notifyListeners();

    try {
      final tempSession = StravaSession(
        accessToken: trimmed,
        refreshToken: '',
        expiresAt: DateTime.now().add(const Duration(hours: 6)),
        clientId: '',
        clientSecret: '',
      );
      final athlete = await _stravaService.fetchAthleteProfile(tempSession);
      final session = tempSession.copyWith(
        athleteName: athlete.name,
        athleteId: athlete.id,
      );
      _stravaSession = session;
      await _stravaStore.save(session);
      notifyListeners();
      await syncFromStrava();
      return true;
    } catch (e) {
      _stravaError = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Pulls Strava activities (up to 200 recent) and joins them to Garmin activities.
  Future<void> syncFromStrava() async {
    if (_stravaSession == null || _isSyncingStrava) return;
    _isSyncingStrava = true;
    _stravaError = null;
    notifyListeners();

    try {
      if (_stravaSession!.isExpired && _stravaSession!.canRefresh) {
        _stravaSession = await _stravaService.refreshToken(_stravaSession!);
        await _stravaStore.save(_stravaSession!);
      }

      final page1 = await _stravaService.fetchActivities(_stravaSession!, page: 1, perPage: 100);
      final all = <StravaActivityEnrichment>[...page1];
      if (page1.length == 100) {
        final page2 = await _stravaService.fetchActivities(_stravaSession!, page: 2, perPage: 100);
        all.addAll(page2);
      }

      _stravaActivities = all;
      _rematchStravaActivities();
      _persistLocalCache();
    } catch (e) {
      _stravaError = e.toString();
    } finally {
      _isSyncingStrava = false;
      notifyListeners();
    }
  }

  /// Lazily loads Strava description, gear, segment efforts, best efforts, and comments
  /// for a Garmin activity that has been matched to a Strava activity.
  Future<void> loadStravaEnrichmentDetail(String garminActivityId) async {
    final session = _stravaSession;
    final matched = _stravaEnrichments[garminActivityId];
    if (session == null || matched == null || _loadedStravaDetailIds.contains(garminActivityId)) {
      return;
    }

    _isLoadingStravaDetail = true;
    notifyListeners();

    try {
      var activeSession = session;
      if (activeSession.isExpired && activeSession.canRefresh) {
        activeSession = await _stravaService.refreshToken(activeSession);
        _stravaSession = activeSession;
        await _stravaStore.save(activeSession);
      }

      final detailFuture = _stravaService.fetchActivityDetail(activeSession, matched.stravaId);
      final commentsFuture = _stravaService.fetchActivityComments(activeSession, matched.stravaId);
      final results = await Future.wait([detailFuture, commentsFuture]);
      final detail = results[0] as StravaActivityEnrichment;
      final comments = results[1] as List<StravaComment>;

      _stravaEnrichments[garminActivityId] = detail.copyWith(
        comments: comments,
        commentCount: comments.isNotEmpty ? comments.length : detail.commentCount,
      );
      _loadedStravaDetailIds.add(garminActivityId);
    } catch (_) {
      // Non-fatal: keep summary Strava enrichment
    } finally {
      _isLoadingStravaDetail = false;
      notifyListeners();
    }
  }

  /// Disconnects Strava and clears locally saved Strava tokens and enrichments.
  Future<void> disconnectStrava() async {
    await _stravaStore.clear();
    _stravaSession = null;
    _stravaError = null;
    _stravaActivities = [];
    _stravaEnrichments = {};
    _loadedStravaDetailIds.clear();
    notifyListeners();
  }

  /// Signs out of Garmin Connect and clears all local cached tokens and data.
  Future<void> signOutGarmin() async {
    await _authStore.clear();
    await _dataCache.clear();
    _session = null;
    _userProfile = null;
    _pendingMfa = null;
    _authError = null;
    _syncError = null;
    _lastSyncedAt = null;
    _searchQuery = '';
    _backfillGeneration++;
    _isBackfilling = false;
    _backfillComplete = false;
    _loadedPolylineIds.clear();
    activities = [];
    connectedDevices = [];
    pmcSeries = [];
    scheduledWorkouts = [];
    profile = const AthletePhysiologicalProfile();
    _selectedActivityId = null;
    _loadedSplitIds.clear();
    notifyListeners();
  }

  void addRaceTarget({
    required String name,
    required RaceTier tier,
    required DateTime raceDate,
    String focusDescription = '',
  }) {
    final daysRemaining = raceDate.difference(DateTime.now()).inDays.clamp(0, 9999);
    final Color color = switch (tier) {
      RaceTier.tierA => AppColors.swimPrimary,
      RaceTier.tierB => AppColors.bikeSecondary,
      RaceTier.tierC => AppColors.runTertiary,
    };
    raceTargets.add(
      RaceTarget(
        id: 'goal-${DateTime.now().millisecondsSinceEpoch}',
        name: name.trim(),
        tier: tier,
        raceDate: raceDate,
        countdownText: '$daysRemaining days',
        daysRemaining: daysRemaining,
        focusDescription: focusDescription.trim().isEmpty
            ? DateFormat('MMM d, yyyy').format(raceDate)
            : focusDescription.trim(),
        blockProgress: (1.0 - (daysRemaining / 120.0)).clamp(0.05, 1.0),
        badgeColor: color,
      ),
    );
    raceTargets.sort((a, b) => a.raceDate.compareTo(b.raceDate));
    _persistRaceGoals();
    notifyListeners();
  }

  void removeRaceTarget(String id) {
    raceTargets.removeWhere((t) => t.id == id);
    _persistRaceGoals();
    notifyListeners();
  }

  Future<void> _persistRaceGoals() async {
    final serialized = raceTargets
        .map((t) => {
              'id': t.id,
              'name': t.name,
              'tier': t.tier.name,
              'raceDate': t.raceDate.toIso8601String(),
              'focusDescription': t.focusDescription,
            })
        .toList();
    await _authStore.saveGoals(serialized);
  }

  Future<void> _loadSavedRaceGoals() async {
    final raw = await _authStore.loadGoals();
    if (raw.isEmpty) return;
    final loaded = <RaceTarget>[];
    for (final item in raw) {
      final name = item['name']?.toString() ?? '';
      final dateStr = item['raceDate']?.toString();
      final raceDate = dateStr != null ? DateTime.tryParse(dateStr) : null;
      if (name.isEmpty || raceDate == null) continue;
      final tierName = item['tier']?.toString() ?? 'tierA';
      final tier = RaceTier.values.firstWhere(
        (t) => t.name == tierName,
        orElse: () => RaceTier.tierA,
      );
      final daysRemaining = raceDate.difference(DateTime.now()).inDays.clamp(0, 9999);
      final color = switch (tier) {
        RaceTier.tierA => AppColors.swimPrimary,
        RaceTier.tierB => AppColors.bikeSecondary,
        RaceTier.tierC => AppColors.runTertiary,
      };
      final desc = item['focusDescription']?.toString() ?? '';
      loaded.add(
        RaceTarget(
          id: item['id']?.toString() ?? 'goal-${loaded.length}',
          name: name,
          tier: tier,
          raceDate: raceDate,
          countdownText: '$daysRemaining days',
          daysRemaining: daysRemaining,
          focusDescription: desc.isEmpty ? DateFormat('MMM d, yyyy').format(raceDate) : desc,
          blockProgress: (1.0 - (daysRemaining / 120.0)).clamp(0.05, 1.0),
          badgeColor: color,
        ),
      );
    }
    loaded.sort((a, b) => a.raceDate.compareTo(b.raceDate));
    raceTargets = loaded;
    notifyListeners();
  }

  void _rebuildWeeklyScheduleFromActivities() {
    final now = DateTime.now();
    // Monday of current week
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    final sundayEnd = monday.add(const Duration(days: 7));
    const dayKeys = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

    scheduledWorkouts = activities
        .where((a) => !a.timestamp.isBefore(monday) && a.timestamp.isBefore(sundayEnd))
        .map((a) {
          final dayKey = dayKeys[(a.timestamp.weekday - 1).clamp(0, 6)];
          final tssVal = a.tss?.round() ?? ((a.durationSeconds / 3600.0) * 50.0).round();
          return ScheduledWorkout(
            id: a.id,
            title: a.title,
            discipline: a.discipline,
            durationText: '${a.movingTime}${a.distanceKm > 0 ? ' • ${a.distanceKm} km' : ''}',
            tss: tssVal,
            prescription: a.avgHr > 0 ? 'Avg HR ${a.avgHr} bpm • ${a.avgSpeedOrPace}' : a.avgSpeedOrPace,
            isCompleted: true,
            adherencePercent: 100.0,
            dayOfWeek: dayKey,
            dateText: DateFormat('MMM d').format(a.timestamp),
          );
        })
        .toList();
  }
}
