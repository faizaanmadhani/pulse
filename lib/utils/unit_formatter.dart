import 'package:intl/intl.dart';

import '../models/activity.dart';

/// Global measurement system preference for distances, elevations, speeds, and paces.
enum UnitSystem {
  metric,
  imperial,
}

/// Centralized unit conversion and formatting utilities for metric and imperial displays.
class UnitFormatter {
  UnitFormatter._();

  static const double kmToMiles = 0.621371;
  static const double metersToFeet = 3.28084;
  static const double metersToYards = 1.09361;

  static final NumberFormat _intFormat = NumberFormat('#,##0', 'en_US');

  /// Converts a distance stored in kilometers into the target [unit].
  ///
  /// For non-swim activities, returns kilometers (metric) or miles (imperial).
  /// For swim activities ([isSwim] == true), returns meters (metric) or yards (imperial).
  static double convertDistance(
    double km,
    UnitSystem unit, {
    bool isSwim = false,
  }) {
    final safeKm = km.isFinite ? km : 0.0;
    if (isSwim) {
      final meters = safeKm * 1000.0;
      return unit == UnitSystem.metric ? meters : meters * metersToYards;
    }
    return unit == UnitSystem.metric ? safeKm : safeKm * kmToMiles;
  }

  /// Formats a distance stored in kilometers for display in [unit].
  ///
  /// Examples:
  /// - Metric run/bike: `'10.2 km'`
  /// - Imperial run/bike: `'6.3 mi'`
  /// - Metric swim: `'1,500 m'`
  /// - Imperial swim: `'1,640 yd'`
  static String formatDistance(
    double km,
    UnitSystem unit, {
    SportDiscipline? discipline,
    int decimals = 1,
  }) {
    final isSwim = discipline == SportDiscipline.swim;
    final converted = convertDistance(km, unit, isSwim: isSwim);
    final label = distanceUnitLabel(unit, isSwim: isSwim);

    if (isSwim) {
      return '${_intFormat.format(converted.round())} $label';
    }

    final safeDecimals = decimals < 0 ? 0 : decimals;
    final formatted = _formatDecimal(converted, safeDecimals);
    return '$formatted $label';
  }

  /// Formats an elevation value stored in meters as whole meters (`'914 m'`)
  /// or whole feet (`'2,999 ft'`).
  static String formatElevation(double meters, UnitSystem unit) {
    final safeMeters = meters.isFinite ? meters : 0.0;
    final converted =
        unit == UnitSystem.metric ? safeMeters : safeMeters * metersToFeet;
    return '${_intFormat.format(converted.round())} ${elevationUnitLabel(unit)}';
  }

  /// Formats pace or speed from meters per second ([speedMps]) for the given [discipline]
  /// and [unit].
  ///
  /// - Bike / IndoorBike: `'32.4 km/h'` or `'20.1 mph'`
  /// - Swim: `'1:40 /100m'` or `'1:31 /100yd'`
  /// - Run: `'4:30 /km'` or `'7:15 /mi'`
  /// - Strength (or non-positive/non-finite speed): `'—'`
  static String formatPaceOrSpeed(
    SportDiscipline discipline,
    double speedMps,
    UnitSystem unit,
  ) {
    if (discipline == SportDiscipline.strength) {
      return '—';
    }
    if (!speedMps.isFinite || speedMps <= 0) {
      return '—';
    }

    switch (discipline) {
      case SportDiscipline.bike:
      case SportDiscipline.indoorBike:
        final speedKmh = speedMps * 3.6;
        final displaySpeed =
            unit == UnitSystem.metric ? speedKmh : speedKmh * kmToMiles;
        return '${displaySpeed.toStringAsFixed(1)} ${speedUnitLabel(unit)}';

      case SportDiscipline.swim:
        final secondsPer100 = unit == UnitSystem.metric
            ? 100.0 / speedMps
            : 100.0 / (speedMps * metersToYards);
        return '${_formatPaceMinutesSeconds(secondsPer100)} ${paceUnitLabel(unit, isSwim: true)}';

      case SportDiscipline.run:
        final secondsPerUnit = unit == UnitSystem.metric
            ? 1000.0 / speedMps
            : 1000.0 / (speedMps * kmToMiles);
        return '${_formatPaceMinutesSeconds(secondsPerUnit)} ${paceUnitLabel(unit)}';

      case SportDiscipline.strength:
        return '—';
    }
  }

  /// Computes average speed from [distanceKm] and [durationSeconds] and delegates
  /// to [formatPaceOrSpeed].
  static String formatPaceFromDistanceAndDuration(
    SportDiscipline discipline,
    double distanceKm,
    double durationSeconds,
    UnitSystem unit,
  ) {
    if (discipline == SportDiscipline.strength) {
      return '—';
    }
    if (!distanceKm.isFinite ||
        !durationSeconds.isFinite ||
        distanceKm <= 0 ||
        durationSeconds <= 0) {
      return '—';
    }
    final speedMps = (distanceKm * 1000.0) / durationSeconds;
    return formatPaceOrSpeed(discipline, speedMps, unit);
  }

  /// Formats a strength session duration in seconds as an unambiguous string
  /// such as `'0 min'`, `'45 min'`, `'1h'`, or `'1h 15m'` (never `'0m'`).
  static String formatStrengthDuration(double seconds) {
    if (!seconds.isFinite || seconds <= 0) {
      return '0 min';
    }
    final totalMinutes = (seconds / 60.0).round();
    if (totalMinutes <= 0) {
      return '0 min';
    }
    if (totalMinutes < 60) {
      return '$totalMinutes min';
    }
    final hours = totalMinutes ~/ 60;
    final remMinutes = totalMinutes % 60;
    if (remMinutes == 0) {
      return '${hours}h';
    }
    return '${hours}h ${remMinutes}m';
  }

  /// Formats a percentage value cleanly to avoid floating-point artifacts
  /// (e.g. `8.489999771118164` -> `'8.5%'`).
  static String formatPercent(double value, {int decimals = 1}) {
    final safeValue = value.isFinite ? value : 0.0;
    final safeDecimals = decimals < 0 ? 0 : decimals;
    return '${safeValue.toStringAsFixed(safeDecimals)}%';
  }

  /// Returns the distance unit label (`'km'`/`'mi'` or `'m'`/`'yd'` for swim).
  static String distanceUnitLabel(UnitSystem unit, {bool isSwim = false}) {
    if (isSwim) {
      return unit == UnitSystem.metric ? 'm' : 'yd';
    }
    return unit == UnitSystem.metric ? 'km' : 'mi';
  }

  /// Returns the elevation unit label (`'m'` or `'ft'`).
  static String elevationUnitLabel(UnitSystem unit) {
    return unit == UnitSystem.metric ? 'm' : 'ft';
  }

  /// Returns the speed unit label (`'km/h'` or `'mph'`).
  static String speedUnitLabel(UnitSystem unit) {
    return unit == UnitSystem.metric ? 'km/h' : 'mph';
  }

  /// Returns the pace unit label (`'/km'`/`'/mi'` or `'/100m'`/`'/100yd'` for swim).
  static String paceUnitLabel(UnitSystem unit, {bool isSwim = false}) {
    if (isSwim) {
      return unit == UnitSystem.metric ? '/100m' : '/100yd';
    }
    return unit == UnitSystem.metric ? '/km' : '/mi';
  }

  static String _formatDecimal(double value, int decimals) {
    if (decimals == 0) {
      return _intFormat.format(value.round());
    }
    final pattern = '#,##0.${'0' * decimals}';
    return NumberFormat(pattern, 'en_US').format(value);
  }

  static String _formatPaceMinutesSeconds(double totalSeconds) {
    final roundedSeconds = totalSeconds.round();
    final mins = roundedSeconds ~/ 60;
    final secs = roundedSeconds % 60;
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }
}
