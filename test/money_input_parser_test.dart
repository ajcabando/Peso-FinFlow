import 'package:flutter_test/flutter_test.dart';

import 'package:finflow/core/utils/money_input_parser.dart';

void main() {
  group('MoneyInputParser.parseMinor', () {
    test('parses whole and decimal amounts into minor units', () {
      expect(MoneyInputParser.parseMinor('1234', decimals: 2), 123400);
      expect(MoneyInputParser.parseMinor('1,234.56', decimals: 2), 123456);
      // Fraction digits map directly to minor units (no zero-padding):
      // '1234.5' is 1234.05, while '1234.50' is 1234.50.
      expect(MoneyInputParser.parseMinor('1234.5', decimals: 2), 123405);
      expect(MoneyInputParser.parseMinor('1234.50', decimals: 2), 123450);
    });

    test('rounds extra fraction digits', () {
      expect(MoneyInputParser.parseMinor('0.007', decimals: 2), 1);
      expect(MoneyInputParser.parseMinor('0.004', decimals: 2), 0);
      expect(MoneyInputParser.parseMinor('9.996', decimals: 2), 1000);
    });

    test('returns null for empty or invalid input', () {
      expect(MoneyInputParser.parseMinor('', decimals: 2), isNull);
      expect(MoneyInputParser.parseMinor('abc', decimals: 2), isNull);
    });
  });

  group('MoneyInputParser.toInput', () {
    test('formats minor units back to decimal strings', () {
      expect(MoneyInputParser.toInput(123456, decimals: 2), '1234.56');
      expect(MoneyInputParser.toInput(1000, decimals: 3), '1.000');
      expect(MoneyInputParser.toInput(5, decimals: 0), '5');
    });
  });

  group('MoneyInputParser round-trip', () {
    test('parse then format preserves the amount', () {
      for (final amount in [0, 1, 999, 123456, 123456789]) {
        final parsed = MoneyInputParser.parseMinor(
          MoneyInputParser.toInput(amount, decimals: 2),
          decimals: 2,
        );
        expect(parsed, amount);
      }
    });
  });
}
