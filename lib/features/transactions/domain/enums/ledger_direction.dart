/// The direction of a single entry in the double-entry ledger.
enum LedgerDirection { debit, credit }

extension LedgerDirectionX on LedgerDirection {
  /// The opposite direction.
  LedgerDirection get opposite => this == LedgerDirection.debit
      ? LedgerDirection.credit
      : LedgerDirection.debit;

  /// Human-readable label.
  String get label => this == LedgerDirection.debit ? 'Debit' : 'Credit';
}
