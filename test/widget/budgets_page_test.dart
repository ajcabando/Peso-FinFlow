import 'package:drift/native.dart';
import 'package:finflow/database/app_database.dart';
import 'package:finflow/features/budgets/domain/models/budget.dart';
import 'package:finflow/features/budgets/domain/models/budget_progress.dart';
import 'package:finflow/features/budgets/presentation/pages/budgets_page.dart';
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

  void useTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Budget budget(String id, String categoryId, int amountMinor) => Budget(
    id: id,
    categoryId: categoryId,
    amountMinor: amountMinor,
    currencyCode: 'PHP',
    createdAt: DateTime(2026, 7, 1),
    updatedAt: DateTime(2026, 7, 1),
  );

  testWidgets('renders budgets with progress and a summary', (tester) async {
    useTallViewport(tester);

    await tester.pumpWidget(
      pumpApp(
        db,
        child: const BudgetsPage(),
        budgetProgress: [
          BudgetProgress(
            budget: budget('b1', 'c1', 30000),
            categoryName: 'Food & Dining',
            colorValue: 0xFF3B82F6,
            spentMinor: 20000,
          ),
          BudgetProgress(
            budget: budget('b2', 'c2', 40000),
            categoryName: 'Transportation',
            colorValue: 0xFFF59E0B,
            spentMinor: 45000,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Budgets'), findsOneWidget);
    expect(find.text('Monthly budgets'), findsOneWidget);
    expect(find.text('BUDGETED'), findsOneWidget);
    // Appears on the donut centre and the stats column.
    expect(find.text('SPENT'), findsNWidgets(2));
    expect(find.text('LEFT'), findsOneWidget);
    expect(find.text('Food & Dining'), findsOneWidget);
    expect(find.text('Transportation'), findsOneWidget);
    // Summary totals: ₱700 budgeted, ₱650 spent, ₱50 left.
    expect(find.text('₱700.00'), findsOneWidget);
    expect(find.text('₱650.00'), findsOneWidget);
    expect(find.text('₱50.00'), findsOneWidget);
    // Over-budget label for Transportation.
    expect(find.text('₱50.00 over'), findsOneWidget);
  });

  testWidgets('shows an empty state without budgets', (tester) async {
    useTallViewport(tester);

    await tester.pumpWidget(pumpApp(db, child: const BudgetsPage()));
    await tester.pumpAndSettle();

    expect(find.text('No budgets yet'), findsOneWidget);
    expect(find.text('Create budget'), findsOneWidget);
  });
}
