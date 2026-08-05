import 'dart:async';

import 'package:drift/drift.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/utils/id_generator.dart';
import '../../../../database/app_database.dart';
import '../../../../database/daos/ledger_dao.dart';
import '../../../transactions/domain/enums/normal_balance_side.dart';
import '../../domain/enums/account_type.dart';
import '../../../transactions/domain/engine/transaction_builder.dart';
import '../../../transactions/domain/repositories/transaction_repository.dart';
import '../../domain/enums/account_kind.dart';
import '../../domain/enums/account_status.dart';
import '../../domain/models/account.dart';
import '../../domain/repositories/account_repository.dart';

/// Account feature data layer.
///
/// Creating an account with a non-zero opening balance atomically writes the
/// account row **and** the corresponding opening-balance ledger transaction,
/// so the double-entry ledger stays balanced from the very first record.
class AccountRepositoryImpl implements AccountRepository {
  AccountRepositoryImpl({
    required this.db,
    required this.transactionRepository,
  });

  final AppDatabase db;
  final TransactionRepository transactionRepository;

  @override
  Stream<List<Account>> watchAccounts() =>
      db.accountDao.watchAccounts().map(_toAccounts);

  @override
  Stream<List<Account>> watchRealAccounts() =>
      db.accountDao.watchRealAccounts().map(_toAccounts);

  @override
  Future<List<Account>> fetchRealAccounts() async {
    final rows = await (db.select(
      db.accounts,
    )..where((t) => t.kind.equalsValue(AccountKind.account))).get();
    return rows.map(Account.fromRow).toList();
  }

  @override
  Future<List<Account>> fetchCategories() async {
    final rows = await (db.select(
      db.accounts,
    )..where((t) => t.kind.equalsValue(AccountKind.category))).get();
    return rows.map(Account.fromRow).toList();
  }

  @override
  Stream<List<Account>> watchCategories() =>
      db.accountDao.watchCategories().map(_toAccounts);

  @override
  Stream<List<AccountWithBalance>> watchAccountsWithBalances() {
    final accounts$ = db.accountDao.watchRealAccounts();
    final sums$ = db.ledgerDao.watchSumsByAccount();
    return _mergeLatest(accounts$, sums$).map((combined) {
      final (rows, sums) = combined;
      return [
        for (final row in rows)
          AccountWithBalance(
            account: Account.fromRow(row),
            balanceMinor: _balanceFor(row, sums[row.id]),
          ),
      ];
    });
  }

  @override
  Stream<int> watchNetWorthMinor() => watchAccountsWithBalances().map((list) {
    var total = 0;
    for (final entry in list) {
      if (entry.account.isHidden) continue;
      // Net Worth = assets − liabilities. Debit-normal accounts are
      // assets (add); credit-normal accounts (credit cards, loans) are
      // liabilities (subtract).
      final balance = entry.balanceMinor;
      total += entry.account.normalBalanceSide == NormalBalanceSide.debit
          ? balance
          : -balance;
    }
    return total;
  });

  @override
  Future<Account?> getOpeningBalancesAccount() async {
    final row = await db.accountDao.getOpeningBalancesAccount();
    return row == null ? null : Account.fromRow(row);
  }

  @override
  Future<Account?> getById(String id) async {
    final row = await db.accountDao.getById(id);
    return row == null ? null : Account.fromRow(row);
  }

  @override
  Future<Account> createAccount(CreateAccountInput input) async {
    if (input.name.trim().isEmpty) {
      throw const ValidationException('Account name is required.');
    }

    final isCategory = input.kind == AccountKind.category;
    if (isCategory) {
      if (input.type != AccountType.income &&
          input.type != AccountType.expense) {
        throw const ValidationException(
          'A category must be an income or expense category.',
        );
      }
      if (input.openingBalanceMinor != 0) {
        throw const ValidationException(
          'Categories cannot have an opening balance.',
        );
      }
    }

    final now = DateTime.now();
    final id = IdGenerator.next();
    // Distinct colour per kind: categories pick from the category pool,
    // accounts from the account pool, so new rows never all render as the
    // same hard-coded brand purple.
    final existing = isCategory
        ? await fetchCategories()
        : await fetchRealAccounts();
    final color = input.colorValue ??
        (isCategory
            ? Account.dynamicColorValue(existing)
            : await _nextDynamicColor());

    await db.transaction(() async {
      await db.accountDao.insert(
        AccountsCompanion.insert(
          id: id,
          name: input.name.trim(),
          institution: Value(input.institution),
          kind: input.kind,
          type: input.type,
          status: AccountStatus.active,
          openingBalanceMinor: input.openingBalanceMinor,
          currencyCode: input.currencyCode,
          colorValue: color,
          iconCode: Value(input.iconCode),
          notes: Value(input.notes),
          sortOrder: 0,
          // Categories are virtual ledger accounts, not real financial
          // accounts: keep them out of account-style surfaces, matching the
          // seeded categories.
          isHidden: isCategory,
          createdAt: now,
          updatedAt: now,
        ),
      );

      final opening = input.openingBalanceMinor;
      if (opening != 0 && !isCategory) {
        final openingAccount = await getOpeningBalancesAccount();
        if (openingAccount == null) {
          throw const DatabaseException(
            'The Opening Balances account is missing from the database.',
          );
        }
        await transactionRepository.create(
          TransactionBuilder.openingBalance(
            occurredAt: now,
            currencyCode: input.currencyCode,
            accountId: id,
            openingBalancesAccountId: openingAccount.id,
            amountMinor: opening.abs(),
            accountNormalSide: input.type.normalBalanceSide,
          ),
        );
      }
    });

    return (await getById(id))!;
  }

  @override
  Future<Account> updateAccount(Account account) async {
    final existing = await getById(account.id);
    if (existing == null) {
      throw const NotFoundException('Account not found.');
    }
    if (existing.currencyCode != account.currencyCode ||
        existing.type != account.type) {
      final entryCount = await db.accountDao.countLedgerEntries(account.id);
      if (entryCount > 0) {
        throw const DomainException(
          'Type and currency cannot be changed on an account that already '
          'has transaction history.',
        );
      }
    }
    await db.accountDao.updateAccount(
      AccountsCompanion(
        id: Value(account.id),
        name: Value(account.name),
        institution: Value(account.institution),
        type: Value(account.type),
        status: Value(account.status),
        currencyCode: Value(account.currencyCode),
        colorValue: Value(account.colorValue),
        iconCode: Value(account.iconCode),
        notes: Value(account.notes),
        sortOrder: Value(account.sortOrder),
        isHidden: Value(account.isHidden),
        updatedAt: Value(DateTime.now()),
      ),
    );
    return (await getById(account.id))!;
  }

  @override
  Future<void> deleteAccount(String id) async {
    final existing = await getById(id);
    if (existing == null) {
      throw const NotFoundException('Account not found.');
    }
    final entryCount = await db.accountDao.countLedgerEntries(id);
    if (entryCount > 0) {
      throw const DomainException(
        'This account has transactions on record and cannot be deleted. '
        'Archive it instead to keep your history intact.',
      );
    }
    await db.accountDao.deleteById(id);
  }

  /// Auto-assigns a distinct palette colour for real accounts: when the
  /// caller did not pick one, the least-used colour among existing accounts
  /// wins, so new accounts never all render as the same brand purple.
  /// (Categories resolve their colour from the category pool in
  /// [createAccount].)
  Future<int> _nextDynamicColor() async {
    final existing = await fetchRealAccounts();
    return Account.dynamicColorValue(existing);
  }

  int _balanceFor(AccountRow row, LedgerSums? sums) {
    final s = sums ?? const LedgerSums(debit: 0, credit: 0);
    return switch (row.type.normalBalanceSide) {
      NormalBalanceSide.debit => s.debit - s.credit,
      NormalBalanceSide.credit => s.credit - s.debit,
    };
  }

  List<Account> _toAccounts(List<AccountRow> rows) =>
      rows.map(Account.fromRow).toList();

  /// Re-emits a pair whenever either source stream emits, using the latest
  /// value of the other. Emits only after both sources have produced once.
  static Stream<(List<AccountRow>, Map<String, LedgerSums>)> _mergeLatest(
    Stream<List<AccountRow>> accounts,
    Stream<Map<String, LedgerSums>> sums,
  ) async* {
    var latestAccounts = <AccountRow>[];
    var latestSums = <String, LedgerSums>{};
    var hasAccounts = false;
    var hasSums = false;

    final controller =
        StreamController<(List<AccountRow>, Map<String, LedgerSums>)>();
    final accountSub = accounts.listen((value) {
      latestAccounts = value;
      hasAccounts = true;
      if (hasSums) controller.add((latestAccounts, latestSums));
    });
    final sumsSub = sums.listen((value) {
      latestSums = value;
      hasSums = true;
      if (hasAccounts) controller.add((latestAccounts, latestSums));
    });

    await for (final value in controller.stream) {
      yield value;
    }
    await accountSub.cancel();
    await sumsSub.cancel();
    await controller.close();
  }
}
