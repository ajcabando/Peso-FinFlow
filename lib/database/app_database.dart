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
import 'tables/sync_tombstones_table.dart';
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
    SyncTombstones,
  ],
  daos: [AccountDao, BillDao, BudgetDao, LedgerDao, TransactionDao, SettingsDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Schema 4 adds cloud sync: `user_id` scoping on the synced tables, the
  /// `sync_meta` cursors, the `sync_tombstones` table, and re-points
  /// legacy random-id seed rows to the deterministic ids in `SeedIds`.
  @override
  int get schemaVersion => 4;

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
        await m.createTable(syncTombstones);
        // Deterministic seed ids: re-point any rows seeded with the old
        // random ids so every device shares the same system account and
        // category ids (required for clean cloud merges).
        await SeedReconciler.repoint(this);
      }
    },
    beforeOpen: (details) async {
      // Enforce referential integrity on every connection.
      await customStatement('PRAGMA foreign_keys = ON');
      // Tombstone triggers: any hard delete of a synced row leaves a record
      // so the deletion can propagate to the cloud and other devices. The
      // `WHEN OLD.user_id IS NOT NULL` guard skips rows that were never
      // adopted by a cloud account.
      await _createTombstoneTriggers();
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

  /// Creates the per-table tombstone triggers (idempotent).
  Future<void> _createTombstoneTriggers() async {
    const template = '''
CREATE TRIGGER IF NOT EXISTS {trigger} AFTER DELETE ON {table}
WHEN OLD.user_id IS NOT NULL
BEGIN
  INSERT INTO sync_tombstones (source_table, row_id, user_id, deleted_at)
  VALUES ('{name}', OLD.{pk}, OLD.user_id, OLD.updated_at);
END''';
    for (final (trigger, table, name, pk) in const [
      ('trg_tombstone_accounts', 'accounts', 'accounts', 'id'),
      ('trg_tombstone_transactions', 'transactions', 'transactions', 'id'),
      ('trg_tombstone_bills', 'bills', 'bills', 'id'),
      ('trg_tombstone_budgets', 'budgets', 'budgets', 'id'),
      ('trg_tombstone_tags', 'tags', 'tags', 'id'),
      ('trg_tombstone_app_settings', 'app_settings', 'app_settings', 'key'),
    ]) {
      await customStatement(
        template
            .replaceAll('{trigger}', trigger)
            .replaceAll('{table}', table)
            .replaceAll('{name}', name)
            .replaceAll('{pk}', pk),
      );
    }
  }
}
