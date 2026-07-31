import 'dart:developer' as developer;
import 'dart:math';

import 'package:asset_recovery_app/domain/entities/geo_point.dart';
import 'package:geolocator/geolocator.dart';

/// Returned by [LocationService.currentLocation] when no fix could be obtained
/// — location services off, permission denied, or no last-known position on
/// record. Callers that must not act on a fabricated position should check
/// [GeoPointFix.hasFix] rather than assume every result is real.
const GeoPoint kNoLocationFix = GeoPoint(lat: 0, lng: 0);

extension GeoPointFix on GeoPoint {
  /// False for [kNoLocationFix]. Null Island is in the Gulf of Guinea, so no
  /// real reading this app will ever see lands on exactly (0, 0).
  bool get hasFix => lat != 0 || lng != 0;
}

/// Provides the device GPS location and geo-fence checks (PRD §4.3, §4.8).
///
/// [GeolocatorLocationService] is the real implementation, used everywhere
/// except the `test` environment, which has no platform channels and gets
/// [StubLocationService]'s jittered fixed point instead.
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

/// Real device GPS via the `geolocator` plugin. Android already declares
/// ACCESS_FINE_LOCATION / ACCESS_COARSE_LOCATION; the runtime grant is
/// requested lazily on the first fix so the agent sees the system prompt in
/// context rather than at launch.
///
/// Never throws. A Field Agent can be underground, out of signal, or have
/// declined the permission, and none of that may take down the screen that
/// asked — every failure path degrades to the last known position and then to
/// [kNoLocationFix].
class GeolocatorLocationService extends LocationService {
  GeolocatorLocationService({this.timeout = const Duration(seconds: 10)});

  /// Cap on a single fix attempt. A cold GPS start can otherwise hang for
  /// minutes indoors, and callers here are all on a UI path.
  final Duration timeout;

  @override
  Future<bool> isLocationEnabled() => Geolocator.isLocationServiceEnabled();

  @override
  Future<GeoPoint> currentLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return _lastKnownOrNoFix('location services are off');
      }
      if (!await _ensurePermission()) {
        return _lastKnownOrNoFix('location permission not granted');
      }
      final p = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: timeout,
      );
      return _toGeoPoint(p);
    } catch (e) {
      // Timed out, GPS hardware unavailable, plugin missing on this platform…
      return _lastKnownOrNoFix('$e');
    }
  }

  /// Asks for the runtime grant if we don't already hold one. A permanent
  /// denial ("Don't ask again") is reported as false rather than re-prompting
  /// on every call — only the OS settings screen can undo that.
  Future<bool> _ensurePermission() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  /// Best effort when a live fix is out of reach: the OS's cached position if
  /// it has one, otherwise the explicit "no fix" sentinel.
  Future<GeoPoint> _lastKnownOrNoFix(String reason) async {
    developer.log('No live GPS fix ($reason); trying last known position.',
        name: 'GeolocatorLocationService',);
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) return _toGeoPoint(last);
    } catch (_) {
      // getLastKnownPosition itself can throw without permission — fall
      // through to the sentinel.
    }
    return kNoLocationFix;
  }

  GeoPoint _toGeoPoint(Position p) => GeoPoint(
        lat: p.latitude,
        lng: p.longitude,
        accuracyMeters: p.accuracy,
        capturedAt: p.timestamp,
      );
}
