import 'package:intl/intl.dart';

/// Display formatting helpers.
class Formatters {
  Formatters._();

  static String distanceKm(double? km) =>
      km == null ? '—' : '${km.toStringAsFixed(1)} km';

  /// Numeric distance without unit, e.g. "2.4" (for "{km} KM" labels).
  static String distanceValue(double? km) =>
      km == null ? '—' : km.toStringAsFixed(1);

  /// How many leading characters of a phone number stay legible when masked.
  static const int _visiblePhoneDigits = 5;

  /// Masks a phone number for display, leaving only the first
  /// [_visiblePhoneDigits] characters readable: `9811100190` → `98111XXXXX`.
  ///
  /// The mask keeps the original length so the value still reads as a phone
  /// number. Anything already at or under the visible length is returned
  /// unchanged — there would be nothing left to hide.
  ///
  /// Display only: never mask the value handed to the dialer or sent to an API.
  static String maskedPhone(String phone) {
    if (phone.length <= _visiblePhoneDigits) return phone;
    return phone.substring(0, _visiblePhoneDigits) +
        'X' * (phone.length - _visiblePhoneDigits);
  }

  static String date(DateTime dt) => DateFormat('dd MMM yyyy').format(dt);

  static String dateTime(DateTime dt) =>
      DateFormat('dd MMM yyyy, hh:mm a').format(dt);

  /// India Standard Time is a fixed UTC+05:30 — the country observes no DST,
  /// so a constant offset is correct year-round and, unlike `toLocal()`, does
  /// not depend on how the agent's device clock is configured.
  static const Duration _istOffset = Duration(hours: 5, minutes: 30);

  /// Formats a backend timestamp in IST, e.g. "27 Jul 2026, 03:45 PM IST".
  ///
  /// Service timestamps arrive in UTC (`...T10:15:00+00:00`), and [DateFormat]
  /// prints a `DateTime`'s own fields without shifting zones — so the value is
  /// normalised through UTC and offset by [_istOffset] before formatting.
  /// A value that is already device-local is handled too, via `toUtc()`.
  static String dateTimeIst(DateTime dt) =>
      DateFormat("dd MMM yyyy, hh:mm a 'IST'").format(dt.toUtc().add(_istOffset));

  /// Figma scan stamp, e.g. "11:42 - 12 May 2026".
  static String scanStamp(DateTime dt) =>
      DateFormat('HH:mm - dd MMM yyyy').format(dt);

  static String age(DateTime from, DateTime now) {
    final d = now.difference(from);
    if (d.inDays >= 1) return '${d.inDays}d';
    if (d.inHours >= 1) return '${d.inHours}h';
    return '${d.inMinutes}m';
  }

  static String etaMinutes(double km, {double avgSpeedKmh = 18}) {
    final minutes = (km / avgSpeedKmh * 60).round();
    return '$minutes';
  }
}
