import '../enums/transaction_type.dart';
import '../models/balance_point.dart';
import '../models/category_spend.dart';
import '../models/draft_transaction.dart';
import '../models/financial_transaction.dart';
import '../models/monthly_cash_flow.dart';
import '../models/net_worth_point.dart';
import '../models/transaction_context.dart';
import '../models/transaction_edit_data.dart';

/// Contract for the transaction feature's data layer.
abstract interface class TransactionRepository {
  /// Every transaction, newest first (full list screen).
  Stream<List<FinancialTransaction>> watchAll();

  /// Most recent transactions, newest first.
  Stream<List<FinancialTransaction>> watchRecent({int limit});

  /// Transactions touching [accountId], newest first.
  Stream<List<FinancialTransaction>> watchForAccount(String accountId);

  Future<FinancialTransaction?> getById(String id);

  /// Enriched streams with account & category display names.
  Stream<List<TransactionContext>> watchAllContext();

  Stream<List<TransactionContext>> watchRecentContext({int limit});

  Stream<List<TransactionContext>> watchForAccountContext(String accountId);

  Future<TransactionContext?> getContextById(String id);

  /// Enriched transactions within the half-open range `[from, to)`, newest
  /// first (used by the reports page and exports).
  Future<List<TransactionContext>> contextsBetween({
    required DateTime from,
    required DateTime to,
  });

  /// Windowed, filtered page of enriched transactions (full list screen).
  Future<List<TransactionContext>> contextPage({
    required int limit,
    required int offset,
    String? search,
    TransactionType? type,
  });

  /// Reactive count of transactions matching [search]/[type] (same filters
  /// as [contextPage]) — drives the list's refresh-on-write.
  Stream<int> watchContextCount({String? search, TransactionType? type});

  /// Monthly income vs expense, oldest first, for the last [months] months.
  Future<List<MonthlyCashFlow>> monthlyCashFlow({int months});

  /// Net category activity for the half-open range `[from, to)`, largest
  /// first. Expense categories report net spending; income categories net
  /// earnings.
  Future<List<CategorySpend>> categorySpend({
    required DateTime from,
    required DateTime to,
  });

  /// Net Worth at the end of each of the last [months] calendar months
  /// (including the current one), oldest first.
  Future<List<NetWorthPoint>> netWorthTrend({int months = 12});

  /// Balance of [accountId] at the end of each of the last [months] calendar
  /// months (including the current one), oldest first — feeds the accounts
  /// page sparklines.
  Future<List<BalancePoint>> accountBalanceTrend(
    String accountId, {
    int months = 6,
  });

  /// Account ids involved in an existing transaction (for form pre-fill).
  Future<TransactionEditData?> getEditData(String id);

  /// Validates and atomically persists a balanced draft.
  ///
  /// Throws `ValidationException` when the draft is unbalanced and
  /// `NotFoundException` when it references unknown accounts.
  Future<FinancialTransaction> create(DraftTransaction draft);

  /// Atomically replaces an existing transaction with a new draft.
  Future<FinancialTransaction> update(String id, DraftTransaction draft);

  /// Atomically removes a transaction and all of its ledger entries.
  Future<void> delete(String id);
}
