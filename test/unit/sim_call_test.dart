import 'dart:async';

import 'package:asset_recovery_app/core/di/injector.dart';
import 'package:asset_recovery_app/core/services/sim_call_service.dart';
import 'package:asset_recovery_app/domain/entities/battery.dart';
import 'package:asset_recovery_app/domain/entities/ticket_detail.dart';
import 'package:asset_recovery_app/domain/usecases/call_usecase.dart';
import 'package:asset_recovery_app/domain/usecases/draft_attempt_usecase.dart';
import 'package:asset_recovery_app/domain/usecases/get_live_location_usecase.dart';
import 'package:asset_recovery_app/domain/usecases/update_customer_details_usecase.dart';
import 'package:asset_recovery_app/domain/usecases/update_customer_usecase.dart';
import 'package:asset_recovery_app/presentation/state/attempt_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_harness.dart';

/// Scriptable stand-in for the Android platform channel, so the Call Customer
/// flow can be driven through every branch the real telephony stack produces.
class _FakeSimCallService implements SimCallService {
  bool supported = true;
  bool canCall = true;
  bool canReadState = true;

  /// Whether the OS grant dialog is answered with "allow".
  bool grantOnRequest = false;

  final _events = StreamController<SimCallEvent>.broadcast();
  final List<String> dialed = [];
  SimCallEvent? platformLastCall;
  bool trackingStopped = false;
  int requestCount = 0;

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<SimCallPermissions> permissions() async =>
      SimCallPermissions(canCall: canCall, canReadState: canReadState);

  @override
  Future<SimCallPermissions> requestPermissions() async {
    requestCount++;
    if (grantOnRequest) {
      canCall = true;
      canReadState = true;
    }
    return permissions();
  }

  @override
  Stream<SimCallEvent> get events => _events.stream;

  @override
  Future<SimCallStart> placeCall(String number) async {
    if (!supported) {
      throw const SimCallException('unsupported', 'call.notSupported');
    }
    if (!canCall) {
      throw const SimCallException('permission_denied', 'call.permissionDenied');
    }
    dialed.add(number);
    return SimCallStart(callId: 'c${dialed.length}', stateTracked: canReadState);
  }

  @override
  Future<SimCallEvent?> lastCallResult() async => platformLastCall;

  @override
  Future<void> stopTracking() async => trackingStopped = true;

  /// Pushes a platform state transition and lets the controller's listener run.
  Future<void> push(
    SimCallState state, {
    String callId = 'c1',
    int durationSeconds = 0,
  }) async {
    _events.add(SimCallEvent(
      callId: callId,
      state: state,
      durationSeconds: durationSeconds,
    ),);
    await Future<void>.delayed(Duration.zero);
  }

  void dispose() => _events.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestEnv env;
  late Battery bp;
  late _FakeSimCallService sim;

  setUp(() async {
    // The DI container initialises the offline sync queue, which reads
    // SharedPreferences — unavailable to the plain test binding.
    SharedPreferences.setMockInitialValues({});
    env = await TestEnv.create();
    final tickets =
        await env.repository.assignedTickets('FA-RM-01', pageSize: 100);
    bp = tickets.items
        .firstWhere((t) => t.ticketId == 'TKT-48217')
        .batteries
        .firstWhere((b) => b.bpId == 'BP-IF-09823-A');
    sim = _FakeSimCallService();
  });

  tearDown(() => sim.dispose());

  /// A ticket detail carrying the customer's numbers exactly as
  /// `GET /tickets/{UUID}` returns them — the source the Call Customer screen
  /// dials from.
  TicketDetail detailWith({String primary = '', String secondary = ''}) =>
      TicketDetail(
        id: 'uuid-48217',
        ticketNumber: 'TKT-48217',
        status: 'ASSIGNED',
        customer: TicketDetailCustomer(
          id: 'cust-1',
          phonePrimary: primary,
          phoneSecondary: secondary,
        ),
      );

  AttemptController controller({TicketDetail? detail}) => AttemptController(
        flow: env.services.attemptFlow,
        ticketId: 'TKT-48217',
        battery: bp,
        agentId: 'FA-RM-01',
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
        simCall: sim,
        ticketDetail: detail,
      );

  test('sanitize keeps only what a tel: number can carry', () {
    expect(SimCallService.sanitize('+91 98765-43210'), '+919876543210');
    expect(SimCallService.sanitize('(080) 4567 8900'), '08045678900');
    expect(SimCallService.sanitize('*99#'), '*99#');
  });

  test('Start Call dials on the SIM and reports the call live', () async {
    final c = controller();
    expect(await c.startSimCall(), isNull);

    expect(sim.dialed.single, SimCallService.sanitize(c.simCallTargetNumber));
    expect(c.callInProgress, isTrue);
    expect(c.simCallTracked, isTrue);
    expect(c.simCallState, SimCallState.dialing);

    await sim.push(SimCallState.active);
    expect(c.simCallState, SimCallState.active);
  });

  test("the customer's own numbers are what the screen offers", () async {
    bp.customer = bp.customer.copyWith(mobile: '9000000001');
    final c = controller(
      detail: detailWith(primary: '+91 98765-43210', secondary: '9811100244'),
    );

    // Ticket detail wins over the cached list-summary mobile, and both numbers
    // come back as the plain 10 digits the dropdown shows and dials.
    expect(c.callableNumbers, ['9876543210', '9811100244']);
    expect(c.simCallTargetNumber, '9876543210');
    expect(await c.startSimCall(), isNull);
    expect(sim.dialed.single, '9876543210');
  });

  test('numbers that are not valid 10-digit mobiles are not offered', () {
    bp.customer = bp.customer.copyWith(mobile: '9000000001');

    // A partial alternate is dropped, leaving only the primary.
    expect(
      controller(detail: detailWith(primary: '9811100244', secondary: '98111'))
          .callableNumbers,
      ['9811100244'],
    );
    // The same number twice (one of them formatted) is offered once.
    expect(
      controller(
        detail: detailWith(primary: '9811100244', secondary: '098111 00244'),
      ).callableNumbers,
      ['9811100244'],
    );
    // Neither number usable — fall back to the cached list-summary mobile.
    expect(
      controller(detail: detailWith(primary: '12345', secondary: ''))
          .callableNumbers,
      ['9000000001'],
    );
    // No ticket detail yet — same fallback.
    expect(controller().callableNumbers, ['9000000001']);
  });

  test('the agent can pick which number the call goes to', () async {
    final c = controller(
      detail: detailWith(primary: '9811100244', secondary: '9811100097'),
    );

    c.selectCallNumber('9811100097');
    expect(c.simCallTargetNumber, '9811100097');
    expect(await c.startSimCall(), isNull);
    expect(sim.dialed.single, '9811100097');

    // A number the customer doesn't have can't be selected.
    c.selectCallNumber('9999999999');
    expect(c.simCallTargetNumber, '9811100097');
  });

  test('hanging up logs the recording with the platform-measured duration',
      () async {
    final c = controller();
    await c.startSimCall();
    await sim.push(SimCallState.active);
    await sim.push(SimCallState.ended, durationSeconds: 132);

    expect(c.callInProgress, isFalse);
    expect(c.simCallState, SimCallState.ended);
    expect(c.recordings.single.durationSeconds, 132);
    expect(c.recordings.single.bpId, bp.bpId);
  });

  test('a repeated end event never logs the same call twice', () async {
    final c = controller();
    await c.startSimCall();
    await sim.push(SimCallState.ended, durationSeconds: 40);
    // Same call reported again — e.g. the event lands and reconcileSimCall
    // replays `lastCallResult` for the same callId.
    await sim.push(SimCallState.ended, durationSeconds: 40);

    expect(c.recordings, hasLength(1));
  });

  test('a call that never connected logs nothing', () async {
    final c = controller();
    await c.startSimCall();
    await sim.push(SimCallState.ended);

    expect(c.callInProgress, isFalse);
    expect(c.recordings, isEmpty);
  });

  test('an end missed while backgrounded is picked up on resume', () async {
    final c = controller();
    await c.startSimCall();
    // The OS in-call screen was up; the event never reached the listener.
    sim.platformLastCall = const SimCallEvent(
      callId: 'c1',
      state: SimCallState.ended,
      durationSeconds: 77,
      connected: true,
    );

    await c.reconcileSimCall();

    expect(c.callInProgress, isFalse);
    expect(c.recordings.single.durationSeconds, 77);
  });

  test('resuming with no finished call leaves the in-progress call alone',
      () async {
    final c = controller();
    await c.startSimCall();
    await c.reconcileSimCall();

    expect(c.callInProgress, isTrue);
    expect(c.recordings, isEmpty);
  });

  test('refusing the phone-call permission reports it and dials nothing',
      () async {
    sim
      ..canCall = false
      ..grantOnRequest = false;
    final c = controller();

    expect(await c.startSimCall(), 'call.permissionDenied');
    expect(sim.requestCount, 1);
    expect(sim.dialed, isEmpty);
    expect(c.callInProgress, isFalse);
  });

  test('granting the permission on the prompt lets the call through', () async {
    sim
      ..canCall = false
      ..canReadState = false
      ..grantOnRequest = true;
    final c = controller();

    expect(await c.startSimCall(), isNull);
    expect(sim.dialed, hasLength(1));
  });

  test('without READ_PHONE_STATE the call is placed but untracked', () async {
    sim.canReadState = false;
    final c = controller();

    expect(await c.startSimCall(), isNull);
    expect(sim.dialed, hasLength(1));
    expect(c.simCallTracked, isFalse);
    // Nothing will report the hang-up, so the UI times it and saves explicitly.
    expect(c.recordings, isEmpty);

    await c.saveCallRecording(25);
    await c.endSimCall();
    expect(c.recordings.single.durationSeconds, 25);
    expect(c.callInProgress, isFalse);
    expect(sim.trackingStopped, isTrue);
  });

  test('a customer with no number is reported before anything is dialed',
      () async {
    bp.customer = bp.customer.copyWith(mobile: '');
    final c = controller(detail: detailWith());

    expect(c.callableNumbers, isEmpty);
    expect(c.simCallTargetNumber, isEmpty);
    expect(await c.startSimCall(), 'call.noNumber');
    expect(sim.dialed, isEmpty);
  });

  test('support is resolved for the Call Customer screen', () async {
    final c = controller();
    expect(c.simCallSupported, isFalse);
    await c.loadSimCallSupport();
    expect(c.simCallSupported, isTrue);

    sim.supported = false;
    final other = controller();
    await other.loadSimCallSupport();
    expect(other.simCallSupported, isFalse);
  });
}
