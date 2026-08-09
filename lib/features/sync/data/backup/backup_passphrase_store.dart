// ignore_for_file: prefer_initializing_formals

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the cloud-backup passphrase so scheduled backups can run
/// unattended (the daily/weekly/monthly trigger fires without the user typing
/// it each time). `flutter_secure_storage` on native platforms;
/// `shared_preferences` (localStorage) on web, where the secure plugin has no
/// implementation — the same tradeoff the auth tokens make.
abstract class BackupPassphraseStore {
  Future<String?> read();
  Future<void> write(String passphrase);
  Future<void> clear();
}

/// Default store selection: secure storage on native, localStorage on web.
BackupPassphraseStore createBackupPassphraseStore() {
  if (kIsWeb) return WebBackupPassphraseStore();
  return SecureBackupPassphraseStore();
}

class SecureBackupPassphraseStore implements BackupPassphraseStore {
  SecureBackupPassphraseStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'finflow.backup.passphrase';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String passphrase) =>
      _storage.write(key: _key, value: passphrase);

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

class WebBackupPassphraseStore implements BackupPassphraseStore {
  WebBackupPassphraseStore({SharedPreferences? prefs}) : _prefs = prefs;

  static const _key = 'finflow.backup.passphrase';

  SharedPreferences? _prefs;

  Future<SharedPreferences> get _instance async =>
      _prefs ??= await SharedPreferences.getInstance();

  @override
  Future<String?> read() async => (await _instance).getString(_key);

  @override
  Future<void> write(String passphrase) async {
    await (await _instance).setString(_key, passphrase);
  }

  @override
  Future<void> clear() async {
    await (await _instance).remove(_key);
  }
}
