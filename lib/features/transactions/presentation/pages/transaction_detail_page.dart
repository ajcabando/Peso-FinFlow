import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers/app_providers.dart';
import '../../../../app/router/app_router.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_time_extensions.dart';
import '../../../../core/theme/app_radii.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/amount_text.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/section_header.dart';
import '../../domain/enums/transaction_type.dart';
import '../../domain/models/transaction_context.dart';
import '../providers/transaction_providers.dart';
import '../widgets/transaction_list_tile.dart';

/// Full view of a single transaction: amount, accounts, category, notes and
/// the audit fields, with edit and delete actions.
class TransactionDetailPage extends ConsumerWidget {
  const TransactionDetailPage({super.key, required this.transactionId});

  final String transactionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(transactionContextProvider(transactionId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
            onPressed: () =>
                context.push(AppRoutes.transactionEdit(transactionId)),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Could not load transaction: $error'),
          ),
        ),
        data: (contextRow) {
          if (contextRow == null) {
            return const Center(child: Text('Transaction not found.'));
          }
          return _TransactionDetailBody(
            contextRow: contextRow,
            onDelete: () => _delete(context, ref, contextRow.transaction.id),
          );
        },
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete transaction?'),
        content: const Text(
          'This permanently removes the transaction and its ledger entries. '
          'Balances will be recalculated automatically.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(transactionRepositoryProvider).delete(id);
      if (!context.mounted) return;
      context.showSnack('Transaction deleted');
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    } on FinFlowException catch (error) {
      if (!context.mounted) return;
      context.showSnack(error.message);
    }
  }
}

class _TransactionDetailBody extends StatelessWidget {
  const _TransactionDetailBody({
    required this.contextRow,
    required this.onDelete,
  });

  final TransactionContext contextRow;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final transaction = contextRow.transaction;
    final visual = transactionTypeVisual(transaction.type);

    final details = <({String label, String? value})>[
      (label: 'Type', value: transaction.type.label),
      if (contextRow.accountName != null)
        (label: 'Account', value: contextRow.accountName),
      if (contextRow.categoryName != null)
        (label: 'Category', value: contextRow.categoryName),
      (label: 'Date', value: transaction.occurredAt.monthDayYear),
      (
        label: 'Time',
        value:
            '${transaction.occurredAt.hour.toString().padLeft(2, '0')}:'
            '${transaction.occurredAt.minute.toString().padLeft(2, '0')}',
      ),
      if (transaction.referenceNumber != null)
        (label: 'Reference', value: transaction.referenceNumber),
      if (transaction.location != null)
        (label: 'Location', value: transaction.location),
      if (transaction.note != null) (label: 'Note', value: transaction.note),
    ];

    final isDark = context.isDarkMode;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        // Gradient hero coloured by the transaction type.
        Container(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.xl),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [
                      Color.lerp(visual.color, Colors.black, 0.30)!,
                      Color.lerp(visual.color, Colors.black, 0.55)!,
                    ]
                  : [
                      visual.color.withValues(alpha: 0.92),
                      Color.lerp(visual.color, Colors.black, 0.38)!,
                    ],
            ),
            boxShadow: [
              BoxShadow(
                color: visual.color.withValues(alpha: 0.35),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(visual.icon, color: Colors.white, size: 28),
              ),
              const SizedBox(height: 16),
              Text(
                transaction.title,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              AmountText(
                transaction.type == TransactionType.expense
                    ? -transaction.amountMinor
                    : transaction.amountMinor,
                currencyCode: transaction.currencyCode,
                showSign: true,
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${transaction.occurredAt.monthDayYear} · '
                '${contextRow.accountName ?? contextRow.categoryName ?? ''}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        const SectionHeader(title: 'Details'),
        const SizedBox(height: AppSpacing.sm),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            children: [
              for (final (index, detail) in details.indexed) ...[
                if (index > 0) const Divider(height: 1),
                _DetailRow(label: detail.label, value: detail.value ?? '—'),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        FilledButton.tonalIcon(
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.errorContainer,
            foregroundColor: theme.colorScheme.onErrorContainer,
          ),
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline),
          label: const Text('Delete Transaction'),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
