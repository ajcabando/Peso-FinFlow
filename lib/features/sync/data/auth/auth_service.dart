import 'dart:async';

// ignore_for_file: prefer_initializing_formals

import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../sync/device_registry.dart';
import 'token_store.dart';

/// A signed-in user (from `/auth/me` or login responses).
class UserProfile {
  const UserProfile({required this.id, required this.email, required this.isVerified});

  final String id;
  final String email;
  final bool isVerified;
}

/// Authentication against the self-hosted FinFlow API
/// (`docs/BACKEND_API.md` §2): signup / login / logout / refresh / me.
///
/// On success the session ([AuthTokens]) is persisted via [TokenStore] and a
/// [Stream] notifies listeners so the sync layer can adopt + sync. Everything
/// is a no-op when no session exists; sign-out clears the store and notifies.
class AuthService {
  AuthService({
    required ApiClient api,
    required TokenStore tokenStore,
    required DeviceRegistry devices,
  }) : _api = api,
       _tokenStore = tokenStore,
       _devices = devices;

  final ApiClient _api;
  final TokenStore _tokenStore;
  final DeviceRegistry _devices;

  final _sessionController = StreamController<AuthTokens?>.broadcast();

  /// Emits the current session whenever it changes (login, refresh, logout).
  /// The initial value is emitted on first listen.
  Stream<AuthTokens?> get sessionStream async* {
    yield await _tokenStore.read();
    yield* _sessionController.stream;
  }

  /// The persisted session, or `null` when signed out.
  Future<AuthTokens?> currentSession() => _tokenStore.read();

  /// Creates an account (email/password). Returns the (possibly unverified)
  /// session when `EMAIL_VERIFICATION_REQUIRED` is off, or throws with the
  /// server message when verification is required (no session yet).
  Future<AuthTokens> signUp({required String email, required String password}) async {
    final response = await _api.post(
      '/auth/signup',
      body: {'email': email, 'password': password},
      auth: false,
    );
    final user = response['user'];
    final userId = user is Map<String, dynamic> ? user['id'] : null;
    final userEmail = user is Map<String, dynamic> ? user['email'] : email;
    if (userId is! String) {
      throw const ApiException(
        code: 'VALIDATION_FAILED',
        message: 'The server did not return a user — check your email and try again.',
      );
    }
    // Sign-up does not issue tokens. If the account needs verification, the
    // caller shows a notice; otherwise the user signs in next.
    final session = AuthTokens(
      accessToken: '',
      refreshToken: '',
      expiresIn: 0,
      userId: userId,
      email: userEmail,
    );
    return session;
  }

  /// Signs in with email/password, registering this device with the server.
  /// Persists the session and notifies listeners.
  Future<AuthTokens> signIn({required String email, required String password}) async {
    final response = await _api.post(
      '/auth/login',
      body: {
        'email': email,
        'password': password,
        'deviceId': await _devices.deviceId(),
        'deviceName': await _devices.deviceName(),
        'platform': await _devices.platform(),
        'appVersion': await _devices.appVersion(),
      },
      auth: false,
    );
    final tokens = _tokensFromLogin(response);
    await _tokenStore.write(tokens);
    _sessionController.add(tokens);
    return tokens;
  }

  /// Refreshes the access token (also rotates the refresh token). Used by
  /// [ApiClient] on 401; exposed for explicit calls.
  Future<AuthTokens?> refresh() async {
    final current = await _tokenStore.read();
    if (current == null) return null;
    try {
      final response = await _api.post(
        '/auth/refresh',
        body: {'refreshToken': current.refreshToken},
        auth: false,
      );
      final tokens = _tokensFromLogin(response);
      await _tokenStore.write(tokens);
      _sessionController.add(tokens);
      return tokens;
    } on ApiException {
      await _tokenStore.clear();
      _sessionController.add(null);
      return null;
    }
  }

  /// Fetches the current user profile from `/auth/me`. Throws on failure.
  Future<UserProfile> me() async {
    final response = await _api.get('/auth/me');
    final user = response['user'];
    if (user is! Map<String, dynamic> || user['id'] is! String) {
      throw const ApiException(
        code: 'INTERNAL',
        message: 'The server returned an unexpected profile.',
      );
    }
    return UserProfile(
      id: user['id'] as String,
      email: user['email'] as String? ?? '',
      isVerified: user['isVerified'] == true,
    );
  }

  /// Logs out: revokes the refresh token server-side and clears the local
  /// session. Best-effort — the local session is cleared even if the server
  /// is unreachable.
  Future<void> signOut() async {
    final tokens = await _tokenStore.read();
    if (tokens != null && tokens.refreshToken.isNotEmpty) {
      try {
        await _api.post(
          '/auth/logout',
          body: {'refreshToken': tokens.refreshToken},
        );
      } on ApiException {
        // Ignore — the local session is cleared regardless.
      }
    }
    await _tokenStore.clear();
    _sessionController.add(null);
  }

  AuthTokens _tokensFromLogin(Map<String, dynamic> response) {
    final access = response['accessToken'];
    final refresh = response['refreshToken'];
    final user = response['user'];
    final userId = user is Map<String, dynamic> ? user['id'] : null;
    final email = user is Map<String, dynamic> ? user['email'] : null;
    if (access is! String || refresh is! String || userId is! String) {
      throw const ApiException(
        code: 'INTERNAL',
        message: 'The server returned an unexpected login response.',
      );
    }
    return AuthTokens(
      accessToken: access,
      refreshToken: refresh,
      expiresIn: response['expiresIn'] is int ? response['expiresIn'] as int : 900,
      userId: userId,
      email: email is String ? email : '',
    );
  }
}
