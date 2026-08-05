import '../enums/ledger_direction.dart';
import '../enums/normal_balance_side.dart';
import '../enums/transaction_type.dart';
import '../models/draft_transaction.dart';

/// Convenience factories that turn everyday financial events into balanced
/// double-entry drafts.
///
/// The mapping rules are:
///
/// - **Expense / credit-card purchase**: debit the expense category, credit
///   the account the money came from.
/// - **Income / refund**: debit the destination account, credit the income
///   category.
/// - **Transfer / credit-card payment**: debit the destination account,
///   credit the source account — no category involved, so no income or
///   expense is ever recorded for a transfer.
/// - **Opening balance**: paired with the system "Opening Balances" account
///   so the ledger stays balanced when an account starts with money in it.
abstract final class TransactionBuilder {
  /// An expense paid from [fromAccountId], categorised under [categoryId].
  static DraftTransaction expense({
    required DateTime occurredAt,
    required String currencyCode,
    required String fromAccountId,
    required String categoryId,
    required int amountMinor,
    String? note,
    String? merchant,
    String? referenceNumber,
    String? location,
  }) {
    return DraftTransaction(
      type: TransactionType.expense,
      occurredAt: occurredAt,
      currencyCode: currencyCode,
      note: note,
      merchant: merchant,
      referenceNumber: referenceNumber,
      location: location,
      entries: [
        DraftEntry(
          accountId: categoryId,
          direction: LedgerDirection.debit,
          amountMinor: amountMinor,
        ),
        DraftEntry(
          accountId: fromAccountId,
          direction: LedgerDirection.credit,
          amountMinor: amountMinor,
        ),
      ],
    );
  }

  /// Income received into [toAccountId], categorised under [categoryId].
  static DraftTransaction income({
    required DateTime occurredAt,
    required String currencyCode,
    required String toAccountId,
    required String categoryId,
    required int amountMinor,
    String? note,
    String? merchant,
    String? referenceNumber,
    String? location,
  }) {
    return DraftTransaction(
      type: TransactionType.income,
      occurredAt: occurredAt,
      currencyCode: currencyCode,
      note: note,
      merchant: merchant,
      referenceNumber: referenceNumber,
      location: location,
      entries: [
        DraftEntry(
          accountId: toAccountId,
          direction: LedgerDirection.debit,
          amountMinor: amountMinor,
        ),
        DraftEntry(
          accountId: categoryId,
          direction: LedgerDirection.credit,
          amountMinor: amountMinor,
        ),
      ],
    );
  }

  /// A transfer of funds between two real accounts. Records no income and no
  /// expense — money simply moves.
  static DraftTransaction transfer({
    required DateTime occurredAt,
    required String currencyCode,
    required String fromAccountId,
    required String toAccountId,
    required int amountMinor,
    String? note,
    String? merchant,
    String? referenceNumber,
    String? location,
  }) {
    return DraftTransaction(
      type: TransactionType.transfer,
      occurredAt: occurredAt,
      currencyCode: currencyCode,
      note: note,
      merchant: merchant,
      referenceNumber: referenceNumber,
      location: location,
      entries: [
        DraftEntry(
          accountId: toAccountId,
          direction: LedgerDirection.debit,
          amountMinor: amountMinor,
        ),
        DraftEntry(
          accountId: fromAccountId,
          direction: LedgerDirection.credit,
          amountMinor: amountMinor,
        ),
      ],
    );
  }

  /// A purchase on a credit card — identical to an expense: the card balance
  /// (a liability, credit-normal) increases, and the category records the
  /// spending.
  static DraftTransaction creditCardPurchase({
    required DateTime occurredAt,
    required String currencyCode,
    required String creditCardAccountId,
    required String categoryId,
    required int amountMinor,
    String? note,
    String? merchant,
    String? referenceNumber,
    String? location,
  }) {
    return expense(
      occurredAt: occurredAt,
      currencyCode: currencyCode,
      fromAccountId: creditCardAccountId,
      categoryId: categoryId,
      amountMinor: amountMinor,
      note: note,
      merchant: merchant,
      referenceNumber: referenceNumber,
      location: location,
    );
  }

  /// Paying down a credit card from a bank account. A transfer that reduces
  /// the liability — never double-counted as an expense.
  static DraftTransaction creditCardPayment({
    required DateTime occurredAt,
    required String currencyCode,
    required String bankAccountId,
    required String creditCardAccountId,
    required int amountMinor,
    String? note,
  }) {
    return transfer(
      occurredAt: occurredAt,
      currencyCode: currencyCode,
      fromAccountId: bankAccountId,
      toAccountId: creditCardAccountId,
      amountMinor: amountMinor,
      note: note,
    );
  }

  /// A refund returning money to [toAccountId] under [categoryId].
  ///
  /// Money flows back: the account is debited and the category credited
  /// (which *reduces* recorded spending for an expense category). Typed as a
  /// refund, never as income, so reports treat it correctly.
  static DraftTransaction refund({
    required DateTime occurredAt,
    required String currencyCode,
    required String toAccountId,
    required String categoryId,
    required int amountMinor,
    String? note,
  }) {
    return DraftTransaction(
      type: TransactionType.refund,
      occurredAt: occurredAt,
      currencyCode: currencyCode,
      note: note,
      entries: [
        DraftEntry(
          accountId: toAccountId,
          direction: LedgerDirection.debit,
          amountMinor: amountMinor,
        ),
        DraftEntry(
          accountId: categoryId,
          direction: LedgerDirection.credit,
          amountMinor: amountMinor,
        ),
      ],
    );
  }

  /// Opens [accountId] with [amountMinor] of starting money, balanced against
  /// the system "Opening Balances" account [openingBalancesAccountId].
  ///
  /// Asset-like accounts (debit-normal) start with a debit; liability-like
  /// accounts (credit-normal, e.g. an outstanding loan balance) start with a
  /// credit.
  static DraftTransaction openingBalance({
    required DateTime occurredAt,
    required String currencyCode,
    required String accountId,
    required String openingBalancesAccountId,
    required int amountMinor,
    required NormalBalanceSide accountNormalSide,
  }) {
    final isDebitNormal = accountNormalSide == NormalBalanceSide.debit;
    return DraftTransaction(
      type: TransactionType.openingBalance,
      occurredAt: occurredAt,
      currencyCode: currencyCode,
      note: 'Opening balance',
      entries: [
        DraftEntry(
          accountId: accountId,
          direction: isDebitNormal
              ? LedgerDirection.debit
              : LedgerDirection.credit,
          amountMinor: amountMinor,
        ),
        DraftEntry(
          accountId: openingBalancesAccountId,
          direction: isDebitNormal
              ? LedgerDirection.credit
              : LedgerDirection.debit,
          amountMinor: amountMinor,
        ),
      ],
    );
  }
}
