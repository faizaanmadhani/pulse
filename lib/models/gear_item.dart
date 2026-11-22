/// Equipment category for tracked gear items.
enum GearCategory {
  shoes,
  bike,
  other,
}

/// Replacement alert severity derived from gear mileage relative to its limit.
enum GearAlertLevel {
  ok,
  warning,
  replace,
}

/// Aggregated mileage and wear state for a single piece of training gear
/// (running shoes, bicycle, trainer, etc.) synced from Garmin and/or Strava.
class GearItem {
  static const double defaultShoeMaxKm = 650.0;
  static const double defaultBikeMaxKm = 8000.0;
  static const double defaultOtherMaxKm = 1000.0;

  static const double warningThreshold = 0.80;
  static const double replaceThreshold = 1.0;

  final String id;
  final String name;
  final GearCategory category;
  final double totalDistanceKm;
  final double maxDistanceKm;
  final int activityCount;
  final DateTime? lastUsedAt;

  /// Data source label: `'Strava'`, `'Garmin'`, or `'Garmin + Strava'`.
  final String source;

  GearItem({
    required this.id,
    required this.name,
    required this.category,
    required this.totalDistanceKm,
    double? maxDistanceKm,
    required this.activityCount,
    this.lastUsedAt,
    required this.source,
  }) : maxDistanceKm = (maxDistanceKm != null &&
                maxDistanceKm.isFinite &&
                maxDistanceKm > 0)
            ? maxDistanceKm
            : defaultMaxDistanceKm(category);

  /// Default recommended replacement distance (in km) for [category].
  static double defaultMaxDistanceKm(GearCategory category) {
    switch (category) {
      case GearCategory.shoes:
        return defaultShoeMaxKm;
      case GearCategory.bike:
        return defaultBikeMaxKm;
      case GearCategory.other:
        return defaultOtherMaxKm;
    }
  }

  /// Ratio of [totalDistanceKm] to [maxDistanceKm] (unclamped; >= 1.0 when over limit).
  double get usageFraction {
    if (!totalDistanceKm.isFinite || totalDistanceKm <= 0) return 0.0;
    if (!maxDistanceKm.isFinite || maxDistanceKm <= 0) return 0.0;
    return totalDistanceKm / maxDistanceKm;
  }

  /// Remaining distance in km before reaching [maxDistanceKm], floored at 0.0.
  double get remainingKm {
    if (!maxDistanceKm.isFinite || maxDistanceKm <= 0) return 0.0;
    final safeTotal =
        (totalDistanceKm.isFinite && totalDistanceKm > 0) ? totalDistanceKm : 0.0;
    final remaining = maxDistanceKm - safeTotal;
    return remaining > 0 ? remaining : 0.0;
  }

  /// Distance in km exceeding [maxDistanceKm], or 0.0 if still within limit.
  double get overdueKm {
    if (!maxDistanceKm.isFinite || maxDistanceKm <= 0) return 0.0;
    final safeTotal =
        (totalDistanceKm.isFinite && totalDistanceKm > 0) ? totalDistanceKm : 0.0;
    final overdue = safeTotal - maxDistanceKm;
    return overdue > 0 ? overdue : 0.0;
  }

  /// Alert level: [GearAlertLevel.replace] at >= 100%, [GearAlertLevel.warning]
  /// at >= 80%, otherwise [GearAlertLevel.ok].
  GearAlertLevel get alertLevel {
    final fraction = usageFraction;
    if (fraction >= replaceThreshold) {
      return GearAlertLevel.replace;
    }
    if (fraction >= warningThreshold) {
      return GearAlertLevel.warning;
    }
    return GearAlertLevel.ok;
  }

  GearItem copyWith({
    String? id,
    String? name,
    GearCategory? category,
    double? totalDistanceKm,
    double? maxDistanceKm,
    int? activityCount,
    DateTime? lastUsedAt,
    String? source,
  }) {
    return GearItem(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      totalDistanceKm: totalDistanceKm ?? this.totalDistanceKm,
      maxDistanceKm: maxDistanceKm ?? this.maxDistanceKm,
      activityCount: activityCount ?? this.activityCount,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      source: source ?? this.source,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category.name,
        'totalDistanceKm': totalDistanceKm,
        'maxDistanceKm': maxDistanceKm,
        'activityCount': activityCount,
        'lastUsedAt': lastUsedAt?.toUtc().toIso8601String(),
        'source': source,
      };

  factory GearItem.fromJson(Map<String, dynamic> json) {
    final categoryName = (json['category'] as String?) ?? 'other';
    final category = GearCategory.values.firstWhere(
      (c) => c.name == categoryName,
      orElse: () => GearCategory.other,
    );
    final rawMax = (json['maxDistanceKm'] as num?)?.toDouble();
    final rawLastUsed = json['lastUsedAt'] as String?;

    return GearItem(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] as String?) ?? '',
      category: category,
      totalDistanceKm: (json['totalDistanceKm'] as num?)?.toDouble() ?? 0.0,
      maxDistanceKm: (rawMax != null && rawMax > 0)
          ? rawMax
          : defaultMaxDistanceKm(category),
      activityCount: (json['activityCount'] as num?)?.toInt() ?? 0,
      lastUsedAt: rawLastUsed != null ? DateTime.tryParse(rawLastUsed) : null,
      source: (json['source'] as String?) ?? 'Garmin',
    );
  }
}
