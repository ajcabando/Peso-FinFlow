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
import 'tables/accounts_table.dart';
import 'tables/app_settings_table.dart';
import 'tables/attachments_table.dart';
import 'tables/bills_table.dart';
import 'tables/budgets_table.dart';
import 'tables/ledger_entries_table.dart';
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
  ],
  daos: [AccountDao, BillDao, BudgetDao, LedgerDao, TransactionDao, SettingsDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Schema 3 adds the `bills` table (Phase 8). Existing data is preserved
  /// through the [migration] step callback.
  @override
  int get schemaVersion => 3;

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
    },
    beforeOpen: (details) async {
      // Enforce referential integrity on every connection.
      await customStatement('PRAGMA foreign_keys = ON');
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
}
