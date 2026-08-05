import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Salting + SHA-256 hashing for the app lock PIN.
///
/// Only a salted hash is ever persisted (never the raw PIN), so a database
/// backup cannot leak the lock code.
abstract final class PinService {
  /// A random 16-byte salt, hex-encoded.
  static String generateSalt() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  static String _hash(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

  /// Persisted representation: `salt:hash`.
  static String encode(String pin) {
    final salt = generateSalt();
    return '$salt:${_hash(pin, salt)}';
  }

  /// True when [pin] matches the stored [encoded] value.
  static bool verify(String pin, String encoded) {
    final separator = encoded.indexOf(':');
    if (separator <= 0 || separator == encoded.length - 1) return false;
    final salt = encoded.substring(0, separator);
    final hash = encoded.substring(separator + 1);
    return _hash(pin, salt) == hash;
  }

  /// PINs are 4–8 numeric digits.
  static bool isValid(String pin) =>
      pin.length >= 4 && pin.length <= 8 && RegExp(r'^\d+$').hasMatch(pin);
}
