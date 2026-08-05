import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/app_providers.dart';
import '../../../transactions/domain/models/transaction_context.dart';
import '../../../transactions/presentation/providers/transaction_providers.dart';
import '../../data/report_exporter.dart';

/// Transactions within a calendar month (keyed by the first of the month),
/// newest first — used by the reports page and exports.
final monthContextsProvider =
    FutureProvider.family<List<TransactionContext>, DateTime>((ref, month) {
      final start = DateTime(month.year, month.month, 1);
      return ref
          .watch(transactionRepositoryProvider)
          .contextsBetween(
            from: start,
            to: DateTime(start.year, start.month + 1, 1),
          );
    });

/// Everything the reports page renders for a calendar month: summary,
/// category breakdown and the transaction list.
final reportDataProvider =
    FutureProvider.family<ReportData, DateTime>((ref, month) async {
      final start = DateTime(month.year, month.month, 1);
      final end = DateTime(start.year, start.month + 1, 1);
      final currency = ref.watch(defaultCurrencyProvider);
      final spends = await ref.watch(categorySpendProvider(month).future);
      final contexts = await ref.watch(monthContextsProvider(month).future);

      final income = spends
          .where((s) => s.isIncome)
          .fold<int>(0, (sum, s) => sum + s.amountMinor);
      final expense = spends
          .where((s) => !s.isIncome)
          .fold<int>(0, (sum, s) => sum + s.amountMinor);

      return ReportData(
        from: start,
        to: end,
        currencyCode: currency,
        incomeMinor: income,
        expenseMinor: expense,
        categories: spends,
        contexts: contexts,
      );
    });
