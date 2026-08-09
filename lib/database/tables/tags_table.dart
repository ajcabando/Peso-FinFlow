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

  /// Operation-log CAS version (schema v5). 0 = never synced; bumped by every
  /// repository write while signed in.
  IntColumn get version => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {name},
  ];
}
