import '../models/budget.dart';
import '../models/budget_progress.dart';

/// Contract for the budgets feature's data layer.
abstract interface class BudgetRepository {
  /// Every budget, reactive (used by the form to know which categories are
  /// already budgeted).
  Stream<List<Budget>> watchBudgets();

  /// The budget for [categoryId], if any.
  Future<Budget?> getByCategory(String categoryId);

  /// The budget with [id], if any.
  Future<Budget?> getById(String id);

  /// Every budget paired with ledger-derived spend for the half-open range
  /// `[from, to)`, most at-risk first (highest fraction used).
  ///
  /// Budgets with no spend in the range still appear at zero progress.
  Future<List<BudgetProgress>> budgetProgress({
    required DateTime from,
    required DateTime to,
  });

  /// Creates the budget for [categoryId] or updates it when one already
  /// exists (a category has at most one budget).
  ///
  /// Throws `ValidationException` when the category is not an expense
  /// category or the amount is not positive, and `NotFoundException` when the
  /// category does not exist.
  Future<Budget> upsert({
    required String categoryId,
    required int amountMinor,
    required String currencyCode,
  });

  Future<void> deleteBudget(String id);
}
