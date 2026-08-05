import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers/app_providers.dart';
import '../../../../app/router/app_router.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_time_extensions.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/empty_state_view.dart';
import '../../../../shared/widgets/section_header.dart';
import '../../../accounts/domain/repositories/account_repository.dart';
import '../../../accounts/presentation/providers/account_providers.dart';
import '../../../accounts/presentation/widgets/account_card.dart';
import '../../../accounts/presentation/widgets/account_card_grid.dart';
import '../../../budgets/presentation/providers/budget_providers.dart';
import '../../../budgets/presentation/widgets/budget_progress_tile.dart';
import '../../../transactions/presentation/providers/transaction_providers.dart';
import '../../../transactions/presentation/widgets/transaction_list_tile.dart';
import '../widgets/balance_card.dart';
import '../widgets/cash_flow_chart.dart';
import '../widgets/category_spend_section.dart';

/// The FinFlow home screen: greeting, gradient balance hero, account strip,
/// cash flow, quick actions and a recent activity feed.
class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final netWorthAsync = ref.watch(netWorthProvider);
    final netWorthTrendAsync = ref.watch(netWorthTrendProvider);
    final accountsAsync = ref.watch(accountsWithBalancesProvider);
    final transactionsAsync = ref.watch(recentTransactionContextsProvider);
    final cashFlowAsync = ref.watch(monthlyCashFlowProvider);
    final currency = ref.watch(defaultCurrencyProvider);
    final currentMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
    final spendAsync = ref.watch(categorySpendProvider(currentMonth));
    final budgetAsync = ref.watch(budgetProgressProvider(currentMonth));

    // Current-month income/expense for the hero stats row.
    final currentFlow = cashFlowAsync.value
        ?.where(
          (f) => f.year == currentMonth.year && f.month == currentMonth.month,
        )
        .firstOrNull;

    final heroTrend = <int>[
      for (final point in netWorthTrendAsync.value ?? const [])
        point.netWorthMinor,
    ];

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    context.colors.primary,
                    context.colors.tertiary,
                  ],
                ),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(
                Icons.account_balance_wallet_outlined,
                color: Colors.white,
                size: 17,
              ),
            ),
            const SizedBox(width: 10),
            const Text('FinFlow'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Search transactions',
            icon: const Icon(Icons.search_rounded),
            onPressed: () => context.go(AppRoutes.transactions),
          ),
          IconButton(
            tooltip: 'Notifications',
            icon: const Icon(Icons.notifications_none_rounded),
            onPressed: () =>
                context.showSnack('Notifications are coming soon.'),
          ),
          IconButton(
            tooltip: 'Analytics',
            icon: const Icon(Icons.insights_outlined),
            onPressed: () => context.go(AppRoutes.analytics),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(netWorthProvider);
          ref.invalidate(netWorthTrendProvider);
          ref.invalidate(accountsWithBalancesProvider);
          ref.invalidate(recentTransactionContextsProvider);
          ref.invalidate(monthlyCashFlowProvider);
          ref.invalidate(categorySpendProvider(currentMonth));
          ref.invalidate(budgetProgressProvider(currentMonth));
          await Future<void>.delayed(const Duration(milliseconds: 300));
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
          children: [
            const _GreetingHeader(),
            const SizedBox(height: AppSpacing.lg),
            netWorthAsync.when(
              loading: () => const SizedBox(
                height: 170,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) =>
                  AppCard(child: Text('Could not load Net Worth: $error')),
              data: (netWorth) => BalanceCard(
                netWorthMinor: netWorth,
                currencyCode: currency,
                accountCount: accountsAsync.value?.length ?? 0,
                incomeMinor: currentFlow?.incomeMinor ?? 0,
                expenseMinor: currentFlow?.expenseMinor ?? 0,
                trendMinor: heroTrend,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            const SectionHeader(title: 'My accounts'),
            accountsAsync.when(
              loading: () => const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) =>
                  AppCard(child: Text('Could not load accounts: $error')),
              data: (accounts) => accounts.isEmpty
                  ? AppCard(
                      onTap: () => context.push(AppRoutes.accountForm),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: context.colors.primary.withValues(
                                alpha: 0.14,
                              ),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              Icons.account_balance_wallet_outlined,
                              color: context.colors.primary,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Text(
                              'Add your first account',
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded),
                        ],
                      ),
                    )
                  : _DashboardAccounts(
                      accounts: accounts,
                      onTapAccount: (id) => context.push(
                        AppRoutes.accountDetail(id),
                      ),
                    ),
            ),
            const SizedBox(height: AppSpacing.xl),
            SectionHeader(title: 'Cash flow', actionLabel: 'Last 6 months'),
            cashFlowAsync.when(
              loading: () => const SizedBox(
                height: 220,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) =>
                  AppCard(child: Text('Could not load cash flow: $error')),
              data: (flow) => CashFlowChart(flow: flow, currencyCode: currency),
            ),
            const SizedBox(height: AppSpacing.xl),
            const SectionHeader(title: 'Quick actions'),
            _QuickActions(
              onAddTransaction: () => context.push(AppRoutes.transactionForm),
              onViewTransactions: () => context.go(AppRoutes.transactions),
              onAddAccount: () => context.push(AppRoutes.accountForm),
              onViewBudgets: () => context.push(AppRoutes.budgets),
            ),
            const SizedBox(height: AppSpacing.xl),
            SectionHeader(
              title: 'Spending by category',
              actionLabel: 'View all',
              onAction: () => context.go(AppRoutes.analytics),
            ),
            spendAsync.when(
              loading: () => const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) =>
                  AppCard(child: Text('Could not load spending: $error')),
              data: (spends) => CategorySpendSection(
                spends: spends.where((s) => !s.isIncome).toList(),
                currencyCode: currency,
                limit: 4,
                compact: true,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            SectionHeader(
              title: 'Budgets',
              actionLabel: 'View all',
              onAction: () => context.push(AppRoutes.budgets),
            ),
            budgetAsync.when(
              loading: () => const SizedBox(
                height: 160,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) =>
                  AppCard(child: Text('Could not load budgets: $error')),
              data: (progress) {
                if (progress.isEmpty) {
                  return AppCard(
                    onTap: () => context.push(AppRoutes.budgetForm),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: context.colors.primary.withValues(
                              alpha: 0.14,
                            ),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            Icons.savings_outlined,
                            color: context.colors.primary,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(
                            'Set a monthly budget',
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded),
                      ],
                    ),
                  );
                }
                return AppCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.md,
                  ),
                  child: Column(
                    children: [
                      for (final (index, entry)
                          in progress.take(3).indexed) ...[
                        if (index > 0) const SizedBox(height: AppSpacing.lg),
                        BudgetProgressTile(
                          progress: entry,
                          currencyCode: currency,
                          compact: true,
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: AppSpacing.xl),
            SectionHeader(
              title: 'Recent activity',
              actionLabel: 'View all',
              onAction: () => context.go(AppRoutes.transactions),
            ),

            transactionsAsync.when(
              loading: () => const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) =>
                  AppCard(child: Text('Could not load activity: $error')),
              data: (transactions) => transactions.isEmpty
                  ? const EmptyStateView(
                      icon: Icons.receipt_long_outlined,
                      title: 'No transactions yet',
                      message:
                          'Once you add income and expenses they will show up '
                          'here, straight from your double-entry ledger.',
                    )
                  : AppCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      child: Column(
                        children: [
                          for (final transaction in transactions)
                            TransactionListTile.context(
                              transaction,
                              onTap: () => context.push(
                                AppRoutes.transactionDetail(
                                  transaction.transaction.id,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The dashboard's "My accounts" section, sized to the available width:
/// a swipeable horizontal strip on narrow phones, and an adaptive grid that
/// reflows into as many columns as fit on tablets, desktop and web.
class _DashboardAccounts extends StatelessWidget {
  const _DashboardAccounts({
    required this.accounts,
    required this.onTapAccount,
  });

  final List<AccountWithBalance> accounts;
  final ValueChanged<String> onTapAccount;

  /// Below this width the swipeable strip is more usable than a one-column
  /// grid; at or above it the section reflows into columns.
  static const double _gridBreakpoint = 560;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _gridBreakpoint) {
          return SizedBox(
            height: 148,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: accounts.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(width: AppSpacing.md),
              itemBuilder: (context, index) {
                final entry = accounts[index];
                return SizedBox(
                  width: 210,
                  child: AccountCard(
                    account: entry.account,
                    balanceMinor: entry.balanceMinor,
                    compact: true,
                    onTap: () => onTapAccount(entry.account.id),
                  ),
                );
              },
            ),
          );
        }

        return AccountCardGrid(
          accounts: accounts,
          compact: true,
          onTapAccount: onTapAccount,
        );
      },
    );
  }
}

/// Time-aware greeting ("Good morning") with the current date and an avatar.
class _GreetingHeader extends StatelessWidget {
  const _GreetingHeader();

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 18
        ? 'Good afternoon'
        : 'Good evening';

    final heroGradient =
        Theme.of(context).extension<FinFlowTheme>()?.heroGradient ??
        const [Color(0xFF9C6BFF), Color(0xFF6D5DF6)];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  greeting,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  DateTime.now().weekdayMonthDay,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: heroGradient,
              ),
              shape: BoxShape.circle,
              border: Border.all(
                color: theme.colorScheme.surface.withValues(alpha: 0.6),
                width: 2,
              ),
            ),
            child: const Icon(Icons.person_rounded, color: Colors.white, size: 24),
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.onAddTransaction,
    required this.onViewTransactions,
    required this.onAddAccount,
    required this.onViewBudgets,
  });

  final VoidCallback onAddTransaction;
  final VoidCallback onViewTransactions;
  final VoidCallback onAddAccount;
  final VoidCallback onViewBudgets;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final actions = <({IconData icon, String label, Color color, VoidCallback onTap})>[
      (
        icon: Icons.add_circle_outline,
        label: 'Add Transaction',
        color: scheme.primary,
        onTap: onAddTransaction,
      ),
      (
        icon: Icons.receipt_long_outlined,
        label: 'Transactions',
        color: scheme.tertiary,
        onTap: onViewTransactions,
      ),
      (
        icon: Icons.account_balance_wallet_outlined,
        label: 'Add Account',
        color: scheme.error,
        onTap: onAddAccount,
      ),
      (
        icon: Icons.savings_outlined,
        label: 'Set Budget',
        color: const Color(0xFF16C784),
        onTap: onViewBudgets,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // Two columns on narrow phones so labels stay readable; four across
        // once there is room.
        final columns = constraints.maxWidth >= 380 ? 4 : 2;
        const spacing = AppSpacing.md;
        final cardWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final action in actions)
              SizedBox(
                width: cardWidth,
                child: _ActionCard(
                  icon: action.icon,
                  label: action.label,
                  color: action.color,
                  onTap: action.onTap,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
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
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  color.withValues(alpha: 0.20),
                  color.withValues(alpha: 0.08),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
