import 'package:finflow/core/utils/currency_formatter.dart';
import 'package:finflow/core/utils/money_input_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CurrencyFormatter', () {
    test('formats PHP with peso sign and thousands separators', () {
      expect(CurrencyFormatter.format(0, 'PHP'), '₱0.00');
      expect(CurrencyFormatter.format(12345, 'PHP'), '₱123.45');
      expect(CurrencyFormatter.format(1234567, 'PHP'), '₱12,345.67');
    });

    test('handles negative amounts', () {
      expect(CurrencyFormatter.format(-50000, 'PHP'), '-₱500.00');
    });

    test('zero-decimal currencies omit the fraction', () {
      expect(CurrencyFormatter.format(12345, 'JPY'), '¥12,345');
    });

    test('three-decimal currencies keep three digits', () {
      expect(CurrencyFormatter.format(123456, 'BHD'), 'BHD 123.456');
    });

    test('signed formatting', () {
      expect(CurrencyFormatter.formatSigned(50000, 'PHP'), '+₱500.00');
      expect(CurrencyFormatter.formatSigned(-12000, 'PHP'), '−₱120.00');
    });

    test('compact formatting for large numbers', () {
      expect(CurrencyFormatter.formatCompact(250000000, 'PHP'), '₱2.50M');
      expect(CurrencyFormatter.formatCompact(85000000, 'PHP'), '₱850.00K');
      expect(CurrencyFormatter.formatCompact(99900, 'PHP'), '₱999.00');
    });
  });

  group('MoneyInputParser', () {
    test('parses whole and decimal input into minor units', () {
      expect(MoneyInputParser.parseMinor('123', decimals: 2), 12300);
      expect(MoneyInputParser.parseMinor('123.45', decimals: 2), 12345);
      expect(MoneyInputParser.parseMinor('1,234.56', decimals: 2), 123456);
    });

    test('rounds excess decimal digits', () {
      expect(MoneyInputParser.parseMinor('1.235', decimals: 2), 124);
      expect(MoneyInputParser.parseMinor('1.234', decimals: 2), 123);
    });

    test('returns null for invalid or empty input', () {
      expect(MoneyInputParser.parseMinor('', decimals: 2), isNull);
      expect(MoneyInputParser.parseMinor('abc', decimals: 2), isNull);
      expect(MoneyInputParser.parseMinor('1.2.3', decimals: 2), isNull);
      expect(MoneyInputParser.parseMinor('-5', decimals: 2), isNull);
    });

    test('round-trips back to a display string', () {
      expect(MoneyInputParser.toInput(123456, decimals: 2), '1234.56');
      expect(MoneyInputParser.toInput(0, decimals: 2), '0.00');
    });
  });
}
