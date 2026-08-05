import '../enums/account_kind.dart';
import '../enums/account_type.dart';
import '../models/account.dart';

/// Input needed to create a new account or category.
class CreateAccountInput {
  const CreateAccountInput({
    required this.name,
    required this.type,
    required this.currencyCode,
    this.kind = AccountKind.account,
    this.institution,
    this.openingBalanceMinor = 0,
    this.colorValue,
    this.iconCode,
    this.notes,
  });

  final String name;
  final AccountType type;
  final String currencyCode;

  /// What is being created: a real [AccountKind.account] or a virtual
  /// [AccountKind.category].
  final AccountKind kind;
  final String? institution;
  final int openingBalanceMinor;
  final int? colorValue;
  final String? iconCode;
  final String? notes;
}

/// A real account paired with its current derived balance.
class AccountWithBalance {
  const AccountWithBalance({required this.account, required this.balanceMinor});

  final Account account;

  /// Balance in minor units, derived from the double-entry ledger.
  final int balanceMinor;
}

/// Contract for the account feature's data layer.
abstract interface class AccountRepository {
  Stream<List<Account>> watchAccounts();

  /// Real (non-virtual) accounts.
  Stream<List<Account>> watchRealAccounts();

  /// One-shot list of real financial accounts (no stream), used by forms to
  /// pre-compute defaults such as the next free account colour.
  Future<List<Account>> fetchRealAccounts();

  /// One-shot list of categories (no stream), used by forms to pre-compute
  /// defaults such as the next free category colour.
  Future<List<Account>> fetchCategories();

  /// Virtual income / expense categories.
  Stream<List<Account>> watchCategories();

  /// Real accounts with their current ledger-derived balances.
  Stream<List<AccountWithBalance>> watchAccountsWithBalances();

  /// Total Net Worth: the sum of every real, visible account balance.
  Stream<int> watchNetWorthMinor();

  /// The system "Opening Balances" account (created during seeding).
  Future<Account?> getOpeningBalancesAccount();

  Future<Account?> getById(String id);

  /// Creates an account and, when [input.openingBalanceMinor] is non-zero,
  /// atomically records the opening-balance ledger transaction.
  Future<Account> createAccount(CreateAccountInput input);

  Future<Account> updateAccount(Account account);

  /// Deletes an account that has no ledger entries.
  Future<void> deleteAccount(String id);
}
