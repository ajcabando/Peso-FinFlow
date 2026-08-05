import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

/// Thin wrapper around `local_auth` that degrades gracefully where
/// biometrics are unavailable (notably the web target, where the plugin has
/// no implementation).
abstract final class BiometricService {
  static final LocalAuthentication _auth = LocalAuthentication();

  /// Whether biometric hardware exists and can be checked on this platform.
  static Future<bool> isAvailable() async {
    if (kIsWeb) return false;
    try {
      return await _auth.canCheckBiometrics;
    } on Exception {
      return false;
    }
  }

  /// Prompts for a biometric unlock; true when the user authenticated.
  static Future<bool> authenticate() async {
    if (kIsWeb) return false;
    try {
      return await _auth.authenticate(
        localizedReason: 'Unlock FinFlow with your biometrics',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } on Exception {
      return false;
    }
  }
}
