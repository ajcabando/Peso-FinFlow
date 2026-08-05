import 'package:finflow/core/errors/app_exception.dart';
import 'package:finflow/features/accounts/domain/enums/account_type.dart';
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

  Future<AccountWithBalance> balanceOf(String accountName) async {
    final list = await h.accounts.watchAccountsWithBalances().first;
    return list.firstWhere((e) => e.account.name == accountName);
  }

  group('expenses & income', () {
    test(
      'an expense reduces the source account and records category spend',
      () async {
        final cash = await h.accounts.createAccount(
          const CreateAccountInput(
            name: 'Cash',
            type: AccountType.cash,
            currencyCode: 'PHP',
            openingBalanceMinor: 100000,
          ),
        );
        final food = await h.category('Food & Dining');

        await h.transactions.create(
          TransactionBuilder.expense(
            occurredAt: DateTime(2026, 8, 4),
            currencyCode: 'PHP',
            fromAccountId: cash.id,
            categoryId: food.id,
            amountMinor: 25000,
            merchant: 'Jollibee',
          ),
        );

        expect((await balanceOf('Cash')).balanceMinor, 75000);
        // Spending lands on the expense category.
        final ledger = await h.db.ledgerDao.sumsFor(food.id);
        expect(ledger.debit, 25000);
        // Net worth dropped by the purchase.
        expect(await h.accounts.watchNetWorthMinor().first, 75000);
      },
    );

    test('income increases the account and the income category', () async {
      final bank = await h.accounts.createAccount(
        const CreateAccountInput(
          name: 'Bank',
          type: AccountType.bank,
          currencyCode: 'PHP',
        ),
      );
      final salary = await h.category('Salary');

      await h.transactions.create(
        TransactionBuilder.income(
          occurredAt: DateTime(2026, 8, 4),
          currencyCode: 'PHP',
          toAccountId: bank.id,
          categoryId: salary.id,
          amountMinor: 3000000,
        ),
      );

      expect((await balanceOf('Bank')).balanceMinor, 3000000);
      final ledger = await h.db.ledgerDao.sumsFor(salary.id);
      expect(ledger.credit, 3000000);
    });
  });

  group('transfers', () {
    test(
      'cash → e-wallet transfer moves money without income or expense',
      () async {
        final cash = await h.accounts.createAccount(
          const CreateAccountInput(
            name: 'Cash',
            type: AccountType.cash,
            currencyCode: 'PHP',
            openingBalanceMinor: 100000,
          ),
        );
        final gcash = await h.accounts.createAccount(
          const CreateAccountInput(
            name: 'GCash',
            type: AccountType.ewallet,
            currencyCode: 'PHP',
          ),
        );

        await h.transactions.create(
          TransactionBuilder.transfer(
            occurredAt: DateTime(2026, 8, 4),
            currencyCode: 'PHP',
            fromAccountId: cash.id,
            toAccountId: gcash.id,
            amountMinor: 40000,
          ),
        );

        expect((await balanceOf('Cash')).balanceMinor, 60000);
        expect((await balanceOf('GCash')).balanceMinor, 40000);
        // Net worth is unchanged by a transfer.
        expect(await h.accounts.watchNetWorthMinor().first, 100000);
      },
    );
  });

  group('credit cards', () {
    test(
      'a credit-card purchase increases the card balance (liability)',
      () async {
        final visa = await h.accounts.createAccount(
          const CreateAccountInput(
            name: 'Visa',
            type: AccountType.creditCard,
            currencyCode: 'PHP',
          ),
        );
        final food = await h.category('Food & Dining');

        await h.transactions.create(
          TransactionBuilder.creditCardPurchase(
            occurredAt: DateTime(2026, 8, 4),
            currencyCode: 'PHP',
            creditCardAccountId: visa.id,
            categoryId: food.id,
            amountMinor: 200000,
            merchant: 'Grocery',
          ),
        );

        // Liability went UP: balance now +2000.00.
        expect((await balanceOf('Visa')).balanceMinor, 200000);
        expect(await h.accounts.watchNetWorthMinor().first, -200000);
      },
    );

    test('paying the card from the bank reduces both balances and never '
        'double-counts the expense', () async {
      final bank = await h.accounts.createAccount(
        const CreateAccountInput(
          name: 'Bank',
          type: AccountType.bank,
          currencyCode: 'PHP',
          openingBalanceMinor: 500000,
        ),
      );
      final visa = await h.accounts.createAccount(
        const CreateAccountInput(
          name: 'Visa',
          type: AccountType.creditCard,
          currencyCode: 'PHP',
        ),
      );
      final food = await h.category('Food & Dining');

      // Buy 2,000 on the card, then pay it off from the bank.
      await h.transactions.create(
        TransactionBuilder.creditCardPurchase(
          occurredAt: DateTime(2026, 8, 4),
          currencyCode: 'PHP',
          creditCardAccountId: visa.id,
          categoryId: food.id,
          amountMinor: 200000,
        ),
      );
      await h.transactions.create(
        TransactionBuilder.creditCardPayment(
          occurredAt: DateTime(2026, 8, 5),
          currencyCode: 'PHP',
          bankAccountId: bank.id,
          creditCardAccountId: visa.id,
          amountMinor: 200000,
        ),
      );

      expect((await balanceOf('Bank')).balanceMinor, 300000);
      expect((await balanceOf('Visa')).balanceMinor, 0);
      // One expense only — category debit is 2000, not 4000.
      final ledger = await h.db.ledgerDao.sumsFor(food.id);
      expect(ledger.debit, 200000);
      expect(await h.accounts.watchNetWorthMinor().first, 300000);
    });
  });

  group('atomicity & invariants', () {
    test('an unbalanced draft is rejected and nothing is written', () async {
      final cash = await h.accounts.createAccount(
        const CreateAccountInput(
          name: 'Cash',
          type: AccountType.cash,
          currencyCode: 'PHP',
        ),
      );
      final food = await h.category('Food & Dining');
      final before = await h.transactions.watchRecent().first;

      final base = TransactionBuilder.expense(
        occurredAt: DateTime(2026, 8, 4),
        currencyCode: 'PHP',
        fromAccountId: cash.id,
        categoryId: food.id,
        amountMinor: 1000,
      );
      // Keep only the debit leg -> unbalanced.
      final draft = base.copyWith(entries: [base.entries[0]]);

      expect(
        () => h.transactions.create(draft),
        throwsA(isA<ValidationException>()),
      );
      expect(await h.transactions.watchRecent().first, before);
    });

    test('unknown accounts are rejected', () async {
      final food = await h.category('Food & Dining');
      expect(
        () => h.transactions.create(
          TransactionBuilder.expense(
            occurredAt: DateTime(2026, 8, 4),
            currencyCode: 'PHP',
            fromAccountId: 'does-not-exist',
            categoryId: food.id,
            amountMinor: 1000,
          ),
        ),
        throwsA(isA<NotFoundException>()),
      );
    });

    test('a transfer referencing a category is rejected', () async {
      final cash = await h.accounts.createAccount(
        const CreateAccountInput(
          name: 'Cash',
          type: AccountType.cash,
          currencyCode: 'PHP',
        ),
      );
      final food = await h.category('Food & Dining');

      expect(
        () => h.transactions.create(
          TransactionBuilder.transfer(
            occurredAt: DateTime(2026, 8, 4),
            currencyCode: 'PHP',
            fromAccountId: cash.id,
            toAccountId: food.id,
            amountMinor: 1000,
          ),
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('an expense debited from an income category is rejected', () async {
      final cash = await h.accounts.createAccount(
        const CreateAccountInput(
          name: 'Cash',
          type: AccountType.cash,
          currencyCode: 'PHP',
        ),
      );
      final salary = await h.category('Salary');

      expect(
        () => h.transactions.create(
          TransactionBuilder.expense(
            occurredAt: DateTime(2026, 8, 4),
            currencyCode: 'PHP',
            fromAccountId: cash.id,
            categoryId: salary.id,
            amountMinor: 1000,
          ),
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('currency mismatches are rejected', () async {
      final cash = await h.accounts.createAccount(
        const CreateAccountInput(
          name: 'Cash',
          type: AccountType.cash,
          currencyCode: 'PHP',
        ),
      );
      final food = await h.category('Food & Dining');
      expect(
        () => h.transactions.create(
          TransactionBuilder.expense(
            occurredAt: DateTime(2026, 8, 4),
            currencyCode: 'USD',
            fromAccountId: cash.id,
            categoryId: food.id,
            amountMinor: 1000,
          ),
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('deleting a transaction reverts every balance', () async {
      final cash = await h.accounts.createAccount(
        const CreateAccountInput(
          name: 'Cash',
          type: AccountType.cash,
          currencyCode: 'PHP',
          openingBalanceMinor: 100000,
        ),
      );
      final food = await h.category('Food & Dining');

      final created = await h.transactions.create(
        TransactionBuilder.expense(
          occurredAt: DateTime(2026, 8, 4),
          currencyCode: 'PHP',
          fromAccountId: cash.id,
          categoryId: food.id,
          amountMinor: 25000,
        ),
      );

      expect((await balanceOf('Cash')).balanceMinor, 75000);

      await h.transactions.delete(created.id);

      expect((await balanceOf('Cash')).balanceMinor, 100000);
      expect(await h.accounts.watchNetWorthMinor().first, 100000);
    });

    test('every ledger transaction is perfectly balanced', () async {
      final cash = await h.accounts.createAccount(
        const CreateAccountInput(
          name: 'Cash',
          type: AccountType.cash,
          currencyCode: 'PHP',
          openingBalanceMinor: 100000,
        ),
      );
      final food = await h.category('Food & Dining');
      final salary = await h.category('Salary');

      await h.transactions.create(
        TransactionBuilder.expense(
          occurredAt: DateTime(2026, 8, 4),
          currencyCode: 'PHP',
          fromAccountId: cash.id,
          categoryId: food.id,
          amountMinor: 20000,
        ),
      );
      await h.transactions.create(
        TransactionBuilder.income(
          occurredAt: DateTime(2026, 8, 5),
          currencyCode: 'PHP',
          toAccountId: cash.id,
          categoryId: salary.id,
          amountMinor: 100000,
        ),
      );

      final rows = await (h.db.select(h.db.ledgerEntries)).get();
      expect(rows, isNotEmpty);

      // Group entries per transaction and assert debits == credits.
      final byTransaction = <String, List<int>>{};
      for (final row in rows) {
        byTransaction
            .putIfAbsent(row.transactionId, () => [])
            .add(
              row.direction == LedgerDirection.debit
                  ? row.amountMinor
                  : -row.amountMinor,
            );
      }
      for (final entry in byTransaction.entries) {
        expect(
          entry.value.fold<int>(0, (a, b) => a + b),
          0,
          reason: 'Transaction ${entry.key} is unbalanced',
        );
      }
    });
  });
}
