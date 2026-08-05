import 'package:flutter/material.dart';

import '../../../../core/extensions/num_extensions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_radii.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/sparkline.dart';

/// The dashboard hero: a large gradient balance card with Net Worth, a
/// twelve-month trend sparkline, account count and monthly income / expense /
/// savings stats.
class BalanceCard extends StatelessWidget {
  const BalanceCard({
    super.key,
    required this.netWorthMinor,
    required this.currencyCode,
    required this.accountCount,
    this.incomeMinor = 0,
    this.expenseMinor = 0,
    this.trendMinor = const [],
  });

  final int netWorthMinor;
  final String currencyCode;
  final int accountCount;

  /// Monthly income and expense (for the stats row); defaults to zero when
  /// the cash flow data is not loaded yet.
  final int incomeMinor;
  final int expenseMinor;

  /// Net worth at the end of each of the last 12 months (oldest first) for
  /// the hero sparkline. Hidden when fewer than two points exist.
  final List<int> trendMinor;

  @override
  Widget build(BuildContext context) {
    final heroGradient =
        Theme.of(context).extension<FinFlowTheme>()?.heroGradient ??
        const [AppColors.brandBright, AppColors.brand];
    final savingsMinor = incomeMinor - expenseMinor;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.xl),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: heroGradient,
        ),
        boxShadow: [
          BoxShadow(
            color: heroGradient.last.withValues(alpha: 0.4),
            blurRadius: 32,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(
                    Icons.account_balance_wallet_outlined,
                    color: Colors.white,
                    size: 19,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                  child: Text(
                    '$accountCount account${accountCount == 1 ? '' : 's'}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              'NET WORTH',
              style: AppTypography.eyebrow(context).copyWith(
                color: Colors.white.withValues(alpha: 0.75),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: netWorthMinor.toDouble()),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => Text(
                value.round().asMoney(currencyCode),
                style: AppTypography.money(
                  context,
                  size: 34,
                ).copyWith(color: Colors.white),
              ),
            ),
            if (trendMinor.length >= 2) ...[
              const SizedBox(height: AppSpacing.lg),
              Sparkline(
                values: trendMinor,
                height: 36,
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            Container(
              height: 1,
              color: Colors.white.withValues(alpha: 0.18),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                _Stat(
                  label: 'Income',
                  amountMinor: incomeMinor,
                  currencyCode: currencyCode,
                  icon: Icons.arrow_upward_rounded,
                  iconColor: const Color(0xFFA7F3D0),
                ),
                _Stat(
                  label: 'Expense',
                  amountMinor: expenseMinor,
                  currencyCode: currencyCode,
                  icon: Icons.arrow_downward_rounded,
                  iconColor: const Color(0xFFFECACA),
                ),
                _Stat(
                  label: 'Savings',
                  amountMinor: savingsMinor,
                  currencyCode: currencyCode,
                  icon: Icons.savings_outlined,
                  iconColor: const Color(0xFFFDE68A),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.amountMinor,
    required this.currencyCode,
    required this.icon,
    required this.iconColor,
  });

  final String label;
  final int amountMinor;
  final String currencyCode;
  final IconData icon;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: iconColor),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            amountMinor.asMoney(currencyCode),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              fontFamily: AppTypography.fontFamily,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
