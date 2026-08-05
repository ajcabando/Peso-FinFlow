import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers/app_providers.dart';
import '../../../../app/router/app_router.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radii.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/engine/transaction_builder.dart';
import '../../domain/enums/transaction_type.dart';
import '../../domain/models/draft_transaction.dart';
import '../../domain/models/transaction_context.dart';
import '../../domain/models/transaction_edit_data.dart';
import '../providers/transaction_providers.dart';
import 'transaction_list_tile.dart';

/// A transaction row with swipe gestures: swipe left reveals Delete, swipe
/// right reveals Edit, and long-press offers Duplicate / Attach Receipt.
class SwipeableTransactionTile extends ConsumerWidget {
  const SwipeableTransactionTile({
    super.key,
    required this.contextRow,
    this.onTap,
  });

  final TransactionContext contextRow;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transaction = contextRow.transaction;

    return Slidable(
      key: ValueKey(transaction.id),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.32,
        children: [
          SlidableAction(
            onPressed: (_) => _delete(context, ref),
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Colors.white,
            icon: Icons.delete_outline_rounded,
            label: 'Delete',
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
        ],
      ),
      startActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.32,
        children: [
          SlidableAction(
            onPressed: (_) => context.push(
              AppRoutes.transactionEdit(transaction.id),
            ),
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Colors.white,
            icon: Icons.edit_outlined,
            label: 'Edit',
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
        ],
      ),
      child: GestureDetector(
        onLongPress: () => _showLongPressMenu(context, ref),
        child: TransactionListTile.context(
          contextRow,
          onTap: onTap,
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final transaction = contextRow.transaction;
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
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(transactionRepositoryProvider).delete(transaction.id);
      if (!context.mounted) return;
      context.showSnack('Transaction deleted');
    } on FinFlowException catch (error) {
      if (!context.mounted) return;
      context.showSnack(error.message);
    }
  }

  Future<void> _duplicate(BuildContext context, WidgetRef ref) async {
    final transaction = contextRow.transaction;
    try {
      final editData = await ref
          .read(transactionEditDataProvider(transaction.id).future);
      if (editData == null) {
        if (!context.mounted) return;
        context.showSnack('Could not duplicate transaction.');
        return;
      }

      final draft = _draftFrom(editData);
      if (draft == null) {
        if (!context.mounted) return;
        context.showSnack('This transaction type cannot be duplicated.');
        return;
      }

      await ref.read(transactionRepositoryProvider).create(draft);
      if (!context.mounted) return;
      context.showSnack('Transaction duplicated');
    } on FinFlowException catch (error) {
      if (!context.mounted) return;
      context.showSnack(error.message);
    }
  }

  void _showLongPressMenu(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                contextRow.transaction.title,
                style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                contextRow.transaction.type.label,
                style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                  color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              _SheetAction(
                icon: Icons.copy_all_outlined,
                label: 'Duplicate',
                color: Theme.of(sheetContext).colorScheme.primary,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _duplicate(context, ref);
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              _SheetAction(
                icon: Icons.camera_alt_outlined,
                label: 'Attach Receipt',
                color: AppColors.gold,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  if (!context.mounted) return;
                  context.showSnack('Receipt attachment is coming soon.');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Rebuilds a duplicate draft from the stored edit data, preserving the
  /// type, accounts, category, merchant and notes but using today's date.
  static DraftTransaction? _draftFrom(TransactionEditData editData) {
    final t = editData.transaction;
    final source = editData.sourceAccountId;
    final destination = editData.destinationAccountId;
    final category = editData.categoryId;
    final now = DateTime.now();

    switch (t.type) {
      case TransactionType.expense:
        if (source == null || category == null) return null;
        return TransactionBuilder.expense(
          occurredAt: now,
          currencyCode: t.currencyCode,
          fromAccountId: source,
          categoryId: category,
          amountMinor: t.amountMinor,
          merchant: t.merchant,
          note: t.note,
        );
      case TransactionType.income:
        if (source == null || category == null) return null;
        return TransactionBuilder.income(
          occurredAt: now,
          currencyCode: t.currencyCode,
          toAccountId: source,
          categoryId: category,
          amountMinor: t.amountMinor,
          merchant: t.merchant,
          note: t.note,
        );
      case TransactionType.transfer:
        if (source == null || destination == null) return null;
        return TransactionBuilder.transfer(
          occurredAt: now,
          currencyCode: t.currencyCode,
          fromAccountId: source,
          toAccountId: destination,
          amountMinor: t.amountMinor,
          note: t.note,
        );
      case TransactionType.refund:
        if (source == null || category == null) return null;
        return TransactionBuilder.refund(
          occurredAt: now,
          currencyCode: t.currencyCode,
          toAccountId: source,
          categoryId: category,
          amountMinor: t.amountMinor,
          note: t.note,
        );
      case TransactionType.adjustment ||
            TransactionType.openingBalance:
        return null;
    }
  }
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 21),
              ),
              const SizedBox(width: AppSpacing.md),
              Text(
                label,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
