import 'package:drift/drift.dart';

import 'tags_table.dart';
import 'transactions_table.dart';

/// Many-to-many link between transactions and tags.
@DataClassName('TransactionTagRow')
class TransactionTags extends Table {
  TextColumn get transactionId =>
      text().references(Transactions, #id, onDelete: KeyAction.cascade)();

  TextColumn get tagId =>
      text().references(Tags, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {transactionId, tagId};
}
