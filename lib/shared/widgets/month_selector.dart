import 'package:flutter/material.dart';

import '../../core/extensions/date_time_extensions.dart';
import '../../core/theme/app_spacing.dart';
import 'app_card.dart';

/// A month navigation control: previous / next arrows around a tappable
/// label that opens the date picker to jump months. Used by the analytics and
/// budgets pages.
class MonthSelector extends StatelessWidget {
  const MonthSelector({
    super.key,
    required this.month,
    required this.onMonthChanged,
    this.firstDate,
  });

  /// First of the currently selected month.
  final DateTime month;

  final ValueChanged<DateTime> onMonthChanged;

  /// Earliest month the picker allows.
  final DateTime? firstDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final isCurrentMonth = month.year == now.year && month.month == now.month;
    final earliest = firstDate ?? DateTime(now.year - 5, 1, 1);

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Previous month',
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: () =>
                onMonthChanged(DateTime(month.year, month.month - 1, 1)),
          ),
          Expanded(
            child: InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: month,
                  firstDate: earliest,
                  lastDate: now,
                  helpText: 'Jump to a month',
                  cancelText: 'Cancel',
                  confirmText: 'Go',
                );
                if (picked != null) {
                  onMonthChanged(DateTime(picked.year, picked.month, 1));
                }
              },
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Column(
                  children: [
                    Text(
                      month.monthYear,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Tap to jump',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Next month',
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: isCurrentMonth
                ? null
                : () =>
                      onMonthChanged(DateTime(month.year, month.month + 1, 1)),
          ),
        ],
      ),
    );
  }
}
