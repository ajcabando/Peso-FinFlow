import 'package:drift/native.dart';
import 'package:finflow/database/app_database.dart';
import 'package:finflow/features/accounts/domain/enums/account_kind.dart';
import 'package:finflow/features/accounts/domain/enums/account_status.dart';
import 'package:finflow/features/accounts/domain/enums/account_type.dart';
import 'package:finflow/features/accounts/domain/models/account.dart';
import 'package:finflow/features/budgets/data/repositories/budget_repository_impl.dart';
import 'package:finflow/features/budgets/presentation/pages/budget_form_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/widget_harness.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  final now = DateTime(2026, 7, 1);

  void useTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Account expenseCategory({String id = 'c1', String name = 'Food & Dining'}) =>
      Account(
        id: id,
        name: name,
        kind: AccountKind.category,
        type: AccountType.expense,
        status: AccountStatus.active,
        openingBalanceMinor: 0,
        currencyCode: 'PHP',
        colorValue: 0xFF3B82F6,
        isHidden: false,
        sortOrder: 0,
        createdAt: now,
        updatedAt: now,
      );

  /// Inserts the category row the repository will validate against, so the
  /// fixture seen by the UI and the row in the DB stay in sync.
  Future<void> seedCategory(Account category) async {
    await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            id: category.id,
            name: category.name,
            kind: category.kind,
            type: category.type,
            status: category.status,
            openingBalanceMinor: 0,
            currencyCode: category.currencyCode,
            colorValue: category.colorValue,
            sortOrder: 0,
            isHidden: false,
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  testWidgets('creates a budget for a selected category', (tester) async {
    useTallViewport(tester);
    final food = expenseCategory();
    await seedCategory(food);

    await tester.pumpWidget(
      pumpApp(
        db,
        child: const BudgetFormPage(),
        categories: [food],
        budgets: const [],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Expense category'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Food & Dining').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Monthly limit',
      ),
      '500.00',
    );
    await tester.tap(find.text('Create Budget'));
    await tester.pumpAndSettle();

    final rows = await db.select(db.budgets).get();
    expect(rows, hasLength(1));
    expect(rows.single.amountMinor, 50000);
    expect(rows.single.currencyCode, 'PHP');
    expect(find.text('Budget created'), findsOneWidget);
  });

  testWidgets('requires a category before saving', (tester) async {
    useTallViewport(tester);
    final food = expenseCategory();
    await seedCategory(food);

    await tester.pumpWidget(
      pumpApp(
        db,
        child: const BudgetFormPage(),
        categories: [food],
        budgets: const [],
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Monthly limit',
      ),
      '500.00',
    );
    await tester.tap(find.text('Create Budget'));
    await tester.pumpAndSettle();

    expect(find.text('Select a category.'), findsOneWidget);
    expect(await db.select(db.budgets).get(), isEmpty);
  });

  testWidgets('rejects a non-positive amount', (tester) async {
    useTallViewport(tester);
    final food = expenseCategory();
    await seedCategory(food);

    await tester.pumpWidget(
      pumpApp(
        db,
        child: const BudgetFormPage(),
        categories: [food],
        budgets: const [],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Expense category'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Food & Dining').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Monthly limit',
      ),
      '0',
    );
    await tester.tap(find.text('Create Budget'));
    await tester.pumpAndSettle();

    expect(
      find.text('Enter a valid monthly amount greater than zero.'),
      findsOneWidget,
    );
    expect(await db.select(db.budgets).get(), isEmpty);
  });

  testWidgets('creates a new expense category inline', (tester) async {
    useTallViewport(tester);

    await tester.pumpWidget(
      pumpApp(
        db,
        child: const BudgetFormPage(),
        categories: const [],
        budgets: const [],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('New'));
    await tester.pumpAndSettle();
    expect(find.text('New Category'), findsOneWidget);

    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Category name',
      ),
      'Groceries',
    );
    await tester.ensureVisible(find.text('Create Category'));
    await tester.tap(find.text('Create Category'));
    await tester.pumpAndSettle();

    final rows = await (db.select(
      db.accounts,
    )..where((t) => t.kind.equalsValue(AccountKind.category))).get();
    expect(rows.where((r) => r.name == 'Groceries'), hasLength(1));
    // The form now targets the new category.
    expect(find.text('Groceries'), findsOneWidget);
  });

  testWidgets('creates a new category while editing an existing budget', (
    tester,
  ) async {
    useTallViewport(tester);
    final food = expenseCategory();
    await seedCategory(food);
    final budget = await BudgetRepositoryImpl(
      db: db,
    ).upsert(categoryId: food.id, amountMinor: 50000, currencyCode: 'PHP');

    await tester.pumpWidget(
      pumpApp(
        db,
        child: BudgetFormPage(budgetId: budget.id),
        categories: [food],
        budgets: [budget],
      ),
    );
    await tester.pumpAndSettle();

    // Creating a category while editing must not crash the dropdown: the new
    // category has to appear among the selectable items right away.
    await tester.tap(find.text('New'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Category name',
      ),
      'Groceries',
    );
    await tester.ensureVisible(find.text('Create Category'));
    await tester.tap(find.text('Create Category'));
    await tester.pumpAndSettle();

    expect(find.text('Groceries'), findsOneWidget);
    final rows = await (db.select(
      db.accounts,
    )..where((t) => t.kind.equalsValue(AccountKind.category))).get();
    expect(rows.where((r) => r.name == 'Groceries'), hasLength(1));
  });

  testWidgets('pre-fills and deletes an existing budget', (tester) async {
    useTallViewport(tester);
    final food = expenseCategory();
    await seedCategory(food);
    final budget = await BudgetRepositoryImpl(
      db: db,
    ).upsert(categoryId: food.id, amountMinor: 50000, currencyCode: 'PHP');

    await tester.pumpWidget(
      pumpApp(
        db,
        child: BudgetFormPage(budgetId: budget.id),
        categories: [food],
        budgets: [budget],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Edit Budget'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.labelText == 'Monthly limit' &&
            w.controller?.text == '500.00',
      ),
      findsOneWidget,
    );
    expect(find.text('Food & Dining'), findsOneWidget);

    // Deleting removes the budget row.
    await tester.tap(find.text('Delete Budget'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(await db.select(db.budgets).get(), isEmpty);
  });
}
