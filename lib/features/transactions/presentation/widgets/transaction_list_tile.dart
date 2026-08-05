import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/amount_text.dart';
import '../../../../core/extensions/date_time_extensions.dart';
import '../../domain/enums/transaction_type.dart';
import '../../domain/models/financial_transaction.dart';
import '../../domain/models/transaction_context.dart';

/// Icon + colour used to visualise a transaction type across lists.
({IconData icon, Color color}) transactionTypeVisual(TransactionType type) {
  return switch (type) {
    TransactionType.income => (
      icon: Icons.trending_up_rounded,
      color: AppColors.income,
    ),
    TransactionType.expense => (
      icon: Icons.trending_down_rounded,
      color: AppColors.expense,
    ),
    TransactionType.transfer => (
      icon: Icons.swap_horiz_rounded,
      color: AppColors.info,
    ),
    TransactionType.refund => (
      icon: Icons.replay_rounded,
      color: AppColors.income,
    ),
    TransactionType.adjustment => (
      icon: Icons.tune_rounded,
      color: AppColors.warning,
    ),
    TransactionType.openingBalance => (
      icon: Icons.flag_outlined,
      color: AppColors.info,
    ),
  };
}

/// Whether an amount should be displayed with an explicit sign for [type].
bool _showsSign(TransactionType type) => switch (type) {
  TransactionType.income || TransactionType.refund => true,
  TransactionType.expense => true,
  _ => false,
};

AmountVariant _variant(TransactionType type) => switch (type) {
  TransactionType.income || TransactionType.refund => AmountVariant.income,
  TransactionType.expense => AmountVariant.expense,
  _ => AmountVariant.neutral,
};

/// A single transaction row: type icon, title, account/category subtitle,
/// date and signed amount.
class TransactionListTile extends StatelessWidget {
  const TransactionListTile({
    super.key,
    required this.transaction,
    this.accountName,
    this.categoryName,
    this.onTap,
  });

  /// Convenience constructor for enriched contexts.
  TransactionListTile.context(
    TransactionContext context, {
    super.key,
    this.onTap,
  }) : transaction = context.transaction,
       accountName = context.accountName,
       categoryName = context.categoryName;

  final FinancialTransaction transaction;
  final String? accountName;
  final String? categoryName;
  final VoidCallback? onTap;

  String get _subtitle {
    final parts = <String>[
      if (accountName != null && accountName!.isNotEmpty) accountName!,
      if (categoryName != null && categoryName!.isNotEmpty) categoryName!,
    ];
    return parts.isEmpty
        ? transaction.occurredAt.monthDayYear
        : '${parts.join(' · ')} · ${transaction.occurredAt.monthDayYear}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visual = transactionTypeVisual(transaction.type);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: visual.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(visual.icon, color: visual.color, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      transaction.title,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              AmountText(
                _showsSign(transaction.type)
                    ? _signed(transaction)
                    : transaction.amountMinor,
                currencyCode: transaction.currencyCode,
                variant: _variant(transaction.type),
                showSign: _showsSign(transaction.type),
                style: theme.textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      ),
    );
  }

  int _signed(FinancialTransaction transaction) =>
      _variant(transaction.type) == AmountVariant.expense
      ? -transaction.amountMinor
      : transaction.amountMinor;
}
