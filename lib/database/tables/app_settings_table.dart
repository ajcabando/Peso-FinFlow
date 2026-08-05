import 'package:drift/drift.dart';

/// Simple key-value store for app preferences (theme, default currency, ...).
/// Lives in the same encrypted local database as the financial data so a
/// single backup/restore captures everything.
@DataClassName('AppSettingRow')
class AppSettings extends Table {
  TextColumn get key => text().withLength(min: 1, max: 80)();

  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
