import 'dart:async';

import 'package:asset_recovery_app/core/services/session_store.dart';
import 'package:flutter/widgets.dart';

/// Enforces auto-logout a fixed [sessionDuration] after the agent signed in
/// (PRD §4.9 — 12 hours).
///
/// The window is ABSOLUTE, not idle-based: an agent who signs in at 08:00 IST
/// is signed out at 20:00 IST, whether they used the app all day or never
/// opened it. Interaction does not extend it.
///
/// The anchor is [PersistedSession.loginAt], written to encrypted storage when
/// the OTP is verified — so the deadline survives backgrounding, a process kill
/// and a relaunch, none of which a [Timer] does. Every entry point re-derives
/// the remaining time from the IST clock rather than trusting a timer that may
/// not have fired:
///
/// * cold start — `configureDependencies` clears an expired session before any
///   UI exists, so the app opens on the login screen;
/// * back from the background — [didChangeAppLifecycleState];
/// * any touch on the home shell — [touch];
/// * the app left open past the deadline — the armed [Timer].
class SessionManager with WidgetsBindingObserver {
  SessionManager({
    required this.store,
    required this.sessionDuration,
    required this.onExpired,
    this.warnBefore = const Duration(minutes: 5),
    this.onWarn,
  });

  /// Owner of the persisted [PersistedSession.loginAt] anchor.
  final SessionStore store;

  final Duration sessionDuration;
  final Duration warnBefore;
  final VoidCallback onExpired;
  final VoidCallback? onWarn;

  Timer? _expiryTimer;
  Timer? _warnTimer;
  bool _expired = false;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  /// Re-checks the deadline. Wire to a top-level [Listener]/gesture. Unlike an
  /// idle timeout this does NOT extend the session — it only makes an already
  /// elapsed one surface on the agent's next interaction instead of waiting for
  /// a timer that a suspended process may never have run.
  void touch() => _check();

  /// Time left before auto-logout, floored at zero.
  Duration get remaining {
    final left = store.remainingSession(sessionDuration);
    return left.isNegative ? Duration.zero : left;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  /// Compares the IST clock against the login anchor and either signs the agent
  /// out or re-arms for exactly the time that is left.
  void _check() {
    _expiryTimer?.cancel();
    _warnTimer?.cancel();
    // Nobody signed in (or already signed out by this manager): nothing to
    // expire, and firing again would fight the login screen.
    if (_expired || !store.hasSession) return;

    final left = store.remainingSession(sessionDuration);
    if (left <= Duration.zero) {
      _expired = true;
      // Deferred: [_check] runs from initState and from lifecycle callbacks,
      // and expiring signs the agent out — which rebuilds the widget tree.
      scheduleMicrotask(onExpired);
      return;
    }

    if (onWarn != null && left > warnBefore) {
      _warnTimer = Timer(left - warnBefore, () => onWarn?.call());
    }
    // Re-enters [_check] rather than expiring blind, so the decision is always
    // made against the clock.
    _expiryTimer = Timer(left, _check);
  }

  void dispose() {
    _expiryTimer?.cancel();
    _warnTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }
}
