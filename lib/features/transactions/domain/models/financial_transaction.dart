import '../../../../database/app_database.dart';
import '../enums/transaction_type.dart';

/// Business-facing view of a recorded transaction.
///
/// The accounting truth lives in the ledger entries; this model carries the
/// presentation-level facts for lists, filters and forms.
class FinancialTransaction {
  const FinancialTransaction({
    required this.id,
    required this.type,
    required this.amountMinor,
    required this.currencyCode,
    required this.occurredAt,
    required this.createdAt,
    required this.updatedAt,
    this.note,
    this.merchant,
    this.referenceNumber,
    this.location,
  });

  factory FinancialTransaction.fromRow(TransactionRow row) =>
      FinancialTransaction(
        id: row.id,
        type: row.type,
        amountMinor: row.amountMinor,
        currencyCode: row.currencyCode,
        occurredAt: row.occurredAt,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
        note: row.note,
        merchant: row.merchant,
        referenceNumber: row.referenceNumber,
        location: row.location,
      );

  final String id;
  final TransactionType type;
  final int amountMinor;
  final String currencyCode;
  final DateTime occurredAt;
  final String? note;
  final String? merchant;
  final String? referenceNumber;
  final String? location;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Primary display title: merchant, note, or a generic label.
  String get title {
    if (merchant != null && merchant!.isNotEmpty) return merchant!;
    if (note != null && note!.isNotEmpty) return note!;
    return type.label;
  }
}
