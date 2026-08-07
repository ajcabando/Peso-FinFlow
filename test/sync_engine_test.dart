import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:finflow/core/sync_session.dart';
import 'package:finflow/database/app_database.dart';
import 'package:finflow/features/accounts/domain/enums/account_kind.dart';
import 'package:finflow/features/accounts/domain/enums/account_status.dart';
import 'package:finflow/features/accounts/domain/enums/account_type.dart';
import 'package:finflow/features/sync/data/sync_engine.dart';
import 'package:finflow/features/sync/data/sync_remote.dart';
import 'package:finflow/features/transactions/domain/enums/ledger_direction.dart';
import 'package:finflow/features/transactions/domain/enums/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory stand-in for the Supabase cloud: a set of per-table row maps.
class FakeSyncRemote implements SyncRemote {
  final Map<String, Map<String, Map<String, dynamic>>> tables = {};

  Map<String, Map<String, dynamic>> _table(String name) =>
      tables.putIfAbsent(name, () => {});

  @override
  Future<List<Map<String, dynamic>>> fetchChanged(
    String table, {
    required DateTime since,
    int limit = 1000,
  }) async {
    final rows = _table(table).values.where((row) {
      final ts = DateTime.tryParse((row['updated_at'] as String?) ?? '');
      return ts != null && ts.isAfter(since);
    }).toList()
      ..sort((a, b) => (a['updated_at'] as String).compareTo(b['updated_at'] as String));
    return rows;
  }

  @override
  Future<Map<String, DateTime>> fetchUpdatedAt(
    String table,
    List<String> ids,
  ) async {
    return {
      for (final id in ids)
        if (_table(table).containsKey(id))
          id: DateTime.parse(_table(table)[id]!['updated_at'] as String),
    };
  }

  @override
  Future<void> upsert(
    String table,
    List<Map<String, dynamic>> rows, {
    required String onConflict,
  }) async {
    for (final row in rows) {
      final key = row[onConflict] as String;
      _table(table)[key] = row;
    }
  }

  @override
  Future<void> replaceTransactionChildren(
    String transactionId, {
    required List<Map<String, dynamic>> ledgerEntries,
    required List<Map<String, dynamic>> transactionTags,
  }) async {
    _table('ledger_entries').removeWhere(
      (_, row) => row['transaction_id'] == transactionId,
    );
    _table('transaction_tags').removeWhere(
      (_, row) => row['transaction_id'] == transactionId,
    );
    for (final row in ledgerEntries) {
      _table('ledger_entries')[row['id'] as String] = row;
    }
    for (final row in transactionTags) {
      _table('transaction_tags')['${row['transaction_id']}:${row['tag_id']}'] =
          row;
    }
  }

  @override
  Future<Map<String, TransactionChildren>> fetchTransactionChildren(
    List<String> transactionIds,
  ) async {
    final result = <String, TransactionChildren>{};
    for (final id in transactionIds) {
      result[id] = TransactionChildren(
        ledgerEntries: [
          for (final row in _table('ledger_entries').values)
            if (row['transaction_id'] == id) row,
        ],
        transactionTags: [
          for (final row in _table('transaction_tags').values)
            if (row['transaction_id'] == id) row,
        ],
      );
    }
    return result;
  }
}

void main() {
  late AppDatabase db;
  late FakeSyncRemote remote;
  late SyncEngine engine;
  var now = DateTime.utc(2026, 8, 7, 12);

  setUp(() async {
    SyncSession.instance.userId = null;
    db = AppDatabase(NativeDatabase.memory());
    remote = FakeSyncRemote();
    engine = SyncEngine(db: db, remote: remote, clock: () => now);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> insertAccount({
    required String id,
    required String name,
    String? userId,
    DateTime? updatedAt,
  }) {
    final ts = updatedAt ?? now;
    return db.into(db.accounts).insert(
      AccountsCompanion.insert(
        id: id,
        name: name,
        kind: AccountKind.account,
        type: AccountType.bank,
        status: AccountStatus.active,
        openingBalanceMinor: 0,
        currencyCode: 'PHP',
        colorValue: 0xFF000000,
        sortOrder: 0,
        isHidden: false,
        createdAt: ts,
        updatedAt: ts,
        userId: Value(userId),
      ),
    );
  }

  group('adoption', () {
    test('adopts local rows and pushes everything on first sync', () async {
      await insertAccount(id: 'acc-1', name: 'BDO');
      await engine.adoptLocalData('user-1');

      final result = await engine.sync('user-1');
      expect(result.ok, isTrue);

      final cloud = remote.tables['accounts'];
      expect(cloud, contains('acc-1'));
      expect(cloud!['acc-1']!['name'], 'BDO');
    });

    test('does not push rows from a different user', () async {
      await insertAccount(id: 'acc-1', name: 'Mine', userId: 'user-1');
      await insertAccount(id: 'acc-2', name: 'Theirs', userId: 'user-2');
      await engine.adoptLocalData('user-1');
      await engine.sync('user-1');

      expect(remote.tables['accounts'], contains('acc-1'));
      expect(remote.tables['accounts'], isNot(contains('acc-2')));
    });
  });

  group('push & pull', () {
    test('pull applies rows created on another device', () async {
      await engine.adoptLocalData('user-1');
      await engine.sync('user-1');

      final later = now.add(const Duration(hours: 1));
      remote.tables['accounts'] = {
        'acc-remote': {
          'id': 'acc-remote',
          'name': 'GCash',
          'institution': null,
          'kind': 'account',
          'type': 'ewallet',
          'status': 'active',
          'opening_balance_minor': 0,
          'currency_code': 'PHP',
          'color_value': 0xFF000000,
          'icon_code': null,
          'notes': null,
          'sort_order': 0,
          'is_hidden': false,
          'created_at': later.toIso8601String(),
          'updated_at': later.toIso8601String(),
          'deleted_at': null,
        },
      };

      final result = await engine.sync('user-1');
      expect(result.ok, isTrue);

      final row = await (db.select(
        db.accounts,
      )..where((t) => t.id.equals('acc-remote'))).getSingleOrNull();
      expect(row, isNotNull);
      expect(row!.name, 'GCash');
      expect(row.userId, 'user-1');
    });

    test('newest edit wins in both directions', () async {
      // Local is newer: push must NOT clobber… local is pushed, so the cloud
      // should end with the local (newer) version.
      await insertAccount(id: 'acc-1', name: 'Old local name');
      await engine.adoptLocalData('user-1');
      await engine.sync('user-1');

      // Now the cloud has a NEWER edit than local.
      final later = now.add(const Duration(hours: 2));
      remote.tables['accounts'] = {
        'acc-1': {
          ...remote.tables['accounts']!['acc-1']!,
          'name': 'Renamed on cloud',
          'updated_at': later.toIso8601String(),
        },
      };
      // Local is not touched — still old.
      await (db.update(
        db.accounts,
      )..where((t) => t.id.equals('acc-1'))).write(
        AccountsCompanion(updatedAt: Value(now)),
      );

      await engine.sync('user-1');

      // Cloud wins locally…
      final localRow = await (db.select(
        db.accounts,
      )..where((t) => t.id.equals('acc-1'))).getSingleOrNull();
      expect(localRow!.name, 'Renamed on cloud');

      // …and the local (older) copy did not clobber the cloud.
      expect(
        remote.tables['accounts']!['acc-1']!['name'],
        'Renamed on cloud',
      );
    });
  });

  group('tombstones', () {
    test('a local delete propagates to the cloud and to other devices',
        () async {
      await insertAccount(id: 'acc-1', name: 'BDO');
      await engine.adoptLocalData('user-1');
      await engine.sync('user-1');

      // Delete locally — the trigger writes a tombstone.
      await (db.delete(db.accounts)..where((t) => t.id.equals('acc-1'))).go();

      await engine.sync('user-1');
      expect(
        remote.tables['accounts']!['acc-1']!['deleted_at'],
        isNotNull,
      );

      // A second device pulls the deletion.
      final db2 = AppDatabase(NativeDatabase.memory());
      final remote2 = FakeSyncRemote()
        ..tables['accounts'] = Map.of(remote.tables['accounts']!);
      final engine2 = SyncEngine(db: db2, remote: remote2, clock: () => now);
      await engine2.adoptLocalData('user-1');
      await engine2.sync('user-1');

      final row = await (db2.select(
        db2.accounts,
      )..where((t) => t.id.equals('acc-1'))).getSingleOrNull();
      expect(row, isNull);
      await db2.close();
    });
  });

  group('transaction children', () {
    test('a transaction pushes its ledger entries together', () async {
      await engine.adoptLocalData('user-1');
      await engine.sync('user-1');

      // Insert a transaction with balanced entries directly (the engine-level
      // path mirrors what the repository produces).
      await insertAccount(id: 'acc-a', name: 'Source');
      await insertAccount(id: 'acc-b', name: 'Target');
      final ts = now;
      await db.transaction(() async {
        await db.into(db.transactions).insert(
          TransactionsCompanion.insert(
            id: 'tx-1',
            type: TransactionType.transfer,
            amountMinor: 1000,
            currencyCode: 'PHP',
            occurredAt: ts,
            createdAt: ts,
            updatedAt: ts,
            userId: Value('user-1'),
          ),
        );
        await db.batch((b) {
          b.insertAll(db.ledgerEntries, [
            LedgerEntriesCompanion.insert(
              id: 'le-1',
            transactionId: 'tx-1',
            accountId: 'acc-a',
            direction: LedgerDirection.debit,
            amountMinor: 1000,
            currencyCode: 'PHP',
          ),
            LedgerEntriesCompanion.insert(
              id: 'le-2',
              transactionId: 'tx-1',
              accountId: 'acc-b',
              direction: LedgerDirection.credit,
              amountMinor: 1000,
              currencyCode: 'PHP',
            ),
          ]);
        });
      });

      await engine.sync('user-1');

      expect(remote.tables['transactions'], contains('tx-1'));
      expect(
        remote.tables['ledger_entries']!.values
            .where((e) => e['transaction_id'] == 'tx-1'),
        hasLength(2),
      );
    });
  });

  group('app_settings', () {
    test('security keys never leave the device', () async {
      await db.batch((b) {
        b.insertAll(db.appSettings, [
          AppSettingsCompanion.insert(
            key: 'settings.themeMode',
            value: 'dark',
            updatedAt: Value(now),
          ),
          AppSettingsCompanion.insert(
            key: 'security.pinHash',
            value: 'deadbeef',
            updatedAt: Value(now),
          ),
        ]);
      });
      await engine.adoptLocalData('user-1');
      await engine.sync('user-1');

      expect(
        remote.tables['app_settings'],
        contains('settings.themeMode'),
      );
      expect(remote.tables['app_settings'], isNot(contains('security.pinHash')));
    });
  });
}
