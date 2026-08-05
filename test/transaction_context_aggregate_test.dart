import 'package:finflow/features/accounts/domain/enums/account_type.dart';
import 'package:finflow/features/accounts/domain/repositories/account_repository.dart';
import 'package:finflow/features/transactions/domain/engine/transaction_builder.dart';
import 'package:finflow/features/transactions/domain/enums/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_database.dart';

void main() {
  late TestHarness h;

  setUp(() async {
    h = await TestHarness.create();
  });

  tearDown(() => h.dispose());

  group('transaction contexts', () {
    test(
      'group one context per transaction with account and category names',
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

        final contexts = await h.transactions.watchAllContext().first;
        // Seed data: the account's opening balance is also a transaction, so
        // filter for the one with a merchant.
        final expense = contexts.firstWhere(
          (c) => c.transaction.merchant == 'Jollibee',
        );

        expect(expense.transaction.type, TransactionType.expense);
        expect(expense.accountName, 'Cash');
        expect(expense.categoryName, 'Food & Dining');
        expect(expense.counterpartName, 'Cash');
      },
    );

    test(
      'watchForAccountContext only returns transactions for that account',
      () async {
        final cash = await h.accounts.createAccount(
          const CreateAccountInput(
            name: 'Cash',
            type: AccountType.cash,
            currencyCode: 'PHP',
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

        final cashContexts = await h.transactions
            .watchForAccountContext(cash.id)
            .first;
        final gcashContexts = await h.transactions
            .watchForAccountContext(gcash.id)
            .first;

        expect(cashContexts, hasLength(1));
        expect(gcashContexts, hasLength(1));
        // A transfer has no category.
        expect(cashContexts.single.categoryName, isNull);
      },
    );

    test('getContextById returns the enriched single transaction', () async {
      final cash = await h.accounts.createAccount(
        const CreateAccountInput(
          name: 'Cash',
          type: AccountType.cash,
          currencyCode: 'PHP',
          openingBalanceMinor: 50000,
        ),
      );
      final salary = await h.category('Salary');

      final created = await h.transactions.create(
        TransactionBuilder.income(
          occurredAt: DateTime(2026, 8, 1),
          currencyCode: 'PHP',
          toAccountId: cash.id,
          categoryId: salary.id,
          amountMinor: 3000000,
        ),
      );

      final context = await h.transactions.getContextById(created.id);

      expect(context, isNotNull);
      expect(context!.accountName, 'Cash');
      expect(context.categoryName, 'Salary');

      expect(await h.transactions.getContextById('missing'), isNull);
    });
  });

  group('monthly cash flow', () {
    test('zero-fills months without activity', () async {
      final flow = await h.transactions.monthlyCashFlow(months: 6);

      expect(flow, hasLength(6));
      expect(
        flow.every((f) => f.incomeMinor == 0 && f.expenseMinor == 0),
        isTrue,
      );
      // Oldest first.
      expect(
        flow.first.month,
        DateTime.now().month - 5 <= 0
            ? DateTime.now().month - 5 + 12
            : DateTime.now().month - 5,
      );
      expect(flow.last.month, DateTime.now().month);
    });

    test('aggregates income and expense per month', () async {
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

      final now = DateTime.now();

      // Income this month.
      await h.transactions.create(
        TransactionBuilder.income(
          occurredAt: now,
          currencyCode: 'PHP',
          toAccountId: cash.id,
          categoryId: salary.id,
          amountMinor: 500000,
        ),
      );
      // Expenses this month.
      await h.transactions.create(
        TransactionBuilder.expense(
          occurredAt: now,
          currencyCode: 'PHP',
          fromAccountId: cash.id,
          categoryId: food.id,
          amountMinor: 150000,
        ),
      );
      await h.transactions.create(
        TransactionBuilder.expense(
          occurredAt: now,
          currencyCode: 'PHP',
          fromAccountId: cash.id,
          categoryId: food.id,
          amountMinor: 50000,
        ),
      );
      // An expense two months ago.
      await h.transactions.create(
        TransactionBuilder.expense(
          occurredAt: DateTime(now.year, now.month - 2, 10),
          currencyCode: 'PHP',
          fromAccountId: cash.id,
          categoryId: food.id,
          amountMinor: 100000,
        ),
      );

      final flow = await h.transactions.monthlyCashFlow(months: 6);

      final thisMonth = flow.last;
      expect(thisMonth.incomeMinor, 500000);
      expect(thisMonth.expenseMinor, 200000);
      expect(thisMonth.netMinor, 300000);

      final twoMonthsAgo = flow[flow.length - 3];
      expect(twoMonthsAgo.expenseMinor, 100000);
      expect(twoMonthsAgo.incomeMinor, 0);
    });

    test('a refund credited to an expense category reduces that month\'s '
        'expense total', () async {
      final cash = await h.accounts.createAccount(
        const CreateAccountInput(
          name: 'Cash',
          type: AccountType.cash,
          currencyCode: 'PHP',
          openingBalanceMinor: 100000,
        ),
      );
      final food = await h.category('Food & Dining');

      final now = DateTime.now();

      await h.transactions.create(
        TransactionBuilder.expense(
          occurredAt: now,
          currencyCode: 'PHP',
          fromAccountId: cash.id,
          categoryId: food.id,
          amountMinor: 100000,
        ),
      );
      // Refund of half of it, credited back under the same expense category.
      await h.transactions.create(
        TransactionBuilder.refund(
          occurredAt: now,
          currencyCode: 'PHP',
          toAccountId: cash.id,
          categoryId: food.id,
          amountMinor: 50000,
        ),
      );

      final flow = await h.transactions.monthlyCashFlow(months: 6);
      expect(flow.last.expenseMinor, 50000);
    });
  });
}
