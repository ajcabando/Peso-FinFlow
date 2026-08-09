import 'dart:convert';

// ignore_for_file: prefer_initializing_formals

import 'package:drift/drift.dart';

import '../../../../core/sync_session.dart';
import '../../../../core/utils/id_generator.dart';
import '../../../../database/app_database.dart';
import '../../../accounts/domain/enums/account_kind.dart';
import '../../../accounts/domain/enums/account_status.dart';
import '../../../accounts/domain/enums/account_type.dart';
import '../../../transactions/domain/enums/ledger_direction.dart';
import '../../../transactions/domain/enums/transaction_type.dart';
import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../sync/device_registry.dart';
import 'op_conflict_resolver.dart';
import 'sync_outbox_writer.dart';
import 'sync_payloads.dart';

/// Outcome of one sync cycle.
class SyncResult {
  const SyncResult({
    this.ok = true,
    this.error,
    this.conflicts = false,
  });

  const SyncResult.busy()
    : this(ok: false, error: 'Sync already in progress.');

  const SyncResult.failure(String message, {bool conflicts = false})
    : this(ok: false, error: message, conflicts: conflicts);

  const SyncResult.success({bool conflicts = false})
    : this(ok: true, conflicts: conflicts);

  final bool ok;

  /// Human-readable failure (network, server, or "needs attention").
  final String? error;

  /// True when a conflict survived the rebase retry — the UI surfaces
  /// "needs attention" (rare; another device raced again).
  final bool conflicts;
}

/// The operation-log sync engine (docs/SELF_HOSTED.md §6, BACKEND_API.md §4).
///
/// Local DB is authoritative; `sync_outbox` is the single write queue. Each
/// cycle:
///
///  1. **Flush**: read pending outbox ops oldest-first, push in batches of
///     ≤ 500, delete acked ops, advance `push_cursor` to the max acked seq.
///  2. **Conflicts**: re-pull (applies the server's winning state), then for
///     each conflicted op either drop it (server state wins LWW) or re-anchor
///     it on `current.version` and re-push once. Persistent conflicts surface
///     "needs attention".
///  3. **Pull**: apply ops newer than `pull_cursor` in one local transaction
///     (upsert replaces rows + transaction children; delete hard-deletes,
///     re-pointing `user_id` first so the tombstone trigger cannot loop).
class OpSyncEngine {
  OpSyncEngine({
    required AppDatabase db,
    required ApiClient api,
    required DeviceRegistry devices,
    required SyncOutboxWriter outboxWriter,
    DateTime Function()? clock,
  }) : _db = db,
       _api = api,
       _devices = devices,
       _outbox = outboxWriter,
       _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final ApiClient _api;
  final DeviceRegistry _devices;
  final SyncOutboxWriter _outbox;
  final DateTime Function() _clock;

  static const int _maxBatch = 500;
  static const int _pullLimit = 1000;

  bool _syncing = false;
  bool get isSyncing => _syncing;

  String? get _userId => SyncSession.instance.userId;

  /// Adopts all local-only rows into [userId]'s account, creates the cursor
  /// row, and enqueues an initial upsert op (baseVersion 0, version 1) for
  /// every row that has never been versioned (v4 installs / fresh data).
  /// Idempotent — rows already adopted/versioned are left untouched.
  Future<void> adoptLocalData(String userId) async {
    await _db.transaction(() async {
      await (_db.update(_db.accounts)..where((t) => t.userId.isNull())).write(
        AccountsCompanion(userId: Value(userId)),
      );
      await (_db.update(_db.transactions)..where((t) => t.userId.isNull()))
          .write(TransactionsCompanion(userId: Value(userId)));
      await (_db.update(_db.bills)..where((t) => t.userId.isNull())).write(
        BillsCompanion(userId: Value(userId)),
      );
      await (_db.update(_db.budgets)..where((t) => t.userId.isNull())).write(
        BudgetsCompanion(userId: Value(userId)),
      );
      await (_db.update(_db.tags)..where((t) => t.userId.isNull())).write(
        TagsCompanion(userId: Value(userId)),
      );
      // Non-secret settings only — security.* keys never leave the device.
      await (_db.update(
        _db.appSettings,
      )..where((t) => t.userId.isNull() & t.key.like('security.%').not()))
          .write(AppSettingsCompanion(userId: Value(userId)));
    });

    // Enqueue the initial full push (version 0 rows only).
    await _enqueueInitialRows();

    final cursor = await _cursor(userId);
    if (cursor == null) {
      await _db.into(_db.syncMeta).insert(
        SyncMetaCompanion.insert(userId: userId),
      );
    }
  }

  /// Enqueues an upsert op for every row still at version 0 (never synced)
  /// and bumps those rows to version 1. Runs outside the adopt transaction so
  /// version reads see the stamped userIds.
  Future<void> _enqueueInitialRows() async {
    final userId = _userId;
    if (userId == null) return;

    final accounts = await (_db.select(
      _db.accounts,
    )..where((t) => t.userId.equals(userId) & t.version.equals(0))).get();
    for (final row in accounts) {
      await _enqueueAndBump('account', row.id, SyncPayloads.account(row));
    }

    final tags = await (_db.select(
      _db.tags,
    )..where((t) => t.userId.equals(userId) & t.version.equals(0))).get();
    for (final row in tags) {
      await _enqueueAndBump('tag', row.id, SyncPayloads.tag(row));
    }

    final transactions = await (_db.select(
      _db.transactions,
    )..where((t) => t.userId.equals(userId) & t.version.equals(0))).get();
    for (final row in transactions) {
      final entries = await (_db.select(
        _db.ledgerEntries,
      )..where((t) => t.transactionId.equals(row.id))).get();
      final tagLinks = await (_db.select(
        _db.transactionTags,
      )..where((t) => t.transactionId.equals(row.id))).get();
      await _enqueueAndBump(
        'transaction',
        row.id,
        SyncPayloads.transaction(row: row, entries: entries, tagLinks: tagLinks),
      );
    }

    final bills = await (_db.select(
      _db.bills,
    )..where((t) => t.userId.equals(userId) & t.version.equals(0))).get();
    for (final row in bills) {
      await _enqueueAndBump('bill', row.id, SyncPayloads.bill(row));
    }

    final budgets = await (_db.select(
      _db.budgets,
    )..where((t) => t.userId.equals(userId) & t.version.equals(0))).get();
    for (final row in budgets) {
      await _enqueueAndBump('budget', row.id, SyncPayloads.budget(row));
    }

    final settings = await (_db.select(
      _db.appSettings,
    )..where(
      (t) =>
          t.userId.equals(userId) &
          t.version.equals(0) &
          t.key.like('security.%').not(),
    )).get();
    for (final row in settings) {
      await _enqueueAndBump('app_setting', row.key, SyncPayloads.appSetting(row));
    }
  }

  Future<void> _enqueueAndBump(
    String entity,
    String entityId,
    Map<String, dynamic> payload,
  ) async {
    final version = await _outbox.enqueueUpsert(
      entity: entity,
      entityId: entityId,
      payload: payload,
    );
    if (version <= 0) return;
    await _bumpRowVersion(entity, entityId, version);
  }

  /// Runs a full push + pull cycle. Safe to call concurrently (busy-guarded).
  Future<SyncResult> sync() async {
    if (_syncing) return const SyncResult.busy();
    final userId = _userId;
    if (userId == null) {
      return const SyncResult.failure('Not signed in.');
    }
    _syncing = true;
    try {
      _outbox.deviceId = await _devices.deviceId();

      // 1. Flush the outbox (push).
      final outcome = await _flushOutbox();

      // 2. On conflicts: re-pull the winning state, rebase, retry once.
      if (outcome.conflicts.isNotEmpty) {
        await _pull(userId);
        final retry = await _rebaseConflicts(outcome);
        if (retry.isNotEmpty) {
          final retryOutcome = await _flushOutbox(only: retry);
          // Conflicts that survive the retry are genuinely persistent: the
          // server state is the LWW winner (already applied by the pull), so
          // drop the stale ops to stop the retry loop, then surface
          // "needs attention" so the user knows their edit was superseded.
          outcome.persistent.addAll(retryOutcome.conflicts);
          for (final opId in retryOutcome.conflicts) {
            await (_db.delete(
              _db.syncOutbox,
            )..where((t) => t.opId.equals(opId))).go();
          }
        }
        // else: every conflict was resolved by dropping the losing op (the
        // server state won LWW and was applied by the pull) — nothing
        // persistent, no "needs attention".
      }

      // 3. Pull everything past our cursor (loop until caught up).
      await _pull(userId);

      if (outcome.persistent.isNotEmpty) {
        return SyncResult.success(conflicts: true);
      }
      return const SyncResult.success();
    } on ApiException catch (e) {
      return SyncResult.failure(e.message);
    } finally {
      _syncing = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Push
  // ---------------------------------------------------------------------------

  Future<_PushOutcome> _flushOutbox({Set<String>? only}) async {
    final outcome = _PushOutcome();
    final query = _db.select(_db.syncOutbox)
      ..orderBy([(t) => OrderingTerm.asc(t.id)]);
    final rows = (await query.get()).where((r) => only == null || only.contains(r.opId)).toList();
    if (rows.isEmpty) return outcome;

    for (var i = 0; i < rows.length; i += _maxBatch) {
      final end = (i + _maxBatch) > rows.length ? rows.length : i + _maxBatch;
      final batch = rows.sublist(i, end);
      final ops = [for (final row in batch) await _wireOp(row)];

      final response = await _api.post('/sync/push', body: {'ops': ops});
      final applied = _asList(response['applied']);
      final conflicts = _asList(response['conflicts']);

      // Ack: delete pushed ops, track the max acked seq for push_cursor.
      var maxSeq = -1;
      for (final entry in applied) {
        final opId = entry['opId'];
        if (opId is! String) continue;
        final seq = entry['seq'];
        if (seq is int && seq > maxSeq) maxSeq = seq;
        await (_db.delete(
          _db.syncOutbox,
        )..where((t) => t.opId.equals(opId))).go();
      }
      if (maxSeq >= 0) {
        final userId = _userId;
        if (userId != null) {
          await _advancePushCursor(userId, maxSeq);
        }
      }

      // Conflicts carry the server's current state for rebasing.
      for (final conflict in conflicts) {
        if (conflict is! Map<String, dynamic>) continue;
        final opId = conflict['opId'];
        if (opId is! String) continue;
        final current = conflict['current'];
        if (current is Map<String, dynamic>) {
          outcome.currentByOp[opId] = current;
        } else {
          outcome.currentByOp[opId] = const {};
        }
        outcome.conflicts.add(opId);
      }
    }
    return outcome;
  }

  /// Builds the wire envelope from an outbox row.
  Future<Map<String, dynamic>> _wireOp(SyncOutboxRow row) async {
    return {
      'opId': row.opId,
      'entity': row.entity,
      'entityId': row.entityId,
      'deviceId': row.deviceId ?? await _devices.deviceId(),
      'operation': row.operation,
      'baseVersion': row.baseVersion,
      'version': row.version,
      'payload': row.payload == null
          ? null
          : jsonDecode(row.payload!) as Map<String, dynamic>,
      'updatedAt': row.updatedAt.toUtc().toIso8601String(),
      'deletedAt': row.deletedAt?.toUtc().toIso8601String(),
    };
  }

  /// For each conflicted op: if the server's current state wins LWW, drop the
  /// losing op; if our edit wins, re-anchor it on `current.version` and keep
  /// it for the retry push. Returns the opIds to retry.
  Future<Set<String>> _rebaseConflicts(_PushOutcome outcome) async {
    final retry = <String>{};
    for (final opId in outcome.conflicts) {
      final row = await (_db.select(
        _db.syncOutbox,
      )..where((t) => t.opId.equals(opId))).getSingleOrNull();
      if (row == null) continue;

      final current = outcome.currentByOp[opId] ?? const {};
      if (current.isEmpty) {
        // The server has NO state for this entity — a CAS conflict against a
        // fresh row the server never saw (e.g. a row created and edited while
        // fully offline). Re-anchor on base 0 / version 1 so the retry lands
        // as a clean create; re-anchoring on the stale base would conflict
        // forever.
        final payload = row.payload == null
            ? null
            : _rebasedPayload(
                jsonDecode(row.payload!) as Map<String, dynamic>,
                1,
              );
        await (_db.update(
          _db.syncOutbox,
        )..where((t) => t.opId.equals(opId))).write(
          SyncOutboxCompanion(
            baseVersion: const Value(0),
            version: const Value(1),
            payload: Value(payload == null ? null : jsonEncode(payload)),
          ),
        );
        // Keep the local CAS counter in lockstep with the re-anchored op, or
        // the next edit bases on a stale version and conflicts forever.
        await _bumpRowVersion(row.entity, row.entityId, 1);
        retry.add(opId);
        continue;
      }
      final currentVersion = (current['version'] as num?)?.toInt() ?? 0;
      final currentUpdatedAt = DateTime.tryParse(
        (current['updated_at'] as String?) ?? '',
      );

      final ours = LwwCandidate(
        version: row.version,
        updatedAt: row.updatedAt,
        opId: row.opId,
      );
      final theirs = LwwCandidate(
        version: currentVersion,
        updatedAt: currentUpdatedAt ?? row.updatedAt,
        opId: opId,
      );
      if (lwwWinner(theirs, ours) != LwwWinner.incoming) {
        // Server state wins — our edit is superseded; drop the losing op.
        await (_db.delete(
          _db.syncOutbox,
        )..where((t) => t.opId.equals(opId))).go();
        continue;
      }

      // Our edit wins: re-anchor on the server's current version.
      final newVersion = currentVersion + 1;
      final payload = row.payload == null
          ? null
          : _rebasedPayload(
              jsonDecode(row.payload!) as Map<String, dynamic>,
              newVersion,
            );
      await (_db.update(
        _db.syncOutbox,
      )..where((t) => t.opId.equals(opId))).write(
        SyncOutboxCompanion(
          baseVersion: Value(currentVersion),
          version: Value(newVersion),
          payload: Value(payload == null ? null : jsonEncode(payload)),
        ),
      );
      // Keep the local CAS counter in lockstep with the re-anchored op: the
      // local row was stamped with the ORIGINAL version at write time, but the
      // server will accept `newVersion` — leaving the row ahead means every
      // subsequent edit bases on a stale version and conflicts once, forever.
      await _bumpRowVersion(row.entity, row.entityId, newVersion);
      retry.add(opId);
    }
    return retry;
  }

  Map<String, dynamic>? _rebasedPayload(
    Map<String, dynamic> payload,
    int version,
  ) {
    return {
      ...payload,
      'version': version,
    };
  }

  // ---------------------------------------------------------------------------
  // Pull
  // ---------------------------------------------------------------------------

  Future<void> _pull(String userId) async {
    final cursorRow = await _cursor(userId);
    var cursor = cursorRow?.pullCursor ?? 0;
    var guard = 0;
    while (true) {
      if (guard++ > 200) break; // safety net against an endless page loop
      final response = await _api.get(
        '/sync/pull',
        query: {'cursor': '$cursor', 'limit': '$_pullLimit'},
      );
      final ops = _asList(response['ops']);
      final nextCursor = response['nextCursor'] is int
          ? response['nextCursor'] as int
          : 0;
      if (ops.isNotEmpty) {
        await _applyOps(ops, userId);
      }
      // The server signals "caught up" with `nextCursor: 0` on the final
      // (non-truncated) page, but the client must still persist a cursor past
      // the ops it just applied — otherwise the tail page is re-fetched on
      // every sync. Pulled ops carry their immutable `seq` (docs §4), so the
      // max applied seq is the authoritative position.
      var maxAppliedSeq = cursor;
      for (final raw in ops) {
        if (raw is Map && raw['seq'] is int) {
          final seq = raw['seq'] as int;
          if (seq > maxAppliedSeq) maxAppliedSeq = seq;
        }
      }
      final effective = maxAppliedSeq > nextCursor ? maxAppliedSeq : nextCursor;
      await _upsertCursor(userId, pullCursor: effective);
      if (nextCursor == 0 || ops.isEmpty) break;
      cursor = nextCursor;
    }
  }

  /// Applies pulled ops locally in one transaction. LWW guard: a pulled op
  /// that is not strictly newer than the local row (by version, then
  /// updated_at) is skipped — the local edit is newer and the push already
  /// resolved it.
  Future<void> _applyOps(List<dynamic> ops, String userId) async {
    await _db.transaction(() async {
      for (final raw in ops) {
        if (raw is! Map<String, dynamic>) continue;
        final entity = raw['entity'];
        final entityId = raw['entityId'];
        final operation = raw['operation'];
        if (entity is! String || entityId is! String || operation is! String) {
          continue;
        }
        final version = raw['version'] is int ? raw['version'] as int : 0;
        final updatedAt = DateTime.tryParse(
          (raw['updatedAt'] as String?) ?? '',
        );

        final local = await _localVersion(entity, entityId);
        if (local != null) {
          if (local.version > version) continue;
          if (local.version == version &&
              local.updatedAt != null &&
              updatedAt != null &&
              !local.updatedAt!.isBefore(updatedAt)) {
            continue;
          }
        }

        if (operation == 'delete') {
          await _deleteLocalRow(entity, entityId);
        } else {
          final payload = raw['payload'];
          if (payload is Map<String, dynamic>) {
            await _applyUpsert(entity, entityId, payload, userId, version);
          }
        }
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Local apply helpers
  // ---------------------------------------------------------------------------

  Future<({int version, DateTime? updatedAt})?> _localVersion(
    String entity,
    String entityId,
  ) async {
    final int? version;
    final DateTime? updatedAt;
    switch (entity) {
      case 'account':
        final row = await _db.accountDao.getById(entityId);
        version = row?.version;
        updatedAt = row?.updatedAt;
      case 'transaction':
        final row = await _db.transactionDao.getById(entityId);
        version = row?.version;
        updatedAt = row?.updatedAt;
      case 'bill':
        final row = await _db.billDao.getById(entityId);
        version = row?.version;
        updatedAt = row?.updatedAt;
      case 'budget':
        final row = await _db.budgetDao.getById(entityId);
        version = row?.version;
        updatedAt = row?.updatedAt;
      case 'tag':
        final row = await (_db.select(
          _db.tags,
        )..where((t) => t.id.equals(entityId))).getSingleOrNull();
        version = row?.version;
        updatedAt = row?.updatedAt;
      case 'app_setting':
        final row = await (_db.select(
          _db.appSettings,
        )..where((t) => t.key.equals(entityId))).getSingleOrNull();
        version = row?.version;
        updatedAt = row?.updatedAt;
      default:
        return null;
    }
    if (version == null) return null;
    return (version: version, updatedAt: updatedAt);
  }

  Future<void> _deleteLocalRow(String entity, String entityId) async {
    // Re-point user_id to NULL first so the AFTER DELETE trigger's
    // `WHEN OLD.user_id IS NOT NULL` guard skips it — a pulled delete must
    // not re-queue itself into the outbox (no loops).
    switch (entity) {
      case 'account':
        await (_db.update(
          _db.accounts,
        )..where((t) => t.id.equals(entityId))).write(
          AccountsCompanion(userId: const Value(null)),
        );
        await (_db.delete(
          _db.accounts,
        )..where((t) => t.id.equals(entityId))).go();
      case 'transaction':
        await (_db.update(
          _db.transactions,
        )..where((t) => t.id.equals(entityId))).write(
          TransactionsCompanion(userId: const Value(null)),
        );
        await _db.transactionDao.deleteById(entityId);
      case 'bill':
        await (_db.update(
          _db.bills,
        )..where((t) => t.id.equals(entityId))).write(
          BillsCompanion(userId: const Value(null)),
        );
        await (_db.delete(
          _db.bills,
        )..where((t) => t.id.equals(entityId))).go();
      case 'budget':
        await (_db.update(
          _db.budgets,
        )..where((t) => t.id.equals(entityId))).write(
          BudgetsCompanion(userId: const Value(null)),
        );
        await (_db.delete(
          _db.budgets,
        )..where((t) => t.id.equals(entityId))).go();
      case 'tag':
        await (_db.update(
          _db.tags,
        )..where((t) => t.id.equals(entityId))).write(
          TagsCompanion(userId: const Value(null)),
        );
        await (_db.delete(
          _db.tags,
        )..where((t) => t.id.equals(entityId))).go();
      case 'app_setting':
        await (_db.update(
          _db.appSettings,
        )..where((t) => t.key.equals(entityId))).write(
          AppSettingsCompanion(userId: const Value(null)),
        );
        await (_db.delete(
          _db.appSettings,
        )..where((t) => t.key.equals(entityId))).go();
    }
  }

  Future<void> _applyUpsert(
    String entity,
    String entityId,
    Map<String, dynamic> payload,
    String userId,
    int version,
  ) async {
    final createdAt = _parseTs(payload['created_at']) ?? _clock();
    final updatedAt = _parseTs(payload['updated_at']) ?? _clock();
    switch (entity) {
      case 'account':
        await _db.into(_db.accounts).insertOnConflictUpdate(
          AccountsCompanion(
            id: Value(entityId),
            name: Value(payload['name'] as String),
            institution: Value(payload['institution'] as String?),
            kind: Value(AccountKind.values.byName(payload['kind'] as String)),
            type: Value(AccountType.values.byName(payload['type'] as String)),
            status: Value(
              AccountStatus.values.byName(payload['status'] as String),
            ),
            openingBalanceMinor: Value(payload['opening_balance_minor'] as int),
            currencyCode: Value(payload['currency_code'] as String),
            colorValue: Value(payload['color_value'] as int),
            iconCode: Value(payload['icon_code'] as String?),
            notes: Value(payload['notes'] as String?),
            sortOrder: Value(payload['sort_order'] as int),
            isHidden: Value(payload['is_hidden'] as bool),
            version: Value(version),
            createdAt: Value(createdAt),
            updatedAt: Value(updatedAt),
            userId: Value(userId),
          ),
        );
      case 'transaction':
        await _db.into(_db.transactions).insertOnConflictUpdate(
          TransactionsCompanion(
            id: Value(entityId),
            type: Value(TransactionType.values.byName(payload['type'] as String)),
            amountMinor: Value(payload['amount_minor'] as int),
            currencyCode: Value(payload['currency_code'] as String),
            occurredAt: Value(_parseTs(payload['occurred_at']) ?? createdAt),
            note: Value(payload['note'] as String?),
            merchant: Value(payload['merchant'] as String?),
            referenceNumber: Value(payload['reference_number'] as String?),
            location: Value(payload['location'] as String?),
            version: Value(version),
            createdAt: Value(createdAt),
            updatedAt: Value(updatedAt),
            userId: Value(userId),
          ),
        );
        await _replaceChildren(entityId, payload);
      case 'bill':
        await _db.into(_db.bills).insertOnConflictUpdate(
          BillsCompanion(
            id: Value(entityId),
            name: Value(payload['name'] as String),
            amountMinor: Value(payload['amount_minor'] as int),
            currencyCode: Value(payload['currency_code'] as String),
            accountId: Value(payload['account_id'] as String?),
            dueDayOfMonth: Value(payload['due_day_of_month'] as int),
            reminderDaysBefore: Value(payload['reminder_days_before'] as int),
            isActive: Value(payload['is_active'] as bool),
            lastPaidOn: Value(_parseTs(payload['last_paid_on'])),
            version: Value(version),
            createdAt: Value(createdAt),
            updatedAt: Value(updatedAt),
            userId: Value(userId),
          ),
        );
      case 'budget':
        await _db.into(_db.budgets).insertOnConflictUpdate(
          BudgetsCompanion(
            id: Value(entityId),
            categoryId: Value(payload['category_id'] as String),
            amountMinor: Value(payload['amount_minor'] as int),
            currencyCode: Value(payload['currency_code'] as String),
            version: Value(version),
            createdAt: Value(createdAt),
            updatedAt: Value(updatedAt),
            userId: Value(userId),
          ),
        );
      case 'tag':
        await _db.into(_db.tags).insertOnConflictUpdate(
          TagsCompanion(
            id: Value(entityId),
            name: Value(payload['name'] as String),
            colorValue: Value(payload['color_value'] as int?),
            version: Value(version),
            createdAt: Value(createdAt),
            updatedAt: Value(updatedAt),
            userId: Value(userId),
          ),
        );
      case 'app_setting':
        // security.* keys never leave the device — ignore defensively.
        if (entityId.startsWith('security.')) return;
        await _db.into(_db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion(
            key: Value(entityId),
            value: Value(payload['value'] as String),
            version: Value(version),
            updatedAt: Value(updatedAt),
            userId: Value(userId),
          ),
        );
    }
  }

  Future<void> _replaceChildren(
    String transactionId,
    Map<String, dynamic> payload,
  ) async {
    await (_db.delete(
      _db.ledgerEntries,
    )..where((t) => t.transactionId.equals(transactionId))).go();
    await (_db.delete(
      _db.transactionTags,
    )..where((t) => t.transactionId.equals(transactionId))).go();

    final entries = payload['ledgerEntries'];
    if (entries is List) {
      await _db.batch((b) {
        for (final raw in entries) {
          if (raw is! Map<String, dynamic>) continue;
          b.insert(
            _db.ledgerEntries,
            LedgerEntriesCompanion.insert(
              id: (raw['id'] as String?) ?? IdGenerator.next(),
              transactionId: transactionId,
              accountId: raw['account_id'] as String,
              direction: LedgerDirection.values.byName(
                raw['direction'] as String,
              ),
              amountMinor: raw['amount_minor'] as int,
              currencyCode: raw['currency_code'] as String,
            ),
          );
        }
      });
    }
    final tagLinks = payload['transactionTags'];
    if (tagLinks is List) {
      await _db.batch((b) {
        for (final raw in tagLinks) {
          if (raw is! Map<String, dynamic>) continue;
          final tagId = raw['tag_id'];
          if (tagId is! String) continue;
          b.insert(
            _db.transactionTags,
            TransactionTagsCompanion.insert(
              transactionId: transactionId,
              tagId: tagId,
            ),
          );
        }
      });
    }
  }

  Future<void> _bumpRowVersion(
    String entity,
    String entityId,
    int version,
  ) async {
    if (version <= 0) return;
    switch (entity) {
      case 'account':
        await (_db.update(
          _db.accounts,
        )..where((t) => t.id.equals(entityId))).write(
          AccountsCompanion(version: Value(version)),
        );
      case 'transaction':
        await (_db.update(
          _db.transactions,
        )..where((t) => t.id.equals(entityId))).write(
          TransactionsCompanion(version: Value(version)),
        );
      case 'bill':
        await (_db.update(
          _db.bills,
        )..where((t) => t.id.equals(entityId))).write(
          BillsCompanion(version: Value(version)),
        );
      case 'budget':
        await (_db.update(
          _db.budgets,
        )..where((t) => t.id.equals(entityId))).write(
          BudgetsCompanion(version: Value(version)),
        );
      case 'tag':
        await (_db.update(
          _db.tags,
        )..where((t) => t.id.equals(entityId))).write(
          TagsCompanion(version: Value(version)),
        );
      case 'app_setting':
        await (_db.update(
          _db.appSettings,
        )..where((t) => t.key.equals(entityId))).write(
          AppSettingsCompanion(version: Value(version)),
        );
    }
  }

  // ---------------------------------------------------------------------------
  // Cursors
  // ---------------------------------------------------------------------------

  Future<SyncMetaRow?> _cursor(String userId) => (_db.select(
    _db.syncMeta,
  )..where((t) => t.userId.equals(userId))).getSingleOrNull();

  Future<void> _advancePushCursor(String userId, int seq) async {
    final existing = await _cursor(userId);
    final next = existing == null || (existing.pushCursor ?? 0) < seq
        ? seq
        : existing.pushCursor;
    await _upsertCursor(userId, pushCursor: next);
  }

  Future<void> _upsertCursor(
    String userId, {
    int? pushCursor,
    int? pullCursor,
  }) async {
    final existing = await _cursor(userId);
    if (existing == null) {
      await _db.into(_db.syncMeta).insert(
        SyncMetaCompanion.insert(
          userId: userId,
          pushCursor: Value(pushCursor),
          pullCursor: Value(pullCursor),
        ),
      );
    } else {
      await (_db.update(
        _db.syncMeta,
      )..where((t) => t.userId.equals(userId))).write(
        SyncMetaCompanion(
          pushCursor: Value(pushCursor ?? existing.pushCursor),
          pullCursor: Value(pullCursor ?? existing.pullCursor),
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static List<dynamic> _asList(dynamic value) =>
      value is List ? value : const [];

  static DateTime? _parseTs(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value.toUtc();
    return DateTime.tryParse(value.toString())?.toUtc();
  }
}

/// Accumulates the outcome of one outbox flush + rebase attempt.
class _PushOutcome {
  final Set<String> conflicts = {};
  final Map<String, Map<String, dynamic>> currentByOp = {};
  final Set<String> persistent = {};
}
