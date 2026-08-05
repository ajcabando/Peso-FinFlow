/// Broad classification of an account in the FinFlow ledger.
///
/// - [account]: a real, on-budget financial account (cash, bank, credit card,
///   e-wallet, ...). These contribute to Net Worth.
/// - [category]: a virtual income/expense category. Categories live in the
///   same ledger as accounts so that income & spending can be computed with
///   the very same double-entry rules.
/// - [system]: infrastructure accounts maintained by FinFlow itself (e.g.
///   the "Opening Balances" counterpart used to keep the ledger balanced).
enum AccountKind { account, category, system }

extension AccountKindX on AccountKind {
  /// True for accounts that are not real financial accounts.
  bool get isVirtual => this != AccountKind.account;

  /// Human-readable label.
  String get label => switch (this) {
    AccountKind.account => 'Account',
    AccountKind.category => 'Category',
    AccountKind.system => 'System',
  };
}
