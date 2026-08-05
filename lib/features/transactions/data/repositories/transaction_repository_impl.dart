import 'package:drift/drift.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/utils/id_generator.dart';
import '../../../../database/app_database.dart';
import '../../../accounts/domain/enums/account_kind.dart';
import '../../../accounts/domain/enums/account_type.dart';
import '../../domain/engine/double_entry_engine.dart';
import '../../domain/enums/ledger_direction.dart';
import '../../domain/enums/transaction_type.dart';
import '../../domain/models/balance_point.dart';
import '../../domain/models/category_spend.dart';
import '../../domain/models/draft_transaction.dart';
import '../../domain/models/financial_transaction.dart';
import '../../domain/models/monthly_cash_flow.dart';
import '../../domain/models/net_worth_point.dart';
import '../../domain/models/transaction_context.dart';
import '../../domain/models/transaction_edit_data.dart';
import '../../domain/repositories/transaction_repository.dart';

/// Persists transactions as **balanced, atomic double-entry records**.
///
/// The repository is the single write path for the ledger: every mutation is
/// validated by [DoubleEntryEngine] and applied inside one database
/// transaction, so a crash mid-write can never leave the ledger unbalanced.
class TransactionRepositoryImpl implements TransactionRepository {
  // ignore: prefer_initializing_formals
  TransactionRepositoryImpl({required AppDatabase db}) : _db = db;

  final AppDatabase _db;

  @override
  Stream<List<FinancialTransaction>> watchAll() => _db.transactionDao
      .watchAll()
      .map((rows) => rows.map(FinancialTransaction.fromRow).toList());

  @override
  Stream<List<FinancialTransaction>> watchRecent({int limit = 50}) => _db
      .transactionDao
      .watchRecent(limit: limit)
      .map((rows) => rows.map(FinancialTransaction.fromRow).toList());

  @override
  Stream<List<FinancialTransaction>> watchForAccount(String accountId) => _db
      .transactionDao
      .watchForAccount(accountId)
      .map((rows) => rows.map(FinancialTransaction.fromRow).toList());

  @override
  Future<FinancialTransaction?> getById(String id) async {
    final row = await _db.transactionDao.getById(id);
    return row == null ? null : FinancialTransaction.fromRow(row);
  }

  @override
  Stream<List<TransactionContext>> watchAllContext() =>
      _db.transactionDao.watchAllContext();

  @override
  Stream<List<TransactionContext>> watchRecentContext({int limit = 50}) =>
      _db.transactionDao.watchRecentContext(limit: limit);

  @override
  Stream<List<TransactionContext>> watchForAccountContext(String accountId) =>
      _db.transactionDao.watchForAccountContext(accountId);

  @override
  Future<TransactionContext?> getContextById(String id) =>
      _db.transactionDao.getContextById(id);

  @override
  Future<List<MonthlyCashFlow>> monthlyCashFlow({int months = 6}) =>
      _db.transactionDao.monthlyCashFlow(months: months);

  @override
  Future<List<CategorySpend>> categorySpend({
    required DateTime from,
    required DateTime to,
  }) => _db.transactionDao.categorySpend(from: from, to: to);

  @override
  Future<List<NetWorthPoint>> netWorthTrend({int months = 12}) =>
      _db.transactionDao.netWorthTrend(months: months);

  @override
  Future<List<BalancePoint>> accountBalanceTrend(
    String accountId, {
    int months = 6,
  }) => _db.transactionDao.accountBalanceTrend(accountId, months: months);

  @override
  Future<TransactionEditData?> getEditData(String id) async {
    final row = await _db.transactionDao.getById(id);
    if (row == null) return null;
    final entries = await _db.transactionDao.entriesFor(id);
    final transaction = FinancialTransaction.fromRow(row);

    String? source;
    String? destination;
    String? category;
    for (final entry in entries) {
      switch (transaction.type) {
        case TransactionType.expense:
          if (entry.direction == LedgerDirection.debit) {
            category = entry.accountId;
          } else {
            source = entry.accountId;
          }
        case TransactionType.income:
          if (entry.direction == LedgerDirection.debit) {
            source = entry.accountId;
          } else {
            category = entry.accountId;
          }
        case TransactionType.transfer:
          if (entry.direction == LedgerDirection.debit) {
            destination = entry.accountId;
          } else {
            source = entry.accountId;
          }
        case TransactionType.refund:
          if (entry.direction == LedgerDirection.debit) {
            source = entry.accountId;
          } else {
            category = entry.accountId;
          }
        case TransactionType.adjustment || TransactionType.openingBalance:
          // Not editable through the daily form; leave pre-fill blank.
          break;
      }
    }

    return TransactionEditData(
      transaction: transaction,
      sourceAccountId: source,
      destinationAccountId: destination,
      categoryId: category,
    );
  }

  @override
  Future<FinancialTransaction> create(DraftTransaction draft) async {
    DoubleEntryEngine.validate(draft);
    await _assertAccountsMatchCurrency(draft);

    final id = IdGenerator.next();
    final now = DateTime.now();

    final transaction = _headerCompanion(
      id: id,
      draft: draft,
      createdAt: now,
      updatedAt: now,
    );
    final entries = _entryCompanions(id, draft);

    await _db.transactionDao.insertWithEntries(
      header: transaction,
      entries: entries,
    );

    return (await getById(id))!;
  }

  @override
  Future<FinancialTransaction> update(String id, DraftTransaction draft) async {
    final existing = await _db.transactionDao.getById(id);
    if (existing == null) {
      throw const NotFoundException('Transaction not found.');
    }
    DoubleEntryEngine.validate(draft);
    await _assertAccountsMatchCurrency(draft);

    final now = DateTime.now();
    final transaction = _headerCompanion(
      id: id,
      draft: draft,
      createdAt: existing.createdAt,
      updatedAt: now,
    );
    final entries = _entryCompanions(id, draft);

    await _db.transactionDao.replaceWithEntries(
      header: transaction,
      entries: entries,
    );

    return (await getById(id))!;
  }

  @override
  Future<void> delete(String id) async {
    final existing = await _db.transactionDao.getById(id);
    if (existing == null) {
      throw const NotFoundException('Transaction not found.');
    }
    await _db.transactionDao.deleteById(id);
  }

  TransactionsCompanion _headerCompanion({
    required String id,
    required DraftTransaction draft,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) {
    return TransactionsCompanion.insert(
      id: id,
      type: draft.type,
      amountMinor: draft.amountMinor,
      currencyCode: draft.currencyCode,
      occurredAt: draft.occurredAt,
      note: Value(draft.note),
      merchant: Value(draft.merchant),
      referenceNumber: Value(draft.referenceNumber),
      location: Value(draft.location),
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  List<LedgerEntriesCompanion> _entryCompanions(
    String transactionId,
    DraftTransaction draft,
  ) {
    return [
      for (final entry in draft.entries)
        LedgerEntriesCompanion.insert(
          id: IdGenerator.next(),
          transactionId: transactionId,
          accountId: entry.accountId,
          direction: entry.direction,
          amountMinor: entry.amountMinor,
          currencyCode: draft.currencyCode,
        ),
    ];
  }

  /// Every referenced account must exist, use the draft's currency, and play a
  /// semantically valid role for the transaction type.
  Future<void> _assertAccountsMatchCurrency(DraftTransaction draft) async {
    final ids = {for (final entry in draft.entries) entry.accountId}.toList();
    final accounts = await _db.accountDao.getByIds(ids);
    final byId = {for (final account in accounts) account.id: account};

    final missing = ids.where((id) => !byId.containsKey(id)).toList();
    if (missing.isNotEmpty) {
      throw NotFoundException('Unknown account(s): ${missing.join(', ')}');
    }

    for (final account in accounts) {
      if (account.currencyCode != draft.currencyCode) {
        throw ValidationException(
          'Account "${account.name}" uses ${account.currencyCode} but the '
          'transaction is in ${draft.currencyCode}.',
        );
      }
    }

    _assertSemantics(draft, byId);
  }

  /// Enforces the role each account may play for the given transaction type.
  ///
  /// The engine guarantees the ledger is *balanced*; this layer guarantees it
  /// is also *sensible* — expenses come out of real accounts into expense
  /// categories, income lands in real accounts from income categories,
  /// transfers move between real accounts only, etc. This keeps report data
  /// (Phase 6+) trustworthy by construction.
  void _assertSemantics(DraftTransaction draft, Map<String, AccountRow> byId) {
    AccountRow accountFor(String id) => byId[id]!;

    switch (draft.type) {
      case TransactionType.transfer:
        for (final entry in draft.entries) {
          if (accountFor(entry.accountId).kind != AccountKind.account) {
            throw const ValidationException(
              'A transfer must move money between real accounts.',
            );
          }
        }
      case TransactionType.income:
        for (final entry in draft.entries) {
          final account = accountFor(entry.accountId);
          if (entry.direction == LedgerDirection.credit) {
            if (account.kind != AccountKind.category ||
                account.type != AccountType.income) {
              throw const ValidationException(
                'Income must be credited to an income category.',
              );
            }
          } else if (account.kind != AccountKind.account) {
            throw const ValidationException(
              'Income must be debited into a real account.',
            );
          }
        }
      case TransactionType.expense:
        for (final entry in draft.entries) {
          final account = accountFor(entry.accountId);
          if (entry.direction == LedgerDirection.debit) {
            if (account.kind != AccountKind.category ||
                account.type != AccountType.expense) {
              throw const ValidationException(
                'Expenses must be debited to an expense category.',
              );
            }
          } else if (account.kind != AccountKind.account) {
            throw const ValidationException(
              'Expenses must be credited from a real account.',
            );
          }
        }
      case TransactionType.refund:
        for (final entry in draft.entries) {
          final account = accountFor(entry.accountId);
          if (entry.direction == LedgerDirection.debit) {
            if (account.kind != AccountKind.account) {
              throw const ValidationException(
                'A refund must debit a real account.',
              );
            }
          } else if (account.kind != AccountKind.category) {
            throw const ValidationException('A refund must credit a category.');
          }
        }
      case TransactionType.openingBalance:
        for (final entry in draft.entries) {
          if (accountFor(entry.accountId).kind == AccountKind.category) {
            throw const ValidationException(
              'An opening balance may not reference a category.',
            );
          }
        }
      case TransactionType.adjustment:
        // Balanced by construction; any combination is allowed.
        break;
    }
  }
}
