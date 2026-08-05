import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/budgets_table.dart';

part 'budget_dao.g.dart';

/// Data access for [Budgets].
@DriftAccessor(tables: [Budgets])
class BudgetDao extends DatabaseAccessor<AppDatabase> with _$BudgetDaoMixin {
  BudgetDao(super.db);

  Stream<List<BudgetRow>> watchAll() => (select(
    budgets,
  )..orderBy([(t) => OrderingTerm(expression: t.createdAt)])).watch();

  Future<List<BudgetRow>> getAll() => (select(
    budgets,
  )..orderBy([(t) => OrderingTerm(expression: t.createdAt)])).get();

  /// The budget for [categoryId], if any (a category has at most one).
  Future<BudgetRow?> getByCategory(String categoryId) => (select(
    budgets,
  )..where((t) => t.categoryId.equals(categoryId))).getSingleOrNull();

  Future<BudgetRow?> getById(String id) =>
      (select(budgets)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> insert(BudgetsCompanion row) => into(budgets).insert(row);

  Future<void> updateRow(BudgetsCompanion row) =>
      (update(budgets)..where((t) => t.id.equals(row.id.value))).write(row);

  Future<void> deleteById(String id) =>
      (delete(budgets)..where((t) => t.id.equals(id))).go();
}
