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

/// What still stands between the app and a GPS fix, in terms the agent can act
/// on. Returned by [LocationService.ensureReady] so the UI can offer the one
/// recovery that actually applies instead of a generic "location unavailable".
enum LocationReadiness {
  /// Permission held and location services on — a fix should be obtainable.
  ready,

  /// Permitted, but location is switched off device-wide. Undone from the
  /// device's own location settings, not the app's.
  servicesOff,

  /// Refused for now. The OS will still show the prompt again later, so asking
  /// again on the next attempt is worthwhile.
  denied,

  /// Refused permanently ("Don't ask again"). Only the app settings screen can
  /// undo this, which is why re-prompting is pointless.
  deniedForever,

  /// No GPS hardware, no plugin on this platform, or the check itself failed.
  /// Nothing the agent can do about it.
  unavailable,
}

/// Provides the device GPS location and geo-fence checks (PRD §4.3, §4.8).
///
/// [GeolocatorLocationService] is the real implementation, used everywhere
/// except the `test` environment, which has no platform channels and gets
/// [StubLocationService]'s jittered fixed point instead.
abstract class LocationService {
  Future<bool> isLocationEnabled();

  /// Acquires whatever is missing before a fix can be read — the runtime
  /// permission grant included — and reports what is still blocked.
  ///
  /// Safe to call from a UI path: it never throws, and it never re-prompts for
  /// a permission the agent has permanently refused.
  Future<LocationReadiness> ensureReady();

  Future<GeoPoint> currentLocation();

  /// Opens the OS screen that can undo a [LocationReadiness.deniedForever] —
  /// this app's own permission page.
  Future<void> openPermissionSettings();

  /// Opens the device location settings that can undo a
  /// [LocationReadiness.servicesOff].
  Future<void> openLocationSettings();

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

  /// Overrideable in tests to force a blocked state without platform channels.
  LocationReadiness? forcedReadiness;

  /// How many times the UI sent the agent to an OS settings screen.
  int settingsOpenCount = 0;

  @override
  Future<bool> isLocationEnabled() async => locationEnabled;

  @override
  Future<LocationReadiness> ensureReady() async =>
      forcedReadiness ??
      (locationEnabled
          ? LocationReadiness.ready
          : LocationReadiness.servicesOff);

  @override
  Future<void> openPermissionSettings() async => settingsOpenCount++;

  @override
  Future<void> openLocationSettings() async => settingsOpenCount++;

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
/// context rather than at launch. Active in every environment except `test`,
/// dev builds included — a stubbed dev build would never surface the prompt
/// where it is being developed.
///
/// Never throws. A Field Agent can be underground, out of signal, or have
/// declined the permission, and none of that may take down the screen that
/// asked — every failure path degrades to the last known position and then to
/// [kNoLocationFix].
class GeolocatorLocationService extends LocationService {
  GeolocatorLocationService({this.timeout = const Duration(seconds: 10)});

  static const _logName = 'GeolocatorLocationService';

  /// Cap on a single fix attempt. A cold GPS start can otherwise hang for
  /// minutes indoors, and callers here are all on a UI path.
  final Duration timeout;

  @override
  Future<bool> isLocationEnabled() => Geolocator.isLocationServiceEnabled();

  @override
  Future<LocationReadiness> ensureReady() async {
    try {
      // Permission is asked for BEFORE the services check, not after. With the
      // old order, a device that had location switched off returned early and
      // the runtime prompt was never shown at all — so an agent who had never
      // been asked looked identical to one who had refused.
      final permission = await _requestPermission();
      if (permission == LocationPermission.deniedForever) {
        return LocationReadiness.deniedForever;
      }
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        // Includes `unableToDetermine`: treated as a soft denial so the next
        // attempt asks again rather than writing the agent off permanently.
        return LocationReadiness.denied;
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        return LocationReadiness.servicesOff;
      }
      return LocationReadiness.ready;
    } catch (e) {
      developer.log('Location readiness check failed: $e', name: _logName);
      return LocationReadiness.unavailable;
    }
  }

  @override
  Future<GeoPoint> currentLocation() async {
    try {
      final readiness = await ensureReady();
      if (readiness != LocationReadiness.ready) {
        return _lastKnownOrNoFix(readiness.name);
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

  @override
  Future<void> openPermissionSettings() async {
    try {
      await Geolocator.openAppSettings();
    } catch (e) {
      developer.log('Could not open app settings: $e', name: _logName);
    }
  }

  @override
  Future<void> openLocationSettings() async {
    try {
      await Geolocator.openLocationSettings();
    } catch (e) {
      developer.log('Could not open location settings: $e', name: _logName);
    }
  }

  /// Asks for the runtime grant only when we don't already hold one and the OS
  /// is still willing to prompt. A permanent denial is returned as-is rather
  /// than re-requested on every call — that call is a no-op on Android and the
  /// agent would never see a dialog from it.
  Future<LocationPermission> _requestPermission() async {
    final permission = await Geolocator.checkPermission();
    if (permission != LocationPermission.denied) return permission;
    return Geolocator.requestPermission();
  }

  /// Best effort when a live fix is out of reach: the OS's cached position if
  /// it has one, otherwise the explicit "no fix" sentinel.
  Future<GeoPoint> _lastKnownOrNoFix(String reason) async {
    developer.log('No live GPS fix ($reason); trying last known position.',
        name: _logName,);
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
