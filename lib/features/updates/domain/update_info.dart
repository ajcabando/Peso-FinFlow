/// A newer release published for FinFlow, as reported by the GitHub
/// releases API (`/releases/latest` on the public Peso-FinFlow repo).
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.url,
    this.publishedAt,
  });

  /// The new version without the leading `v` (e.g. `0.3.0`).
  final String version;

  /// The release page URL (opens in the browser).
  final String url;

  /// When the release was published, when the API provided it.
  final DateTime? publishedAt;
}
