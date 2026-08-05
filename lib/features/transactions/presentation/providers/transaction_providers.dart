import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/app_providers.dart';
import '../../domain/models/balance_point.dart';
import '../../domain/models/category_spend.dart';
import '../../domain/models/financial_transaction.dart';
import '../../domain/models/monthly_cash_flow.dart';
import '../../domain/models/net_worth_point.dart';
import '../../domain/models/transaction_context.dart';
import '../../domain/models/transaction_edit_data.dart';

/// Every transaction, newest first (full list screen), reactive.
final allTransactionsProvider = StreamProvider<List<FinancialTransaction>>(
  (ref) => ref.watch(transactionRepositoryProvider).watchAll(),
);

/// Most recent transactions (dashboard feed), reactive.
final recentTransactionsProvider = StreamProvider<List<FinancialTransaction>>(
  (ref) => ref.watch(transactionRepositoryProvider).watchRecent(limit: 10),
);

/// Transactions touching a given account, reactive.
final accountTransactionsProvider =
    StreamProvider.family<List<FinancialTransaction>, String>(
      (ref, accountId) =>
          ref.watch(transactionRepositoryProvider).watchForAccount(accountId),
    );

/// Enriched transaction feed (account & category names), full list screen.
final allTransactionContextsProvider = StreamProvider<List<TransactionContext>>(
  (ref) => ref.watch(transactionRepositoryProvider).watchAllContext(),
);

/// Enriched recent transactions (dashboard feed).
final recentTransactionContextsProvider =
    StreamProvider<List<TransactionContext>>(
      (ref) => ref
          .watch(transactionRepositoryProvider)
          .watchRecentContext(limit: 10),
    );

/// Enriched transactions touching a given account.
final accountTransactionContextsProvider =
    StreamProvider.family<List<TransactionContext>, String>(
      (ref, accountId) => ref
          .watch(transactionRepositoryProvider)
          .watchForAccountContext(accountId),
    );

/// One enriched transaction (detail page), keyed by transaction id.
final transactionContextProvider =
    FutureProvider.family<TransactionContext?, String>(
      (ref, id) => ref.watch(transactionRepositoryProvider).getContextById(id),
    );

/// Monthly income vs expense for the cash flow chart.
final monthlyCashFlowProvider = FutureProvider<List<MonthlyCashFlow>>(
  (ref) => ref.watch(transactionRepositoryProvider).monthlyCashFlow(months: 6),
);

/// Pre-fill data for the edit form, keyed by transaction id.
final transactionEditDataProvider =
    FutureProvider.family<TransactionEditData?, String>(
      (ref, id) => ref.watch(transactionRepositoryProvider).getEditData(id),
    );

/// Net category activity for a calendar month (keyed by the first of the
/// month), largest first — feeds the analytics breakdowns.
final categorySpendProvider =
    FutureProvider.family<List<CategorySpend>, DateTime>((ref, month) {
      final start = DateTime(month.year, month.month, 1);
      return ref
          .watch(transactionRepositoryProvider)
          .categorySpend(
            from: start,
            to: DateTime(start.year, start.month + 1, 1),
          );
    });

/// Net Worth at the end of each of the last 12 calendar months, oldest
/// first — feeds the net worth history chart.
final netWorthTrendProvider = FutureProvider<List<NetWorthPoint>>(
  (ref) => ref.watch(transactionRepositoryProvider).netWorthTrend(months: 12),
);

/// Per-account balance history (last 6 months) for the accounts page
/// sparklines.
final accountBalanceTrendProvider =
    FutureProvider.family<List<BalancePoint>, String>(
      (ref, accountId) => ref
          .watch(transactionRepositoryProvider)
          .accountBalanceTrend(accountId, months: 6),
    );
