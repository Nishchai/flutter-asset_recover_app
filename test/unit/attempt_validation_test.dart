import 'package:asset_recovery_app/core/di/injector.dart';
import 'package:asset_recovery_app/domain/entities/battery.dart';
import 'package:asset_recovery_app/domain/entities/enums.dart';
import 'package:asset_recovery_app/domain/entities/form_field_config.dart';
import 'package:asset_recovery_app/domain/entities/geo_point.dart';
import 'package:asset_recovery_app/domain/usecases/call_usecase.dart';
import 'package:asset_recovery_app/domain/usecases/draft_attempt_usecase.dart';
import 'package:asset_recovery_app/domain/usecases/get_live_location_usecase.dart';
import 'package:asset_recovery_app/domain/usecases/update_customer_details_usecase.dart';
import 'package:asset_recovery_app/presentation/state/attempt_controller.dart';
import 'package:asset_recovery_app/presentation/state/ticket_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_harness.dart';

// Identity translator: returns the key so assertions can match on keys.
String _t(String key, [Map<String, Object?> params = const {}]) => key;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestEnv env;
  late Battery bp;

  setUp(() async {
    env = await TestEnv.create();
    // Wide window: the fixture is looked up by id, so it must not depend on
    // which page the seeded list happens to put it on.
    final tickets =
        await env.repository.assignedTickets('FA-RM-01', pageSize: 100);
    bp = tickets.items
        .firstWhere((t) => t.ticketId == 'TKT-48217')
        .batteries
        .firstWhere((b) => b.bpId == 'BP-IF-09823-A');
  });

  AttemptController controller() => AttemptController(
        flow: env.services.attemptFlow,
        ticketId: 'TKT-48217',
        battery: bp,
        agentId: 'FA-RM-01',
        config: env.config,
        location: env.location,
        proof: env.services.proof,
        getDraft: sl<GetDraftUseCase>(),
        saveDraft: sl<SaveDraftUseCase>(),
        updateCustomerDetails: sl<UpdateCustomerDetailsUseCase>(),
        auditLog: env.services.auditLog,
        getLiveLocation: sl<GetLiveLocationUseCase>(),
        startCallUseCase: sl<StartCallUseCase>(),
        getCallRecordings: sl<GetCallRecordingsUseCase>(),
        syncQueue: env.services.syncQueue,
      );

  StepConfig section(AttemptController c, String id) =>
      c.flow.steps.firstWhere((s) => s.id == id);

  FormFieldConfig field(AttemptController c, String stepId, String fieldId) =>
      section(c, stepId).fields.firstWhere((f) => f.id == fieldId);

  test('call action requires the call status dropdown', () {
    final c = controller();
    expect(c.actionSections.first.id, 'call');
    expect(c.validateSection(section(c, 'call'), _t), 'validation.required');
  });

  test('call action has no photo-upload field — call recording replaces it '
      '(Rule 8a)', () {
    final c = controller();
    final ids = section(c, 'call').fields.map((f) => f.id);
    expect(ids, isNot(contains('callScreenshot')));
    c.setValue('callStatus', 'connected');
    expect(c.validateSection(section(c, 'call'), _t), isNull);
  });

  test('conditional amount fields appear only for the right outcomes', () {
    final c = controller();
    final amount = field(c, 'outcome', 'amountDemanded');

    c.setValue('outcome', 'not_found_refused');
    expect(c.isVisible(amount), isTrue);

    c.setValue('outcome', 'fir');
    expect(c.isVisible(amount), isFalse);

    c.setValue('outcome', 'customer_not_cooperating');
    expect(c.isVisible(amount), isFalse);

    c.setValue('outcome', 'recovered');
    expect(c.isVisible(amount), isTrue);
  });

  test('Swap is never an FA-selectable outcome (system/TIU-detected) and FIR '
      'is separate from Not Found/Refused (Rules 1, 2, 6)', () {
    final outcomeOptions = env.config.options('outcome').map((o) => o.value);
    expect(outcomeOptions,
        ['recovered', 'fir', 'not_found_refused', 'customer_not_cooperating'],);
  });

  test('battery remark is hidden for FIR (Rule 3) and for Customer Not '
      'Cooperating (Rule 6)', () {
    final c = controller();
    final batteryRemark = field(c, 'outcome', 'batteryRemarkReason');

    c.setValue('outcome', 'fir');
    expect(c.isVisible(batteryRemark), isFalse);

    c.setValue('outcome', 'customer_not_cooperating');
    expect(c.isVisible(batteryRemark), isFalse);

    c.setValue('outcome', 'recovered');
    expect(c.isVisible(batteryRemark), isTrue);
  });

  test('FIR reason is required only for outcome=fir (Rule 3), replacing the '
      'old generic pending reason', () {
    final c = controller();
    final firReason = field(c, 'outcome', 'firReason');

    c.setValue('outcome', 'not_found_refused');
    expect(c.isVisible(firReason), isFalse);

    c.setValue('outcome', 'fir');
    expect(c.isVisible(firReason), isTrue);
    expect(c.isRequired(firReason), isTrue);
  });

  test('helping factor and FIR reason do not appear for Not Found / Refused '
      '(Rule 4)', () {
    final c = controller();
    c.setValue('outcome', 'not_found_refused');
    expect(c.isVisible(field(c, 'outcome', 'helpingFactor')), isFalse);
    expect(c.isVisible(field(c, 'outcome', 'firReason')), isFalse);
  });

  test('customer remark is required for Not Found / Refused (Rule 5)', () {
    final c = controller();
    c.setValue('outcome', 'not_found_refused');
    expect(c.isVisible(field(c, 'outcome', 'customerRemarkReason')), isTrue);
    expect(c.isRequired(field(c, 'outcome', 'customerRemarkReason')), isTrue);
    expect(c.validateSection(section(c, 'outcome'), _t), 'validation.required');

    c.setValue('customerRemarkReason', 'denies_payment');
    expect(c.validateSection(section(c, 'outcome'), _t), isNull);
  });

  test('OTP field is required and validated only for physical recovery', () {
    final c = controller();
    final otp = field(c, 'outcome', 'handoverOtp');

    c.setValue('outcome', 'not_found_refused');
    expect(c.isVisible(otp), isFalse);

    c.setValue('outcome', 'recovered');
    expect(c.isVisible(otp), isTrue);
    expect(c.isRequired(otp), isTrue);
  });

  test('geo-fence enforcement rejects recovery proof captured too far away',
      () async {
    final c = controller();
    // Force the device far from the BP's last known location (Delhi vs BLR).
    env.location.forcedLocation = const GeoPoint(lat: 28.6139, lng: 77.2090);
    final proof = field(c, 'outcome', 'recoveryProof');
    final captured = await c.captureProof(proof);
    expect(c.isProofWithinGeofence(captured), isFalse);
  });

  test('geo-fence passes when the agent is at the BP location', () async {
    final c = controller();
    env.location.forcedLocation = bp.lastKnownLocation;
    final proof = field(c, 'outcome', 'recoveryProof');
    final captured = await c.captureProof(proof);
    expect(c.isProofWithinGeofence(captured), isTrue);
  });

  test('buildAttempt maps the outcome value to its resolution', () {
    final c = controller();
    c.setValue('outcome', 'fir');
    final attempt = c.buildAttempt();
    expect(attempt.outcome, 'fir');
    expect(attempt.resolution, 'FIR');
  });

  test(
      'a Field Agent can never directly close a ticket via FIR — approval-gated '
      'outcomes move it to pending, not closed (Rule 3)', () async {
    final c = controller();
    c.setValue('outcome', 'fir');
    c.setValue('firReason', 'battery_stolen_confirmed');
    await c.captureProof(field(c, 'outcome', 'firDocument'));
    final tickets = sl<TicketProvider>();
    await tickets.load('FA-RM-01');

    final error = await c.submitOutcome(tickets, _t);
    expect(error, isNull);

    final updated = await env.repository.ticketDetail('TKT-48217');
    expect(updated.status, TicketStatus.pending);
    expect(updated.status, isNot(TicketStatus.closed));
  });

  test('Not Found / Refused is non-terminal — the case stays open', () async {
    final c = controller();
    c.setValue('outcome', 'not_found_refused');
    c.setValue('customerRemarkReason', 'denies_payment');
    final tickets = sl<TicketProvider>();
    await tickets.load('FA-RM-01');

    final error = await c.submitOutcome(tickets, _t);
    expect(error, isNull);

    final updated = await env.repository.ticketDetail('TKT-48217');
    expect(updated.status, TicketStatus.inProgress);
  });

  test('Customer Not Cooperating closes the ticket directly, unlike every '
      'other FA-selectable outcome (Rule 6)', () async {
    final c = controller();
    c.setValue('outcome', 'customer_not_cooperating');
    c.setValue('customerRemarkReason', 'uncooperative');
    final tickets = sl<TicketProvider>();
    await tickets.load('FA-RM-01');

    final error = await c.submitOutcome(tickets, _t);
    expect(error, isNull);

    final updated = await env.repository.ticketDetail('TKT-48217');
    expect(updated.status, TicketStatus.closed);
  });
}
