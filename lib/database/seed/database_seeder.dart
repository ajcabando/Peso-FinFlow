import 'package:drift/drift.dart';

import '../../core/constants/app_constants.dart';
import '../../features/accounts/domain/enums/account_kind.dart';
import '../../features/accounts/domain/enums/account_status.dart';
import '../../features/accounts/domain/enums/account_type.dart';
import '../app_database.dart';
import 'default_categories.dart';
import 'seed_ids.dart';

/// Seeds a brand-new database with the system accounts and default categories.
///
/// Idempotent by design: every block first checks whether its rows already
/// exist, so this is safe to run on every `onCreate`.
///
/// Every seeded row uses a **deterministic** id from [SeedIds], so all
/// devices converge on the same system account and category ids — a
/// requirement for clean multi-device cloud sync (see `docs/SYNC.md`).
class DatabaseSeeder {
  static Future<void> seed(AppDatabase db) async {
    final now = DateTime.now();
    await db.transaction(() async {
      await _seedSystemAccounts(db, now);
      await _seedDefaultCategories(db, now);
    });
  }

  static Future<void> _seedSystemAccounts(AppDatabase db, DateTime now) async {
    final existing = await (db.select(
      db.accounts,
    )..where((t) => t.kind.equalsValue(AccountKind.system))).get();
    if (existing.isNotEmpty) return;

    await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            id: SeedIds.systemAccount,
            name: AppConstants.openingBalancesAccountName,
            kind: AccountKind.system,
            type: AccountType.openingBalance,
            status: AccountStatus.active,
            openingBalanceMinor: 0,
            currencyCode: 'PHP',
            colorValue: 0xFF0E9F6E,
            sortOrder: 0,
            isHidden: true,
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  static Future<void> _seedDefaultCategories(
    AppDatabase db,
    DateTime now,
  ) async {
    final existing = await (db.select(
      db.accounts,
    )..where((t) => t.kind.equalsValue(AccountKind.category))).get();
    if (existing.isNotEmpty) return;

    await db.batch((batch) {
      batch.insertAll(db.accounts, [
        for (var i = 0; i < defaultCategories.length; i++)
          AccountsCompanion.insert(
            id: SeedIds.category(i),
            name: defaultCategories[i].name,
            kind: AccountKind.category,
            type: defaultCategories[i].type,
            status: AccountStatus.active,
            openingBalanceMinor: 0,
            currencyCode: 'PHP',
            colorValue: defaultCategories[i].color.toARGB32(),
            iconCode: Value(defaultCategories[i].iconCode),
            sortOrder: 0,
            isHidden: true,
            createdAt: now,
            updatedAt: now,
          ),
      ]);
    });
  }
}
