import 'package:flutter/material.dart';

/// Branded loading indicator - a pulsing app logo instead of a generic spinner, used
/// on the screens that feel most like "home base" (Dashboard, Accounting).
class LogoLoader extends StatefulWidget {
  final String label;
  const LogoLoader({super.key, this.label = 'Loading...'});

  @override
  State<LogoLoader> createState() => _LogoLoaderState();
}

class _LogoLoaderState extends State<LogoLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final scale = 0.9 + (_controller.value * 0.15);
              return Stack(
                alignment: Alignment.center,
                children: [
                  // Soft radial glow instead of a flat alpha-pulsed circle.
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          scheme.primary.withValues(alpha: 0.22 * (1 - _controller.value) + 0.10),
                          scheme.primary.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                  Transform.scale(scale: scale, child: child),
                ],
              );
            },
            child: ClipOval(
              child: Image.asset('assets/icon/app_icon.jpg', width: 48, height: 48, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: 16),
          Text(widget.label, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
        ],
      ),
    );
  }
}
