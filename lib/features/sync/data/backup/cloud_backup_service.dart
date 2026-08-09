// ignore_for_file: prefer_initializing_formals

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../../../../core/errors/app_exception.dart';
import '../../../../database/app_database.dart';
import '../../../backup/data/backup_service.dart';
import '../api/api_client.dart';
import 'backup_crypto.dart';

/// A cloud backup entry (metadata from `GET /backups`).
class CloudBackup {
  const CloudBackup({
    required this.id,
    required this.sizeBytes,
    required this.createdAt,
    this.deviceName,
  });

  final String id;
  final int sizeBytes;
  final DateTime createdAt;
  final String? deviceName;

  factory CloudBackup.fromJson(Map<String, dynamic> json) => CloudBackup(
    id: json['id'] as String? ?? '',
    sizeBytes: json['sizeBytes'] is int ? json['sizeBytes'] as int : 0,
    createdAt: DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
    deviceName: json['deviceName'] as String?,
  );
}

/// Client-side encrypted cloud backup (docs/SELF_HOSTED.md §7,
/// BACKEND_API.md §8).
///
/// Flow: export the local snapshot → derive a key from the passphrase →
/// AES-256-GCM encrypt → `POST /backups` (server returns a presigned PUT) →
/// upload the blob to MinIO → `PATCH { uploaded: true }`. Restore is the
/// mirror: list → presigned GET → download → decrypt → local `importBackup`.
class CloudBackupService {
  CloudBackupService({
    required ApiClient api,
    required AppDatabase db,
    BackupCrypto? crypto,
    http.Client? httpClient,
  }) : _api = api,
       _db = db,
       _crypto = crypto ?? BackupCrypto(),
       _http = httpClient ?? http.Client();

  final ApiClient _api;
  final AppDatabase _db;
  final BackupCrypto _crypto;
  final http.Client _http;

  BackupService get _backup => BackupService(db: _db);

  /// Creates an encrypted cloud backup. Throws [ValidationException] when the
  /// passphrase is empty.
  Future<CloudBackup> backup({
    required String passphrase,
    required String userId,
  }) async {
    if (passphrase.isEmpty) {
      throw const ValidationException(
        'Set a backup passphrase first — it encrypts your data before upload.',
      );
    }
    final snapshot = await _backup.exportBackup();
    final blob = await _crypto.encrypt(
      plaintext: snapshot,
      passphrase: passphrase,
      userId: userId,
    );

    // Two-step: create metadata + presigned PUT.
    final created = await _api.post(
      '/backups',
      body: {
        'sizeBytes': blob.length,
        'sha256': _sha256(blob),
      },
    );
    final backup = created['backup'];
    final uploadUrl = created['uploadUrl'];
    if (backup is! Map<String, dynamic> ||
        backup['id'] is! String ||
        uploadUrl is! String) {
      throw const DomainException(
        'The server returned an unexpected backup response.',
      );
    }
    final id = backup['id'] as String;

    // Upload the raw blob via the presigned URL (never through the API body).
    final put = await _http.put(Uri.parse(uploadUrl), body: blob);
    if (put.statusCode != 200) {
      throw DomainException(
        'Upload failed (HTTP ${put.statusCode}) — try again.',
      );
    }

    // Confirm (server stats the object before marking it uploaded).
    await _api.patch('/backups/$id', body: {'uploaded': true});
    return CloudBackup.fromJson({
      ...backup,
      'sizeBytes': blob.length,
    });
  }

  /// Lists cloud backups, newest first.
  Future<List<CloudBackup>> list() async {
    final response = await _api.get('/backups', query: {'page': '1', 'limit': '50'});
    final items = response['items'];
    if (items is! List) return const [];
    return [
      for (final item in items)
        if (item is Map<String, dynamic>) CloudBackup.fromJson(item),
    ];
  }

  /// Downloads + decrypts [id] and replaces the local database with it.
  /// Throws [BackupDecryptionException] on wrong passphrase / tampered data.
  Future<void> restore({
    required String id,
    required String passphrase,
    required String userId,
  }) async {
    if (passphrase.isEmpty) {
      throw const ValidationException('Enter your backup passphrase.');
    }
    final urlRes = await _api.get('/backups/$id/url');
    final downloadUrl = urlRes['downloadUrl'];
    if (downloadUrl is! String) {
      throw const DomainException(
        'The server did not return a download link.',
      );
    }
    final get = await _http.get(Uri.parse(downloadUrl));
    if (get.statusCode != 200) {
      throw DomainException(
        'Download failed (HTTP ${get.statusCode}) — try again.',
      );
    }
    final snapshot = await _crypto.decrypt(
      blob: get.bodyBytes,
      passphrase: passphrase,
      userId: userId,
    );
    await _backup.importBackup(snapshot);
  }

  static String _sha256(List<int> bytes) => sha256.convert(bytes).toString();
}
