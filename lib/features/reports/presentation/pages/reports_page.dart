import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/empty_state_view.dart';
import '../../../../shared/widgets/month_selector.dart';
import '../../../../shared/widgets/section_header.dart';
import '../../../accounts/presentation/widgets/account_type_ui.dart';
import '../../../transactions/domain/models/category_spend.dart';
import '../../../transactions/presentation/widgets/transaction_list_tile.dart';
import '../../data/report_exporter.dart';
import '../providers/report_providers.dart';

/// Period reports: income/expense summary, category breakdown and the full
/// transaction list, exportable as CSV or PDF.
class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});

  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  late DateTime _month;
  bool _exportingCsv = false;
  bool _exportingPdf = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month, 1);
  }

  Future<void> _exportCsv(ReportData report) async {
    setState(() => _exportingCsv = true);
    try {
      await ReportExporter.exportCsv(report);
      if (mounted) context.showSnack('CSV downloaded');
    } on Exception {
      if (mounted) context.showSnack('Could not export CSV.');
    } finally {
      if (mounted) setState(() => _exportingCsv = false);
    }
  }

  Future<void> _exportPdf(ReportData report) async {
    setState(() => _exportingPdf = true);
    try {
      await ReportExporter.exportPdf(report);
      if (mounted) context.showSnack('PDF downloaded');
    } on Exception {
      if (mounted) context.showSnack('Could not export PDF.');
    } finally {
      if (mounted) setState(() => _exportingPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reportAsync = ref.watch(reportDataProvider(_month));

    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          MonthSelector(
            month: _month,
            onMonthChanged: (month) => setState(() => _month = month),
          ),
          const SizedBox(height: AppSpacing.xl),
          reportAsync.when(
            loading: () => const SizedBox(
              height: 260,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) =>
                AppCard(child: Text('Could not load report: $error')),
            data: (report) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ReportSummaryCard(report: report),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: AppChipAction(
                        icon: Icons.table_chart_outlined,
                        label: 'Export CSV',
                        loading: _exportingCsv,
                        onTap: () => _exportCsv(report),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: AppChipAction(
                        icon: Icons.picture_as_pdf_outlined,
                        label: 'Export PDF',
                        loading: _exportingPdf,
                        onTap: () => _exportPdf(report),
                      ),
                    ),
                  ],
                ),
                if (report.categories.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xl),
                  const SectionHeader(title: 'Spending by category'),
                  AppCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.md,
                    ),
                    child: Column(
                      children: [
                        for (final (index, spend)
                            in report.categories.where((c) => !c.isIncome)
                                .toList()
                                .indexed) ...[
                          if (index > 0) const Divider(height: AppSpacing.xl),
                          _CategoryRow(
                            spend: spend,
                            currencyCode: report.currencyCode,
                            totalExpense: report.expenseMinor,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                SectionHeader(
                  title: 'Transactions (${report.contexts.length})',
                ),
                if (report.contexts.isEmpty)
                  EmptyStateView(
                    icon: Icons.receipt_long_outlined,
                    title: 'No transactions this month',
                    message:
                        'Add income or expenses and they will appear in the '
                        'report and its exports.',
                  )
                else
                  AppCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    child: Column(
                      children: [
                        for (final context in report.contexts)
                          TransactionListTile.context(context),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// An export action pill (reuses the selectable-chip visual language).
class AppChipAction extends StatelessWidget {
  const AppChipAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.loading = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      onTap: loading ? null : onTap,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (loading)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            )
          else
            Icon(icon, size: 20, color: context.colors.primary),
          const SizedBox(width: AppSpacing.sm),
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportSummaryCard extends StatelessWidget {
  const _ReportSummaryCard({required this.report});

  final ReportData report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currency = report.currencyCode;

    Widget column(String label, int minor, {required Color color}) => Column(
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
          CurrencyFormatter.format(minor, currency),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: color,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );

    return AppCard(
      child: Row(
        children: [
          Expanded(
            child: column('INCOME', report.incomeMinor, color: AppColors.income),
          ),
          Expanded(
            child: column(
              'EXPENSE',
              report.expenseMinor,
              color: AppColors.expense,
            ),
          ),
          Expanded(
            child: column(
              'NET',
              report.netMinor,
              color: report.netMinor >= 0 ? AppColors.income : AppColors.expense,
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.spend,
    required this.currencyCode,
    required this.totalExpense,
  });

  final CategorySpend spend;
  final String currencyCode;
  final int totalExpense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = totalExpense == 0 ? 0.0 : spend.amountMinor / totalExpense;
    final color = Color(spend.colorValue);

    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(
            iconFromCode(spend.iconCode, fallback: Icons.category_outlined),
            color: color,
            size: 18,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                spend.categoryName,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: fraction,
                  minHeight: 5,
                  color: color,
                  backgroundColor: color.withValues(alpha: 0.12),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Text(
          CurrencyFormatter.format(spend.amountMinor, currencyCode),
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

}
