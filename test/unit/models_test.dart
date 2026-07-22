import 'package:asset_recovery_app/domain/entities/battery.dart';
import 'package:asset_recovery_app/domain/entities/customer.dart';
import 'package:asset_recovery_app/domain/entities/enums.dart';
import 'package:asset_recovery_app/domain/entities/geo_point.dart';
import 'package:asset_recovery_app/domain/entities/ticket.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GeoPoint', () {
    test('haversine distance is ~0 for same point', () {
      const p = GeoPoint(lat: 12.97, lng: 77.59);
      expect(p.haversineMeters(p), closeTo(0, 0.001));
    });

    test('haversine distance between known points is sane', () {
      const a = GeoPoint(lat: 12.9716, lng: 77.5946);
      const b = GeoPoint(lat: 12.9352, lng: 77.6245);
      final m = a.haversineMeters(b);
      // ~5 km between these Bengaluru points.
      expect(m, greaterThan(4000));
      expect(m, lessThan(6500));
    });

    test('display formats to 6 decimals', () {
      const p = GeoPoint(lat: 12.5, lng: 77.25);
      expect(p.display, '12.500000, 77.250000');
    });
  });

  group('Ticket', () {
    Ticket sample({required DateTime created}) => Ticket(
          ticketId: 'TKT-1',
          status: TicketStatus.assigned,
          createdAt: created,
          assignedAgentId: 'FA-1',
          batteries: [
            Battery(
              bpId: 'BP-1',
              caseType: 'Theft',
              customer: const Customer(name: 'A', mobile: '9811100000', address: 'x'),
              lastKnownLocation: const GeoPoint(lat: 1, lng: 1),
              zoneStatus: ZoneStatus.field,
              bpState: BpState.idle,
            ),
          ],
        );

    test('slaDaysLeft counts down from creation', () {
      final now = DateTime(2026, 6, 22);
      final t = sample(created: DateTime(2026, 6, 1));
      // 90-day SLA, created 21 days ago -> 69 days left.
      expect(t.slaDaysLeft(90, now), 69);
    });

    test('JSON round-trips losslessly', () {
      final t = sample(created: DateTime(2026, 6, 1));
      final back = Ticket.fromJson(t.toJson());
      expect(back.ticketId, t.ticketId);
      expect(back.status, TicketStatus.assigned);
      expect(back.primaryBp.bpId, 'BP-1');
      expect(back.primaryBp.customer.mobile, '9811100000');
    });
  });

  group('Customer', () {
    test('masks mobile number', () {
      const c = Customer(name: 'A', mobile: '9811100012', address: 'x');
      expect(c.maskedMobile(), '98XXXXX012');
    });
  });
}
