/// Lifecycle state of an account.
enum AccountStatus {
  /// Visible and usable in transactions.
  active,

  /// Hidden from default lists but kept for history.
  archived,

  /// Permanently closed (kept for records).
  closed,
}

extension AccountStatusX on AccountStatus {
  String get label => switch (this) {
    AccountStatus.active => 'Active',
    AccountStatus.archived => 'Archived',
    AccountStatus.closed => 'Closed',
  };
}
