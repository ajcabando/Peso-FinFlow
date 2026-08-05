import 'package:finflow/core/errors/app_exception.dart';
import 'package:finflow/features/accounts/domain/enums/account_kind.dart';
import 'package:finflow/features/accounts/domain/enums/account_type.dart';
import 'package:finflow/features/accounts/domain/models/account.dart';
import 'package:finflow/features/accounts/domain/repositories/account_repository.dart';
import 'package:finflow/features/transactions/domain/engine/transaction_builder.dart';
import 'package:finflow/features/transactions/domain/enums/ledger_direction.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_database.dart';

void main() {
  late TestHarness h;

  setUp(() async {
    h = await TestHarness.create();
  });

  tearDown(() => h.dispose());

  group('createAccount', () {
    test('creates a real account with zero balance by default', () async {
      final account = await h.accounts.createAccount(
        const CreateAccountInput(
          name: 'GCash',
          type: AccountType.ewallet,
          currencyCode: 'PHP',
        ),
      );

      expect(account.name, 'GCash');
      expect(account.kind, AccountKind.account);
      expect(account.openingBalanceMinor, 0);
      expect(await h.accounts.watchNetWorthMinor().first, 0);
    });

    test(
      'an opening balance is recorded as a balanced ledger transaction',
      () async {
        await h.accounts.createAccount(
          const CreateAccountInput(
            name: 'Savings',
            type: AccountType.bank,
            currencyCode: 'PHP',
            openingBalanceMinor: 2500000,
          ),
        );

        // Net worth reflects the opening balance...
        expect(await h.accounts.watchNetWorthMinor().first, 2500000);

        // ...and the ledger is still perfectly balanced.
        final rows = await (h.db.select(h.db.ledgerEntries)).get();
        expect(rows, hasLength(2));
        final signed = rows
            .map(
              (r) => r.direction == LedgerDirection.debit
                  ? r.amountMinor
                  : -r.amountMinor,
            )
            .fold<int>(0, (a, b) => a + b);
        expect(signed, 0);

        // The Opening Balances system account holds the counterpart.
        final opening = await h.openingBalances();
        final sums = await h.db.ledgerDao.sumsFor(opening.id);
        expect(sums.credit, 2500000);
      },
    );

    test(
      'a credit-card opening balance records a liability (credit)',
      () async {
        await h.accounts.createAccount(
          const CreateAccountInput(
            name: 'Visa',
            type: AccountType.creditCard,
            currencyCode: 'PHP',
            openingBalanceMinor: 1500000,
          ),
        );

        final visa = (await h.accounts.watchAccountsWithBalances().first)
            .firstWhere((e) => e.account.name == 'Visa');
        expect(visa.balanceMinor, 1500000);
        // An outstanding balance is a negative contribution to net worth.
        expect(await h.accounts.watchNetWorthMinor().first, -1500000);
      },
    );

    test('rejects an empty name', () async {
      expect(
        () => h.accounts.createAccount(
          const CreateAccountInput(
            name: '   ',
            type: AccountType.cash,
            currencyCode: 'PHP',
          ),
        ),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  group('deleteAccount', () {
    test('deletes an account that has no entries', () async {
      final account = await h.accounts.createAccount(
        const CreateAccountInput(
          name: 'Temp',
          type: AccountType.cash,
          currencyCode: 'PHP',
        ),
      );
      await h.accounts.deleteAccount(account.id);
      expect(await h.accounts.getById(account.id), isNull);
    });

    test('refuses to delete an account that holds transactions', () async {
      final account = await h.accounts.createAccount(
        const CreateAccountInput(
          name: 'Cash',
          type: AccountType.cash,
          currencyCode: 'PHP',
          openingBalanceMinor: 50000,
        ),
      );
      expect(
        () => h.accounts.deleteAccount(account.id),
        throwsA(isA<DomainException>()),
      );
    });
  });

  group('watchAccountsWithBalances', () {
    test(
      'only real accounts are listed (no categories or system accounts)',
      () async {
        await h.accounts.createAccount(
          const CreateAccountInput(
            name: 'Cash',
            type: AccountType.cash,
            currencyCode: 'PHP',
            openingBalanceMinor: 10000,
          ),
        );
        final list = await h.accounts.watchAccountsWithBalances().first;

        expect(list.map((e) => e.account.name), ['Cash']);
      },
    );

    test('balances update reactively after a transaction', () async {
      final cash = await h.accounts.createAccount(
        const CreateAccountInput(
          name: 'Cash',
          type: AccountType.cash,
          currencyCode: 'PHP',
          openingBalanceMinor: 100000,
        ),
      );
      final food = await h.category('Food & Dining');

      expect(await h.accounts.watchNetWorthMinor().first, 100000);

      await h.transactions.create(
        TransactionBuilder.expense(
          occurredAt: DateTime(2026, 8, 4),
          currencyCode: 'PHP',
          fromAccountId: cash.id,
          categoryId: food.id,
          amountMinor: 10000,
        ),
      );

      expect(await h.accounts.watchNetWorthMinor().first, 90000);
    });
  });

  group('updateAccount', () {
    test('refuses a currency change once transactions exist', () async {
      final account = await h.accounts.createAccount(
        const CreateAccountInput(
          name: 'Cash',
          type: AccountType.cash,
          currencyCode: 'PHP',
          openingBalanceMinor: 10000,
        ),
      );

      expect(
        () => h.accounts.updateAccount(
          Account(
            id: account.id,
            name: account.name,
            kind: account.kind,
            type: account.type,
            status: account.status,
            openingBalanceMinor: account.openingBalanceMinor,
            currencyCode: 'USD',
            colorValue: account.colorValue,
            isHidden: account.isHidden,
            sortOrder: account.sortOrder,
            createdAt: account.createdAt,
            updatedAt: account.updatedAt,
          ),
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('renames and recolors an account', () async {
      final account = await h.accounts.createAccount(
        const CreateAccountInput(
          name: 'Old Name',
          type: AccountType.cash,
          currencyCode: 'PHP',
        ),
      );

      final updated = await h.accounts.updateAccount(
        Account(
          id: account.id,
          name: 'New Name',
          kind: account.kind,
          type: account.type,
          status: account.status,
          openingBalanceMinor: account.openingBalanceMinor,
          currencyCode: account.currencyCode,
          colorValue: 0xFF0000FF,
          isHidden: account.isHidden,
          sortOrder: account.sortOrder,
          createdAt: account.createdAt,
          updatedAt: account.updatedAt,
        ),
      );

      expect(updated.name, 'New Name');
      expect(updated.colorValue, 0xFF0000FF);
    });
  });
}
