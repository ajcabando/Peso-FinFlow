import 'package:drift/native.dart';
import 'package:finflow/core/utils/id_generator.dart';
import 'package:finflow/database/app_database.dart';
import 'package:finflow/database/seed/database_seeder.dart';
import 'package:finflow/features/accounts/domain/enums/account_kind.dart';
import 'package:finflow/features/accounts/domain/enums/account_status.dart';
import 'package:finflow/features/accounts/domain/enums/account_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('schema', () {
    test('schema version is 4', () {
      expect(db.schemaVersion, 4);
    });

    test('creates all eleven tables', () async {
      final tables = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' "
            "AND name NOT LIKE 'sqlite_%'",
          )
          .get();
      final names = tables.map((r) => r.read<String>('name')).toSet();

      expect(
        names,
        containsAll([
          'accounts',
          'transactions',
          'ledger_entries',
          'tags',
          'transaction_tags',
          'attachments',
          'app_settings',
          'budgets',
          'bills',
          'sync_meta',
          'sync_tombstones',
        ]),
      );
    });

    test('creates the ledger indexes', () async {
      final indexes = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_%'",
          )
          .get();
      final names = indexes.map((r) => r.read<String>('name')).toSet();

      expect(
        names,
        containsAll([
          'idx_ledger_entries_account',
          'idx_ledger_entries_transaction',
          'idx_transactions_occurred_at',
        ]),
      );
    });
  });

  group('seeding', () {
    test('creates the Opening Balances system account', () async {
      final rows = await (db.select(
        db.accounts,
      )..where((t) => t.kind.equalsValue(AccountKind.system))).get();
      expect(rows, hasLength(1));
      expect(rows.single.type, AccountType.openingBalance);
    });

    test('seeds default income and expense categories', () async {
      final rows = await (db.select(
        db.accounts,
      )..where((t) => t.kind.equalsValue(AccountKind.category))).get();
      expect(rows, isNotEmpty);
      expect(
        rows.map((r) => r.type).toSet(),
        containsAll([AccountType.income, AccountType.expense]),
      );
      expect(
        rows.map((r) => r.name),
        containsAll(['Salary', 'Food & Dining', 'Utilities', 'Internet']),
      );
    });

    test(
      're-seeding after a manual category insert does not duplicate rows',
      () async {
        // Simulate a user-created custom category, then re-run the seeder.
        final now = DateTime.now();
        await db
            .into(db.accounts)
            .insert(
              AccountsCompanion.insert(
                id: IdGenerator.next(),
                name: 'My Custom Category',
                kind: AccountKind.category,
                type: AccountType.expense,
                status: AccountStatus.active,
                openingBalanceMinor: 0,
                currencyCode: 'PHP',
                colorValue: 0xFF123456,
                sortOrder: 99,
                isHidden: true,
                createdAt: now,
                updatedAt: now,
              ),
            );

        await DatabaseSeeder.seed(db);

        final rows = await (db.select(db.accounts)).get();
        final names = rows.map((r) => r.name).toList();
        // Exactly one instance of each category name.
        for (final name in names.toSet()) {
          expect(names.where((n) => n == name), hasLength(1));
        }
        expect(names, contains('My Custom Category'));
      },
    );
  });
}
