import 'package:drift/drift.dart';

/// Records rows that were hard-deleted locally so the deletion can still be
/// pushed to the cloud and applied on other devices.
///
/// Rows are written by SQLite `AFTER DELETE` triggers (see `AppDatabase`) —
/// every deletion of a synced row, no matter which code path did it, leaves a
/// tombstone here. Tombstones are pruned once they have been pushed.
@DataClassName('SyncTombstoneRow')
class SyncTombstones extends Table {
  /// The table the row lived in, e.g. `accounts` or `transactions`.
  TextColumn get sourceTable => text().withLength(min: 1, max: 60)();

  /// Primary key value of the deleted row (account id, transaction id, ...).
  TextColumn get rowId => text()();

  /// Owning user at the time of deletion; only synced rows get tombstones.
  TextColumn get userId => text().nullable()();

  /// The deleted row's `updated_at` — the moment the row's final state
  /// became "deleted", used for last-write-wins ordering.
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {sourceTable, rowId};
}
