import 'package:finflow/core/theme/app_colors.dart';
import 'package:finflow/features/accounts/domain/enums/account_kind.dart';
import 'package:finflow/features/accounts/domain/enums/account_status.dart';
import 'package:finflow/features/accounts/domain/enums/account_type.dart';
import 'package:finflow/features/accounts/domain/models/account.dart';
import 'package:flutter_test/flutter_test.dart';

Account _account(int colorValue) => Account(
  id: 'a-$colorValue',
  name: 'Account',
  kind: AccountKind.account,
  type: AccountType.cash,
  status: AccountStatus.active,
  openingBalanceMinor: 0,
  currencyCode: 'PHP',
  colorValue: colorValue,
  isHidden: false,
  sortOrder: 0,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

void main() {
  test('starts with the first palette colour when no accounts exist', () {
    expect(Account.dynamicColorValue(const []), AppColors.accountPalette.first.toARGB32());
  });

  test('picks a distinct colour when one is already in use', () {
    final purple = AppColors.accountPalette[0].toARGB32();
    final blue = AppColors.accountPalette[1].toARGB32();
    expect(Account.dynamicColorValue([_account(purple)]), blue);
  });

  test('prefers an unused colour over a tied pair', () {
    final purple = AppColors.accountPalette[0].toARGB32();
    final blue = AppColors.accountPalette[1].toARGB32();
    final green = AppColors.accountPalette[2].toARGB32();
    // Purple and blue are each used once; the least-used colour is any
    // unused one, so the first unused palette entry (green) wins.
    expect(
      Account.dynamicColorValue([_account(purple), _account(blue)]),
      green,
    );
  });

  test('prefers an unused palette colour even late in the sequence', () {
    final values = [
      for (final color in AppColors.accountPalette) color.toARGB32(),
    ];
    final existing = [for (final value in values) _account(value)];
    // Every palette colour is used once; wrap around to the first.
    expect(Account.dynamicColorValue(existing), values.first);
  });
}
