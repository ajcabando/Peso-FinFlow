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
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/app_icon_tile.dart';
import '../../../../shared/widgets/empty_state_view.dart';
import '../../../../shared/widgets/section_header.dart';
import '../../../../shared/widgets/amount_text.dart';
import '../../../transactions/domain/models/transaction_context.dart';
import '../../../transactions/presentation/providers/transaction_providers.dart';
import '../../../transactions/presentation/widgets/transaction_list_tile.dart';
import '../../domain/enums/account_status.dart';
import '../../domain/models/account.dart';
import '../../domain/repositories/account_repository.dart';
import '../providers/account_providers.dart';
import '../widgets/account_gradient_card.dart';
import '../widgets/account_type_ui.dart';

/// Detail screen for a single account: its balance, information and the
/// transactions touching it, plus edit / archive / delete actions.
class AccountDetailPage extends ConsumerWidget {
  const AccountDetailPage({super.key, required this.accountId});

  final String accountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(accountsWithBalancesProvider);
    final transactionsAsync = ref.watch(
      accountTransactionContextsProvider(accountId),
    );

    return accountsAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(body: Center(child: Text('$error'))),
      data: (entries) {
        AccountWithBalance? match;
        for (final entry in entries) {
          if (entry.account.id == accountId) match = entry;
        }
        if (match == null) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(child: Text('Account not found.')),
          );
        }
        return _DetailBody(entry: match, transactionsAsync: transactionsAsync);
      },
    );
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.entry, required this.transactionsAsync});

  final AccountWithBalance entry;
  final AsyncValue<List<TransactionContext>> transactionsAsync;

  Future<void> _toggleArchive(BuildContext context, WidgetRef ref) async {
    final account = entry.account;
    final archived = account.status == AccountStatus.active;
    try {
      await ref
          .read(accountRepositoryProvider)
          .updateAccount(
            _withStatus(
              account,
              archived ? AccountStatus.archived : AccountStatus.active,
            ),
          );
      if (context.mounted) {
        context.showSnack(archived ? 'Account archived' : 'Account activated');
      }
    } on FinFlowException catch (error) {
      if (context.mounted) context.showSnack(error.message);
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete account?'),
        content: Text(
          '"${entry.account.name}" will be removed. Accounts with transaction '
          'history cannot be deleted — archive them instead.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(accountRepositoryProvider).deleteAccount(entry.account.id);
      if (context.mounted) {
        context.showSnack('Account deleted');
        context.pop();
      }
    } on FinFlowException catch (error) {
      if (context.mounted) context.showSnack(error.message);
    }
  }

  Account _withStatus(Account account, AccountStatus status) => Account(
    id: account.id,
    name: account.name,
    kind: account.kind,
    type: account.type,
    status: status,
    openingBalanceMinor: account.openingBalanceMinor,
    currencyCode: account.currencyCode,
    colorValue: account.colorValue,
    isHidden: account.isHidden,
    sortOrder: account.sortOrder,
    createdAt: account.createdAt,
    updatedAt: account.updatedAt,
    institution: account.institution,
    iconCode: account.iconCode,
    notes: account.notes,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = entry.account;
    final theme = context.theme;

    return Scaffold(
      appBar: AppBar(
        title: Text(account.name),
        actions: [
          PopupMenuButton<String>(
            onSelected: (action) {
              switch (action) {
                case 'edit':
                  context.push(AppRoutes.accountEdit(account.id));
                case 'archive':
                  _toggleArchive(context, ref);
                case 'delete':
                  _delete(context, ref);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'edit',
                child: ListTile(
                  leading: Icon(Icons.edit_outlined),
                  title: Text('Edit'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'archive',
                child: ListTile(
                  leading: Icon(
                    account.status == AccountStatus.active
                        ? Icons.archive_outlined
                        : Icons.unarchive_outlined,
                  ),
                  title: Text(
                    account.status == AccountStatus.active
                        ? 'Archive'
                        : 'Activate',
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete_outline),
                  title: Text('Delete'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            context.push('${AppRoutes.transactionForm}?account=${account.id}'),
        icon: const Icon(Icons.add),
        label: const Text('Transaction'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          AccountGradientCard(
            account: account,
            radius: AppRadii.xl,
            child: Row(
              children: [
                AppIconTile(
                  icon: iconFromCode(
                    account.iconCode,
                    fallback: accountTypeIcon(account.type),
                  ),
                  color: account.color,
                  size: 56,
                  iconSize: 26,
                  frosted: true,
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        account.type.label,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.72),
                        ),
                      ),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: AmountText(
                          entry.balanceMinor,
                          currencyCode: account.currencyCode,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (account.notes != null && account.notes!.isNotEmpty) ...[
            AppCard(
              child: Text(
                account.notes!,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          AppCard(
            child: Column(
              children: [
                _InfoRow(
                  label: 'Institution',
                  value: account.institution ?? '—',
                ),
                const Divider(height: 1),
                _InfoRow(label: 'Currency', value: account.currencyCode),
                const Divider(height: 1),
                _InfoRow(label: 'Status', value: account.status.label),
                const Divider(height: 1),
                _InfoRow(
                  label: 'Opened',
                  value: account.createdAt.monthDayYear,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          const SectionHeader(title: 'Recent activity'),
          transactionsAsync.when(
            loading: () => const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => AppCard(child: Text('$error')),
            data: (transactions) {
              if (transactions.isEmpty) {
                return const EmptyStateView(
                  icon: Icons.receipt_long_outlined,
                  title: 'No activity yet',
                  message:
                      'Transactions touching this account will appear here.',
                );
              }
              return AppCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < transactions.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      TransactionListTile.context(
                        transactions[i],
                        onTap: () => context.push(
                          AppRoutes.transactionDetail(
                            transactions[i].transaction.id,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
