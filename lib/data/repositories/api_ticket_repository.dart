import 'dart:developer' as developer;

import 'package:asset_recovery_app/core/services/api_client.dart';
import 'package:asset_recovery_app/data/datasources/gupshup_otp_datasource.dart';
import 'package:asset_recovery_app/domain/entities/agent.dart';
import 'package:asset_recovery_app/domain/entities/attempt.dart';
import 'package:asset_recovery_app/domain/entities/attempt_submission.dart';
import 'package:asset_recovery_app/domain/entities/battery.dart';
import 'package:asset_recovery_app/domain/entities/battery_detail.dart';
import 'package:asset_recovery_app/domain/entities/call_recording.dart';
import 'package:asset_recovery_app/domain/entities/customer.dart';
import 'package:asset_recovery_app/domain/entities/draft_attempt.dart';
import 'package:asset_recovery_app/domain/entities/enums.dart';
import 'package:asset_recovery_app/domain/entities/geo_point.dart';
import 'package:asset_recovery_app/domain/entities/live_token_model.dart';
import 'package:asset_recovery_app/domain/entities/partner_login_data.dart';
import 'package:asset_recovery_app/domain/entities/ticket.dart';
import 'package:asset_recovery_app/domain/entities/ticket_detail.dart';
import 'package:asset_recovery_app/domain/repositories/ticket_repository.dart';

/// Real backend implementation. Wired through [ApiClient] + `api_endpoints.json`.
///
/// The request/response JSON shapes below are best-effort placeholders aligned
/// to the model `fromJson`/`toJson`. Once the backend contract is finalised,
/// adjust ONLY the mapping lines marked `// MAP:` — endpoints themselves are
/// config, not code. See docs/API_INTEGRATION.md.
class ApiTicketRepository implements TicketRepository {
  ApiTicketRepository(this._api, this._gupshup);

  final ApiClient _api;
  final GupshupOtpDataSource _gupshup;

  /// Logs the raw response received from [endpoint] so backend contracts can be
  /// verified during integration. Visible via `dart:developer` (DevTools/IDE).
  void _logResponse(String endpoint, Object? response) {
    developer.log('[$endpoint] response: $response',
        name: 'ApiTicketRepository',);
  }

  /// Maps one entry from the backend ticket-list envelope
  /// (`{"items":[...], "page":.., "pageSize":.., "total":..}`) into the app's
  /// [Ticket]/[Battery] model.
  ///
  /// The backend returns a FLATTENED ticket+BP summary (one BP per ticket in
  /// Phase 1), so the single [Battery] is reconstructed here rather than read
  /// from a nested `batteries` array. Adjust only the `// MAP:` lines if the
  /// contract changes.
  Ticket _ticketFromListItem(Map<String, dynamic> json) {
    final battery = Battery(
      bpId: json['bpId'] as String? ?? '', // MAP: bpId
      // riskTier ("theft"/"standard") is the closest field to the app's
      // case-type concept; fall back to source, then Manual.
      caseType:
          (json['riskTier'] ?? json['source'] ?? 'Manual').toString(), // MAP: riskTier
      customer: Customer(
        name: json['customerName'] as String? ?? '', // MAP: customerName
        mobile: json['customerMobile'] as String? ?? '',
        address: json['customerAddress'] as String? ?? '',
      ),
      // lastKnownLocation is nullable on the wire (null in the current
      // response); the model field is non-null, so fall back to (0,0) until a
      // real fix is captured in the field.
      lastKnownLocation: json['lastKnownLocation'] is Map<String, dynamic>
          ? GeoPoint.fromJson(json['lastKnownLocation'] as Map<String, dynamic>)
          : const GeoPoint(lat: 0, lng: 0), // MAP: lastKnownLocation
      zoneStatus: zoneFromString(json['zoneStatus'] as String?),
      bpState: bpStateFromString(json['bpState'] as String?),
      vehicleType: json['vehicleType'] as String? ?? '', // MAP: vehicleType
      vehicleRegNo: json['vehicleRegNo'] as String? ?? '', // MAP: vehicleRegNo
      bpType: json['bpType'] as String? ?? '', // MAP: bpType
      soc: (json['soc'] as num?)?.toInt(), // MAP: soc
      distanceKm: (json['distanceKm'] as num?)?.toDouble(), // MAP: distanceKm
      zone: json['zoneCode'] as String? ?? '', // MAP: zoneCode
      lastStation: json['lastSwapStationCode'] as String? ?? '', // MAP: lastSwapStationCode
      lastSwap: _tryDate(json['lastSwapDate']), // MAP: lastSwapDate
    );

    return Ticket(
      // MAP: `ticketNumber` (e.g. TKT-2026-00003) is the human-facing label
      // shown on the card and used for local lookup. The backend `id` is the
      // resource UUID — if the attempt/pickup endpoints expect the UUID in
      // their `{ticketId}` path segment, switch this to `json['id']`.
      ticketId: json['ticketNumber'] as String? ?? json['id'] as String? ?? '',
      status: TicketStatus.fromString(json['status'] as String?),
      createdAt: _tryDate(json['createdAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      assignedAgentId: json['agentId'] as String? ?? '', // MAP: agentId
      agentName: json['agentName'] as String? ?? '', // MAP: agentName
      cluster: json['clusterCode'] as String? ?? '', // MAP: clusterCode
      caseId: json['id'] as String? ?? '', // MAP: backend resource UUID
      caseSource: json['source'] as String? ?? '', // MAP: source
      priority: (json['priority'] as num?)?.toInt() ?? 0, // MAP: priority
      slaDeadline: _tryDate(json['slaDeadline']), // MAP: slaDeadline
      overdueDays: (json['overdueDays'] as num?)?.toInt() ?? 0, // MAP: overdueDays
      resolutionType: json['resolutionType'] as String? ?? '', // MAP: resolutionType
      isEmergency: json['isEmergency'] as bool? ?? false, // MAP: isEmergency
      routeCode: json['routeCode'] as String? ?? '', // MAP: routeCode
      daysSinceLastAttempt:
          (json['daysSinceLastAttempt'] as num?)?.toInt() ?? 0, // MAP: daysSinceLastAttempt
      batteryCount: (json['batteryCount'] as num?)?.toInt() ?? 0, // MAP: batteryCount
      batteries: [battery],
    );
  }

  /// Lenient ISO-8601 parse for nullable date fields.
  DateTime? _tryDate(Object? v) =>
      v is String ? DateTime.tryParse(v) : null;

  @override
  Future<PartnerLoginData> commonLogin(String mobile) async {
    // `appName` is baked into the configured absolute URL; only the mobile
    // number is appended here — Uri percent-encodes it, matching the legacy
    // Java string concatenation (`...commonLogin?userMobilenumber=<m>&appName=...`).
    final res = await _api.call('auth.commonLogin', query: {
      'userMobilenumber': mobile,
    },);
    _logResponse('auth.commonLogin', res);

    // Envelope: {"status": 200, "reason": "...", "data": {...}}. Anything else
    // (unknown number, backend failure) is surfaced with the server's `reason`
    // so the login screen can show why the number was rejected.
    final envelope = res as Map<String, dynamic>?;
    final status = (envelope?['status'] as num?)?.toInt(); // MAP: status
    final reason = envelope?['reason'] as String? ?? ''; // MAP: reason
    final data = envelope?['data']; // MAP: data
    if (data is! Map<String, dynamic> || (status != null && status != 200)) {
      throw ApiException(
        reason.isEmpty ? 'Login failed for $mobile' : reason,
        statusCode: status,
      );
    }
    return PartnerLoginData.fromJson(data);
  }

  @override
  Future<void> requestLoginOtp(String mobile) =>
      _gupshup.sendOtp(mobile);

  @override
  Future<Agent> verifyLoginOtp(String mobile, String otp) async {
    // Gupshup validates the code itself; it does NOT return an app session.
    final matched = await _gupshup.verifyOtp(mobile, otp);
    if (!matched) {
      throw ApiException('Invalid or expired OTP');
    }
    // Gupshup returns no profile, so this is only a fallback identity: the real
    // agent record comes from [commonLogin] in step 1 of the login and is what
    // VerifyLoginOtpUseCase actually keeps (see AuthenticatedSession.agent).
    return Agent(
      id: mobile,
      name: '',
      cluster: '',
      recoveredCount: 0,
      phone: mobile,
    );
  }

  @override
  Future<LiveTokenModel> generateAuthToken({
    required String url,
    required String clientId,
    required String resource,
    required String clientSecret,
    String grantType = 'client_credentials',
  }) async {
    final res = await _api.postForm(url, {
      'client_id': clientId,
      'resource': resource,
      'client_secret': clientSecret,
      'grant_type': grantType,
    });
    _logResponse('auth.liveToken', {...res, 'access_token': '***'}); // never log the token
    final model = LiveTokenModel.fromJson(res);
    // Attach for every subsequent request; ApiClient sends it as `Bearer`.
    _api.authToken = model.accessToken;
    return model;
  }

  @override
  Future<List<Ticket>> assignedTickets(String agentId) async {
    // agentId is attached globally by ApiClient; only paging is passed here.
    final res = await _api.call('tickets.assigned', query: {
      'page': '1',
      'pageSize': '20',
    },);
    _logResponse('tickets.assigned', res);
    final list = (res as Map<String, dynamic>)['items'] as List; // MAP: items
    return list
        .map((e) => _ticketFromListItem(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<Map<String, int>> shiftStats(String agentId) async {
    final res = await _api.call('tickets.stats', pathParams: {'agentId': agentId})
        as Map<String, dynamic>;
    _logResponse('tickets.stats', res);
    return {
      'assigned': (res['assigned'] as num?)?.toInt() ?? 0, // MAP: counters
      'inProgress': (res['inProgress'] as num?)?.toInt() ?? 0,
      'pending': (res['pending'] as num?)?.toInt() ?? 0,
    };
  }

  @override
  Future<Ticket> ticketDetail(String ticketId) async {
    final res = await _api.call('tickets.detail', pathParams: {'ticketId': ticketId});
    _logResponse('tickets.detail', res);
    return _ticketFromListItem(res as Map<String, dynamic>);
  }

  @override
  Future<TicketDetail> ticketFullDetail(String uuid) async {
    final res =
        await _api.call('tickets.fullDetail', pathParams: {'ticketId': uuid});
    _logResponse('tickets.fullDetail', res);
    return TicketDetail.fromJson(res as Map<String, dynamic>);
  }

  @override
  Future<BatteryDetail?> batteryDetail(String bpId) async {
    final res =
        await _api.call('battery.getBatteryDetails', pathParams: {'bpId': bpId});
    _logResponse('battery.getBatteryDetails', res);
    if (res is! Map<String, dynamic>) return null;
    return BatteryDetail.fromEnvelope(res); // MAP: envelope -> result[0]
  }

  @override
  Future<Attempt> submitAttempt(
      String ticketId, String bpId, Attempt attempt,) async {
    final res = await _api.call(
      'attempts.create',
      pathParams: {'ticketId': ticketId, 'bpId': bpId},
      body: attempt.toJson(),
    );
    _logResponse('attempts.create', res);
    return Attempt.fromJson(res as Map<String, dynamic>);
  }

  @override
  Future<void> submitAttemptRecord(AttemptSubmission submission) async {
    // Absolute-URL endpoint: ApiClient sends the body verbatim with no
    // apiBaseUrl prefix and no agentId query param (contract accepts none).
    final res = await _api.call('attempts.submit', body: submission.toJson());
    _logResponse('attempts.submit', res);
  }

  @override
  Future<bool> validateScan(
      String ticketId, String bpId, String scannedSerial,) async {
    final res = await _api.call('qr.validate', body: {
      'ticketId': ticketId,
      'bpId': bpId,
      'serial': scannedSerial,
    },) as Map<String, dynamic>;
    _logResponse('qr.validate', res);
    return res['valid'] == true; // MAP: valid flag
  }

  @override
  Future<double> roadDistanceKm(GeoPoint from, GeoPoint to) async {
    final res = await _api.call('distance.roadDistance', query: {
      'fromLat': '${from.lat}',
      'fromLng': '${from.lng}',
      'toLat': '${to.lat}',
      'toLng': '${to.lng}',
    },) as Map<String, dynamic>;
    _logResponse('distance.roadDistance', res);
    return (res['distanceKm'] as num).toDouble(); // MAP: distanceKm
  }

  @override
  Future<void> updateCustomer(String bpId, Customer customer) async {
    final res = await _api.call('customer.update',
        pathParams: {'bpId': bpId}, body: customer.toJson(),);
    _logResponse('customer.update', res);
  }

  @override
  Future<void> requestHandoverOtp(String bpId) async {
    final res = await _api.call('otp.request', body: {'bpId': bpId});
    _logResponse('otp.request', res);
  }

  @override
  Future<bool> verifyHandoverOtp(String bpId, String otp) async {
    final res = await _api.call('otp.verify', body: {'bpId': bpId, 'otp': otp})
        as Map<String, dynamic>;
    _logResponse('otp.verify', res);
    return res['verified'] == true; // MAP: verified flag
  }

  @override
  Future<DraftAttempt?> getDraft(String bpId) async {
    final res = await _api.call('drafts.get', pathParams: {'bpId': bpId});
    _logResponse('drafts.get', res);
    if (res == null) return null;
    return DraftAttempt.fromJson(res as Map<String, dynamic>); // MAP: draft shape
  }

  @override
  Future<void> saveDraft(String bpId, DraftAttempt draft) async {
    final res = await _api.call('drafts.save',
        pathParams: {'bpId': bpId}, body: draft.toJson(),);
    _logResponse('drafts.save', res);
  }

  @override
  Future<GeoPoint> liveLocation(String bpId) async {
    final res = await _api.call('bp.liveLocation', pathParams: {'bpId': bpId});
    _logResponse('bp.liveLocation', res);
    return GeoPoint.fromJson(res as Map<String, dynamic>); // MAP: live location shape
  }

  @override
  Future<CallRecording> startCall(String bpId, String phoneNumber) async {
    final res = await _api.call('calls.start',
        body: {'bpId': bpId, 'phoneNumber': phoneNumber},) as Map<String, dynamic>;
    _logResponse('calls.start', res);
    return CallRecording.fromJson(res); // MAP: Ozonetel call-session shape
  }

  @override
  Future<List<CallRecording>> callRecordings(String bpId) async {
    final res = await _api.call('calls.recordings', pathParams: {'bpId': bpId});
    _logResponse('calls.recordings', res);
    final list = (res as Map<String, dynamic>)['recordings'] as List; // MAP: recordings
    return list.map((e) => CallRecording.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<List<Ticket>> nearbyUnassignedTickets(GeoPoint near, double radiusKm) async {
    final res = await _api.call('tickets.nearbyUnassigned', query: {
      'lat': '${near.lat}',
      'lng': '${near.lng}',
      'radiusKm': '$radiusKm',
    },);
    _logResponse('tickets.nearbyUnassigned', res);
    final list = (res as Map<String, dynamic>)['items'] as List; // MAP: items
    return list
        .map((e) => _ticketFromListItem(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<Ticket> pickupTicket(String ticketId, String agentId) async {
    final res = await _api.call('tickets.pickup',
        pathParams: {'ticketId': ticketId}, body: {'agentId': agentId},);
    _logResponse('tickets.pickup', res);
    return _ticketFromListItem(res as Map<String, dynamic>);
  }
}
