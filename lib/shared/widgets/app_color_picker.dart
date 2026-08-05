import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

/// A wrap of selectable colour circles backed by [AppColors.accountPalette],
/// shared by the account and category forms so every new entity picks from
/// the same dynamic palette.
class AppColorPicker extends StatelessWidget {
  const AppColorPicker({
    super.key,
    required this.selected,
    required this.onSelected,
    this.palette = AppColors.accountPalette,
  });

  /// The currently selected colour (ARGB value).
  final int selected;
  final ValueChanged<int> onSelected;

  /// The palette to offer; defaults to the shared account/category palette.
  final List<Color> palette;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      children: [
        for (final color in palette)
          GestureDetector(
            onTap: () => onSelected(color.toARGB32()),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: selected == color.toARGB32()
                    ? Border.all(
                        color: Theme.of(context).colorScheme.onSurface,
                        width: 2.5,
                      )
                    : null,
              ),
              child: selected == color.toARGB32()
                  ? const Icon(Icons.check, size: 18, color: Colors.white)
                  : null,
            ),
          ),
      ],
    );
  }
}
