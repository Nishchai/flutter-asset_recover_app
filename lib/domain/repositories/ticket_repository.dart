import 'package:asset_recovery_app/domain/entities/agent.dart';
import 'package:asset_recovery_app/domain/entities/attempt.dart';
import 'package:asset_recovery_app/domain/entities/attempt_submission.dart';
import 'package:asset_recovery_app/domain/entities/battery_detail.dart';
import 'package:asset_recovery_app/domain/entities/call_recording.dart';
import 'package:asset_recovery_app/domain/entities/customer.dart';
import 'package:asset_recovery_app/domain/entities/customer_details_update.dart';
import 'package:asset_recovery_app/domain/entities/draft_attempt.dart';
import 'package:asset_recovery_app/domain/entities/geo_point.dart';
import 'package:asset_recovery_app/domain/entities/live_token_model.dart';
import 'package:asset_recovery_app/domain/entities/partner_login_data.dart';
import 'package:asset_recovery_app/domain/entities/ticket.dart';
import 'package:asset_recovery_app/domain/entities/ticket_detail.dart';
import 'package:asset_recovery_app/domain/entities/ticket_page.dart';

/// Backend-agnostic contract for all data access.
///
/// Two implementations exist:
///  * [MockTicketRepository] — seeded in-memory data (default; useMockData=true)
///  * [ApiTicketRepository]  — real HTTP backend (wired once endpoints arrive)
///
/// Screens depend ONLY on this interface, so switching backends is a one-line
/// change in the provider wiring. See docs/API_INTEGRATION.md.
abstract class TicketRepository {
  /// Looks [mobile] up in the SM-Partners directory (`commonLogin`) and returns
  /// the agent record behind it. Step 1 of sign-in: it runs the moment the
  /// mobile number is submitted and must succeed before any OTP is sent.
  /// Throws when the number is unknown or the backend reports a failure.
  Future<PartnerLoginData> commonLogin(String mobile);

  /// Validates [mobile] server-side and triggers an OTP send (mobile+OTP
  /// sign-in).
  Future<void> requestLoginOtp(String mobile);

  /// Verifies the OTP sent to [mobile] and returns the signed-in agent.
  Future<Agent> verifyLoginOtp(String mobile, String otp);

  /// Sends the end-of-shift OTP to [mobile] — the signed-in agent's own
  /// `commonLogin` `usermobileNumber`, not a ticket- or BP-scoped number.
  ///
  /// [codeLength] is how many digits the gateway must generate. It has to match
  /// the length the end-shift sheet asks the agent to type, so it is required
  /// rather than defaulted to the login flow's configured length.
  Future<void> requestShiftEndOtp(String mobile, {required int codeLength});

  /// Verifies the end-of-shift OTP sent to [mobile]. Returns false for a wrong
  /// or expired code; throws only when the gateway itself fails.
  Future<bool> verifyShiftEndOtp(String mobile, String otp);

  /// Exchanges client credentials for a live access token (OAuth2
  /// client-credentials flow). [url] is the ABSOLUTE token endpoint — it is not
  /// resolved against `apiBaseUrl`. Mirrors the Java `getLiveToken` Retrofit
  /// call: a `application/x-www-form-urlencoded` POST with the given fields.
  Future<LiveTokenModel> generateAuthToken({
    required String url,
    required String clientId,
    required String resource,
    required String clientSecret,
    String grantType = 'client_credentials',
  });

  /// One page of the tickets assigned to [agentId], already scoped to the
  /// agent's cluster. [page] is 1-based; the home list walks it upwards as the
  /// agent scrolls, using [TicketPage.hasMore] to know when to stop.
  Future<TicketPage> assignedTickets(
    String agentId, {
    int page,
    int pageSize,
  });

  /// Aggregate shift counters for the home header: keys `assigned`,
  /// `inProgress`, `pending`.
  Future<Map<String, int>> shiftStats(String agentId);

  Future<Ticket> ticketDetail(String ticketId);

  /// Full, NESTED ticket detail (`GET /tickets/{UUID}`) fetched with the backend
  /// resource UUID ([Ticket.caseId] / the response `id`). Carries fields the
  /// flattened list summary omits — e.g. the customer's last-seen geo, last-swap
  /// date and last-swap station — surfaced on the BP detail screen.
  Future<TicketDetail> ticketFullDetail(String uuid);

  /// Live battery telemetry from the Battery Master API
  /// (`battery.getBatteryDetails`), keyed by the ticket's [bpId]. Supplies the
  /// BP detail screen's "Last Seen" (last lat/long) and "Last TIU" (last TIU
  /// timestamp). Null when the service returns no telemetry row for [bpId].
  Future<BatteryDetail?> batteryDetail(String bpId);

  /// Persists a completed attempt and returns the stored record (with id).
  Future<Attempt> submitAttempt(String ticketId, String bpId, Attempt attempt);

  /// Submits a completed attempt record to the standalone attempts service
  /// (`attempts.submit` — `POST /api/v1/attempts`). Fire-and-confirm; throws
  /// [ApiException] on a non-2xx response.
  Future<void> submitAttemptRecord(AttemptSubmission submission);

  /// Moves [ticketId] to [status] on the backend (`tickets.status` —
  /// `POST /tickets/status` with `{"ticketId": ..., "status": ...}`).
  /// [ticketId] is the human ticket number shown as "Case ID" on the ticket
  /// detail screen (e.g. `TKT-2026-00026`), NOT the resource UUID.
  Future<void> updateTicketStatus(String ticketId, String status);

  /// Validates a scanned BP serial against the assigned ticket (PRD §4.9 / QR).
  Future<bool> validateScan(String ticketId, String bpId, String scannedSerial);

  /// Google road distance in km between two points (PRD §4.8). Mock falls back
  /// to a road-factor-adjusted haversine estimate.
  Future<double> roadDistanceKm(GeoPoint from, GeoPoint to);

  Future<void> updateCustomer(String bpId, Customer customer);

  /// Patches the customer's address components and alternate number against
  /// the customers service. Targets `PATCH /api/v1/customers/{id}` when
  /// [CustomerDetailsUpdate.customerId] is set, falling back to the by-phone
  /// route otherwise. Throws [ApiException] on a non-2xx response.
  Future<void> updateCustomerByPhone(CustomerDetailsUpdate update);

  /// Reports the agent's current device position (`agent.location` —
  /// `PATCH /agents/location` with `{agentId, lat, lng}`). Fired whenever the
  /// agent lands on the home screen. Throws [ApiException] on a non-2xx.
  Future<void> updateAgentLocation(String agentId, GeoPoint position);

  /// Requests an OTP for store/ESV physical handover (PRD §5.1.6).
  Future<void> requestHandoverOtp(String bpId);

  Future<bool> verifyHandoverOtp(String bpId, String otp);

  /// Partially-completed attempt data for [bpId], if any (item 13 — free-choice
  /// actions persist across sessions until the Outcome action is submitted).
  Future<DraftAttempt?> getDraft(String bpId);

  Future<void> saveDraft(String bpId, DraftAttempt draft);

  /// Latest live BP location from the BP Live API (Rule 8b), which may have
  /// moved since [Battery.lastKnownLocation] was last synced.
  Future<GeoPoint> liveLocation(String bpId);

  /// Starts an in-app call via the configured telephony provider (Ozonetel —
  /// Rule 8a) and returns the resulting recording once the call ends.
  Future<CallRecording> startCall(String bpId, String phoneNumber);

  /// Prior call recordings for [bpId], most recent first.
  Future<List<CallRecording>> callRecordings(String bpId);

  /// Unassigned tickets within [radiusKm] of [near] (M1-02 — location-based
  /// pickup) — cases nobody's working yet that happen to sit on the agent's
  /// current route, sorted nearest-first.
  Future<List<Ticket>> nearbyUnassignedTickets(GeoPoint near, double radiusKm);

  /// Self-assigns [ticketId] to [agentId], moving it out of the unassigned
  /// pool and into that agent's ticket list.
  Future<Ticket> pickupTicket(String ticketId, String agentId);
}
