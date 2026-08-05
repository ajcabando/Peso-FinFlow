import 'currency_formatter.dart';

/// Parses user-typed decimal amounts (e.g. `1,234.56`) into integer minor
/// units (`123456`), and back again for form pre-filling.
///
/// This is the only place user-entered money strings become numbers, so the
/// parsing rules are consistent app-wide and covered by tests.
abstract final class MoneyInputParser {
  /// Parses [input] into minor units with [decimals] fraction digits.
  ///
  /// Accepts thousand separators (`,`) and optional decimals. Returns `null`
  /// when the input is empty or not a valid number.
  static int? parseMinor(String input, {required int decimals}) {
    final cleaned = input.trim().replaceAll(',', '');
    if (cleaned.isEmpty) return null;

    final match = RegExp(r'^(\d+)(?:\.(\d+))?$').firstMatch(cleaned);
    if (match == null) return null;

    final whole = int.parse(match.group(1)!);
    var fraction = match.group(2) ?? '';
    if (fraction.length > decimals) {
      // Round the extra digits rather than silently truncating.
      final extra = fraction.substring(decimals);
      fraction = fraction.substring(0, decimals);
      if (int.parse(extra[0]) >= 5) {
        fraction = (int.parse(fraction.isEmpty ? '0' : fraction) + 1)
            .toString()
            .padLeft(decimals, '0');
        if (fraction.length > decimals) {
          return (whole + 1) * CurrencyFormatter.pow10(decimals);
        }
      }
    }
    final fractionValue = fraction.isEmpty ? 0 : int.parse(fraction);
    return whole * CurrencyFormatter.pow10(decimals) + fractionValue;
  }

  /// Formats [minorAmount] for display in a text field.
  static String toInput(int minorAmount, {required int decimals}) {
    final negative = minorAmount < 0;
    final abs = minorAmount.abs();
    final whole = abs ~/ CurrencyFormatter.pow10(decimals);
    final fraction = (abs % CurrencyFormatter.pow10(decimals))
        .toString()
        .padLeft(decimals, '0');
    final body = decimals == 0 ? '$whole' : '$whole.$fraction';
    return negative ? '-$body' : body;
  }
}
