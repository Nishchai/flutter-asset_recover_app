import 'dart:math' as math;

/// A latitude/longitude pair with optional accuracy and capture time.
class GeoPoint {
  const GeoPoint({
    required this.lat,
    required this.lng,
    this.accuracyMeters,
    this.capturedAt,
  });

  final double lat;
  final double lng;
  final double? accuracyMeters;
  final DateTime? capturedAt;

  factory GeoPoint.fromJson(Map<String, dynamic> json) => GeoPoint(
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        accuracyMeters: (json['accuracyMeters'] as num?)?.toDouble(),
        capturedAt: json['capturedAt'] == null
            ? null
            : DateTime.tryParse(json['capturedAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lng': lng,
        if (accuracyMeters != null) 'accuracyMeters': accuracyMeters,
        if (capturedAt != null) 'capturedAt': capturedAt!.toIso8601String(),
      };

  String get display => '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}';

  /// Haversine great-circle distance in metres. Used as a fallback when the
  /// Google road-distance service is unavailable. Real road distance is
  /// provided by [DistanceService] per PRD §4.8.
  double haversineMeters(GeoPoint other) {
    const earthRadius = 6371000.0;
    final dLat = _rad(other.lat - lat);
    final dLng = _rad(other.lng - lng);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat)) *
            math.cos(_rad(other.lat)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return earthRadius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _rad(double deg) => deg * math.pi / 180.0;
}
