import 'package:finflow/shared/widgets/quick_actions_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> openSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  showDragHandle: true,
                  builder: (_) => const QuickActionsSheet(),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  const allLabels = [
    'Income',
    'Expense',
    'Transfer',
    'Cash In',
    'Cash Out',
    'Card Purchase',
    'Card Payment',
    'Loan',
    'Investment',
  ];

  testWidgets('renders every action plus page shortcuts', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await openSheet(tester);

    expect(find.text('Quick actions'), findsOneWidget);
    for (final label in allLabels) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Bills'), findsOneWidget);
    expect(find.text('Reports'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fits on a small phone without overflow', (tester) async {
    // iPhone SE (1st gen) class viewport — the compact grid must not throw
    // a RenderFlex overflow.
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await openSheet(tester);

    expect(find.text('Income'), findsOneWidget);
    expect(find.text('Card Purchase'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reflows into five columns on a tablet', (tester) async {
    // DPR 1.0 so the logical width (1024) clears the 600px breakpoint and
    // the wide five-column grid is actually exercised.
    tester.view.physicalSize = const Size(1024, 1366);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await openSheet(tester);

    for (final label in allLabels) {
      expect(find.text(label), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
}
