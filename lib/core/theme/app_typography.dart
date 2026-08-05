import 'package:flutter/material.dart';

/// Typography scale. Uses Inter with explicit sizes and weights tuned for
/// the premium finance dashboard (Inter SemiBold titles, Bold amounts).
abstract final class AppTypography {
  /// The bundled Inter family name.
  static const String fontFamily = 'Inter';

  static const double headline = 28;
  static const double title = 20;
  static const double subtitle = 16;
  static const double body = 14;
  static const double caption = 12;
  static const double micro = 10;

  static const FontWeight weightBold = FontWeight.w700;
  static const FontWeight weightSemiBold = FontWeight.w600;
  static const FontWeight weightMedium = FontWeight.w500;
  static const FontWeight weightRegular = FontWeight.w400;

  static const FontWeight tabularNumbers = FontWeight.w600;

  /// Style for large monetary values (dashboard hero figures).
  static TextStyle money(BuildContext context, {double size = headline}) =>
      Theme.of(context).textTheme.headlineSmall!.copyWith(
        fontSize: size,
        fontWeight: weightBold,
        fontFamily: fontFamily,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// Style for secondary monetary values (list rows).
  static TextStyle moneyRow(BuildContext context) =>
      Theme.of(context).textTheme.bodyLarge!.copyWith(
        fontWeight: weightSemiBold,
        fontFamily: fontFamily,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// Small, letter-spaced uppercase style for section eyebrows.
  static TextStyle eyebrow(BuildContext context) =>
      Theme.of(context).textTheme.labelSmall!.copyWith(
        fontSize: 11,
        fontWeight: weightSemiBold,
        letterSpacing: 1.4,
      );
}
