/// A category's net activity for a period, ready for analytics charts.
///
/// For expense categories [amountMinor] is net spending (debits minus
/// refunds); for income categories it is net earnings (credits minus
/// refunds). Only categories with positive activity are produced, so a
/// category that was fully refunded simply disappears from the breakdown.
class CategorySpend {
  const CategorySpend({
    required this.categoryId,
    required this.categoryName,
    required this.amountMinor,
    required this.isIncome,
    required this.colorValue,
    this.iconCode,
  });

  final String categoryId;

  final String categoryName;

  /// Net minor-unit amount for the period (always positive).
  final int amountMinor;

  /// True for income categories (earnings), false for expense categories.
  final bool isIncome;

  /// ARGB colour used by chart slices and list swatches.
  final int colorValue;

  /// Material icon name for the category, when one is set.
  final String? iconCode;
}
