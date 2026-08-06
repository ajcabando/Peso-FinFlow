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
    label: 'Card Purchase',
    icon: Icons.credit_card_rounded,
    color: AppColors.pink,
    type: TransactionType.expense,
  ),
  QuickAction(
    label: 'Card Payment',
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
///
/// Kept deliberately compact so it never swallows a phone screen: small
/// icon tiles with single-line labels, a three-column grid (five on wide
/// screens) and a scroll wrapper as a safety net for very short viewports.
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
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Quick actions',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                'Record a transaction in a tap',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              LayoutBuilder(
                builder: (context, constraints) {
                  // Three columns on phones, five across on tablets/web so
                  // the grid never stretches into oversized cells.
                  final columns = constraints.maxWidth >= 600 ? 5 : 3;
                  return GridView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: AppSpacing.sm,
                      crossAxisSpacing: AppSpacing.sm,
                      mainAxisExtent: 68,
                    ),
                    children: [
                      for (final action in quickActions)
                        _QuickActionButton(
                          action: action,
                          onTap: () => _open(context, action),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: AppSpacing.md),
              const Divider(height: 1),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: _ShortcutTile(
                      icon: Icons.event_repeat_outlined,
                      label: 'Bills',
                      color: AppColors.warning,
                      onTap: () {
                        final router = GoRouter.of(context);
                        Navigator.of(context).pop();
                        router.push(AppRoutes.bills);
                      },
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: _ShortcutTile(
                      icon: Icons.description_outlined,
                      label: 'Reports',
                      color: AppColors.info,
                      onTap: () {
                        final router = GoRouter.of(context);
                        Navigator.of(context).pop();
                        router.push(AppRoutes.reports);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A compact shortcut tile for full pages (Bills, Reports).
class _ShortcutTile extends StatelessWidget {
  const _ShortcutTile({
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
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      action.color.withValues(alpha: 0.85),
                      action.color.withValues(alpha: 0.65),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  boxShadow: [
                    BoxShadow(
                      color: action.color.withValues(alpha: 0.30),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(action.icon, color: Colors.white, size: 20),
              ),
            ),
            const SizedBox(height: 6),
            // Flexible + FittedBox keeps the fixed tile height safe at large
            // accessibility text scales: the label shrinks instead of
            // overflowing the cell.
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  action.label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
