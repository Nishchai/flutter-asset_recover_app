import 'dart:async';

import 'package:asset_recovery_app/core/di/app_services.dart';
import 'package:asset_recovery_app/core/localization/app_localizations.dart';
import 'package:asset_recovery_app/core/services/location_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Holds the app shut until the device can actually produce a GPS fix.
///
/// Every recovery action an agent records — arrival, route, photo — is only
/// worth anything with a position attached, so location is treated as a
/// precondition for the shift rather than a per-action inconvenience. This runs
/// on landing at home ([HomeShell]), after the runtime permission request that
/// [LocationService.ensureReady] performs, and returns only once readiness is
/// [LocationReadiness.ready].
///
/// No "not now": a dismissable prompt was what let an agent work a whole ticket
/// with location switched off and no coordinates on any of it. The dialog has
/// no dismiss path — no barrier tap, no system back — and closes on its own the
/// moment a re-check comes back ready.
Future<void> enforceLocationAccess(
  BuildContext context, {
  LocationService? service,
}) async {
  // Resolved before the first await so nothing reads from a context that may
  // have been unmounted while the OS prompt was up.
  final location = service ?? context.read<AppServices>().location;
  final readiness = await location.ensureReady();
  if (readiness == LocationReadiness.ready) return;
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _LocationGateDialog(
      location: location,
      readiness: readiness,
    ),
  );
}

/// The gate itself. Re-checks on every resume, because the two blocked states
/// worth a dialog are both undone on an OS screen the agent has to leave the
/// app to reach — coming back is the only signal that the answer may have
/// changed.
class _LocationGateDialog extends StatefulWidget {
  const _LocationGateDialog({
    required this.location,
    required this.readiness,
  });

  final LocationService location;

  /// Readiness as [enforceLocationAccess] resolved it; the starting state, kept
  /// current by [_LocationGateDialogState._recheck].
  final LocationReadiness readiness;

  @override
  State<_LocationGateDialog> createState() => _LocationGateDialogState();
}

class _LocationGateDialogState extends State<_LocationGateDialog>
    with WidgetsBindingObserver {
  late LocationReadiness _readiness = widget.readiness;

  /// Set while a re-check is in flight so a resume and a button press can't run
  /// two `ensureReady` calls — and two permission prompts — at once.
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The agent is back from the settings screen (or from anywhere else). Ask
  /// again — this is what closes the gate in the normal case, without needing
  /// them to find the button.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_recheck());
  }

  Future<void> _recheck() async {
    if (_checking) return;
    setState(() => _checking = true);
    // Re-requests the runtime permission when it is merely `denied`, so this
    // doubles as the retry path for an agent who dismissed the system prompt.
    final readiness = await widget.location.ensureReady();
    if (!mounted) return;
    if (readiness == LocationReadiness.ready) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _readiness = readiness;
      _checking = false;
    });
  }

  /// Sends the agent to the one OS screen that can unblock the current state.
  /// Deliberately does not re-check afterwards: the settings screen is now in
  /// front, the answer doesn't exist yet, and the resume callback has it.
  Future<void> _openSettings() async {
    if (_readiness == LocationReadiness.servicesOff) {
      await widget.location.openLocationSettings();
    } else {
      await widget.location.openPermissionSettings();
    }
  }

  /// Only two states have an OS screen to offer. A soft `denied` is fixed by
  /// the retry (which re-prompts), and `unavailable` — no GPS hardware, no
  /// plugin — has nowhere to send anyone.
  bool get _hasSettingsScreen =>
      _readiness == LocationReadiness.servicesOff ||
      _readiness == LocationReadiness.deniedForever;

  String get _bodyKey => switch (_readiness) {
        LocationReadiness.servicesOff => 'location.servicesOff',
        LocationReadiness.deniedForever => 'location.permissionBlocked',
        LocationReadiness.denied => 'location.permissionNeeded',
        _ => 'location.unavailable',
      };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(l.t('location.accessNeeded')),
        content: Text(l.t(_bodyKey)),
        actions: [
          if (_hasSettingsScreen)
            TextButton(
              onPressed: _checking ? null : () => unawaited(_openSettings()),
              child: Text(l.t('location.openSettings')),
            ),
          TextButton(
            onPressed: _checking ? null : () => unawaited(_recheck()),
            child: _checking
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l.t('location.retry')),
          ),
        ],
      ),
    );
  }
}
