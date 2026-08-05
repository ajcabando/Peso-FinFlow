import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../domain/models/budget_progress.dart';

/// A single budget's progress: category, spent/limit, status-coloured bar
/// and remaining (or over) label. Renders content only — parents supply the
/// [Card] surface so it works on both the budgets page and the dashboard.
class BudgetProgressTile extends StatelessWidget {
  const BudgetProgressTile({
    super.key,
    required this.progress,
    required this.currencyCode,
    this.compact = false,
  });

  final BudgetProgress progress;
  final String currencyCode;

  /// Compact dashboard variant: tighter spacing, smaller bar.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final barColor = progress.isOver
        ? AppColors.expense
        : progress.isNearlyExhausted
        ? AppColors.warning
        : context.colors.primary;
    final fill = progress.fraction.clamp(0.0, 1.0);
    final percent = (progress.fraction * 100).round();
    final categoryColor = progress.colorValue != 0
        ? Color(progress.colorValue)
        : AppColors.categoryPalette.first;

    final statusLabel = progress.isOver
        ? '${CurrencyFormatter.format(-progress.remainingMinor, currencyCode)} over'
        : '${CurrencyFormatter.format(progress.remainingMinor, currencyCode)} left';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: categoryColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                progress.categoryName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '${CurrencyFormatter.format(progress.spentMinor, currencyCode)} / '
              '${CurrencyFormatter.format(progress.amountMinor, currencyCode)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        SizedBox(height: compact ? AppSpacing.sm : AppSpacing.md),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fill,
            minHeight: compact ? 6 : 9,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            color: barColor,
          ),
        ),
        SizedBox(height: compact ? 6 : AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: Text(
                statusLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: progress.isOver
                      ? AppColors.expense
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: progress.isOver
                      ? FontWeight.w700
                      : FontWeight.w500,
                ),
              ),
            ),
            Text(
              '$percent%',
              style: theme.textTheme.bodySmall?.copyWith(
                color: progress.isOver ? AppColors.expense : null,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
