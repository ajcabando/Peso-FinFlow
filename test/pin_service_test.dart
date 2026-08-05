import 'package:finflow/core/security/pin_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PinService', () {
    test('encode produces a salt:hash pair that verifies', () {
      final encoded = PinService.encode('1234');
      expect(encoded.split(':'), hasLength(2));
      expect(PinService.verify('1234', encoded), isTrue);
    });

    test('wrong PINs never verify', () {
      final encoded = PinService.encode('9876');
      expect(PinService.verify('9875', encoded), isFalse);
      expect(PinService.verify('98765', encoded), isFalse);
    });

    test('two encodings of the same PIN differ (random salt)', () {
      final a = PinService.encode('2468');
      final b = PinService.encode('2468');
      expect(a, isNot(b));
      expect(PinService.verify('2468', a), isTrue);
      expect(PinService.verify('2468', b), isTrue);
    });

    test('malformed stored values are rejected safely', () {
      expect(PinService.verify('1234', ''), isFalse);
      expect(PinService.verify('1234', 'nosalt'), isFalse);
      expect(PinService.verify('1234', 'salt:'), isFalse);
      expect(PinService.verify('1234', ':hash'), isFalse);
    });

    test('isValid accepts 4–8 digit PINs only', () {
      expect(PinService.isValid('1234'), isTrue);
      expect(PinService.isValid('12345678'), isTrue);
      expect(PinService.isValid('123'), isFalse);
      expect(PinService.isValid('123456789'), isFalse);
      expect(PinService.isValid('12a4'), isFalse);
      expect(PinService.isValid(''), isFalse);
    });
  });
}
