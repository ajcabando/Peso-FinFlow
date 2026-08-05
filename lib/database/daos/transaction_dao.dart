import 'package:drift/drift.dart';

import '../../features/accounts/domain/enums/account_kind.dart';
import '../../features/accounts/domain/enums/account_type.dart';
import '../../features/transactions/domain/enums/ledger_direction.dart';
import '../../features/transactions/domain/enums/normal_balance_side.dart';
import '../../features/transactions/domain/enums/transaction_type.dart';
import '../../features/transactions/domain/models/balance_point.dart';
import '../../features/transactions/domain/models/category_spend.dart';
import '../../features/transactions/domain/models/financial_transaction.dart';
import '../../features/transactions/domain/models/monthly_cash_flow.dart';
import '../../features/transactions/domain/models/net_worth_point.dart';
import '../../features/transactions/domain/models/transaction_context.dart';
import '../app_database.dart';
import '../tables/accounts_table.dart';
import '../tables/attachments_table.dart';
import '../tables/ledger_entries_table.dart';
import '../tables/tags_table.dart';
import '../tables/transaction_tags_table.dart';
import '../tables/transactions_table.dart';

part 'transaction_dao.g.dart';

/// Data access for transactions and everything attached to them.
///
/// Writes that touch several tables (transaction + ledger entries + tags) are
/// executed **atomically inside a single database transaction** — the double-
/// entry invariant is enforced at the repository layer, but the durability of
/// the whole record is guaranteed here.
@DriftAccessor(
  tables: [
    Transactions,
    LedgerEntries,
    TransactionTags,
    Tags,
    Attachments,
    Accounts,
  ],
)
class TransactionDao extends DatabaseAccessor<AppDatabase>
    with _$TransactionDaoMixin {
  TransactionDao(super.db);

  /// Transactions joined with their account & category display names.
  ///
  /// The join yields one row per ledger entry, so results are grouped back
  /// into one [TransactionContext] per transaction. Insertion order is the
  /// query's sort order, so grouping preserves it.
  Stream<List<TransactionContext>> watchAllContext() =>
      _contextQuery().watch().map(_groupContexts);

  Stream<List<TransactionContext>> watchRecentContext({int limit = 50}) =>
      _contextQuery(limit: limit).watch().map(_groupContexts);

  Stream<List<TransactionContext>> watchForAccountContext(String accountId) {
    final query =
        select(transactions).join([
            innerJoin(
              ledgerEntries,
              ledgerEntries.transactionId.equalsExp(transactions.id),
            ),
            innerJoin(accounts, accounts.id.equalsExp(ledgerEntries.accountId)),
          ])
          ..where(ledgerEntries.accountId.equals(accountId))
          ..orderBy([
            OrderingTerm.desc(transactions.occurredAt),
            OrderingTerm.desc(transactions.createdAt),
          ]);
    return query.watch().map(_groupContexts);
  }

  Future<TransactionContext?> getContextById(String id) async {
    final query = _contextQuery()..where(transactions.id.equals(id));
    final rows = await query.get();
    final grouped = _groupContexts(rows);
    return grouped.isEmpty ? null : grouped.first;
  }

  /// Enriched transactions within the half-open range `[from, to)`, newest
  /// first (used by the reports page and exports).
  Future<List<TransactionContext>> contextsBetween({
    required DateTime from,
    required DateTime to,
  }) async {
    final query = _contextQuery()
      ..where(transactions.occurredAt.isBiggerOrEqualValue(from))
      ..where(transactions.occurredAt.isSmallerThanValue(to));
    final rows = await query.get();
    return _groupContexts(rows);
  }

  /// Every transaction, newest first (used by the full list screen).
  Stream<List<TransactionRow>> watchAll() =>
      (select(transactions)..orderBy([
            (t) => OrderingTerm.desc(t.occurredAt),
            (t) => OrderingTerm.desc(t.createdAt),
          ]))
          .watch();

  /// Most recent transactions, newest first.
  Stream<List<TransactionRow>> watchRecent({int limit = 50}) =>
      (select(transactions)
            ..orderBy([
              (t) => OrderingTerm.desc(t.occurredAt),
              (t) => OrderingTerm.desc(t.createdAt),
            ])
            ..limit(limit))
          .watch();

  /// Transactions touching [accountId], newest first.
  Stream<List<TransactionRow>> watchForAccount(String accountId) {
    final query =
        select(transactions).join([
            innerJoin(
              ledgerEntries,
              ledgerEntries.transactionId.equalsExp(transactions.id),
            ),
          ])
          ..where(ledgerEntries.accountId.equals(accountId))
          ..orderBy([
            OrderingTerm.desc(transactions.occurredAt),
            OrderingTerm.desc(transactions.createdAt),
          ]);
    return query.watch().map(
      (rows) => rows.map((r) => r.readTable(transactions)).toList(),
    );
  }

  Future<TransactionRow?> getById(String id) =>
      (select(transactions)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Ledger entries for one transaction.
  Future<List<LedgerEntryRow>> entriesFor(String transactionId) => (select(
    ledgerEntries,
  )..where((t) => t.transactionId.equals(transactionId))).get();

  /// Tags attached to one transaction.
  Future<List<TagRow>> tagsFor(String transactionId) async {
    final query =
        select(tags).join([
            innerJoin(
              transactionTags,
              transactionTags.tagId.equalsExp(tags.id),
            ),
          ])
          ..where(transactionTags.transactionId.equals(transactionId))
          ..orderBy([OrderingTerm(expression: tags.name)]);
    final rows = await query.get();
    return rows.map((r) => r.readTable(tags)).toList();
  }

  /// Monthly income vs expense for the last [months] calendar months
  /// (including the current one), oldest first. Zero-filled for months
  /// without activity so charts render continuous.
  ///
  /// Income is net credits to income categories; expense is net debits to
  /// expense categories — so refunds credited to an expense category
  /// correctly reduce that month's expense total.
  Future<List<MonthlyCashFlow>> monthlyCashFlow({int months = 6}) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month - (months - 1), 1);

    final query =
        select(ledgerEntries).join([
            innerJoin(
              transactions,
              transactions.id.equalsExp(ledgerEntries.transactionId),
            ),
            innerJoin(accounts, accounts.id.equalsExp(ledgerEntries.accountId)),
          ])
          ..where(accounts.kind.equalsValue(AccountKind.category))
          ..where(transactions.occurredAt.isBiggerOrEqualValue(start));

    final rows = await query.get();

    // Mutable per-month accumulation, keyed by 'yyyy-MM'.
    final income = <String, int>{};
    final expense = <String, int>{};
    for (final row in rows) {
      final entry = row.readTable(ledgerEntries);
      final transaction = row.readTable(transactions);
      final account = row.readTable(accounts);
      final key =
          '${transaction.occurredAt.year}-'
          '${transaction.occurredAt.month.toString().padLeft(2, '0')}';

      switch (account.type) {
        case AccountType.income:
          final delta = entry.direction == LedgerDirection.credit
              ? entry.amountMinor
              : -entry.amountMinor;
          income.update(key, (v) => v + delta, ifAbsent: () => delta);
        case AccountType.expense:
          final delta = entry.direction == LedgerDirection.debit
              ? entry.amountMinor
              : -entry.amountMinor;
          expense.update(key, (v) => v + delta, ifAbsent: () => delta);
        default:
          break;
      }
    }

    // Assemble a continuous, oldest-first series over the requested months.
    return [
      for (var i = months - 1; i >= 0; i--)
        () {
          final month = DateTime(now.year, now.month - i, 1);
          final key =
              '${month.year}-'
              '${month.month.toString().padLeft(2, '0')}';
          return MonthlyCashFlow(
            year: month.year,
            month: month.month,
            incomeMinor: income[key] ?? 0,
            expenseMinor: expense[key] ?? 0,
          );
        }(),
    ];
  }

  /// Net category activity for the half-open range `[from, to)`.
  ///
  /// Expense categories report net spending (debits minus refund credits);
  /// income categories report net earnings (credits minus refund debits).
  /// Rows are sorted by amount, largest first; categories with no net
  /// activity are omitted so charts never show zero-value slices.
  Future<List<CategorySpend>> categorySpend({
    required DateTime from,
    required DateTime to,
  }) async {
    final query =
        select(ledgerEntries).join([
            innerJoin(
              transactions,
              transactions.id.equalsExp(ledgerEntries.transactionId),
            ),
            innerJoin(accounts, accounts.id.equalsExp(ledgerEntries.accountId)),
          ])
          ..where(accounts.kind.equalsValue(AccountKind.category))
          ..where(transactions.occurredAt.isBiggerOrEqualValue(from))
          ..where(transactions.occurredAt.isSmallerThanValue(to));

    final rows = await query.get();

    final net = <String, int>{};
    final meta =
        <String, ({String name, AccountType type, int color, String? icon})>{};
    for (final row in rows) {
      final entry = row.readTable(ledgerEntries);
      final account = row.readTable(accounts);
      final delta = switch (account.type) {
        AccountType.income =>
          entry.direction == LedgerDirection.credit
              ? entry.amountMinor
              : -entry.amountMinor,
        AccountType.expense =>
          entry.direction == LedgerDirection.debit
              ? entry.amountMinor
              : -entry.amountMinor,
        _ => 0,
      };
      net.update(account.id, (v) => v + delta, ifAbsent: () => delta);
      meta[account.id] = (
        name: account.name,
        type: account.type,
        color: account.colorValue,
        icon: account.iconCode,
      );
    }

    final result = [
      for (final entry in net.entries)
        if (entry.value > 0)
          CategorySpend(
            categoryId: entry.key,
            categoryName: meta[entry.key]!.name,
            amountMinor: entry.value,
            isIncome: meta[entry.key]!.type == AccountType.income,
            colorValue: meta[entry.key]!.color,
            iconCode: meta[entry.key]!.icon,
          ),
    ]..sort((a, b) => b.amountMinor.compareTo(a.amountMinor));
    return result;
  }

  /// Net Worth at the end of each of the last [months] calendar months
  /// (including the current one), oldest first.
  ///
  /// Net Worth is derived purely from the ledger. Every debit to a real
  /// account raises net worth and every credit lowers it, so the series is
  /// simply a running sum over real-account ledger entries.
  Future<List<NetWorthPoint>> netWorthTrend({int months = 12}) async {
    // One boundary per represented month: the first instant *after* that
    // month, so a September entry lands in the point for September.
    final boundaries = _monthBoundaries(months);

    final query =
        select(ledgerEntries).join([
            innerJoin(
              transactions,
              transactions.id.equalsExp(ledgerEntries.transactionId),
            ),
            innerJoin(accounts, accounts.id.equalsExp(ledgerEntries.accountId)),
          ])
          ..where(accounts.kind.equalsValue(AccountKind.account))
          // Hidden accounts are excluded from Net Worth totals (mirrors the
          // dashboard hero) so the history chart never disagrees with it.
          ..where(accounts.isHidden.equals(false))
          ..where(transactions.occurredAt.isSmallerThanValue(boundaries.last))
          ..orderBy([OrderingTerm.asc(transactions.occurredAt)]);

    final rows = await query.get();

    return _monthlyRunningSum(
          rows: rows,
          boundaries: boundaries,
          deltaFor: (row) {
            final entry = row.readTable(ledgerEntries);
            return entry.direction == LedgerDirection.debit
                ? entry.amountMinor
                : -entry.amountMinor;
          },
        )
        .map(
          (point) => NetWorthPoint(
            year: point.year,
            month: point.month,
            netWorthMinor: point.value,
          ),
        )
        .toList();
  }

  /// Balance of [accountId] at the end of each of the last [months] calendar
  /// months (including the current one), oldest first.
  ///
  /// Mirrors [netWorthTrend] but scoped to one account and honouring its
  /// normal balance side: credit-normal accounts (credit cards, loans) trend
  /// their outstanding balance, which grows as the account is credited.
  Future<List<BalancePoint>> accountBalanceTrend(
    String accountId, {
    int months = 6,
  }) async {
    final boundaries = _monthBoundaries(months);

    final query =
        select(ledgerEntries).join([
            innerJoin(
              transactions,
              transactions.id.equalsExp(ledgerEntries.transactionId),
            ),
            innerJoin(accounts, accounts.id.equalsExp(ledgerEntries.accountId)),
          ])
          ..where(ledgerEntries.accountId.equals(accountId))
          ..where(transactions.occurredAt.isSmallerThanValue(boundaries.last))
          ..orderBy([OrderingTerm.asc(transactions.occurredAt)]);

    final rows = await query.get();

    // Debit-normal accounts (assets) rise with debits; credit-normal accounts
    // (liabilities) rise with credits.
    final debitNormal =
        rows.isEmpty ||
        rows.first.readTable(accounts).type.normalBalanceSide ==
            NormalBalanceSide.debit;

    return _monthlyRunningSum(
          rows: rows,
          boundaries: boundaries,
          deltaFor: (row) {
            final entry = row.readTable(ledgerEntries);
            final delta = entry.direction == LedgerDirection.debit
                ? entry.amountMinor
                : -entry.amountMinor;
            return debitNormal ? delta : -delta;
          },
        )
        .map(
          (point) => BalancePoint(
            year: point.year,
            month: point.month,
            balanceMinor: point.value,
          ),
        )
        .toList();
  }

  /// Windowed, filtered page of enriched transactions for the full list
  /// screen. [search] matches the merchant, note or account/category name
  /// (SQLite `LIKE` is case-insensitive); [type] narrows the type.
  Future<List<TransactionContext>> contextPage({
    required int limit,
    required int offset,
    String? search,
    TransactionType? type,
  }) async {
    final ids = await _contextPageIds(
      limit: limit,
      offset: offset,
      search: search,
      type: type,
    );
    if (ids.isEmpty) return const [];

    final rows = await (_contextQuery()..where(transactions.id.isIn(ids))).get();
    final grouped = _groupContexts(rows);
    final byId = {for (final c in grouped) c.transaction.id: c};
    // The ids are already in display order — rebuild in that exact order so
    // pagination boundaries line up between pages.
    return [
      for (final id in ids)
        if (byId.containsKey(id)) byId[id]!,
    ];
  }

  /// Reactive count of transactions matching the same filters as
  /// [contextPage]; total changes drive the list's refresh-on-write.
  Stream<int> watchContextCount({String? search, TransactionType? type}) {
    final query = selectOnly(transactions)
      ..addColumns([transactions.id.count()]);
    for (final filter in _contextFilters(search: search, type: type)) {
      query.where(filter);
    }
    // A `COUNT` without grouping always yields exactly one row.
    return query.map((row) => row.read(transactions.id.count()) ?? 0).watchSingle();
  }

  /// Ordered, windowed transaction ids matching the current filters.
  Future<List<String>> _contextPageIds({
    required int limit,
    required int offset,
    String? search,
    TransactionType? type,
  }) {
    final query = select(transactions)
      ..orderBy([
        (t) => OrderingTerm.desc(t.occurredAt),
        (t) => OrderingTerm.desc(t.createdAt),
      ])
      ..limit(limit, offset: offset);
    for (final filter in _contextFilters(search: search, type: type)) {
      query.where((_) => filter);
    }
    return query.map((row) => row.id).get();
  }

  /// Shared search + type predicates for the full-list windowed queries.
  List<Expression<bool>> _contextFilters({
    String? search,
    TransactionType? type,
  }) {
    final filters = <Expression<bool>>[];
    if (type != null) {
      filters.add(transactions.type.equalsValue(type));
    }
    final term = search?.trim();
    if (term == null || term.isEmpty) return filters;
    final pattern = '%$term%';
    final nameMatch = existsQuery(
      select(ledgerEntries).join([
        innerJoin(accounts, accounts.id.equalsExp(ledgerEntries.accountId)),
      ])
        ..where(ledgerEntries.transactionId.equalsExp(transactions.id))
        ..where(accounts.name.like(pattern)),
    );
    filters.add(
      transactions.merchant.like(pattern) |
          transactions.note.like(pattern) |
          nameMatch,
    );
    return filters;
  }

  /// First instant *after* each of the last [months] calendar months.
  static List<DateTime> _monthBoundaries(int months) {
    final now = DateTime.now();
    return [
      for (var i = months; i >= 1; i--)
        DateTime(now.year, now.month - i + 2, 1),
    ];
  }

  /// Assembles a running-sum series snapped at [boundaries] from ledger rows
  /// already ordered by transaction date (ascending). [deltaFor] yields each
  /// row's signed contribution to the running total.
  List<({int year, int month, int value})> _monthlyRunningSum({
    required List<TypedResult> rows,
    required List<DateTime> boundaries,
    required int Function(TypedResult row) deltaFor,
  }) {
    final points = <({int year, int month, int value})>[];
    var running = 0;
    var index = 0;
    for (final boundary in boundaries) {
      while (index < rows.length &&
          rows[index].readTable(transactions).occurredAt.isBefore(boundary)) {
        running += deltaFor(rows[index]);
        index++;
      }
      points.add((
        year: boundary.month == 1 ? boundary.year - 1 : boundary.year,
        month: boundary.month == 1 ? 12 : boundary.month - 1,
        value: running,
      ));
    }
    return points;
  }

  /// Base join of transactions → ledger entries → accounts, newest first.
  JoinedSelectStatement<HasResultSet, dynamic> _contextQuery({int? limit}) {
    final query =
        select(transactions).join([
          innerJoin(
            ledgerEntries,
            ledgerEntries.transactionId.equalsExp(transactions.id),
          ),
          innerJoin(accounts, accounts.id.equalsExp(ledgerEntries.accountId)),
        ])..orderBy([
          OrderingTerm.desc(transactions.occurredAt),
          OrderingTerm.desc(transactions.createdAt),
        ]);
    if (limit != null) query.limit(limit);
    return query;
  }

  /// Collapses joined rows into one [TransactionContext] per transaction,
  /// picking the first real account and the first category seen.
  List<TransactionContext> _groupContexts(List<TypedResult> rows) {
    final ordered = <String, TransactionContext>{};
    for (final row in rows) {
      final transaction = FinancialTransaction.fromRow(
        row.readTable(transactions),
      );
      final account = row.readTable(accounts);
      final existing = ordered[transaction.id];
      if (existing == null) {
        ordered[transaction.id] = TransactionContext(
          transaction: transaction,
          accountName: account.kind == AccountKind.account
              ? account.name
              : null,
          categoryName: account.kind == AccountKind.category
              ? account.name
              : null,
        );
      } else {
        if (existing.accountName == null &&
            account.kind == AccountKind.account) {
          ordered[transaction.id] = TransactionContext(
            transaction: existing.transaction,
            accountName: account.name,
            categoryName: existing.categoryName,
          );
        } else if (existing.categoryName == null &&
            account.kind == AccountKind.category) {
          ordered[transaction.id] = TransactionContext(
            transaction: existing.transaction,
            accountName: existing.accountName,
            categoryName: account.name,
          );
        }
      }
    }
    return ordered.values.toList();
  }

  /// Atomically inserts a transaction with its ledger entries and tags.
  Future<void> insertWithEntries({
    required TransactionsCompanion header,
    required List<LedgerEntriesCompanion> entries,
    List<TransactionTagsCompanion> tags = const [],
  }) async {
    await transaction(() async {
      await into(transactions).insert(header);
      await batch((b) {
        b.insertAll(ledgerEntries, entries);
        if (tags.isNotEmpty) b.insertAll(transactionTags, tags);
      });
    });
  }

  /// Atomically replaces the ledger entries & tags of an existing transaction
  /// and refreshes its header row.
  Future<void> replaceWithEntries({
    required TransactionsCompanion header,
    required List<LedgerEntriesCompanion> entries,
    List<TransactionTagsCompanion> tags = const [],
  }) async {
    await transaction(() async {
      await (update(
        transactions,
      )..where((t) => t.id.equals(header.id.value))).write(header);
      await (delete(
        ledgerEntries,
      )..where((t) => t.transactionId.equals(header.id.value))).go();
      await (delete(
        transactionTags,
      )..where((t) => t.transactionId.equals(header.id.value))).go();
      await batch((b) {
        b.insertAll(ledgerEntries, entries);
        if (tags.isNotEmpty) b.insertAll(transactionTags, tags);
      });
    });
  }

  /// Atomically removes a transaction and everything attached to it.
  Future<void> deleteById(String id) async {
    await transaction(() async {
      await (delete(
        attachments,
      )..where((t) => t.transactionId.equals(id))).go();
      await (delete(
        ledgerEntries,
      )..where((t) => t.transactionId.equals(id))).go();
      await (delete(
        transactionTags,
      )..where((t) => t.transactionId.equals(id))).go();
      await (delete(transactions)..where((t) => t.id.equals(id))).go();
    });
  }
}
