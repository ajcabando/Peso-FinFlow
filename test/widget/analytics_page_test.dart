import 'package:drift/native.dart';
import 'package:finflow/core/extensions/date_time_extensions.dart';
import 'package:finflow/database/app_database.dart';
import 'package:finflow/features/dashboard/presentation/pages/analytics_page.dart';
import 'package:finflow/features/transactions/domain/models/category_spend.dart';
import 'package:finflow/features/transactions/domain/models/net_worth_point.dart';
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
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('renders net worth history and category breakdowns', (
    tester,
  ) async {
    useTallViewport(tester);

    await tester.pumpWidget(
      pumpApp(
        db,
        child: const AnalyticsPage(),
        netWorthTrend: const [
          NetWorthPoint(year: 2026, month: 6, netWorthMinor: 100000),
          NetWorthPoint(year: 2026, month: 7, netWorthMinor: 75000),
        ],
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

    expect(find.text('Analytics'), findsOneWidget);
    expect(find.text('Net worth history'), findsOneWidget);
    expect(find.text('Spending by category'), findsOneWidget);
    expect(find.text('Income by category'), findsOneWidget);
    expect(find.text('Food & Dining'), findsOneWidget);
    expect(find.text('Salary'), findsOneWidget);
    expect(find.text('₱250.00'), findsWidgets);
    expect(find.text('₱300.00'), findsWidgets);
  });

  testWidgets('navigates between months', (tester) async {
    useTallViewport(tester);

    await tester.pumpWidget(pumpApp(db, child: const AnalyticsPage()));
    await tester.pumpAndSettle();

    final now = DateTime.now();
    expect(find.text(now.monthYear), findsOneWidget);

    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    final previous = DateTime(now.year, now.month - 1, 1);
    expect(find.text(previous.monthYear), findsOneWidget);

    // Next month is enabled again after stepping back.
    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    expect(find.text(now.monthYear), findsOneWidget);

    // At the current month the forward button is disabled.
    final nextButton = tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip('Next month'),
        matching: find.byType(IconButton),
      ),
    );
    expect(nextButton.onPressed, isNull);
  });

  testWidgets('shows empty states without data', (tester) async {
    useTallViewport(tester);

    await tester.pumpWidget(pumpApp(db, child: const AnalyticsPage()));
    await tester.pumpAndSettle();

    expect(
      find.text('Record income or expenses to see your\nnet worth history.'),
      findsOneWidget,
    );
    expect(find.textContaining('No expenses recorded'), findsOneWidget);
    expect(find.textContaining('No income recorded'), findsOneWidget);
  });
}
