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
