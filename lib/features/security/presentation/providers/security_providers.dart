import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/app_providers.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/security/pin_service.dart';

/// The app security state: whether a PIN is set, the preference toggles and
/// whether the lock screen is currently showing.
class SecurityState {
  const SecurityState({
    this.pinHash,
    this.biometricsEnabled = false,
    this.autoLockEnabled = true,
    this.locked = false,
  });

  /// Salted PIN hash, or `null` when no lock is configured.
  final String? pinHash;

  final bool biometricsEnabled;

  /// Locks automatically when the app is backgrounded.
  final bool autoLockEnabled;

  /// True while the lock screen is shown.
  final bool locked;

  bool get hasPin => pinHash != null;

  SecurityState copyWith({
    String? pinHash,
    bool? biometricsEnabled,
    bool? autoLockEnabled,
    bool? locked,
  }) => SecurityState(
    pinHash: pinHash ?? this.pinHash,
    biometricsEnabled: biometricsEnabled ?? this.biometricsEnabled,
    autoLockEnabled: autoLockEnabled ?? this.autoLockEnabled,
    locked: locked ?? this.locked,
  );
}

/// Drives the PIN lock lifecycle and preference toggles, persisted in the
/// local settings table.
final securityControllerProvider =
    NotifierProvider<SecurityController, SecurityState>(
      SecurityController.new,
    );

class SecurityController extends Notifier<SecurityState> {
  @override
  SecurityState build() {
    final dao = ref.watch(settingsDaoProvider);
    dao.get(SettingsKeys.securityPin).then((value) {
      if (value != null) state = state.copyWith(pinHash: value);
    });
    dao.get(SettingsKeys.securityBiometrics).then((value) {
      state = state.copyWith(biometricsEnabled: value == 'true');
    });
    dao.get(SettingsKeys.securityAutoLock).then((value) {
      state = state.copyWith(autoLockEnabled: value != 'false');
    });
    return const SecurityState();
  }

  /// Sets a new lock PIN (4–8 digits), replacing any existing one.
  Future<void> setPin(String pin) async {
    if (!PinService.isValid(pin)) {
      throw const ValidationException('The PIN must be 4–8 digits.');
    }
    final encoded = PinService.encode(pin);
    await ref
        .read(settingsDaoProvider)
        .set(SettingsKeys.securityPin, encoded);
    state = state.copyWith(pinHash: encoded, locked: false);
  }

  /// Removes the lock entirely.
  Future<void> removePin() async {
    await ref.read(settingsDaoProvider).remove(SettingsKeys.securityPin);
    state = state.copyWith(pinHash: null, locked: false);
  }

  /// Verifies [pin] against the stored hash; unlocks on success.
  Future<bool> verifyPin(String pin) async {
    final current = state.pinHash;
    if (current == null) return false;
    final ok = PinService.verify(pin, current);
    if (ok) state = state.copyWith(locked: false);
    return ok;
  }

  /// Shows the lock screen (no-op when no PIN is set).
  void lock() {
    if (state.hasPin) state = state.copyWith(locked: true);
  }

  void unlock() => state = state.copyWith(locked: false);

  Future<void> setBiometricsEnabled(bool enabled) async {
    await ref.read(settingsDaoProvider).set(
      SettingsKeys.securityBiometrics,
      enabled ? 'true' : 'false',
    );
    state = state.copyWith(biometricsEnabled: enabled);
  }

  Future<void> setAutoLock(bool enabled) async {
    await ref.read(settingsDaoProvider).set(
      SettingsKeys.securityAutoLock,
      enabled ? 'true' : 'false',
    );
    state = state.copyWith(autoLockEnabled: enabled);
  }
}
