import 'package:asset_recovery_app/core/utils/formatters.dart';
import 'package:flutter_test/flutter_test.dart';

/// [Formatters.maskedPhone] is the single mask behind the BP detail customer
/// card and the Call Customer number picker, so what it hides is pinned here.
void main() {
  test('a 10-digit number keeps only its first five digits', () {
    expect(Formatters.maskedPhone('9811100190'), '98111XXXXX');
  });

  test('the masked value keeps the original length', () {
    expect(Formatters.maskedPhone('919811100190'), hasLength(12));
    expect(Formatters.maskedPhone('919811100190'), '91981XXXXXXX');
  });

  test('a value at or under five characters is left alone', () {
    // Nothing left to hide — masking would only misrepresent the value.
    expect(Formatters.maskedPhone('98111'), '98111');
    expect(Formatters.maskedPhone('981'), '981');
    expect(Formatters.maskedPhone(''), '');
  });

  test('the sixth character onwards is never legible', () {
    const raw = '9876543210';
    final masked = Formatters.maskedPhone(raw);
    expect(masked.substring(5), isNot(contains(RegExp(r'\d'))));
    expect(masked.startsWith(raw.substring(0, 5)), isTrue);
  });
}
