import 'dart:convert';

// ignore_for_file: prefer_initializing_formals

import 'package:drift/drift.dart';

import '../../../../core/sync_session.dart';
import '../../../../core/utils/id_generator.dart';
import '../../../../database/app_database.dart';

/// Appends operation-log upsert ops to `sync_outbox` from inside repository
/// write transactions (docs/SELF_HOSTED.md §6-7).
///
/// Repositories call [enqueueUpsert] inside the SAME `db.transaction` that
/// writes the row, so a local write and its pending op are atomic — the UI
/// never waits for the network, and a crash can never produce a row without
/// its op. DELETE ops need no writer: the per-table `AFTER DELETE` triggers
/// enqueue them automatically.
///
/// `base_version`/`version` are computed from the row's current `version`
/// column (CAS); the returned version is what the caller stamps back on the
/// row so the next edit's base matches what the server saw.
class SyncOutboxWriter {
  SyncOutboxWriter({required AppDatabase db, DateTime Function()? clock})
    : _db = db,
      _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  /// The install's device id, stamped on every op (verified against the JWT
  /// claim server-side). Set by the sync engine before a flush.
  String? deviceId;

  /// True when a user is signed in — the only condition under which ops are
  /// written (local-only rows are adopted + enqueued on sign-in instead).
  bool get _signedIn => SyncSession.instance.signedIn;

  /// Appends an upsert op for [entity]/[entityId] with [payload] (the
  /// snake_case wire row; `version`/`updated_at` are normalised to match the
  /// op). Returns the new version for the caller to stamp on its row.
  ///
  /// [baseVersion] lets the caller pass the base it already read (the row's
  /// version BEFORE this write); when omitted it is read from the row. Must
  /// run inside the caller's `db.transaction` so op + row stay atomic.
  ///
  /// The row's `version` column is bumped to the op's version in the same
  /// call, so the next edit's base matches what the server saw.
  Future<int> enqueueUpsert({
    required String entity,
    required String entityId,
    required Map<String, dynamic> payload,
    int? baseVersion,
    DateTime? updatedAt,
  }) async {
    if (!_signedIn) return 0;
    final now = (updatedAt ?? _clock()).toUtc();
    final base = baseVersion ?? await _currentVersion(entity, entityId);
    final version = base + 1;
    final enriched = <String, dynamic>{
      ...payload,
      'version': version,
      'updated_at': _iso(now),
    };
    await _db.into(_db.syncOutbox).insert(
      SyncOutboxCompanion.insert(
        opId: IdGenerator.next(),
        entity: entity,
        entityId: entityId,
        deviceId: Value(deviceId),
        operation: 'upsert',
        baseVersion: base,
        version: version,
        payload: Value(jsonEncode(enriched)),
        updatedAt: now,
        createdAt: _clock(),
      ),
    );
    await _stampVersion(entity, entityId, version);
    return version;
  }

  /// Bumps the entity row's `version` column to [version] (keeps the local
  /// CAS base in lockstep with the ops actually enqueued).
  Future<void> _stampVersion(
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

  /// The row's current CAS version (0 for a never-synced / fresh row).
  Future<int> _currentVersion(String entity, String entityId) async {
    final int? version;
    switch (entity) {
      case 'account':
        version = (await _db.accountDao.getById(entityId))?.version;
      case 'transaction':
        version = (await _db.transactionDao.getById(entityId))?.version;
      case 'bill':
        version = (await _db.billDao.getById(entityId))?.version;
      case 'budget':
        version = (await _db.budgetDao.getById(entityId))?.version;
      case 'tag':
        version =
            (await (_db.select(
              _db.tags,
            )..where((t) => t.id.equals(entityId)))
                    .getSingleOrNull())
                ?.version;
      case 'app_setting':
        version =
            (await (_db.select(
              _db.appSettings,
            )..where((t) => t.key.equals(entityId)))
                    .getSingleOrNull())
                ?.version;
      default:
        version = 0;
    }
    return version ?? 0;
  }

  static String _iso(DateTime value) => value.toUtc().toIso8601String();
}
