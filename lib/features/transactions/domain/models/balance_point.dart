/// Balance of one account at the end of one calendar month, derived purely
/// from the ledger.
class BalancePoint {
  const BalancePoint({
    required this.year,
    required this.month,
    required this.balanceMinor,
  });

  final int year;
  final int month;

  /// Balance (or outstanding amount for credit-normal accounts) in minor
  /// units at the end of this month.
  final int balanceMinor;
}
