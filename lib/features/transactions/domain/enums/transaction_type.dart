/// The business-facing classification of a transaction.
///
/// The double-entry engine derives the accounting reality from the transaction
/// entries; this enum is a convenience classification used for filtering and
/// display.
enum TransactionType {
  income('Income'),
  expense('Expense'),
  transfer('Transfer'),
  refund('Refund'),
  adjustment('Adjustment'),
  openingBalance('Opening Balance');

  const TransactionType(this.label);

  /// Human-readable name shown in the UI.
  final String label;
}
