import 'package:flutter/material.dart';
import '../theme/app_semantic_colors.dart';

/// A full-width filled button with the app's indigo->violet gradient - reserved for
/// the single highest-frequency call-to-action per screen (POS "Complete Sale"),
/// per the design plan's deliberately restricted gradient list.
class GradientButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  const GradientButton({super.key, required this.onPressed, required this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final disabled = onPressed == null;
    return Container(
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: disabled ? null : AppGradients.primary(scheme),
        color: disabled ? scheme.surfaceContainerHighest : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onPressed,
          child: Center(
            child: DefaultTextStyle(
              style: TextStyle(
                color: disabled ? scheme.onSurfaceVariant : scheme.onPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
              child: IconTheme(
                data: IconThemeData(color: disabled ? scheme.onSurfaceVariant : scheme.onPrimary),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
