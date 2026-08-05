import 'package:drift/native.dart';
import 'package:finflow/database/app_database.dart';
import 'package:finflow/features/accounts/data/repositories/account_repository_impl.dart';
import 'package:finflow/features/accounts/domain/models/account.dart';
import 'package:finflow/features/accounts/domain/repositories/account_repository.dart';
import 'package:finflow/features/budgets/data/repositories/budget_repository_impl.dart';
import 'package:finflow/features/budgets/domain/repositories/budget_repository.dart';
import 'package:finflow/features/transactions/data/repositories/transaction_repository_impl.dart';
import 'package:finflow/features/transactions/domain/repositories/transaction_repository.dart';

/// A fully wired, in-memory test harness with seeded defaults.
class TestHarness {
  TestHarness._(this.db);

  /// Wires repositories around an already-open [database] (used by widget
  /// tests that inject their own instance).
  TestHarness.attach(AppDatabase database) : db = database;

  final AppDatabase db;

  late final TransactionRepository transactions = TransactionRepositoryImpl(
    db: db,
  );
  late final AccountRepository accounts = AccountRepositoryImpl(
    db: db,
    transactionRepository: transactions,
  );
  late final BudgetRepository budgets = BudgetRepositoryImpl(db: db);

  /// Finds a seeded category account by name.
  Future<Account> category(String name) async {
    final account = await _accountWhere(name);
    if (account == null) {
      throw StateError('Category "$name" not found in the seeded database.');
    }
    return account;
  }

  /// Finds the system Opening Balances account.
  Future<Account> openingBalances() async {
    final account = await accounts.getOpeningBalancesAccount();
    if (account == null) {
      throw StateError('Opening Balances account missing.');
    }
    return account;
  }

  Future<Account?> _accountWhere(String name) async {
    final rows = await (db.select(
      db.accounts,
    )..where((t) => t.name.equals(name))).get();
    return rows.isEmpty ? null : Account.fromRow(rows.first);
  }

  static Future<TestHarness> create() async {
    final db = AppDatabase(NativeDatabase.memory());
    return TestHarness._(db);
  }

  Future<void> dispose() => db.close();
}
