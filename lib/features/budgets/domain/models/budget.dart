import '../../../../database/app_database.dart';

/// A monthly spending limit for one expense category.
class Budget {
  const Budget({
    required this.id,
    required this.categoryId,
    required this.amountMinor,
    required this.currencyCode,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Budget.fromRow(BudgetRow row) => Budget(
    id: row.id,
    categoryId: row.categoryId,
    amountMinor: row.amountMinor,
    currencyCode: row.currencyCode,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );

  final String id;

  /// The expense category this budget limits.
  final String categoryId;

  /// Monthly limit in minor units.
  final int amountMinor;

  final String currencyCode;

  final DateTime createdAt;
  final DateTime updatedAt;
}
