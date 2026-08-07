import 'package:flutter/material.dart';

/// Single source of truth for status/semantic colors (success/warning/danger/neutral)
/// and the app's handful of deliberately-restricted gradients - replaces the ad hoc
/// `Colors.green.shade700` / `_statusColors` maps that used to be copy-pasted across
/// invoices/accounting/contacts/staff/search screens.
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  final Color success;
  final Color successContainer;
  final Color warning;
  final Color warningContainer;
  final Color danger;
  final Color dangerContainer;
  final Color neutral;
  final Color neutralContainer;

  const AppSemanticColors({
    required this.success,
    required this.successContainer,
    required this.warning,
    required this.warningContainer,
    required this.danger,
    required this.dangerContainer,
    required this.neutral,
    required this.neutralContainer,
  });

  static const light = AppSemanticColors(
    success: Color(0xFF15803D),
    successContainer: Color(0xFFDCFCE7),
    warning: Color(0xFFB45309),
    warningContainer: Color(0xFFFEF3C7),
    danger: Color(0xFFB91C1C),
    dangerContainer: Color(0xFFFEE2E2),
    neutral: Color(0xFF6B7280),
    neutralContainer: Color(0xFFF3F4F6),
  );

  static const dark = AppSemanticColors(
    success: Color(0xFF4ADE80),
    successContainer: Color(0xFF14532D),
    warning: Color(0xFFFBBF24),
    warningContainer: Color(0xFF78350F),
    danger: Color(0xFFF87171),
    dangerContainer: Color(0xFF7F1D1D),
    neutral: Color(0xFFA1A1AA),
    neutralContainer: Color(0xFF27272A),
  );

  /// Maps an invoice/bill status string to (foreground, container) colors - same
  /// red=overdue / amber=partial / green=paid / gray=draft convention as before,
  /// just sourced from one place instead of a map literal per screen.
  (Color, Color) statusColor(String status) {
    switch (status) {
      case 'paid':
        return (success, successContainer);
      case 'partially_paid':
        return (warning, warningContainer);
      case 'overdue':
      case 'cancelled':
        return (danger, dangerContainer);
      case 'draft':
      case 'sent':
      default:
        return (neutral, neutralContainer);
    }
  }

  @override
  AppSemanticColors copyWith({
    Color? success,
    Color? successContainer,
    Color? warning,
    Color? warningContainer,
    Color? danger,
    Color? dangerContainer,
    Color? neutral,
    Color? neutralContainer,
  }) {
    return AppSemanticColors(
      success: success ?? this.success,
      successContainer: successContainer ?? this.successContainer,
      warning: warning ?? this.warning,
      warningContainer: warningContainer ?? this.warningContainer,
      danger: danger ?? this.danger,
      dangerContainer: dangerContainer ?? this.dangerContainer,
      neutral: neutral ?? this.neutral,
      neutralContainer: neutralContainer ?? this.neutralContainer,
    );
  }

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      successContainer: Color.lerp(successContainer, other.successContainer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningContainer: Color.lerp(warningContainer, other.warningContainer, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerContainer: Color.lerp(dangerContainer, other.dangerContainer, t)!,
      neutral: Color.lerp(neutral, other.neutral, t)!,
      neutralContainer: Color.lerp(neutralContainer, other.neutralContainer, t)!,
    );
  }
}

extension AppSemanticColorsX on BuildContext {
  AppSemanticColors get semanticColors => Theme.of(this).extension<AppSemanticColors>()!;
}

/// The app's short, deliberate list of gradients - kept in one place so they can't
/// proliferate ad hoc per screen. Everything else (list tiles, form fields, plain
/// cards, chips) stays flat/solid.
class AppGradients {
  AppGradients._();

  static LinearGradient primary(ColorScheme scheme) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [scheme.primary, scheme.secondary],
      );
}
