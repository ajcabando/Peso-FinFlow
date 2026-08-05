import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/app_providers.dart';
import '../../domain/models/budget.dart';
import '../../domain/models/budget_progress.dart';

/// Every budget, reactive.
final budgetsProvider = StreamProvider<List<Budget>>(
  (ref) => ref.watch(budgetRepositoryProvider).watchBudgets(),
);

/// Budgets paired with ledger-derived spend for a calendar month (keyed by
/// the first of the month), most at-risk first.
final budgetProgressProvider =
    FutureProvider.family<List<BudgetProgress>, DateTime>((ref, month) {
      final start = DateTime(month.year, month.month, 1);
      return ref
          .watch(budgetRepositoryProvider)
          .budgetProgress(
            from: start,
            to: DateTime(start.year, start.month + 1, 1),
          );
    });
