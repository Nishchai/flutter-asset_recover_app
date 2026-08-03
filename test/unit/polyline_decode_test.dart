import 'package:asset_recovery_app/core/services/directions_service.dart';
import 'package:asset_recovery_app/domain/entities/geo_point.dart';
import 'package:flutter_test/flutter_test.dart';

/// [DirectionsService.decodePolyline] turns the Directions API's
/// `overview_polyline` into the shape the map draws for in-app navigation — a
/// silent bug here would put the agent's route in the wrong place, so the
/// reference vectors are pinned.
void main() {
  test('decodes the Google reference polyline', () {
    // From the encoded-polyline algorithm docs: three points around
    // California, the canonical worked example.
    final points = DirectionsService.decodePolyline(r'_p~iF~ps|U_ulLnnqC_mqNvxq`@');

    expect(points, hasLength(3));
    _expectPoint(points[0], 38.5, -120.2);
    _expectPoint(points[1], 40.7, -120.95);
    _expectPoint(points[2], 43.252, -126.453);
  });

  test('a single-point polyline decodes to one coordinate', () {
    final points = DirectionsService.decodePolyline('_p~iF~ps|U');
    expect(points, hasLength(1));
    _expectPoint(points.single, 38.5, -120.2);
  });

  test('an empty polyline decodes to no points', () {
    expect(DirectionsService.decodePolyline(''), isEmpty);
  });

  test('deltas accumulate — later points are relative to earlier ones', () {
    // Two identical zero deltas after the first point: the shape must stay put
    // rather than drift back toward (0, 0).
    final points = DirectionsService.decodePolyline('_p~iF~ps|U??');
    expect(points, hasLength(2));
    _expectPoint(points[1], 38.5, -120.2);
  });

  test('the straight-line fallback is a two-point leg with a real distance', () {
    const from = GeoPoint(lat: 12.9716, lng: 77.5946);
    const to = GeoPoint(lat: 12.9352, lng: 77.6245);
    final route = DirectionsRoute.straightLine(from, to);

    expect(route.isRoadRoute, isFalse);
    expect(route.points, [from, to]);
    // ~5 km apart in Bengaluru; assert the order of magnitude, not the decimal.
    expect(route.distanceKm, closeTo(5.1, 0.5));
    expect(route.durationMinutes, greaterThan(0));
  });
}

void _expectPoint(GeoPoint p, double lat, double lng) {
  expect(p.lat, closeTo(lat, 0.00001));
  expect(p.lng, closeTo(lng, 0.00001));
}
