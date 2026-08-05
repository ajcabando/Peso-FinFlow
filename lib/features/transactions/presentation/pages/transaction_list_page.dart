import 'dart:async';

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
import '../providers/transaction_list_controller.dart';
import '../widgets/swipeable_transaction_tile.dart';

/// The full transaction history with instant search and type filters,
/// loaded in pages so very large ledgers stay fast.
class TransactionListPage extends ConsumerStatefulWidget {
  const TransactionListPage({super.key});

  @override
  ConsumerState<TransactionListPage> createState() =>
      _TransactionListPageState();
}

class _TransactionListPageState extends ConsumerState<TransactionListPage> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter < 400) {
      ref
          .read(transactionListControllerProvider.notifier)
          .loadMore();
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      ref
          .read(transactionListControllerProvider.notifier)
          .setFilters(search: value);
    });
  }

  void _setTypeFilter(TransactionType? type) {
    ref
        .read(transactionListControllerProvider.notifier)
        .setFilters(type: type);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(transactionListControllerProvider);
    final controller = ref.read(transactionListControllerProvider.notifier);

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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: AppTextField(
              label: 'Search',
              hintText: 'Merchant or note…',
              prefixIcon: Icons.search,
              controller: _searchController,
              onChanged: _onSearchChanged,
            ),
          ),
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              children: [
                AppSelectableChip(
                  label: 'All',
                  selected: state.type == null,
                  onSelected: (_) => _setTypeFilter(null),
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
                    selected: state.type == type,
                    onSelected: (selected) =>
                        _setTypeFilter(selected ? type : null),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: _buildBody(state, controller),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    TransactionListState state,
    TransactionListController controller,
  ) {
    if (state.initialLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.items.isEmpty) {
      return EmptyStateView(
        icon: Icons.receipt_long_outlined,
        title: state.total == 0 ? 'No transactions yet' : 'Nothing matches',
        message: state.total == 0
            ? 'Record income, expenses and transfers to start building '
                  'your ledger.'
            : 'Try a different search or clear the filters.',
        actionLabel: state.total == 0 ? 'Add Transaction' : null,
        onAction: state.total == 0
            ? () => context.push(AppRoutes.transactionForm)
            : null,
      );
    }

    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(
            children: [
              for (var i = 0; i < state.items.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                SwipeableTransactionTile(
                  contextRow: state.items[i],
                  onTap: () => context.push(
                    AppRoutes.transactionDetail(state.items[i].transaction.id),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (state.hasMore) ...[
          const SizedBox(height: AppSpacing.lg),
          Center(
            child: state.loadingMore
                ? const SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                : TextButton.icon(
                    onPressed: controller.loadMore,
                    icon: const Icon(Icons.expand_more_rounded),
                    label: Text(
                      'Load more (${state.items.length} of ${state.total})',
                    ),
                  ),
          ),
        ] else if (state.total > state.items.length)
          const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}
