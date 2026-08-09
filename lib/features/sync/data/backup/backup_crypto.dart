import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Client-side encryption for cloud backups (docs/SELF_HOSTED.md §7).
///
/// Zero-knowledge: the server only ever stores the opaque blob. The key is
/// derived from the user's backup passphrase with PBKDF2-HMAC-SHA256
/// (≥ 310k iterations, per the plan) and the snapshot is sealed with
/// AES-256-GCM using a random 12-byte nonce and the user id as
/// authenticated additional data (AAD) — a blob copied to another account
/// fails authentication.
///
/// Pure Dart (`package:cryptography`) so it runs identically on native,
/// desktop and the WASM web build.
class BackupCrypto {
  BackupCrypto({this.pbkdf2Iterations = 310000});

  /// PBKDF2 iteration count (OWASP recommends ≥ 600k for SHA-256 in 2023;
  /// 310k is the plan's floor — tune with the machine's capability in mind).
  final int pbkdf2Iterations;

  static const int _nonceLength = 12;
  static const int _saltLength = 16;

  /// Encrypts [plaintext] (the portable backup JSON) into a self-describing
  /// blob: `salt | nonce | ciphertext | mac`.
  Future<Uint8List> encrypt({
    required Uint8List plaintext,
    required String passphrase,
    required String userId,
  }) async {
    final salt = _randomBytes(_saltLength);
    final key = await _deriveKey(passphrase, salt);
    final algorithm = AesGcm.with256bits();
    final nonce = algorithm.newNonce();
    final box = await algorithm.encrypt(
      plaintext,
      secretKey: key,
      nonce: nonce,
      aad: utf8.encode(userId),
    );
    final out = BytesBuilder(copy: false);
    out.add(salt);
    out.add(box.nonce);
    out.add(box.cipherText);
    out.add(box.mac.bytes);
    return out.toBytes();
  }

  /// Decrypts a blob produced by [encrypt]. Throws
  /// [BackupDecryptionException] on wrong passphrase, tampered data or a
  /// different user id (AAD mismatch) — the caller surfaces it as "wrong
  /// passphrase or not a backup".
  Future<Uint8List> decrypt({
    required Uint8List blob,
    required String passphrase,
    required String userId,
  }) async {
    if (blob.length < _saltLength + _nonceLength + 16) {
      throw const BackupDecryptionException('Backup blob is too short.');
    }
    final salt = blob.sublist(0, _saltLength);
    final nonce = blob.sublist(_saltLength, _saltLength + _nonceLength);
    final macStart = blob.length - 16;
    final cipherText = blob.sublist(_saltLength + _nonceLength, macStart);
    final macBytes = blob.sublist(macStart);

    final key = await _deriveKey(passphrase, salt);
    try {
      final clear = await AesGcm.with256bits().decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes)),
        secretKey: key,
        aad: utf8.encode(userId),
      );
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      throw const BackupDecryptionException(
        'Wrong passphrase, or this backup was encrypted with a different account.',
      );
    } catch (_) {
      throw const BackupDecryptionException('The backup blob is malformed.');
    }
  }

  Future<SecretKey> _deriveKey(String passphrase, List<int> salt) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: pbkdf2Iterations,
      bits: 256,
    );
    return pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );
  }

  static Uint8List _randomBytes(int length) {
    final bytes = Uint8List(length);
    // Random.secure uses the platform CSPRNG (not the seeded default).
    for (var i = 0; i < length; i++) {
      bytes[i] = Random.secure().nextInt(256);
    }
    return bytes;
  }
}

/// Thrown when a backup blob cannot be decrypted.
class BackupDecryptionException implements Exception {
  const BackupDecryptionException(this.message);

  final String message;

  @override
  String toString() => message;
}
