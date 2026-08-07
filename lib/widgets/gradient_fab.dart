import 'package:flutter/material.dart';
import '../theme/app_semantic_colors.dart';

/// A FloatingActionButton with the app's indigo->violet gradient. Flutter's stock
/// FloatingActionButtonThemeData only supports a solid backgroundColor, hence this
/// thin wrapper instead of a theme-level change.
class GradientFab extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final String? tooltip;
  const GradientFab({super.key, required this.onPressed, required this.child, this.tooltip});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppGradients.primary(scheme),
        boxShadow: [
          BoxShadow(color: scheme.primary.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Tooltip(
            message: tooltip ?? '',
            child: SizedBox(
              width: 56,
              height: 56,
              child: IconTheme(
                data: IconThemeData(color: scheme.onPrimary),
                child: Center(child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
