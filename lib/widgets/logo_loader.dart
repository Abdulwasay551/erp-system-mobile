import 'package:flutter/material.dart';

const _ink = Color(0xFF171717);

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
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _ink.withValues(alpha: 0.08 * (1 - _controller.value) + 0.04),
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
          Text(widget.label, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
        ],
      ),
    );
  }
}
