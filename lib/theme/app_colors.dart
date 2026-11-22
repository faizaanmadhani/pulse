import 'package:flutter/material.dart';

/// Native macOS Sonoma / Sequoia Human Interface Guidelines color palette.
/// Supports both Light Mode (default) and Dark Mode without sci-fi neon colors.
class AppColors {
  static bool isDark = false;

  // Window & Surface Hierarchy
  static Color get surfaceLowest => isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F7);
  static Color get surfaceLow => isDark ? const Color(0xFF252527) : const Color(0xFFECECEF);
  static Color get surfaceContainerLow => isDark ? const Color(0xFF262628) : const Color(0xFFF2F2F5);
  static Color get surface => isDark ? const Color(0xFF202022) : const Color(0xFFF8F8FA);
  static Color get surfaceContainer => isDark ? const Color(0xFF2C2C2E) : const Color(0xFFFFFFFF);
  static Color get surfaceContainerHigh => isDark ? const Color(0xFF3A3A3C) : const Color(0xFFE5E5EA);
  static Color get surfaceContainerHighest => isDark ? const Color(0xFF48484A) : const Color(0xFFD1D1D6);
  static Color get surfaceBright => isDark ? const Color(0xFF545456) : const Color(0xFFC7C7CC);

  // Sidebar & Toolbar chrome
  static Color get sidebarBackground => isDark ? const Color(0xFF242426) : const Color(0xFFEEEFF2);
  static Color get toolbarBackground => isDark ? const Color(0xFF28282A) : const Color(0xFFFBFBFD);

  // Text & Labels (Apple HIG Label hierarchy)
  static Color get onSurface => isDark ? const Color(0xFFF5F5F7) : const Color(0xFF1D1D1F);
  static Color get onSurfaceVariant => isDark ? const Color(0xFFAEAEB2) : const Color(0xFF515154);
  static Color get outline => isDark ? const Color(0xFF8E8E93) : const Color(0xFF86868B);
  static Color get outlineVariant => isDark ? const Color(0xFF38383A) : const Color(0xFFD2D2D7);

  // System Accent (macOS Blue)
  static Color get accent => isDark ? const Color(0xFF0A84FF) : const Color(0xFF007AFF);

  // Semantic Sport Colors (Apple Health / Fitness palette)
  // Swim: Apple System Blue / Cyan
  static Color get swimPrimary => isDark ? const Color(0xFF0A84FF) : const Color(0xFF007AFF);
  static Color get swimContainer => isDark ? const Color(0xFF0A3A66) : const Color(0xFFE5F1FF);
  static Color get swimLight => isDark ? const Color(0xFF64D2FF) : const Color(0xFF0062CC);

  // Bike: Apple System Orange
  static Color get bikeSecondary => isDark ? const Color(0xFFFF9F0A) : const Color(0xFFFF9500);
  static Color get bikeContainer => isDark ? const Color(0xFF4D2E00) : const Color(0xFFFFF4E5);
  static Color get bikeLight => isDark ? const Color(0xFFFFB340) : const Color(0xFFC96A00);

  // Run: Apple System Green
  static Color get runTertiary => isDark ? const Color(0xFF30D158) : const Color(0xFF34C759);
  static Color get runContainer => isDark ? const Color(0xFF0E3D1C) : const Color(0xFFEAF9EE);
  static Color get runLight => isDark ? const Color(0xFF63E686) : const Color(0xFF1F8B3C);

  // Strength: Apple System Purple
  static Color get strengthViolet => isDark ? const Color(0xFFBF5AF2) : const Color(0xFFAF52DE);
  static Color get strengthContainer => isDark ? const Color(0xFF3B1A4F) : const Color(0xFFF6ECFC);
  static Color get strengthLight => isDark ? const Color(0xFFDA8FFF) : const Color(0xFF8931B8);

  // Status Colors
  static Color get error => isDark ? const Color(0xFFFF453A) : const Color(0xFFFF3B30);
  static Color get errorContainer => isDark ? const Color(0xFF4D1412) : const Color(0xFFFFEBEA);
  static Color get warningGold => isDark ? const Color(0xFFFFD60A) : const Color(0xFFFFB800);

  // Hairline Borders & Shadows
  static Color get borderSubtle => isDark
      ? const Color(0xFFFFFFFF).withOpacity(0.10)
      : const Color(0xFF000000).withOpacity(0.08);
  static Color get borderDivider => isDark
      ? const Color(0xFFFFFFFF).withOpacity(0.07)
      : const Color(0xFF000000).withOpacity(0.06);
  static Color get cardHighlight => isDark
      ? const Color(0xFFFFFFFF).withOpacity(0.04)
      : const Color(0xFF000000).withOpacity(0.02);
  static Color get cardShadow => isDark
      ? Colors.black.withOpacity(0.28)
      : Colors.black.withOpacity(0.05);
}
