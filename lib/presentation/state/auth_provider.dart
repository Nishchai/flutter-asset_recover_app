import 'dart:async';

import 'package:asset_recovery_app/core/error/result.dart';
import 'package:asset_recovery_app/core/services/audit_log_service.dart';
import 'package:asset_recovery_app/domain/entities/agent.dart';
import 'package:asset_recovery_app/domain/usecases/login_otp_usecase.dart';
import 'package:flutter/foundation.dart';

enum AuthStatus { loggedOut, sendingOtp, otpSent, verifyingOtp, loggedIn }

/// Holds authentication state and the signed-in [Agent]. Mobile-number + OTP
/// sign-in: [requestOtp] validates the mobile server-side and triggers the
/// SMS send, [verifyOtp] exchanges the code for the authenticated agent.
/// Depends on use cases (not the repository) — presentation talks to the
/// domain through use cases only.
class AuthProvider extends ChangeNotifier {
  AuthProvider(this._requestOtp, this._verifyOtp, this._auditLog);

  final RequestLoginOtpUseCase _requestOtp;
  final VerifyLoginOtpUseCase _verifyOtp;
  final AuditLogService _auditLog;

  AuthStatus _status = AuthStatus.loggedOut;
  Agent? _agent;
  String? _error;
  String? _mobile;

  AuthStatus get status => _status;
  Agent? get agent => _agent;
  String? get error => _error;

  /// The mobile number an OTP was last sent to, once [requestOtp] succeeds.
  String? get mobile => _mobile;
  bool get isLoggedIn => _status == AuthStatus.loggedIn;

  Future<bool> requestOtp(String mobile) async {
    _status = AuthStatus.sendingOtp;
    _error = null;
    notifyListeners();

    final result = await _requestOtp(mobile);
    return result.fold(
      (_) {
        _mobile = mobile;
        _status = AuthStatus.otpSent;
        notifyListeners();
        return true;
      },
      (failure) {
        _error = failure.message;
        _status = AuthStatus.loggedOut;
        notifyListeners();
        return false;
      },
    );
  }

  Future<bool> verifyOtp(String otp) async {
    final mobile = _mobile;
    if (mobile == null) return false;
    _status = AuthStatus.verifyingOtp;
    _error = null;
    notifyListeners();

    final result = await _verifyOtp(VerifyLoginOtpParams(mobile, otp));
    return result.fold(
      (agent) {
        _agent = agent;
        _status = AuthStatus.loggedIn;
        notifyListeners();
        unawaited(_auditLog.log(agentId: agent.id, action: 'login'));
        return true;
      },
      (failure) {
        _error = failure.message;
        _status = AuthStatus.otpSent;
        notifyListeners();
        return false;
      },
    );
  }

  /// Returns to the mobile-entry step (e.g. the "change number" link on the
  /// OTP screen).
  void resetToMobileEntry() {
    _status = AuthStatus.loggedOut;
    _mobile = null;
    _error = null;
    notifyListeners();
  }

  void logout() {
    final agentId = _agent?.id;
    _agent = null;
    _mobile = null;
    _status = AuthStatus.loggedOut;
    notifyListeners();
    if (agentId != null) {
      unawaited(_auditLog.log(agentId: agentId, action: 'logout'));
    }
  }
}
