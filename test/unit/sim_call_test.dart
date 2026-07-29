import 'dart:async';

import 'package:asset_recovery_app/core/di/injector.dart';
import 'package:asset_recovery_app/core/services/sim_call_service.dart';
import 'package:asset_recovery_app/domain/entities/battery.dart';
import 'package:asset_recovery_app/domain/usecases/call_usecase.dart';
import 'package:asset_recovery_app/domain/usecases/draft_attempt_usecase.dart';
import 'package:asset_recovery_app/domain/usecases/get_live_location_usecase.dart';
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
    final tickets = await env.repository.assignedTickets('FA-RM-01');
    bp = tickets
        .firstWhere((t) => t.ticketId == 'TKT-48217')
        .batteries
        .firstWhere((b) => b.bpId == 'BP-IF-09823-A');
    sim = _FakeSimCallService();
  });

  tearDown(() => sim.dispose());

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
        updateCustomer: sl<UpdateCustomerUseCase>(),
        auditLog: env.services.auditLog,
        getLiveLocation: sl<GetLiveLocationUseCase>(),
        startCallUseCase: sl<StartCallUseCase>(),
        getCallRecordings: sl<GetCallRecordingsUseCase>(),
        syncQueue: env.services.syncQueue,
        simCall: sim,
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

  test('while the test line is hardcoded it wins over the customer number',
      () async {
    // Delete this test together with AttemptController.simCallOverrideNumber.
    expect(AttemptController.simCallOverrideNumber, isNotEmpty);
    bp.customer = bp.customer.copyWith(mobile: '9000000001');
    final c = controller();

    expect(c.simCallTargetNumber, AttemptController.simCallOverrideNumber);
    expect(await c.startSimCall(), isNull);
    expect(
      sim.dialed.single,
      SimCallService.sanitize(AttemptController.simCallOverrideNumber),
    );
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
    final c = controller();

    if (AttemptController.simCallOverrideNumber.isEmpty) {
      expect(await c.startSimCall(), 'call.noNumber');
      expect(sim.dialed, isEmpty);
    } else {
      // The hardcoded test line stands in for the customer's number for now,
      // so there is nothing to refuse. This branch goes away with the override.
      expect(await c.startSimCall(), isNull);
      expect(sim.dialed, hasLength(1));
    }
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
