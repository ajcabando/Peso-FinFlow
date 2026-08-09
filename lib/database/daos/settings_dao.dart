import 'package:drift/drift.dart';

import '../../core/sync_session.dart';
import '../../features/sync/data/sync/sync_outbox_writer.dart';
import '../../features/sync/data/sync/sync_payloads.dart';
import '../app_database.dart';
import '../tables/app_settings_table.dart';

part 'settings_dao.g.dart';

/// `app_settings` keys that are device-local secrets and never leave the
/// device (e.g. the salted PIN hash).
const String kSettingsSecretPrefix = 'security.';

/// Data access for the key-value [AppSettings] store.
@DriftAccessor(tables: [AppSettings])
class SettingsDao extends DatabaseAccessor<AppDatabase>
    with _$SettingsDaoMixin {
  SettingsDao(super.db);

  /// One-shot read; returns `null` when the key is absent.
  Future<String?> get(String key) async {
    final row = await (select(
      appSettings,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  /// Reactive read of a single key.
  Stream<String?> watch(String key) =>
      (select(appSettings)..where((t) => t.key.equals(key)))
          .watchSingleOrNull()
          .map((row) => row?.value);

  /// Inserts or replaces [value] for [key], stamping the change time and the
  /// owning cloud user, and enqueues the operation-log upsert (schema v5) so
  /// the value syncs. `security.*` keys never leave the device (no op).
  Future<void> set(String key, String value) async {
    final now = DateTime.now();
    await transaction(() async {
      await into(appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(
          key: key,
          value: value,
          updatedAt: Value(now),
          userId: Value(SyncSession.instance.userId),
        ),
      );
      if (key.startsWith(kSettingsSecretPrefix)) return;
      final row = await (select(
        appSettings,
      )..where((t) => t.key.equals(key))).getSingleOrNull();
      if (row != null) {
        await SyncOutboxWriter(db: attachedDatabase).enqueueUpsert(
          entity: 'app_setting',
          entityId: key,
          payload: SyncPayloads.appSetting(row),
          updatedAt: now,
        );
      }
    });
  }

  Future<void> remove(String key) =>
      (delete(appSettings)..where((t) => t.key.equals(key))).go();
}
