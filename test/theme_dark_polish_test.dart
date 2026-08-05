import 'package:finflow/core/theme/app_colors.dart';
import 'package:finflow/core/theme/app_theme.dart';
import 'package:finflow/features/accounts/presentation/widgets/account_gradient_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('accountCardGradient', () {
    const brand = Color(0xFF6D5DF6);

    test('dark mode yields a three-stop ramp (sheen → mid → deep)', () {
      final colors = accountCardGradient(brand, isDark: true);
      expect(colors, hasLength(3));
    });

    test('light mode keeps the two-stop ramp', () {
      final colors = accountCardGradient(brand, isDark: false);
      expect(colors, hasLength(2));
    });

    test('dark ramp deepens towards the bottom stop', () {
      final colors = accountCardGradient(brand, isDark: true);
      expect(
        colors.last.computeLuminance(),
        lessThan(colors.first.computeLuminance()),
      );
    });
  });

  group('AppColors chart helpers', () {
    test('dark mode uses barely-visible white hairlines', () {
      final theme = AppTheme.dark();
      expect(AppColors.chartGrid(theme).a, lessThan(0.15));
      expect(AppColors.chartTrack(theme).a, lessThan(0.15));
      expect(AppColors.chartGrid(theme).r, greaterThan(0.9));
    });

    test('light mode keeps the soft M3 outline/surface tints', () {
      final theme = AppTheme.light();
      expect(
        AppColors.chartGrid(theme),
        equals(theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
      );
      expect(
        AppColors.chartTrack(theme),
        equals(
          theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        ),
      );
    });
  });
}
