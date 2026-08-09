import 'package:drift/drift.dart';

import '../features/accounts/domain/enums/account_kind.dart';
import '../features/accounts/domain/enums/account_status.dart';
import '../features/accounts/domain/enums/account_type.dart';
import '../features/transactions/domain/enums/ledger_direction.dart';
import '../features/transactions/domain/enums/transaction_type.dart';
import 'converters/enum_converters.dart';
import 'daos/account_dao.dart';
import 'daos/bill_dao.dart';
import 'daos/budget_dao.dart';
import 'daos/ledger_dao.dart';
import 'daos/settings_dao.dart';
import 'daos/transaction_dao.dart';
import 'seed/database_seeder.dart';
import 'seed/seed_reconciler.dart';
import 'tables/accounts_table.dart';
import 'tables/app_settings_table.dart';
import 'tables/attachments_table.dart';
import 'tables/bills_table.dart';
import 'tables/budgets_table.dart';
import 'tables/ledger_entries_table.dart';
import 'tables/sync_meta_table.dart';
import 'tables/sync_outbox_table.dart';
import 'tables/tags_table.dart';
import 'tables/transaction_tags_table.dart';
import 'tables/transactions_table.dart';

part 'app_database.g.dart';

/// The FinFlow local database.
///
/// SQLite via Drift, running fully offline. Schema version 1 covers the core
/// ledger; later phases (bills, budgets, goals, ...) add tables through
/// [migration] step callbacks without ever touching existing data.
@DriftDatabase(
  tables: [
    Accounts,
    Transactions,
    LedgerEntries,
    Tags,
    TransactionTags,
    Attachments,
    AppSettings,
    Budgets,
    Bills,
    SyncMeta,
    SyncOutbox,
  ],
  daos: [AccountDao, BillDao, BudgetDao, LedgerDao, TransactionDao, SettingsDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Schema 5 moves sync to the operation log (docs/SELF_HOSTED.md §6-7):
  /// adds the `sync_outbox` table, per-row `version` CAS columns on the six
  /// synced tables, integer seq cursors on `sync_meta` (replacing the v4
  /// DateTime watermarks), and repoints the tombstone triggers to write
  /// DELETE ops into the outbox instead of `sync_tombstones` (which is
  /// dropped along with the deprecated row-delta engine).
  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      // Tables are created with `IF NOT EXISTS`, but indexes are not — a
      // web-persisted database can be reopened without a version marker
      // (e.g. an interrupted write), which would otherwise re-run `createAll`
      // and fail with "index already exists". Creating tables and indexes
      // idempotently makes a re-created database just work.
      for (final table in allTables) {
        await m.createTable(table);
      }
      await _createIndexesIfMissing();
      // Fresh installation: provision system accounts and default
      // categories so the app is immediately usable.
      await DatabaseSeeder.seed(this);
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(budgets);
      }
      if (from < 3) {
        await m.createTable(bills);
      }
      if (from < 4) {
        // Cloud sync scoping: every synced row may carry an owner.
        await m.addColumn(accounts, accounts.userId);
        await m.addColumn(transactions, transactions.userId);
        await m.addColumn(bills, bills.userId);
        await m.addColumn(budgets, budgets.userId);
        await m.addColumn(tags, tags.userId);
        await m.addColumn(tags, tags.updatedAt);
        await m.addColumn(appSettings, appSettings.userId);
        await m.addColumn(appSettings, appSettings.updatedAt);
        await m.createTable(syncMeta);
        // The deprecated row-delta tombstone table (dropped again in v5) is
        // created manually — it is no longer part of the drift schema, but
        // v4 installs upgrading through this step need it to exist.
        await customStatement(
          'CREATE TABLE IF NOT EXISTS sync_tombstones ('
          'source_table TEXT NOT NULL, '
          'row_id TEXT NOT NULL, '
          'user_id TEXT, '
          'deleted_at TEXT, '
          'PRIMARY KEY (source_table, row_id))',
        );
        // Deterministic seed ids: re-point any rows seeded with the old
        // random ids so every device shares the same system account and
        // category ids (required for clean cloud merges).
        await SeedReconciler.repoint(this);
      }
      if (from < 5) {
        // Operation-log sync (docs/SELF_HOSTED.md §7):
        // - `sync_outbox` mirrors the wire envelope; the flush path drains it.
        // - `version` CAS columns on the six synced tables (default 0).
        // - `sync_meta` becomes integer seq cursors (the old v4 DateTime
        //   watermark values are discarded — the first op-log sync starts
        //   from cursor 0 and pushes every local row as baseVersion 0, so no
        //   data is lost: the rows themselves are already in the local DB).
        // - The old row-delta tombstone machinery (table + six triggers that
        //   feed it) is dropped; beforeOpen creates the new outbox triggers.
        await m.createTable(syncOutbox);
        await m.addColumn(accounts, accounts.version);
        await m.addColumn(transactions, transactions.version);
        await m.addColumn(bills, bills.version);
        await m.addColumn(budgets, budgets.version);
        await m.addColumn(tags, tags.version);
        await m.addColumn(appSettings, appSettings.version);
        // sync_meta: replace last_push_at/last_pull_at (DateTime) with
        // push_cursor/pull_cursor (integer seq). Both old columns are
        // nullable and had no indexes — safe to drop in SQLite (≥ 3.35).
        await customStatement('ALTER TABLE sync_meta DROP COLUMN last_push_at');
        await customStatement('ALTER TABLE sync_meta DROP COLUMN last_pull_at');
        await m.addColumn(syncMeta, syncMeta.pushCursor);
        await m.addColumn(syncMeta, syncMeta.pullCursor);
        // Drop the deprecated row-delta tombstone table + the triggers that
        // wrote to it (a trigger referencing a dropped table would fail on
        // the next delete). The new outbox triggers are created in
        // beforeOpen with new names, so nothing references this table.
        for (final trigger in _tombstoneTriggerNames) {
          await customStatement('DROP TRIGGER IF EXISTS $trigger');
        }
        await customStatement('DROP TABLE IF EXISTS sync_tombstones');
      }
    },
    beforeOpen: (details) async {
      // Enforce referential integrity on every connection.
      await customStatement('PRAGMA foreign_keys = ON');
      // Outbox triggers: any hard delete of a synced row enqueues a DELETE op
      // so the deletion can propagate through the operation log. The
      // `WHEN OLD.user_id IS NOT NULL` guard skips rows that were never
      // adopted by a cloud account (same rule as the old tombstone triggers).
      await _createOutboxTriggers();
    },
  );

  /// Creates the schema's indexes if they don't exist yet (idempotent).
  Future<void> _createIndexesIfMissing() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_ledger_entries_account '
      'ON ledger_entries (account_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_ledger_entries_transaction '
      'ON ledger_entries (transaction_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_transactions_occurred_at '
      'ON transactions (occurred_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_transactions_merchant '
      'ON transactions (merchant)',
    );
  }

  /// The deprecated row-delta tombstone trigger names (dropped in v5).
  static const List<String> _tombstoneTriggerNames = [
    'trg_tombstone_accounts',
    'trg_tombstone_transactions',
    'trg_tombstone_bills',
    'trg_tombstone_budgets',
    'trg_tombstone_tags',
    'trg_tombstone_app_settings',
  ];

  /// Creates the per-table outbox DELETE triggers (idempotent).
  ///
  /// Any hard delete of a synced row enqueues a DELETE operation into
  /// `sync_outbox` with `base_version = OLD.version` and
  /// `version = OLD.version + 1` (the v5 `version` column makes this
  /// possible), so the server's CAS sees it as the natural successor of the
  /// last upsert. The op_id is a UUIDv4 built from SQLite's `randomblob`.
  Future<void> _createOutboxTriggers() async {
    const template = '''
CREATE TRIGGER IF NOT EXISTS {trigger} AFTER DELETE ON {table}
WHEN OLD.user_id IS NOT NULL
BEGIN
  INSERT INTO sync_outbox (
    op_id, entity, entity_id, operation,
    base_version, version, payload,
    updated_at, deleted_at, created_at
  ) VALUES (
    lower(hex(randomblob(4))) || '-' || lower(hex(randomblob(2))) || '-' ||
    '4' || substr(lower(hex(randomblob(2))), 2) || '-' ||
    substr('89ab', 1 + (abs(random()) % 4), 1) ||
    substr(lower(hex(randomblob(2))), 2) || '-' ||
    lower(hex(randomblob(6))),
    '{entity}', OLD.{pk}, 'delete',
    OLD.version, OLD.version + 1, NULL,
    OLD.updated_at, OLD.updated_at, strftime('%s', 'now')
  );
END''';
    for (final (trigger, table, entity, pk) in const [
      ('trg_outbox_accounts', 'accounts', 'account', 'id'),
      ('trg_outbox_transactions', 'transactions', 'transaction', 'id'),
      ('trg_outbox_bills', 'bills', 'bill', 'id'),
      ('trg_outbox_budgets', 'budgets', 'budget', 'id'),
      ('trg_outbox_tags', 'tags', 'tag', 'id'),
      ('trg_outbox_app_settings', 'app_settings', 'app_setting', 'key'),
    ]) {
      await customStatement(
        template
            .replaceAll('{trigger}', trigger)
            .replaceAll('{table}', table)
            .replaceAll('{entity}', entity)
            .replaceAll('{pk}', pk),
      );
    }
  }
}
