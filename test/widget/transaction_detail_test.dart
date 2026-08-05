import 'package:drift/native.dart';
import 'package:finflow/database/app_database.dart';
import 'package:finflow/features/accounts/domain/enums/account_kind.dart';
import 'package:finflow/features/accounts/domain/enums/account_status.dart';
import 'package:finflow/features/accounts/domain/enums/account_type.dart';
import 'package:finflow/features/accounts/domain/models/account.dart';
import 'package:finflow/features/transactions/domain/enums/transaction_type.dart';
import 'package:finflow/features/transactions/domain/models/financial_transaction.dart';
import 'package:finflow/features/transactions/domain/models/transaction_context.dart';
import 'package:finflow/features/transactions/domain/models/transaction_edit_data.dart';
import 'package:finflow/features/transactions/presentation/pages/transaction_detail_page.dart';
import 'package:finflow/features/transactions/presentation/pages/transaction_form_page.dart';
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

  final transaction = FinancialTransaction(
    id: 't-1',
    type: TransactionType.expense,
    amountMinor: 25000,
    currencyCode: 'PHP',
    occurredAt: DateTime(2026, 7, 15, 18, 30),
    createdAt: DateTime(2026, 7, 15),
    updatedAt: DateTime(2026, 7, 15),
    merchant: 'Jollibee',
    note: 'Dinner with friends',
    referenceNumber: 'REF-123',
  );

  testWidgets('shows all transaction details', (tester) async {
    await tester.pumpWidget(
      pumpApp(
        db,
        child: TransactionDetailPage(transactionId: 't-1'),
        transactionContext: TransactionContext(
          transaction: transaction,
          accountName: 'GCash',
          categoryName: 'Food & Dining',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Jollibee'), findsOneWidget);
    // The detail page renders the amount with an explicit expense sign.
    expect(find.text('−₱250.00'), findsOneWidget);
    expect(find.text('GCash'), findsOneWidget);
    expect(find.text('Food & Dining'), findsOneWidget);
    expect(find.text('Dinner with friends'), findsOneWidget);
    expect(find.text('REF-123'), findsOneWidget);
    expect(find.text('Expense'), findsOneWidget);
  });

  testWidgets('shows a not-found state for a missing transaction', (
    tester,
  ) async {
    await tester.pumpWidget(
      pumpApp(db, child: const TransactionDetailPage(transactionId: 'missing')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Transaction not found.'), findsOneWidget);
  });

  testWidgets('pre-fills every field in edit mode', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // The form's dropdowns validate that every selected id has a matching
    // item, so the source account and category referenced by the edit data
    // must exist in the fixture lists.
    final now = DateTime(2026, 7, 15);
    final sourceAccount = Account(
      id: 'acc-1',
      name: 'GCash',
      kind: AccountKind.account,
      type: AccountType.ewallet,
      status: AccountStatus.active,
      openingBalanceMinor: 0,
      currencyCode: 'PHP',
      colorValue: 0xFF000000,
      isHidden: false,
      sortOrder: 0,
      createdAt: now,
      updatedAt: now,
    );
    final expenseCategory = Account(
      id: 'cat-1',
      name: 'Food & Dining',
      kind: AccountKind.category,
      type: AccountType.expense,
      status: AccountStatus.active,
      openingBalanceMinor: 0,
      currencyCode: 'PHP',
      colorValue: 0xFF000000,
      isHidden: false,
      sortOrder: 0,
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      pumpApp(
        db,
        child: const TransactionFormPage(transactionId: 't-1'),
        accounts: [sourceAccount],
        categories: [expenseCategory],
        editData: TransactionEditData(
          transaction: transaction,
          sourceAccountId: 'acc-1',
          categoryId: 'cat-1',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Edit Transaction'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.labelText == 'Amount' &&
            w.controller?.text == '250.00',
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.labelText == 'Merchant (optional)' &&
            w.controller?.text == 'Jollibee',
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.labelText == 'Note (optional)' &&
            w.controller?.text == 'Dinner with friends',
      ),
      findsOneWidget,
    );
  });
}
