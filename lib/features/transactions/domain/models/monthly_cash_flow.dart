/// Income vs expense totals for one calendar month, in minor units.
class MonthlyCashFlow {
  const MonthlyCashFlow({
    required this.year,
    required this.month,
    required this.incomeMinor,
    required this.expenseMinor,
  });

  final int year;
  final int month;
  final int incomeMinor;
  final int expenseMinor;

  int get netMinor => incomeMinor - expenseMinor;
}
