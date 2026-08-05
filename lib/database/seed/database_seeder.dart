import 'package:drift/drift.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/id_generator.dart';
import '../../features/accounts/domain/enums/account_kind.dart';
import '../../features/accounts/domain/enums/account_status.dart';
import '../../features/accounts/domain/enums/account_type.dart';
import '../app_database.dart';
import 'default_categories.dart';

/// Seeds a brand-new database with the system accounts and default categories.
///
/// Idempotent by design: every block first checks whether its rows already
/// exist, so this is safe to run on every `onCreate`.
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
            id: IdGenerator.next(),
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
        for (final category in defaultCategories)
          AccountsCompanion.insert(
            id: IdGenerator.next(),
            name: category.name,
            kind: AccountKind.category,
            type: category.type,
            status: AccountStatus.active,
            openingBalanceMinor: 0,
            currencyCode: 'PHP',
            colorValue: category.color.toARGB32(),
            iconCode: Value(category.iconCode),
            sortOrder: 0,
            isHidden: true,
            createdAt: now,
            updatedAt: now,
          ),
      ]);
    });
  }
}
