/// Net Worth at the end of one calendar month, derived purely from the ledger.
class NetWorthPoint {
  const NetWorthPoint({
    required this.year,
    required this.month,
    required this.netWorthMinor,
  });

  final int year;
  final int month;

  /// Net Worth in minor units at the end of this month.
  final int netWorthMinor;
}
