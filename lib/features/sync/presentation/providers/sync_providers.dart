import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/app_providers.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/sync_session.dart';
import '../../data/api/api_client.dart';
import '../../data/auth/auth_service.dart';
import '../../data/auth/token_store.dart';
import '../../data/backup/backup_passphrase_store.dart';
import '../../data/backup/cloud_backup_service.dart';
import '../../data/sync/device_registry.dart';
import '../../data/sync/op_sync_engine.dart';
import '../../data/sync/sync_outbox_writer.dart';
import '../../domain/sync_config.dart';
import '../../domain/sync_status.dart';

/// Cloud-sync configuration (the `FINFLOW_API_URL` define; disabled when
/// absent — the app is then fully local, exactly as before).
final syncConfigProvider = Provider<SyncConfig>(
  (ref) => SyncConfig.fromEnvironment(),
);

/// Token persistence: secure storage on native, localStorage on web.
final tokenStoreProvider = Provider<TokenStore>((ref) {
  final store = createTokenStore();
  ref.onDispose(store.clear);
  return store;
});

/// The HTTP client for the self-hosted API, or `null` when not configured.
final apiClientProvider = Provider<ApiClient?>((ref) {
  final config = ref.watch(syncConfigProvider);
  if (!config.enabled) return null;
  return ApiClient(
    baseUrl: config.apiBase,
    tokenStore: ref.watch(tokenStoreProvider),
  );
});

final deviceRegistryProvider = Provider<DeviceRegistry>(
  (ref) => DeviceRegistry.instance,
);

/// Stores the cloud-backup passphrase for unattended scheduled backups
/// (secure storage on native, localStorage on web).
final backupPassphraseStoreProvider = Provider<BackupPassphraseStore>(
  (ref) => createBackupPassphraseStore(),
);

/// Encrypted cloud backup client, or `null` when sync is not configured.
final cloudBackupServiceProvider = Provider<CloudBackupService?>((ref) {
  final api = ref.watch(apiClientProvider);
  if (api == null) return null;
  return CloudBackupService(
    api: api,
    db: ref.watch(databaseProvider),
  );
});

final authServiceProvider = Provider<AuthService?>((ref) {
  final api = ref.watch(apiClientProvider);
  if (api == null) return null;
  return AuthService(
    api: api,
    tokenStore: ref.watch(tokenStoreProvider),
    devices: ref.watch(deviceRegistryProvider),
  );
});

/// Appends ops to the outbox from inside repository write transactions.
final syncOutboxWriterProvider = Provider<SyncOutboxWriter?>((ref) {
  final db = ref.watch(databaseProvider);
  return SyncOutboxWriter(db: db);
});

/// The operation-log engine, or `null` when sync is not configured.
final opSyncEngineProvider = Provider<OpSyncEngine?>((ref) {
  final api = ref.watch(apiClientProvider);
  final writer = ref.watch(syncOutboxWriterProvider);
  if (api == null || writer == null) return null;
  return OpSyncEngine(
    db: ref.watch(databaseProvider),
    api: api,
    devices: ref.watch(deviceRegistryProvider),
    outboxWriter: writer,
  );
});

/// The persisted session (tokens), emitted live as it changes.
final authSessionProvider = StreamProvider<AuthTokens?>((ref) async* {
  final auth = ref.watch(authServiceProvider);
  if (auth == null) {
    yield null;
    return;
  }
  yield* auth.sessionStream;
});

/// Sync + auth controller for the Settings sync section.
final syncControllerProvider = NotifierProvider<SyncController, SyncStatus>(
  SyncController.new,
);

class SyncController extends Notifier<SyncStatus> {
  AuthService? get _auth => ref.read(authServiceProvider);
  OpSyncEngine? get _engine => ref.read(opSyncEngineProvider);

  /// Serialises cloud-backup runs. Without this, a local write during an
  /// in-flight scheduled backup (the 2 s debounce calls the same check) would
  /// start a second concurrent export+encrypt+upload.
  bool _backupInFlight = false;

  @override
  SyncStatus build() {
    final enabled = ref.watch(syncConfigProvider).enabled;
    _loadPersistedBackupState();
    return SyncStatus(enabled: enabled);
  }

  /// Restores the persisted schedule, passphrase flag and last-run time into
  /// the status (called on provider build; fire-and-forget).
  Future<void> _loadPersistedBackupState() async {
    final dao = ref.read(settingsDaoProvider);
    final scheduleName = await dao.get('backup.schedule');
    final lastRunRaw = await dao.get('backup.lastRunAt');
    final passphrase = await ref.read(backupPassphraseStoreProvider).read();
    state = state.copyWith(
      backupSchedule: BackupSchedule.fromName(scheduleName),
      backupPassphraseSet: passphrase != null && passphrase.isNotEmpty,
      lastBackupAt: DateTime.tryParse(lastRunRaw ?? '')?.toLocal(),
    );
  }

  /// Called whenever the auth session changes (sign-in, sign-out, restore).
  Future<void> onSessionChanged(AuthTokens? session) async {
    if (session == null || session.userId.isEmpty) {
      SyncSession.instance.userId = null;
      state = state.copyWith(
        signedIn: false,
        userId: null,
        email: null,
        syncing: false,
        error: null,
        conflictNeedsAttention: false,
        devices: const [],
      );
      return;
    }
    SyncSession.instance.userId = session.userId;
    state = state.copyWith(
      signedIn: true,
      userId: session.userId,
      email: session.email,
      syncing: true,
      error: null,
      conflictNeedsAttention: false,
    );
    final engine = _engine;
    if (engine == null) {
      state = state.copyWith(syncing: false);
      return;
    }
    try {
      await engine.adoptLocalData(session.userId);
      await _runSync(engine);
    } on Exception catch (e) {
      state = state.copyWith(syncing: false, error: _message(e));
    }
  }

  /// Manually triggered sync (button, app resume, periodic timer, or a
  /// debounce after a local write).
  Future<void> syncNow() async {
    final engine = _engine;
    if (engine == null || !state.signedIn) return;
    if (state.syncing) return;
    state = state.copyWith(syncing: true, clearError: true);
    await _runSync(engine);
  }

  Future<void> _runSync(OpSyncEngine engine) async {
    final result = await engine.sync();
    state = state.copyWith(
      syncing: false,
      lastSyncedAt: result.ok ? DateTime.now() : null,
      error: result.ok ? null : result.error,
      conflictNeedsAttention: result.conflicts,
    );
    if (result.ok && state.signedIn) {
      await refreshDevices();
    }
  }

  /// Fetches the device list for the signed-in account.
  Future<void> refreshDevices() async {
    final api = ref.read(apiClientProvider);
    if (api == null || !state.signedIn) return;
    try {
      final response = await api.get('/devices');
      final list = response['devices'];
      if (list is List) {
        state = state.copyWith(
          devices: [
            for (final item in list)
              if (item is Map<String, dynamic>) CloudDevice.fromJson(item),
          ],
        );
      }
    } on Exception {
      // Non-fatal — the devices list just stays as-is.
    }
  }

  Future<void> signInWithEmail(String email, String password) async {
    final auth = _auth;
    if (auth == null) {
      throw StateError('Cloud sync is not configured for this build.');
    }
    await auth.signIn(email: email, password: password);
    // onSessionChanged fires via the session stream.
  }

  Future<void> signUp(String email, String password) async {
    final auth = _auth;
    if (auth == null) {
      throw StateError('Cloud sync is not configured for this build.');
    }
    final session = await auth.signUp(email: email, password: password);
    if (session.userId.isEmpty) return;
    // New accounts need a login round-trip to mint tokens.
    await auth.signIn(email: email, password: password);
  }

  Future<void> signOut() async {
    final auth = _auth;
    if (auth == null) return;
    await auth.signOut();
    // onSessionChanged(null) fires via the session stream.
  }

  Future<void> revokeDevice(String deviceId) async {
    final api = ref.read(apiClientProvider);
    if (api == null) return;
    await api.delete('/devices/$deviceId');
    await refreshDevices();
  }

  /// Stores the backup passphrase on this device. Required before a
  /// non-manual schedule can be enabled (scheduled backups run unattended).
  Future<void> saveBackupPassphrase(String passphrase) async {
    final trimmed = passphrase.trim();
    if (trimmed.isEmpty) {
      throw const ValidationException('Enter a backup passphrase.');
    }
    await ref.read(backupPassphraseStoreProvider).write(trimmed);
    state = state.copyWith(backupPassphraseSet: true);
  }

  /// Sets the backup schedule. Non-manual schedules throw
  /// [ValidationException] when no passphrase is stored yet — the trigger
  /// cannot run unattended without one.
  Future<void> setBackupSchedule(BackupSchedule schedule) async {
    if (schedule != BackupSchedule.manual) {
      final passphrase = await ref.read(backupPassphraseStoreProvider).read();
      if (passphrase == null || passphrase.isEmpty) {
        throw const ValidationException(
          'Set a backup passphrase first — scheduled backups run automatically.',
        );
      }
    }
    state = state.copyWith(backupSchedule: schedule);
    await ref.read(settingsDaoProvider).set('backup.schedule', schedule.name);
  }

  /// Runs a cloud backup now, persists the passphrase for future scheduled
  /// runs, and records the last-run time. Returns the created backup.
  Future<CloudBackup> backupNow({required String passphrase}) async {
    if (_backupInFlight) {
      throw StateError('A cloud backup is already running.');
    }
    final service = ref.read(cloudBackupServiceProvider);
    final userId = SyncSession.instance.userId;
    if (service == null || userId == null) {
      throw StateError('Cloud backup is not configured for this build.');
    }
    final trimmed = passphrase.trim();
    if (trimmed.isEmpty) {
      throw const ValidationException('Enter a backup passphrase.');
    }
    _backupInFlight = true;
    try {
      await ref.read(backupPassphraseStoreProvider).write(trimmed);
      final backup = await service.backup(
        passphrase: trimmed,
        userId: userId,
      );
      final now = DateTime.now();
      await ref
          .read(settingsDaoProvider)
          .set('backup.lastRunAt', now.toUtc().toIso8601String());
      state = state.copyWith(backupPassphraseSet: true, lastBackupAt: now);
      return backup;
    } finally {
      _backupInFlight = false;
    }
  }

  /// Fires the scheduled backup when it is due: signed in, a non-manual
  /// schedule, a stored passphrase, and `interval` elapsed since the last
  /// run. Failures are swallowed — the next heartbeat retries.
  Future<void> maybeRunScheduledBackup() async {
    if (_backupInFlight) return;
    final status = state;
    if (!status.signedIn) return;
    if (status.backupSchedule == BackupSchedule.manual) return;
    final store = ref.read(backupPassphraseStoreProvider);
    final passphrase = await store.read();
    if (passphrase == null || passphrase.isEmpty) return;

    final lastRaw = await ref.read(settingsDaoProvider).get('backup.lastRunAt');
    final lastRun = DateTime.tryParse(lastRaw ?? '');
    final now = DateTime.now();
    if (lastRun != null &&
        now.difference(lastRun.toLocal()) < status.backupSchedule.interval) {
      return;
    }

    final service = ref.read(cloudBackupServiceProvider);
    final userId = SyncSession.instance.userId;
    if (service == null || userId == null) return;

    // Re-check and set atomically (no await between) — the debounce can fire
    // while a scheduled backup is in flight, and both would otherwise pass
    // the due check on the stale lastRunAt.
    if (_backupInFlight) return;
    _backupInFlight = true;
    try {
      await service.backup(passphrase: passphrase, userId: userId);
      await ref
          .read(settingsDaoProvider)
          .set('backup.lastRunAt', now.toUtc().toIso8601String());
      state = state.copyWith(lastBackupAt: now);
    } on Exception {
      // Non-fatal — the next heartbeat tries again.
    } finally {
      _backupInFlight = false;
    }
  }

  static String _message(Object error) =>
      error.toString().replaceFirst('Exception: ', '');
}
