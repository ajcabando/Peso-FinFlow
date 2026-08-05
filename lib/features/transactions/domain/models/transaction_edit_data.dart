import 'financial_transaction.dart';

/// Everything the transaction form needs to pre-fill when editing an
/// existing transaction: the transaction plus the account ids involved.
class TransactionEditData {
  const TransactionEditData({
    required this.transaction,
    this.sourceAccountId,
    this.destinationAccountId,
    this.categoryId,
  });

  final FinancialTransaction transaction;

  /// The real account money moved from / into.
  final String? sourceAccountId;

  /// For transfers: the account money moved to.
  final String? destinationAccountId;

  /// For income / expense / refund: the category involved.
  final String? categoryId;
}
