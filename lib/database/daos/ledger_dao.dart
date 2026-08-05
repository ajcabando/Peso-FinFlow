import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/ledger_entries_table.dart';

part 'ledger_dao.g.dart';

/// Sum of debit and credit amounts for one account (raw ledger facts).
class LedgerSums {
  const LedgerSums({required this.debit, required this.credit});

  final int debit;
  final int credit;
}

/// Data access for [LedgerEntries] — the double-entry ledger.
///
/// Balances are never stored; they are always aggregated from this table.
@DriftAccessor(tables: [LedgerEntries])
class LedgerDao extends DatabaseAccessor<AppDatabase> with _$LedgerDaoMixin {
  LedgerDao(super.db);

  /// Reactive map of `accountId → (debit sum, credit sum)` for every account
  /// that has any entries.
  Stream<Map<String, LedgerSums>> watchSumsByAccount() {
    const query =
        'SELECT account_id AS accountId, '
        'SUM(CASE WHEN direction = ? THEN amount_minor ELSE 0 END) AS debitSum, '
        'SUM(CASE WHEN direction = ? THEN amount_minor ELSE 0 END) AS creditSum '
        'FROM ledger_entries GROUP BY account_id';
    return customSelect(
      query,
      variables: const [Variable('debit'), Variable('credit')],
      readsFrom: {ledgerEntries},
    ).watch().map((rows) {
      final result = <String, LedgerSums>{};
      for (final row in rows) {
        result[row.read<String>('accountId')] = LedgerSums(
          debit: row.read<int>('debitSum'),
          credit: row.read<int>('creditSum'),
        );
      }
      return result;
    });
  }

  /// One-shot raw sums for [accountId] (empty sums when the account has no
  /// entries).
  Future<LedgerSums> sumsFor(String accountId) async {
    final row = await customSelect(
      'SELECT '
      'COALESCE(SUM(CASE WHEN direction = ? THEN amount_minor ELSE 0 END), 0) AS debitSum, '
      'COALESCE(SUM(CASE WHEN direction = ? THEN amount_minor ELSE 0 END), 0) AS creditSum '
      'FROM ledger_entries WHERE account_id = ?',
      variables: [Variable('debit'), Variable('credit'), Variable(accountId)],
    ).getSingle();
    return LedgerSums(
      debit: row.read<int>('debitSum'),
      credit: row.read<int>('creditSum'),
    );
  }
}
