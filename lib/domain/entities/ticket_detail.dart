import 'dart:convert';

/// Full ticket detail returned by `GET /tickets/{UUID}` (`tickets.fullDetail`).
///
/// Unlike the FLATTENED ticket+BP summary used in the list/[Ticket] model, this
/// endpoint returns the fully NESTED representation (agent / customer / battery
/// / attempts as sub-objects). It is fetched on the BP detail screen using the
/// backend resource UUID (`Ticket.caseId`, i.e. the response `id`) to enrich the
/// on-screen card with fields the list summary doesn't carry — notably the
/// customer's [TicketDetailCustomer.geoLocation] (Last Seen),
/// [TicketDetailCustomer.lastSwapDate] (Last TIU) and
/// [TicketDetailCustomer.lastSwapStationCode] (Last Swap).
class TicketDetail {
  const TicketDetail({
    required this.id,
    required this.ticketNumber,
    required this.status,
    this.priority,
    this.source = '',
    this.slaDeadline,
    this.overdueDays = 0,
    this.clusterCode = '',
    this.reassignCount = 0,
    this.assignedAt,
    this.closedAt,
    this.notes = '',
    this.resolutionType = '',
    this.acConfirmationRequired = false,
    this.closureSignedOff = false,
    this.agent,
    this.customer,
    this.battery,
    this.attempts = const [],
    this.createdAt,
    this.updatedAt,
    this.riskTier = '',
    this.isEmergency = false,
    this.ertFlag = false,
    this.esvFlag = false,
    this.zoneCode = '',
    this.routeCode = '',
    this.daysSinceLastAttempt = 0,
  });

  /// Backend resource UUID — the value passed in the `{ticketId}` path segment.
  final String id;
  final String ticketNumber;
  final String status;
  final int? priority;
  final String source;
  final DateTime? slaDeadline;
  final int overdueDays;
  final String clusterCode;
  final int reassignCount;
  final DateTime? assignedAt;
  final DateTime? closedAt;
  final String notes;
  final String resolutionType;
  final bool acConfirmationRequired;
  final bool closureSignedOff;
  final TicketDetailAgent? agent;
  final TicketDetailCustomer? customer;
  final TicketDetailBattery? battery;
  final List<TicketDetailAttempt> attempts;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String riskTier;
  final bool isEmergency;
  final bool ertFlag;
  final bool esvFlag;
  final String zoneCode;
  final String routeCode;
  final int daysSinceLastAttempt;

  factory TicketDetail.fromJson(Map<String, dynamic> json) => TicketDetail(
        id: json['id'] as String? ?? '',
        ticketNumber: json['ticketNumber'] as String? ?? '',
        status: json['status'] as String? ?? '',
        priority: (json['priority'] as num?)?.toInt(),
        source: json['source'] as String? ?? '',
        slaDeadline: _tryDate(json['slaDeadline']),
        overdueDays: (json['overdueDays'] as num?)?.toInt() ?? 0,
        clusterCode: json['clusterCode'] as String? ?? '',
        reassignCount: (json['reassignCount'] as num?)?.toInt() ?? 0,
        assignedAt: _tryDate(json['assignedAt']),
        closedAt: _tryDate(json['closedAt']),
        notes: json['notes'] as String? ?? '',
        resolutionType: json['resolutionType'] as String? ?? '',
        acConfirmationRequired: json['acConfirmationRequired'] as bool? ?? false,
        closureSignedOff: json['closureSignedOff'] as bool? ?? false,
        agent: json['agent'] is Map<String, dynamic>
            ? TicketDetailAgent.fromJson(json['agent'] as Map<String, dynamic>)
            : null,
        customer: json['customer'] is Map<String, dynamic>
            ? TicketDetailCustomer.fromJson(
                json['customer'] as Map<String, dynamic>,)
            : null,
        battery: json['battery'] is Map<String, dynamic>
            ? TicketDetailBattery.fromJson(
                json['battery'] as Map<String, dynamic>,)
            : null,
        attempts: (json['attempts'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(TicketDetailAttempt.fromJson)
                .toList() ??
            const [],
        createdAt: _tryDate(json['createdAt']),
        updatedAt: _tryDate(json['updatedAt']),
        riskTier: json['riskTier'] as String? ?? '',
        isEmergency: json['isEmergency'] as bool? ?? false,
        ertFlag: json['ertFlag'] as bool? ?? false,
        esvFlag: json['esvFlag'] as bool? ?? false,
        zoneCode: json['zoneCode'] as String? ?? '',
        routeCode: json['routeCode'] as String? ?? '',
        daysSinceLastAttempt:
            (json['daysSinceLastAttempt'] as num?)?.toInt() ?? 0,
      );
}

/// Agent sub-object of [TicketDetail].
class TicketDetailAgent {
  const TicketDetailAgent({
    required this.id,
    this.employeeId = '',
    this.fullName = '',
    this.phone = '',
    this.email = '',
    this.role = '',
    this.isActive = false,
    this.hubCode = '',
    this.clusterCode = '',
    this.zoneCode = '',
    this.routeCode = '',
    this.lastKnownLocation = '',
  });

  final String id;
  final String employeeId;
  final String fullName;
  final String phone;
  final String email;
  final String role;
  final bool isActive;
  final String hubCode;
  final String clusterCode;
  final String zoneCode;
  final String routeCode;
  final String lastKnownLocation;

  factory TicketDetailAgent.fromJson(Map<String, dynamic> json) =>
      TicketDetailAgent(
        id: json['id'] as String? ?? '',
        employeeId: json['employeeId'] as String? ?? '',
        fullName: json['fullName'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
        email: json['email'] as String? ?? '',
        role: json['role'] as String? ?? '',
        isActive: json['isActive'] as bool? ?? false,
        hubCode: json['hubCode'] as String? ?? '',
        clusterCode: json['clusterCode'] as String? ?? '',
        zoneCode: json['zoneCode'] as String? ?? '',
        routeCode: json['routeCode'] as String? ?? '',
        lastKnownLocation: json['lastKnownLocation']?.toString() ?? '',
      );
}

/// Customer sub-object of [TicketDetail]. Source of the three fields surfaced on
/// the BP detail card: [geoLocation] (Last Seen), [lastSwapDate] (Last TIU) and
/// [lastSwapStationCode] (Last Swap).
class TicketDetailCustomer {
  const TicketDetailCustomer({
    required this.id,
    this.externalId = '',
    this.fullName = '',
    this.phonePrimary = '',
    this.phoneSecondary = '',
    this.email = '',
    this.addressLine1 = '',
    this.city = '',
    this.state = '',
    this.pincode = '',
    this.geoLocation = '',
    this.bpType = '',
    this.lastSwapDate,
    this.lastSwapStationCode = '',
  });

  final String id;
  final String externalId;
  final String fullName;
  final String phonePrimary;
  final String phoneSecondary;
  final String email;
  final String addressLine1;
  final String city;
  final String state;
  final String pincode;

  /// Last-known geo position of the customer. The wire type is unspecified
  /// (null in samples); accepts either a JSON object ({lat,lng}) or a plain
  /// string and is normalised to a display string. → "Last Seen".
  final String geoLocation;

  final String bpType;

  /// → "Last TIU".
  final DateTime? lastSwapDate;

  /// → "Last Swap".
  final String lastSwapStationCode;

  factory TicketDetailCustomer.fromJson(Map<String, dynamic> json) =>
      TicketDetailCustomer(
        id: json['id'] as String? ?? '',
        externalId: json['externalId'] as String? ?? '',
        fullName: json['fullName'] as String? ?? '',
        phonePrimary: json['phonePrimary'] as String? ?? '',
        phoneSecondary: json['phoneSecondary'] as String? ?? '',
        email: json['email'] as String? ?? '',
        addressLine1: json['addressLine1'] as String? ?? '',
        city: json['city'] as String? ?? '',
        state: json['state'] as String? ?? '',
        pincode: json['pincode']?.toString() ?? '',
        geoLocation: _geoDisplay(json['geoLocation']),
        bpType: json['bpType'] as String? ?? '',
        lastSwapDate: _tryDate(json['lastSwapDate']),
        lastSwapStationCode: json['lastSwapStationCode'] as String? ?? '',
      );
}

/// Battery sub-object of [TicketDetail].
class TicketDetailBattery {
  const TicketDetailBattery({
    required this.id,
    this.bpId = '',
    this.status = '',
    this.zoneStatus = '',
    this.model = '',
    this.vehicleType = '',
    this.vehicleRegNo = '',
    this.vehicleId = '',
    this.soc,
    this.tiuStatus = '',
    this.tiuId = '',
    this.bpState = '',
    this.dealerName = '',
    this.dealerContact = '',
    this.serialNumber = '',
    this.condition = '',
    this.lastKnownLocation = '',
    this.lastPingAt,
    this.attemptCount = 0,
  });

  final String id;
  final String bpId;
  final String status;
  final String zoneStatus;
  final String model;
  final String vehicleType;
  final String vehicleRegNo;
  final String vehicleId;
  final int? soc;
  final String tiuStatus;
  final String tiuId;
  final String bpState;
  final String dealerName;
  final String dealerContact;
  final String serialNumber;
  final String condition;
  final String lastKnownLocation;
  final DateTime? lastPingAt;
  final int attemptCount;

  factory TicketDetailBattery.fromJson(Map<String, dynamic> json) =>
      TicketDetailBattery(
        id: json['id'] as String? ?? '',
        bpId: json['bpId'] as String? ?? '',
        status: json['status'] as String? ?? '',
        zoneStatus: json['zoneStatus'] as String? ?? '',
        model: json['model'] as String? ?? '',
        vehicleType: json['vehicleType'] as String? ?? '',
        vehicleRegNo: json['vehicleRegNo'] as String? ?? '',
        vehicleId: json['vehicleId'] as String? ?? '',
        soc: (json['soc'] as num?)?.toInt(),
        tiuStatus: json['tiuStatus'] as String? ?? '',
        tiuId: json['tiuId'] as String? ?? '',
        bpState: json['bpState'] as String? ?? '',
        dealerName: json['dealerName'] as String? ?? '',
        dealerContact: json['dealerContact'] as String? ?? '',
        serialNumber: json['serialNumber'] as String? ?? '',
        condition: json['condition'] as String? ?? '',
        lastKnownLocation: json['lastKnownLocation']?.toString() ?? '',
        lastPingAt: _tryDate(json['lastPingAt']),
        attemptCount: (json['attemptCount'] as num?)?.toInt() ?? 0,
      );
}

/// Attempt sub-object of [TicketDetail]. Distinct from the app's own [Attempt]
/// wizard model — this is the backend's persisted attempt record shape.
class TicketDetailAttempt {
  const TicketDetailAttempt({
    required this.id,
    this.ticketId = '',
    this.batteryId = '',
    this.agentId = '',
    this.agentName = '',
    this.attemptType = '',
    this.outcome = '',
    this.attemptedAt,
    this.completedAt,
    this.location = '',
    this.latitude,
    this.longitude,
    this.customerPresent = false,
    this.notes = '',
    this.proofUrls = const [],
    this.metadata,
  });

  final String id;
  final String ticketId;
  final String batteryId;
  final String agentId;
  final String agentName;
  final String attemptType;
  final String outcome;
  final DateTime? attemptedAt;
  final DateTime? completedAt;

  /// Raw location value as received (a JSON-encoded `{lat,lng}` object string).
  final String location;

  /// Latitude/longitude decoded from [location], when parseable.
  final double? latitude;
  final double? longitude;

  final bool customerPresent;
  final String notes;
  final List<String> proofUrls;
  final Map<String, dynamic>? metadata;

  factory TicketDetailAttempt.fromJson(Map<String, dynamic> json) {
    // `location` arrives as a JSON-encoded object string
    // (e.g. `"{\"lat\": 26.83, \"lng\": 75.68}"`); decode to lat/lng.
    final (lat, lng) = _latLng(json['location']);
    return TicketDetailAttempt(
      id: json['id'] as String? ?? '',
      ticketId: json['ticketId'] as String? ?? '',
      batteryId: json['batteryId'] as String? ?? '',
      agentId: json['agentId'] as String? ?? '',
      agentName: json['agentName'] as String? ?? '',
      attemptType: json['attemptType'] as String? ?? '',
      outcome: json['outcome'] as String? ?? '',
      attemptedAt: _tryDate(json['attemptedAt']),
      completedAt: _tryDate(json['completedAt']),
      location: json['location']?.toString() ?? '',
      latitude: lat,
      longitude: lng,
      customerPresent: json['customerPresent'] as bool? ?? false,
      notes: json['notes'] as String? ?? '',
      // `proofUrls` arrives as a JSON-encoded string (e.g. `"[\"...\"]"`) in
      // the current contract, but tolerate a real JSON array too.
      proofUrls: _stringList(json['proofUrls']),
      metadata: json['metadata'] is Map<String, dynamic>
          ? json['metadata'] as Map<String, dynamic>
          : null,
    );
  }
}

/// Lenient ISO-8601 parse for nullable date fields.
DateTime? _tryDate(Object? v) => v is String ? DateTime.tryParse(v) : null;

/// Decodes a location value into `(lat, lng)`. Accepts a real JSON object
/// (`{lat,lng}`) or a JSON-encoded object *string*
/// (`"{\"lat\": .., \"lng\": ..}"`); returns `(null, null)` when unparseable.
(double?, double?) _latLng(Object? v) {
  Map<dynamic, dynamic>? m;
  if (v is Map) {
    m = v;
  } else if (v is String) {
    final s = v.trim();
    if (s.startsWith('{') && s.endsWith('}')) {
      try {
        final decoded = jsonDecode(s);
        if (decoded is Map) m = decoded;
      } catch (_) {
        // Malformed location string — leave lat/lng null.
      }
    }
  }
  if (m == null) return (null, null);
  final lat = (m['lat'] ?? m['latitude']) as num?;
  final lng = (m['lng'] ?? m['longitude']) as num?;
  return (lat?.toDouble(), lng?.toDouble());
}

/// Normalises a geo value (JSON object `{lat,lng}`, a plain string, or null)
/// into a display string.
String _geoDisplay(Object? v) {
  if (v == null) return '';
  if (v is Map) {
    final lat = v['lat'] ?? v['latitude'];
    final lng = v['lng'] ?? v['longitude'];
    if (lat != null && lng != null) return '$lat, $lng';
    return v.toString();
  }
  return v.toString();
}

/// Coerces a proof-URL field that may be a JSON-encoded string, a real list,
/// or null into a `List<String>`.
List<String> _stringList(Object? v) {
  if (v == null) return const [];
  if (v is List) return v.map((e) => e.toString()).toList();
  if (v is String) {
    final s = v.trim();
    if (s.isEmpty) return const [];
    // Best-effort: strip the JSON array brackets/quotes without a full decode
    // (the caller only needs the URLs, and a malformed value shouldn't throw).
    if (s.startsWith('[') && s.endsWith(']')) {
      final inner = s.substring(1, s.length - 1);
      if (inner.trim().isEmpty) return const [];
      return inner
          .split(',')
          .map((e) => e.trim().replaceAll('"', '').replaceAll(r'\/', '/'))
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return [s];
  }
  return const [];
}
