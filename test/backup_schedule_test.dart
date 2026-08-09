import 'package:drift/native.dart';
import 'package:finflow/app/providers/app_providers.dart';
import 'package:finflow/core/errors/app_exception.dart';
import 'package:finflow/database/app_database.dart';
import 'package:finflow/features/sync/data/auth/token_store.dart';
import 'package:finflow/features/sync/data/backup/backup_passphrase_store.dart';
import 'package:finflow/features/sync/data/backup/cloud_backup_service.dart';
import 'package:finflow/features/sync/domain/sync_status.dart';
import 'package:finflow/features/sync/presentation/providers/sync_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory passphrase store (flutter_secure_storage has no test impl).
class FakePassphraseStore implements BackupPassphraseStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String passphrase) async => value = passphrase;

  @override
  Future<void> clear() async => value = null;
}

/// Records backup calls without touching the network.
class FakeCloudBackupService implements CloudBackupService {
  int backupCalls = 0;

  @override
  Future<CloudBackup> backup({
    required String passphrase,
    required String userId,
  }) async {
    backupCalls++;
    return CloudBackup(
      id: 'backup-$backupCalls',
      sizeBytes: 1234,
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<void> restore({
    required String id,
    required String passphrase,
    required String userId,
  }) async {}

  @override
  Future<List<CloudBackup>> list() async => const [];
}

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late FakePassphraseStore passphrases;
  late FakeCloudBackupService backups;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    passphrases = FakePassphraseStore();
    backups = FakeCloudBackupService();
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        backupPassphraseStoreProvider.overrideWithValue(passphrases),
        cloudBackupServiceProvider.overrideWithValue(backups),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(db.close);
  });

  /// First read builds the controller and kicks off the async restore of the
  /// persisted schedule/passphrase state; give it a beat to settle.
  Future<SyncController> controller() async {
    container.read(syncControllerProvider);
    final controller = container.read(syncControllerProvider.notifier);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    return controller;
  }

  Future<void> signIn() async {
    await container.read(syncControllerProvider.notifier).onSessionChanged(
      const AuthTokens(
        accessToken: 'access',
        refreshToken: 'refresh',
        expiresIn: 3600,
        userId: 'test-user',
        email: 'test@finflow.dev',
      ),
    );
  }

  Future<void> setLastRun(DateTime time) async {
    await container
        .read(settingsDaoProvider)
        .set('backup.lastRunAt', time.toUtc().toIso8601String());
  }

  test('non-manual schedule is rejected until a passphrase is stored',
      () async {
    final sync = await controller();

    await expectLater(
      sync.setBackupSchedule(BackupSchedule.daily),
      throwsA(isA<ValidationException>()),
    );
    expect(
      container.read(syncControllerProvider).backupSchedule,
      BackupSchedule.manual,
    );
    expect(passphrases.value, isNull);
  });

  test('saveBackupPassphrase persists (trimmed) and flips the flag', () async {
    final sync = await controller();

    await sync.saveBackupPassphrase(' s3cret ');

    expect(passphrases.value, 's3cret');
    expect(container.read(syncControllerProvider).backupPassphraseSet, isTrue);

    await expectLater(
      sync.saveBackupPassphrase('   '),
      throwsA(isA<ValidationException>()),
    );
  });

  test('schedule is persisted to app_settings once a passphrase is set',
      () async {
    final sync = await controller();
    await sync.saveBackupPassphrase('s3cret');

    await sync.setBackupSchedule(BackupSchedule.weekly);

    expect(
      container.read(syncControllerProvider).backupSchedule,
      BackupSchedule.weekly,
    );
    expect(await container.read(settingsDaoProvider).get('backup.schedule'),
        'weekly');
  });

  test('backupNow persists the passphrase and records the last run', () async {
    await signIn();
    final sync = await controller();

    final backup = await sync.backupNow(passphrase: 's3cret');

    expect(backup.id, 'backup-1');
    expect(backups.backupCalls, 1);
    expect(passphrases.value, 's3cret');
    final status = container.read(syncControllerProvider);
    expect(status.backupPassphraseSet, isTrue);
    expect(status.lastBackupAt, isNotNull);
    expect(
      await container.read(settingsDaoProvider).get('backup.lastRunAt'),
      isNotNull,
    );
  });

  test('due scheduled backup fires and records the run', () async {
    await signIn();
    final sync = await controller();
    await sync.saveBackupPassphrase('s3cret');
    await sync.setBackupSchedule(BackupSchedule.daily);
    await setLastRun(DateTime.now().subtract(const Duration(days: 2)));

    await sync.maybeRunScheduledBackup();

    expect(backups.backupCalls, 1);
    expect(container.read(syncControllerProvider).lastBackupAt, isNotNull);
  });

  test('scheduled backup is skipped when not yet due', () async {
    await signIn();
    final sync = await controller();
    await sync.saveBackupPassphrase('s3cret');
    await sync.setBackupSchedule(BackupSchedule.daily);
    await setLastRun(DateTime.now());

    await sync.maybeRunScheduledBackup();

    expect(backups.backupCalls, 0);
  });

  test('manual schedule never fires automatically', () async {
    await signIn();
    final sync = await controller();
    await sync.saveBackupPassphrase('s3cret');
    // Schedule stays manual by default; last run is long past.
    await setLastRun(DateTime.now().subtract(const Duration(days: 30)));

    await sync.maybeRunScheduledBackup();

    expect(backups.backupCalls, 0);
  });

  test('scheduled backup is skipped while signed out', () async {
    final sync = await controller();
    await sync.saveBackupPassphrase('s3cret');
    await sync.setBackupSchedule(BackupSchedule.daily);
    await setLastRun(DateTime.now().subtract(const Duration(days: 2)));

    await sync.maybeRunScheduledBackup();

    expect(backups.backupCalls, 0);
  });
}
