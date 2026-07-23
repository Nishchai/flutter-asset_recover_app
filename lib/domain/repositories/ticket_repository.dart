import 'package:asset_recovery_app/domain/entities/agent.dart';
import 'package:asset_recovery_app/domain/entities/attempt.dart';
import 'package:asset_recovery_app/domain/entities/call_recording.dart';
import 'package:asset_recovery_app/domain/entities/customer.dart';
import 'package:asset_recovery_app/domain/entities/draft_attempt.dart';
import 'package:asset_recovery_app/domain/entities/geo_point.dart';
import 'package:asset_recovery_app/domain/entities/live_token_model.dart';
import 'package:asset_recovery_app/domain/entities/ticket.dart';

/// Backend-agnostic contract for all data access.
///
/// Two implementations exist:
///  * [MockTicketRepository] — seeded in-memory data (default; useMockData=true)
///  * [ApiTicketRepository]  — real HTTP backend (wired once endpoints arrive)
///
/// Screens depend ONLY on this interface, so switching backends is a one-line
/// change in the provider wiring. See docs/API_INTEGRATION.md.
abstract class TicketRepository {
  /// Validates [mobile] server-side and triggers an OTP send (mobile+OTP
  /// sign-in).
  Future<void> requestLoginOtp(String mobile);

  /// Verifies the OTP sent to [mobile] and returns the signed-in agent.
  Future<Agent> verifyLoginOtp(String mobile, String otp);

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

  /// Tickets assigned to [agentId], already scoped to the agent's cluster.
  Future<List<Ticket>> assignedTickets(String agentId);

  /// Aggregate shift counters for the home header: keys `assigned`,
  /// `inProgress`, `pending`.
  Future<Map<String, int>> shiftStats(String agentId);

  Future<Ticket> ticketDetail(String ticketId);

  /// Persists a completed attempt and returns the stored record (with id).
  Future<Attempt> submitAttempt(String ticketId, String bpId, Attempt attempt);

  /// Validates a scanned BP serial against the assigned ticket (PRD §4.9 / QR).
  Future<bool> validateScan(String ticketId, String bpId, String scannedSerial);

  /// Google road distance in km between two points (PRD §4.8). Mock falls back
  /// to a road-factor-adjusted haversine estimate.
  Future<double> roadDistanceKm(GeoPoint from, GeoPoint to);

  Future<void> updateCustomer(String bpId, Customer customer);

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
