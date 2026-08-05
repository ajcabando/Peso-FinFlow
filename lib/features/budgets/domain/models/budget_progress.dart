import 'budget.dart';

/// A [Budget] paired with the ledger-derived spend for the selected month.
///
/// Spend is the net expense-category activity (debits minus refunds) so
/// progress always matches the double-entry source of truth.
class BudgetProgress {
  const BudgetProgress({
    required this.budget,
    required this.categoryName,
    required this.colorValue,
    required this.spentMinor,
  });

  final Budget budget;

  final String categoryName;

  /// ARGB colour of the category (used for the progress bar).
  final int colorValue;

  /// Net spend in minor units for the month.
  final int spentMinor;

  int get amountMinor => budget.amountMinor;

  /// 0.0 → 1.0+ fraction of the budget used (can exceed 1 when over).
  double get fraction =>
      budget.amountMinor <= 0 ? 0 : spentMinor / budget.amountMinor;

  /// Remaining budget (negative when over).
  int get remainingMinor => budget.amountMinor - spentMinor;

  bool get isOver => spentMinor > budget.amountMinor;

  /// Over 80% used but not yet over.
  bool get isNearlyExhausted => !isOver && fraction >= 0.8;
}
