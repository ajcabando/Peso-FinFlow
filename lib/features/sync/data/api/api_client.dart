import 'dart:convert';

// ignore_for_file: prefer_initializing_formals

import 'package:http/http.dart' as http;

import '../auth/token_store.dart';
import 'api_exception.dart';

/// Thin JSON HTTP client for the self-hosted FinFlow API.
///
/// Responsibilities (docs/BACKEND_API.md §0-1):
///  - attaches the bearer access token from [TokenStore],
///  - on `401 UNAUTHORIZED` refreshes the access token once and retries the
///    original request (a single retry — a second 401 means the session is
///    really gone),
///  - maps non-2xx responses to [ApiException] via the uniform error
///    envelope, and transport failures to a network [ApiException].
class ApiClient {
  ApiClient({
    required this.baseUrl,
    required TokenStore tokenStore,
    http.Client? httpClient,
    DateTime Function()? clock,
  })  : _tokenStore = tokenStore,
        _http = httpClient ?? http.Client(),
        _clock = clock ?? DateTime.now;

  /// Base URL including the API prefix, e.g. `https://api.example.com/v1`.
  final String baseUrl;

  final TokenStore _tokenStore;
  final http.Client _http;
  final DateTime Function() _clock;

  bool _refreshing = false;

  /// True when the last response invalidated the session (a failed refresh),
  /// so callers can surface "sign in again" and stop background sync.
  bool sessionInvalidated = false;

  /// GET with optional query parameters. Returns the decoded JSON body.
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? query,
    bool auth = true,
  }) async {
    final uri = Uri.parse('$baseUrl$path').replace(
      queryParameters: query == null || query.isEmpty ? null : query,
    );
    final response = await _sendWithRetry(
      () async =>
          _http.get(uri, headers: await _headers(auth: auth)),
    );
    return _decode(response);
  }

  /// POST a JSON body; `204` returns an empty map.
  Future<Map<String, dynamic>> post(
    String path, {
    Object? body,
    bool auth = true,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final response = await _sendWithRetry(
      () async => _http.post(
        uri,
        headers: await _headers(auth: auth),
        body: body == null ? null : jsonEncode(body),
      ),
    );
    return _decode(response);
  }

  /// PATCH a JSON body; `204` returns an empty map.
  Future<Map<String, dynamic>> patch(
    String path, {
    Object? body,
    bool auth = true,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final response = await _sendWithRetry(
      () async => _http.patch(
        uri,
        headers: await _headers(auth: auth),
        body: body == null ? null : jsonEncode(body),
      ),
    );
    return _decode(response);
  }

  /// DELETE; `204` returns an empty map.
  Future<Map<String, dynamic>> delete(
    String path, {
    bool auth = true,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final response = await _sendWithRetry(
      () async =>
          _http.delete(uri, headers: await _headers(auth: auth)),
    );
    return _decode(response);
  }

  Future<Map<String, String>> _headers({required bool auth}) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (auth) {
      final tokens = await _tokenStore.read();
      if (tokens != null) {
        headers['Authorization'] = 'Bearer ${tokens.accessToken}';
      }
    }
    return headers;
  }

  /// Runs [send]; on a 401 with an available refresh token, refreshes once
  /// and retries. A failed refresh invalidates the session (the store is
  /// cleared by the caller on sign-out; here we only flag it).
  Future<http.Response> _sendWithRetry(
    Future<http.Response> Function() send,
  ) async {
    var response = await _guard(send);
    if (response.statusCode != 401) return response;
    final refreshed = await _tryRefresh();
    if (!refreshed) {
      sessionInvalidated = true;
      return response;
    }
    return _guard(send);
  }

  /// Serialises refresh attempts so concurrent requests only trigger one.
  Future<bool> _tryRefresh() async {
    if (_refreshing) {
      // Another in-flight request is refreshing; wait for it to finish, then
      // assume success (the caller retries with the new token).
      var waited = 0;
      while (_refreshing && waited < 50) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        waited++;
      }
      return !_refreshing;
    }
    _refreshing = true;
    try {
      final tokens = await _tokenStore.read();
      if (tokens == null) return false;
      final response = await _guard(
        () => _http.post(
          Uri.parse('$baseUrl/auth/refresh'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'refreshToken': tokens.refreshToken}),
        ),
      );
      if (response.statusCode != 200) return false;
      final body = _decode(response);
      final accessToken = body['accessToken'];
      final refreshToken = body['refreshToken'];
      if (accessToken is! String || refreshToken is! String) return false;
      await _tokenStore.write(
        AuthTokens(
          accessToken: accessToken,
          refreshToken: refreshToken,
          expiresIn: body['expiresIn'] is int ? body['expiresIn'] as int : 900,
          userId: tokens.userId,
          email: tokens.email,
        ),
      );
      return true;
    } on ApiException {
      return false;
    } finally {
      _refreshing = false;
    }
  }

  /// Runs [send] and maps transport failures to a network [ApiException].
  Future<http.Response> _guard(
    Future<http.Response> Function() send,
  ) async {
    try {
      return await send();
    } on ApiException {
      rethrow;
    } catch (error) {
      throw ApiException.network(error);
    }
  }

  /// Decodes a 2xx JSON body; throws [ApiException] for anything else.
  Map<String, dynamic> _decode(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return const {};
      final decoded = jsonDecode(response.body);
      return decoded is Map<String, dynamic> ? decoded : const {};
    }
    throw ApiException.fromResponse(response);
  }

  /// Best-effort current time (used to stamp local ops before a sync).
  DateTime now() => _clock().toUtc();
}
