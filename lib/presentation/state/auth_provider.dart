import 'dart:async';

import 'package:asset_recovery_app/core/error/result.dart';
import 'package:asset_recovery_app/core/services/audit_log_service.dart';
import 'package:asset_recovery_app/core/services/location_service.dart';
import 'package:asset_recovery_app/core/services/session_store.dart';
import 'package:asset_recovery_app/core/utils/ist_time.dart';
import 'package:asset_recovery_app/domain/entities/agent.dart';
import 'package:asset_recovery_app/domain/entities/audit_event.dart';
import 'package:asset_recovery_app/domain/entities/partner_login_data.dart';
import 'package:asset_recovery_app/domain/usecases/login_otp_usecase.dart';
import 'package:flutter/foundation.dart';

enum AuthStatus { loggedOut, sendingOtp, otpSent, verifyingOtp, loggedIn }

/// Holds authentication state and the signed-in [Agent]. Two-step
/// mobile-number + OTP sign-in:
///
/// 1. [requestOtp] — looks the number up in the SM-Partners directory
///    (`commonLogin`); only if it resolves to an agent is an OTP sent. The
///    returned record is held in [profile] until the OTP is verified.
/// 2. [verifyOtp] — verifies the code, mints the access token, and the agent
///    from step 1 becomes the signed-in identity.
///
/// Depends on use cases (not the repository) — presentation talks to the
/// domain through use cases only.
///
/// Session persistence: the login screens are shown only ONCE. On a successful
/// [verifyOtp] the access token, agent and partner profile go to the
/// [SessionStore] (encrypted); the DI container restores them at startup, so
/// this provider is constructed already [AuthStatus.loggedIn] and the root
/// router opens the home shell directly. [logout] wipes the stored session,
/// sending the next launch back to the login screen.
class AuthProvider extends ChangeNotifier {
  AuthProvider(
    this._requestOtp,
    this._verifyOtp,
    this._auditLog,
    this._sessionStore,
    this._location,
  )   : _agent = _sessionStore.current?.agent,
        _status = _sessionStore.current == null
            ? AuthStatus.loggedOut
            : AuthStatus.loggedIn,
        _mobile = _sessionStore.current?.agent.phone,
        _profile = _sessionStore.current?.profile;

  final RequestLoginOtpUseCase _requestOtp;
  final VerifyLoginOtpUseCase _verifyOtp;
  final AuditLogService _auditLog;
  final SessionStore _sessionStore;
  final LocationService _location;

  AuthStatus _status;
  Agent? _agent;
  String? _error;
  String? _mobile;
  PartnerLoginData? _profile;

  AuthStatus get status => _status;
  Agent? get agent => _agent;
  String? get error => _error;

  /// The full `commonLogin` record for the signed-in agent (userId, role,
  /// email, app version…) — restored from encrypted storage on relaunch. Set
  /// from [requestOtp] onwards; null in mock mode's pre-login state.
  PartnerLoginData? get profile => _profile;

  /// The mobile number an OTP was last sent to, once [requestOtp] succeeds.
  String? get mobile => _mobile;
  bool get isLoggedIn => _status == AuthStatus.loggedIn;

  /// Step 1: directory lookup, then OTP send. Returns false — with [error] set
  /// to the backend's own reason — when the number isn't a known active agent,
  /// in which case no OTP is sent.
  Future<bool> requestOtp(String mobile) async {
    _status = AuthStatus.sendingOtp;
    _error = null;
    notifyListeners();

    final result = await _requestOtp(mobile);
    return result.fold(
      (profile) {
        _mobile = mobile;
        _profile = profile;
        _status = AuthStatus.otpSent;
        notifyListeners();
        return true;
      },
      (failure) {
        _error = failure.message;
        _profile = null;
        _status = AuthStatus.loggedOut;
        notifyListeners();
        return false;
      },
    );
  }

  /// Step 2: verifies the code, mints the token and signs the agent in using the
  /// record [requestOtp] fetched.
  Future<bool> verifyOtp(String otp) async {
    final mobile = _mobile;
    if (mobile == null) return false;
    _status = AuthStatus.verifyingOtp;
    _error = null;
    notifyListeners();

    final result = await _verifyOtp(
      VerifyLoginOtpParams(mobile, otp, profile: _profile),
    );
    return result.fold(
      (login) {
        _agent = login.agent;
        _profile = login.profile ?? _profile;
        _status = AuthStatus.loggedIn;
        notifyListeners();
        // Persist so this is the last time the login screens are shown. Not
        // awaited: the UI must not wait on a keystore write, and a failure to
        // save only costs an extra OTP on the next launch.
        //
        // `loginAt` stamps the IST moment sign-in completed: it anchors the
        // fixed auto-logout window (PRD §4.9), so from here the agent has
        // exactly `session.autoLogoutHours` — sign in at 08:00 IST, signed out
        // at 20:00 IST regardless of what they do in between. See
        // `SessionManager`.
        unawaited(() async {
          try {
            // Minted fresh for this sign-in and carried unchanged through to
            // `logout` (see `PersistedSession.transactionId`), so every audit
            // entry in between — this one included — shares one id.
            await _sessionStore.save(PersistedSession(
              authToken: login.accessToken,
              agent: login.agent,
              profile: login.profile,
              loginAt: nowIst(),
              transactionId: AuditEvent.newTransactionId(),
            ),);
          } finally {
            // Emitted only AFTER the token mint succeeded and the session is in
            // place — `save` is what pushes the new credential to `ApiClient`,
            // so chaining the audit POST behind it means the first request of
            // the session can never go out ahead of the `Bearer` header it
            // needs (an audit entry sent unauthenticated would 401 and land on
            // the offline queue for nothing). The mint itself already gates
            // this: `VerifyLoginOtpUseCase` fails the whole login if it fails,
            // so reaching here at all means there IS a token. Queued for retry
            // by AuditLogService if the send still fails. [transactionId] is
            // left to default to the session's own, just saved above.
            final gps = await _location.currentLocation();
            await _auditLog.log(
              agentId: login.agent.id,
              action: 'login_success',
              entityType: 'agent',
              entityId: login.agent.id,
              metadata: gps.hasFix
                  ? {'latitude': gps.lat, 'longitude': gps.lng}
                  : const {},
            );
          }
        }(),);
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
    _profile = null;
    _error = null;
    notifyListeners();
  }

  /// Registers [callback] to run on every [logout], before the login screen is
  /// shown. Used by the agent-scoped presentation state (e.g. `TicketProvider`)
  /// to drop the signed-out agent's cached data and, with it, the agent id it
  /// would otherwise reuse on the next refresh — those providers live for the
  /// whole app lifetime, so nothing else resets them between two sign-ins.
  /// Wired once in `AssetRecoveryApp`.
  void addLogoutListener(VoidCallback callback) => _onLogout.add(callback);

  void removeLogoutListener(VoidCallback callback) => _onLogout.remove(callback);

  final List<VoidCallback> _onLogout = [];

  /// Signs out and erases the stored session — access token AND the
  /// request-scoping agent id, which [SessionStore.clear] pushes to the
  /// `ApiClient` as null. Nothing of the signed-out agent survives: the next
  /// sign-in scopes its calls to the id ITS `commonLogin` returned. Awaiting it
  /// is optional — the UI flips to the login screen as soon as the state
  /// changes.
  Future<void> logout() async {
    final agentId = _agent?.id;
    _agent = null;
    _mobile = null;
    _profile = null;
    _error = null;
    _status = AuthStatus.loggedOut;
    for (final callback in List<VoidCallback>.of(_onLogout)) {
      callback();
    }
    notifyListeners();
    // Emitted BEFORE the session is cleared, and deliberately so: the request
    // is built (token + agentId) synchronously inside the `log` call below, so
    // the logout event still carries the credential of the agent it belongs
    // to. [_sessionStore.clear] is awaited only after `log` has been invoked
    // (NOT after it completes — `unawaited` below), so the GPS fetch's own
    // delay sits entirely before the credential is torn down, never after.
    // Queued for retry by AuditLogService if it fails.
    if (agentId != null) {
      final gps = await _location.currentLocation();
      unawaited(_auditLog.log(
        agentId: agentId,
        action: 'logout',
        entityType: 'agent',
        entityId: agentId,
        metadata: gps.hasFix
            ? {'latitude': gps.lat, 'longitude': gps.lng}
            : const {},
      ),);
    }
    await _sessionStore.clear();
  }
}
