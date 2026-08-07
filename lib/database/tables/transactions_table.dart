import 'package:drift/drift.dart';

import '../../features/transactions/domain/enums/transaction_type.dart';
import '../converters/enum_converters.dart';

/// The business-facing view of a financial event.
///
/// The accounting reality lives in `ledger_entries`; this table stores the
/// presentation-level facts (when, what, notes, merchant) plus the primary
/// amount for quick display and filtering.
@DataClassName('TransactionRow')
@TableIndex(name: 'idx_transactions_occurred_at', columns: {#occurredAt})
@TableIndex(name: 'idx_transactions_merchant', columns: {#merchant})
class Transactions extends Table {
  TextColumn get id => text()();

  TextColumn get type =>
      text().map(enumNameConverter(TransactionType.values))();

  /// Primary display amount in minor units (always positive).
  IntColumn get amountMinor => integer()();

  TextColumn get currencyCode => text()();

  /// The moment the transaction happened (date + time).
  DateTimeColumn get occurredAt => dateTime()();

  TextColumn get note => text().nullable()();

  TextColumn get merchant => text().nullable()();

  TextColumn get referenceNumber => text().nullable()();

  TextColumn get location => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();

  /// Owning cloud user (null = local-only until adopted at sign-in).
  TextColumn get userId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
