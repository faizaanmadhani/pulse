import '../models/activity.dart';
import '../models/gear_item.dart';
import '../models/strava_enrichment.dart';

/// Aggregates shoe, bike, and equipment mileage from Garmin activities and
/// Strava activity enrichments, with automatic categorization and wear alerts.
class GearTrackerService {
  GearTrackerService._();

  static const List<String> _shoeKeywords = [
    'vaporfly',
    'alphafly',
    'pegasus',
    'hoka',
    'asics',
    'brooks',
    'saucony',
    'altra',
    'shoe',
    'sneaker',
    'clifton',
    'endorphin',
    'novablast',
    'superblast',
    'metaspeed',
    'nimbus',
    'kayano',
    'adios',
    'kinvara',
    'ghost',
    'glycerin',
    'invincible',
    'vomero',
    'zoom fly',
    'cloudboom',
    'fuelcell',
    'fresh foam',
  ];

  static const List<String> _bikeKeywords = [
    'cervélo',
    'cervelo',
    'trek',
    'specialized',
    'canyon',
    'pinarello',
    'bike',
    'bicycle',
    'kickr',
    'wahoo',
    'tacx',
    's-works',
    'tarmac',
    'aeroad',
    'madone',
    'domane',
    'emonda',
    'dogma',
    'cannondale',
    'giant',
    'scott',
    'bmc',
    'bianchi',
    'colnago',
    'factor',
    'orbea',
    'felt',
    'argon',
    'smart trainer',
    'bike trainer',
    'gravel',
  ];

  /// Computes a sorted inventory of [GearItem]s from [activities] and
  /// [stravaEnrichments] (keyed by [Activity.id]).
  ///
  /// For each activity, prefers `stravaEnrichments[act.id]?.gearName` when
  /// non-empty, otherwise falls back to `act.gearName`.
  ///
  /// Optional [customMaxKm] overrides default replacement limits keyed by gear
  /// name (case-sensitive or lowercase) or generated gear id.
  static List<GearItem> computeGearInventory(
    List<Activity> activities,
    Map<String, StravaActivityEnrichment> stravaEnrichments, {
    Map<String, double>? customMaxKm,
  }) {
    final Map<String, _GearAccumulator> accumulators = {};

    for (final act in activities) {
      final stravaGear = stravaEnrichments[act.id]?.gearName?.trim();
      final garminGear = act.gearName?.trim();

      final hasStravaGear = stravaGear != null && stravaGear.isNotEmpty;
      final hasGarminGear = garminGear != null && garminGear.isNotEmpty;

      if (!hasStravaGear && !hasGarminGear) {
        continue;
      }

      final resolvedName = hasStravaGear ? stravaGear : garminGear!;
      final key = resolvedName.toLowerCase();

      final acc = accumulators.putIfAbsent(
        key,
        () => _GearAccumulator(
          id: _buildGearId(key),
          displayName: resolvedName,
        ),
      );

      if (hasStravaGear) {
        acc.hasStrava = true;
        // Prefer Strava's canonical casing if Garmin created the bucket first.
        acc.displayName = stravaGear;
        if (hasGarminGear && garminGear.toLowerCase() == key) {
          acc.hasGarmin = true;
        }
      } else if (hasGarminGear) {
        acc.hasGarmin = true;
      }

      final safeDistance =
          (act.distanceKm.isFinite && act.distanceKm > 0) ? act.distanceKm : 0.0;
      acc.totalDistanceKm += safeDistance;
      acc.activityCount += 1;

      if (acc.lastUsedAt == null || act.timestamp.isAfter(acc.lastUsedAt!)) {
        acc.lastUsedAt = act.timestamp;
      }

      if (act.discipline == SportDiscipline.run) {
        acc.runCount += 1;
      } else if (act.discipline == SportDiscipline.bike ||
          act.discipline == SportDiscipline.indoorBike) {
        acc.bikeCount += 1;
      }
    }

    // Build normalized lookup map for customMaxKm overrides.
    final Map<String, double> normalizedCustomMax = {};
    if (customMaxKm != null) {
      for (final entry in customMaxKm.entries) {
        if (entry.value.isFinite && entry.value > 0) {
          normalizedCustomMax[entry.key.trim().toLowerCase()] = entry.value;
        }
      }
    }

    final items = accumulators.entries.map((entry) {
      final key = entry.key;
      final acc = entry.value;
      final category = classifyCategory(
        acc.displayName,
        runCount: acc.runCount,
        bikeCount: acc.bikeCount,
      );

      final customLimit = customMaxKm?[acc.displayName] ??
          normalizedCustomMax[key] ??
          normalizedCustomMax[acc.id.toLowerCase()];

      final source = (acc.hasGarmin && acc.hasStrava)
          ? 'Garmin + Strava'
          : (acc.hasStrava ? 'Strava' : 'Garmin');

      return GearItem(
        id: acc.id,
        name: acc.displayName,
        category: category,
        totalDistanceKm: acc.totalDistanceKm,
        maxDistanceKm: customLimit,
        activityCount: acc.activityCount,
        lastUsedAt: acc.lastUsedAt,
        source: source,
      );
    }).toList();

    items.sort((a, b) {
      final priorityCompare =
          _alertPriority(a.alertLevel).compareTo(_alertPriority(b.alertLevel));
      if (priorityCompare != 0) return priorityCompare;

      final distanceCompare = b.totalDistanceKm.compareTo(a.totalDistanceKm);
      if (distanceCompare != 0) return distanceCompare;

      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return items;
  }

  /// Auto-classifies a gear item into [GearCategory.shoes], [GearCategory.bike],
  /// or [GearCategory.other] using keyword matching first, then activity
  /// discipline counts.
  static GearCategory classifyCategory(
    String gearName, {
    int runCount = 0,
    int bikeCount = 0,
  }) {
    final lower = gearName.toLowerCase();

    for (final keyword in _shoeKeywords) {
      if (lower.contains(keyword)) {
        return GearCategory.shoes;
      }
    }
    for (final keyword in _bikeKeywords) {
      if (lower.contains(keyword)) {
        return GearCategory.bike;
      }
    }

    if (runCount > 0 && runCount >= bikeCount) {
      return GearCategory.shoes;
    }
    if (bikeCount > 0) {
      return GearCategory.bike;
    }

    return GearCategory.other;
  }

  static int _alertPriority(GearAlertLevel level) {
    switch (level) {
      case GearAlertLevel.replace:
        return 0;
      case GearAlertLevel.warning:
        return 1;
      case GearAlertLevel.ok:
        return 2;
    }
  }

  static String _buildGearId(String normalizedName) {
    final slug = normalizedName
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return slug.isEmpty ? 'gear_unknown' : 'gear_$slug';
  }
}

class _GearAccumulator {
  final String id;
  String displayName;
  double totalDistanceKm = 0.0;
  int activityCount = 0;
  DateTime? lastUsedAt;
  bool hasStrava = false;
  bool hasGarmin = false;
  int runCount = 0;
  int bikeCount = 0;

  _GearAccumulator({
    required this.id,
    required this.displayName,
  });
}
