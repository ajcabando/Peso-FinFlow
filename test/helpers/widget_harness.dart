import 'package:finflow/app/providers/app_providers.dart';
import 'package:finflow/core/theme/app_theme.dart';
import 'package:finflow/database/app_database.dart';
import 'package:finflow/features/accounts/domain/enums/account_kind.dart';
import 'package:finflow/features/accounts/domain/models/account.dart';
import 'package:finflow/features/accounts/domain/repositories/account_repository.dart';
import 'package:finflow/features/accounts/presentation/providers/account_providers.dart';
import 'package:finflow/features/bills/domain/models/bill.dart';
import 'package:finflow/features/bills/presentation/providers/bill_providers.dart';
import 'package:finflow/features/budgets/domain/models/budget.dart';
import 'package:finflow/features/budgets/domain/models/budget_progress.dart';
import 'package:finflow/features/budgets/presentation/providers/budget_providers.dart';
import 'package:finflow/features/transactions/domain/models/balance_point.dart';
import 'package:finflow/features/transactions/domain/models/category_spend.dart';
import 'package:finflow/features/transactions/domain/models/monthly_cash_flow.dart';
import 'package:finflow/features/transactions/domain/models/net_worth_point.dart';
import 'package:finflow/features/transactions/domain/models/transaction_context.dart';
import 'package:finflow/features/transactions/domain/models/transaction_edit_data.dart';
import 'package:finflow/features/transactions/presentation/providers/transaction_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One-shot, stream-free reads used by widget tests.
///
/// Drift `watch()` streams schedule a zero-duration timer on cancellation,
/// which fails under the widget test framework's fake-async pending-timer
/// check. Widget tests therefore drive the UI with static provider data and
/// verify writes through one-shot queries instead.
abstract final class WidgetDb {
  static Future<List<Account>> realAccounts(AppDatabase db) async {
    final rows = await (db.select(
      db.accounts,
    )..where((t) => t.kind.equalsValue(AccountKind.account))).get();
    return rows.map(Account.fromRow).toList();
  }

  static Future<List<Account>> categories(AppDatabase db) async {
    final rows = await (db.select(
      db.accounts,
    )..where((t) => t.kind.equalsValue(AccountKind.category))).get();
    return rows.map(Account.fromRow).toList();
  }
}

/// Wraps [child] in a [ProviderScope] with the given overrides.
///
/// Pass static data for any stream-backed provider the page under test
/// watches; the real repository providers still point at [db] so forms can
/// persist through the double-entry engine.
Widget pumpApp(
  AppDatabase db, {
  required Widget child,
  List<Account>? accounts,
  List<Account>? categories,
  List<Bill>? bills,
  List<AccountWithBalance>? accountsWithBalances,
  List<TransactionContext>? recentContexts,
  List<MonthlyCashFlow>? cashFlow,
  List<CategorySpend>? categorySpend,
  List<NetWorthPoint>? netWorthTrend,
  Map<String, List<BalancePoint>>? accountTrends,
  List<Budget>? budgets,
  List<BudgetProgress>? budgetProgress,
  TransactionContext? transactionContext,
  TransactionEditData? editData,
  int? netWorth,
}) {
  return ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      if (accounts != null)
        realAccountsProvider.overrideWith((ref) => Stream.value(accounts)),
      if (categories != null)
        categoriesProvider.overrideWith((ref) => Stream.value(categories)),
      if (accountsWithBalances != null)
        accountsWithBalancesProvider.overrideWith(
          (ref) => Stream.value(accountsWithBalances),
        ),
      if (netWorth != null)
        netWorthProvider.overrideWith((ref) => Stream.value(netWorth)),
      if (recentContexts != null)
        recentTransactionContextsProvider.overrideWith(
          (ref) => Stream.value(recentContexts),
        ),
      if (cashFlow != null)
        monthlyCashFlowProvider.overrideWith((ref) => Future.value(cashFlow)),
      if (categorySpend != null)
        categorySpendProvider.overrideWith(
          (ref, month) => Future.value(categorySpend),
        ),
      if (netWorthTrend != null)
        netWorthTrendProvider.overrideWith(
          (ref) => Future.value(netWorthTrend),
        ),
      if (accountTrends != null)
        accountBalanceTrendProvider.overrideWith(
          (ref, accountId) =>
              Future.value(accountTrends[accountId] ?? const []),
        ),
      if (budgets != null)
        budgetsProvider.overrideWith((ref) => Stream.value(budgets)),
      // The dashboard watches the bills stream; always override it so widget
      // tests never subscribe to a real drift watch (drift's zero-duration
      // watch timers fail under the fake-async pending-timer check).
      billsProvider.overrideWith((ref) => Stream.value(bills ?? const [])),
      if (budgetProgress != null)
        budgetProgressProvider.overrideWith(
          (ref, month) => Future.value(budgetProgress),
        ),
      if (transactionContext != null)
        transactionContextProvider.overrideWith(
          (ref, id) => Future.value(transactionContext),
        ),
      if (editData != null)
        transactionEditDataProvider.overrideWith(
          (ref, id) => Future.value(editData),
        ),
    ],
    child: MaterialApp(theme: AppTheme.light(), home: child),
  );
}
