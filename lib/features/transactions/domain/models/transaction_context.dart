import 'financial_transaction.dart';

/// A transaction enriched with the display names of the accounts and
/// categories it touches — everything a list row or detail page needs
/// without extra queries.
class TransactionContext {
  const TransactionContext({
    required this.transaction,
    this.accountName,
    this.categoryName,
  });

  final FinancialTransaction transaction;
  final String? accountName;
  final String? categoryName;

  /// The title of the counterpart account, falling back to the category.
  String get counterpartName => accountName ?? categoryName ?? '';
}
