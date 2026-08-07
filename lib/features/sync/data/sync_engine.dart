import 'package:drift/drift.dart';

import '../../../core/utils/id_generator.dart';
import '../../../database/app_database.dart';
import '../../../features/accounts/domain/enums/account_kind.dart';
import '../../../features/accounts/domain/enums/account_status.dart';
import '../../../features/accounts/domain/enums/account_type.dart';
import '../../../features/transactions/domain/enums/ledger_direction.dart';
import '../../../features/transactions/domain/enums/transaction_type.dart';
import 'sync_remote.dart';

/// Result of one full sync cycle.
class SyncResult {
  const SyncResult({required this.ok, this.iterations = 0, this.error});

  const SyncResult.busy() : this(ok: false, error: 'Sync already in progress.');

  const SyncResult.failure(String message) : this(ok: false, error: message);

  const SyncResult.success({int iterations = 0})
    : this(ok: true, iterations: iterations);

  final bool ok;
  final int iterations;
  final String? error;
}

/// Table names whose rows are synced, in dependency order (parents before
/// children, referenced rows before referencing rows) so pulled rows never
/// violate foreign keys.
const List<String> kSyncedTables = [
  'accounts',
  'tags',
  'transactions',
  'bills',
  'budgets',
  'app_settings',
];

/// `app_settings` keys that are device-local secrets and never leave the
/// device (e.g. the salted PIN hash).
const String kSettingsSecretPrefix = 'security.';

/// The offline-first sync engine.
///
/// The local database remains the source of truth the user interacts with;
/// the cloud is a converging mirror. Each cycle:
///
///  1. **Push** — rows changed locally since the last push (`updated_at` >
///     watermark) are uploaded, but only when the cloud copy is not newer
///     (last-write-wins). Deleted rows ride along as tombstones. A winning
///     transaction uploads its ledger entries + tags as a consistent set.
///  2. **Pull** — rows changed in the cloud since the last pull are applied
///     locally, again newest-wins; tombstones hard-delete local rows.
///  3. Repeats until a pass changes nothing (converged) or a cap is hit.
///
/// Known limitations (documented in `docs/SYNC.md`): last-write-wins means a
/// concurrent edit of the *same* row keeps the newest version wholesale; and
/// ordering uses client clocks, so devices with badly skewed clocks can
/// mis-order writes. Both are acceptable for a personal finance app.
class SyncEngine {
  SyncEngine({
    required AppDatabase db,
    required SyncRemote remote,
    DateTime Function()? clock,
  }) : this._(db, remote, clock ?? DateTime.now);

  SyncEngine._(this._db, this._remote, this._clock);

  final AppDatabase _db;
  final SyncRemote _remote;
  final DateTime Function() _clock;

  static const int _maxIterations = 5;
  static final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0);

  bool _syncing = false;
  bool get isSyncing => _syncing;

  /// Adopts all local-only rows into [userId]'s account and initialises the
  /// sync cursors. Safe to call repeatedly; idempotent.
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
      await (_db.update(
        _db.appSettings,
      )..where(
        (t) => t.userId.isNull() & t.key.like('$kSettingsSecretPrefix%').not(),
      )).write(AppSettingsCompanion(userId: Value(userId)));
    });

    final cursor = await _cursor(userId);
    if (cursor == null) {
      // First sign-in for this user: reset the watermarks so *everything*
      // local is pushed once and everything cloud is pulled once.
      await _db.into(_db.syncMeta).insert(
        SyncMetaCompanion.insert(userId: userId),
      );
    }
  }

  /// Runs a full push + pull cycle for [userId]. Safe to call concurrently —
  /// a second call while one is running returns a "busy" result.
  Future<SyncResult> sync(String userId) async {
    if (_syncing) return const SyncResult.busy();
    _syncing = true;
    try {
      var iterations = 0;
      var changed = false;
      do {
        changed = false;
        changed = await _push(userId) || changed;
        changed = await _pull(userId) || changed;
        iterations++;
      } while (changed && iterations < _maxIterations);
      return SyncResult.success(iterations: iterations);
    } on Exception catch (e) {
      return SyncResult.failure(e.toString());
    } finally {
      _syncing = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Push
  // ---------------------------------------------------------------------------

  Future<bool> _push(String userId) async {
    final cursor = await _cursor(userId);
    var pushed = false;

    for (final table in kSyncedTables) {
      // Legacy settings rows (v3 installs) have no `updated_at` — stamp them
      // now so the cloud delta query can see them and they stop re-pushing.
      if (table == 'app_settings') {
        await (_db.update(
          _db.appSettings,
        )..where(
          (t) => t.userId.equals(userId) & t.updatedAt.isNull(),
        )).write(AppSettingsCompanion(updatedAt: Value(_clock().toUtc())));
      }
      final rows = await _localChangedRows(table, userId, since: cursor?.lastPushAt);
      if (rows.isEmpty) continue;

      final winners = await _lwwWinners(table, rows);
      if (winners.isEmpty) continue;

      if (table == 'transactions') {
        for (final row in winners) {
          final children = await _localChildren(row['id'] as String);
          await _remote.replaceTransactionChildren(
            row['id'] as String,
            ledgerEntries: children.$1,
            transactionTags: children.$2,
          );
        }
      }
      await _remote.upsert(table, _toRemoteRows(table, winners), onConflict: _pkOf(table));
      pushed = true;
    }

    pushed = await _pushTombstones(userId, since: cursor?.lastPushAt) || pushed;

    final watermark = _clock().toUtc();
    await _setCursor(userId, lastPushAt: watermark);
    await _pruneTombstones(userId, watermark);
    return pushed;
  }

  /// Local rows of [table] owned by [userId] changed after [since].
  ///
  /// `>=` semantics (not strict `>`) so a row written at the exact same
  /// instant as the previous watermark is still picked up; the CAS compare in
  /// [_lwwWinners] makes any re-push a harmless no-op.
  Future<List<Map<String, dynamic>>> _localChangedRows(
    String table,
    String userId, {
    DateTime? since,
  }) async {
    final rows = await _localRowsForUser(table, userId);
    return [
      for (final row in rows)
        if (since == null ||
            row['updated_at'] == null ||
            !(row['updated_at'] as DateTime).isBefore(since))
          row,
    ];
  }

  Future<List<Map<String, dynamic>>> _localRowsForUser(
    String table,
    String userId,
  ) async {
    switch (table) {
      case 'accounts':
        final rows = await (_db.select(
          _db.accounts,
        )..where((t) => t.userId.equals(userId))).get();
        return rows.map(_accountRow).toList();
      case 'tags':
        final rows = await (_db.select(
          _db.tags,
        )..where((t) => t.userId.equals(userId))).get();
        return rows.map(_tagRow).toList();
      case 'transactions':
        final rows = await (_db.select(
          _db.transactions,
        )..where((t) => t.userId.equals(userId))).get();
        return rows.map(_transactionRow).toList();
      case 'bills':
        final rows = await (_db.select(
          _db.bills,
        )..where((t) => t.userId.equals(userId))).get();
        return rows.map(_billRow).toList();
      case 'budgets':
        final rows = await (_db.select(
          _db.budgets,
        )..where((t) => t.userId.equals(userId))).get();
        return rows.map(_budgetRow).toList();
      case 'app_settings':
        final rows = await (_db.select(
          _db.appSettings,
        )        ..where(
          (t) =>
              t.userId.equals(userId) &
              t.key.like('$kSettingsSecretPrefix%').not(),
        )).get();
        return rows.map(_settingRow).toList();
    }
    return const [];
  }

  /// Filters [rows] to those whose local `updated_at` is not older than the
  /// cloud copy (last-write-wins — never push a stale row over a newer one).
  Future<List<Map<String, dynamic>>> _lwwWinners(
    String table,
    List<Map<String, dynamic>> rows,
  ) async {
    final pk = _pkOf(table);
    final ids = [for (final row in rows) row[pk] as String];
    final serverTs = await _remote.fetchUpdatedAt(table, ids);
    return [
      for (final row in rows)
        if (() {
          final localTs = row['updated_at'] as DateTime?;
          final remoteTs = serverTs[row[pk]];
          if (remoteTs == null) return true;
          if (localTs == null) return false;
          return !localTs.isBefore(remoteTs);
        }())
          row,
    ];
  }

  Future<(List<Map<String, dynamic>>, List<Map<String, dynamic>>)>
  _localChildren(String transactionId) async {
    final entries = await (_db.select(
      _db.ledgerEntries,
    )..where((t) => t.transactionId.equals(transactionId))).get();
    final tags = await (_db.select(
      _db.transactionTags,
    )..where((t) => t.transactionId.equals(transactionId))).get();
    return (
      [for (final e in entries) _entryRow(e)],
      [for (final t in tags) _tagLinkRow(t)],
    );
  }

  Future<bool> _pushTombstones(
    String userId, {
    DateTime? since,
  }) async {
    var query = _db.select(_db.syncTombstones)
      ..where((t) => t.userId.equals(userId));
    final tombstones = await query.get();
    final changed = [
      for (final t in tombstones)
        if (since == null ||
            t.deletedAt == null ||
            !t.deletedAt!.isBefore(since))
          t,
    ];
    if (changed.isEmpty) return false;

    var pushed = false;
    for (final table in kSyncedTables) {
      final group = changed.where((t) => t.sourceTable == table).toList();
      if (group.isEmpty) continue;
      final ids = [for (final t in group) t.rowId];
      final serverTs = await _remote.fetchUpdatedAt(table, ids);
      final winners = [
        for (final t in group)
          if (serverTs[t.rowId] == null ||
              t.deletedAt == null ||
              !t.deletedAt!.isBefore(serverTs[t.rowId]!))
            t,
      ];
      if (winners.isEmpty) continue;
      final pk = _pkOf(table);
      await _remote.upsert(
        table,
        [
          for (final t in winners)
            {
              pk: t.rowId,
              'deleted_at': _iso(t.deletedAt ?? _clock()),
              'updated_at': _iso(t.deletedAt ?? _clock()),
            },
        ],
        onConflict: pk,
      );
      pushed = true;
    }
    return pushed;
  }

  Future<void> _pruneTombstones(String userId, DateTime watermark) async {
    await (_db.delete(
      _db.syncTombstones,
    )..where(
      (t) => t.userId.equals(userId) & t.deletedAt.isSmallerOrEqualValue(watermark),
    )).go();
  }

  // ---------------------------------------------------------------------------
  // Pull
  // ---------------------------------------------------------------------------

  Future<bool> _pull(String userId) async {
    final cursor = await _cursor(userId);
    final since = cursor?.lastPullAt ?? _epoch;
    var applied = false;
    DateTime? watermark;
    final appliedTransactions = <String>{};

    for (final table in kSyncedTables) {
      final remoteRows = await _fetchAllChanged(table, since);
      for (final row in remoteRows) {
        final updatedAt = _parseTs(row['updated_at']);
        if (updatedAt != null &&
            (watermark == null || updatedAt.isAfter(watermark))) {
          watermark = updatedAt;
        }

        final id = row['id'] ?? row['key'];
        if (id == null) continue;
        final idString = id as String;
        final isDelete = row['deleted_at'] != null;

        final local = await _localUpdatedAt(table, idString);
        if (!isDelete && local != null && !local.isBefore(updatedAt ?? _epoch)) {
          // Local copy is not older — keep it; our push already won server-side.
          continue;
        }

        if (isDelete) {
          await _deleteLocalRow(table, idString);
          await _clearTombstone(table, idString);
          if (table == 'transactions') appliedTransactions.remove(idString);
        } else {
          await _applyRemoteRow(table, row, userId);
          if (table == 'transactions') appliedTransactions.add(idString);
        }
        applied = true;
      }
    }

    if (appliedTransactions.isNotEmpty) {
      final children = await _remote.fetchTransactionChildren(
        appliedTransactions.toList(),
      );
      for (final entry in children.entries) {
        await _replaceLocalChildren(
          entry.key,
          children: entry.value,
          // Only replace when the remote actually carries entries — a valid
          // double-entry record always has them.
          force: entry.value.ledgerEntries.isNotEmpty,
        );
      }
    }

    await _setCursor(
      userId,
      lastPullAt: watermark ?? (since == _epoch ? _clock().toUtc() : since),
    );
    return applied;
  }

  Future<List<Map<String, dynamic>>> _fetchAllChanged(
    String table,
    DateTime since,
  ) async {
    final all = <Map<String, dynamic>>[];
    var current = since;
    while (true) {
      final page = await _remote.fetchChanged(table, since: current);
      all.addAll(page);
      if (page.length < 1000) break;
      final maxTs = _parseTs(
        page.map((r) => r['updated_at']).whereType<String>().reduce(
          (a, b) => DateTime.parse(a).isAfter(DateTime.parse(b)) ? a : b,
        ),
      );
      if (maxTs == null || !maxTs.isAfter(current)) break;
      current = maxTs;
    }
    return all;
  }

  Future<DateTime?> _localUpdatedAt(String table, String id) async {
    switch (table) {
      case 'accounts':
        return (await (_db.select(
          _db.accounts,
        )..where((t) => t.id.equals(id))).getSingleOrNull())?.updatedAt;
      case 'tags':
        return (await (_db.select(
          _db.tags,
        )..where((t) => t.id.equals(id))).getSingleOrNull())?.updatedAt;
      case 'transactions':
        return (await (_db.select(
          _db.transactions,
        )..where((t) => t.id.equals(id))).getSingleOrNull())?.updatedAt;
      case 'bills':
        return (await (_db.select(
          _db.bills,
        )..where((t) => t.id.equals(id))).getSingleOrNull())?.updatedAt;
      case 'budgets':
        return (await (_db.select(
          _db.budgets,
        )..where((t) => t.id.equals(id))).getSingleOrNull())?.updatedAt;
      case 'app_settings':
        return (await (_db.select(
          _db.appSettings,
        )..where((t) => t.key.equals(id))).getSingleOrNull())?.updatedAt;
    }
    return null;
  }

  Future<void> _applyRemoteRow(
    String table,
    Map<String, dynamic> row,
    String userId,
  ) async {
    switch (table) {
      case 'accounts':
        await _db.into(_db.accounts).insertOnConflictUpdate(
          AccountsCompanion(
            id: Value(row['id'] as String),
            name: Value(row['name'] as String),
            institution: Value(row['institution'] as String?),
            kind: Value(AccountKind.values.byName(row['kind'] as String)),
            type: Value(AccountType.values.byName(row['type'] as String)),
            status: Value(AccountStatus.values.byName(row['status'] as String)),
            openingBalanceMinor: Value(row['opening_balance_minor'] as int),
            currencyCode: Value(row['currency_code'] as String),
            colorValue: Value(row['color_value'] as int),
            iconCode: Value(row['icon_code'] as String?),
            notes: Value(row['notes'] as String?),
            sortOrder: Value(row['sort_order'] as int),
            isHidden: Value(row['is_hidden'] as bool),
            createdAt: Value(_parseTs(row['created_at']) ?? _clock()),
            updatedAt: Value(_parseTs(row['updated_at']) ?? _clock()),
            userId: Value(userId),
          ),
        );
      case 'tags':
        await _db.into(_db.tags).insertOnConflictUpdate(
          TagsCompanion(
            id: Value(row['id'] as String),
            name: Value(row['name'] as String),
            colorValue: Value(row['color_value'] as int?),
            createdAt: Value(_parseTs(row['created_at']) ?? _clock()),
            updatedAt: Value(_parseTs(row['updated_at']) ?? _clock()),
            userId: Value(userId),
          ),
        );
      case 'transactions':
        await _db.into(_db.transactions).insertOnConflictUpdate(
          TransactionsCompanion(
            id: Value(row['id'] as String),
            type: Value(TransactionType.values.byName(row['type'] as String)),
            amountMinor: Value(row['amount_minor'] as int),
            currencyCode: Value(row['currency_code'] as String),
            occurredAt: Value(_parseTs(row['occurred_at']) ?? _clock()),
            note: Value(row['note'] as String?),
            merchant: Value(row['merchant'] as String?),
            referenceNumber: Value(row['reference_number'] as String?),
            location: Value(row['location'] as String?),
            createdAt: Value(_parseTs(row['created_at']) ?? _clock()),
            updatedAt: Value(_parseTs(row['updated_at']) ?? _clock()),
            userId: Value(userId),
          ),
        );
      case 'bills':
        await _db.into(_db.bills).insertOnConflictUpdate(
          BillsCompanion(
            id: Value(row['id'] as String),
            name: Value(row['name'] as String),
            amountMinor: Value(row['amount_minor'] as int),
            currencyCode: Value(row['currency_code'] as String),
            accountId: Value(row['account_id'] as String?),
            dueDayOfMonth: Value(row['due_day_of_month'] as int),
            reminderDaysBefore: Value(row['reminder_days_before'] as int),
            isActive: Value(row['is_active'] as bool),
            lastPaidOn: Value(_parseTs(row['last_paid_on'])),
            createdAt: Value(_parseTs(row['created_at']) ?? _clock()),
            updatedAt: Value(_parseTs(row['updated_at']) ?? _clock()),
            userId: Value(userId),
          ),
        );
      case 'budgets':
        await _db.into(_db.budgets).insertOnConflictUpdate(
          BudgetsCompanion(
            id: Value(row['id'] as String),
            categoryId: Value(row['category_id'] as String),
            amountMinor: Value(row['amount_minor'] as int),
            currencyCode: Value(row['currency_code'] as String),
            createdAt: Value(_parseTs(row['created_at']) ?? _clock()),
            updatedAt: Value(_parseTs(row['updated_at']) ?? _clock()),
            userId: Value(userId),
          ),
        );
      case 'app_settings':
        await _db.into(_db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion(
            key: Value(row['key'] as String),
            value: Value(row['value'] as String),
            updatedAt: Value(_parseTs(row['updated_at']) ?? _clock()),
            userId: Value(userId),
          ),
        );
    }
  }

  Future<void> _deleteLocalRow(String table, String id) async {
    switch (table) {
      case 'accounts':
        await (_db.delete(
          _db.accounts,
        )..where((t) => t.id.equals(id))).go();
      case 'tags':
        await (_db.delete(_db.tags)..where((t) => t.id.equals(id))).go();
      case 'transactions':
        await (_db.delete(
          _db.transactions,
        )..where((t) => t.id.equals(id))).go();
      case 'bills':
        await (_db.delete(_db.bills)..where((t) => t.id.equals(id))).go();
      case 'budgets':
        await (_db.delete(_db.budgets)..where((t) => t.id.equals(id))).go();
      case 'app_settings':
        await (_db.delete(
          _db.appSettings,
        )..where((t) => t.key.equals(id))).go();
    }
  }

  Future<void> _clearTombstone(String table, String id) async {
    await (_db.delete(
      _db.syncTombstones,
    )..where(
      (t) => t.sourceTable.equals(table) & t.rowId.equals(id),
    )).go();
  }

  Future<void> _replaceLocalChildren(
    String transactionId, {
    required TransactionChildren children,
    bool force = true,
  }) async {
    if (!force) return;
    await _db.transaction(() async {
      await (_db.delete(
        _db.ledgerEntries,
      )..where((t) => t.transactionId.equals(transactionId))).go();
      await (_db.delete(
        _db.transactionTags,
      )..where((t) => t.transactionId.equals(transactionId))).go();
      if (children.ledgerEntries.isNotEmpty) {
        await _db.batch((b) {
          b.insertAll(_db.ledgerEntries, [
            for (final e in children.ledgerEntries)
              LedgerEntriesCompanion.insert(
                id: (e['id'] as String?) ?? IdGenerator.next(),
                transactionId: transactionId,
                accountId: e['account_id'] as String,
                direction: LedgerDirection.values.byName(
                  e['direction'] as String,
                ),
                amountMinor: e['amount_minor'] as int,
                currencyCode: e['currency_code'] as String,
              ),
          ]);
        });
      }
      if (children.transactionTags.isNotEmpty) {
        await _db.batch((b) {
          b.insertAll(_db.transactionTags, [
            for (final t in children.transactionTags)
              TransactionTagsCompanion.insert(
                transactionId: transactionId,
                tagId: t['tag_id'] as String,
              ),
          ]);
        });
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Row serialisation (local drift row -> remote map)
  // ---------------------------------------------------------------------------

  /// The internal row maps keep [DateTime] values; [SyncEngine._toRemoteRows]
  /// serialises them to ISO-8601 when talking to the cloud.
  static Map<String, dynamic> _accountRow(AccountRow row) => {
    'id': row.id,
    'name': row.name,
    'institution': row.institution,
    'kind': row.kind.name,
    'type': row.type.name,
    'status': row.status.name,
    'opening_balance_minor': row.openingBalanceMinor,
    'currency_code': row.currencyCode,
    'color_value': row.colorValue,
    'icon_code': row.iconCode,
    'notes': row.notes,
    'sort_order': row.sortOrder,
    'is_hidden': row.isHidden,
    'created_at': row.createdAt,
    'updated_at': row.updatedAt,
  };

  static Map<String, dynamic> _tagRow(TagRow row) => {
    'id': row.id,
    'name': row.name,
    'color_value': row.colorValue,
    'created_at': row.createdAt,
    'updated_at': row.updatedAt ?? row.createdAt,
  };

  static Map<String, dynamic> _transactionRow(TransactionRow row) => {
    'id': row.id,
    'type': row.type.name,
    'amount_minor': row.amountMinor,
    'currency_code': row.currencyCode,
    'occurred_at': row.occurredAt,
    'note': row.note,
    'merchant': row.merchant,
    'reference_number': row.referenceNumber,
    'location': row.location,
    'created_at': row.createdAt,
    'updated_at': row.updatedAt,
  };

  static Map<String, dynamic> _billRow(BillRow row) => {
    'id': row.id,
    'name': row.name,
    'amount_minor': row.amountMinor,
    'currency_code': row.currencyCode,
    'account_id': row.accountId,
    'due_day_of_month': row.dueDayOfMonth,
    'reminder_days_before': row.reminderDaysBefore,
    'is_active': row.isActive,
    'last_paid_on': row.lastPaidOn,
    'created_at': row.createdAt,
    'updated_at': row.updatedAt,
  };

  static Map<String, dynamic> _budgetRow(BudgetRow row) => {
    'id': row.id,
    'category_id': row.categoryId,
    'amount_minor': row.amountMinor,
    'currency_code': row.currencyCode,
    'created_at': row.createdAt,
    'updated_at': row.updatedAt,
  };

  static Map<String, dynamic> _settingRow(AppSettingRow row) => {
    'key': row.key,
    'value': row.value,
    'updated_at': row.updatedAt,
  };

  static Map<String, dynamic> _entryRow(LedgerEntryRow row) => {
    'id': row.id,
    'transaction_id': row.transactionId,
    'account_id': row.accountId,
    'direction': row.direction.name,
    'amount_minor': row.amountMinor,
    'currency_code': row.currencyCode,
  };

  static Map<String, dynamic> _tagLinkRow(TransactionTagRow row) => {
    'transaction_id': row.transactionId,
    'tag_id': row.tagId,
  };

  /// Converts the internal row maps (DateTime values) into the wire format
  /// (ISO-8601 strings) the cloud expects. Legacy rows with a missing
  /// `updated_at` are stamped with the current time so the cloud's NOT NULL
  /// constraint is always satisfied.
  List<Map<String, dynamic>> _toRemoteRows(
    String table,
    List<Map<String, dynamic>> rows,
  ) {
    final now = _clock().toUtc();
    return [
      for (final row in rows)
        {
          for (final entry in row.entries)
            entry.key: () {
              final value = entry.value;
              if (value is DateTime) return _iso(value);
              if (value == null && entry.key == 'updated_at') return _iso(now);
              return value;
            }(),
        },
    ];
  }

  static String _pkOf(String table) =>
      switch (table) {
        'app_settings' => 'key',
        _ => 'id',
      };

  // ---------------------------------------------------------------------------
  // Cursors
  // ---------------------------------------------------------------------------

  Future<SyncMetaRow?> _cursor(String userId) => (_db.select(
    _db.syncMeta,
  )..where((t) => t.userId.equals(userId))).getSingleOrNull();

  Future<void> _setCursor(
    String userId, {
    DateTime? lastPushAt,
    DateTime? lastPullAt,
  }) async {
    final existing = await _cursor(userId);
    if (existing == null) {
      await _db.into(_db.syncMeta).insert(
        SyncMetaCompanion.insert(
          userId: userId,
          lastPushAt: Value(lastPushAt),
          lastPullAt: Value(lastPullAt),
        ),
      );
    } else {
      await (_db.update(
        _db.syncMeta,
      )..where((t) => t.userId.equals(userId))).write(
        SyncMetaCompanion(
          lastPushAt: Value(lastPushAt ?? existing.lastPushAt),
          lastPullAt: Value(lastPullAt ?? existing.lastPullAt),
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static String _iso(DateTime value) => value.toUtc().toIso8601String();

  static DateTime? _parseTs(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value.toUtc();
    return DateTime.tryParse(value.toString())?.toUtc();
  }
}
