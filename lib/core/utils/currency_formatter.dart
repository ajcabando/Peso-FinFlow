/// Formats integer "minor unit" amounts (e.g. `12345` → `₱123.45`) for any
/// supported currency.
///
/// All monetary values in FinFlow are stored as **integer minor units** to
/// avoid floating-point rounding errors. This formatter is the single place
/// that knows how to display them, including per-currency decimal digits
/// (JPY has none, BHD has three) and symbols.
abstract final class CurrencyFormatter {
  /// Decimal digits per ISO 4217 currency code. Currencies absent from this
  /// map default to two digits.
  static const Map<String, int> _decimalDigits = {
    'JPY': 0,
    'KRW': 0,
    'VND': 0,
    'CLP': 0,
    'ISK': 0,
    'BHD': 3,
    'IQD': 3,
    'JOD': 3,
    'KWD': 3,
    'LYD': 3,
    'OMR': 3,
    'TND': 3,
  };

  /// Symbol per ISO 4217 currency code. Currencies absent from this map fall
  /// back to the plain code prefix (e.g. `AED 100.00`).
  static const Map<String, String> _symbols = {
    'PHP': '₱',
    'USD': r'$',
    'CAD': r'$',
    'AUD': r'$',
    'NZD': r'$',
    'SGD': r'$',
    'HKD': r'$',
    'EUR': '€',
    'GBP': '£',
    'JPY': '¥',
    'CNY': '¥',
    'KRW': '₩',
    'INR': '₹',
  };

  /// Number of decimal digits used by [currencyCode].
  static int decimalDigits(String currencyCode) =>
      _decimalDigits[currencyCode] ?? 2;

  /// Display symbol (or code prefix) for [currencyCode].
  static String symbolFor(String currencyCode) =>
      _symbols[currencyCode] ?? '$currencyCode ';

  /// Formats [minorAmount] as `₱1,234.56`.
  static String format(int minorAmount, String currencyCode) {
    final digits = decimalDigits(currencyCode);
    final symbol = symbolFor(currencyCode);
    final negative = minorAmount < 0;
    final abs = minorAmount.abs();

    final whole = abs ~/ pow10(digits);
    final fraction = digits == 0
        ? ''
        : '.${(abs % pow10(digits)).toString().padLeft(digits, '0')}';
    final sign = negative ? '-' : '';
    return '$sign$symbol${_groupThousands(whole)}$fraction';
  }

  /// Formats [minorAmount] with an explicit sign for the *largest* unit,
  /// e.g. `+₱500.00` / `−₱120.00`. Used for income / expense flows.
  static String formatSigned(int minorAmount, String currencyCode) {
    if (minorAmount == 0) return format(0, currencyCode);
    final sign = minorAmount > 0 ? '+' : '−';
    return '$sign${format(minorAmount.abs(), currencyCode)}';
  }

  /// Compact format for large dashboard numbers: `₱1.2M`, `₱850K`.
  static String formatCompact(int minorAmount, String currencyCode) {
    final digits = decimalDigits(currencyCode);
    final divisor = pow10(digits);
    final value = minorAmount / divisor;
    final symbol = symbolFor(currencyCode);

    String body;
    final abs = value.abs();
    if (abs >= 1000000000) {
      body = '${(value / 1000000000).toStringAsFixed(2)}B';
    } else if (abs >= 1000000) {
      body = '${(value / 1000000).toStringAsFixed(2)}M';
    } else if (abs >= 1000) {
      body = '${(value / 1000).toStringAsFixed(2)}K';
    } else {
      return format(minorAmount, currencyCode);
    }
    return '$symbol$body';
  }

  /// Returns `10` raised to [exponent].
  static int pow10(int exponent) {
    var result = 1;
    for (var i = 0; i < exponent; i++) {
      result *= 10;
    }
    return result;
  }

  static String _groupThousands(int value) {
    final digits = value.toString();
    if (digits.length <= 3) return digits;
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }
}
