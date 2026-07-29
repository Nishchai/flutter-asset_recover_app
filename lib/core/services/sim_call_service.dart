import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Where a SIM call is in its lifecycle, as reported by the Android telephony
/// stack.
enum SimCallState {
  /// `ACTION_CALL` accepted — the line is dialing.
  dialing,

  /// The line went off-hook (ringing at the other end / connected).
  active,

  /// The agent hung up, or the call never got off the ground.
  ended,
}

/// One call-state transition pushed up from the platform.
@immutable
class SimCallEvent {
  const SimCallEvent({
    required this.callId,
    required this.state,
    this.durationSeconds = 0,
    this.number,
    this.connected = false,
  });

  /// Identifies the call this event belongs to, so a late [SimCallState.ended]
  /// is never recorded twice (see `AttemptController.reconcileSimCall`).
  final String callId;
  final SimCallState state;

  /// Seconds the line was off-hook. Only meaningful on [SimCallState.ended].
  ///
  /// Measured OFF_HOOK → IDLE by the platform, which for an outgoing call
  /// starts when it is placed — so this includes the ringing time before the
  /// customer picked up.
  final int durationSeconds;
  final String? number;

  /// False when the call ended without ever going off-hook (rejected by the
  /// SIM, cancelled, blocked by a call-screening app).
  final bool connected;

  factory SimCallEvent.fromMap(Map<Object?, Object?> map) => SimCallEvent(
        callId: '${map['callId'] ?? ''}',
        state: _parseState('${map['state']}'),
        durationSeconds: (map['durationSeconds'] as num?)?.toInt() ?? 0,
        number: map['number'] as String?,
        connected: map['connected'] as bool? ?? false,
      );

  static SimCallState _parseState(String raw) {
    switch (raw) {
      case 'active':
        return SimCallState.active;
      case 'ended':
        return SimCallState.ended;
      default:
        return SimCallState.dialing;
    }
  }
}

/// Result of asking the platform to dial.
@immutable
class SimCallStart {
  const SimCallStart({
    required this.callId,
    required this.stateTracked,
  });

  final String callId;

  /// True when the platform will report this call's state and duration. False
  /// when READ_PHONE_STATE was refused — the call is still placed, but the
  /// caller has to time it (see the in-app stopwatch fallback).
  final bool stateTracked;
}

/// Why a [SimCallService.placeCall] could not dial. Carries a localization key
/// so the UI can report it in the agent's language.
class SimCallException implements Exception {
  const SimCallException(this.code, this.messageKey);

  /// Platform error code (`permission_denied`, `unsupported`, `dial_failed`…).
  final String code;

  /// `assets/l10n/*.json` key describing the failure.
  final String messageKey;

  @override
  String toString() => 'SimCallException($code)';
}

/// Which of the two telephony permissions the agent has granted.
@immutable
class SimCallPermissions {
  const SimCallPermissions({required this.canCall, required this.canReadState});

  /// CALL_PHONE — without it nothing can be dialed from inside the app.
  final bool canCall;

  /// READ_PHONE_STATE — without it the call is untracked (no auto duration).
  final bool canReadState;

  factory SimCallPermissions.fromMap(Map<Object?, Object?> map) =>
      SimCallPermissions(
        canCall: map['call'] as bool? ?? false,
        canReadState: map['phoneState'] as bool? ?? false,
      );

  static const denied = SimCallPermissions(canCall: false, canReadState: false);
}

/// Places a call to the customer on the device's own SIM without leaving the
/// app (Rule 8a), and reports the call's real duration so the Call Customer
/// screen can log it as a [CallRecording].
///
/// Android-only by design: [AndroidSimCallService] bridges to `SimCallHandler`
/// via platform channels, and every other platform gets [NoopSimCallService],
/// which reports itself unsupported so the UI falls back to its in-app
/// stopwatch dialog.
abstract class SimCallService {
  /// True when this build can dial on a SIM at all.
  Future<bool> isSupported();

  Future<SimCallPermissions> permissions();

  /// Shows the OS grant dialog for whichever of the two is still missing.
  Future<SimCallPermissions> requestPermissions();

  /// State transitions for the call in flight. Broadcast — safe to listen to
  /// from more than one place.
  Stream<SimCallEvent> get events;

  /// Dials [number] on the device SIM. Throws [SimCallException] when the call
  /// could not be placed.
  Future<SimCallStart> placeCall(String number);

  /// The most recently finished call, or null if none. Lets the UI catch up on
  /// an `ended` event that arrived while it was in the background.
  Future<SimCallEvent?> lastCallResult();

  /// Stops platform tracking of the call in flight — used when the UI has
  /// finished with it (or timed it itself).
  Future<void> stopTracking();

  /// Strips formatting the dialer cannot take, keeping the digits and the
  /// `+ * #` that are meaningful in a `tel:` number.
  static String sanitize(String number) =>
      number.replaceAll(RegExp(r'[^0-9+*#]'), '');
}

/// Real implementation, talking to `SimCallHandler.kt`.
class AndroidSimCallService implements SimCallService {
  AndroidSimCallService({
    MethodChannel? method,
    EventChannel? events,
  })  : _method = method ?? const MethodChannel(_methodChannelName),
        _events = events ?? const EventChannel(_eventChannelName);

  static const _methodChannelName = 'com.sunmobility.asset_recovery_app/sim_call';
  static const _eventChannelName =
      'com.sunmobility.asset_recovery_app/sim_call/events';

  final MethodChannel _method;
  final EventChannel _events;
  Stream<SimCallEvent>? _stream;

  @override
  Future<bool> isSupported() async {
    try {
      return await _method.invokeMethod<bool>('isSupported') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<SimCallPermissions> permissions() => _permissionCall('permissions');

  @override
  Future<SimCallPermissions> requestPermissions() =>
      _permissionCall('requestPermissions');

  Future<SimCallPermissions> _permissionCall(String method) async {
    try {
      final map = await _method.invokeMethod<Map<Object?, Object?>>(method);
      return map == null
          ? SimCallPermissions.denied
          : SimCallPermissions.fromMap(map);
    } on PlatformException {
      return SimCallPermissions.denied;
    } on MissingPluginException {
      return SimCallPermissions.denied;
    }
  }

  @override
  Stream<SimCallEvent> get events => _stream ??= _events
      .receiveBroadcastStream()
      .map((e) => SimCallEvent.fromMap(e as Map<Object?, Object?>));

  @override
  Future<SimCallStart> placeCall(String number) async {
    try {
      final map = await _method.invokeMethod<Map<Object?, Object?>>(
        'placeCall',
        {'number': SimCallService.sanitize(number)},
      );
      return SimCallStart(
        callId: '${map?['callId'] ?? ''}',
        stateTracked: map?['stateTracked'] as bool? ?? false,
      );
    } on PlatformException catch (e) {
      throw SimCallException(e.code, _messageKeyFor(e.code));
    } on MissingPluginException {
      throw const SimCallException('unsupported', 'call.notSupported');
    }
  }

  static String _messageKeyFor(String code) {
    switch (code) {
      case 'permission_denied':
        return 'call.permissionDenied';
      case 'unsupported':
        return 'call.notSupported';
      case 'invalid_number':
        return 'call.noNumber';
      default:
        return 'call.dialFailed';
    }
  }

  @override
  Future<SimCallEvent?> lastCallResult() async {
    try {
      final map =
          await _method.invokeMethod<Map<Object?, Object?>>('lastCallResult');
      return map == null ? null : SimCallEvent.fromMap(map);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<void> stopTracking() async {
    try {
      await _method.invokeMethod<void>('stopTracking');
    } on PlatformException {
      // Nothing to stop — the platform already closed the call out.
    } on MissingPluginException {
      // Not running against the Android host.
    }
  }
}

/// Stand-in for iOS/desktop/tests: never dials, always reports unsupported.
class NoopSimCallService implements SimCallService {
  const NoopSimCallService();

  @override
  Future<bool> isSupported() async => false;

  @override
  Future<SimCallPermissions> permissions() async => SimCallPermissions.denied;

  @override
  Future<SimCallPermissions> requestPermissions() async =>
      SimCallPermissions.denied;

  @override
  Stream<SimCallEvent> get events => const Stream<SimCallEvent>.empty();

  @override
  Future<SimCallStart> placeCall(String number) async =>
      throw const SimCallException('unsupported', 'call.notSupported');

  @override
  Future<SimCallEvent?> lastCallResult() async => null;

  @override
  Future<void> stopTracking() async {}
}

/// Picks the implementation for the running platform. Called by the DI
/// container — in-app SIM calling is Android-only for now (Phase 1).
SimCallService createSimCallService() {
  if (kIsWeb) return const NoopSimCallService();
  return Platform.isAndroid ? AndroidSimCallService() : const NoopSimCallService();
}
