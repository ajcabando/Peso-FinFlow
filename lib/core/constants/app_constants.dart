/// Application-wide constants shared across all FinFlow modules.
abstract final class AppConstants {
  /// Brand / product name.
  static const String appName = 'FinFlow';

  /// Brand tagline.
  static const String tagline = 'Know Where Every Peso Goes';

  /// Default currency used for new accounts and formatting fallbacks.
  static const String defaultCurrencyCode = 'PHP';

  /// Currencies offered in pickers. New codes can be added at any time — the
  /// formatter resolves symbols and decimal digits dynamically.
  static const List<String> supportedCurrencies = [
    'PHP',
    'USD',
    'EUR',
    'GBP',
    'JPY',
    'SGD',
  ];

  /// Database file name (without extension).
  static const String databaseName = 'finflow';

  /// Name of the system "Opening Balances" account used to keep the
  /// double-entry ledger balanced when an account is opened with a
  /// non-zero starting balance.
  static const String openingBalancesAccountName = 'Opening Balances';
}
