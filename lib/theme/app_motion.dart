import 'package:flutter/material.dart';

/// Shared timing/curve constants so hand-rolled AnimationControllers (LogoLoader,
/// Skeleton, Dashboard's stat-card stagger) and flutter_animate-based entrance
/// animations (everything added from Phase 3 onward) read as one consistent system.
class AppMotion {
  AppMotion._();

  static const entranceDuration = Duration(milliseconds: 350);
  static const staggerStep = Duration(milliseconds: 60);
  static const entranceCurve = Curves.easeOut;
}
