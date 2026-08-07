/// Cloud-sync configuration.
///
/// Credentials come from build-time defines so the anon key never lives in
/// source control:
///   flutter build web --dart-define=SUPABASE_URL=... \
///                     --dart-define=SUPABASE_ANON_KEY=...
///
/// When the defines are absent (plain `flutter run` / `flutter test`) the
/// feature is gracefully disabled and the app behaves exactly as before —
/// fully local and offline.
class SyncConfig {
  const SyncConfig({required this.supabaseUrl, required this.supabaseAnonKey});

  factory SyncConfig.fromEnvironment() => SyncConfig(
    supabaseUrl: const String.fromEnvironment('SUPABASE_URL'),
    supabaseAnonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
  );

  final String supabaseUrl;
  final String supabaseAnonKey;

  /// Whether cloud sync is wired up (both defines present).
  bool get enabled => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
