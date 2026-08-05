import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers/app_providers.dart';
import '../../../../app/router/app_router.dart';
import '../../../../core/extensions/num_extensions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_radii.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/empty_state_view.dart';
import '../../../../shared/widgets/section_header.dart';
import '../providers/account_providers.dart';
import '../widgets/account_card_grid.dart';

/// Lists every real account as a large card with its live, ledger-derived
/// balance and a six-month sparkline.
class AccountsPage extends ConsumerWidget {
  const AccountsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(accountsWithBalancesProvider);
    final defaultCurrency = ref.watch(defaultCurrencyProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Accounts'),
        actions: [
          IconButton(
            tooltip: 'Add Account',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => context.push(AppRoutes.accountForm),
          ),
        ],
      ),
      body: accountsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (accounts) {
          if (accounts.isEmpty) {
            return EmptyStateView(
              icon: Icons.account_balance_wallet_outlined,
              title: 'No accounts yet',
              message:
                  'Add your first account — cash, bank, e-wallet or credit '
                  'card — and FinFlow will start tracking it.',
              actionLabel: 'Add Account',
              onAction: () => context.push(AppRoutes.accountForm),
            );
          }

          final total = accounts
              .where((entry) => !entry.account.isHidden)
              .fold<int>(0, (sum, entry) => sum + entry.balanceMinor);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              _AccountsHero(
                totalMinor: total,
                currencyCode: defaultCurrency,
                accountCount: accounts.length,
              ),
              const SizedBox(height: AppSpacing.xl),
              const SectionHeader(title: 'Your accounts'),
              const SizedBox(height: AppSpacing.sm),
              AccountCardGrid(
                accounts: accounts,
                onTapAccount: (id) =>
                    context.push(AppRoutes.accountDetail(id)),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Gradient header summarising total balances, matching the reference's
/// green gradient hero.
class _AccountsHero extends StatelessWidget {
  const _AccountsHero({
    required this.totalMinor,
    required this.currencyCode,
    required this.accountCount,
  });

  final int totalMinor;
  final String currencyCode;
  final int accountCount;

  @override
  Widget build(BuildContext context) {
    final heroGradient =
        Theme.of(context).extension<FinFlowTheme>()?.heroGradient ??
        const [AppColors.brandBright, AppColors.brand];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TOTAL BALANCE',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // FittedBox keeps the total readable on narrow phones: huge
          // balances scale down instead of overflowing the hero card.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              totalMinor.asMoney(currencyCode),
              style: AppTypography.money(context, size: 30).copyWith(
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(999),
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
    );
  }
}
