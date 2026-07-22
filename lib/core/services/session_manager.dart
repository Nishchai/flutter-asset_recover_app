import 'dart:async';

import 'package:flutter/widgets.dart';

/// Enforces auto-logout after a configurable idle/session window (PRD §4.9 —
/// default 12 hours). Any user interaction calls [touch] to reset the timer.
class SessionManager with WidgetsBindingObserver {
  SessionManager({
    required this.sessionDuration,
    required this.onExpired,
    this.warnBefore = const Duration(minutes: 5),
    this.onWarn,
  });

  final Duration sessionDuration;
  final Duration warnBefore;
  final VoidCallback onExpired;
  final VoidCallback? onWarn;

  Timer? _expiryTimer;
  Timer? _warnTimer;
  DateTime? _sessionStart;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _sessionStart = DateTime.now();
    _arm();
  }

  /// Resets the idle countdown. Wire to a top-level [Listener]/gesture.
  void touch() => _arm();

  void _arm() {
    _expiryTimer?.cancel();
    _warnTimer?.cancel();
    if (onWarn != null && sessionDuration > warnBefore) {
      _warnTimer = Timer(sessionDuration - warnBefore, () => onWarn?.call());
    }
    _expiryTimer = Timer(sessionDuration, onExpired);
  }

  /// Total elapsed since sign-in, regardless of activity.
  Duration get elapsed =>
      _sessionStart == null ? Duration.zero : DateTime.now().difference(_sessionStart!);

  void dispose() {
    _expiryTimer?.cancel();
    _warnTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }
}
