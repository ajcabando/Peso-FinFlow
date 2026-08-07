import 'package:drift/drift.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/sync_session.dart';
import '../../../../core/utils/id_generator.dart';
import '../../../../database/app_database.dart';
import '../../../accounts/domain/enums/account_kind.dart';
import '../../../accounts/domain/enums/account_type.dart';
import '../../domain/models/budget.dart';
import '../../domain/models/budget_progress.dart';
import '../../domain/repositories/budget_repository.dart';

/// Persists monthly per-category budgets.
///
/// Progress is computed by reusing the ledger's `categorySpend` aggregation
/// (expense debits minus refunds) for the requested range, so a budget can
/// never disagree with the double-entry source of truth.
class BudgetRepositoryImpl implements BudgetRepository {
  // ignore: prefer_initializing_formals
  BudgetRepositoryImpl({required AppDatabase db}) : _db = db;

  final AppDatabase _db;

  @override
  Stream<List<Budget>> watchBudgets() =>
      _db.budgetDao.watchAll().map((rows) => rows.map(Budget.fromRow).toList());

  @override
  Future<Budget?> getByCategory(String categoryId) async {
    final row = await _db.budgetDao.getByCategory(categoryId);
    return row == null ? null : Budget.fromRow(row);
  }

  @override
  Future<Budget?> getById(String id) async {
    final row = await _db.budgetDao.getById(id);
    return row == null ? null : Budget.fromRow(row);
  }

  @override
  Future<List<BudgetProgress>> budgetProgress({
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await _db.budgetDao.getAll();
    if (rows.isEmpty) return const [];

    final spends = await _db.transactionDao.categorySpend(from: from, to: to);
    final spendByCategory = {
      for (final spend in spends) spend.categoryId: spend.amountMinor,
    };
    final categories = await _db.accountDao.getByIds([
      for (final row in rows) row.categoryId,
    ]);
    final categoryById = {
      for (final category in categories) category.id: category,
    };

    final progress = [
      for (final row in rows)
        BudgetProgress(
          budget: Budget.fromRow(row),
          categoryName:
              categoryById[row.categoryId]?.name ?? 'Unknown category',
          colorValue: categoryById[row.categoryId]?.colorValue ?? 0,
          spentMinor: spendByCategory[row.categoryId] ?? 0,
        ),
    ]..sort((a, b) => b.fraction.compareTo(a.fraction));
    return progress;
  }

  @override
  Future<Budget> upsert({
    required String categoryId,
    required int amountMinor,
    required String currencyCode,
  }) async {
    if (amountMinor <= 0) {
      throw const ValidationException(
        'A budget amount must be greater than zero.',
      );
    }
    final category = await _db.accountDao.getById(categoryId);
    if (category == null) {
      throw const NotFoundException('Category not found.');
    }
    if (category.kind != AccountKind.category ||
        category.type != AccountType.expense) {
      throw const ValidationException(
        'Budgets can only be set for expense categories.',
      );
    }
    if (category.currencyCode != currencyCode) {
      throw ValidationException(
        'The budget currency must match the category ('
        '${category.currencyCode}).',
      );
    }

    final now = DateTime.now();
    final id = IdGenerator.next();
    await _db.transaction(() async {
      final existing = await _db.budgetDao.getByCategory(categoryId);
      if (existing != null) {
        await _db.budgetDao.updateRow(
          BudgetsCompanion(
            id: Value(existing.id),
            amountMinor: Value(amountMinor),
            currencyCode: Value(currencyCode),
            updatedAt: Value(now),
          ),
        );
      } else {
        await _db.budgetDao.insert(
          BudgetsCompanion.insert(
            id: id,
            categoryId: categoryId,
            amountMinor: amountMinor,
            currencyCode: currencyCode,
            createdAt: now,
            updatedAt: now,
            userId: Value(SyncSession.instance.userId),
          ),
        );
      }
    });
    return (await getByCategory(categoryId))!;
  }

  @override
  Future<void> deleteBudget(String id) async {
    final existing = await _db.budgetDao.getById(id);
    if (existing == null) {
      throw const NotFoundException('Budget not found.');
    }
    await _db.budgetDao.deleteById(id);
  }
}
