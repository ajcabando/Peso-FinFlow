import 'package:drift/drift.dart';

import '../../features/transactions/domain/enums/ledger_direction.dart';
import '../converters/enum_converters.dart';
import 'accounts_table.dart';
import 'transactions_table.dart';

/// The double-entry ledger.
///
/// Every transaction writes at least two rows here — one debit and one credit
/// — such that debits always equal credits per transaction. Account balances
/// are **derived** by aggregating these rows; they are never stored, which is
/// what makes balance corruption structurally impossible.
@DataClassName('LedgerEntryRow')
@TableIndex(name: 'idx_ledger_entries_account', columns: {#accountId})
@TableIndex(name: 'idx_ledger_entries_transaction', columns: {#transactionId})
class LedgerEntries extends Table {
  TextColumn get id => text()();

  TextColumn get transactionId =>
      text().references(Transactions, #id, onDelete: KeyAction.cascade)();

  /// The account or category affected.
  TextColumn get accountId => text().references(Accounts, #id)();

  TextColumn get direction =>
      text().map(enumNameConverter(LedgerDirection.values))();

  /// Positive amount in minor units.
  IntColumn get amountMinor => integer()();

  /// Denormalised currency for future multi-currency support.
  TextColumn get currencyCode => text()();

  @override
  Set<Column> get primaryKey => {id};
}
