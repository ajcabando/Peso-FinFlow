import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers/app_providers.dart';
import '../../../../app/router/app_router.dart';
import '../../../../core/extensions/date_time_extensions.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/month_selector.dart';
import '../../../../shared/widgets/section_header.dart';
import '../../../transactions/presentation/providers/transaction_providers.dart';
import '../widgets/category_spend_section.dart';
import '../widgets/net_worth_trend_chart.dart';

/// Deep-dive analytics: net worth history plus income & expense breakdowns,
/// scoped to a selectable month.
class AnalyticsPage extends ConsumerStatefulWidget {
  const AnalyticsPage({super.key});

  @override
  ConsumerState<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends ConsumerState<AnalyticsPage> {
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
    final trendAsync = ref.watch(netWorthTrendProvider);
    final spendAsync = ref.watch(categorySpendProvider(_month));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics'),
        actions: [
          IconButton(
            tooltip: 'Reports & exports',
            icon: const Icon(Icons.description_outlined),
            onPressed: () => context.push(AppRoutes.reports),
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
          const SectionHeader(
            title: 'Net worth history',
            actionLabel: 'Last 12 months',
          ),
          trendAsync.when(
            loading: () => const SizedBox(
              height: 220,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => AppCard(
              child: Text('Could not load net worth history: $error'),
            ),
            data: (points) =>
                NetWorthTrendChart(points: points, currencyCode: currency),
          ),
          const SizedBox(height: AppSpacing.xl),
          const SectionHeader(title: 'Spending by category'),
          spendAsync.when(
            loading: () => const SizedBox(
              height: 260,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) =>
                AppCard(child: Text('Could not load spending: $error')),
            data: (spends) => CategorySpendSection(
              spends: spends.where((s) => !s.isIncome).toList(),
              currencyCode: currency,
              emptyMessage: 'No expenses recorded in ${_month.monthYear}.',
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          const SectionHeader(title: 'Income by category'),
          spendAsync.when(
            loading: () => const SizedBox(
              height: 180,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) =>
                AppCard(child: Text('Could not load income: $error')),
            data: (spends) => CategorySpendSection(
              spends: spends.where((s) => s.isIncome).toList(),
              currencyCode: currency,
              emptyMessage: 'No income recorded in ${_month.monthYear}.',
            ),
          ),
        ],
      ),
    );
  }
}
