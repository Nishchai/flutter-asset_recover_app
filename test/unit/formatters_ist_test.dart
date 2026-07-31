import 'package:asset_recovery_app/core/utils/formatters.dart';
import 'package:flutter_test/flutter_test.dart';

/// The attempt history card renders `attemptedAt` / `completedAt` through
/// [Formatters.dateTimeIst]. These stamps arrive from the service in UTC, so
/// the formatter — not the device clock — is what shifts them to IST.
void main() {
  test('a UTC stamp is shifted by +05:30 and labelled IST', () {
    expect(
      Formatters.dateTimeIst(DateTime.utc(2026, 7, 27, 10, 15)),
      '27 Jul 2026, 03:45 PM IST',
    );
  });

  test('the shift rolls the date over when it crosses midnight IST', () {
    // 20:00 UTC + 5:30 = 01:30 IST on the following day.
    expect(
      Formatters.dateTimeIst(DateTime.utc(2026, 7, 27, 20, 0)),
      '28 Jul 2026, 01:30 AM IST',
    );
  });

  test('an explicit-offset stamp is normalised through UTC first', () {
    // The wire shape the service actually sends, parsed as UTC.
    final parsed = DateTime.parse('2026-07-27T10:22:00+00:00');
    expect(Formatters.dateTimeIst(parsed), '27 Jul 2026, 03:52 PM IST');
  });

  test('a non-UTC stamp converts from its own instant, not its wall clock', () {
    // 12:00 at +02:00 is 10:00 UTC, hence 15:30 IST.
    final parsed = DateTime.parse('2026-07-27T12:00:00+02:00');
    expect(Formatters.dateTimeIst(parsed), '27 Jul 2026, 03:30 PM IST');
  });
}
