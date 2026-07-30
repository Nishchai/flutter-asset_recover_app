import 'package:asset_recovery_app/core/error/result.dart';
import 'package:asset_recovery_app/core/services/session_store.dart';
import 'package:asset_recovery_app/core/utils/validators.dart';
import 'package:asset_recovery_app/domain/usecases/shift_otp_usecase.dart';
import 'package:flutter/foundation.dart';

/// Outcome of an end-shift OTP send request.
enum EndOtpSendResult {
  /// The gateway accepted it and an SMS is on its way.
  sent,

  /// Blocked: a send is already in flight, or the last one was less than
  /// [ShiftProvider.otpResendCooldown] ago. Nothing was sent and no SMS was
  /// spent — the code from that earlier send is still the valid one.
  throttled,

  /// The send failed; [ShiftProvider.otpError] says why.
  failed,
}

/// Tracks the agent's shift (Figma "SHIFT ACTIVE" banner + toggle) and the
/// end-of-shift OTP flow (Daily logout flow). Starting a shift is immediate;
/// ending it requires an OTP sent to the agent's registered mobile.
///
/// The number is NOT asked for again: it is [registeredMobile] — the
/// `usermobileNumber` of the `commonLogin` record persisted with the session —
/// so the code always goes to the number the agent signed in with.
class ShiftProvider extends ChangeNotifier {
  ShiftProvider({
    required RequestShiftEndOtpUseCase requestOtp,
    required VerifyShiftEndOtpUseCase verifyOtp,
    required SessionStore session,
  })  : _requestOtp = requestOtp,
        _verifyOtp = verifyOtp,
        _session = session;

  /// Digits in the end-shift OTP. Drives all three of: the length requested from
  /// the SMS gateway, the sheet's input field, and the local pre-check in
  /// [verifyEndOtp] — they must never disagree, so they all read this.
  ///
  /// Deliberately independent of `gupshup.otpCodeLength` (the login screen's
  /// length), which the environment config sets to 4.
  static const int otpLength = 6;

  /// Minimum gap between two end-shift OTP sends. Repeated taps inside this
  /// window are blocked rather than spending another SMS — reopening the sheet
  /// or hammering "Resend" costs nothing, and the code already sent stays the
  /// valid one.
  static const Duration otpResendCooldown = Duration(seconds: 30);

  final RequestShiftEndOtpUseCase _requestOtp;
  final VerifyShiftEndOtpUseCase _verifyOtp;
  final SessionStore _session;

  bool _active = true;
  bool _sendingOtp = false;
  String? _otpError;
  DateTime? _lastOtpSentAt;

  bool get active => _active;

  /// True while the OTP send is in flight.
  bool get sendingOtp => _sendingOtp;

  /// Whole seconds left before another send is allowed; 0 when one is allowed
  /// right now. Drives the "please wait" message on the end-shift sheet.
  int get otpCooldownRemaining {
    final last = _lastOtpSentAt;
    if (last == null) return 0;
    final leftMs = otpResendCooldown.inMilliseconds -
        DateTime.now().difference(last).inMilliseconds;
    return leftMs <= 0 ? 0 : (leftMs / 1000).ceil();
  }

  /// Message from the last failed send/verify — a gateway or session problem,
  /// NOT a wrong code (that is a plain `false` from [verifyEndOtp]). Null when
  /// the last attempt was clean.
  String? get otpError => _otpError;

  /// Where the end-shift OTP is sent: the `usermobileNumber` of the persisted
  /// `commonLogin` data block, falling back to the session agent's phone (mock
  /// sessions carry no profile).
  String get registeredMobile {
    final session = _session.current;
    final fromProfile = session?.profile?.usermobileNumber.trim() ?? '';
    if (fromProfile.isNotEmpty) return fromProfile;
    return session?.agent.phone.trim() ?? '';
  }

  /// Starts the shift immediately (no OTP required to begin).
  void startShift() {
    if (_active) return;
    _active = true;
    _otpError = null;
    notifyListeners();
  }

  /// Drops shift state back to what a fresh sign-in sees. This provider is
  /// created once and outlives the session, so without it the ended shift (and
  /// any stale error) would carry over to the next agent who signs in — they
  /// would land on "SHIFT INACTIVE" having never ended one. Wired to
  /// `AuthProvider`'s logout listeners in `AssetRecoveryApp`.
  void reset() {
    _active = true;
    _sendingOtp = false;
    _otpError = null;
    // The cooldown belongs to the session that was signed in; whoever signs in
    // next starts with a clean slate.
    _lastOtpSentAt = null;
    notifyListeners();
  }

  /// Sends the end-shift OTP to [registeredMobile].
  ///
  /// Debounced by [otpResendCooldown]: a request made while one is in flight, or
  /// within the cooldown of the last successful send, returns
  /// [EndOtpSendResult.throttled] without touching the gateway. Only a
  /// successful send starts the clock, so a failure can be retried at once.
  Future<EndOtpSendResult> requestEndOtp() async {
    if (_sendingOtp || otpCooldownRemaining > 0) {
      return EndOtpSendResult.throttled;
    }
    _sendingOtp = true;
    _otpError = null;
    notifyListeners();

    final result = await _requestOtp(
      RequestShiftEndOtpParams(registeredMobile, codeLength: otpLength),
    );
    _sendingOtp = false;
    return result.fold(
      (_) {
        _lastOtpSentAt = DateTime.now();
        notifyListeners();
        return EndOtpSendResult.sent;
      },
      (failure) {
        _otpError = failure.message;
        notifyListeners();
        return EndOtpSendResult.failed;
      },
    );
  }

  /// Verifies [otp] against the code sent to [registeredMobile] and, only on a
  /// match, ends the shift. False covers all three negatives — wrong length,
  /// wrong/expired code, and gateway failure (the last one also sets
  /// [otpError]).
  Future<bool> verifyEndOtp(String otp) async {
    if (!Validators.isValidOtp(otp, length: otpLength)) {
      _otpError = null;
      return false;
    }
    final result = await _verifyOtp(VerifyShiftEndOtpParams(registeredMobile, otp));
    return result.fold(
      (matched) {
        _otpError = null;
        if (!matched) {
          notifyListeners();
          return false;
        }
        _active = false;
        notifyListeners();
        return true;
      },
      (failure) {
        _otpError = failure.message;
        notifyListeners();
        return false;
      },
    );
  }
}
