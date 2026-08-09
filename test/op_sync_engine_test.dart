import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:finflow/core/sync_session.dart';
import 'package:finflow/database/app_database.dart';
import 'package:finflow/features/accounts/domain/enums/account_kind.dart';
import 'package:finflow/features/accounts/domain/enums/account_status.dart';
import 'package:finflow/features/accounts/domain/enums/account_type.dart';
import 'package:finflow/features/sync/data/api/api_client.dart';
import 'package:finflow/features/sync/data/auth/token_store.dart';
import 'package:finflow/features/sync/data/sync/device_registry.dart';
import 'package:finflow/features/sync/data/sync/op_sync_engine.dart';
import 'package:finflow/features/sync/data/sync/sync_outbox_writer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory stand-in for the self-hosted API: an op log with server-assigned
/// seqs, idempotency by opId, CAS + LWW conflict resolution (mirrors
/// `server/src/sync`), and a devices list. Talks to [OpSyncEngine] through a
/// real [ApiClient] + MockClient, so the engine's HTTP path is exercised.
class FakeApiServer {
  FakeApiServer();

  final List<Map<String, dynamic>> ops = [];
  final Map<String, Map<String, dynamic>> currentState = {};
  int _seq = 0;

  String? accessToken = 'access-token-1';
  String? refreshToken = 'refresh-token-1';

  /// When set, the next push returns these conflicts verbatim.
  List<Map<String, dynamic>> forcedConflicts = [];

  /// Pull page size (mirrors the real server's `limit` cap). 0 = no cap.
  int pullPageSize = 0;

  /// How many pull requests returned at least one op (cursor-advance probes).
  int pullsWithOps = 0;

  http.Client client() {
    return MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/auth/login')) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        return _json(200, {
          'accessToken': accessToken,
          'expiresIn': 900,
          'refreshToken': refreshToken,
          'user': {'id': 'user-1', 'email': body['email'], 'isVerified': true},
        });
      }
      if (path.endsWith('/auth/refresh')) {
        refreshToken = 'refresh-token-2';
        accessToken = 'access-token-2';
        return _json(200, {
          'accessToken': accessToken,
          'expiresIn': 900,
          'refreshToken': refreshToken,
        });
      }
      if (path.endsWith('/sync/push')) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final result = _push(body['ops'] as List);
        return _json(200, result);
      }
      if (path.endsWith('/sync/pull')) {
        final cursor = int.parse(request.url.queryParameters['cursor'] ?? '0');
        final limit =
            int.parse(request.url.queryParameters['limit'] ?? '1000');
        final result = _pull(cursor, limit);
        return _json(200, result);
      }
      if (path.endsWith('/devices')) {
        return _json(200, {'devices': []});
      }
      return _json(404, _error('NOT_FOUND', 'no such route'));
    });
  }

  Map<String, dynamic> _push(List<dynamic> incoming) {
    // Fires on EVERY push while set (the engine pushes once, then retries
    // after rebasing — both must conflict to simulate a genuine race that
    // never converges).
    if (forcedConflicts.isNotEmpty) {
      return {
        'applied': <Map<String, dynamic>>[],
        'conflicts': forcedConflicts,
        'serverCursor': null,
      };
    }

    final applied = <Map<String, dynamic>>[];
    final conflicts = <Map<String, dynamic>>[];
    for (final raw in incoming) {
      final op = Map<String, dynamic>.from(raw as Map);
      final existing = ops.where((o) => o['opId'] == op['opId']).toList();
      if (existing.isNotEmpty) {
        applied.add({'opId': op['opId'], 'seq': existing.first['seq']});
        continue;
      }
      final key = '${op['entity']}:${op['entityId']}';
      final current = currentState[key];
      final currentVersion = (current?['version'] as num?)?.toInt() ?? 0;
      final opVersion = (op['version'] as num).toInt();

      // CAS: base > stored → conflict.
      if ((op['baseVersion'] as num).toInt() > currentVersion) {
        conflicts.add({
          'opId': op['opId'],
          'current': current?['payload'],
        });
        continue;
      }
      // LWW: stored wins → conflict.
      final storedUpdatedAt =
          (current?['updatedAt'] ?? current?['payload']?['updated_at'] ?? '')
              .toString();
      if (current != null &&
          (opVersion < currentVersion ||
              (opVersion == currentVersion &&
                  storedUpdatedAt.compareTo(
                        (op['updatedAt'] ?? '').toString(),
                      ) >=
                      0))) {
        conflicts.add({
          'opId': op['opId'],
          'current': current['payload'],
        });
        continue;
      }

      _seq++;
      ops.add({...op, 'seq': _seq});
      currentState[key] = {...op, 'seq': _seq};
      applied.add({'opId': op['opId'], 'seq': _seq});
    }
    final serverCursor = applied.isEmpty
        ? null
        : (applied.map((a) => a['seq'] as int).reduce((a, b) => a > b ? a : b));
    return {'applied': applied, 'conflicts': conflicts, 'serverCursor': serverCursor};
  }

  /// Mirrors the real server (`server/src/sync/sync.service.ts`): ops with
  /// seq > cursor, capped at [limit]; `truncated: true` + `nextCursor: maxSeq`
  /// while more remain, `nextCursor: 0` on the final page (the "caught up"
  /// sentinel). Every op carries its immutable `seq`.
  Map<String, dynamic> _pull(int cursor, int limit) {
    final cap = pullPageSize > 0 && pullPageSize < limit ? pullPageSize : limit;
    final all = ops.where((o) => (o['seq'] as int) > cursor).toList();
    final page = all.take(cap).toList();
    final truncated = all.length > cap;
    final maxSeq = page.isEmpty
        ? 0
        : page.map((o) => o['seq'] as int).reduce((a, b) => a > b ? a : b);
    if (page.isNotEmpty) pullsWithOps++;
    return {
      'ops': page.map((o) => {
        'seq': o['seq'],
        'opId': o['opId'],
        'entity': o['entity'],
        'entityId': o['entityId'],
        'deviceId': o['deviceId'],
        'operation': o['operation'],
        'baseVersion': o['baseVersion'],
        'version': o['version'],
        'payload': o['payload'],
        'updatedAt': o['updatedAt'],
        'deletedAt': o['deletedAt'],
      }).toList(),
      'nextCursor': truncated ? maxSeq : 0,
      'truncated': truncated,
    };
  }

  static Map<String, dynamic> _error(String code, String message) => {
    'error': {'code': code, 'message': message},
  };

  static http.Response _json(int status, Map<String, dynamic> body) =>
      http.Response(jsonEncode(body), status, headers: {
        'content-type': 'application/json',
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late AppDatabase db;
  late FakeApiServer server;
  late TokenStore tokenStore;
  late OpSyncEngine engine;
  late SyncOutboxWriter writer;
  var now = DateTime.utc(2026, 8, 8, 12);

  setUp(() async {
    SyncSession.instance.userId = null;
    db = AppDatabase(NativeDatabase.memory());
    server = FakeApiServer();
    tokenStore = InMemoryTokenStore();
    await tokenStore.write(
      const AuthTokens(
        accessToken: 'access-token-1',
        refreshToken: 'refresh-token-1',
        expiresIn: 900,
        userId: 'user-1',
        email: 'ada@example.com',
      ),
    );
    final api = ApiClient(
      baseUrl: 'http://fake/v1',
      tokenStore: tokenStore,
      httpClient: server.client(),
      clock: () => now,
    );
    writer = SyncOutboxWriter(db: db, clock: () => now);
    writer.deviceId = 'device-1';
    engine = OpSyncEngine(
      db: db,
      api: api,
      devices: DeviceRegistry.instance,
      outboxWriter: writer,
      clock: () => now,
    );
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> insertAccount({
    required String id,
    required String name,
    String? userId,
    int version = 0,
  }) {
    final ts = now;
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
        version: Value(version),
      ),
    );
  }

  group('adoption', () {
    test('adopts local rows and pushes everything on first sync', () async {
      await insertAccount(id: 'acc-1', name: 'BDO');
      SyncSession.instance.userId = 'user-1';
      await engine.adoptLocalData('user-1');

      final result = await engine.sync();
      expect(result.ok, isTrue);

      expect(server.currentState.containsKey('account:acc-1'), isTrue);
      expect(server.currentState['account:acc-1']!['payload']!['name'], 'BDO');
      // Applied ops are removed from the outbox.
      expect(await (db.select(db.syncOutbox)).get(), isEmpty);
      // The row's version advanced to 1.
      final row = await (db.select(
        db.accounts,
      )..where((t) => t.id.equals('acc-1'))).getSingle();
      expect(row.version, 1);
    });

    test('does not push rows from a different user', () async {
      await insertAccount(id: 'acc-1', name: 'Mine', userId: 'user-1');
      await insertAccount(id: 'acc-2', name: 'Theirs', userId: 'user-2');
      SyncSession.instance.userId = 'user-1';
      await engine.adoptLocalData('user-1');
      await engine.sync();

      expect(server.currentState.containsKey('account:acc-1'), isTrue);
      expect(server.currentState.containsKey('account:acc-2'), isFalse);
    });
  });

  group('push & pull', () {
    test('pull applies rows created on another device', () async {
      SyncSession.instance.userId = 'user-1';
      await engine.adoptLocalData('user-1');
      await engine.sync();

      // Another device pushes an account through the fake server.
      final later = now.add(const Duration(hours: 1));
      server.currentState['account:acc-remote'] = {
        'opId': 'op-remote-1',
        'entity': 'account',
        'entityId': 'acc-remote',
        'deviceId': 'device-2',
        'operation': 'upsert',
        'baseVersion': 0,
        'version': 1,
        'payload': {
          'id': 'acc-remote',
          'name': 'GCash',
          'kind': 'account',
          'type': 'ewallet',
          'status': 'active',
          'opening_balance_minor': 0,
          'currency_code': 'PHP',
          'color_value': 0xFF000000,
          'sort_order': 0,
          'is_hidden': false,
          'created_at': later.toIso8601String(),
          'updated_at': later.toIso8601String(),
        },
        'updatedAt': later.toIso8601String(),
        'deletedAt': null,
      };
      server.ops.add({
        'opId': 'op-remote-1',
        'entity': 'account',
        'entityId': 'acc-remote',
        'deviceId': 'device-2',
        'operation': 'upsert',
        'baseVersion': 0,
        'version': 1,
        'payload': {
          'id': 'acc-remote',
          'name': 'GCash',
          'kind': 'account',
          'type': 'ewallet',
          'status': 'active',
          'opening_balance_minor': 0,
          'currency_code': 'PHP',
          'color_value': 0xFF000000,
          'sort_order': 0,
          'is_hidden': false,
          'created_at': later.toIso8601String(),
          'updated_at': later.toIso8601String(),
        },
        'updatedAt': later.toIso8601String(),
        'deletedAt': null,
        'seq': 100,
      });

      final result = await engine.sync();
      expect(result.ok, isTrue);

      final row = await (db.select(
        db.accounts,
      )..where((t) => t.id.equals('acc-remote'))).getSingleOrNull();
      expect(row, isNotNull);
      expect(row!.name, 'GCash');
      expect(row.userId, 'user-1');
    });

    test('a newer cloud edit is pulled over an older local copy', () async {
      await insertAccount(id: 'acc-1', name: 'BDO');
      SyncSession.instance.userId = 'user-1';
      await engine.adoptLocalData('user-1');
      await engine.sync();

      // Cloud has a NEWER edit.
      final later = now.add(const Duration(hours: 2));
      server.currentState['account:acc-1'] = {
        'opId': 'op-cloud-2',
        'entity': 'account',
        'entityId': 'acc-1',
        'deviceId': 'device-2',
        'operation': 'upsert',
        'baseVersion': 1,
        'version': 2,
        'payload': {
          'id': 'acc-1',
          'name': 'Renamed on cloud',
          'kind': 'account',
          'type': 'bank',
          'status': 'active',
          'opening_balance_minor': 0,
          'currency_code': 'PHP',
          'color_value': 0xFF000000,
          'sort_order': 0,
          'is_hidden': false,
          'created_at': now.toIso8601String(),
          'updated_at': later.toIso8601String(),
        },
        'updatedAt': later.toIso8601String(),
        'deletedAt': null,
      };
      server.ops.add({
        'opId': 'op-cloud-2',
        'entity': 'account',
        'entityId': 'acc-1',
        'deviceId': 'device-2',
        'operation': 'upsert',
        'baseVersion': 1,
        'version': 2,
        'payload': {
          'id': 'acc-1',
          'name': 'Renamed on cloud',
          'kind': 'account',
          'type': 'bank',
          'status': 'active',
          'opening_balance_minor': 0,
          'currency_code': 'PHP',
          'color_value': 0xFF000000,
          'sort_order': 0,
          'is_hidden': false,
          'created_at': now.toIso8601String(),
          'updated_at': later.toIso8601String(),
        },
        'updatedAt': later.toIso8601String(),
        'deletedAt': null,
        'seq': 200,
      });

      await engine.sync();

      final localRow = await (db.select(
        db.accounts,
      )..where((t) => t.id.equals('acc-1'))).getSingle();
      expect(localRow.name, 'Renamed on cloud');
    });

    test('a local edit made while offline is pushed on the next sync',
        () async {
      await insertAccount(id: 'acc-1', name: 'BDO');
      SyncSession.instance.userId = 'user-1';
      await engine.adoptLocalData('user-1');
      await engine.sync();

      // Edit locally (writes an outbox op via the writer).
      SyncSession.instance.userId = 'user-1';
      final row = await (db.select(
        db.accounts,
      )..where((t) => t.id.equals('acc-1'))).getSingle();
      await db.transaction(() async {
        await (db.update(db.accounts)..where((t) => t.id.equals('acc-1')))
            .write(AccountsCompanion(name: Value('BDO Plus')));
        await writer.enqueueUpsert(
          entity: 'account',
          entityId: 'acc-1',
          payload: {'id': 'acc-1', 'name': 'BDO Plus'},
          baseVersion: row.version,
        );
      });

      await engine.sync();
      expect(server.currentState['account:acc-1']!['payload']!['name'], 'BDO Plus');
    });
  });

  group('deletes', () {
    test('a local delete propagates to the cloud and other devices',
        () async {
      await insertAccount(id: 'acc-1', name: 'BDO', userId: 'user-1');
      SyncSession.instance.userId = 'user-1';
      await engine.adoptLocalData('user-1');
      await engine.sync();

      // Delete locally — the v5 trigger enqueues a delete op.
      await (db.delete(db.accounts)..where((t) => t.id.equals('acc-1'))).go();

      await engine.sync();
      final state = server.currentState['account:acc-1'];
      expect(state, isNotNull);
      expect(state!['operation'], 'delete');

      // A second device pulls the deletion and hard-deletes locally.
      final db2 = AppDatabase(NativeDatabase.memory());
      final server2 = FakeApiServer()
        ..ops.addAll([for (final o in server.ops) Map.of(o)]);
      SyncSession.instance.userId = 'user-1';
      final writer2 = SyncOutboxWriter(db: db2, clock: () => now);
      final api2 = ApiClient(
        baseUrl: 'http://fake/v1',
        tokenStore: tokenStore,
        httpClient: server2.client(),
        clock: () => now,
      );
      final engine2 = OpSyncEngine(
        db: db2,
        api: api2,
        devices: DeviceRegistry.instance,
        outboxWriter: writer2,
        clock: () => now,
      );
      await engine2.adoptLocalData('user-1');
      await engine2.sync();

      final row = await (db2.select(
        db2.accounts,
      )..where((t) => t.id.equals('acc-1'))).getSingleOrNull();
      expect(row, isNull);
      // The pulled delete must NOT re-enqueue itself into the outbox.
      expect(await (db2.select(db2.syncOutbox)).get(), isEmpty);
      await db2.close();
    });
  });

  group('pull pagination', () {
    test('the cursor advances past the final page and the tail is not re-fetched',
        () async {
      SyncSession.instance.userId = 'user-1';

      // Seed 5 remote ops; page size 2 → three pages, the last one signalling
      // `nextCursor: 0` (the "caught up" sentinel).
      final ts = now;
      for (var i = 0; i < 5; i++) {
        final id = 'acc-page-$i';
        server.ops.add({
          'opId': 'op-page-$i',
          'entity': 'account',
          'entityId': id,
          'deviceId': 'device-2',
          'operation': 'upsert',
          'baseVersion': 0,
          'version': 1,
          'payload': {
            'id': id,
            'name': 'Paged account $i',
            'kind': 'account',
            'type': 'bank',
            'status': 'active',
            'opening_balance_minor': 0,
            'currency_code': 'PHP',
            'color_value': 0xFF000000,
            'sort_order': 0,
            'is_hidden': false,
            'created_at': ts.toIso8601String(),
            'updated_at': ts.toIso8601String(),
          },
          'updatedAt': ts.toIso8601String(),
          'deletedAt': null,
          'seq': 100 + i,
        });
      }
      server.pullPageSize = 2;

      final result = await engine.sync();
      expect(result.ok, isTrue);

      // Every page was fetched once (3 pages of 2/2/1).
      expect(server.pullsWithOps, 3);
      // All 5 rows landed.
      for (var i = 0; i < 5; i++) {
        final row = await (db.select(
          db.accounts,
        )..where((t) => t.id.equals('acc-page-$i'))).getSingleOrNull();
        expect(row, isNotNull, reason: 'acc-page-$i must be applied');
      }
      // The persisted cursor is past the final page (max applied seq), not
      // stuck at the last page boundary — so a second sync does NOT re-fetch
      // the tail page.
      final meta = await (db.select(db.syncMeta)).getSingle();
      expect(meta.pullCursor, 104);

      final pullsBefore = server.pullsWithOps;
      await engine.sync();
      expect(server.pullsWithOps, pullsBefore,
          reason: 'a caught-up sync must not re-pull the tail page');
    });
  });

  group('conflicts', () {
    test('a losing LWW edit is dropped (server state wins)', () async {
      await insertAccount(id: 'acc-1', name: 'BDO');
      SyncSession.instance.userId = 'user-1';
      await engine.adoptLocalData('user-1');
      await engine.sync();

      // Simulate: another device pushed version 2 (newer updatedAt) and our
      // local edit (version 2, older timestamp) loses LWW at push time.
      final cloudLater = now.add(const Duration(hours: 1));
      server.currentState['account:acc-1'] = {
        'opId': 'op-cloud-2',
        'entity': 'account',
        'entityId': 'acc-1',
        'deviceId': 'device-2',
        'operation': 'upsert',
        'baseVersion': 1,
        'version': 2,
        'payload': {
          'id': 'acc-1',
          'name': 'Cloud won',
          'kind': 'account',
          'type': 'bank',
          'status': 'active',
          'opening_balance_minor': 0,
          'currency_code': 'PHP',
          'color_value': 0xFF000000,
          'sort_order': 0,
          'is_hidden': false,
          'version': 2,
          'created_at': now.toIso8601String(),
          'updated_at': cloudLater.toIso8601String(),
        },
        'updatedAt': cloudLater.toIso8601String(),
        'deletedAt': null,
      };
      server.ops.add({
        'opId': 'op-cloud-2',
        'entity': 'account',
        'entityId': 'acc-1',
        'deviceId': 'device-2',
        'operation': 'upsert',
        'baseVersion': 1,
        'version': 2,
        'payload': {
          'id': 'acc-1',
          'name': 'Cloud won',
          'kind': 'account',
          'type': 'bank',
          'status': 'active',
          'opening_balance_minor': 0,
          'currency_code': 'PHP',
          'color_value': 0xFF000000,
          'sort_order': 0,
          'is_hidden': false,
          'version': 2,
          'created_at': now.toIso8601String(),
          'updated_at': cloudLater.toIso8601String(),
        },
        'updatedAt': cloudLater.toIso8601String(),
        'deletedAt': null,
        'seq': 300,
      });

      // Local stale edit at version 2 with an OLDER timestamp — push then
      // conflicts; the engine re-pulls (cloud v2 applied) and drops the op.
      // (The seeded cloud payload must carry `version` so the conflict
      // carries it, mirroring what a real client pushes.)
      final localRow = await (db.select(
        db.accounts,
      )..where((t) => t.id.equals('acc-1'))).getSingle();
      await db.transaction(() async {
        await (db.update(db.accounts)..where((t) => t.id.equals('acc-1')))
            .write(AccountsCompanion(name: Value('Local lost edit')));
        await writer.enqueueUpsert(
          entity: 'account',
          entityId: 'acc-1',
          payload: {'id': 'acc-1', 'name': 'Local lost edit'},
          baseVersion: localRow.version,
        );
      });

      final result = await engine.sync();
      // The engine surfaces "needs attention" OR silently converges; either
      // way the server state wins and the losing op leaves the outbox.
      expect(
        (await (db.select(db.accounts)..where((t) => t.id.equals('acc-1')))
                .getSingle())
            .name,
        'Cloud won',
      );
      expect(await (db.select(db.syncOutbox)).get(), isEmpty);
      expect(result.ok, isTrue);
    });

    test('a CAS-stale op that would win LWW is rebased and retried', () async {
      await insertAccount(id: 'acc-1', name: 'BDO');
      SyncSession.instance.userId = 'user-1';
      await engine.adoptLocalData('user-1');
      await engine.sync();

      // Server current is at version 2, while our local row claims version 4
      // (two offline edits) — the push is CAS-stale (base 3 > stored 2) even
      // though LWW would pick us (version 4 > 2). The engine must re-anchor
      // on the server's version (base 2, version 3) and retry.
      final cloudCurrent = {
        'id': 'acc-1',
        'name': 'Cloud v2',
        'kind': 'account',
        'type': 'bank',
        'status': 'active',
        'opening_balance_minor': 0,
        'currency_code': 'PHP',
        'color_value': 0xFF000000,
        'sort_order': 0,
        'is_hidden': false,
        'version': 2,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      };
      server.currentState['account:acc-1'] = {
        'opId': 'op-cloud-2',
        'entity': 'account',
        'entityId': 'acc-1',
        'deviceId': 'device-2',
        'operation': 'upsert',
        'baseVersion': 1,
        'version': 2,
        'payload': cloudCurrent,
        'updatedAt': now.toIso8601String(),
        'deletedAt': null,
      };

      await db.transaction(() async {
        await (db.update(db.accounts)..where((t) => t.id.equals('acc-1')))
            .write(AccountsCompanion(name: Value('My rebased edit')));
        await writer.enqueueUpsert(
          entity: 'account',
          entityId: 'acc-1',
          payload: {'id': 'acc-1', 'name': 'My rebased edit'},
          baseVersion: 3,
        );
      });

      final result = await engine.sync();
      expect(result.ok, isTrue);
      // The rebased op was retried and applied — the server now holds v3.
      expect(server.currentState['account:acc-1']!['version'], 3);
      expect(await (db.select(db.syncOutbox)).get(), isEmpty);
    });

    test('a CAS-stale op for an entity the server never saw re-anchors on base 0',
        () async {
      SyncSession.instance.userId = 'user-1';

      // A row created AND edited while fully offline: local version is 3 but
      // the server has never seen the entity, so the push (base 3) is
      // CAS-stale against the implicit version 0 with `current: null`. The
      // engine must re-anchor on base 0 / version 1 (a clean create) instead
      // of re-anchoring on the stale base and looping.
      await insertAccount(id: 'acc-1', name: 'Offline row', userId: 'user-1');
      await db.transaction(() async {
        await (db.update(db.accounts)..where((t) => t.id.equals('acc-1')))
            .write(AccountsCompanion(name: Value('Offline edit')));
        await writer.enqueueUpsert(
          entity: 'account',
          entityId: 'acc-1',
          payload: {'id': 'acc-1', 'name': 'Offline edit'},
          baseVersion: 3,
        );
      });
      // Note: server.currentState has NO entry for acc-1 (server never saw it).

      final result = await engine.sync();
      expect(result.ok, isTrue);
      // The retried op landed as a clean create (base 0 → version 1).
      expect(server.currentState['account:acc-1']!['version'], 1);
      expect(server.currentState['account:acc-1']!['payload']!['name'], 'Offline edit');
      // The losing op left the outbox.
      expect(await (db.select(db.syncOutbox)).get(), isEmpty);
      // The local row's CAS counter was re-synced to the accepted version so
      // the next edit does NOT conflict again.
      final synced = await (db.select(
        db.accounts,
      )..where((t) => t.id.equals('acc-1'))).getSingle();
      expect(synced.version, 1);
    });

    test('a conflict that survives the rebase retry surfaces "needs attention" and stops looping',
        () async {
      await insertAccount(id: 'acc-1', name: 'BDO');
      SyncSession.instance.userId = 'user-1';
      await engine.adoptLocalData('user-1');
      await engine.sync();

      // Local edit based on version 1.
      await db.transaction(() async {
        await (db.update(db.accounts)..where((t) => t.id.equals('acc-1')))
            .write(AccountsCompanion(name: Value('Local racing edit')));
        await writer.enqueueUpsert(
          entity: 'account',
          entityId: 'acc-1',
          payload: {'id': 'acc-1', 'name': 'Local racing edit'},
          baseVersion: 1,
        );
      });

      // The server races us on EVERY push with a state that LWW loses to ours
      // (version 1, older timestamp) — the rebase re-anchors and retries, and
      // the retry conflicts too: the race genuinely never converges.
      final outboxRow = await (db.select(db.syncOutbox)).getSingle();
      final older = now.subtract(const Duration(hours: 1));
      server.forcedConflicts = [
        {
          'opId': outboxRow.opId,
          'current': {
            'id': 'acc-1',
            'name': 'Cloud stale',
            'kind': 'account',
            'type': 'bank',
            'status': 'active',
            'opening_balance_minor': 0,
            'currency_code': 'PHP',
            'color_value': 0xFF000000,
            'sort_order': 0,
            'is_hidden': false,
            'version': 1,
            'updated_at': older.toIso8601String(),
          },
        },
      ];

      final result = await engine.sync();
      // "needs attention" — the conflict survived the rebase retry.
      expect(result.ok, isTrue);
      expect(result.conflicts, isTrue);
      // The stale op was dropped, so the next sync does not loop forever.
      expect(await (db.select(db.syncOutbox)).get(), isEmpty);
    });
  });

  group('app_settings', () {
    test('security keys never get outbox ops', () async {
      SyncSession.instance.userId = 'user-1';
      // The settings DAO path must skip security.* keys (the writer itself
      // enqueues whatever it is told — the DAO is the guard).
      await db.settingsDao.set('security.pinHash', 'deadbeef');
      await db.settingsDao.set('settings.themeMode', 'dark');
      final ops = await (db.select(db.syncOutbox)).get();
      expect(ops.where((o) => o.entityId == 'security.pinHash'), isEmpty);
      expect(
        ops.where((o) => o.entityId == 'settings.themeMode'),
        hasLength(1),
      );
    });
  });
}

/// In-memory token store for tests (no platform channels).
class InMemoryTokenStore implements TokenStore {
  AuthTokens? _tokens;

  @override
  Future<AuthTokens?> read() async => _tokens;

  @override
  Future<void> write(AuthTokens tokens) async => _tokens = tokens;

  @override
  Future<void> clear() async => _tokens = null;
}
