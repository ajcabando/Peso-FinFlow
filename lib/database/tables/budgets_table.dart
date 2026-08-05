import 'package:drift/drift.dart';

import 'accounts_table.dart';

/// A monthly spending limit for one expense category.
///
/// Budgets are compared against **ledger-derived** spend for the selected
/// month (expense debits minus refunds), so progress can never drift from
/// the double-entry source of truth. One budget per category.
@DataClassName('BudgetRow')
class Budgets extends Table {
  TextColumn get id => text()();

  /// The expense category this budget limits.
  TextColumn get categoryId =>
      text().references(Accounts, #id, onDelete: KeyAction.cascade)();

  /// Monthly limit in minor units (e.g. `500000` = ₱5,000.00).
  IntColumn get amountMinor => integer()();

  TextColumn get currencyCode => text()();

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {categoryId},
  ];
}
