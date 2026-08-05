import 'package:flutter/material.dart';

import '../../core/extensions/context_extensions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_shadows.dart';
import '../../core/theme/app_spacing.dart';

/// The standard FinFlow card surface: softly rounded with a hairline border,
/// tinted by the current theme, optionally tappable or carrying a gradient.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.color,
    this.gradient,
    this.radius = AppRadii.lg,
    this.showBorder = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final List<Color>? gradient;
  final double radius;
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    // Card surfaces are tinted by the theme by default; an explicit [color]
    // or [gradient] overrides that.
    final resolvedColor =
        color ?? (isDark ? context.theme.cardTheme.color : Colors.white);

    final decoration = BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      color: gradient == null ? resolvedColor : null,
      gradient: gradient == null
          ? null
          : LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradient!,
            ),
      border: showBorder
          ? Border.all(
              color: isDark ? AppColors.borderDark : AppColors.borderLight,
            )
          : null,
      boxShadow: isDark ? null : AppShadows.card,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: Ink(
          decoration: decoration,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
