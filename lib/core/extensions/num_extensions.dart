import '../utils/currency_formatter.dart';

/// Formatting helpers for integer minor-unit amounts.
extension IntMoneyFormatting on int {
  /// Formats as `₱1,234.56`.
  String asMoney(String currencyCode) =>
      CurrencyFormatter.format(this, currencyCode);

  /// Formats with an explicit sign: `+₱500.00` / `−₱120.00`.
  String asMoneySigned(String currencyCode) =>
      CurrencyFormatter.formatSigned(this, currencyCode);

  /// Formats compactly: `₱1.2M`.
  String asMoneyCompact(String currencyCode) =>
      CurrencyFormatter.formatCompact(this, currencyCode);
}
