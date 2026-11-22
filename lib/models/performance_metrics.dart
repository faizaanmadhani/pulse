class PmcDataPoint {
  final DateTime date;
  final double ctl; // Chronic Training Load (Fitness)
  final double atl; // Acute Training Load (Fatigue)
  final double tsb; // Training Stress Balance (Form)
  final double dailyTss;

  const PmcDataPoint({
    required this.date,
    required this.ctl,
    required this.atl,
    required this.tsb,
    required this.dailyTss,
  });
}

class PowerZoneDistribution {
  final String zoneName;
  final String zoneRange;
  final int minutes;
  final double percentage;
  final int colorHex;

  const PowerZoneDistribution({
    required this.zoneName,
    required this.zoneRange,
    required this.minutes,
    required this.percentage,
    required this.colorHex,
  });
}

class CriticalPowerPoint {
  final String durationLabel;
  final int durationSeconds;
  final int watts;
  final double wattsPerKg;

  const CriticalPowerPoint({
    required this.durationLabel,
    required this.durationSeconds,
    required this.watts,
    required this.wattsPerKg,
  });
}

class AthletePhysiologicalProfile {
  final double? acwrRatio;
  final String? acwrStatus;
  final double? ctlFitness;
  final double? atlFatigue;
  final double? tsbForm;
  final int? restingHr;
  final int? hrvMs;
  final int? ftpWatts;
  final double? weightKg;
  final double? vo2MaxEst;
  final int? enduranceScore;
  final int? hillScore;
  final int? dailySteps;
  final int? activeCalories;

  const AthletePhysiologicalProfile({
    this.acwrRatio,
    this.acwrStatus,
    this.ctlFitness,
    this.atlFatigue,
    this.tsbForm,
    this.restingHr,
    this.hrvMs,
    this.ftpWatts,
    this.weightKg,
    this.vo2MaxEst,
    this.enduranceScore,
    this.hillScore,
    this.dailySteps,
    this.activeCalories,
  });

  bool get hasAnyMetric =>
      acwrRatio != null ||
      ctlFitness != null ||
      restingHr != null ||
      hrvMs != null ||
      vo2MaxEst != null ||
      dailySteps != null;
}
