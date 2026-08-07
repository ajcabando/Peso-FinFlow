/// The child rows of one transaction (its ledger entries and tags).
class TransactionChildren {
  const TransactionChildren({this.ledgerEntries = const [], this.transactionTags = const []});

  final List<Map<String, dynamic>> ledgerEntries;
  final List<Map<String, dynamic>> transactionTags;

  bool get isEmpty => ledgerEntries.isEmpty && transactionTags.isEmpty;
}

/// Remote (cloud) data access used by [SyncEngine].
///
/// Implementations speak to Supabase PostgREST; tests use an in-memory fake.
/// Rows are plain maps with snake_case keys matching the cloud schema.
abstract class SyncRemote {
  /// All rows in [table] whose `updated_at` is strictly after [since],
  /// newest-last. Pagination is the caller's concern ([limit] per page).
  Future<List<Map<String, dynamic>>> fetchChanged(
    String table, {
    required DateTime since,
    int limit = 1000,
  });

  /// Server-side `updated_at` for the given primary keys — used for the
  /// last-write-wins compare before pushing (never clobber a newer cloud
  /// row with a stale local one).
  Future<Map<String, DateTime>> fetchUpdatedAt(
    String table,
    List<String> ids,
  );

  /// Upserts [rows] into [table], merging on its primary key.
  Future<void> upsert(
    String table,
    List<Map<String, dynamic>> rows, {
    required String onConflict,
  });

  /// Replaces a transaction's children on the server (delete-then-insert)
  /// so the cloud ledger always mirrors the winning transaction version.
  Future<void> replaceTransactionChildren(
    String transactionId, {
    required List<Map<String, dynamic>> ledgerEntries,
    required List<Map<String, dynamic>> transactionTags,
  });

  /// All child rows belonging to [transactionIds].
  Future<Map<String, TransactionChildren>> fetchTransactionChildren(
    List<String> transactionIds,
  );
}
