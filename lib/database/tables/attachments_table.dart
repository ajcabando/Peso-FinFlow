import 'package:drift/drift.dart';

import 'transactions_table.dart';

/// Receipts, photos and documents attached to a transaction.
@DataClassName('AttachmentRow')
class Attachments extends Table {
  TextColumn get id => text()();

  TextColumn get transactionId =>
      text().references(Transactions, #id, onDelete: KeyAction.cascade)();

  /// Local file path (or blob URL on the web).
  TextColumn get filePath => text()();

  /// e.g. `image/jpeg`, `application/pdf`.
  TextColumn get mimeType => text().nullable()();

  IntColumn get fileSizeBytes => integer().nullable()();

  TextColumn get caption => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
