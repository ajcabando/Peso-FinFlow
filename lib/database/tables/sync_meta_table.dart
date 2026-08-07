import 'package:drift/drift.dart';

/// Per-user sync watermark cursors.
///
/// One row per cloud user who has ever synced on this device. The watermarks
/// drive the delta queries: local rows with `updated_at > lastPushAt` are
/// pushed, and remote rows with `updated_at > lastPullAt` are pulled.
@DataClassName('SyncMetaRow')
class SyncMeta extends Table {
  /// Supabase auth user id this cursor belongs to.
  TextColumn get userId => text()();

  /// Local rows changed after this moment are pushed on the next sync.
  /// `null` (a fresh account) means *everything* adopted is pushed once.
  DateTimeColumn get lastPushAt => dateTime().nullable()();

  /// Remote rows changed after this moment are pulled on the next sync.
  DateTimeColumn get lastPullAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {userId};
}
