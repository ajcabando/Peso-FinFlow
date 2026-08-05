import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Elevation shadows. Light mode uses a soft, larger-blur shadow for cards;
/// dark mode intentionally drops harsh shadows in favour of surface
/// elevation with a whisper of depth.
abstract final class AppShadows {
  static List<BoxShadow> get card => const [
    BoxShadow(color: Color(0x14000000), blurRadius: 24, offset: Offset(0, 10)),
    BoxShadow(color: Color(0x0A000000), blurRadius: 6, offset: Offset(0, 2)),
  ];

  static List<BoxShadow> get cardStrong => const [
    BoxShadow(color: Color(0x24000000), blurRadius: 40, offset: Offset(0, 16)),
  ];

  /// Gentle shadow for floating elements (nav pill, FAB) in dark mode too,
  /// since those sit above the surface.
  static List<BoxShadow> get floating => const [
    BoxShadow(color: Color(0x33000000), blurRadius: 24, offset: Offset(0, 8)),
  ];

  /// No shadow — used on flat surfaces in dark mode.
  static List<BoxShadow> get none => const [];

  static List<BoxShadow> forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? none : card;

  static List<BoxShadow> forBrightnessStrong(Brightness brightness) =>
      brightness == Brightness.dark ? none : cardStrong;

  static Color overlayFor(Brightness brightness) =>
      brightness == Brightness.dark
      ? Colors.black.withValues(alpha: 0.28)
      : AppColors.brand.withValues(alpha: 0.10);
}
