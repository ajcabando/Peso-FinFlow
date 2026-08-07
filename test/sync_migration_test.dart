import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:finflow/core/sync_session.dart';
import 'package:finflow/core/utils/id_generator.dart';
import 'package:finflow/database/app_database.dart';
import 'package:finflow/database/seed/default_categories.dart';
import 'package:finflow/database/seed/seed_ids.dart';
import 'package:finflow/database/seed/seed_reconciler.dart';
import 'package:finflow/features/accounts/domain/enums/account_kind.dart';
import 'package:finflow/features/accounts/domain/enums/account_status.dart';
import 'package:finflow/features/accounts/domain/enums/account_type.dart';
import 'package:finflow/features/transactions/domain/enums/ledger_direction.dart';
import 'package:finflow/features/transactions/domain/enums/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    SyncSession.instance.userId = null;
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('deterministic seeding', () {
    test('system account uses the canonical id', () async {
      final row = await db.accountDao.getOpeningBalancesAccount();
      expect(row, isNotNull);
      expect(row!.id, SeedIds.systemAccount);
    });

    test('default categories use the canonical ids', () async {
      final rows = await (db.select(
        db.accounts,
      )..where((t) => t.kind.equalsValue(AccountKind.category))).get();
      for (var i = 0; i < defaultCategories.length; i++) {
        expect(
          rows.map((r) => r.id),
          contains(SeedIds.category(i)),
          reason: defaultCategories[i].name,
        );
      }
    });
  });

  group('seed reconciler (legacy random-id upgrade path)', () {
    Future<String> insertLegacyRow({
      required String name,
      required AccountType type,
      String? legacySystemId,
    }) async {
      final id = legacySystemId ?? IdGenerator.next();
      final now = DateTime.now();
      await db.into(db.accounts).insert(
        AccountsCompanion.insert(
          id: id,
          name: name,
          kind: legacySystemId != null
              ? AccountKind.system
              : AccountKind.category,
          type: type,
          status: AccountStatus.active,
          openingBalanceMinor: 0,
          currencyCode: 'PHP',
          colorValue: 0xFF000000,
          sortOrder: 0,
          isHidden: true,
          createdAt: now,
          updatedAt: now,
        ),
      );
      return id;
    }

    Future<void> addLedgerReference(String accountId) async {
      final now = DateTime.now();
      final transactionId = IdGenerator.next();
      await db.transaction(() async {
        await db.into(db.transactions).insert(
          TransactionsCompanion.insert(
            id: transactionId,
            type: TransactionType.expense,
            amountMinor: 1000,
            currencyCode: 'PHP',
            occurredAt: now,
            createdAt: now,
            updatedAt: now,
          ),
        );
        await db.into(db.ledgerEntries).insert(
          LedgerEntriesCompanion.insert(
            id: IdGenerator.next(),
            transactionId: transactionId,
            accountId: accountId,
            direction: LedgerDirection.debit,
            amountMinor: 1000,
            currencyCode: 'PHP',
          ),
        );
      });
    }

    test('re-points a legacy system account and its ledger references',
        () async {
      final legacyId = await insertLegacyRow(
        name: 'Opening Balances',
        type: AccountType.openingBalance,
        legacySystemId: IdGenerator.next(),
      );
      await addLedgerReference(legacyId);

      await SeedReconciler.repoint(db);

      final system = await db.accountDao.getOpeningBalancesAccount();
      expect(system!.id, SeedIds.systemAccount);
      // The legacy id is gone and ledger entries now point at the canonical.
      expect(
        await (db.select(db.accounts)..where((t) => t.id.equals(legacyId)))
            .getSingleOrNull(),
        isNull,
      );
      final entries = await (db.select(
        db.ledgerEntries,
      )..where((t) => t.accountId.equals(SeedIds.systemAccount))).get();
      expect(entries, isNotEmpty);
    });

    test('re-points a legacy category row', () async {
      final salary = defaultCategories.firstWhere((c) => c.name == 'Salary');
      final legacyId = await insertLegacyRow(
        name: 'Salary',
        type: salary.type,
      );

      await SeedReconciler.repoint(db);

      final row = await (db.select(
        db.accounts,
      )..where((t) => t.id.equals(SeedIds.category(0)))).getSingleOrNull();
      expect(row, isNotNull);
      expect(row!.name, 'Salary');
      expect(
        await (db.select(db.accounts)..where((t) => t.id.equals(legacyId)))
            .getSingleOrNull(),
        isNull,
      );
    });
  });

  group('tombstone triggers', () {
    Future<void> insertAccount({required String id, String? userId}) async {
      final now = DateTime.now();
      await db.into(db.accounts).insert(
        AccountsCompanion.insert(
          id: id,
          name: id,
          kind: AccountKind.account,
          type: AccountType.bank,
          status: AccountStatus.active,
          openingBalanceMinor: 0,
          currencyCode: 'PHP',
          colorValue: 0xFF000000,
          sortOrder: 0,
          isHidden: false,
          createdAt: now,
          updatedAt: now,
          userId: Value(userId),
        ),
      );
    }

    test('deleting a synced row writes a tombstone', () async {
      await insertAccount(id: 'acc-1', userId: 'user-1');
      await (db.delete(db.accounts)..where((t) => t.id.equals('acc-1'))).go();

      final tombstones = await (db.select(db.syncTombstones)).get();
      expect(tombstones, hasLength(1));
      expect(tombstones.single.sourceTable, 'accounts');
      expect(tombstones.single.rowId, 'acc-1');
      expect(tombstones.single.userId, 'user-1');
      expect(tombstones.single.deletedAt, isNotNull);
    });

    test('deleting a local-only row writes no tombstone', () async {
      await insertAccount(id: 'acc-2');
      await (db.delete(db.accounts)..where((t) => t.id.equals('acc-2'))).go();

      expect(await (db.select(db.syncTombstones)).get(), isEmpty);
    });
  });
}
