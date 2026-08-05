import 'package:finflow/features/accounts/domain/enums/account_type.dart';
import 'package:finflow/features/accounts/domain/models/account.dart';
import 'package:finflow/features/accounts/domain/repositories/account_repository.dart';
import 'package:finflow/features/transactions/domain/engine/transaction_builder.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_database.dart';

void main() {
  late TestHarness harness;

  setUp(() async {
    harness = await TestHarness.create();
  });

  tearDown(() => harness.dispose());

  Future<String> cashAccount() async {
    final cash = await harness.accounts.createAccount(
      const CreateAccountInput(
        name: 'Cash',
        type: AccountType.cash,
        currencyCode: 'PHP',
      ),
    );
    return cash.id;
  }

  group('categorySpend', () {
    test('aggregates expense categories with net refunds', () async {
      final cash = await cashAccount();
      final food = await harness.category('Food & Dining');

      await harness.transactions.create(
        TransactionBuilder.expense(
          occurredAt: DateTime(2026, 7, 15),
          currencyCode: 'PHP',
          fromAccountId: cash,
          categoryId: food.id,
          amountMinor: 25000,
          merchant: 'Jollibee',
        ),
      );
      // A refund credited to the same expense category reduces the spend.
      await harness.transactions.create(
        TransactionBuilder.refund(
          occurredAt: DateTime(2026, 7, 20),
          currencyCode: 'PHP',
          toAccountId: cash,
          categoryId: food.id,
          amountMinor: 5000,
        ),
      );

      final spends = await harness.transactions.categorySpend(
        from: DateTime(2026, 7, 1),
        to: DateTime(2026, 8, 1),
      );

      expect(spends, hasLength(1));
      expect(spends.single.categoryName, 'Food & Dining');
      expect(spends.single.amountMinor, 20000);
      expect(spends.single.isIncome, isFalse);
    });

    test(
      'reports income categories separately and honours the range',
      () async {
        final cash = await cashAccount();
        final salary = await harness.category('Salary');
        final food = await harness.category('Food & Dining');

        await harness.transactions.create(
          TransactionBuilder.income(
            occurredAt: DateTime(2026, 7, 10),
            currencyCode: 'PHP',
            toAccountId: cash,
            categoryId: salary.id,
            amountMinor: 30000,
            merchant: 'Employer',
          ),
        );
        // Outside the requested range — must be excluded.
        await harness.transactions.create(
          TransactionBuilder.expense(
            occurredAt: DateTime(2026, 6, 25),
            currencyCode: 'PHP',
            fromAccountId: cash,
            categoryId: food.id,
            amountMinor: 5000,
          ),
        );

        final spends = await harness.transactions.categorySpend(
          from: DateTime(2026, 7, 1),
          to: DateTime(2026, 8, 1),
        );

        expect(spends, hasLength(1));
        expect(spends.single.categoryName, 'Salary');
        expect(spends.single.amountMinor, 30000);
        expect(spends.single.isIncome, isTrue);
      },
    );

    test('sorts largest first and drops fully-refunded categories', () async {
      final cash = await cashAccount();
      final salary = await harness.category('Salary');
      final food = await harness.category('Food & Dining');
      final transport = await harness.category('Transportation');

      await harness.transactions.create(
        TransactionBuilder.income(
          occurredAt: DateTime(2026, 7, 5),
          currencyCode: 'PHP',
          toAccountId: cash,
          categoryId: salary.id,
          amountMinor: 90000,
        ),
      );
      await harness.transactions.create(
        TransactionBuilder.expense(
          occurredAt: DateTime(2026, 7, 6),
          currencyCode: 'PHP',
          fromAccountId: cash,
          categoryId: food.id,
          amountMinor: 40000,
        ),
      );
      await harness.transactions.create(
        TransactionBuilder.expense(
          occurredAt: DateTime(2026, 7, 7),
          currencyCode: 'PHP',
          fromAccountId: cash,
          categoryId: transport.id,
          amountMinor: 10000,
        ),
      );
      // Fully refunded — should not appear in the breakdown.
      await harness.transactions.create(
        TransactionBuilder.expense(
          occurredAt: DateTime(2026, 7, 8),
          currencyCode: 'PHP',
          fromAccountId: cash,
          categoryId: food.id,
          amountMinor: 10000,
        ),
      );
      await harness.transactions.create(
        TransactionBuilder.refund(
          occurredAt: DateTime(2026, 7, 9),
          currencyCode: 'PHP',
          toAccountId: cash,
          categoryId: food.id,
          amountMinor: 10000,
        ),
      );

      final spends = await harness.transactions.categorySpend(
        from: DateTime(2026, 7, 1),
        to: DateTime(2026, 8, 1),
      );

      expect(spends, hasLength(3));
      expect(
        [for (final s in spends) s.categoryName],
        ['Salary', 'Food & Dining', 'Transportation'],
      );
      // Food & Dining: 40000 + 10000 expense, minus the 10000 refund.
      expect([for (final s in spends) s.amountMinor], [90000, 40000, 10000]);
    });
  });

  group('netWorthTrend', () {
    test('tracks ledger-driven net worth across month boundaries', () async {
      final cash = await cashAccount();
      final salary = await harness.category('Salary');
      final food = await harness.category('Food & Dining');

      final now = DateTime.now();
      // Income landed last month; spending happened this month.
      await harness.transactions.create(
        TransactionBuilder.income(
          occurredAt: DateTime(now.year, now.month - 1, 15),
          currencyCode: 'PHP',
          toAccountId: cash,
          categoryId: salary.id,
          amountMinor: 100000,
        ),
      );
      await harness.transactions.create(
        TransactionBuilder.expense(
          occurredAt: DateTime(now.year, now.month, 1),
          currencyCode: 'PHP',
          fromAccountId: cash,
          categoryId: food.id,
          amountMinor: 25000,
        ),
      );

      final points = await harness.transactions.netWorthTrend(months: 12);

      expect(points, hasLength(12));
      // The series is oldest first and the current month is last.
      expect(points.first.netWorthMinor, 0);
      expect(points[points.length - 2].netWorthMinor, 100000);
      expect(points.last.netWorthMinor, 75000);
    });

    test('ignores category entries when deriving net worth', () async {
      final cash = await cashAccount();
      final food = await harness.category('Food & Dining');

      final now = DateTime.now();
      await harness.transactions.create(
        TransactionBuilder.expense(
          occurredAt: DateTime(now.year, now.month, 1),
          currencyCode: 'PHP',
          fromAccountId: cash,
          categoryId: food.id,
          amountMinor: 5000,
        ),
      );

      final points = await harness.transactions.netWorthTrend(months: 3);

      expect(points, hasLength(3));
      // Spending reduced net worth; category debits never inflate it.
      expect(points.last.netWorthMinor, -5000);
    });

    test('excludes hidden accounts, mirroring the Net Worth hero', () async {
      final hidden = await harness.accounts.createAccount(
        const CreateAccountInput(
          name: 'Hidden Savings',
          type: AccountType.bank,
          currencyCode: 'PHP',
          openingBalanceMinor: 500000,
        ),
      );
      // Hide the account; its balance must stop counting toward Net Worth.
      final account = (await harness.accounts.getById(hidden.id))!;
      await harness.accounts.updateAccount(
        Account(
          id: account.id,
          name: account.name,
          institution: account.institution,
          kind: account.kind,
          type: account.type,
          status: account.status,
          openingBalanceMinor: account.openingBalanceMinor,
          currencyCode: account.currencyCode,
          colorValue: account.colorValue,
          iconCode: account.iconCode,
          notes: account.notes,
          sortOrder: account.sortOrder,
          isHidden: true,
          createdAt: account.createdAt,
          updatedAt: account.updatedAt,
        ),
      );

      final points = await harness.transactions.netWorthTrend(months: 3);

      expect(points, hasLength(3));
      // The opening balance is excluded along with the hidden account.
      expect(points.last.netWorthMinor, 0);
    });
  });

  group('accountBalanceTrend', () {
    test('tracks a debit-normal account across month boundaries', () async {
      final cash = await cashAccount();
      final salary = await harness.category('Salary');
      final food = await harness.category('Food & Dining');

      final now = DateTime.now();
      // Income landed last month; spending happened this month.
      await harness.transactions.create(
        TransactionBuilder.income(
          occurredAt: DateTime(now.year, now.month - 1, 15),
          currencyCode: 'PHP',
          toAccountId: cash,
          categoryId: salary.id,
          amountMinor: 100000,
        ),
      );
      await harness.transactions.create(
        TransactionBuilder.expense(
          occurredAt: DateTime(now.year, now.month, 1),
          currencyCode: 'PHP',
          fromAccountId: cash,
          categoryId: food.id,
          amountMinor: 25000,
        ),
      );

      final points = await harness.transactions.accountBalanceTrend(
        cash,
        months: 12,
      );

      expect(points, hasLength(12));
      expect(points.first.balanceMinor, 0);
      expect(points[points.length - 2].balanceMinor, 100000);
      expect(points.last.balanceMinor, 75000);
    });

    test('credit-normal accounts trend their outstanding balance', () async {
      final card = await harness.accounts.createAccount(
        const CreateAccountInput(
          name: 'BDO Visa',
          type: AccountType.creditCard,
          currencyCode: 'PHP',
        ),
      );
      final food = await harness.category('Food & Dining');

      final now = DateTime.now();
      await harness.transactions.create(
        TransactionBuilder.expense(
          occurredAt: DateTime(now.year, now.month, 10),
          currencyCode: 'PHP',
          fromAccountId: card.id,
          categoryId: food.id,
          amountMinor: 5000,
        ),
      );

      final points = await harness.transactions.accountBalanceTrend(
        card.id,
        months: 6,
      );

      expect(points, hasLength(6));
      // The card was flat before the purchase, then jumped to 5,000.
      expect(points[points.length - 2].balanceMinor, 0);
      expect(points.last.balanceMinor, 5000);
    });

    test('ignores activity on other accounts', () async {
      final cash = await cashAccount();
      final other = await harness.accounts.createAccount(
        const CreateAccountInput(
          name: 'GCash',
          type: AccountType.ewallet,
          currencyCode: 'PHP',
        ),
      );
      final salary = await harness.category('Salary');

      final now = DateTime.now();
      await harness.transactions.create(
        TransactionBuilder.income(
          occurredAt: DateTime(now.year, now.month, 5),
          currencyCode: 'PHP',
          toAccountId: other.id,
          categoryId: salary.id,
          amountMinor: 99999,
        ),
      );

      final points = await harness.transactions.accountBalanceTrend(
        cash,
        months: 6,
      );

      expect(points, hasLength(6));
      expect(points.every((p) => p.balanceMinor == 0), isTrue);
    });
  });
}
