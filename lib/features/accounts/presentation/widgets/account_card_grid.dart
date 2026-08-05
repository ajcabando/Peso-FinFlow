import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/repositories/account_repository.dart';
import 'account_card.dart';

/// Responsive grid of [AccountCard]s that reflows into as many columns as the
/// available width fits (one on phones, two on small tablets, more on wider
/// screens), so account sections adapt to the display instead of stretching
/// cards edge to edge or staying phone-sized on desktop.
class AccountCardGrid extends StatelessWidget {
  const AccountCardGrid({
    super.key,
    required this.accounts,
    required this.onTapAccount,
    this.compact = false,
  });

  final List<AccountWithBalance> accounts;
  final ValueChanged<String> onTapAccount;

  /// Compact horizontal card variant (used on the dashboard).
  final bool compact;

  /// The minimum comfortable card width. The layout adds a column whenever
  /// the available width fits one more card at this size.
  static const double _columnBreakpoint = 320;

  @override
  Widget build(BuildContext context) {
    const spacing = AppSpacing.md;

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        final columns = math.max(
          1,
          ((available + spacing) / (_columnBreakpoint + spacing)).floor(),
        );
        final cardWidth = (available - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final entry in accounts)
              SizedBox(
                width: cardWidth,
                child: AccountCard(
                  account: entry.account,
                  balanceMinor: entry.balanceMinor,
                  compact: compact,
                  onTap: () => onTapAccount(entry.account.id),
                ),
              ),
          ],
        );
      },
    );
  }
}
