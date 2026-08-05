import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/amount_text.dart';
import '../../../../shared/widgets/app_icon_tile.dart';
import '../../../../shared/widgets/sparkline.dart';
import '../../../transactions/domain/enums/normal_balance_side.dart';
import '../../../transactions/domain/models/balance_point.dart';
import '../../../transactions/presentation/providers/transaction_providers.dart';
import '../../domain/models/account.dart';
import 'account_gradient_card.dart';
import 'account_type_ui.dart';

/// A large tappable card for one account: icon, name, type, current balance
/// and a sparkline of the last six months so growth or shrinkage is visible
/// at a glance.
///
/// Rendered as a colourful gradient card derived from the account's colour
/// (which follows the active theme seed by default), with white text so every
/// account stands out and stays readable on any phone width — the balance
/// scales down instead of overflowing on narrow screens.
class AccountCard extends ConsumerWidget {
  const AccountCard({
    super.key,
    required this.account,
    required this.balanceMinor,
    this.onTap,
    this.compact = false,
  });

  final Account account;
  final int balanceMinor;
  final VoidCallback? onTap;

  /// Compact horizontal variant used for the dashboard account strip.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.theme;

    final trendAsync = ref.watch(accountBalanceTrendProvider(account.id));
    final trend = [
      for (final point in trendAsync.value ?? const <BalancePoint>[])
        point.balanceMinor,
    ];

    // Credit accounts with a positive balance are debt; flag it so the
    // semantic signal from the old red amount survives on the gradient card.
    final isOutstanding =
        account.normalBalanceSide == NormalBalanceSide.credit &&
        balanceMinor > 0;

    return AccountGradientCard(
      onTap: onTap,
      account: account,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Measured here, *outside* the inner Row: Row children that are not
          // flexible are laid out with unbounded width, so a LayoutBuilder
          // inside the Row would see Infinity. From the card's bounded width
          // we cap the amount so the account name always keeps room.
          final amountMaxWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth * 0.42
              : 120.0;

          if (compact) {
            return _CompactBody(
              theme: theme,
              account: account,
              balanceMinor: balanceMinor,
              amountMaxWidth: amountMaxWidth,
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AppIconTile(
                    icon: iconFromCode(
                      account.iconCode,
                      fallback: accountTypeIcon(account.type),
                    ),
                    color: account.color,
                    frosted: true,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          account.name,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          account.type.label,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.72),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (isOutstanding) ...[
                          const SizedBox(height: 4),
                          const _OutstandingChip(),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _FittedAmount(
                    balanceMinor: balanceMinor,
                    currencyCode: account.currencyCode,
                    maxWidth: amountMaxWidth,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              if (trend.length >= 2) ...[
                const SizedBox(height: AppSpacing.md),
                // White line keeps the trend visible on any card colour;
                // the direction still reads from the shape itself.
                Sparkline(
                  values: trend,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Renders the balance so it always fits the card: it is capped to [maxWidth]
/// (a fraction of the card width, so the account name keeps room) and the
/// formatted string scales down if it still doesn't fit — no truncation, no
/// overflow on narrow phones.
class _FittedAmount extends StatelessWidget {
  const _FittedAmount({
    required this.balanceMinor,
    required this.currencyCode,
    required this.maxWidth,
    required this.style,
  });

  final int balanceMinor;
  final String currencyCode;
  final double maxWidth;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: AmountText(
          balanceMinor,
          currencyCode: currencyCode,
          style: style,
        ),
      ),
    );
  }
}

class _CompactBody extends StatelessWidget {
  const _CompactBody({
    required this.theme,
    required this.account,
    required this.balanceMinor,
    required this.amountMaxWidth,
  });

  final ThemeData theme;
  final Account account;
  final int balanceMinor;
  final double amountMaxWidth;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AppIconTile(
          icon: iconFromCode(
            account.iconCode,
            fallback: accountTypeIcon(account.type),
          ),
          color: account.color,
          frosted: true,
          size: 40,
          iconSize: 20,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                account.name,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                account.type.label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.72),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        _FittedAmount(
          balanceMinor: balanceMinor,
          currencyCode: account.currencyCode,
          maxWidth: amountMaxWidth,
          style: theme.textTheme.titleSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// Small red pill flagging an outstanding (owed) balance on a credit account.
class _OutstandingChip extends StatelessWidget {
  const _OutstandingChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.expense.withValues(alpha: 0.26),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        'Outstanding',
        style: TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
