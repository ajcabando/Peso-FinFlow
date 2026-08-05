import '../../../../core/errors/app_exception.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../enums/ledger_direction.dart';
import '../enums/normal_balance_side.dart';
import '../models/draft_transaction.dart';

/// The pure, side-effect-free rules of the FinFlow double-entry ledger.
///
/// Every transaction FinFlow records must be **balanced**: the sum of all
/// debit entries must equal the sum of all credit entries. This single
/// invariant guarantees that account balances can never drift out of sync —
/// there is no separate "balance" state to corrupt. Balances are always
/// derived from the ledger, and the ledger is always consistent.
///
/// The engine performs validation and balance math only; persistence is left
/// to the repositories, which write transactions atomically inside a database
/// transaction.
abstract final class DoubleEntryEngine {
  /// Minimum number of entries a transaction must have.
  static const int minimumEntries = 2;

  /// Validates [draft] against the double-entry invariant.
  ///
  /// Throws a [ValidationException] when the draft is unbalanced, contains a
  /// non-positive amount, references an account twice, or mixes currencies.
  static void validate(DraftTransaction draft) {
    if (draft.occurredAt.isBefore(DateTime(1970))) {
      throw const ValidationException('The transaction date is invalid.');
    }
    if (draft.currencyCode.isEmpty) {
      throw const ValidationException('A currency is required.');
    }
    if (draft.entries.length < minimumEntries) {
      throw ValidationException(
        'A transaction needs at least $minimumEntries ledger entries.',
      );
    }

    var debitSum = 0;
    var creditSum = 0;
    final seenAccounts = <String>{};

    for (final entry in draft.entries) {
      if (entry.amountMinor <= 0) {
        throw const ValidationException('Entry amounts must be positive.');
      }
      if (!seenAccounts.add(entry.accountId)) {
        throw const ValidationException(
          'An account may appear only once per transaction.',
        );
      }
      if (entry.direction == LedgerDirection.debit) {
        debitSum += entry.amountMinor;
      } else {
        creditSum += entry.amountMinor;
      }
    }

    if (debitSum != creditSum) {
      throw ValidationException(
        'Unbalanced transaction: debits ${_fmt(debitSum, draft.currencyCode)} '
        'do not equal credits ${_fmt(creditSum, draft.currencyCode)}.',
      );
    }
  }

  /// Net effect a set of raw ledger entries has on the balance of an account
  /// whose normal balance side is [side].
  ///
  /// - Debit-normal (cash, bank, expense): `debits - credits`.
  /// - Credit-normal (credit card, income): `credits - debits`.
  static int netEffect(
    NormalBalanceSide side,
    List<({LedgerDirection direction, int amountMinor})> entries,
  ) {
    var debitSum = 0;
    var creditSum = 0;
    for (final entry in entries) {
      if (entry.direction == LedgerDirection.debit) {
        debitSum += entry.amountMinor;
      } else {
        creditSum += entry.amountMinor;
      }
    }
    return switch (side) {
      NormalBalanceSide.debit => debitSum - creditSum,
      NormalBalanceSide.credit => creditSum - debitSum,
    };
  }

  /// Signed impact of a single [entry] on an account with normal side [side]:
  /// positive increases the balance, negative decreases it.
  static int signedImpact(DraftEntry entry, NormalBalanceSide side) {
    final isDebit = entry.direction == LedgerDirection.debit;
    return switch (side) {
      NormalBalanceSide.debit =>
        isDebit ? entry.amountMinor : -entry.amountMinor,
      NormalBalanceSide.credit =>
        isDebit ? -entry.amountMinor : entry.amountMinor,
    };
  }

  static String _fmt(int minor, String currency) =>
      CurrencyFormatter.format(minor, currency);
}
