import 'dart:convert';
import 'dart:developer' as developer;

import 'package:asset_recovery_app/core/config/config_service.dart';
import 'package:asset_recovery_app/domain/entities/geo_point.dart';
import 'package:http/http.dart' as http;

/// A road-following route between two points, ready to draw as a map polyline.
///
/// [points] is the decoded `overview_polyline` — the shape the vehicle actually
/// travels, not a straight line between origin and destination.
class DirectionsRoute {
  const DirectionsRoute({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.isRoadRoute,
  });

  final List<GeoPoint> points;
  final int distanceMeters;
  final int durationSeconds;

  /// True when the shape came from the Directions API. False for the
  /// [DirectionsRoute.straightLine] fallback, so the UI can say the leg is an
  /// approximation instead of a driving route.
  final bool isRoadRoute;

  double get distanceKm => distanceMeters / 1000;
  int get durationMinutes => (durationSeconds / 60).round();

  /// Fallback shape used when the Directions API is unavailable (no key, key
  /// not authorised for the web service, or the call failed): a direct line
  /// between the two points with a haversine distance and a rough ETA at
  /// [avgSpeedKmh]. Keeps "Start navigation" useful in-app instead of failing.
  factory DirectionsRoute.straightLine(
    GeoPoint from,
    GeoPoint to, {
    double avgSpeedKmh = 18,
  }) {
    final meters = from.haversineMeters(to);
    return DirectionsRoute(
      points: [from, to],
      distanceMeters: meters.round(),
      durationSeconds: (meters / 1000 / avgSpeedKmh * 3600).round(),
      isRoadRoute: false,
    );
  }
}

/// Google Directions API client — turns two coordinates into the drivable route
/// between them so navigation can be drawn on the app's own `GoogleMap` instead
/// of handing the agent off to the external Maps app.
///
/// Uses the active environment's `mapsApiKey`. NOTE that this is a *web service*
/// call: an API key restricted to Android/iOS apps will be rejected with
/// `REQUEST_DENIED` even though the same key renders the map fine. The key needs
/// the Directions API enabled and either no application restriction or an IP
/// one. Every failure path returns null and the caller falls back to
/// [DirectionsRoute.straightLine].
class DirectionsService {
  DirectionsService(this._config, {http.Client? client})
      : _client = client ?? http.Client();

  final ConfigService _config;
  final http.Client _client;

  static const _host = 'maps.googleapis.com';
  static const _path = '/maps/api/directions/json';

  bool get isConfigured => _config.env.mapsApiKey.isNotEmpty;

  /// Driving directions from [origin] to [destination], optionally through
  /// [waypoints] in the given order. Returns null when the route cannot be
  /// fetched — callers draw the straight-line fallback rather than nothing.
  Future<DirectionsRoute?> fetch({
    required GeoPoint origin,
    required GeoPoint destination,
    List<GeoPoint> waypoints = const [],
  }) async {
    final key = _config.env.mapsApiKey;
    if (key.isEmpty) return null;

    final uri = Uri.https(_host, _path, {
      'origin': '${origin.lat},${origin.lng}',
      'destination': '${destination.lat},${destination.lng}',
      'mode': 'driving',
      if (waypoints.isNotEmpty)
        'waypoints': waypoints.map((p) => '${p.lat},${p.lng}').join('|'),
      'key': key,
    });

    try {
      final res = await _client
          .get(uri)
          .timeout(Duration(seconds: _config.env.apiTimeoutSeconds));
      if (res.statusCode != 200) {
        _log('HTTP ${res.statusCode}', res.body);
        return null;
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final status = body['status'] as String? ?? 'UNKNOWN';
      if (status != 'OK') {
        // REQUEST_DENIED here almost always means the key is app-restricted or
        // the Directions API isn't enabled on the project — surface the reason
        // rather than silently degrading to a straight line.
        _log(status, body['error_message'] as String? ?? '');
        return null;
      }
      final routes = body['routes'] as List<dynamic>;
      if (routes.isEmpty) return null;
      final route = routes.first as Map<String, dynamic>;
      final encoded = (route['overview_polyline']
          as Map<String, dynamic>?)?['points'] as String?;
      if (encoded == null || encoded.isEmpty) return null;

      var meters = 0;
      var seconds = 0;
      for (final leg in (route['legs'] as List<dynamic>? ?? [])) {
        final l = leg as Map<String, dynamic>;
        meters += ((l['distance'] as Map<String, dynamic>?)?['value'] as num?)
                ?.toInt() ??
            0;
        seconds += ((l['duration'] as Map<String, dynamic>?)?['value'] as num?)
                ?.toInt() ??
            0;
      }

      return DirectionsRoute(
        points: decodePolyline(encoded),
        distanceMeters: meters,
        durationSeconds: seconds,
        isRoadRoute: true,
      );
    } catch (e) {
      _log('request failed', '$e');
      return null;
    }
  }

  void _log(String status, String detail) {
    if (!_config.env.enableNetworkLogging) return;
    developer.log('Directions $status${detail.isEmpty ? '' : ' — $detail'}',
        name: 'DirectionsService',);
  }

  /// Decodes Google's [encoded polyline algorithm][1] into coordinates.
  ///
  /// Each value is a base64-ish varint of the *delta* from the previous point,
  /// zig-zag encoded so negatives stay compact, scaled by 1e5.
  ///
  /// [1]: https://developers.google.com/maps/documentation/utilities/polylinealgorithm
  static List<GeoPoint> decodePolyline(String encoded) {
    final points = <GeoPoint>[];
    var index = 0;
    var lat = 0;
    var lng = 0;

    while (index < encoded.length) {
      for (var coord = 0; coord < 2; coord++) {
        var shift = 0;
        var result = 0;
        int byte;
        do {
          byte = encoded.codeUnitAt(index++) - 63;
          result |= (byte & 0x1f) << shift;
          shift += 5;
        } while (byte >= 0x20 && index < encoded.length);
        final delta = (result & 1) != 0 ? ~(result >> 1) : result >> 1;
        if (coord == 0) {
          lat += delta;
        } else {
          lng += delta;
        }
      }
      points.add(GeoPoint(lat: lat / 1e5, lng: lng / 1e5));
    }
    return points;
  }

  void dispose() => _client.close();
}
