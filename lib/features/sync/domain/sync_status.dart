/// The current cloud-sync state, as surfaced in Settings.
class SyncStatus {
  const SyncStatus({
    required this.enabled,
    this.signedIn = false,
    this.userId,
    this.email,
    this.syncing = false,
    this.lastSyncedAt,
    this.error,
  });

  /// Whether Supabase credentials are compiled in (`SUPABASE_URL` /
  /// `SUPABASE_ANON_KEY` dart-defines).
  final bool enabled;

  final bool signedIn;
  final String? userId;

  /// Email or phone of the signed-in user, for display.
  final String? email;

  final bool syncing;
  final DateTime? lastSyncedAt;
  final String? error;

  SyncStatus copyWith({
    bool? enabled,
    bool? signedIn,
    String? userId,
    String? email,
    bool? syncing,
    DateTime? lastSyncedAt,
    String? error,
    bool clearError = false,
  }) {
    return SyncStatus(
      enabled: enabled ?? this.enabled,
      signedIn: signedIn ?? this.signedIn,
      userId: userId ?? this.userId,
      email: email ?? this.email,
      syncing: syncing ?? this.syncing,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      error: clearError ? null : (error ?? this.error),
    );
  }
}
