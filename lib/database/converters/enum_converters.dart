import 'package:drift/drift.dart';

/// A [TypeConverter] that stores enums by their stable `.name` value.
///
/// Names are used instead of indices so that inserting a new enum value never
/// corrupts previously stored rows.
class EnumNameConverter<T extends Enum> extends TypeConverter<T, String> {
  const EnumNameConverter(this.values);

  /// All values of the enum, used to look names up.
  final List<T> values;

  @override
  T fromSql(String fromDb) => values.byName(fromDb);

  @override
  String toSql(T value) => value.name;
}

/// Helper so table definitions stay terse:
/// `text().map(enumNameConverter(AccountKind.values))`.
TypeConverter<T, String> enumNameConverter<T extends Enum>(List<T> values) =>
    EnumNameConverter<T>(values);
