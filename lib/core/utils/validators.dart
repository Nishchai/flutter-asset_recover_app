/// Pure validation helpers, unit-tested in test/unit/validators_test.dart.
class Validators {
  Validators._();

  static bool isValidMobile(String? value) {
    if (value == null) return false;
    final digits = value.replaceAll(RegExp(r'\D'), '');
    return RegExp(r'^\d{10}$').hasMatch(digits);
  }

  /// The plain 10-digit form of a mobile number that arrived from the backend,
  /// or null when [value] isn't one. Unlike [isValidMobile] — which checks what
  /// the agent typed and so insists on exactly ten digits — stored records
  /// carry formatting and country prefixes (`+91 98765-43210`, `09876543210`),
  /// so those are stripped before the ten-digit rule is applied.
  ///
  /// Used to decide which of the customer's numbers the Call Customer screen
  /// may dial: anything that doesn't reduce to ten digits isn't callable and
  /// isn't offered.
  static String? mobileDigits(String? value) {
    if (value == null) return null;
    var digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 12 && digits.startsWith('91')) {
      digits = digits.substring(2);
    } else if (digits.length == 11 && digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    return RegExp(r'^\d{10}$').hasMatch(digits) ? digits : null;
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
