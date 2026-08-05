import 'package:finflow/core/errors/app_exception.dart';
import 'package:finflow/core/theme/app_colors.dart';
import 'package:finflow/features/accounts/domain/enums/account_kind.dart';
import 'package:finflow/features/accounts/domain/enums/account_type.dart';
import 'package:finflow/features/accounts/domain/models/account.dart';
import 'package:finflow/features/accounts/domain/repositories/account_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_database.dart';

void main() {
  late TestHarness harness;

  setUp(() async {
    harness = await TestHarness.create();
  });

  tearDown(() async {
    await harness.dispose();
  });

  CreateAccountInput input({
    String name = 'Groceries',
    AccountType type = AccountType.expense,
    int? colorValue,
  }) => CreateAccountInput(
    name: name,
    type: type,
    kind: AccountKind.category,
    currencyCode: 'PHP',
    colorValue: colorValue,
  );

  group('createCategory', () {
    setUp(() async {
      // Start with an empty category pool so colour expectations below are
      // deterministic regardless of the seeded default categories.
      await (harness.db.delete(
        harness.db.accounts,
      )..where((t) => t.kind.equalsValue(AccountKind.category))).go();
    });

    test('creates a hidden category row with no ledger entries', () async {
      final category = await harness.accounts.createAccount(input());

      expect(category.kind, AccountKind.category);
      expect(category.type, AccountType.expense);
      expect(category.isHidden, isTrue);
      expect(category.name, 'Groceries');

      // A category must not write an opening-balance ledger transaction.
      final entries = await (harness.db.select(
        harness.db.ledgerEntries,
      )..where((t) => t.accountId.equals(category.id))).get();
      expect(entries, isEmpty);
    });

    test('assigns the first palette colour to the first category', () async {
      final category = await harness.accounts.createAccount(input());

      expect(
        category.colorValue,
        AppColors.accountPalette.first.toARGB32(),
      );
    });

    test('assigns distinct colours to consecutive categories', () async {
      final first = await harness.accounts.createAccount(
        input(name: 'Groceries'),
      );
      final second = await harness.accounts.createAccount(
        input(name: 'Utilities'),
      );

      expect(first.colorValue, AppColors.accountPalette[0].toARGB32());
      expect(second.colorValue, AppColors.accountPalette[1].toARGB32());
      expect(second.colorValue, isNot(first.colorValue));
    });

    test('draws from the category pool, not the account pool', () async {
      // A real account already holds the first palette colour; a brand-new
      // category's pool is still empty, so it gets the first colour too.
      await harness.accounts.createAccount(
        const CreateAccountInput(
          name: 'Cash',
          type: AccountType.cash,
          currencyCode: 'PHP',
        ),
      );

      final category = await harness.accounts.createAccount(input());

      expect(
        category.colorValue,
        AppColors.accountPalette.first.toARGB32(),
      );
    });

    test('respects an explicit colour', () async {
      final category = await harness.accounts.createAccount(
        input(colorValue: 0xFF123456),
      );

      expect(category.colorValue, 0xFF123456);
    });

    test('rejects a non-category type', () async {
      expect(
        () => harness.accounts.createAccount(
          input(type: AccountType.cash),
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('rejects an opening balance on a category', () async {
      expect(
        () => harness.accounts.createAccount(
          CreateAccountInput(
            name: 'Groceries',
            type: AccountType.expense,
            kind: AccountKind.category,
            currencyCode: 'PHP',
            openingBalanceMinor: 500,
          ),
        ),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  group('update & delete category', () {
    test('updates name, colour and icon while preserving kind', () async {
      final category = await harness.accounts.createAccount(input());

      final updated = await harness.accounts.updateAccount(
        Account(
          id: category.id,
          name: 'Weekly Groceries',
          kind: category.kind,
          type: category.type,
          status: category.status,
          openingBalanceMinor: category.openingBalanceMinor,
          currencyCode: category.currencyCode,
          colorValue: 0xFF123456,
          isHidden: category.isHidden,
          sortOrder: category.sortOrder,
          createdAt: category.createdAt,
          updatedAt: category.updatedAt,
          iconCode: category.iconCode,
        ),
      );

      expect(updated.name, 'Weekly Groceries');
      expect(updated.colorValue, 0xFF123456);
      expect(updated.kind, AccountKind.category);
    });

    test('deletes a category with no transactions', () async {
      final category = await harness.accounts.createAccount(input());

      await harness.accounts.deleteAccount(category.id);

      expect(await harness.accounts.getById(category.id), isNull);
    });
  });
}
