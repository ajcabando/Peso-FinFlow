/// Holds the id of the currently signed-in cloud user (if any).
///
/// Repositories and DAOs read this when creating rows so every new row is
/// tagged with its owner; the cloud-sync layer updates it from the Supabase
/// auth state. `null` means "local-only" — the row will be adopted by the
/// next account that signs in on this device.
///
/// A plain mutable holder (rather than a provider) keeps the write path
/// free of Riverpod plumbing while remaining trivially testable.
class SyncSession {
  SyncSession._();

  /// The application-wide session holder.
  static final SyncSession instance = SyncSession._();

  /// Id of the currently signed-in cloud user, or `null` when local-only.
  String? userId;

  bool get signedIn => userId != null;
}
