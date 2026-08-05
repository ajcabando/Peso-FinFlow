import 'package:drift/native.dart';
import 'package:finflow/core/theme/app_colors.dart';
import 'package:finflow/database/app_database.dart';
import 'package:finflow/features/accounts/domain/enums/account_kind.dart';
import 'package:finflow/features/accounts/domain/enums/account_type.dart';
import 'package:finflow/features/accounts/domain/repositories/account_repository.dart';
import 'package:finflow/features/transactions/domain/enums/transaction_type.dart';
import 'package:finflow/features/transactions/presentation/pages/transaction_form_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_database.dart';
import '../helpers/widget_harness.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('records an expense into the double-entry ledger', (
    tester,
  ) async {
    // Taller viewport so the whole form (incl. the Save button) is visible.
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final harness = TestHarness.attach(db);
    final cash = await harness.accounts.createAccount(
      const CreateAccountInput(
        name: 'Cash',
        type: AccountType.cash,
        currencyCode: 'PHP',
        openingBalanceMinor: 100000,
      ),
    );

    final accounts = await WidgetDb.realAccounts(db);
    final categories = await WidgetDb.categories(db);

    await tester.pumpWidget(
      pumpApp(
        db,
        child: const TransactionFormPage(),
        accounts: accounts,
        categories: categories,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Amount',
      ),
      '250.00',
    );

    // Pick the expense category from the dropdown.
    await tester.tap(find.text('Category').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Food & Dining').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save Transaction'));
    await tester.pumpAndSettle();

    // One-shot verification. (The account's opening balance created its own
    // ledger transaction, so filter for the expense we just recorded.)
    final rows = await db.select(db.transactions).get();
    final expenses = rows
        .where((r) => r.type == TransactionType.expense)
        .toList();
    expect(expenses, hasLength(1));
    expect(expenses.single.amountMinor, 25000);

    // Cash was credited 250.00 — its ledger sum now shows the outflow.
    final sums = await db.ledgerDao.sumsFor(cash.id);
    expect(sums.credit, 25000);
  });

  testWidgets('records a transfer between two accounts', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final harness = TestHarness.attach(db);
    final cash = await harness.accounts.createAccount(
      const CreateAccountInput(
        name: 'Cash',
        type: AccountType.cash,
        currencyCode: 'PHP',
        openingBalanceMinor: 100000,
      ),
    );
    final gcash = await harness.accounts.createAccount(
      const CreateAccountInput(
        name: 'GCash',
        type: AccountType.ewallet,
        currencyCode: 'PHP',
      ),
    );

    final accounts = await WidgetDb.realAccounts(db);
    final categories = await WidgetDb.categories(db);

    await tester.pumpWidget(
      pumpApp(
        db,
        child: const TransactionFormPage(),
        accounts: accounts,
        categories: categories,
      ),
    );
    await tester.pumpAndSettle();

    // Switch to Transfer and enter the amount.
    await tester.tap(find.text('Transfer'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Amount',
      ),
      '300.00',
    );

    await tester.tap(find.text('Save Transaction'));
    await tester.pumpAndSettle();

    final rows = await db.select(db.transactions).get();
    final transfers = rows
        .where((r) => r.type == TransactionType.transfer)
        .toList();
    expect(transfers, hasLength(1));
    expect(transfers.single.amountMinor, 30000);

    // Cash was credited 300.00; GCash was debited 300.00.
    expect((await db.ledgerDao.sumsFor(cash.id)).credit, 30000);
    expect((await db.ledgerDao.sumsFor(gcash.id)).debit, 30000);
  });

  testWidgets('clears the category when switching types', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final harness = TestHarness.attach(db);
    await harness.accounts.createAccount(
      const CreateAccountInput(
        name: 'Cash',
        type: AccountType.cash,
        currencyCode: 'PHP',
        openingBalanceMinor: 100000,
      ),
    );

    final accounts = await WidgetDb.realAccounts(db);
    final categories = await WidgetDb.categories(db);

    await tester.pumpWidget(
      pumpApp(
        db,
        child: const TransactionFormPage(),
        accounts: accounts,
        categories: categories,
      ),
    );
    await tester.pumpAndSettle();

    // Pick an expense category first.
    await tester.tap(find.text('Category').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Food & Dining').last);
    await tester.pumpAndSettle();

    // Switching to Income must drop the stale expense category; the form
    // should then offer income categories only.
    await tester.tap(find.text('Income'));
    await tester.pumpAndSettle();

    expect(find.text('Income category'), findsOneWidget);
    // The stale expense category is no longer selected in the income list.
    final incomeItems = find.descendant(
      of: find.byType(DropdownButtonFormField<String>),
      matching: find.text('Food & Dining'),
    );
    expect(incomeItems, findsNothing);
  });

  testWidgets('creates a new category inline from the form', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final harness = TestHarness.attach(db);
    await harness.accounts.createAccount(
      const CreateAccountInput(
        name: 'Cash',
        type: AccountType.cash,
        currencyCode: 'PHP',
        openingBalanceMinor: 100000,
      ),
    );

    final accounts = await WidgetDb.realAccounts(db);
    final categories = await WidgetDb.categories(db);

    await tester.pumpWidget(
      pumpApp(
        db,
        child: const TransactionFormPage(),
        accounts: accounts,
        categories: categories,
      ),
    );
    await tester.pumpAndSettle();

    // Open the inline category form and create a brand-new category.
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

    // The category was persisted and got a palette colour that stays
    // distinct from the seeded defaults.
    final rows = await (db.select(
      db.accounts,
    )..where((t) => t.kind.equalsValue(AccountKind.category))).get();
    final groceries = rows.singleWhere((r) => r.name == 'Groceries');
    expect(
      AppColors.accountPalette.map((c) => c.toARGB32()).toList(),
      contains(groceries.colorValue),
    );

    // The form selected the new category automatically.
    expect(find.text('Groceries'), findsOneWidget);
  });

  testWidgets('rejects an empty amount', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final harness = TestHarness.attach(db);
    await harness.accounts.createAccount(
      const CreateAccountInput(
        name: 'Cash',
        type: AccountType.cash,
        currencyCode: 'PHP',
      ),
    );

    final accounts = await WidgetDb.realAccounts(db);
    final categories = await WidgetDb.categories(db);

    await tester.pumpWidget(
      pumpApp(
        db,
        child: const TransactionFormPage(),
        accounts: accounts,
        categories: categories,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save Transaction'));
    await tester.pumpAndSettle();

    expect(await db.select(db.transactions).get(), isEmpty);
  });
}
