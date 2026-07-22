import 'package:asset_recovery_app/core/utils/validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Validators.isValidMobile', () {
    test('accepts 10 digits, with or without separators', () {
      expect(Validators.isValidMobile('9811100000'), isTrue);
      expect(Validators.isValidMobile('98111 00000'), isTrue);
      expect(Validators.isValidMobile('+91-9811100000'), isFalse); // 12 digits
    });
    test('rejects short / empty / null', () {
      expect(Validators.isValidMobile('12345'), isFalse);
      expect(Validators.isValidMobile(''), isFalse);
      expect(Validators.isValidMobile(null), isFalse);
    });
  });

  group('Validators.isValidOtp', () {
    test('accepts exactly 6 digits', () {
      expect(Validators.isValidOtp('123456'), isTrue);
      expect(Validators.isValidOtp('12345'), isFalse);
      expect(Validators.isValidOtp('1234567'), isFalse);
      expect(Validators.isValidOtp('12a456'), isFalse);
    });
  });

  group('Validators.isNotEmpty', () {
    test('trims strings and handles nulls', () {
      expect(Validators.isNotEmpty('  '), isFalse);
      expect(Validators.isNotEmpty('x'), isTrue);
      expect(Validators.isNotEmpty(null), isFalse);
      expect(Validators.isNotEmpty(5), isTrue);
    });
  });
}
