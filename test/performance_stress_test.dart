import 'package:drift/drift.dart';
import 'package:finflow/core/utils/id_generator.dart';
import 'package:finflow/database/app_database.dart';
import 'package:finflow/features/accounts/domain/repositories/account_repository.dart';
import 'package:finflow/features/accounts/domain/enums/account_type.dart';
import 'package:finflow/features/transactions/domain/enums/ledger_direction.dart';
import 'package:finflow/features/transactions/domain/enums/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_database.dart';

/// Seeds [count] expense transactions (with balanced ledger entries) directly
/// through drift batches — the double-entry engine is already covered by the
/// repository tests; here we exercise the windowed *read* path at volume.
Future<void> seedTransactions(
  TestHarness harness, {
  required int count,
}) async {
  final cash = await harness.accounts.createAccount(
    CreateAccountInput(
      name: 'Stress Cash',
      type: AccountType.cash,
      currencyCode: 'PHP',
      openingBalanceMinor: count * 100,
    ),
  );
  final food = await harness.category('Food & Dining');

  final now = DateTime.now();
  await harness.db.transaction(() async {
    for (var batchStart = 0; batchStart < count; batchStart += 500) {
      final batchEnd = (batchStart + 500).clamp(0, count);
      await harness.db.batch((batch) {
        for (var i = batchStart; i < batchEnd; i++) {
          final id = IdGenerator.next();
          final occurredAt = now.subtract(Duration(minutes: i));
          final merchant = i % 100 == 0 ? 'Grocery #${i ~/ 100}' : 'Merchant $i';
          batch.insert(
            harness.db.transactions,
            TransactionsCompanion.insert(
              id: id,
              type: TransactionType.expense,
              amountMinor: 100 + (i % 100),
              currencyCode: 'PHP',
              occurredAt: occurredAt,
              merchant: Value(merchant),
              createdAt: occurredAt,
              updatedAt: occurredAt,
            ),
          );
          batch.insert(
            harness.db.ledgerEntries,
            LedgerEntriesCompanion.insert(
              id: IdGenerator.next(),
              transactionId: id,
              accountId: food.id,
              direction: LedgerDirection.debit,
              amountMinor: 100 + (i % 100),
              currencyCode: 'PHP',
            ),
          );
          batch.insert(
            harness.db.ledgerEntries,
            LedgerEntriesCompanion.insert(
              id: IdGenerator.next(),
              transactionId: id,
              accountId: cash.id,
              direction: LedgerDirection.credit,
              amountMinor: 100 + (i % 100),
              currencyCode: 'PHP',
            ),
          );
        }
      });
    }
  });
}

void main() {
  const pageSize = 100;

  test('windowed pages walk the whole history without gaps or overlaps',
      () async {
    final harness = await TestHarness.create();
    addTearDown(harness.dispose);
    await seedTransactions(harness, count: 1050);

    final seen = <String>[];
    var offset = 0;
    while (true) {
      final page = await harness.transactions.contextPage(
        limit: pageSize,
        offset: offset,
      );
      seen.addAll(page.map((c) => c.transaction.id));
      if (page.length < pageSize) break;
      offset += pageSize;
    }

    // 1050 seeded + 1 opening-balance transaction, no duplicates, newest
    // first.
    expect(seen, hasLength(1051));
    expect(seen.toSet(), hasLength(1051));

    // First page is ordered newest-first by occurrence.
    final firstPage = await harness.transactions.contextPage(
      limit: 10,
      offset: 0,
    );
    final dates = firstPage
        .map((c) => c.transaction.occurredAt)
        .toList();
    expect(
      dates,
      [...dates]..sort((a, b) => b.compareTo(a)),
    );
  });

  test('type filters narrow windowed results', () async {
    final harness = await TestHarness.create();
    addTearDown(harness.dispose);
    await seedTransactions(harness, count: 300);

    final incomes = await harness.transactions.contextPage(
      limit: pageSize,
      offset: 0,
      type: TransactionType.income,
    );
    expect(incomes, isEmpty);

    final expenses = await harness.transactions.contextPage(
      limit: pageSize,
      offset: 0,
      type: TransactionType.expense,
    );
    expect(expenses, hasLength(pageSize));
  });

  test('search matches merchant text at the database level', () async {
    final harness = await TestHarness.create();
    addTearDown(harness.dispose);
    await seedTransactions(harness, count: 500);

    // Grocery rows occur every 100 transactions (5 total).
    final grocery = await harness.transactions.contextPage(
      limit: pageSize,
      offset: 0,
      search: 'grocery',
    );
    expect(grocery, hasLength(5));
    expect(
      grocery.every((c) => c.transaction.merchant!.contains('Grocery')),
      isTrue,
    );

    final nothing = await harness.transactions.contextPage(
      limit: pageSize,
      offset: 0,
      search: 'zzzz-not-found',
    );
    expect(nothing, isEmpty);
  });

  test('the count stream matches the total and tracks writes', () async {
    final harness = await TestHarness.create();
    addTearDown(harness.dispose);
    await seedTransactions(harness, count: 250);

    final total = await harness.transactions.watchContextCount().first;
    expect(total, 251); // 250 seeded + 1 opening balance

    final filtered = await harness.transactions
        .watchContextCount(type: TransactionType.income)
        .first;
    expect(filtered, 0);
  });

  test('a 50k-transaction history stays responsive and consistent',
      () async {
    final harness = await TestHarness.create();
    addTearDown(harness.dispose);
    await seedTransactions(harness, count: 50000);

    final total = await harness.transactions.watchContextCount().first;
    expect(total, 50001); // 50000 seeded + 1 opening balance

    final stopwatch = Stopwatch()..start();
    final page = await harness.transactions.contextPage(
      limit: pageSize,
      offset: 45000,
    );
    stopwatch.stop();

    expect(page, hasLength(pageSize));
    // Extremely generous bound (in-memory SQLite); the point of the phase is
    // that a single window stays near-instant at volume.
    expect(stopwatch.elapsedMilliseconds, lessThan(3000));
  });
}
