import 'package:flutter/material.dart';

/// A shimmering placeholder block - used in grids of stat cards while data loads.
class Skeleton extends StatefulWidget {
  final double width;
  final double height;
  final BorderRadius? borderRadius;
  const Skeleton({super.key, this.width = double.infinity, this.height = 14, this.borderRadius});

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            // surfaceContainerHighest/outline instead of hardcoded grey shades - the
            // old literals were invisible-to-wrong on a dark background.
            color: Color.lerp(scheme.surfaceContainerHighest, scheme.outline, _controller.value),
            borderRadius: widget.borderRadius ?? BorderRadius.circular(6),
          ),
        );
      },
    );
  }
}

/// Grid of skeleton stat cards matching the Dashboard's real card layout.
class StatCardSkeletonGrid extends StatelessWidget {
  final int count;
  const StatCardSkeletonGrid({super.key, this.count = 6});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.15,
      ),
      itemCount: count,
      itemBuilder: (context, i) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Skeleton(width: 80, height: 12),
                SizedBox(height: 12),
                Skeleton(width: 60, height: 20),
              ],
            ),
          ),
        );
      },
    );
  }
}
