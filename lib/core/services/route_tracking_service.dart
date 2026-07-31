import 'dart:async';
import 'dart:convert';

import 'package:asset_recovery_app/core/services/location_service.dart';
import 'package:asset_recovery_app/domain/entities/route_point.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Actual-route GPS trail capture during navigation (M3-02 — feeds the
/// backend's plan-vs-actual comparison, RP-03).
///
/// Cadence decision (open point in the spec, resolved here): this is an
/// audit/comparison trail, not a live dispatch feed — nothing consumes it in
/// real time — so it doesn't need Uber-style sub-5-second sampling. Fleet/
/// logistics trackers doing the same "breadcrumb trail for later comparison"
/// job commonly sample every 30-60s with a minimum-distance filter, trading
/// a little polyline smoothness for a large battery win over continuous
/// high-accuracy GPS. Decision:
///   - Only sample while a navigation session is explicitly active
///     (start/stop) — never poll GPS in the background.
///   - Every [sampleIntervalSeconds] (30s) OR [minDistanceMeters] (50m) of
///     movement, whichever comes first — avoids flooding the trail with
///     duplicate points while stationary (e.g. agent doing paperwork).
///   - [LocationService] is already abstracted behind balanced-power
///     defaults; this service doesn't request high-accuracy mode.
///   - Hard-capped at [maxPoints] per session (guards against a
///     forgotten/stuck "Start Navigation" running for hours).
///   - Persisted incrementally to disk so a killed app doesn't lose the
///     trail; the caller is responsible for handing the finished trail to
///     the sync queue on [stop].
class RouteTrackingService {
  RouteTrackingService(
    this._location, {
    this.sampleIntervalSeconds = 30,
    this.minDistanceMeters = 50,
    this.maxPoints = 500,
  });

  final LocationService _location;
  final int sampleIntervalSeconds;
  final double minDistanceMeters;
  final int maxPoints;

  static const _prefsKeyPrefix = 'route_tracking.trail.';

  Timer? _timer;
  String? _activeRouteId;
  List<RoutePoint> _points = [];

  bool get isTracking => _activeRouteId != null;

  Future<void> start(String routeId) async {
    if (_activeRouteId == routeId) return;
    await stop();
    _activeRouteId = routeId;
    _points = [];
    await _sample();
    _timer = Timer.periodic(Duration(seconds: sampleIntervalSeconds), (_) => _sample());
  }

  /// Stops tracking and returns the captured trail (empty if none was active).
  Future<List<RoutePoint>> stop() async {
    _timer?.cancel();
    _timer = null;
    final routeId = _activeRouteId;
    final points = _points;
    _activeRouteId = null;
    _points = [];
    if (routeId != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_prefsKeyPrefix$routeId');
    }
    return points;
  }

  Future<void> _sample() async {
    if (_activeRouteId == null || _points.length >= maxPoints) return;
    final location = await _location.currentLocation();
    // No fix this tick (permission denied, services off, indoors). Drop the
    // sample rather than draw the agent's route through Null Island — the
    // next tick picks up again if the fix comes back.
    if (!location.hasFix) return;
    if (_points.isNotEmpty) {
      final movedMeters = _points.last.location.haversineMeters(location);
      if (movedMeters < minDistanceMeters) return;
    }
    _points.add(RoutePoint(location: location, capturedAt: DateTime.now()));
    await _persist();
  }

  Future<void> _persist() async {
    final routeId = _activeRouteId;
    if (routeId == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_prefsKeyPrefix$routeId',
      jsonEncode(_points.map((p) => p.toJson()).toList()),
    );
  }
}
