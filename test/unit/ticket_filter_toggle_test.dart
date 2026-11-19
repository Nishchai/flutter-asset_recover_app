import 'package:asset_recovery_app/presentation/state/ticket_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TicketFilter.toggle', () {
    test('filters from different groups combine (Open + Fleet)', () {
      var s = <TicketFilter>{TicketFilter.open};
      s = TicketFilter.toggle(s, TicketFilter.fleet);
      expect(s, {TicketFilter.open, TicketFilter.fleet});
      s = TicketFilter.toggle(s, TicketFilter.sla7);
      expect(s, {TicketFilter.open, TicketFilter.fleet, TicketFilter.sla7});
    });

    test('a filter replaces the pick from its own group', () {
      var s = <TicketFilter>{TicketFilter.open, TicketFilter.fleet};
      s = TicketFilter.toggle(s, TicketFilter.retail);
      expect(s, {TicketFilter.open, TicketFilter.retail});
      s = TicketFilter.toggle(s, TicketFilter.inProgress);
      expect(s, {TicketFilter.inProgress, TicketFilter.retail});
    });

    test('tapping a selected filter clears it', () {
      final s = TicketFilter.toggle(
        {TicketFilter.open, TicketFilter.fleet},
        TicketFilter.fleet,
      );
      expect(s, {TicketFilter.open});
    });

    test('the input set is never modified', () {
      final before = <TicketFilter>{TicketFilter.open};
      TicketFilter.toggle(before, TicketFilter.fleet);
      expect(before, {TicketFilter.open});
    });

    test('every filter belongs to the expected group', () {
      expect(TicketFilter.completed.group, TicketFilterGroup.status);
      expect(TicketFilter.retail.group, TicketFilterGroup.customerType);
      expect(TicketFilter.sla20Plus.group, TicketFilterGroup.sla);
    });
  });
}
