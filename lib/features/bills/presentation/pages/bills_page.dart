import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers/app_providers.dart';
import '../../../../app/router/app_router.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/empty_state_view.dart';
import '../../../../shared/widgets/section_header.dart';
import '../../domain/models/bill.dart';
import '../providers/bill_providers.dart';
import '../widgets/bill_tile.dart';

/// Recurring bills and subscriptions with due-date tracking and one-tap
/// "mark paid" for the current month.
class BillsPage extends ConsumerStatefulWidget {
  const BillsPage({super.key});

  @override
  ConsumerState<BillsPage> createState() => _BillsPageState();
}

class _BillsPageState extends ConsumerState<BillsPage> {
  Future<void> _markPaid(Bill bill) async {
    try {
      await ref.read(billRepositoryProvider).markPaid(bill.id);
      if (!mounted) return;
      context.showSnack('${bill.name} marked as paid');
    } on Exception {
      if (!mounted) return;
      context.showSnack('Could not mark the bill as paid.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final billsAsync = ref.watch(billsProvider);
    final currency = ref.watch(defaultCurrencyProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bills & Reminders'),
        actions: [
          IconButton(
            tooltip: 'New bill',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => context.push(AppRoutes.billForm),
          ),
        ],
      ),
      body: billsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            AppCard(child: Text('Could not load bills: $error')),
        data: (bills) {
          final active = bills.where((b) => b.isActive).toList();
          final dueThisMonth = active
              .where(
                (b) =>
                    b.status != BillStatus.paid &&
                    b.status != BillStatus.paused,
              )
              .toList();
          final dueTotal = dueThisMonth.fold<int>(
            0,
            (sum, b) => sum + b.amountMinor,
          );

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              _BillsSummaryCard(
                totalDueMinor: dueTotal,
                currencyCode: currency,
                needingAttention: active.where((b) => b.needsAttention).length,
                billCount: active.length,
              ),
              const SizedBox(height: AppSpacing.xl),
              if (bills.isEmpty)
                EmptyStateView(
                  icon: Icons.event_repeat_outlined,
                  title: 'No bills yet',
                  message:
                      'Track rent, subscriptions and other recurring '
                      'payments. FinFlow will flag what is due — mark it '
                      'paid in a tap.',
                  actionLabel: 'Add a bill',
                  onAction: () => context.push(AppRoutes.billForm),
                )
              else ...[
                SectionHeader(
                  title: 'This month',
                  actionLabel: 'Add bill',
                  onAction: () => context.push(AppRoutes.billForm),
                ),
                AppCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.xs,
                  ),
                  child: Column(
                    children: [
                      for (final (index, bill) in bills.indexed) ...[
                        if (index > 0) const Divider(height: 1),
                        BillTile(
                          bill: bill,
                          currencyCode: bill.currencyCode,
                          onTap: () => context.push(AppRoutes.billEdit(bill.id)),
                          onMarkPaid: () => _markPaid(bill),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _BillsSummaryCard extends StatelessWidget {
  const _BillsSummaryCard({
    required this.totalDueMinor,
    required this.currencyCode,
    required this.needingAttention,
    required this.billCount,
  });

  final int totalDueMinor;
  final String currencyCode;
  final int needingAttention;
  final int billCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.warning.withValues(alpha: 0.85),
                  AppColors.coral,
                ],
              ),
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(
              Icons.event_repeat_outlined,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Due this month',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  CurrencyFormatter.format(totalDueMinor, currencyCode),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$needingAttention need attention',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: needingAttention > 0
                      ? AppColors.expense
                      : AppColors.income,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$billCount active bills',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
