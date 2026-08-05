import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../domain/models/bill.dart';
import 'bill_status_chip.dart';

/// A row describing one bill: status chip, name, due info and amount, plus a
/// one-tap "mark paid" action when it needs attention.
class BillTile extends StatelessWidget {
  const BillTile({
    super.key,
    required this.bill,
    required this.currencyCode,
    this.onTap,
    this.onMarkPaid,
    this.compact = false,
  });

  final Bill bill;
  final String currencyCode;
  final VoidCallback? onTap;
  final VoidCallback? onMarkPaid;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = bill.status;
    final now = DateTime.now();
    final due = bill.dueDateIn(now);

    String dueLabel;
    switch (status) {
      case BillStatus.paid:
        dueLabel = 'Paid this month';
      case BillStatus.overdue:
        final days = now.day - due.day;
        dueLabel = days <= 1 ? 'Due yesterday' : 'Due $days days ago';
      case BillStatus.dueSoon:
        final days = due.day - now.day;
        dueLabel = days == 0 ? 'Due today' : 'Due in $days days';
      case BillStatus.upcoming:
        dueLabel = 'Due ${due.day} ${_monthName(due.month)}';
      case BillStatus.paused:
        dueLabel = 'Paused';
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: status.needsAttention
                      ? [AppColors.expense, const Color(0xFFF5A623)]
                      : [theme.colorScheme.primary, theme.colorScheme.tertiary],
                ),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(
                _iconFor(status),
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          bill.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (!compact) ...[
                        const SizedBox(width: 8),
                        BillStatusChip(status: status),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    dueLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              CurrencyFormatter.format(bill.amountMinor, currencyCode),
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: status == BillStatus.paid
                    ? AppColors.income
                    : status.needsAttention
                    ? AppColors.expense
                    : null,
              ),
            ),
            if (onMarkPaid != null && status.needsAttention) ...[
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Mark paid',
                onPressed: onMarkPaid,
                icon: const Icon(Icons.check_circle_outline),
                color: AppColors.income,
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _monthName(int month) => const [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ][month - 1];

  static IconData _iconFor(BillStatus status) => switch (status) {
    BillStatus.overdue => Icons.error_outline_rounded,
    BillStatus.dueSoon => Icons.notifications_active_outlined,
    BillStatus.paid => Icons.check_circle_outline,
    BillStatus.upcoming => Icons.event_outlined,
    BillStatus.paused => Icons.pause_circle_outline,
  };
}
