import 'package:finflow/features/bills/data/repositories/bill_repository_impl.dart';
import 'package:finflow/features/bills/presentation/pages/bills_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_database.dart';
import '../helpers/widget_harness.dart';

void main() {
  late TestHarness harness;

  setUp(() async {
    harness = await TestHarness.create();
  });

  tearDown(() => harness.dispose());

  testWidgets('renders bills with due amounts and status chips', (tester) async {
    final repo = BillRepositoryImpl(db: harness.db);
    final internet = await repo.create(
      name: 'Internet',
      amountMinor: 150000,
      currencyCode: 'PHP',
      dueDayOfMonth: 28,
      reminderDaysBefore: 3,
    );

    await tester.pumpWidget(
      pumpApp(
        harness.db,
        bills: [internet],
        child: const BillsPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Internet'), findsOneWidget);
    // Shown in the summary card and on the bill tile itself.
    expect(find.text('₱1,500.00'), findsNWidgets(2));
    expect(find.text('Bills & Reminders'), findsOneWidget);
    // No bills need attention this month by default.
    expect(find.text('0 need attention'), findsOneWidget);
  });

  testWidgets('an overdue bill shows the mark-paid action and pays it',
      (tester) async {
    final repo = BillRepositoryImpl(db: harness.db);
    // Due yesterday so the status is always "overdue" regardless of when the
    // suite runs.
    final yesterday =
        DateTime.now().day == 1 ? 2 : DateTime.now().day - 1;
    final rent = await repo.create(
      name: 'Rent',
      amountMinor: 1200000,
      currencyCode: 'PHP',
      dueDayOfMonth: yesterday,
      reminderDaysBefore: 3,
    );

    await tester.pumpWidget(
      pumpApp(harness.db, bills: [rent], child: const BillsPage()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Overdue'), findsOneWidget);

    // Mark paid → persists through the repository.
    await tester.tap(find.byIcon(Icons.check_circle_outline));
    await tester.pumpAndSettle();

    final stored = await harness.db.billDao.getById(rent.id);
    expect(stored, isNotNull);
    expect(stored!.lastPaidOn, isNotNull);
  });

  testWidgets('offers the add-bill action in the app bar', (tester) async {
    final repo = BillRepositoryImpl(db: harness.db);
    final bill = await repo.create(
      name: 'Water',
      amountMinor: 50000,
      currencyCode: 'PHP',
      dueDayOfMonth: 10,
      reminderDaysBefore: 3,
    );

    await tester.pumpWidget(
      pumpApp(harness.db, bills: [bill], child: const BillsPage()),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(BillsPage),
        matching: find.byIcon(Icons.add_rounded),
      ),
      findsOneWidget,
    );
  });
}
