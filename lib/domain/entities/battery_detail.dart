import 'package:asset_recovery_app/domain/entities/geo_point.dart';

/// Live battery telemetry returned by the Battery Master API
/// (`battery.getBatteryDetails` → `GET .../WheelerBattery/SearchBattery/{bpId}`).
///
/// That service lives on its own host (a different base URL than `apiBaseUrl`),
/// so the endpoint carries an ABSOLUTE URL in `api_endpoints.json` and
/// [ApiClient] uses it verbatim. The response wraps the data in an envelope
/// (`{version, statusCode, message, responseException, result: [ ... ]}`); the
/// telemetry we surface lives in the FIRST element of `result`.
///
/// Only the fields the BP detail screen needs are modelled — notably
/// [lastLatitude]/[lastLongitude] (→ "Last Seen") and [lastTiuTimestamp]
/// (→ "Last TIU"). The wire carries many more (cell voltages, faults, …) which
/// are ignored here.
class BatteryDetail {
  const BatteryDetail({
    this.batterySerialNumber = '',
    this.tiuSerialNumber = '',
    this.lastLatitude,
    this.lastLongitude,
    this.lastTiuTimestamp,
    this.lastSoc,
    this.lastPackVoltage,
  });

  final String batterySerialNumber;
  final String tiuSerialNumber;

  /// Last known position → "Last Seen".
  final double? lastLatitude;
  final double? lastLongitude;

  /// Timestamp of the last TIU report → "Last TIU". Parsed from the wire's
  /// `lastTiutimestamp` (Unix epoch SECONDS).
  final DateTime? lastTiuTimestamp;

  final double? lastSoc;
  final double? lastPackVoltage;

  /// True once both coordinates are present.
  bool get hasLocation => lastLatitude != null && lastLongitude != null;

  /// The last-known position as a [GeoPoint], or null when either coordinate is
  /// missing.
  GeoPoint? get location => hasLocation
      ? GeoPoint(lat: lastLatitude!, lng: lastLongitude!)
      : null;

  /// Unwraps the API envelope and parses the first `result` entry. Returns null
  /// when the envelope carries no telemetry row.
  static BatteryDetail? fromEnvelope(Map<String, dynamic> json) {
    final result = json['result'];
    if (result is! List || result.isEmpty) return null;
    final first = result.first;
    if (first is! Map<String, dynamic>) return null;
    return BatteryDetail.fromJson(first);
  }

  factory BatteryDetail.fromJson(Map<String, dynamic> json) => BatteryDetail(
        batterySerialNumber: json['batterySerialNumber'] as String? ?? '',
        tiuSerialNumber: json['tiuSerialNumber'] as String? ?? '',
        lastLatitude: (json['lastLatitude'] as num?)?.toDouble(),
        lastLongitude: (json['lastLongitude'] as num?)?.toDouble(),
        // `lastTiutimestamp` (note the lowercase `t`) is Unix epoch seconds.
        lastTiuTimestamp: _epochSecondsToDate(json['lastTiutimestamp']),
        lastSoc: (json['lastSoc'] as num?)?.toDouble(),
        lastPackVoltage: (json['lastPackVoltage'] as num?)?.toDouble(),
      );
}

/// Converts a Unix epoch-SECONDS value to a local [DateTime]. Tolerates a null
/// or non-numeric input (→ null) and a zero/negative sentinel (→ null).
DateTime? _epochSecondsToDate(Object? v) {
  final seconds = (v as num?)?.toInt();
  if (seconds == null || seconds <= 0) return null;
  return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
}
