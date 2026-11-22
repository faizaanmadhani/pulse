import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Native macOS SF Pro typography scale with tabular figures for numeric alignment.
class AppTypography {
  static const String systemFont = '.AppleSystemUIFont';

  static TextStyle get displayHero => TextStyle(
        fontFamily: systemFont,
        fontSize: 26,
        height: 1.2,
        fontWeight: FontWeight.w700,
        color: AppColors.onSurface,
        letterSpacing: -0.4,
      );

  static TextStyle get headlineLg => TextStyle(
        fontFamily: systemFont,
        fontSize: 20,
        height: 1.25,
        fontWeight: FontWeight.w600,
        color: AppColors.onSurface,
        letterSpacing: -0.3,
      );

  static TextStyle get headlineMd => TextStyle(
        fontFamily: systemFont,
        fontSize: 15,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: AppColors.onSurface,
        letterSpacing: -0.1,
      );

  static TextStyle get headlineSm => TextStyle(
        fontFamily: systemFont,
        fontSize: 13,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: AppColors.onSurface,
      );

  static TextStyle get bodyLg => TextStyle(
        fontFamily: systemFont,
        fontSize: 14,
        height: 1.4,
        fontWeight: FontWeight.w400,
        color: AppColors.onSurface,
      );

  static TextStyle get bodyMd => TextStyle(
        fontFamily: systemFont,
        fontSize: 13,
        height: 1.35,
        fontWeight: FontWeight.w400,
        color: AppColors.onSurfaceVariant,
      );

  static TextStyle get bodySm => TextStyle(
        fontFamily: systemFont,
        fontSize: 11.5,
        height: 1.35,
        fontWeight: FontWeight.w400,
        color: AppColors.outline,
      );

  // Tabular numeric styles (SF Pro with tabular figures — clean macOS look, not monospace terminal)
  static TextStyle get telemetryHero => TextStyle(
        fontFamily: systemFont,
        fontSize: 24,
        height: 1.15,
        fontWeight: FontWeight.w700,
        color: AppColors.onSurface,
        letterSpacing: -0.5,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static TextStyle get telemetryLg => TextStyle(
        fontFamily: systemFont,
        fontSize: 17,
        height: 1.2,
        fontWeight: FontWeight.w600,
        color: AppColors.onSurface,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static TextStyle get telemetryMd => TextStyle(
        fontFamily: systemFont,
        fontSize: 13,
        height: 1.25,
        fontWeight: FontWeight.w500,
        color: AppColors.onSurface,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static TextStyle get telemetrySm => TextStyle(
        fontFamily: systemFont,
        fontSize: 11.5,
        height: 1.25,
        fontWeight: FontWeight.w500,
        color: AppColors.onSurfaceVariant,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  // macOS Sidebar / Section Header label (subtle, readable, not sci-fi mono)
  static TextStyle get labelCaps => TextStyle(
        fontFamily: systemFont,
        fontSize: 11,
        height: 1.2,
        fontWeight: FontWeight.w600,
        color: AppColors.outline,
        letterSpacing: 0.2,
      );
}
