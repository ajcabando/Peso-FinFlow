import 'package:drift/drift.dart';

/// Per-user operation-log cursors (schema v5, docs/SELF_HOSTED.md §7).
///
/// One row per cloud user who has ever synced on this device. Unlike the v4
/// DateTime watermarks (which drove the deprecated row-delta engine), these
/// are integer `seq` cursors from the operation log:
///
///  - [pushCursor]: the highest server-assigned `seq` the last push acked.
///  - [pullCursor]: the highest server-assigned `seq` applied from a pull.
///
/// A fresh account starts at 0 (push everything, pull everything); the old v4
/// watermark values are discarded on upgrade (the first op-log sync starts
/// from cursor 0 and pushes every local row as `baseVersion 0` — no data is
/// lost because the rows themselves are already in the local DB).
@DataClassName('SyncMetaRow')
class SyncMeta extends Table {
  /// Cloud user id this cursor belongs to.
  TextColumn get userId => text()();

  /// Last pushed server seq (via push acks), or `null` for a fresh account.
  IntColumn get pushCursor => integer().nullable()();

  /// Last applied server seq (via pull), or `null` for a fresh account.
  IntColumn get pullCursor => integer().nullable()();

  @override
  Set<Column> get primaryKey => {userId};
}
