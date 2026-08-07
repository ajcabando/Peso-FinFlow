import 'package:drift/drift.dart';

import '../../features/accounts/domain/enums/account_kind.dart';
import '../../features/accounts/domain/enums/account_type.dart';
import '../app_database.dart';
import 'default_categories.dart';
import 'seed_ids.dart';

/// Re-points seed rows created by older (random-id) versions of
/// `DatabaseSeeder` to the canonical ids in [SeedIds].
///
/// Runs during the schema v4 migration, so a device that was seeded before
/// deterministic ids existed still converges on the same system account and
/// category ids as a fresh device — without which cloud sync would duplicate
/// the Opening Balances account and every default category.
///
/// Moving a row is three steps, all FK-safe with `PRAGMA foreign_keys = ON`:
/// 1. insert a copy under the canonical id,
/// 2. re-point every reference at the new id (`ledger_entries.account_id`,
///    `budgets.category_id`, and `bills.account_id` for completeness — bills
///    never reference seed rows in practice, but their FK is `SET NULL`),
/// 3. delete the legacy row (it has no references left).
class SeedReconciler {
  static Future<void> repoint(AppDatabase db) async {
    await _repointSystemAccount(db);
    for (var i = 0; i < defaultCategories.length; i++) {
      await _repointCategory(
        db,
        name: defaultCategories[i].name,
        type: defaultCategories[i].type,
        canonicalId: SeedIds.category(i),
      );
    }
  }

  static Future<void> _repointSystemAccount(AppDatabase db) async {
    final rows = await (db.select(
      db.accounts,
    )..where((t) => t.kind.equalsValue(AccountKind.system))).get();
    for (final row in rows.where((r) => r.id != SeedIds.systemAccount)) {
      await _moveAccount(db, row, SeedIds.systemAccount);
    }
  }

  static Future<void> _repointCategory(
    AppDatabase db, {
    required String name,
    required AccountType type,
    required String canonicalId,
  }) async {
    final rows = await (db.select(
      db.accounts,
    )..where(
      (t) =>
          t.kind.equalsValue(AccountKind.category) &
          t.name.equals(name) &
          t.type.equalsValue(type),
    )).get();
    for (final row in rows.where((r) => r.id != canonicalId)) {
      await _moveAccount(db, row, canonicalId);
    }
  }

  static Future<void> _moveAccount(
    AppDatabase db,
    AccountRow legacy,
    String canonicalId,
  ) async {
    final canonicalExists = await (db.select(
      db.accounts,
    )..where((t) => t.id.equals(canonicalId))).getSingleOrNull();

    if (canonicalExists == null) {
      await db.into(db.accounts).insert(
        AccountsCompanion(
          id: Value(canonicalId),
          name: Value(legacy.name),
          institution: Value(legacy.institution),
          kind: Value(legacy.kind),
          type: Value(legacy.type),
          status: Value(legacy.status),
          openingBalanceMinor: Value(legacy.openingBalanceMinor),
          currencyCode: Value(legacy.currencyCode),
          colorValue: Value(legacy.colorValue),
          iconCode: Value(legacy.iconCode),
          notes: Value(legacy.notes),
          sortOrder: Value(legacy.sortOrder),
          isHidden: Value(legacy.isHidden),
          createdAt: Value(legacy.createdAt),
          updatedAt: Value(legacy.updatedAt),
          userId: Value(legacy.userId),
        ),
      );
    }

    await (db.update(
      db.ledgerEntries,
    )..where((t) => t.accountId.equals(legacy.id))).write(
      LedgerEntriesCompanion(accountId: Value(canonicalId)),
    );
    await (db.update(
      db.budgets,
    )..where((t) => t.categoryId.equals(legacy.id))).write(
      BudgetsCompanion(categoryId: Value(canonicalId)),
    );
    await (db.update(
      db.bills,
    )..where((t) => t.accountId.equals(legacy.id))).write(
      BillsCompanion(accountId: Value(canonicalId)),
    );

    await (db.delete(
      db.accounts,
    )..where((t) => t.id.equals(legacy.id))).go();
  }
}
