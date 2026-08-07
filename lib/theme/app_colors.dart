import 'package:flutter/material.dart';

/// Raw palette - electric indigo/violet with cyan as a sparing tertiary accent.
/// Nothing in this file references `ThemeData` directly; `app_theme.dart` assembles
/// these into light/dark `ColorScheme`s.
class AppColors {
  AppColors._();

  // Light
  static const lightPrimary = Color(0xFF4F46E5);
  static const lightOnPrimary = Color(0xFFFFFFFF);
  static const lightPrimaryContainer = Color(0xFFE0E7FF);
  static const lightOnPrimaryContainer = Color(0xFF312E81);
  static const lightSecondary = Color(0xFF7C3AED);
  static const lightOnSecondary = Color(0xFFFFFFFF);
  static const lightSecondaryContainer = Color(0xFFEDE9FE);
  static const lightOnSecondaryContainer = Color(0xFF4C1D95);
  static const lightTertiary = Color(0xFF06B6D4);
  static const lightOnTertiary = Color(0xFFFFFFFF);
  static const lightError = Color(0xFFDC2626);
  static const lightOnError = Color(0xFFFFFFFF);
  static const lightErrorContainer = Color(0xFFFEE2E2);
  static const lightOnErrorContainer = Color(0xFF7F1D1D);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightOnSurface = Color(0xFF171717);
  static const lightOnSurfaceVariant = Color(0xFF6B7280);
  static const lightSurfaceContainerHighest = Color(0xFFF1F1F8);
  static const lightOutline = Color(0xFFE4E4EF);
  static const lightScaffoldBackground = Color(0xFFFAFAFC);

  // Dark
  static const darkPrimary = Color(0xFF818CF8);
  static const darkOnPrimary = Color(0xFF1E1B4B);
  static const darkPrimaryContainer = Color(0xFF312E81);
  static const darkOnPrimaryContainer = Color(0xFFE0E7FF);
  static const darkSecondary = Color(0xFFA78BFA);
  static const darkOnSecondary = Color(0xFF2E1065);
  static const darkSecondaryContainer = Color(0xFF4C1D95);
  static const darkOnSecondaryContainer = Color(0xFFEDE9FE);
  static const darkTertiary = Color(0xFF22D3EE);
  static const darkOnTertiary = Color(0xFF083344);
  static const darkError = Color(0xFFF87171);
  static const darkOnError = Color(0xFF450A0A);
  static const darkErrorContainer = Color(0xFF7F1D1D);
  static const darkOnErrorContainer = Color(0xFFFEE2E2);
  static const darkSurface = Color(0xFF151520);
  static const darkOnSurface = Color(0xFFE4E4E7);
  static const darkOnSurfaceVariant = Color(0xFFA1A1AA);
  static const darkSurfaceContainerHighest = Color(0xFF1E1E2A);
  static const darkOutline = Color(0xFF2A2A38);
  static const darkScaffoldBackground = Color(0xFF0B0B12);
}
