import 'package:asset_recovery_app/domain/entities/geo_point.dart';

/// One stop on the agent's server-planned route (`agent.route` —
/// `GET /agents/{agentId}/route`).
///
/// [sequence] is the backend's visiting order (1-based) — the app never
/// re-orders stops, it draws them exactly as planned. [legDistanceKm] is the
/// distance of the leg that *arrives* at this stop: for sequence 1 that is the
/// drive from the agent's current position, for every later stop the drive from
/// the previous one.
class RouteStop {
  const RouteStop({
    required this.ticketId,
    required this.ticketNumber,
    required this.customerName,
    required this.sequence,
    required this.lat,
    required this.lng,
    this.legDistanceKm,
  });

  /// Backend resource UUID of the ticket behind this stop.
  final String ticketId;

  /// Human ticket reference (e.g. `TKT-2026-00042`) — what the ticket list and
  /// [Ticket.ticketId] use as their key, so this is what "View details" opens.
  final String ticketNumber;
  final String customerName;
  final int sequence;
  final double lat;
  final double lng;
  final double? legDistanceKm;

  GeoPoint get location => GeoPoint(lat: lat, lng: lng);

  factory RouteStop.fromJson(Map<String, dynamic> json) => RouteStop(
        ticketId: json['ticketId'] as String? ?? '', // MAP: ticketId
        ticketNumber: json['ticketNumber'] as String? ?? '', // MAP: ticketNumber
        customerName: json['customerName'] as String? ?? '', // MAP: customerName
        sequence: (json['sequence'] as num?)?.toInt() ?? 0, // MAP: sequence
        lat: (json['lat'] as num?)?.toDouble() ?? 0, // MAP: lat
        lng: (json['lng'] as num?)?.toDouble() ?? 0, // MAP: lng
        legDistanceKm: (json['legDistanceKm'] as num?)?.toDouble(), // MAP: legDistanceKm
      );

  Map<String, dynamic> toJson() => {
        'ticketId': ticketId,
        'ticketNumber': ticketNumber,
        'customerName': customerName,
        'sequence': sequence,
        'lat': lat,
        'lng': lng,
        if (legDistanceKm != null) 'legDistanceKm': legDistanceKm,
      };
}

/// The agent's planned route for the shift, as returned by `agent.route`.
///
/// The backend owns the ordering and the distances; the map screen only plots
/// [stops] in [RouteStop.sequence] order and draws the drive between them.
class AgentRoute {
  const AgentRoute({
    required this.agentId,
    required this.agentName,
    required this.stops,
    this.totalDistanceKm,
  });

  final String agentId;
  final String agentName;

  /// Stops in visiting order — sorted by [RouteStop.sequence] at parse time, so
  /// callers can rely on index 0 being the first stop regardless of the order
  /// the array arrived in.
  final List<RouteStop> stops;
  final double? totalDistanceKm;

  static const AgentRoute empty =
      AgentRoute(agentId: '', agentName: '', stops: []);

  factory AgentRoute.fromJson(Map<String, dynamic> json) {
    final raw = json['stops'] as List<dynamic>? ?? const []; // MAP: stops
    final stops = raw
        .whereType<Map<String, dynamic>>()
        .map(RouteStop.fromJson)
        .toList()
      ..sort((a, b) => a.sequence.compareTo(b.sequence));
    return AgentRoute(
      agentId: json['agentId'] as String? ?? '', // MAP: agentId
      agentName: json['agentName'] as String? ?? '', // MAP: agentName
      stops: stops,
      totalDistanceKm:
          (json['totalDistanceKm'] as num?)?.toDouble(), // MAP: totalDistanceKm
    );
  }

  Map<String, dynamic> toJson() => {
        'agentId': agentId,
        'agentName': agentName,
        'stops': stops.map((s) => s.toJson()).toList(),
        if (totalDistanceKm != null) 'totalDistanceKm': totalDistanceKm,
      };
}
