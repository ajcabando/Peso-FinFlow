import 'package:flutter/material.dart';

/// A rounded, tinted square used for account and category iconography.
class AppIconTile extends StatelessWidget {
  const AppIconTile({
    super.key,
    required this.icon,
    required this.color,
    this.size = 44,
    this.iconSize,
    this.frosted = false,
  });

  final IconData icon;
  final Color color;
  final double size;
  final double? iconSize;

  /// Frosted-glass variant for coloured gradient surfaces: a translucent
  /// white tile with a white icon that stays legible on any hue. When
  /// enabled, [color] is not used for the tile or icon.
  final bool frosted;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: frosted
            ? Colors.white.withValues(alpha: 0.22)
            : isDark
            ? color.withValues(alpha: 0.22)
            : color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(
        icon,
        color: frosted ? Colors.white : color,
        size: iconSize ?? size * 0.48,
      ),
    );
  }
}
