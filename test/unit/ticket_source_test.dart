import 'package:asset_recovery_app/domain/entities/ticket_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TicketSource', () {
    test('matches the API value ignoring case and punctuation', () {
      expect(TicketSource.atRisk.matches('at_risk'), isTrue);
      expect(TicketSource.atRisk.matches('AT_RISK'), isTrue);
      expect(TicketSource.atRisk.matches('At-risk'), isTrue);
      expect(TicketSource.erpSync.matches('erp_sync'), isTrue);
      expect(TicketSource.bulkImport.matches('Bulk import'), isTrue);
      expect(TicketSource.freshservice.matches('FRESHSERVICE'), isTrue);
      expect(TicketSource.amd.matches('amd'), isTrue);
      expect(TicketSource.manual.matches('Manual'), isTrue);
    });

    test('theft also matches the dashboard value', () {
      expect(TicketSource.theft.matches('theft'), isTrue);
      expect(TicketSource.theft.matches('theft_dashboard'), isTrue);
    });

    test('different sources do not match each other', () {
      expect(TicketSource.amd.matches('at_risk'), isFalse);
      expect(TicketSource.manual.matches(''), isFalse);
    });

    test('fromRaw finds the source; prettify tidies unknown values', () {
      expect(TicketSource.fromRaw('at_risk'), TicketSource.atRisk);
      expect(TicketSource.fromRaw('nope'), isNull);
      expect(TicketSource.prettify('some_new-source'), 'Some new source');
      expect(TicketSource.prettify(''), '');
    });

    test('an empty selection matches every ticket; otherwise any pick', () {
      expect(TicketSource.anyMatches({}, 'whatever'), isTrue);
      final picks = {TicketSource.amd, TicketSource.atRisk};
      expect(TicketSource.anyMatches(picks, 'at_risk'), isTrue);
      expect(TicketSource.anyMatches(picks, 'manual'), isFalse);
    });
  });
}
