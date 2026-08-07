/// Canonical, deterministic identifiers for the rows `DatabaseSeeder`
/// creates.
///
/// Every device seeds the exact same IDs, so syncing two devices never
/// produces duplicate system accounts or categories — a remote row carrying
/// the same ID merges with the local seed row instead of duplicating it.
/// Older installations (random seed IDs) are re-pointed to these canonical
/// IDs by `SeedReconciler` during the schema v4 migration.
abstract final class SeedIds {
  /// The system "Opening Balances" account.
  static const String systemAccount = '00000000-0000-4000-8000-000000000001';

  /// Deterministic ID for the [index]-th default category (0-based).
  static String category(int index) =>
      '00000000-0000-4000-8000-${(index + 2).toString().padLeft(12, '0')}';
}
