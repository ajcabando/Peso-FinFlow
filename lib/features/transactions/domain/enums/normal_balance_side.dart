/// The side of the ledger on which an account records *increases*.
///
/// This is the core rule of double-entry accounting:
///
/// - **Asset-like accounts** (cash, bank, e-wallet, investments) increase on
///   the debit side — a debit makes the balance go up.
/// - **Liability-like accounts** (credit cards, loans) increase on the credit
///   side — a credit makes the balance go up.
/// - **Income categories** are credit-normal: crediting the category records
///   income earned.
/// - **Expense categories** are debit-normal: debiting the category records
///   money spent.
enum NormalBalanceSide { debit, credit }
