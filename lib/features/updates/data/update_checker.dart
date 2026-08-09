import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/update_info.dart';

/// Thrown when the update check cannot reach or parse the release feed.
class UpdateCheckException implements Exception {
  const UpdateCheckException(this.message);

  /// A user-facing description of the failure.
  final String message;

  @override
  String toString() => 'UpdateCheckException: $message';
}

/// Checks the public GitHub releases feed for a newer FinFlow build.
///
/// The repo is public, so the anonymous `/releases/latest` endpoint needs no
/// auth (subject to GitHub's per-IP rate limits — fine for an occasional
/// manual check from Settings).
class UpdateChecker {
  UpdateChecker({http.Client? httpClient, this.repository = kUpdateRepo})
    : _http = httpClient ?? http.Client();

  /// The public repo holding the release artifacts.
  static const String kUpdateRepo = 'ajcabando/Peso-FinFlow';

  final http.Client _http;
  final String repository;

  /// Fetches the latest release and returns [UpdateInfo] when it is newer
  /// than [currentVersion], or `null` when this build is already current.
  ///
  /// Throws [UpdateCheckException] when the feed is unreachable or malformed.
  Future<UpdateInfo?> check({required String currentVersion}) async {
    final uri = Uri.parse(
      'https://api.github.com/repos/$repository/releases/latest',
    );
    final http.Response response;
    try {
      response = await _http.get(
        uri,
        headers: const {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'Peso-FinFlow',
        },
      );
    } on Exception catch (error) {
      throw UpdateCheckException("Couldn't reach the update server: $error");
    }

    if (response.statusCode != 200) {
      throw UpdateCheckException(
        'The update server returned ${response.statusCode}.',
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const UpdateCheckException('The update server sent an odd reply.');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const UpdateCheckException('The update server sent an odd reply.');
    }

    final version = stripVersionPrefix(decoded['tag_name'] as String? ?? '');
    final url = decoded['html_url'] as String? ?? '';
    if (version.isEmpty || url.isEmpty) return null;

    if (!isNewerVersion(candidate: version, current: currentVersion)) {
      return null;
    }
    final publishedRaw = decoded['published_at'] as String?;
    return UpdateInfo(
      version: version,
      url: url,
      publishedAt: publishedRaw == null ? null : DateTime.tryParse(publishedRaw),
    );
  }

  /// True when [candidate] is strictly newer than [current] by semver
  /// (major/minor/patch). Build metadata and prefixes (`v`, `+1`) are ignored.
  static bool isNewerVersion({
    required String candidate,
    required String current,
  }) {
    final c = _parts(current);
    final n = _parts(candidate);
    for (var i = 0; i < 3; i++) {
      if (n[i] > c[i]) return true;
      if (n[i] < c[i]) return false;
    }
    return false;
  }

  /// Strips a leading `v` (e.g. `v0.2.0` → `0.2.0`).
  static String stripVersionPrefix(String version) =>
      version.replaceFirst(RegExp(r'^v'), '').trim();

  static List<int> _parts(String version) {
    final segments = stripVersionPrefix(version).split(RegExp(r'[.+_\-]'));
    return [
      for (var i = 0; i < 3; i++)
        i < segments.length ? int.tryParse(segments[i]) ?? 0 : 0,
    ];
  }
}
