import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'activity.dart';

enum RaceTier {
  tierA, // Championship / Primary Target
  tierB, // Tune-up
  tierC, // Training Simulation / Stimulus
}

class RaceTarget {
  final String id;
  final String name;
  final RaceTier tier;
  final DateTime raceDate;
  final String countdownText;
  final int daysRemaining;
  final String focusDescription;
  final double blockProgress; // 0.0 to 1.0
  final Color badgeColor;

  const RaceTarget({
    required this.id,
    required this.name,
    required this.tier,
    required this.raceDate,
    required this.countdownText,
    required this.daysRemaining,
    required this.focusDescription,
    required this.blockProgress,
    required this.badgeColor,
  });

  String get tierLabel {
    switch (tier) {
      case RaceTier.tierA:
        return 'TIER A (CHAMPIONSHIP)';
      case RaceTier.tierB:
        return 'TIER B (TUNE-UP)';
      case RaceTier.tierC:
        return 'TIER C (STIMULUS)';
    }
  }
}

class ScheduledWorkout {
  final String id;
  final String title;
  final SportDiscipline discipline;
  final String durationText;
  final int tss;
  final String prescription;
  final bool isCompleted;
  final double adherencePercent;
  final String dayOfWeek;
  final String dateText;

  const ScheduledWorkout({
    required this.id,
    required this.title,
    required this.discipline,
    required this.durationText,
    required this.tss,
    required this.prescription,
    required this.isCompleted,
    required this.adherencePercent,
    required this.dayOfWeek,
    required this.dateText,
  });

  Color get disciplineColor {
    switch (discipline) {
      case SportDiscipline.swim:
        return AppColors.swimPrimary;
      case SportDiscipline.bike:
      case SportDiscipline.indoorBike:
        return AppColors.bikeSecondary;
      case SportDiscipline.run:
        return AppColors.runTertiary;
      case SportDiscipline.strength:
        return AppColors.strengthViolet;
    }
  }
}

class PeriodizationPhase {
  final String name;
  final String monthLabel;
  final double startFraction;
  final double widthFraction;
  final Color color;
  final String subtitle;

  const PeriodizationPhase({
    required this.name,
    required this.monthLabel,
    required this.startFraction,
    required this.widthFraction,
    required this.color,
    required this.subtitle,
  });
}
