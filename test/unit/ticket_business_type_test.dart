import 'package:asset_recovery_app/domain/entities/ticket.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _json(String? businessType) => {
      'ticketId': 'TKT-1',
      'status': 'assigned',
      'createdAt': '2026-01-01T00:00:00Z',
      if (businessType != null) 'businessType': businessType,
      'batteries': <Map<String, dynamic>>[],
    };

void main() {
  group('Ticket.slaDueWithin', () {
    final now = DateTime.utc(2026, 6, 1, 12);
    Ticket withDeadline(DateTime? d) => Ticket.fromJson(_json('Fleet'))
      ..slaDeadline = d;

    test('compares the deadline with now, in days', () {
      final t = withDeadline(now.add(const Duration(days: 6, hours: 23)));
      expect(t.slaDueWithin(7, now), isTrue);
      final u = withDeadline(now.add(const Duration(days: 7)));
      expect(u.slaDueWithin(7, now), isFalse);
      expect(u.slaDueWithin(14, now, fromDays: 7), isTrue);
      final v = withDeadline(now.add(const Duration(days: 19)));
      expect(v.slaDueWithin(14, now, fromDays: 7), isFalse);
      expect(v.slaDueWithin(20, now, fromDays: 14), isTrue);
    });

    test('buckets are exclusive: each ticket lands in at most one', () {
      bool b7(Ticket t) => t.slaDueWithin(7, now);
      bool b14(Ticket t) => t.slaDueWithin(14, now, fromDays: 7);
      bool b20(Ticket t) => t.slaDueWithin(20, now, fromDays: 14);
      bool b20plus(Ticket t) => t.slaDueAtLeast(20, now);
      for (final days in [-3, 0, 5, 7, 10, 14, 17, 20, 25]) {
        final t = withDeadline(now.add(Duration(days: days)));
        final hits =
            [b7(t), b14(t), b20(t), b20plus(t)].where((x) => x).length;
        expect(hits, 1, reason: '$days days left');
      }
      expect(b20plus(withDeadline(null)), isFalse);
    });

    test('overdue counts as due; no deadline never matches', () {
      final overdue = withDeadline(now.subtract(const Duration(days: 3)));
      expect(overdue.slaDueWithin(7, now), isTrue);
      expect(withDeadline(null).slaDueWithin(20, now), isFalse);
    });
  });

  group('Ticket.businessType', () {
    test('Fleet and Retail are recognised, ignoring case and spaces', () {
      expect(Ticket.fromJson(_json('Fleet')).isFleet, isTrue);
      expect(Ticket.fromJson(_json(' retail ')).isRetail, isTrue);
      expect(Ticket.fromJson(_json('FLEET')).isRetail, isFalse);
    });

    test('a missing or unknown type is neither', () {
      final none = Ticket.fromJson(_json(null));
      expect(none.businessType, '');
      expect(none.isFleet || none.isRetail, isFalse);
      expect(Ticket.fromJson(_json('Other')).isFleet, isFalse);
    });

    test('survives a toJson round trip', () {
      final t = Ticket.fromJson(_json('Retail'));
      expect(Ticket.fromJson(t.toJson()).businessType, 'Retail');
    });
  });
}
