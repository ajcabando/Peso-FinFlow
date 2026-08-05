import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers/app_providers.dart';
import '../../../../app/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/circular_chart_card.dart';
import '../../../../shared/widgets/empty_state_view.dart';
import '../../../../shared/widgets/month_selector.dart';
import '../../../../shared/widgets/section_header.dart';
import '../../domain/models/budget_progress.dart';
import '../providers/budget_providers.dart';
import '../widgets/budget_progress_tile.dart';

/// Monthly budgets with ledger-derived progress for a selectable month.
class BudgetsPage extends ConsumerStatefulWidget {
  const BudgetsPage({super.key});

  @override
  ConsumerState<BudgetsPage> createState() => _BudgetsPageState();
}

class _BudgetsPageState extends ConsumerState<BudgetsPage> {
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month, 1);
  }

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(defaultCurrencyProvider);
    final progressAsync = ref.watch(budgetProgressProvider(_month));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Budgets'),
        actions: [
          IconButton(
            tooltip: 'New budget',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => context.push(AppRoutes.budgetForm),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          MonthSelector(
            month: _month,
            onMonthChanged: (month) => setState(() => _month = month),
          ),
          const SizedBox(height: AppSpacing.xl),
          SectionHeader(title: 'Monthly budgets'),
          progressAsync.when(
            loading: () => const SizedBox(
              height: 220,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) =>
                AppCard(child: Text('Could not load budgets: $error')),
            data: (progress) {
              if (progress.isEmpty) {
                return EmptyStateView(
                  icon: Icons.savings_outlined,
                  title: 'No budgets yet',
                  message:
                      'Set a monthly limit for a category and track your '
                      'spending against it — powered by your double-entry '
                      'ledger.',
                  actionLabel: 'Create budget',
                  onAction: () => context.push(AppRoutes.budgetForm),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _BudgetSummaryCard(
                    progress: progress,
                    currencyCode: currency,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  for (final entry in progress) ...[
                    AppCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: AppSpacing.md,
                      ),
                      onTap: () =>
                          context.push(AppRoutes.budgetEdit(entry.budget.id)),
                      child: BudgetProgressTile(
                        progress: entry,
                        currencyCode: currency,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _BudgetSummaryCard extends StatelessWidget {
  const _BudgetSummaryCard({
    required this.progress,
    required this.currencyCode,
  });

  final List<BudgetProgress> progress;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final budgeted = progress.fold<int>(0, (sum, p) => sum + p.amountMinor);
    final spent = progress.fold<int>(0, (sum, p) => sum + p.spentMinor);
    final remaining = budgeted - spent;
    final fraction = budgeted == 0 ? 0.0 : spent / budgeted;

    Widget column(String label, int minor, {Color? valueColor}) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          CurrencyFormatter.format(minor, currencyCode),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: valueColor,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );

    return AppCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xl,
        ),
        child: Row(
          children: [
            CircularChartCard(
              progress: fraction,
              size: 116,
              centerTitle: 'SPENT',
              centerValue: '${(fraction * 100).round()}%',
              centerSubtitle:
                  '${CurrencyFormatter.format(spent, currencyCode)} of '
                  '${CurrencyFormatter.format(budgeted, currencyCode)}',
            ),
            const SizedBox(width: AppSpacing.xl),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  column('BUDGETED', budgeted),
                  const SizedBox(height: AppSpacing.md),
                  column('SPENT', spent, valueColor: AppColors.expense),
                  const SizedBox(height: AppSpacing.md),
                  column(
                    'LEFT',
                    remaining,
                    valueColor: remaining < 0
                        ? AppColors.expense
                        : context.colors.primary,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
