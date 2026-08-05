import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../features/transactions/domain/enums/transaction_type.dart';

/// Quick action definitions shown in the FAB sheet. Each entry maps to the
/// transaction form pre-seeded with a type (and a hint colour).
class QuickAction {
  const QuickAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.type,
  });

  final String label;
  final IconData icon;
  final Color color;
  final TransactionType type;
}

const List<QuickAction> quickActions = [
  QuickAction(
    label: 'Income',
    icon: Icons.south_west_rounded,
    color: AppColors.income,
    type: TransactionType.income,
  ),
  QuickAction(
    label: 'Expense',
    icon: Icons.north_east_rounded,
    color: AppColors.expense,
    type: TransactionType.expense,
  ),
  QuickAction(
    label: 'Transfer',
    icon: Icons.swap_horiz_rounded,
    color: AppColors.blue,
    type: TransactionType.transfer,
  ),
  QuickAction(
    label: 'Cash In',
    icon: Icons.add_card_rounded,
    color: AppColors.green,
    type: TransactionType.income,
  ),
  QuickAction(
    label: 'Cash Out',
    icon: Icons.currency_exchange_rounded,
    color: AppColors.coral,
    type: TransactionType.expense,
  ),
  QuickAction(
    label: 'Credit Card Purchase',
    icon: Icons.credit_card_rounded,
    color: AppColors.pink,
    type: TransactionType.expense,
  ),
  QuickAction(
    label: 'Credit Card Payment',
    icon: Icons.payment_rounded,
    color: AppColors.brand,
    type: TransactionType.transfer,
  ),
  QuickAction(
    label: 'Loan',
    icon: Icons.request_quote_rounded,
    color: AppColors.info,
    type: TransactionType.income,
  ),
  QuickAction(
    label: 'Investment',
    icon: Icons.trending_up_rounded,
    color: Color(0xFF8B5CF6),
    type: TransactionType.income,
  ),
];

/// Modal bottom sheet listing the quick actions; each opens the transaction
/// form with the matching type pre-selected.
class QuickActionsSheet extends StatelessWidget {
  const QuickActionsSheet({super.key});

  Future<void> _open(BuildContext context, QuickAction action) async {
    // Resolve the router before popping the sheet so the navigation call
    // never uses a deactivated context.
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    await router.push(
      AppRoutes.transactionForm,
      extra: action.type,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quick actions',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Record a transaction in a tap',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 3,
              mainAxisSpacing: AppSpacing.md,
              crossAxisSpacing: AppSpacing.md,
              childAspectRatio: 0.95,
              children: [
                for (final action in quickActions)
                  _QuickActionButton(
                    action: action,
                    onTap: () => _open(context, action),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({required this.action, required this.onTap});

  final QuickAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    action.color.withValues(alpha: 0.85),
                    action.color.withValues(alpha: 0.65),
                  ],
                ),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: action.color.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Icon(action.icon, color: Colors.white, size: 24),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              action.label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
