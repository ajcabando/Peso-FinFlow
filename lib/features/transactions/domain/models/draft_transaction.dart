import '../enums/ledger_direction.dart';
import '../enums/transaction_type.dart';

/// A single planned line of the double-entry ledger.
///
/// [amountMinor] is always a positive integer (minor units). Direction is
/// expressed explicitly rather than as a sign so the raw accounting facts are
/// never ambiguous.
class DraftEntry {
  const DraftEntry({
    required this.accountId,
    required this.direction,
    required this.amountMinor,
  });

  /// Ledger account (real account or category) affected.
  final String accountId;

  /// Debit or credit.
  final LedgerDirection direction;

  /// Positive amount in minor units.
  final int amountMinor;
}

/// A transaction awaiting validation and persistence.
///
/// Drafts are produced by [TransactionBuilder] and consumed by
/// [TransactionRepository], which validates and stores them atomically.
class DraftTransaction {
  const DraftTransaction({
    required this.type,
    required this.occurredAt,
    required this.currencyCode,
    required this.entries,
    this.note,
    this.merchant,
    this.referenceNumber,
    this.location,
  });

  final TransactionType type;
  final DateTime occurredAt;

  /// Currency shared by every entry (validated by the engine).
  final String currencyCode;
  final List<DraftEntry> entries;
  final String? note;
  final String? merchant;
  final String? referenceNumber;
  final String? location;

  /// Primary monetary value of the transaction (sum of the debit side).
  int get amountMinor {
    var total = 0;
    for (final entry in entries) {
      if (entry.direction == LedgerDirection.debit) total += entry.amountMinor;
    }
    return total;
  }

  DraftTransaction copyWith({
    TransactionType? type,
    DateTime? occurredAt,
    String? currencyCode,
    List<DraftEntry>? entries,
    String? note,
    String? merchant,
    String? referenceNumber,
    String? location,
  }) {
    return DraftTransaction(
      type: type ?? this.type,
      occurredAt: occurredAt ?? this.occurredAt,
      currencyCode: currencyCode ?? this.currencyCode,
      entries: entries ?? this.entries,
      note: note ?? this.note,
      merchant: merchant ?? this.merchant,
      referenceNumber: referenceNumber ?? this.referenceNumber,
      location: location ?? this.location,
    );
  }
}
