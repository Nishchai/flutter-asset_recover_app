import 'package:asset_recovery_app/core/utils/validators.dart';
import 'package:flutter/foundation.dart';

/// Tracks the agent's shift (Figma "SHIFT ACTIVE" banner + toggle) and the
/// end-of-shift OTP flow (Daily logout flow). Starting a shift is immediate;
/// ending it requires an OTP sent to the registered mobile.
class ShiftProvider extends ChangeNotifier {
  bool _active = true;
  bool get active => _active;

  /// Starts the shift immediately (no OTP required to begin).
  void startShift() {
    if (_active) return;
    _active = true;
    notifyListeners();
  }

  /// Demo: the backend would send an SMS OTP here.
  Future<void> requestEndOtp() async {
    // no-op in mock mode; wired to shift.endOtpRequest in production.
  }

  /// Verifies the end-shift OTP and, on success, ends the shift.
  /// Demo accepts any 6-digit code.
  Future<bool> verifyEndOtp(String otp) async {
    if (!Validators.isValidOtp(otp)) return false;
    _active = false;
    notifyListeners();
    return true;
  }
}
