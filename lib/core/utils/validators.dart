/// Pure validation helpers, unit-tested in test/unit/validators_test.dart.
class Validators {
  Validators._();

  static bool isValidMobile(String? value) {
    if (value == null) return false;
    final digits = value.replaceAll(RegExp(r'\D'), '');
    return RegExp(r'^\d{10}$').hasMatch(digits);
  }

  static bool isValidOtp(String? value, {int length = 6}) {
    if (value == null) return false;
    return RegExp('^\\d{$length}\$').hasMatch(value.trim());
  }

  static bool isNotEmpty(Object? value) {
    if (value == null) return false;
    if (value is String) return value.trim().isNotEmpty;
    return true;
  }
}
