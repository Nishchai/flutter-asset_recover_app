import 'dart:developer' as developer;

import 'package:asset_recovery_app/core/services/api_client.dart';
import 'package:asset_recovery_app/data/datasources/gupshup_otp_datasource.dart';
import 'package:asset_recovery_app/domain/entities/agent.dart';
import 'package:asset_recovery_app/domain/entities/attempt.dart';
import 'package:asset_recovery_app/domain/entities/call_recording.dart';
import 'package:asset_recovery_app/domain/entities/customer.dart';
import 'package:asset_recovery_app/domain/entities/draft_attempt.dart';
import 'package:asset_recovery_app/domain/entities/geo_point.dart';
import 'package:asset_recovery_app/domain/entities/live_token_model.dart';
import 'package:asset_recovery_app/domain/entities/ticket.dart';
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
    // MAP: with direct-to-Gupshup verification there is no backend token/agent
    // in this response. Fetch the agent profile for the verified [mobile] here
    // once that endpoint exists (e.g. `_api.call('auth.me', ...)`), and set
    // `_api.authToken`. For now a minimal agent keyed on the mobile number is
    // returned so the existing session/UI flow works unchanged.
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
    return LiveTokenModel.fromJson(res);
  }

  @override
  Future<List<Ticket>> assignedTickets(String agentId) async {
    final res = await _api.call('tickets.assigned', pathParams: {'agentId': agentId});
    _logResponse('tickets.assigned', res);
    final list = (res as Map<String, dynamic>)['tickets'] as List; // MAP: tickets
    return list.map((e) => Ticket.fromJson(e as Map<String, dynamic>)).toList();
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
    return Ticket.fromJson(res as Map<String, dynamic>);
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
    final list = (res as Map<String, dynamic>)['tickets'] as List; // MAP: tickets
    return list.map((e) => Ticket.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<Ticket> pickupTicket(String ticketId, String agentId) async {
    final res = await _api.call('tickets.pickup',
        pathParams: {'ticketId': ticketId}, body: {'agentId': agentId},);
    _logResponse('tickets.pickup', res);
    return Ticket.fromJson(res as Map<String, dynamic>);
  }
}
