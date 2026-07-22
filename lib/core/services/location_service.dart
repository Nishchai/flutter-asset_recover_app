import 'dart:math';

import 'package:asset_recovery_app/domain/entities/geo_point.dart';

/// Provides the device GPS location and geo-fence checks (PRD §4.3, §4.8).
///
/// The default [StubLocationService] returns a jittered fixed point so the app
/// runs without the `geolocator` plugin. Swap in [GeolocatorLocationService]
/// (see commented stub) once the plugin is added.
abstract class LocationService {
  Future<bool> isLocationEnabled();

  Future<GeoPoint> currentLocation();

  /// True when [device] is within [radiusMeters] of [target].
  bool isWithinGeofence(GeoPoint device, GeoPoint target, double radiusMeters) {
    return device.haversineMeters(target) <= radiusMeters;
  }
}

/// No-plugin stub used in dev/test. Centres around the agent's seed location.
class StubLocationService extends LocationService {
  StubLocationService({GeoPoint? origin, int? seed})
      : _origin = origin ?? const GeoPoint(lat: 12.9352, lng: 77.6245),
        _rng = Random(seed ?? 11);

  final GeoPoint _origin;
  final Random _rng;
  bool locationEnabled = true;

  /// Overrideable in tests to force a point inside/outside a geo-fence.
  GeoPoint? forcedLocation;

  @override
  Future<bool> isLocationEnabled() async => locationEnabled;

  @override
  Future<GeoPoint> currentLocation() async {
    if (forcedLocation != null) return forcedLocation!;
    // ±25 m jitter to emulate GPS noise.
    final dLat = (_rng.nextDouble() - 0.5) * 0.0004;
    final dLng = (_rng.nextDouble() - 0.5) * 0.0004;
    return GeoPoint(
      lat: _origin.lat + dLat,
      lng: _origin.lng + dLng,
      accuracyMeters: 8 + _rng.nextDouble() * 12,
      capturedAt: DateTime.now(),
    );
  }
}

// -----------------------------------------------------------------------------
// REAL IMPLEMENTATION (enable geolocator in pubspec, then uncomment):
//
// class GeolocatorLocationService extends LocationService {
//   @override
//   Future<bool> isLocationEnabled() => Geolocator.isLocationServiceEnabled();
//
//   @override
//   Future<GeoPoint> currentLocation() async {
//     final p = await Geolocator.getCurrentPosition(
//       desiredAccuracy: LocationAccuracy.best,
//     );
//     return GeoPoint(
//       lat: p.latitude, lng: p.longitude,
//       accuracyMeters: p.accuracy, capturedAt: DateTime.now(),
//     );
//   }
// }
