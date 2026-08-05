import 'package:flutter_test/flutter_test.dart';

import 'package:finflow/core/utils/chart_utils.dart';
import 'package:finflow/core/utils/currency_formatter.dart';

void main() {
  group('CurrencyFormatter.pow10', () {
    test('computes powers of ten', () {
      expect(CurrencyFormatter.pow10(0), 1);
      expect(CurrencyFormatter.pow10(1), 10);
      expect(CurrencyFormatter.pow10(2), 100);
      expect(CurrencyFormatter.pow10(4), 10000);
    });
  });

  group('ChartUtils.forCurrency', () {
    test('scales by the currency decimal digits', () {
      expect(ChartUtils.forCurrency('PHP'), 100.0);
      expect(ChartUtils.forCurrency('USD'), 100.0);
      // Zero-decimal currencies scale by 1.
      expect(ChartUtils.forCurrency('JPY'), 1.0);
      // Three-decimal currencies scale by 1000.
      expect(ChartUtils.forCurrency('BHD'), 1000.0);
      // Unknown currencies default to two decimal digits.
      expect(ChartUtils.forCurrency('XYZ'), 100.0);
    });
  });

  group('ChartUtils.monthName', () {
    test('returns short names for 1-based months', () {
      const expected = [
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
      for (var month = 1; month <= 12; month++) {
        expect(ChartUtils.monthName(month), expected[month - 1]);
      }
    });

    test('rejects months outside 1..12 in debug mode', () {
      expect(() => ChartUtils.monthName(0), throwsA(isA<AssertionError>()));
      expect(() => ChartUtils.monthName(13), throwsA(isA<AssertionError>()));
    });
  });
}
