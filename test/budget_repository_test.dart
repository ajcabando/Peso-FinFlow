import 'package:finflow/core/errors/app_exception.dart';
import 'package:finflow/features/accounts/domain/enums/account_type.dart';
import 'package:finflow/features/accounts/domain/repositories/account_repository.dart';
import 'package:finflow/features/budgets/domain/models/budget.dart';
import 'package:finflow/features/budgets/domain/models/budget_progress.dart';
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

  Future<Budget> upsertBudget({
    required String categoryId,
    required int amountMinor,
  }) {
    return harness.budgets.upsert(
      categoryId: categoryId,
      amountMinor: amountMinor,
      currencyCode: 'PHP',
    );
  }

  Future<List<BudgetProgress>> julyProgress() => harness.budgets.budgetProgress(
    from: DateTime(2026, 7, 1),
    to: DateTime(2026, 8, 1),
  );

  group('upsert', () {
    test('creates a budget for an expense category', () async {
      final food = await harness.category('Food & Dining');

      final budget = await upsertBudget(
        categoryId: food.id,
        amountMinor: 500000,
      );

      expect(budget.categoryId, food.id);
      expect(budget.amountMinor, 500000);
      expect(budget.currencyCode, 'PHP');
    });

    test('updates the existing budget for the same category', () async {
      final food = await harness.category('Food & Dining');
      await upsertBudget(categoryId: food.id, amountMinor: 500000);

      final updated = await upsertBudget(
        categoryId: food.id,
        amountMinor: 600000,
      );

      expect(updated.amountMinor, 600000);
      // One budget row only — a category never holds two budgets.
      final all = await harness.budgets.watchBudgets().first;
      expect(all, hasLength(1));
      expect(all.single.amountMinor, 600000);
    });

    test('rejects non-expense categories', () async {
      final salary = await harness.category('Salary');
      final cash = await cashAccount();

      expect(
        () => upsertBudget(categoryId: salary.id, amountMinor: 100000),
        throwsA(isA<ValidationException>()),
      );
      // Real accounts can't be budgeted either.
      expect(
        () => upsertBudget(categoryId: cash, amountMinor: 100000),
        throwsA(isA<ValidationException>()),
      );
    });

    test('rejects unknown categories', () async {
      expect(
        () => upsertBudget(categoryId: 'missing', amountMinor: 100000),
        throwsA(isA<NotFoundException>()),
      );
    });

    test('rejects a non-positive amount for a known category', () async {
      final food = await harness.category('Food & Dining');

      expect(
        () => upsertBudget(categoryId: food.id, amountMinor: 0),
        throwsA(isA<ValidationException>()),
      );
      // Nothing was written.
      expect(await harness.budgets.getByCategory(food.id), isNull);
    });

    test('rejects a currency that does not match the category', () async {
      final food = await harness.category('Food & Dining');

      expect(
        () => harness.budgets.upsert(
          categoryId: food.id,
          amountMinor: 50000,
          currencyCode: 'USD',
        ),
        throwsA(isA<ValidationException>()),
      );
      expect(await harness.budgets.getByCategory(food.id), isNull);
    });

    test('deleteBudget removes the budget', () async {
      final food = await harness.category('Food & Dining');
      final budget = await upsertBudget(
        categoryId: food.id,
        amountMinor: 500000,
      );

      await harness.budgets.deleteBudget(budget.id);

      expect(await harness.budgets.getByCategory(food.id), isNull);
    });
  });

  group('budgetProgress', () {
    test('reflects ledger-derived spend and flags over-budget', () async {
      final cash = await cashAccount();
      final food = await harness.category('Food & Dining');
      final transport = await harness.category('Transportation');
      await upsertBudget(categoryId: food.id, amountMinor: 30000);
      await upsertBudget(categoryId: transport.id, amountMinor: 100000);

      await harness.transactions.create(
        TransactionBuilder.expense(
          occurredAt: DateTime(2026, 7, 10),
          currencyCode: 'PHP',
          fromAccountId: cash,
          categoryId: food.id,
          amountMinor: 40000,
        ),
      );
      await harness.transactions.create(
        TransactionBuilder.expense(
          occurredAt: DateTime(2026, 7, 12),
          currencyCode: 'PHP',
          fromAccountId: cash,
          categoryId: transport.id,
          amountMinor: 20000,
        ),
      );

      final progress = await julyProgress();

      expect(progress, hasLength(2));
      final foodProgress = progress.firstWhere(
        (p) => p.categoryName == 'Food & Dining',
      );
      final transportProgress = progress.firstWhere(
        (p) => p.categoryName == 'Transportation',
      );
      expect(foodProgress.spentMinor, 40000);
      expect(foodProgress.isOver, isTrue);
      expect(foodProgress.fraction, greaterThan(1));
      expect(transportProgress.spentMinor, 20000);
      expect(transportProgress.fraction, 0.2);
      expect(transportProgress.isOver, isFalse);
      // Most at-risk (highest fraction) sorts first.
      expect(progress.first.categoryName, 'Food & Dining');
    });

    test('refunds reduce spend against the budget', () async {
      final cash = await cashAccount();
      final food = await harness.category('Food & Dining');
      await upsertBudget(categoryId: food.id, amountMinor: 30000);

      await harness.transactions.create(
        TransactionBuilder.expense(
          occurredAt: DateTime(2026, 7, 10),
          currencyCode: 'PHP',
          fromAccountId: cash,
          categoryId: food.id,
          amountMinor: 25000,
        ),
      );
      await harness.transactions.create(
        TransactionBuilder.refund(
          occurredAt: DateTime(2026, 7, 15),
          currencyCode: 'PHP',
          toAccountId: cash,
          categoryId: food.id,
          amountMinor: 5000,
        ),
      );

      final progress = await julyProgress();

      expect(progress.single.spentMinor, 20000);
    });

    test('budgets with no spend still appear at zero progress', () async {
      final food = await harness.category('Food & Dining');
      await upsertBudget(categoryId: food.id, amountMinor: 30000);

      final progress = await julyProgress();

      expect(progress, hasLength(1));
      expect(progress.single.spentMinor, 0);
      expect(progress.single.fraction, 0);
    });

    test('spend outside the month is excluded', () async {
      final cash = await cashAccount();
      final food = await harness.category('Food & Dining');
      await upsertBudget(categoryId: food.id, amountMinor: 30000);

      await harness.transactions.create(
        TransactionBuilder.expense(
          occurredAt: DateTime(2026, 6, 30),
          currencyCode: 'PHP',
          fromAccountId: cash,
          categoryId: food.id,
          amountMinor: 50000,
        ),
      );

      final progress = await julyProgress();

      expect(progress.single.spentMinor, 0);
    });
  });
}
