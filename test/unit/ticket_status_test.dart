import 'package:asset_recovery_app/domain/entities/enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TicketStatus.fromString', () {
    test('maps QC-approved recovery/FIR outcomes onto closed (Completed)', () {
      expect(TicketStatus.fromString('Recovered - QC done'), TicketStatus.closed);
      expect(TicketStatus.fromString('FIR - QC done'), TicketStatus.closed);
    });

    test('is case- and separator-insensitive for the QC-done statuses', () {
      expect(TicketStatus.fromString('recovered_qc_done'), TicketStatus.closed);
      expect(TicketStatus.fromString('FIRQCDONE'), TicketStatus.closed);
    });
  });
}
