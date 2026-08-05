import 'package:flutter/material.dart';

/// A selectable colour theme for FinFlow.
///
/// Each palette carries a Material 3 seed colour (the whole `ColorScheme`
/// is derived from it) plus a two-stop hero gradient used for the Net Worth
/// hero card and colour swatches. Palettes are persisted by [id].
@immutable
class AppPalette {
  const AppPalette({
    required this.id,
    required this.label,
    required this.seed,
    required this.heroGradient,
    required this.heroGradientDark,
    required this.icon,
  });

  /// Stable identifier persisted in the settings store.
  final String id;

  /// Human readable name shown in the settings picker.
  final String label;

  /// Material 3 seed colour — drives the entire tonal `ColorScheme`.
  final Color seed;

  /// Vibrant two-stop gradient used in light mode.
  final List<Color> heroGradient;

  /// Deeper two-stop gradient used in dark mode.
  final List<Color> heroGradientDark;

  /// Icon shown in the settings picker.
  final IconData icon;
}

/// The built-in palette registry.
abstract final class AppPalettes {
  /// The premium purple default: `#6D5DF6 → #9C6BFF`.
  static const AppPalette purple = AppPalette(
    id: 'purple',
    label: 'Purple',
    seed: Color(0xFF6D5DF6),
    heroGradient: [Color(0xFF9C6BFF), Color(0xFF6D5DF6)],
    heroGradientDark: [Color(0xFF7C5CFF), Color(0xFF4636C4)],
    icon: Icons.auto_awesome_outlined,
  );

  static const AppPalette pink = AppPalette(
    id: 'pink',
    label: 'Pink',
    seed: Color(0xFFFF4D8D),
    heroGradient: [Color(0xFFFF7AA6), Color(0xFFF0267A)],
    heroGradientDark: [Color(0xFFF04B8E), Color(0xFFB31557)],
    icon: Icons.favorite_outline,
  );

  static const AppPalette green = AppPalette(
    id: 'green',
    label: 'Green',
    seed: Color(0xFF16C784),
    heroGradient: [Color(0xFF3ED6A0), Color(0xFF0E9F6E)],
    heroGradientDark: [Color(0xFF12B981), Color(0xFF086C4E)],
    icon: Icons.eco_outlined,
  );

  static const AppPalette blue = AppPalette(
    id: 'blue',
    label: 'Blue',
    seed: Color(0xFF4E9BFF),
    heroGradient: [Color(0xFF6FB1FF), Color(0xFF2474E8)],
    heroGradientDark: [Color(0xFF3D8BFF), Color(0xFF1D55B8)],
    icon: Icons.water_drop_outlined,
  );

  static const AppPalette coral = AppPalette(
    id: 'coral',
    label: 'Coral',
    seed: Color(0xFFFF6B6B),
    heroGradient: [Color(0xFFFF8A80), Color(0xFFE5384B)],
    heroGradientDark: [Color(0xFFF05555), Color(0xFFB01F31)],
    icon: Icons.wb_sunny_outlined,
  );

  static const AppPalette teal = AppPalette(
    id: 'teal',
    label: 'Teal',
    seed: Color(0xFF14B8A6),
    heroGradient: [Color(0xFF2DD4BF), Color(0xFF0E7490)],
    heroGradientDark: [Color(0xFF16B5A3), Color(0xFF0B5566)],
    icon: Icons.waves_outlined,
  );

  static const List<AppPalette> all = [
    purple,
    pink,
    green,
    blue,
    coral,
    teal,
  ];

  /// Looks up a palette by persisted [id], falling back to [purple].
  static AppPalette byId(String id) => all.firstWhere(
    (palette) => palette.id == id,
    orElse: () => purple,
  );
}

/// Theme extension exposing the palette's hero gradient to widgets.
///
/// The gradient is pre-resolved for the active brightness (light palettes
/// carry the vibrant stops, dark palettes the deep stops), so widgets simply
/// read `Theme.of(context).extension<FinFlowTheme>()`.
@immutable
class FinFlowTheme extends ThemeExtension<FinFlowTheme> {
  const FinFlowTheme({required this.heroGradient});

  final List<Color> heroGradient;

  @override
  FinFlowTheme copyWith({List<Color>? heroGradient}) => FinFlowTheme(
    heroGradient: heroGradient ?? this.heroGradient,
  );

  @override
  FinFlowTheme lerp(ThemeExtension<FinFlowTheme>? other, double t) {
    if (other is! FinFlowTheme ||
        heroGradient.length < 2 ||
        other.heroGradient.length < 2) {
      return this;
    }
    return FinFlowTheme(
      heroGradient: [
        Color.lerp(heroGradient[0], other.heroGradient[0], t)!,
        Color.lerp(heroGradient[1], other.heroGradient[1], t)!,
      ],
    );
  }
}
