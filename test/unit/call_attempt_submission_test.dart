import 'package:asset_recovery_app/core/di/injector.dart';
import 'package:asset_recovery_app/core/error/failure.dart';
import 'package:asset_recovery_app/core/error/result.dart';
import 'package:asset_recovery_app/domain/entities/attempt_submission.dart';
import 'package:asset_recovery_app/domain/entities/battery.dart';
import 'package:asset_recovery_app/domain/entities/form_field_config.dart';
import 'package:asset_recovery_app/domain/entities/geo_point.dart';
import 'package:asset_recovery_app/domain/usecases/call_usecase.dart';
import 'package:asset_recovery_app/domain/usecases/draft_attempt_usecase.dart';
import 'package:asset_recovery_app/domain/usecases/get_live_location_usecase.dart';
import 'package:asset_recovery_app/domain/usecases/submit_attempt_record_usecase.dart';
import 'package:asset_recovery_app/domain/usecases/update_customer_details_usecase.dart';
import 'package:asset_recovery_app/domain/usecases/update_customer_usecase.dart';
import 'package:asset_recovery_app/presentation/state/attempt_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_harness.dart';

// Identity translator: returns the key so assertions can match on keys.
String _t(String key, [Map<String, Object?> params = const {}]) => key;

/// Captures what the Call Customer save actually PUTs on the wire, standing in
/// for `POST v1/attempts`.
class _CapturingSubmit extends SubmitAttemptRecordUseCase {
  _CapturingSubmit(super.repo, {this.fail = false});

  final bool fail;
  final List<AttemptSubmission> submissions = [];

  @override
  Future<Result<void>> call(AttemptSubmission params) async {
    submissions.add(params);
    return fail ? const Err(UnknownFailure('boom')) : const Ok(null);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestEnv env;
  late Battery bp;
  late _CapturingSubmit submit;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    env = await TestEnv.create();
    final tickets = await env.repository.assignedTickets('FA-RM-01');
    bp = tickets
        .firstWhere((t) => t.ticketId == 'TKT-48217')
        .batteries
        .firstWhere((b) => b.bpId == 'BP-IF-09823-A');
    submit = _CapturingSubmit(env.repository);
  });

  AttemptController controller({SubmitAttemptRecordUseCase? submitRecord}) =>
      AttemptController(
        flow: env.services.attemptFlow,
        ticketId: 'TKT-48217',
        battery: bp,
        agentId: 'FA-RM-01',
        agentName: 'Ravi Kumar',
        config: env.config,
        location: env.location,
        proof: env.services.proof,
        getDraft: sl<GetDraftUseCase>(),
        saveDraft: sl<SaveDraftUseCase>(),
        updateCustomer: sl<UpdateCustomerUseCase>(),
        updateCustomerDetails: sl<UpdateCustomerDetailsUseCase>(),
        auditLog: env.services.auditLog,
        getLiveLocation: sl<GetLiveLocationUseCase>(),
        startCallUseCase: sl<StartCallUseCase>(),
        getCallRecordings: sl<GetCallRecordingsUseCase>(),
        syncQueue: env.services.syncQueue,
        submitAttemptRecord: submitRecord ?? submit,
      );

  StepConfig callSection(AttemptController c) =>
      c.flow.steps.firstWhere((s) => s.id == 'call');

  /// Fills the Call Customer form the way an agent would.
  void fillCall(
    AttemptController c, {
    String status = 'connected',
    String remark = 'Customer will return the pack tomorrow evening',
    String? mobile = '9998887776',
  }) {
    c
      ..markSectionOpened('call')
      ..setValue('callStatus', status)
      ..setValue('callingRemark', remark);
    if (mobile != null) c.setValue('newCustomerMobile', mobile);
  }

  test('the call section records its own attempt, like the visit sections', () {
    expect(controller().recordsOwnAttempt('call'), isTrue);
  });

  test('Save POSTs the attempt with the call dropdown as the outcome',
      () async {
    final c = controller();
    fillCall(c);

    expect(await c.saveSection(callSection(c), _t), isNull);
    expect(c.lastSectionSubmittedToService, isTrue);

    final sent = submit.submissions.single;
    expect(sent.attemptType, 'call');
    expect(sent.outcome, 'connected');
    // "What did the customer say?" is the attempt's notes.
    expect(sent.notes, 'Customer will return the pack tomorrow evening');
  });

  test('ticketId and batteryId are the same identifiers the visit sections send',
      () async {
    final c = controller();
    fillCall(c);
    await c.saveSection(callSection(c), _t);

    final sent = submit.submissions.single;
    expect(sent.ticketId, 'TKT-48217');
    expect(sent.batteryId, bp.bpId);
    expect(sent.agentId, 'FA-RM-01');
    expect(sent.agentName, 'Ravi Kumar');
  });

  test('the updated customer mobile rides along in metadata', () async {
    final c = controller();
    fillCall(c, mobile: '9998887776');
    await c.saveSection(callSection(c), _t);

    final meta = submit.submissions.single.metadata;
    expect(meta['newCustomerMobile'], '9998887776');
    expect(meta['callStatus'], 'connected');
    expect(meta['callingRemark'], isNotEmpty);
    expect(meta['customerName'], bp.customer.name);
  });

  test('attemptedAt is when the screen opened, completedAt when Save ran',
      () async {
    final c = controller();
    final before = DateTime.now();
    fillCall(c);
    await c.saveSection(callSection(c), _t);
    final after = DateTime.now();

    final sent = submit.submissions.single;
    expect(sent.attemptedAt.isBefore(sent.completedAt) ||
        sent.attemptedAt.isAtSameMomentAs(sent.completedAt), isTrue,);
    expect(sent.attemptedAt.isBefore(before.subtract(const Duration(seconds: 1))),
        isFalse,);
    expect(sent.completedAt.isAfter(after), isFalse);
  });

  test('re-opening the call screen does not restamp attemptedAt', () async {
    final c = controller();
    fillCall(c);
    final firstOpen = DateTime.now();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    // Agent backs out and comes in again before saving.
    c.markSectionOpened('call');
    await c.saveSection(callSection(c), _t);

    expect(submit.submissions.single.attemptedAt.isAfter(firstOpen), isFalse);
  });

  test('the agent GPS fix is sent as top-level latitude/longitude', () async {
    final c = controller();
    // The call section captures no proof photo, so the coordinates come from a
    // fresh device fix taken at Save time.
    env.location.forcedLocation = const GeoPoint(lat: 12.9611, lng: 77.6387);
    fillCall(c);
    await c.saveSection(callSection(c), _t);

    final sent = submit.submissions.single;
    expect(sent.latitude, 12.9611);
    expect(sent.longitude, 77.6387);
    expect(sent.proofUrls, isEmpty);
  });

  test('a rejected POST still saves the draft and says so', () async {
    final failing = _CapturingSubmit(env.repository, fail: true);
    final c = controller(submitRecord: failing);
    fillCall(c);

    // Not an error the agent has to fix — the local draft is kept either way.
    expect(await c.saveSection(callSection(c), _t), isNull);
    expect(failing.submissions, hasLength(1));
    expect(c.lastSectionSubmittedToService, isFalse);
  });

  test('a missing call status is refused before anything is POSTed', () async {
    final c = controller()..markSectionOpened('call');

    expect(await c.saveSection(callSection(c), _t), 'validation.required');
    expect(submit.submissions, isEmpty);
  });
}
