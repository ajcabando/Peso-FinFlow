import 'package:drift/drift.dart';

/// User-defined tags (e.g. `work`, `family`) attachable to transactions.
@DataClassName('TagRow')
class Tags extends Table {
  TextColumn get id => text()();

  TextColumn get name => text().withLength(min: 1, max: 60)();

  /// ARGB colour, optional.
  IntColumn get colorValue => integer().nullable()();

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime().nullable()();

  /// Owning cloud user (null = local-only until adopted at sign-in).
  TextColumn get userId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {name},
  ];
}
