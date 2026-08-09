import 'package:drift/drift.dart';

/// Simple key-value store for app preferences (theme, default currency, ...).
/// Lives in the same encrypted local database as the financial data so a
/// single backup/restore captures everything.
@DataClassName('AppSettingRow')
class AppSettings extends Table {
  TextColumn get key => text().withLength(min: 1, max: 80)();

  TextColumn get value => text()();

  /// When the value last changed (drives cloud sync deltas).
  DateTimeColumn get updatedAt => dateTime().nullable()();

  /// Owning cloud user (null = local-only until adopted at sign-in).
  TextColumn get userId => text().nullable()();

  /// Operation-log CAS version (schema v5). 0 = never synced; bumped by every
  /// repository write while signed in.
  IntColumn get version => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {key};
}
