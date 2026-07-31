import 'package:asset_recovery_app/core/di/app_services.dart';
import 'package:asset_recovery_app/core/localization/app_localizations.dart';
import 'package:asset_recovery_app/core/services/location_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Explains a blocked location read and sends the agent to the one OS screen
/// that can unblock it.
///
/// [readiness] is what an earlier [LocationService.ensureReady] already
/// returned; this never re-checks and never re-requests, so the system prompt
/// the agent has just answered can't be followed by a second one.
///
/// Deliberately silent for [LocationReadiness.ready] and
/// [LocationReadiness.denied]: a fresh refusal is the agent's own answer to a
/// prompt they just saw, and the OS will ask again on the next attempt, so
/// arguing with it here would only be noise. The two states that do need a
/// dialog are the ones no amount of asking can recover from —
/// [LocationReadiness.deniedForever], undone only from this app's permission
/// page, and [LocationReadiness.servicesOff], undone only from the device's
/// location settings. [LocationReadiness.unavailable] gets no dialog either:
/// there is no screen to send the agent to.
Future<void> promptForLocationAccess(
  BuildContext context,
  LocationReadiness readiness, {
  LocationService? service,
}) async {
  final bodyKey = switch (readiness) {
    LocationReadiness.deniedForever => 'location.permissionBlocked',
    LocationReadiness.servicesOff => 'location.servicesOff',
    _ => null,
  };
  if (bodyKey == null) return;

  final l = AppLocalizations.of(context);
  // Resolved before the await so nothing reads from a context that may have
  // been unmounted while the dialog was up.
  final location = service ?? context.read<AppServices>().location;

  final openSettings = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l.t('location.accessNeeded')),
      content: Text(l.t(bodyKey)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l.t('location.notNow')),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l.t('location.openSettings')),
        ),
      ],
    ),
  );
  if (openSettings != true) return;

  if (readiness == LocationReadiness.servicesOff) {
    await location.openLocationSettings();
  } else {
    await location.openPermissionSettings();
  }
}
