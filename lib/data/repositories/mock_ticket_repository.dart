import 'dart:async';
import 'dart:math';

import 'package:asset_recovery_app/domain/entities/agent.dart';
import 'package:asset_recovery_app/domain/entities/attempt.dart';
import 'package:asset_recovery_app/domain/entities/attempt_submission.dart';
import 'package:asset_recovery_app/domain/entities/battery.dart';
import 'package:asset_recovery_app/domain/entities/battery_detail.dart';
import 'package:asset_recovery_app/domain/entities/call_recording.dart';
import 'package:asset_recovery_app/domain/entities/customer.dart';
import 'package:asset_recovery_app/domain/entities/customer_details_update.dart';
import 'package:asset_recovery_app/domain/entities/draft_attempt.dart';
import 'package:asset_recovery_app/domain/entities/enums.dart';
import 'package:asset_recovery_app/domain/entities/geo_point.dart';
import 'package:asset_recovery_app/domain/entities/live_token_model.dart';
import 'package:asset_recovery_app/domain/entities/partner_login_data.dart';
import 'package:asset_recovery_app/domain/entities/ticket.dart';
import 'package:asset_recovery_app/domain/entities/ticket_detail.dart';
import 'package:asset_recovery_app/domain/repositories/ticket_repository.dart';

/// In-memory backend seeded with data that mirrors the Asset Assurance Figma
/// flows (agent Rohan M., BP-IF-… serials, TKT-48217 tickets).
///
/// Lets the entire app run end-to-end with NO backend. Pass [seed] (test env)
/// for reproducible data and [latency] = Duration.zero to make tests instant.
class MockTicketRepository implements TicketRepository {
  MockTicketRepository({
    int? seed,
    this.latency = const Duration(milliseconds: 350),
    this.otpLength = 6,
  }) : _rng = Random(seed ?? 7) {
    _seedData();
  }

  final Duration latency;

  /// Number of digits [verifyLoginOtp] accepts, mirroring the active
  /// environment's `gupshup.otpCodeLength` (the login OTP UI renders exactly
  /// this many boxes). Wired from config in the injector.
  final int otpLength;

  final Random _rng;

  late Agent _agent;
  final List<Ticket> _tickets = [];
  final List<Ticket> _unassigned = [];
  final Map<String, DraftAttempt> _drafts = {};
  final Map<String, List<CallRecording>> _callRecordings = {};

  Future<T> _delayed<T>(T value) async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    return value;
  }

  // Reference point: SUN Mobility, Bengaluru South.
  static const _base = GeoPoint(lat: 12.9352, lng: 77.6245);

  void _seedData() {
    _agent = const Agent(
      id: 'FA-RM-01',
      name: 'Rohan M.',
      cluster: 'Bengaluru South',
      zone: 'Zone 4',
      recoveredCount: 47,
      phone: '+91 98765 43210',
      currentLocation: GeoPoint(lat: 12.9352, lng: 77.6245),
    );

    // Anchored to real time (not a fixed past date) so SLA countdowns and the
    // Rule 7 auto-expiry sweep behave sensibly whenever the app actually runs.
    final now = DateTime.now();

    _tickets.addAll([
      _ticket(
        id: 'TKT-48217',
        status: TicketStatus.assigned,
        createdDaysAgo: 84,
        now: now,
        reason: 'Inactive 30 days · BP movement alert',
        caseId: 'AAR-48217',
        caseSource: 'Theft Dashboard',
        bp: _bp(
          id: 'BP-IF-09823-A',
          caseType: 'Theft',
          custName: 'Gulshan Kumar',
          mobile: '9811100190',
          lat: 12.9145,
          lng: 77.6010,
          vin: 'MD9KS5C46N125679',
          reg: 'DL 1CP 5689 P',
          vehicleId: 'FLT-09823',
          station: 'ATOM-BLR-217, Jayanagar',
          zone: 'Bengaluru South',
          subzone: 'Jayanagar',
          inactiveDays: 30,
          attempts: 0,
          now: now,
        ),
      ),
      _ticket(
        id: 'TKT-48231',
        status: TicketStatus.inProgress,
        createdDaysAgo: 12,
        now: now,
        reason: 'Theft dashboard case',
        caseId: 'AAR-48231',
        caseSource: 'TIU Inactivity Alert',
        bp: _bp(
          id: 'BP-IF-10044-D',
          caseType: 'At-Risk',
          custName: 'Rohit Sharma',
          mobile: '9811100244',
          lat: 12.9279,
          lng: 77.6271,
          vin: 'MD9KS5C46N130044',
          reg: 'KA 05 CP 7741',
          vehicleId: 'FLT-10044',
          station: 'ATOM-BLR-118, BTM',
          zone: 'Bengaluru South',
          subzone: 'BTM Layout',
          inactiveDays: 14,
          attempts: 1,
          now: now,
        ),
      ),
      _ticket(
        id: 'TKT-48256',
        status: TicketStatus.pending,
        createdDaysAgo: 40,
        now: now,
        reason: 'FIR raised · awaiting coordinator confirmation',
        caseId: 'AAR-48256',
        caseSource: 'Impound Registry',
        bp: _bp(
          id: 'BP-IF-10097-P',
          caseType: 'Impound',
          custName: 'Manoj Gupta',
          mobile: '9811100097',
          lat: 12.8703,
          lng: 77.6045,
          vin: 'MD9KS5C46N130097',
          reg: 'KA 02 EV 3321',
          vehicleId: '',
          station: 'ATOM-BLR-302, HSR',
          zone: 'Bengaluru South',
          subzone: 'HSR Layout',
          inactiveDays: 22,
          attempts: 2,
          now: now,
        ),
      ),
      _closedTicket(now),
    ]);

    // M1-02 — unassigned pool an agent can pick up if it falls on their
    // route, distinct from `_tickets` (their own assigned work list).
    _unassigned.addAll([
      _ticket(
        id: 'TKT-48302',
        status: TicketStatus.assigned,
        createdDaysAgo: 3,
        now: now,
        reason: 'Unassigned — awaiting pickup',
        caseId: 'AAR-48302',
        caseSource: 'Theft Dashboard',
        bp: _bp(
          id: 'BP-IF-10205-Q',
          caseType: 'At-Risk',
          custName: 'Farida Sheikh',
          mobile: '9811100305',
          lat: 12.9198,
          lng: 77.6350,
          vin: 'MD9KS5C46N130205',
          reg: 'KA 03 CP 4471',
          vehicleId: 'FLT-10205',
          station: 'ATOM-BLR-118, BTM',
          zone: 'Bengaluru South',
          subzone: 'Koramangala',
          inactiveDays: 4,
          attempts: 0,
          now: now,
        ),
      )..assignedAgentId = '',
      _ticket(
        id: 'TKT-48311',
        status: TicketStatus.assigned,
        createdDaysAgo: 1,
        now: now,
        reason: 'Unassigned — awaiting pickup',
        caseId: 'AAR-48311',
        caseSource: 'Manual',
        bp: _bp(
          id: 'BP-IF-10218-R',
          caseType: 'Manual',
          custName: 'Vikram Nair',
          mobile: '9811100318',
          lat: 12.9420,
          lng: 77.6180,
          vin: 'MD9KS5C46N130218',
          reg: 'KA 04 CP 5582',
          vehicleId: '',
          station: 'ATOM-BLR-217, Jayanagar',
          zone: 'Bengaluru South',
          subzone: 'Jayanagar',
          inactiveDays: 1,
          attempts: 0,
          now: now,
        ),
      )..assignedAgentId = '',
    ]);
  }

  Ticket _ticket({
    required String id,
    required TicketStatus status,
    required int createdDaysAgo,
    required DateTime now,
    required String reason,
    required Battery bp,
    String caseId = '',
    String caseSource = '',
  }) {
    return Ticket(
      ticketId: id,
      status: status,
      createdAt: now.subtract(Duration(days: createdDaysAgo)),
      assignedAgentId: 'FA-RM-01',
      cluster: 'Bengaluru South',
      reason: reason,
      caseId: caseId,
      caseSource: caseSource,
      batteries: [bp],
    );
  }

  Battery _bp({
    required String id,
    required String caseType,
    required String custName,
    required String mobile,
    required double lat,
    required double lng,
    required String vin,
    required String reg,
    required String station,
    required int inactiveDays,
    required int attempts,
    required DateTime now,
    String vehicleId = '',
    String zone = '',
    String subzone = '',
  }) {
    final loc = GeoPoint(lat: lat, lng: lng);
    // Stand-in for the ML layer's risk_scores output (M2-03) — real scoring
    // happens server-side; the mock just approximates from case severity +
    // how long the BP has been inactive, purely so the read-only UI has
    // something representative to render.
    final riskScore = ((caseType == 'Theft' ? 55.0 : caseType == 'At-Risk' ? 35.0 : 15.0) +
            inactiveDays * 0.6 + attempts * 4)
        .clamp(0, 100)
        .toDouble();
    final riskCategory =
        riskScore >= 70 ? 'high' : (riskScore >= 40 ? 'medium' : 'low');
    final bp = Battery(
      bpId: id,
      caseType: caseType,
      riskScore: riskScore,
      riskCategory: riskCategory,
      customer: Customer(
        name: custName,
        mobile: mobile,
        address: 'A-646/B, 22nd Cross, JP Nagar, Bengaluru, 560078',
        homeLocation: loc,
      ),
      lastKnownLocation: loc,
      zoneStatus: ZoneStatus.field,
      bpState: BpState.values[_rng.nextInt(3)],
      dealerName: 'SUN Mobility Dealer ${_rng.nextInt(40) + 1}',
      dealerContact: '+91 98${_rng.nextInt(90000000) + 10000000}',
      vehicleType: '3W - Passenger Auto',
      vehicleRegNo: reg,
      vehicleId: vehicleId,
      zone: zone,
      subzone: subzone,
      vin: vin,
      tiuStatus: _rng.nextBool() ? 'Online' : 'Offline',
      lastStation: station,
      lastTiuTime: '12 : 30 : 27 PM',
      lastSwap: now.subtract(const Duration(days: 61)),
      inactiveDays: inactiveDays,
      soc: _rng.nextInt(100),
      homeAddress: 'JP Nagar, Bengaluru',
      distanceKm: double.parse(
        (_base.haversineMeters(loc) / 1000 * 1.35).toStringAsFixed(1),
      ),
    );
    for (var i = 0; i < attempts; i++) {
      bp.attempts.add(
        Attempt(
          id: '${id}_A${i + 1}',
          bpId: id,
          sequence: i + 1,
          createdAt: now.subtract(Duration(days: attempts - i, hours: 2)),
          gps: loc,
          outcome: 'not_found_refused',
          resolution: '',
          values: const {
            'callStatus': 'connected',
            'visitStatus': 'visit_done',
            'outcome': 'not_found_refused',
          },
          proofs: const [],
          remark: 'Customer present but refused to return BP.',
        ),
      );
    }
    return bp;
  }

  Ticket _closedTicket(DateTime now) {
    const loc = GeoPoint(lat: 12.9648, lng: 77.6167);
    final bp = Battery(
      bpId: 'BP-IF-09780-S',
      caseType: 'Theft',
      customer: const Customer(
          name: 'Alok Nath', mobile: '9811100099', address: 'BTM Layout, Bengaluru',),
      lastKnownLocation: loc,
      zoneStatus: ZoneStatus.deployed,
      bpState: BpState.idle,
      vin: 'MD9KS5C46N109780',
      vehicleRegNo: 'KA 01 CP 1122',
      vehicleType: '3W - Passenger Auto',
      lastStation: 'ATOM-BLR-217, Jayanagar',
      distanceKm: 5.2,
      attempts: [
        Attempt(
          id: 'BP-IF-09780-S_A1',
          bpId: 'BP-IF-09780-S',
          sequence: 1,
          createdAt: now.subtract(const Duration(days: 45)),
          gps: loc,
          outcome: 'swap_organic',
          resolution: 'Swap (Organic)',
          values: const {'outcome': 'swap_organic'},
          proofs: const [],
          remark: 'Customer cooperative. BP swapped on first visit.',
        ),
      ],
    );
    return Ticket(
      ticketId: 'TKT-48109',
      status: TicketStatus.closed,
      createdAt: now.subtract(const Duration(days: 45)),
      closedAt: now,
      assignedAgentId: 'FA-RM-01',
      cluster: 'Bengaluru South',
      reason: 'Recovered via organic swap',
      batteries: [bp],
    );
  }

  // --- TicketRepository -------------------------------------------------------

  /// Mirrors a successful `commonLogin` for the seeded agent, so demo/mock mode
  /// walks the same two-step login as the real backend: any 10-digit number is
  /// "found" in the directory.
  ///
  /// `partnerId` — which `toAgent()` turns into the session's agent id — is the
  /// seeded agent's id, since every ticket in this mock is assigned to that one
  /// id and would otherwise filter out to an empty list.
  @override
  Future<PartnerLoginData> commonLogin(String mobile) => _delayed(
        PartnerLoginData(
          usermobileNumber: mobile,
          userId: _agent.id,
          apppartneruserId: 1,
          appId: 1,
          partnerId: _agent.id,
          isActive: true,
          isLoggedIn: true,
          userName: _agent.name,
          userRole: _agent.role.name,
          emailId: 'rohan.m@example.com',
        ),
      );

  @override
  Future<void> requestLoginOtp(String mobile) => _delayed(null);

  @override
  Future<Agent> verifyLoginOtp(String mobile, String otp) {
    if (!RegExp('^\\d{$otpLength}\$').hasMatch(otp)) {
      throw const FormatException('Invalid OTP');
    }
    return _delayed(_agent);
  }

  /// Digits the last end-shift OTP was requested with; [verifyShiftEndOtp]
  /// accepts any code of exactly that length, so the mock stays in step with
  /// whatever the end-shift sheet asks for.
  int _shiftOtpLength = 6;

  @override
  Future<void> requestShiftEndOtp(String mobile, {required int codeLength}) {
    _shiftOtpLength = codeLength;
    return _delayed(null);
  }

  @override
  Future<bool> verifyShiftEndOtp(String mobile, String otp) =>
      _delayed(RegExp('^\\d{$_shiftOtpLength}\$').hasMatch(otp));

  @override
  Future<LiveTokenModel> generateAuthToken({
    required String url,
    required String clientId,
    required String resource,
    required String clientSecret,
    String grantType = 'client_credentials',
  }) =>
      _delayed(LiveTokenModel(
        accessToken: 'mock-token-${clientId.hashCode.toUnsigned(32)}',
        resource: resource,
        expiresIn: 3599,
      ),);

  @override
  Future<List<Ticket>> assignedTickets(String agentId) =>
      _delayed(_tickets.where((t) => t.assignedAgentId == agentId).toList());

  @override
  Future<Map<String, int>> shiftStats(String agentId) =>
      // Aggregate counts shown on the home header. In production these come from
      // the backend; the detailed list above is the (paginated) working set.
      _delayed(const {'assigned': 27, 'inProgress': 16, 'pending': 11});

  @override
  Future<Ticket> ticketDetail(String ticketId) =>
      _delayed(_tickets.firstWhere((t) => t.ticketId == ticketId));

  @override
  Future<TicketDetail> ticketFullDetail(String uuid) {
    // Match on the backend UUID ([Ticket.caseId]); fall back to the human
    // ticket number so the mock resolves regardless of which id the caller has.
    final t = _tickets.firstWhere(
      (t) => t.caseId == uuid || t.ticketId == uuid,
      orElse: () => _tickets.first,
    );
    final bp = t.primaryBp;
    return _delayed(TicketDetail(
      id: t.caseId.isEmpty ? t.ticketId : t.caseId,
      ticketNumber: t.ticketId,
      status: t.status.wire,
      priority: t.priority,
      source: t.caseSource,
      slaDeadline: t.slaDeadline,
      overdueDays: t.overdueDays,
      clusterCode: t.cluster,
      reassignCount: t.reassignmentCount,
      assignedAt: t.createdAt,
      closedAt: t.closedAt,
      resolutionType: t.resolutionType,
      customer: TicketDetailCustomer(
        id: '',
        fullName: bp.customer.name,
        phonePrimary: bp.customer.mobile,
        addressLine1: bp.customer.address,
        geoLocation: bp.lastKnownLocation.display,
        lastSwapDate: bp.lastSwap,
        lastSwapStationCode: bp.lastStation,
      ),
      battery: TicketDetailBattery(
        id: '',
        bpId: bp.bpId,
        vehicleType: bp.vehicleType,
        vehicleRegNo: bp.vehicleRegNo,
        soc: bp.soc,
        attemptCount: bp.attemptCount,
      ),
      createdAt: t.createdAt,
      updatedAt: t.createdAt,
      riskTier: bp.caseType,
      isEmergency: t.isEmergency,
      routeCode: t.routeCode,
      daysSinceLastAttempt: t.daysSinceLastAttempt,
    ),);
  }

  @override
  Future<BatteryDetail?> batteryDetail(String bpId) {
    // No real Battery Master API in mock mode — synthesise telemetry from the
    // seeded BP so "Last Seen"/"Last TIU" render end-to-end without a backend.
    for (final t in _tickets) {
      for (final bp in t.batteries) {
        if (bp.bpId == bpId) {
          final loc = bp.lastKnownLocation;
          return _delayed(BatteryDetail(
            batterySerialNumber: bp.bpId,
            lastLatitude: loc.lat,
            lastLongitude: loc.lng,
            lastTiuTimestamp:
                (bp.lastSwap ?? DateTime.now()).subtract(const Duration(hours: 3)),
            lastSoc: bp.soc?.toDouble(),
          ),);
        }
      }
    }
    return _delayed(null);
  }

  @override
  Future<Attempt> submitAttempt(
      String ticketId, String bpId, Attempt attempt,) async {
    final ticket = _tickets.firstWhere((t) => t.ticketId == ticketId);
    final bp = ticket.batteries.firstWhere((b) => b.bpId == bpId);
    final stored = Attempt(
      id: '${bpId}_A${bp.attemptCount + 1}',
      bpId: bpId,
      sequence: bp.attemptCount + 1,
      createdAt: attempt.createdAt,
      gps: attempt.gps,
      outcome: attempt.outcome,
      resolution: attempt.resolution,
      values: attempt.values,
      proofs: attempt.proofs,
      remark: attempt.remark,
    );
    bp.attempts.add(stored);
    // Apply post-decision system behaviour. Swap is system/TIU-detected
    // (Rule 1) — organic if it happens before any ticket action, assisted if
    // after — and either way it never requires approval: the ticket auto-
    // closes and drops off the work list immediately. FIR / Recovered
    // require coordinator/AC approval before closure (Rule 3), which happens
    // on the Web App, out of this mobile app's scope — this app only ever
    // moves those tickets to `pending`. Customer Not Cooperating is the one
    // FA-selectable outcome that closes directly, handing the case to the
    // central team (Rule 6). Not Found / Refused (which also covers "Lost"
    // non-FIR cases — Rule 2) is non-terminal; the case stays open.
    if (stored.resolution.startsWith('Swap')) {
      bp.zoneStatus = ZoneStatus.deployed;
      ticket.status = TicketStatus.closed;
      ticket.closedAt = attempt.createdAt;
    } else if (stored.resolution == 'Recovered') {
      bp.zoneStatus = ZoneStatus.nonField;
      ticket.status = TicketStatus.pending; // awaiting AC recovery validation
    } else if (stored.resolution == 'FIR') {
      bp.zoneStatus = ZoneStatus.fir;
      ticket.status = TicketStatus.pending; // awaiting coordinator closure
    } else if (stored.resolution == 'Customer Not Cooperating') {
      ticket.status = TicketStatus.closed;
      ticket.closedAt = attempt.createdAt;
      ticket.reason = 'Customer Not Cooperating — handed to central team';
    } else {
      // Not Found / Refused — non-terminal, case remains open for further attempts.
      ticket.status = TicketStatus.inProgress;
    }
    _drafts.remove(bpId);
    return _delayed(stored);
  }

  @override
  Future<void> submitAttemptRecord(AttemptSubmission submission) =>
      // Mock backend: accept and drop; nothing is persisted server-side.
      _delayed(null);

  @override
  Future<void> updateTicketStatus(String ticketId, String status) async {
    // The wire vocabulary is camelCase ("inProgress") while [TicketStatus]
    // parses snake_case, so fold the case before mapping onto the local model.
    final normalized = status.replaceAllMapped(
        RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}',);
    for (final t in _tickets) {
      if (t.ticketId == ticketId || t.caseId == ticketId) {
        t.status = TicketStatus.fromString(normalized);
      }
    }
    return _delayed(null);
  }

  @override
  Future<bool> validateScan(
      String ticketId, String bpId, String scannedSerial,) async {
    final normalized = scannedSerial.trim().toUpperCase();
    return _delayed(normalized == bpId.toUpperCase());
  }

  @override
  Future<double> roadDistanceKm(GeoPoint from, GeoPoint to) async {
    final km = from.haversineMeters(to) / 1000 * 1.35;
    return _delayed(double.parse(km.toStringAsFixed(1)));
  }

  @override
  Future<void> updateCustomer(String bpId, Customer customer) async {
    for (final t in _tickets) {
      for (var i = 0; i < t.batteries.length; i++) {
        if (t.batteries[i].bpId == bpId) {
          t.batteries[i].customer = customer;
        }
      }
    }
    return _delayed(null);
  }

  @override
  Future<void> updateCustomerByPhone(CustomerDetailsUpdate update) =>
      // Mock backend: accept and drop. The caller has already mirrored the
      // edits onto the in-memory battery, which is all the mock data needs.
      _delayed(null);

  @override
  Future<void> updateAgentLocation(String agentId, GeoPoint position) =>
      // Mock backend: accept and drop; nothing tracks agent positions here.
      _delayed(null);

  @override
  Future<void> requestHandoverOtp(String bpId) => _delayed(null);

  @override
  Future<bool> verifyHandoverOtp(String bpId, String otp) =>
      _delayed(RegExp(r'^\d{6}$').hasMatch(otp));

  @override
  Future<DraftAttempt?> getDraft(String bpId) => _delayed(_drafts[bpId]);

  @override
  Future<void> saveDraft(String bpId, DraftAttempt draft) {
    _drafts[bpId] = draft;
    return _delayed(null);
  }

  @override
  Future<GeoPoint> liveLocation(String bpId) async {
    // No real BP Live API in mock mode — jitter the last known location a
    // little so "live" visibly differs from the cached value in the demo.
    for (final t in _tickets) {
      for (final bp in t.batteries) {
        if (bp.bpId == bpId) {
          final jittered = GeoPoint(
            lat: bp.lastKnownLocation.lat + (_rng.nextDouble() - 0.5) * 0.0006,
            lng: bp.lastKnownLocation.lng + (_rng.nextDouble() - 0.5) * 0.0006,
            capturedAt: DateTime.now(),
          );
          return _delayed(jittered);
        }
      }
    }
    throw StateError('Unknown bpId: $bpId');
  }

  @override
  Future<CallRecording> startCall(String bpId, String phoneNumber) async {
    final recording = CallRecording(
      id: '${bpId}_call${(_callRecordings[bpId]?.length ?? 0) + 1}',
      bpId: bpId,
      startedAt: DateTime.now(),
      durationSeconds: 30 + _rng.nextInt(90),
      recordingUrl: 'mock://ozonetel/recordings/$bpId/${DateTime.now().millisecondsSinceEpoch}.mp3',
    );
    _callRecordings.putIfAbsent(bpId, () => []).insert(0, recording);
    return _delayed(recording);
  }

  @override
  Future<List<CallRecording>> callRecordings(String bpId) =>
      _delayed(List.unmodifiable(_callRecordings[bpId] ?? const []));

  @override
  Future<List<Ticket>> nearbyUnassignedTickets(GeoPoint near, double radiusKm) async {
    final inRange = _unassigned
        .where((t) => near.haversineMeters(t.primaryBp.lastKnownLocation) / 1000 <= radiusKm)
        .toList()
      ..sort((a, b) => near
          .haversineMeters(a.primaryBp.lastKnownLocation)
          .compareTo(near.haversineMeters(b.primaryBp.lastKnownLocation)),);
    return _delayed(inRange);
  }

  @override
  Future<Ticket> pickupTicket(String ticketId, String agentId) async {
    final ticket = _unassigned.firstWhere((t) => t.ticketId == ticketId,
        orElse: () => throw StateError('Ticket $ticketId is not available for pickup'),);
    _unassigned.remove(ticket);
    ticket.assignedAgentId = agentId;
    ticket.status = TicketStatus.assigned;
    _tickets.add(ticket);
    return _delayed(ticket);
  }
}
