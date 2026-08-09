import 'dart:convert';
import 'dart:typed_data';

import 'package:finflow/features/sync/data/backup/backup_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// Round-trip + tamper tests for the zero-knowledge backup encryption
/// (`BackupCrypto`, AES-256-GCM + PBKDF2-HMAC-SHA256).
void main() {
  // Tests use a low iteration count so the suite stays fast; the production
  // default (310k) is exercised implicitly via the constructor default.
  final crypto = BackupCrypto(pbkdf2Iterations: 1000);

  final snapshot = utf8.encode(
    jsonEncode({
      'format': 'finflow-backup',
      'version': 1,
      'accounts': [
        {'id': 'a1', 'name': 'BDO'},
      ],
    }),
  );

  test('round-trips a snapshot with the same passphrase + user', () async {
    final blob = await crypto.encrypt(
      plaintext: Uint8List.fromList(snapshot),
      passphrase: 'correct horse battery staple',
      userId: 'user-1',
    );

    final clear = await crypto.decrypt(
      blob: blob,
      passphrase: 'correct horse battery staple',
      userId: 'user-1',
    );
    expect(jsonDecode(utf8.decode(clear))['accounts'][0]['name'], 'BDO');
  });

  test('blobs are non-deterministic (random salt + nonce)', () async {
    final a = await crypto.encrypt(
      plaintext: Uint8List.fromList(snapshot),
      passphrase: 'pw',
      userId: 'user-1',
    );
    final b = await crypto.encrypt(
      plaintext: Uint8List.fromList(snapshot),
      passphrase: 'pw',
      userId: 'user-1',
    );
    expect(a, isNot(equals(b)));
  });

  test('wrong passphrase fails authentication', () async {
    final blob = await crypto.encrypt(
      plaintext: Uint8List.fromList(snapshot),
      passphrase: 'right',
      userId: 'user-1',
    );
    expect(
      () => crypto.decrypt(
        blob: blob,
        passphrase: 'wrong',
        userId: 'user-1',
      ),
      throwsA(isA<BackupDecryptionException>()),
    );
  });

  test('a blob from another account fails authentication (AAD)', () async {
    final blob = await crypto.encrypt(
      plaintext: Uint8List.fromList(snapshot),
      passphrase: 'pw',
      userId: 'user-1',
    );
    expect(
      () => crypto.decrypt(
        blob: blob,
        passphrase: 'pw',
        userId: 'user-2',
      ),
      throwsA(isA<BackupDecryptionException>()),
    );
  });

  test('tampered ciphertext fails authentication', () async {
    final blob = await crypto.encrypt(
      plaintext: Uint8List.fromList(snapshot),
      passphrase: 'pw',
      userId: 'user-1',
    );
    final tampered = Uint8List.fromList(blob);
    tampered[tampered.length ~/ 2] ^= 0x01; // flip one ciphertext bit
    expect(
      () => crypto.decrypt(
        blob: tampered,
        passphrase: 'pw',
        userId: 'user-1',
      ),
      throwsA(isA<BackupDecryptionException>()),
    );
  });

  test('truncated blobs are rejected up front', () async {
    expect(
      () => crypto.decrypt(
        blob: Uint8List.fromList([1, 2, 3]),
        passphrase: 'pw',
        userId: 'user-1',
      ),
      throwsA(isA<BackupDecryptionException>()),
    );
  });
}
