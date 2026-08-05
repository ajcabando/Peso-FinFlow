import 'package:drift/drift.dart';

import '../../features/accounts/domain/enums/account_kind.dart';
import '../app_database.dart';
import '../tables/accounts_table.dart';
import '../tables/ledger_entries_table.dart';

part 'account_dao.g.dart';

/// Data access for [Accounts].
@DriftAccessor(tables: [Accounts, LedgerEntries])
class AccountDao extends DatabaseAccessor<AppDatabase> with _$AccountDaoMixin {
  AccountDao(super.db);

  Stream<List<AccountRow>> watchAccounts() =>
      (select(accounts)..orderBy([
            (t) => OrderingTerm(expression: t.sortOrder),
            (t) => OrderingTerm(expression: t.name),
          ]))
          .watch();

  /// Real financial accounts (excludes virtual categories & system rows).
  Stream<List<AccountRow>> watchRealAccounts() =>
      (select(accounts)
            ..where((t) => t.kind.equalsValue(AccountKind.account))
            ..orderBy([
              (t) => OrderingTerm(expression: t.sortOrder),
              (t) => OrderingTerm(expression: t.name),
            ]))
          .watch();

  /// Virtual income/expense categories.
  Stream<List<AccountRow>> watchCategories() =>
      (select(accounts)
            ..where((t) => t.kind.equalsValue(AccountKind.category))
            ..orderBy([
              (t) => OrderingTerm(expression: t.sortOrder),
              (t) => OrderingTerm(expression: t.name),
            ]))
          .watch();

  /// System accounts (e.g. "Opening Balances").
  Stream<List<AccountRow>> watchSystemAccounts() => (select(
    accounts,
  )..where((t) => t.kind.equalsValue(AccountKind.system))).watch();

  Future<AccountRow?> getById(String id) =>
      (select(accounts)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// The system "Opening Balances" account created during seeding.
  Future<AccountRow?> getOpeningBalancesAccount() =>
      (select(accounts)
            ..where((t) => t.kind.equalsValue(AccountKind.system))
            ..limit(1))
          .getSingleOrNull();

  Future<List<AccountRow>> getByIds(List<String> ids) {
    if (ids.isEmpty) return Future.value(const []);
    return (select(accounts)..where((t) => t.id.isIn(ids))).get();
  }

  Future<void> insert(AccountsCompanion row) => into(accounts).insert(row);

  /// Updates an existing account row (must carry the account id).
  Future<void> updateAccount(AccountsCompanion row) =>
      (update(accounts)..where((t) => t.id.equals(row.id.value))).write(row);

  Future<void> deleteById(String id) =>
      (delete(accounts)..where((t) => t.id.equals(id))).go();

  /// Number of ledger entries referencing [accountId] (used to decide whether
  /// an account can be deleted).
  Future<int> countLedgerEntries(String accountId) async {
    final row = await customSelect(
      'SELECT COUNT(*) AS c FROM ledger_entries WHERE account_id = ?',
      variables: [Variable(accountId)],
    ).getSingle();
    return row.read<int>('c');
  }
}
