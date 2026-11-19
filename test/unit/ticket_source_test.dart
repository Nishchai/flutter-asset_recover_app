import 'package:asset_recovery_app/domain/entities/ticket_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TicketSource', () {
    test('offers only Theft, At-risk and Manual', () {
      expect(TicketSource.values, [
        TicketSource.theft,
        TicketSource.atRisk,
        TicketSource.manual,
      ]);
    });

    test('matches the API value ignoring case and punctuation', () {
      expect(TicketSource.atRisk.matches('at_risk'), isTrue);
      expect(TicketSource.atRisk.matches('AT_RISK'), isTrue);
      expect(TicketSource.atRisk.matches('At-risk'), isTrue);
      expect(TicketSource.manual.matches('Manual'), isTrue);
      expect(TicketSource.theft.matches('THEFT'), isTrue);
    });

    test('theft also matches the dashboard value', () {
      expect(TicketSource.theft.matches('theft'), isTrue);
      expect(TicketSource.theft.matches('theft_dashboard'), isTrue);
    });

    test('different sources do not match each other', () {
      expect(TicketSource.theft.matches('at_risk'), isFalse);
      expect(TicketSource.manual.matches(''), isFalse);
    });

    test('fromRaw finds the source; prettify tidies unknown values', () {
      expect(TicketSource.fromRaw('at_risk'), TicketSource.atRisk);
      expect(TicketSource.fromRaw('erp_sync'), isNull);
      expect(TicketSource.prettify('erp_sync'), 'Erp sync');
      expect(TicketSource.prettify(''), '');
    });

    test('an empty selection matches every ticket; otherwise any pick', () {
      expect(TicketSource.anyMatches({}, 'whatever'), isTrue);
      final picks = {TicketSource.theft, TicketSource.atRisk};
      expect(TicketSource.anyMatches(picks, 'at_risk'), isTrue);
      expect(TicketSource.anyMatches(picks, 'manual'), isFalse);
    });
  });
}
