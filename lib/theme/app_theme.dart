import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_semantic_colors.dart';

const _fontFamily = 'Sora';

/// Builds the app's light and dark `ThemeData`. Replaces the old inline `ThemeData`
/// block that used to live directly in `main.dart` with a flat black/white palette -
/// every component theme below is rebuilt against the new indigo/violet palette, plus
/// a `TabBarThemeData` that didn't exist before (TabBars were unstyled/default).
class AppTheme {
  AppTheme._();

  static TextTheme _textTheme(Color onSurface, Color onSurfaceVariant) {
    return TextTheme(
      titleLarge: TextStyle(fontFamily: _fontFamily, fontWeight: FontWeight.w700, fontSize: 20, color: onSurface),
      titleMedium: TextStyle(fontFamily: _fontFamily, fontWeight: FontWeight.w600, fontSize: 18, color: onSurface),
      titleSmall: TextStyle(fontFamily: _fontFamily, fontWeight: FontWeight.w600, fontSize: 15, color: onSurface),
      headlineSmall: TextStyle(
        fontFamily: _fontFamily,
        fontWeight: FontWeight.w700,
        fontSize: 24,
        letterSpacing: -0.2,
        color: onSurface,
      ),
      bodyLarge: TextStyle(fontFamily: _fontFamily, fontWeight: FontWeight.w400, fontSize: 15, color: onSurface),
      bodyMedium: TextStyle(fontFamily: _fontFamily, fontWeight: FontWeight.w400, fontSize: 14, color: onSurface),
      bodySmall: TextStyle(fontFamily: _fontFamily, fontWeight: FontWeight.w400, fontSize: 12, color: onSurfaceVariant),
      labelLarge: TextStyle(fontFamily: _fontFamily, fontWeight: FontWeight.w600, fontSize: 14, color: onSurface),
      labelMedium: TextStyle(fontFamily: _fontFamily, fontWeight: FontWeight.w500, fontSize: 12, color: onSurfaceVariant),
      labelSmall: TextStyle(fontFamily: _fontFamily, fontWeight: FontWeight.w400, fontSize: 11, color: onSurfaceVariant),
    );
  }

  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.lightPrimary,
      onPrimary: AppColors.lightOnPrimary,
      primaryContainer: AppColors.lightPrimaryContainer,
      onPrimaryContainer: AppColors.lightOnPrimaryContainer,
      secondary: AppColors.lightSecondary,
      onSecondary: AppColors.lightOnSecondary,
      secondaryContainer: AppColors.lightSecondaryContainer,
      onSecondaryContainer: AppColors.lightOnSecondaryContainer,
      tertiary: AppColors.lightTertiary,
      onTertiary: AppColors.lightOnTertiary,
      error: AppColors.lightError,
      onError: AppColors.lightOnError,
      errorContainer: AppColors.lightErrorContainer,
      onErrorContainer: AppColors.lightOnErrorContainer,
      surface: AppColors.lightSurface,
      onSurface: AppColors.lightOnSurface,
      onSurfaceVariant: AppColors.lightOnSurfaceVariant,
      surfaceContainerHighest: AppColors.lightSurfaceContainerHighest,
      outline: AppColors.lightOutline,
    );
    return _build(scheme, AppColors.lightScaffoldBackground, AppSemanticColors.light, isDark: false);
  }

  static ThemeData dark() {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: AppColors.darkPrimary,
      onPrimary: AppColors.darkOnPrimary,
      primaryContainer: AppColors.darkPrimaryContainer,
      onPrimaryContainer: AppColors.darkOnPrimaryContainer,
      secondary: AppColors.darkSecondary,
      onSecondary: AppColors.darkOnSecondary,
      secondaryContainer: AppColors.darkSecondaryContainer,
      onSecondaryContainer: AppColors.darkOnSecondaryContainer,
      tertiary: AppColors.darkTertiary,
      onTertiary: AppColors.darkOnTertiary,
      error: AppColors.darkError,
      onError: AppColors.darkOnError,
      errorContainer: AppColors.darkErrorContainer,
      onErrorContainer: AppColors.darkOnErrorContainer,
      surface: AppColors.darkSurface,
      onSurface: AppColors.darkOnSurface,
      onSurfaceVariant: AppColors.darkOnSurfaceVariant,
      surfaceContainerHighest: AppColors.darkSurfaceContainerHighest,
      outline: AppColors.darkOutline,
    );
    return _build(scheme, AppColors.darkScaffoldBackground, AppSemanticColors.dark, isDark: true);
  }

  static ThemeData _build(
    ColorScheme scheme,
    Color scaffoldBackground,
    AppSemanticColors semantic, {
    required bool isDark,
  }) {
    const radius = 12.0;
    final textTheme = _textTheme(scheme.onSurface, scheme.onSurfaceVariant);

    return ThemeData(
      useMaterial3: true,
      brightness: scheme.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffoldBackground,
      fontFamily: _fontFamily,
      textTheme: textTheme,
      extensions: [semantic],
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldBackground,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          fontFamily: _fontFamily,
          color: scheme.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      // Flat-outline cards work on a white background but disappear on a near-black
      // one - dark mode gets a real (if subtle) elevation/shadow instead of relying
      // purely on a 1px border the way light mode does.
      cardTheme: CardThemeData(
        elevation: isDark ? 1 : 0,
        color: scheme.surface,
        shadowColor: isDark ? Colors.black.withValues(alpha: 0.4) : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: scheme.outline),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          textStyle: const TextStyle(fontFamily: _fontFamily, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius - 2)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          side: BorderSide(color: scheme.outline),
          textStyle: const TextStyle(fontFamily: _fontFamily, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius - 2)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: const TextStyle(fontFamily: _fontFamily, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        labelStyle: TextStyle(fontFamily: _fontFamily, color: scheme.onSurfaceVariant),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius - 2),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius - 2),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius - 2),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scaffoldBackground,
        indicatorColor: scheme.secondaryContainer,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontFamily: _fontFamily,
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w400,
            color: states.contains(WidgetState.selected) ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
          ),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        labelStyle: const TextStyle(fontFamily: _fontFamily, fontWeight: FontWeight.w600, fontSize: 13),
        unselectedLabelStyle: const TextStyle(fontFamily: _fontFamily, fontWeight: FontWeight.w400, fontSize: 13),
        indicatorColor: scheme.primary,
        dividerColor: scheme.outline,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHighest,
        selectedColor: scheme.primaryContainer,
        labelStyle: TextStyle(fontFamily: _fontFamily, color: scheme.onSurface, fontSize: 13),
        secondaryLabelStyle: TextStyle(fontFamily: _fontFamily, color: scheme.onPrimaryContainer, fontSize: 13),
        side: BorderSide(color: scheme.outline),
        shape: const StadiumBorder(),
      ),
      dividerTheme: DividerThemeData(color: scheme.outline),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? scheme.primary : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? scheme.primaryContainer : null,
        ),
      ),
    );
  }
}
