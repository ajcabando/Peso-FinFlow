import 'package:drift/native.dart';
import 'package:finflow/database/app_database.dart';
import 'package:finflow/features/accounts/domain/enums/account_kind.dart';
import 'package:finflow/features/accounts/presentation/pages/account_form_page.dart';
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

  testWidgets('creates an account with an opening balance', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(pumpApp(db, child: const AccountFormPage()));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Account name',
      ),
      'Maya',
    );
    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Opening balance',
      ),
      '1000.00',
    );
    await tester.tap(find.text('Save Account'));
    await tester.pumpAndSettle();

    // One-shot verification (no drift watch streams in widget tests).
    final accounts = await (db.select(
      db.accounts,
    )..where((t) => t.kind.equalsValue(AccountKind.account))).get();
    expect(accounts, hasLength(1));
    expect(accounts.single.name, 'Maya');
    expect(accounts.single.openingBalanceMinor, 100000);

    // The opening balance was recorded through the ledger.
    final sums = await db.ledgerDao.sumsFor(accounts.single.id);
    expect(sums.debit, 100000);
  });

  testWidgets('does not create an account with an empty name', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(pumpApp(db, child: const AccountFormPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save Account'));
    await tester.pumpAndSettle();

    final accounts = await (db.select(
      db.accounts,
    )..where((t) => t.kind.equalsValue(AccountKind.account))).get();
    expect(accounts, isEmpty);
  });
}
