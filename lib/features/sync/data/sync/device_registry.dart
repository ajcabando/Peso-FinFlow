import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/utils/id_generator.dart';

/// Identity of this installation, as registered with the self-hosted backend
/// at login (`docs/BACKEND_API.md` §2: `deviceId`, `deviceName`, `platform`,
/// `appVersion`).
///
/// The device id is a random UUID persisted once per install — the same value
/// sent at `/auth/login` and carried on every sync op. Revoking it from
/// Settings → devices kills this device's sessions server-side.
class DeviceRegistry {
  DeviceRegistry._();

  static final DeviceRegistry instance = DeviceRegistry._();

  static const _idKey = 'finflow.device.id';
  static const _nameKey = 'finflow.device.name';

  String? _cachedId;
  String? _cachedName;

  /// The persisted install id, generating + storing one on first use.
  Future<String> deviceId() async {
    final cached = _cachedId;
    if (cached != null) return cached;
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_idKey);
    if (id == null || id.isEmpty) {
      id = IdGenerator.next();
      await prefs.setString(_idKey, id);
    }
    _cachedId = id;
    return id;
  }

  /// A human-readable device name (host name, or "FinFlow on `<platform>`").
  Future<String> deviceName() async {
    final cached = _cachedName;
    if (cached != null) return cached;
    final prefs = await SharedPreferences.getInstance();
    var name = prefs.getString(_nameKey);
    if (name == null || name.isEmpty) {
      name = await _detectName();
      await prefs.setString(_nameKey, name);
    }
    _cachedName = name;
    return name;
  }

  /// Platform string matching the API contract: android | ios | ipados |
  /// web | macos.
  Future<String> platform() async {
    if (kIsWeb) return 'web';
    try {
      final info = await DeviceInfoPlugin().deviceInfo;
      if (info is AndroidDeviceInfo) return 'android';
      if (info is IosDeviceInfo) {
        return info.systemName.toLowerCase().contains('ipad')
            ? 'ipados'
            : 'ios';
      }
      if (info is MacOsDeviceInfo) return 'macos';
      if (info is WindowsDeviceInfo) return 'windows';
      if (info is LinuxDeviceInfo) return 'linux';
    } on PlatformException {
      // Fall through to the default.
    }
    return 'ios';
  }

  /// App version from package_info (e.g. `0.2.0`), or a fallback.
  Future<String> appVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (info.version.isNotEmpty) return info.version;
    } catch (_) {
      // PackageInfo unavailable in tests/edge cases — fall back.
    }
    return '0.0.0';
  }

  Future<String> _detectName() async {
    if (kIsWeb) return 'FinFlow on web';
    try {
      final info = await DeviceInfoPlugin().deviceInfo;
      final name = switch (info) {
        AndroidDeviceInfo() =>
          '${info.model.isNotEmpty ? info.model : 'Android device'} '
              '(${info.manufacturer})',
        IosDeviceInfo() =>
          info.name.isEmpty ? 'FinFlow on ${info.systemName}' : info.name,
        MacOsDeviceInfo() => info.model,
        WindowsDeviceInfo() => 'FinFlow on Windows',
        LinuxDeviceInfo() => 'FinFlow on Linux',
        _ => 'FinFlow device',
      };
      return name.trim().isEmpty ? 'FinFlow device' : name.trim();
    } on PlatformException {
      return 'FinFlow device';
    }
  }
}
