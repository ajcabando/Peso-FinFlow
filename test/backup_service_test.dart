import 'dart:convert';
import 'dart:typed_data';

import 'package:finflow/core/utils/id_generator.dart';
import 'package:finflow/database/app_database.dart';
import 'package:finflow/features/accounts/domain/enums/account_type.dart';
import 'package:finflow/features/accounts/domain/repositories/account_repository.dart';
import 'package:finflow/features/backup/data/backup_service.dart';
import 'package:finflow/features/transactions/domain/engine/transaction_builder.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_database.dart';

void main() {
  late TestHarness harness;

  setUp(() async {
    harness = await TestHarness.create();
  });

  tearDown(() => harness.dispose());

  Future<void> seedData() async {
    final wallet = await harness.accounts.createAccount(
      const CreateAccountInput(
        name: 'Backup Wallet',
        type: AccountType.ewallet,
        currencyCode: 'PHP',
        openingBalanceMinor: 500000,
      ),
    );
    final category = await harness.category('Food & Dining');
    await harness.transactions.create(
      TransactionBuilder.expense(
        occurredAt: DateTime(2026, 7, 3, 12, 30),
        currencyCode: 'PHP',
        fromAccountId: wallet.id,
        categoryId: category.id,
        amountMinor: 25000,
        merchant: 'Lunch',
      ),
    );
  }

  test('export → restore reproduces accounts, transactions and settings', () async {
    await seedData();
    final service = BackupService(db: harness.db);
    final backup = await service.exportBackup();
    expect(backup, isNotEmpty);

    final accountCountBefore =
        (await harness.db.select(harness.db.accounts).get()).length;

    // Mutate the database beyond recognition.
    await harness.db
        .delete(harness.db.ledgerEntries)
        .go();
    await harness.db.delete(harness.db.transactions).go();
    await harness.db.delete(harness.db.accounts).go();
    expect((await harness.db.select(harness.db.accounts).get()), isEmpty);

    // Restore the snapshot.
    await service.importBackup(backup);
    final restoredAccounts = await harness.db.select(harness.db.accounts).get();
    final restoredTransactions =
        await harness.db.select(harness.db.transactions).get();

    expect(restoredAccounts, hasLength(accountCountBefore));
    expect(
      restoredAccounts.map((r) => r.name),
      contains('Backup Wallet'),
    );
    // Opening-balance transaction + the lunch expense.
    expect(restoredTransactions, hasLength(2));
    expect(
      restoredTransactions.map((r) => r.merchant),
      contains('Lunch'),
    );
  });

  test('restored ledger still derives the same account balance', () async {
    await seedData();
    final service = BackupService(db: harness.db);
    final backup = await service.exportBackup();

    await service.importBackup(backup);

    final wallet = await harness.db.customSelect(
      "SELECT name FROM accounts WHERE name = 'Backup Wallet'",
    ).get();
    expect(wallet, isNotEmpty);

    final balances = await harness.accounts
        .watchAccountsWithBalances()
        .first;
    final walletBalance = balances.firstWhere(
      (entry) => entry.account.name == 'Backup Wallet',
    );
    // 500000 opening − 25000 lunch = 475000.
    expect(walletBalance.balanceMinor, 475000);
  });

  test('restoring a second time is idempotent (no duplicate rows)', () async {
    await seedData();
    final service = BackupService(db: harness.db);
    final backup = await service.exportBackup();

    await service.importBackup(backup);
    await service.importBackup(backup);

    final accounts = await harness.db.select(harness.db.accounts).get();
    final names = accounts.map((r) => r.name).toList();
    for (final name in names.toSet()) {
      expect(names.where((n) => n == name), hasLength(1));
    }
  });

  test('non-backup input is rejected', () {
    final service = BackupService(db: harness.db);
    expect(
      () => service.importBackup(Uint8List.fromList(utf8.encode('garbage'))),
      throwsA(isA<FormatException>()),
    );
  });

  test('backup includes bills and budgets', () async {
    await seedData();
    await harness.db
        .into(harness.db.bills)
        .insert(
          BillsCompanion.insert(
            id: IdGenerator.next(),
            name: 'Backed-up bill',
            amountMinor: 100000,
            currencyCode: 'PHP',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
    final service = BackupService(db: harness.db);
    final backup = await service.exportBackup();
    expect(utf8.decode(backup), contains('Backed-up bill'));
  });
}
