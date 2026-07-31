import 'package:asset_recovery_app/data/repositories/mock_ticket_repository.dart';
import 'package:asset_recovery_app/domain/entities/attempt.dart';
import 'package:asset_recovery_app/domain/entities/enums.dart';
import 'package:asset_recovery_app/domain/entities/geo_point.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late MockTicketRepository repo;

  setUp(() {
    repo = MockTicketRepository(seed: 42, latency: Duration.zero);
  });

  test('login returns the seeded agent (Rohan M.)', () async {
    await repo.requestLoginOtp('9876543210');
    final agent = await repo.verifyLoginOtp('9876543210', '123456');
    expect(agent.id, 'FA-RM-01');
    expect(agent.name, 'Rohan M.');
    expect(agent.cluster, 'Bengaluru South');
    expect(agent.zone, 'Zone 4');
    expect(agent.shiftArea, 'Bengaluru South · Zone 4');
  });

  test('login OTP length honours the configured otpLength', () async {
    // Dev config uses gupshup.otpCodeLength = 4, so the mock must accept a
    // 4-digit code and reject the old hardcoded 6-digit assumption.
    final devRepo = MockTicketRepository(
      seed: 42,
      latency: Duration.zero,
      otpLength: 4,
    );
    final agent = await devRepo.verifyLoginOtp('9876543210', '1234');
    expect(agent.id, 'FA-RM-01');
    expect(
      () => devRepo.verifyLoginOtp('9876543210', '123456'),
      throwsA(isA<FormatException>()),
    );
  });

  test('assignedTickets returns seeded tickets for the agent', () async {
    final page = await repo.assignedTickets('FA-RM-01');
    final tickets = page.items;
    expect(tickets, isNotEmpty);
    expect(tickets.every((t) => t.assignedAgentId == 'FA-RM-01'), isTrue);
    expect(tickets.map((t) => t.ticketId), contains('TKT-48217'));
    expect(tickets.first.primaryBp.bpId, startsWith('BP-IF-'));
  });

  test('assignedTickets windows the seeded list and reports the total',
      () async {
    final all = (await repo.assignedTickets('FA-RM-01', pageSize: 100)).items;

    final first = await repo.assignedTickets('FA-RM-01', pageSize: 2);
    expect(first.items, hasLength(2));
    expect(first.items.map((t) => t.ticketId),
        all.take(2).map((t) => t.ticketId),);
    expect(first.total, all.length);

    final second = await repo.assignedTickets('FA-RM-01', page: 2, pageSize: 2);
    expect(second.items.map((t) => t.ticketId),
        all.skip(2).take(2).map((t) => t.ticketId),);

    // A window entirely past the end is empty, and stops the paging.
    final past = await repo.assignedTickets('FA-RM-01', page: 99, pageSize: 2);
    expect(past.items, isEmpty);
    expect(past.hasMore, isFalse);
  });

  test('shiftStats returns the home header counters', () async {
    final stats = await repo.shiftStats('FA-RM-01');
    expect(stats['assigned'], 27);
    expect(stats['inProgress'], 16);
    expect(stats['pending'], 11);
  });

  test('validateScan matches the assigned BP and rejects others', () async {
    expect(await repo.validateScan('TKT-48217', 'BP-IF-09823-A', 'BP-IF-09823-A'),
        isTrue,);
    expect(await repo.validateScan('TKT-48217', 'BP-IF-09823-A', 'bp-if-09823-a'),
        isTrue,); // case-insensitive
    expect(await repo.validateScan('TKT-48217', 'BP-IF-09823-A', 'BP-IF-99999-Z'),
        isFalse,);
  });

  test('submitting a Swap outcome closes the ticket and deploys the BP', () async {
    const loc = GeoPoint(lat: 12.9145, lng: 77.6010);
    final attempt = Attempt(
      id: 'pending',
      bpId: 'BP-IF-09823-A',
      sequence: 1,
      createdAt: DateTime(2026, 5, 12),
      gps: loc,
      outcome: 'swap_assisted',
      resolution: 'Swap (Assisted)',
      values: const {'outcome': 'swap_assisted'},
      proofs: const [],
    );
    await repo.submitAttempt('TKT-48217', 'BP-IF-09823-A', attempt);
    final ticket = await repo.ticketDetail('TKT-48217');
    expect(ticket.status, TicketStatus.closed);
    expect(ticket.primaryBp.zoneStatus, ZoneStatus.deployed);
  });

  test('FIR outcome moves the ticket to pending (coordinator closure)', () async {
    const loc = GeoPoint(lat: 12.9145, lng: 77.6010);
    final attempt = Attempt(
      id: 'pending',
      bpId: 'BP-IF-09823-A',
      sequence: 1,
      createdAt: DateTime(2026, 5, 12),
      gps: loc,
      outcome: 'fir',
      resolution: 'FIR',
      values: const {'outcome': 'fir'},
      proofs: const [],
    );
    await repo.submitAttempt('TKT-48217', 'BP-IF-09823-A', attempt);
    final ticket = await repo.ticketDetail('TKT-48217');
    expect(ticket.status, TicketStatus.pending);
    expect(ticket.primaryBp.zoneStatus, ZoneStatus.fir);
  });

  test('Customer Not Cooperating closes the ticket directly (Rule 6)', () async {
    const loc = GeoPoint(lat: 12.9145, lng: 77.6010);
    final attempt = Attempt(
      id: 'pending',
      bpId: 'BP-IF-09823-A',
      sequence: 1,
      createdAt: DateTime(2026, 5, 12),
      gps: loc,
      outcome: 'customer_not_cooperating',
      resolution: 'Customer Not Cooperating',
      values: const {'outcome': 'customer_not_cooperating'},
      proofs: const [],
    );
    await repo.submitAttempt('TKT-48217', 'BP-IF-09823-A', attempt);
    final ticket = await repo.ticketDetail('TKT-48217');
    expect(ticket.status, TicketStatus.closed);
  });

  test('road distance exceeds aerial distance (road factor applied)', () async {
    const a = GeoPoint(lat: 12.9716, lng: 77.5946);
    const b = GeoPoint(lat: 12.9352, lng: 77.6245);
    final road = await repo.roadDistanceKm(a, b);
    expect(road, greaterThan(a.haversineMeters(b) / 1000));
  });

  test('OTP verification accepts any 6-digit code in demo mode', () async {
    expect(await repo.verifyHandoverOtp('BP-IF-09823-A', '123456'), isTrue);
    expect(await repo.verifyHandoverOtp('BP-IF-09823-A', '12'), isFalse);
  });
}
