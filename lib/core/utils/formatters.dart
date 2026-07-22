import 'package:intl/intl.dart';

/// Display formatting helpers.
class Formatters {
  Formatters._();

  static String distanceKm(double? km) =>
      km == null ? '—' : '${km.toStringAsFixed(1)} km';

  /// Numeric distance without unit, e.g. "2.4" (for "{km} KM" labels).
  static String distanceValue(double? km) =>
      km == null ? '—' : km.toStringAsFixed(1);

  static String date(DateTime dt) => DateFormat('dd MMM yyyy').format(dt);

  static String dateTime(DateTime dt) =>
      DateFormat('dd MMM yyyy, hh:mm a').format(dt);

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
