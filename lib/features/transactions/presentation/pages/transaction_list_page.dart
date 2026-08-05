import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/app_router.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/app_chip.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../../shared/widgets/empty_state_view.dart';
import '../../domain/enums/transaction_type.dart';
import '../../domain/models/transaction_context.dart';
import '../providers/transaction_providers.dart';
import '../widgets/swipeable_transaction_tile.dart';

/// The full transaction history with instant search and type filters.
class TransactionListPage extends ConsumerStatefulWidget {
  const TransactionListPage({super.key});

  @override
  ConsumerState<TransactionListPage> createState() =>
      _TransactionListPageState();
}

class _TransactionListPageState extends ConsumerState<TransactionListPage> {
  final _searchController = TextEditingController();
  TransactionType? _typeFilter;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<TransactionContext> _applyFilters(List<TransactionContext> contexts) {
    final query = _searchController.text.trim().toLowerCase();
    return contexts.where((context) {
      final t = context.transaction;
      if (_typeFilter != null && t.type != _typeFilter) return false;
      if (query.isEmpty) return true;
      return (t.title.toLowerCase().contains(query) ||
          (t.note?.toLowerCase().contains(query) ?? false) ||
          (context.accountName?.toLowerCase().contains(query) ?? false) ||
          (context.categoryName?.toLowerCase().contains(query) ?? false));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final transactionsAsync = ref.watch(allTransactionContextsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
        actions: [
          IconButton(
            tooltip: 'Add Transaction',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => context.push(AppRoutes.transactionForm),
          ),
        ],
      ),
      body: transactionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (transactions) {
          final filtered = _applyFilters(transactions);
          final total = transactions.length;

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: AppTextField(
                  label: 'Search',
                  hintText: 'Merchant or note…',
                  prefixIcon: Icons.search,
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              SizedBox(
                height: 52,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  children: [
                    AppSelectableChip(
                      label: 'All',
                      selected: _typeFilter == null,
                      onSelected: (_) => setState(() => _typeFilter = null),
                    ),
                    for (final type in const [
                      TransactionType.income,
                      TransactionType.expense,
                      TransactionType.transfer,
                      TransactionType.refund,
                    ]) ...[
                      const SizedBox(width: 8),
                      AppSelectableChip(
                        label: type.label,
                        selected: _typeFilter == type,
                        onSelected: (selected) => setState(() {
                          _typeFilter = selected ? type : null;
                        }),
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? EmptyStateView(
                        icon: Icons.receipt_long_outlined,
                        title: transactions.isEmpty
                            ? 'No transactions yet'
                            : 'Nothing matches',
                        message: total == 0
                            ? 'Record income, expenses and transfers to start '
                                  'building your ledger.'
                            : 'Try a different search or clear the filters.',
                        actionLabel: total == 0 ? 'Add Transaction' : null,
                        onAction: total == 0
                            ? () => context.push(AppRoutes.transactionForm)
                            : null,
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                        children: [
                          AppCard(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 6,
                            ),
                            child: Column(
                              children: [
                                for (var i = 0; i < filtered.length; i++) ...[
                                  if (i > 0) const Divider(height: 1),
                                  SwipeableTransactionTile(
                                    contextRow: filtered[i],
                                    onTap: () => context.push(
                                      AppRoutes.transactionDetail(
                                        filtered[i].transaction.id,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
