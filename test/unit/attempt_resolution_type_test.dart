import 'package:asset_recovery_app/domain/entities/attempt_submission.dart';
import 'package:flutter_test/flutter_test.dart';

AttemptSubmission _submission(String outcome) => AttemptSubmission(
      id: 'a-1',
      ticketId: 'TKT-2026-00024',
      batteryId: 'INSMOMAH0001',
      agentId: 'SUNMU00002340',
      agentName: 'Ravi',
      attemptType: 'field_visit',
      outcome: outcome,
      resolutionType: AttemptSubmission.resolutionFor(outcome),
      attemptedAt: DateTime.utc(2026, 11, 5, 10),
      completedAt: DateTime.utc(2026, 11, 5, 10, 5),
      latitude: 12.97,
      longitude: 77.59,
      customerPresent: false,
      notes: 'ok',
    );

void main() {
  group('AttemptSubmission.resolutionType', () {
    test('Recovered and FIR send resolutionType alongside outcome', () {
      for (final o in ['recovered', 'fir']) {
        final json = _submission(o).toJson();
        expect(json['outcome'], o);
        expect(json['resolutionType'], o);
      }
    });

    test('other outcomes do not send it', () {
      for (final o in [
        'not_found_refused',
        'customer_not_cooperating',
        'customer_will_take_swap',
      ]) {
        expect(_submission(o).toJson().containsKey('resolutionType'), isFalse);
      }
    });

    test('survives the offline-queue round trip', () {
      final back = AttemptSubmission.fromJson(_submission('fir').toJson());
      expect(back.resolutionType, 'fir');
      final rec = AttemptSubmission.fromJson(_submission('recovered').toJson());
      expect(rec.resolutionType, 'recovered');
      final nf =
          AttemptSubmission.fromJson(_submission('not_found_refused').toJson());
      expect(nf.resolutionType, isNull);
    });
  });
}
