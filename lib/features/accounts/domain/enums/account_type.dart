import 'account_kind.dart';
import '../../../transactions/domain/enums/normal_balance_side.dart';

/// Every account type FinFlow supports.
///
/// Each type carries its accounting [normalBalanceSide] — the side of the
/// ledger on which increases are recorded. This is the information the
/// double-entry engine needs to derive correct balances for any account:
///
/// | Type            | Normal side | Effect of a debit / credit |
/// |-----------------|-------------|------------------------------|
/// | cash, bank, ... | debit       | debit ↑, credit ↓            |
/// | creditCard,loan | credit      | credit ↑, debit ↓            |
/// | income category | credit      | credit = income earned       |
/// | expense category| debit       | debit = money spent          |
enum AccountType {
  cash(
    label: 'Cash',
    kind: AccountKind.account,
    normalBalanceSide: NormalBalanceSide.debit,
  ),
  bank(
    label: 'Bank',
    kind: AccountKind.account,
    normalBalanceSide: NormalBalanceSide.debit,
  ),
  debitCard(
    label: 'Debit Card',
    kind: AccountKind.account,
    normalBalanceSide: NormalBalanceSide.debit,
  ),
  creditCard(
    label: 'Credit Card',
    kind: AccountKind.account,
    normalBalanceSide: NormalBalanceSide.credit,
  ),
  ewallet(
    label: 'E-Wallet',
    kind: AccountKind.account,
    normalBalanceSide: NormalBalanceSide.debit,
  ),
  paypal(
    label: 'PayPal',
    kind: AccountKind.account,
    normalBalanceSide: NormalBalanceSide.debit,
  ),
  crypto(
    label: 'Crypto',
    kind: AccountKind.account,
    normalBalanceSide: NormalBalanceSide.debit,
  ),
  investment(
    label: 'Investment',
    kind: AccountKind.account,
    normalBalanceSide: NormalBalanceSide.debit,
  ),
  loan(
    label: 'Loan',
    kind: AccountKind.account,
    normalBalanceSide: NormalBalanceSide.credit,
  ),
  income(
    label: 'Income',
    kind: AccountKind.category,
    normalBalanceSide: NormalBalanceSide.credit,
  ),
  expense(
    label: 'Expense',
    kind: AccountKind.category,
    normalBalanceSide: NormalBalanceSide.debit,
  ),
  openingBalance(
    label: 'Opening Balances',
    kind: AccountKind.system,
    normalBalanceSide: NormalBalanceSide.credit,
  );

  const AccountType({
    required this.label,
    required this.kind,
    required this.normalBalanceSide,
  });

  /// Human-readable name shown in the UI.
  final String label;

  /// Which [AccountKind] instances of this type belong to.
  final AccountKind kind;

  /// The ledger side on which this type records increases.
  final NormalBalanceSide normalBalanceSide;

  /// The concrete account types a user may create.
  static const List<AccountType> creatableTypes = [
    cash,
    bank,
    debitCard,
    creditCard,
    ewallet,
    paypal,
    crypto,
    investment,
    loan,
  ];
}
