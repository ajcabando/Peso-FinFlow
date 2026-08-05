import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/accounts/presentation/pages/account_detail_page.dart';
import '../../features/accounts/presentation/pages/account_form_page.dart';
import '../../features/accounts/presentation/pages/accounts_page.dart';
import '../../features/bills/presentation/pages/bill_form_page.dart';
import '../../features/bills/presentation/pages/bills_page.dart';
import '../../features/budgets/presentation/pages/budget_form_page.dart';
import '../../features/budgets/presentation/pages/budgets_page.dart';
import '../../features/dashboard/presentation/pages/analytics_page.dart';
import '../../features/dashboard/presentation/pages/dashboard_page.dart';
import '../../features/reports/presentation/pages/reports_page.dart';
import '../../features/settings/presentation/pages/settings_page.dart';
import '../../features/transactions/domain/enums/transaction_type.dart';
import '../../features/transactions/presentation/pages/transaction_detail_page.dart';
import '../../features/transactions/presentation/pages/transaction_form_page.dart';
import '../../features/transactions/presentation/pages/transaction_list_page.dart';
import '../../shared/widgets/app_navigation_bar.dart';

/// Route names used with `context.push(...)` / `context.go(...)`.
abstract final class AppRoutes {
  static const String dashboard = '/';
  static const String accounts = '/accounts';
  static const String settings = '/settings';
  static const String accountForm = '/accounts/new';
  static const String analytics = '/analytics';
  static const String reports = '/reports';
  static const String budgets = '/budgets';
  static const String budgetForm = '/budgets/new';
  static const String bills = '/bills';
  static const String billForm = '/bills/new';
  static const String transactions = '/transactions';
  static const String transactionForm = '/transactions/new';

  /// Detail page for [accountId].
  static String accountDetail(String accountId) => '/accounts/$accountId';

  /// Edit page for [accountId].
  static String accountEdit(String accountId) => '/accounts/$accountId/edit';

  /// Detail page for [transactionId].
  static String transactionDetail(String transactionId) =>
      '/transactions/$transactionId';

  /// Edit page for [transactionId].
  static String transactionEdit(String transactionId) =>
      '/transactions/$transactionId/edit';

  /// Edit page for [budgetId].
  static String budgetEdit(String budgetId) => '/budgets/$budgetId/edit';

  /// Edit page for [billId].
  static String billEdit(String billId) => '/bills/$billId/edit';
}

/// Application navigation tree.
///
/// A stateful shell keeps the three main sections alive while switching tabs
/// (dashboard → accounts → settings). Full-screen pages (transaction list,
/// account detail, forms) are pushed on the root navigator so they overlay
/// the shell.
final appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: AppRoutes.dashboard,
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AppNavigationShell(shell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.dashboard,
              builder: (context, state) => const DashboardPage(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.transactions,
              builder: (context, state) => const TransactionListPage(),
              routes: [
                GoRoute(
                  path: 'new',
                  parentNavigatorKey: _rootNavigatorKey,
                  builder: (context, state) => TransactionFormPage(
                    accountId: state.uri.queryParameters['account'],
                    initialType: state.extra is TransactionType
                        ? state.extra as TransactionType
                        : null,
                  ),
                ),
                GoRoute(
                  path: ':id',
                  parentNavigatorKey: _rootNavigatorKey,
                  builder: (context, state) => TransactionDetailPage(
                    transactionId: state.pathParameters['id']!,
                  ),
                  routes: [
                    GoRoute(
                      path: 'edit',
                      parentNavigatorKey: _rootNavigatorKey,
                      builder: (context, state) => TransactionFormPage(
                        transactionId: state.pathParameters['id'],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.accounts,
              builder: (context, state) => const AccountsPage(),
              routes: [
                GoRoute(
                  path: 'new',
                  parentNavigatorKey: _rootNavigatorKey,
                  builder: (context, state) => const AccountFormPage(),
                ),
                GoRoute(
                  path: ':id',
                  builder: (context, state) =>
                      AccountDetailPage(accountId: state.pathParameters['id']!),
                  routes: [
                    GoRoute(
                      path: 'edit',
                      parentNavigatorKey: _rootNavigatorKey,
                      builder: (context, state) => AccountFormPage(
                        accountId: state.pathParameters['id'],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.analytics,
              builder: (context, state) => const AnalyticsPage(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.settings,
              builder: (context, state) => const SettingsPage(),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: AppRoutes.budgets,
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const BudgetsPage(),
      routes: [
        GoRoute(
          path: 'new',
          parentNavigatorKey: _rootNavigatorKey,
          builder: (context, state) => const BudgetFormPage(),
        ),
        GoRoute(
          path: ':id/edit',
          parentNavigatorKey: _rootNavigatorKey,
          builder: (context, state) =>
              BudgetFormPage(budgetId: state.pathParameters['id']),
        ),
      ],
    ),
    GoRoute(
      path: AppRoutes.bills,
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const BillsPage(),
      routes: [
        GoRoute(
          path: 'new',
          parentNavigatorKey: _rootNavigatorKey,
          builder: (context, state) => const BillFormPage(),
        ),
        GoRoute(
          path: ':id/edit',
          parentNavigatorKey: _rootNavigatorKey,
          builder: (context, state) =>
              BillFormPage(billId: state.pathParameters['id']),
        ),
      ],
    ),
    GoRoute(
      path: AppRoutes.reports,
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const ReportsPage(),
    ),
  ],
);

final _rootNavigatorKey = GlobalKey<NavigatorState>();
