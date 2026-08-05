import 'package:flutter/material.dart';

/// The FinFlow brand palette.
///
/// A premium fintech palette: a vivid purple accent
/// (`#6D5DF6 → #9C6BFF`), green income / red expense semantics, near-black
/// surfaces in dark mode and clean near-white surfaces in light mode.
abstract final class AppColors {
  // ---- Brand ----
  static const Color brand = Color(0xFF6D5DF6);
  static const Color brandBright = Color(0xFF9C6BFF);
  static const Color gold = Color(0xFFF5A623);

  // ---- Semantic ----
  static const Color income = Color(0xFF16C784);
  static const Color expense = Color(0xFFEA3943);
  static const Color warning = Color(0xFFF5A623);
  static const Color info = Color(0xFF4E9BFF);

  // ---- Reference accents ----
  static const Color pink = Color(0xFFFF5C8D);
  static const Color green = Color(0xFF16C784);
  static const Color blue = Color(0xFF4E9BFF);
  static const Color coral = Color(0xFFFF6B6B);

  // ---- Text ----
  static const Color textPrimary = Color(0xFF131722);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textOnDarkPrimary = Color(0xFFFFFFFF);
  static const Color textOnDarkSecondary = Color(0xFF9AA4B2);

  // ---- Borders (rgba(255,255,255,0.06) in dark mode) ----
  static const Color borderLight = Color(0x0F131722);
  static const Color borderDark = Color(0x0FFFFFFF);

  // ---- App backgrounds ----
  static const Color surfaceLight = Color(0xFFF5F6FA);
  static const Color surfaceDark = Color(0xFF0F1117);
  static const Color surfaceDarkElevated = Color(0xFF171B22);
  static const Color cardDark = Color(0xFF1D222C);

  /// Palette used for account icon tiles and auto-assigned account colours
  /// (cycled so every new account gets a distinct shade).
  static const List<Color> accountPalette = [
    Color(0xFF6D5DF6),
    Color(0xFF4E9BFF),
    Color(0xFF16C784),
    Color(0xFFFF5C8D),
    Color(0xFFFF6B6B),
    Color(0xFF14B8A6),
    Color(0xFFF5A623),
    Color(0xFF8B5CF6),
  ];

  /// Palette used for category icon tiles.
  static const List<Color> categoryPalette = [
    Color(0xFF4E9BFF),
    Color(0xFF16C784),
    Color(0xFFF5A623),
    Color(0xFFEA3943),
    Color(0xFF8B5CF6),
    Color(0xFFFF5C8D),
    Color(0xFF14B8A6),
    Color(0xFFFF6B6B),
  ];

  /// Hairline used for chart grid lines and axis guides.
  ///
  /// Dark mode uses a barely-visible white so lines read cleanly against the
  /// deep `#0F1117` surfaces (the default M3 `outlineVariant` grey looks
  /// washed-out there); light mode keeps the soft outline tint.
  static Color chartGrid(ThemeData theme) => theme.brightness == Brightness.dark
      ? Colors.white.withValues(alpha: 0.07)
      : theme.colorScheme.outlineVariant.withValues(alpha: 0.4);

  /// Background track for chart bars and progress rings.
  ///
  /// Dark mode: barely-there white; light mode: surface-tinted grey.
  static Color chartTrack(ThemeData theme) => theme.brightness == Brightness.dark
      ? Colors.white.withValues(alpha: 0.05)
      : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35);
}
