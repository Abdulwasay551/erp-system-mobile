import 'package:flutter/material.dart';
import '../theme/app_semantic_colors.dart';

/// A FloatingActionButton with the app's indigo->violet gradient. Flutter's stock
/// FloatingActionButtonThemeData only supports a solid backgroundColor, hence this
/// thin wrapper instead of a theme-level change.
class GradientFab extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final String? tooltip;
  /// When set, renders as an extended (pill-shaped, icon + label) FAB instead of
  /// a plain circle - matches FloatingActionButton.extended's shape.
  final String? label;
  const GradientFab({super.key, required this.onPressed, required this.child, this.tooltip, this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final extended = label != null;
    final content = extended
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              child,
              const SizedBox(width: 8),
              DefaultTextStyle(
                style: TextStyle(color: scheme.onPrimary, fontWeight: FontWeight.w600, fontSize: 15),
                child: Text(label!),
              ),
            ],
          )
        : child;
    return Container(
      width: extended ? null : 56,
      height: 56,
      padding: extended ? const EdgeInsets.symmetric(horizontal: 20) : null,
      decoration: BoxDecoration(
        shape: extended ? BoxShape.rectangle : BoxShape.circle,
        borderRadius: extended ? BorderRadius.circular(16) : null,
        gradient: AppGradients.primary(scheme),
        boxShadow: [
          BoxShadow(color: scheme.primary.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        shape: extended ? null : const CircleBorder(),
        borderRadius: extended ? BorderRadius.circular(16) : null,
        child: InkWell(
          customBorder: extended ? null : const CircleBorder(),
          borderRadius: extended ? BorderRadius.circular(16) : null,
          onTap: onPressed,
          child: Tooltip(
            message: tooltip ?? '',
            child: IconTheme(
              data: IconThemeData(color: scheme.onPrimary),
              // widthFactor/heightFactor: 1 makes Center shrink-wrap the Row instead
              // of expanding to fill the Scaffold FAB slot's bounded loose width.
              child: Center(widthFactor: 1, heightFactor: 1, child: content),
            ),
          ),
        ),
      ),
    );
  }
}
