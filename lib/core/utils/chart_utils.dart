import 'currency_formatter.dart';

/// Shared helpers for the dashboard chart widgets.
///
/// Charts plot amounts in major units (e.g. `1234.50`) while the domain
/// models store minor units (e.g. `123450`); [`forCurrency`] yields the
/// multiplier that converts one to the other for a given currency.
class ChartUtils {
  ChartUtils._();

  /// Multiplier that converts a minor-unit amount to major units for
  /// [currencyCode] (e.g. 100 for a 2-decimal currency).
  static double forCurrency(String currencyCode) => CurrencyFormatter.pow10(
    CurrencyFormatter.decimalDigits(currencyCode),
  ).toDouble();

  static const List<String> _monthNames = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// Short name for a 1-based calendar [month] (1 = January).
  static String monthName(int month) {
    assert(month >= 1 && month <= 12, 'month must be 1..12, got $month');
    return _monthNames[month - 1];
  }
}
