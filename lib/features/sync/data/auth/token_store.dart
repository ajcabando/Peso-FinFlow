import 'dart:convert';

// ignore_for_file: prefer_initializing_formals

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The signed-in session as persisted on this device.
class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
    required this.userId,
    required this.email,
  });

  final String accessToken;
  final String refreshToken;
  final int expiresIn;

  /// Cloud user id (also stamped on synced rows via [SyncSession]).
  final String userId;
  final String email;

  Map<String, dynamic> toJson() => {
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'expiresIn': expiresIn,
    'userId': userId,
    'email': email,
  };

  static AuthTokens? tryParse(Map<String, dynamic> json) {
    final access = json['accessToken'];
    final refresh = json['refreshToken'];
    final userId = json['userId'];
    final email = json['email'];
    if (access is! String ||
        refresh is! String ||
        userId is! String ||
        email is! String) {
      return null;
    }
    return AuthTokens(
      accessToken: access,
      refreshToken: refresh,
      expiresIn: json['expiresIn'] is int ? json['expiresIn'] as int : 900,
      userId: userId,
      email: email,
    );
  }
}

/// Persists the session tokens. `flutter_secure_storage` on native platforms;
/// `shared_preferences` (localStorage) on web, where the secure plugin has no
/// implementation. Refresh tokens stay revocable server-side either way.
abstract class TokenStore {
  Future<AuthTokens?> read();
  Future<void> write(AuthTokens tokens);
  Future<void> clear();
}

/// Default store selection: secure storage on native, localStorage on web.
TokenStore createTokenStore() {
  if (kIsWeb) return WebTokenStore();
  return SecureTokenStore();
}

class SecureTokenStore implements TokenStore {
  SecureTokenStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'finflow.auth.session';

  final FlutterSecureStorage _storage;

  @override
  Future<AuthTokens?> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    try {
      return AuthTokens.tryParse(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> write(AuthTokens tokens) =>
      _storage.write(key: _key, value: jsonEncode(tokens.toJson()));

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

class WebTokenStore implements TokenStore {
  WebTokenStore({SharedPreferences? prefs}) : _prefs = prefs;

  static const _key = 'finflow.auth.session';

  SharedPreferences? _prefs;

  Future<SharedPreferences> get _instance async =>
      _prefs ??= await SharedPreferences.getInstance();

  @override
  Future<AuthTokens?> read() async {
    final raw = (await _instance).getString(_key);
    if (raw == null) return null;
    try {
      return AuthTokens.tryParse(jsonDecode(raw) as Map<String, dynamic>);
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> write(AuthTokens tokens) async {
    await (await _instance).setString(_key, jsonEncode(tokens.toJson()));
  }

  @override
  Future<void> clear() async {
    await (await _instance).remove(_key);
  }
}
