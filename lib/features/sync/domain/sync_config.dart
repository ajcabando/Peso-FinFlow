/// Cloud-sync configuration for the self-hosted backend.
///
/// The API base URL comes from a build-time define so it never lives in
/// source control:
///   flutter build web --dart-define=FINFLOW_API_URL=https://api.example.com
///
/// When the define is absent (plain `flutter run` / `flutter test`) the
/// feature is gracefully disabled and the app behaves exactly as before —
/// fully local and offline. No vendor dependency.
class SyncConfig {
  const SyncConfig({required this.apiUrl});

  factory SyncConfig.fromEnvironment() =>
      SyncConfig(apiUrl: const String.fromEnvironment('FINFLOW_API_URL'));

  /// The self-hosted backend base URL (e.g. `https://api.example.com`).
  /// Empty when not configured.
  final String apiUrl;

  /// Whether cloud sync is wired up (the define is present).
  bool get enabled => apiUrl.isNotEmpty;

  /// The API base URL with the configured prefix (`/v1`), ready for calls.
  String get apiBase => enabled ? '$apiUrl/v1' : '';
}
