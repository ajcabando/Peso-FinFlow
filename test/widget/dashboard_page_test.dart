import 'package:drift/native.dart';
import 'package:finflow/database/app_database.dart';
import 'package:finflow/features/accounts/domain/enums/account_type.dart';
import 'package:finflow/features/accounts/domain/repositories/account_repository.dart';
import 'package:finflow/features/dashboard/presentation/pages/dashboard_page.dart';
import 'package:finflow/features/accounts/presentation/widgets/account_card_grid.dart';
import 'package:finflow/features/budgets/domain/models/budget.dart';
import 'package:finflow/features/budgets/domain/models/budget_progress.dart';
import 'package:finflow/features/transactions/domain/enums/transaction_type.dart';
import 'package:finflow/features/transactions/domain/models/category_spend.dart';
import 'package:finflow/features/transactions/domain/models/financial_transaction.dart';
import 'package:finflow/features/transactions/domain/models/monthly_cash_flow.dart';
import 'package:finflow/features/transactions/domain/models/transaction_context.dart';
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

  testWidgets('renders the Net Worth hero and empty recent activity', (
    tester,
  ) async {
    // Tall viewport so every dashboard section is built: the ListView builds
    // children lazily and the Quick actions / activity sections sit below the
    // fold in the default 800×600 test viewport.
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      pumpApp(
        db,
        child: const DashboardPage(),
        netWorth: 0,
        recentContexts: [],
        cashFlow: [],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('FinFlow'), findsOneWidget);
    expect(find.text('NET WORTH'), findsOneWidget);
    expect(find.text('Cash flow'), findsOneWidget);
    expect(find.text('Quick actions'), findsOneWidget);
    expect(find.text('Add Transaction'), findsOneWidget);
    expect(find.text('Transactions'), findsOneWidget);
    expect(find.text('No transactions yet'), findsOneWidget);
  });

  testWidgets('shows the default currency on a zero Net Worth', (tester) async {
    await tester.pumpWidget(
      pumpApp(
        db,
        child: const DashboardPage(),
        netWorth: 0,
        recentContexts: [],
        cashFlow: [],
      ),
    );
    await tester.pumpAndSettle();

    // The hero card shows the currency on Net Worth plus the income,
    // expense and savings stats.
    expect(find.textContaining('₱0.00'), findsNWidgets(4));
  });

  testWidgets('Net Worth renders the provided figure', (tester) async {
    await tester.pumpWidget(
      pumpApp(
        db,
        child: const DashboardPage(),
        netWorth: 500000,
        accountsWithBalances: const [],
        recentContexts: const [],
        cashFlow: const [],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('₱5,000.00'), findsWidgets);
  });

  testWidgets('renders recent transactions with account names', (tester) async {
    // Tall viewport so the Recent activity section is built and on-screen.
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      pumpApp(
        db,
        child: const DashboardPage(),
        netWorth: 150000,
        accountsWithBalances: const [],
        cashFlow: const [
          MonthlyCashFlow(
            year: 2026,
            month: 7,
            incomeMinor: 500000,
            expenseMinor: 250000,
          ),
        ],
        recentContexts: [
          TransactionContext(
            transaction: FinancialTransaction(
              id: 't1',
              type: TransactionType.expense,
              amountMinor: 25000,
              currencyCode: 'PHP',
              occurredAt: DateTime(2026, 7, 15),
              createdAt: DateTime(2026, 7, 15),
              updatedAt: DateTime(2026, 7, 15),
              merchant: 'Jollibee',
            ),
            accountName: 'GCash',
            categoryName: 'Food & Dining',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Jollibee'), findsOneWidget);
    expect(find.textContaining('GCash'), findsOneWidget);
    expect(find.textContaining('Food & Dining'), findsOneWidget);
  });

  testWidgets('renders the spending by category section', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      pumpApp(
        db,
        child: const DashboardPage(),
        netWorth: 150000,
        accountsWithBalances: const [],
        recentContexts: const [],
        cashFlow: const [],
        categorySpend: const [
          CategorySpend(
            categoryId: 'c1',
            categoryName: 'Food & Dining',
            amountMinor: 25000,
            isIncome: false,
            colorValue: 0xFF3B82F6,
          ),
          CategorySpend(
            categoryId: 'c2',
            categoryName: 'Salary',
            amountMinor: 30000,
            isIncome: true,
            colorValue: 0xFF10B981,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Spending by category'), findsOneWidget);
    // The amount appears in the donut centre and the ranked list row.
    expect(find.text('₱250.00'), findsNWidgets(2));
    // Income is not part of the dashboard spending breakdown.
    expect(find.text('Salary'), findsNothing);
  });

  testWidgets('renders the budgets section with progress', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      pumpApp(
        db,
        child: const DashboardPage(),
        netWorth: 150000,
        accountsWithBalances: const [],
        recentContexts: const [],
        cashFlow: const [],
        budgetProgress: [
          BudgetProgress(
            budget: Budget(
              id: 'b1',
              categoryId: 'c1',
              amountMinor: 30000,
              currencyCode: 'PHP',
              createdAt: DateTime(2026, 7, 1),
              updatedAt: DateTime(2026, 7, 1),
            ),
            categoryName: 'Transportation',
            colorValue: 0xFFF59E0B,
            spentMinor: 45000,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Budgets'), findsOneWidget);
    expect(find.text('Transportation'), findsOneWidget);
    // 450.00 spent against a 300.00 budget → 150.00 over.
    expect(find.text('₱150.00 over'), findsOneWidget);
  });

  testWidgets('compact account strip does not overflow on a narrow phone', (
    tester,
  ) async {
    // Tall enough that the accounts section (below the What's-new banner)
    // is built by the lazy ListView on this narrow viewport.
    tester.view.physicalSize = const Size(360, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final harness = TestHarness.attach(db);
    final wallet = await harness.accounts.createAccount(
      const CreateAccountInput(
        name: 'GCash Wallet With A Long Name',
        type: AccountType.ewallet,
        currencyCode: 'PHP',
        openingBalanceMinor: 123456789,
      ),
    );

    await tester.pumpWidget(
      pumpApp(
        db,
        child: const DashboardPage(),
        netWorth: 123456789,
        accountsWithBalances: [
          AccountWithBalance(account: wallet, balanceMinor: 123456789),
        ],
        recentContexts: const [],
        cashFlow: const [],
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('My accounts'), findsOneWidget);
    expect(find.textContaining('GCash Wallet'), findsOneWidget);
    // Narrow screens keep the swipeable strip, not the responsive grid.
    expect(find.byType(AccountCardGrid), findsNothing);
  });

  testWidgets('My accounts reflows into a grid on wide displays', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final harness = TestHarness.attach(db);
    for (final name in ['Wallet', 'GCash', 'BDO']) {
      await harness.accounts.createAccount(
        CreateAccountInput(
          name: name,
          type: AccountType.cash,
          currencyCode: 'PHP',
        ),
      );
    }
    final all = await WidgetDb.realAccounts(db);
    final entries = [
      for (final account in all)
        AccountWithBalance(account: account, balanceMinor: 10000),
    ];

    await tester.pumpWidget(
      pumpApp(
        db,
        child: const DashboardPage(),
        netWorth: 30000,
        accountsWithBalances: entries,
        recentContexts: const [],
        cashFlow: const [],
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // On tablets / desktop / web the section reflows into a grid instead of
    // staying a fixed phone-sized strip.
    expect(find.byType(AccountCardGrid), findsOneWidget);
    for (final name in ['Wallet', 'GCash', 'BDO']) {
      expect(find.text(name), findsOneWidget);
    }
  });
}
