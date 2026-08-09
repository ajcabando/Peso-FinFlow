import 'package:drift/drift.dart';

/// The local operation-log outbox (schema v5, docs/SELF_HOSTED.md §6-7).
///
/// Every repository write to a synced table, when a user is signed in, also
/// appends one row here (inside the same DB transaction as the write). The
/// row mirrors the wire envelope from `docs/BACKEND_API.md` §4: on the next
/// sync the engine flushes the outbox to `POST /sync/push`, and applied ops
/// are deleted (acknowledged).
///
/// DELETE ops are written by the per-table SQLite `AFTER DELETE` triggers
/// (see `AppDatabase._createOutboxTriggers`), so any hard delete of a synced
/// row — no matter which code path did it — becomes a delete op. The trigger
/// computes `base_version`/`version` from the row's `version` column.
@DataClassName('SyncOutboxRow')
class SyncOutbox extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Client-generated operation id (idempotency key on the server).
  TextColumn get opId => text()();

  /// Singular wire entity name: account | transaction | bill | budget |
  /// tag | app_setting.
  TextColumn get entity => text().withLength(min: 1, max: 40)();

  /// Client row id of the entity (opaque text; the server's current-state
  /// primary key is `(user_id, entity_id)`).
  TextColumn get entityId => text().withLength(min: 1, max: 255)();

  /// Stamped by the engine at flush time (the device that authored the op);
  /// the trigger leaves it null.
  TextColumn get deviceId => text().nullable()();

  /// upsert | delete
  TextColumn get operation => text().withLength(min: 1, max: 10)();

  /// The version this edit was based on (CAS guard).
  IntColumn get baseVersion => integer()();

  /// The version this edit produces (base + 1).
  IntColumn get version => integer()();

  /// Full entity row, JSON-encoded snake_case (null for deletes).
  TextColumn get payload => text().nullable()();

  DateTimeColumn get updatedAt => dateTime()();

  DateTimeColumn get deletedAt => dateTime().nullable()();

  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {opId},
  ];
}
