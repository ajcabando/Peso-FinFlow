import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_radii.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/models/account.dart';
import 'account_type_ui.dart';

/// Gradient for account surfaces, derived from the account's own colour and
/// adapted to the active brightness so cards stay vibrant yet readable in
/// both light and dark mode.
///
/// Dark mode gets a three-stop ramp — a faint white sheen at the top corner
/// falling through a rich mid-tone into a deep base — so the card keeps its
/// colour intensity instead of turning muddy when darkened against the
/// near-black background.
List<Color> accountCardGradient(Color accountColor, {required bool isDark}) {
  if (isDark) {
    return [
      Color.lerp(accountColor, Colors.white, 0.06)!,
      Color.lerp(accountColor, Colors.black, 0.24)!,
      Color.lerp(accountColor, Colors.black, 0.52)!,
    ];
  }
  return [
    Color.lerp(accountColor, Colors.white, 0.14)!,
    Color.lerp(accountColor, Colors.black, 0.26)!,
  ];
}

/// A colourful, bank-card style surface for one account.
///
/// The gradient is derived from the account's colour (which itself picks up
/// the active theme seed by default), so every account reads as a distinct,
/// non-generic card while staying consistent with the app's palette in both
/// light and dark mode. A soft watermark of the account's type icon sits in
/// the corner for a little extra character.
class AccountGradientCard extends StatelessWidget {
  const AccountGradientCard({
    super.key,
    required this.account,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.radius = AppRadii.lg,
  });

  final Account account;
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final colors = accountCardGradient(account.color, isDark: isDark);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        splashColor: Colors.white.withValues(alpha: 0.10),
        highlightColor: Colors.white.withValues(alpha: 0.06),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
            borderRadius: BorderRadius.circular(radius),
            // Dark mode: a hairline edge lifts the card off the near-black
            // background, and a soft glow in the account's own colour gives
            // it depth (a plain dark shadow would be invisible on #0F1117).
            border: isDark
                ? Border.all(color: Colors.white.withValues(alpha: 0.08))
                : null,
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? account.color.withValues(alpha: 0.38)
                    : colors.last.withValues(alpha: 0.30),
                blurRadius: isDark ? 30 : 20,
                offset: Offset(0, isDark ? 12 : 8),
              ),
            ],
          ),
          // Clip keeps the decorative watermark inside the rounded corners.
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: Stack(
              children: [
                Positioned(
                  right: -12,
                  bottom: -12,
                  child: Icon(
                    accountTypeIcon(account.type),
                    size: 84,
                    color: Colors.white.withValues(alpha: 0.10),
                  ),
                ),
                Padding(padding: padding, child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
