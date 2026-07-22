import 'package:asset_recovery_app/domain/entities/geo_point.dart';

/// One GPS sample captured during active navigation (M3-02 — actual route
/// capture, for plan-vs-actual comparison). Sampling cadence is decided in
/// [RouteTrackingService], not here.
class RoutePoint {
  const RoutePoint({required this.location, required this.capturedAt});

  final GeoPoint location;
  final DateTime capturedAt;

  factory RoutePoint.fromJson(Map<String, dynamic> json) => RoutePoint(
        location: GeoPoint.fromJson(json['location'] as Map<String, dynamic>),
        capturedAt: DateTime.parse(json['capturedAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'location': location.toJson(),
        'capturedAt': capturedAt.toIso8601String(),
      };
}
