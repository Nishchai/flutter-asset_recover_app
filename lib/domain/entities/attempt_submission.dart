/// Payload for the standalone attempts service (`POST /api/v1/attempts`,
/// endpoint `attempts.submit`). Built on the Update Status screen when the
/// agent taps "Submit Attempt".
///
/// NOTE on the wire contract — verified against the live service:
///   • location   → send top-level `latitude` / `longitude` numbers. The
///                  backend DERIVES and stores the `location` field from them;
///                  a nested `location` in the payload is ignored (persists
///                  null), so we don't send one.
///   • [metadata]  → a native JSON *object* (422 "metadata must be a JSON
///                   object" if stringified).
///   • [proofUrls] → a native JSON *array* of strings (HTTP 400
///                   `IReadOnlyList<string>` bind failure if stringified).
/// [ticketId] and [batteryId] must be the human identifiers (ticket number
/// e.g. `TKT-2026-00024` and bpId e.g. `INSMOMAH...`), NOT internal GUIDs —
/// the service resolves them and 422s ("Unknown ticket"/"Unknown battery")
/// on an unknown value.
class AttemptSubmission {
  const AttemptSubmission({
    required this.id,
    required this.ticketId,
    required this.batteryId,
    required this.agentId,
    required this.agentName,
    required this.attemptType,
    required this.outcome,
    required this.attemptedAt,
    required this.completedAt,
    required this.latitude,
    required this.longitude,
    required this.customerPresent,
    required this.notes,
    this.proofUrls = const [],
    this.metadata = const {},
  });

  /// Client-generated attempt id (UUID v4).
  final String id;

  /// Recovery case id — the "Case ID" shown on the ticket detail screen
  /// ([Ticket.ticketId]).
  final String ticketId;

  /// BP identifier ([Battery.bpId]).
  final String batteryId;

  /// Agent id — hard-coded for now (see the caller), mirroring [ApiClient].
  final String agentId;
  final String agentName;

  /// Attempt channel, e.g. `field_visit`.
  final String attemptType;

  /// Selected outcome value, e.g. `recovered`.
  final String outcome;

  /// Captured when the agent opened the Update Status screen.
  final DateTime attemptedAt;

  /// Captured when the agent tapped "Submit Attempt".
  final DateTime completedAt;

  /// Agent's current GPS at submit time; sent as top-level `latitude` /
  /// `longitude`, from which the backend derives the stored `location`.
  final double latitude;
  final double longitude;

  final bool customerPresent;
  final String notes;

  /// Blob URLs of proof photos captured on this screen.
  final List<String> proofUrls;

  /// Any additional Update Status fields not mapped to a first-class column.
  final Map<String, dynamic> metadata;

  Map<String, dynamic> toJson() => {
        'id': id,
        'ticketId': ticketId,
        'batteryId': batteryId,
        'agentId': agentId,
        'agentName': agentName,
        'attemptType': attemptType,
        'outcome': outcome,
        'attemptedAt': attemptedAt.toUtc().toIso8601String(),
        'completedAt': completedAt.toUtc().toIso8601String(),
        // Location: top-level lat/long — backend derives the stored `location`
        // from these. metadata (object) and proofUrls (array) go out as native
        // JSON; a stringified value is rejected (422 "must be a JSON object" /
        // HTTP 400 IReadOnlyList<string> bind failure).
        'latitude': latitude,
        'longitude': longitude,
        'customerPresent': customerPresent,
        'notes': notes,
        'proofUrls': proofUrls,
        'metadata': metadata,
      };

  /// Inverse of [toJson] — used to replay a submission persisted on the offline
  /// sync queue. Timestamps round-trip through UTC ISO-8601.
  factory AttemptSubmission.fromJson(Map<String, dynamic> json) =>
      AttemptSubmission(
        id: json['id'] as String,
        ticketId: json['ticketId'] as String,
        batteryId: json['batteryId'] as String,
        agentId: json['agentId'] as String,
        agentName: json['agentName'] as String? ?? '',
        attemptType: json['attemptType'] as String,
        outcome: json['outcome'] as String,
        attemptedAt: DateTime.parse(json['attemptedAt'] as String),
        completedAt: DateTime.parse(json['completedAt'] as String),
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        customerPresent: json['customerPresent'] as bool? ?? false,
        notes: json['notes'] as String? ?? '',
        proofUrls: (json['proofUrls'] as List? ?? const [])
            .map((e) => e.toString())
            .toList(),
        metadata: Map<String, dynamic>.from(
            json['metadata'] as Map? ?? const <String, dynamic>{},),
      );
}
