import 'dart:async';

import 'package:asset_recovery_app/core/localization/app_localizations.dart';
import 'package:asset_recovery_app/core/services/sim_call_service.dart';
import 'package:asset_recovery_app/core/theme/app_theme.dart';
import 'package:asset_recovery_app/core/utils/formatters.dart';
import 'package:asset_recovery_app/domain/entities/form_field_config.dart';
import 'package:asset_recovery_app/presentation/features/attempt/dynamic_field.dart';
import 'package:asset_recovery_app/presentation/features/map/map_screen.dart';
import 'package:asset_recovery_app/presentation/features/qr/qr_scan_screen.dart';
import 'package:asset_recovery_app/presentation/shared/mark_ticket_in_progress.dart';
import 'package:asset_recovery_app/presentation/shared/widgets/pill_button.dart';
import 'package:asset_recovery_app/presentation/state/attempt_controller.dart';
import 'package:asset_recovery_app/presentation/state/ticket_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Renders ONE action section (Call / Visit BP Location / Visit Customer
/// Address / Update Status) from `attempt_flow.json`. Replaces the old
/// forced-stepper `AttemptWizardScreen` — every section is opened
/// independently from the [TicketActionsHub] and saved on its own.
class AttemptSectionScreen extends StatefulWidget {
  const AttemptSectionScreen({
    super.key,
    required this.section,
    required this.isOutcome,
  });

  final StepConfig section;
  final bool isOutcome;

  @override
  State<AttemptSectionScreen> createState() => _AttemptSectionScreenState();
}

class _AttemptSectionScreenState extends State<AttemptSectionScreen>
    with WidgetsBindingObserver {
  /// Previous SIM-call state, so the transition into `ended` can be reported
  /// once (the platform pushes the whole lifecycle, not just the end).
  SimCallState? _lastSimCallState;
  int _recordingsAtCallStart = 0;

  @override
  void initState() {
    super.initState();
    final controller = context.read<AttemptController>();
    // Deferred to a post-frame callback: these call notifyListeners()
    // (some synchronously, before their first await) and calling that
    // during initState — which runs mid-build — trips Flutter's
    // "setState during build" assertion.
    // Stamp when the agent entered the Update Status screen — sent as
    // `attemptedAt` on the attempt submission.
    if (widget.isOutcome) controller.markUpdateStatusOpened();
    // Same for the visit sections: entry time is `attemptedAt`, Save time is
    // `completedAt` on the section's own attempt POST. Stamped here rather
    // than in the post-frame callback so it reflects when the screen actually
    // opened; neither marker notifies listeners, so this is safe in initState.
    if (controller.recordsOwnAttempt(widget.section.id)) {
      controller.markSectionOpened(widget.section.id);
    }
    if (widget.section.id == 'call') {
      // The OS in-call screen backgrounds this one; on the way back we ask the
      // platform whether the call finished while we weren't listening, and we
      // watch the controller so a finished call is reported to the agent.
      WidgetsBinding.instance.addObserver(this);
      controller.addListener(_onSimCallStateChanged);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.section.id == 'call') {
        controller.loadCallRecordings();
        controller.loadSimCallSupport();
      }
      if (widget.section.id == 'location_visit') controller.fetchLiveLocation();
    });
  }

  @override
  void dispose() {
    if (widget.section.id == 'call') {
      WidgetsBinding.instance.removeObserver(this);
      // read() is safe here: the provider outlives this screen (it lives on the
      // hub), and dispose() runs before it is torn down.
      context.read<AttemptController>().removeListener(_onSimCallStateChanged);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<AttemptController>().reconcileSimCall();
    }
  }

  /// Announces the end of a SIM call the platform tracked for us — the agent
  /// hung up on the OS call screen, so nothing else would tell them whether the
  /// call got logged.
  void _onSimCallStateChanged() {
    final controller = context.read<AttemptController>();
    final state = controller.simCallState;
    if (state == _lastSimCallState) return;
    final previous = _lastSimCallState;
    _lastSimCallState = state;
    if (state == SimCallState.dialing) {
      _recordingsAtCallStart = controller.recordings.length;
      return;
    }
    if (state != SimCallState.ended || previous == null) return;
    if (!mounted) return;
    final l = AppLocalizations.of(context);
    final logged = controller.recordings.length > _recordingsAtCallStart;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l.t(logged ? 'call.recordingSaved' : 'call.notConnected')),
      ),
    );
  }

  Future<void> _onSave(BuildContext context) async {
    final controller = context.read<AttemptController>();
    final l = AppLocalizations.of(context);

    if (widget.isOutcome) {
      // A recovery is only recorded against a battery the agent has physically
      // verified, so the scan runs here — between the form and the attempts API.
      // Every other outcome (FIR, Not Found / Refused, Customer Not
      // Cooperating) has no battery in hand to scan, so it submits straight
      // from the form.
      //
      // Validate first: an incomplete form would be rejected by submitOutcome
      // anyway, and there is no point sending the agent to the scanner only to
      // bounce them back. A mismatch never reaches the API — QrScanScreen shows
      // the QR-mismatch screen and returns without a confirmed match, which
      // leaves the agent on this screen with everything they entered intact.
      final invalid = controller.validateSection(widget.section, l.t);
      if (invalid != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(invalid)));
        return;
      }
      if (controller.requiresBatteryScan) {
        final verified = await Navigator.of(context).push<bool>(
          MaterialPageRoute<bool>(
            builder: (_) => QrScanScreen(
              battery: controller.battery,
              ticketId: controller.ticketId,
            ),
          ),
        );
        if (!context.mounted || verified != true) return;
      }

      if (controller.selectedOutcome == 'recovered') {
        final withinRange = await controller.isWithinBpLocationRange();
        if (!context.mounted) return;
        if (!withinRange) {
          await showDialog<void>(
            context: context,
            builder: (_) => AlertDialog(
              title: Text(l.t('attempt.outOfRangeTitle')),
              content: Text(l.t('attempt.outOfRangeMessage')),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l.t('common.close')),
                ),
              ],
            ),
          );
          return;
        }
      }

      final tickets = context.read<TicketProvider>();
      final error = await controller.submitOutcome(tickets, l.t);
      if (!context.mounted) return;
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
        return;
      }
      // The attempts service accepted the status — confirm it plainly. Any
      // ticket-side write that had to be queued behind it syncs on its own and
      // isn't the agent's problem, so no "you're offline" message here.
      final msg = controller.lastOutcomeSubmittedToService
          ? l.t('attempt.statusUpdated')
          : (controller.lastOutcomeWasQueued
              ? l.t('sync.queuedOffline')
              : (controller.requiresApproval
                  ? l.t('attempt.pendingApproval')
                  : (controller.resolution.isNotEmpty && !controller.requiresApproval
                      ? l.t('attempt.closed')
                      : l.t('attempt.success'))));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      Navigator.of(context)
        ..pop()
        ..pop(); // back out of the hub too — the outcome closes this attempt cycle.
      return;
    }

    // The agent must be physically at the battery's live telemetry location
    // to log this visit — same 100m geo-fence the "Recovered" outcome
    // enforces — but only when they're reporting the battery as found
    // (recovered, or not recovered because the customer denied pickup); the
    // other visit outcomes (not found, restricted entry, other) don't require
    // the agent to be on top of the battery's last-known spot.
    if (widget.section.id == 'location_visit' &&
        const {
          'battery_found_recovered',
          'battery_found_not_recovered_denied',
        }.contains(controller.value('visitStatus'))) {
      final withinRange = await controller.isWithinBpLocationRange();
      if (!context.mounted) return;
      if (!withinRange) {
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(l.t('attempt.outOfRangeTitle')),
            content: Text(l.t('attempt.outOfRangeMessage')),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l.t('common.close')),
              ),
            ],
          ),
        );
        return;
      }
    }

    final error = await controller.saveSection(widget.section, l.t);
    if (!context.mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    // Submitting an attempt from Call Customer, Visit BP Location or Visit
    // Customer Address means the agent is now working the case, so move the
    // ticket to `inProgress`. Only after a successful save — a validation
    // failure returned above and never reaches here.
    unawaited(markTicketInProgress(controller.ticketId));
    // The call and visit sections also POST their attempt to the attempts
    // service. The draft is saved either way, so say plainly which of the two
    // happened instead of a blanket "Saved" that hides a rejected submission.
    final isCall = widget.section.id == 'call';
    final message = controller.recordsOwnAttempt(widget.section.id)
        ? (controller.lastSectionSubmittedToService
            ? l.t(isCall ? 'attempt.callRecorded' : 'attempt.visitRecorded')
            : l.t(isCall ? 'attempt.callNotSynced' : 'attempt.visitNotSynced'))
        : l.t('attempt.draftSaved');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = context.read<AppPalette>();
    final controller = context.watch<AttemptController>();
    final fields = controller.visibleFields(widget.section);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Container(
              decoration: BoxDecoration(gradient: palette.heroGradient),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 8, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: IconButton(
                          icon: Icon(Icons.close, color: palette.onDark),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                      Text(l.t(widget.section.titleKey),
                          style: TextStyle(
                              color: palette.onDark,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,),),
                      const SizedBox(height: 2),
                      Text(controller.battery.bpId,
                          style: TextStyle(color: palette.primary, fontSize: 14),),
                    ],
                  ),
                ),
              ),
            ),
            if (widget.section.id == 'call') _CallRecordingPanel(palette: palette),
            if (widget.section.id == 'location_visit') _LiveLocationBar(palette: palette),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                children: [
                  for (final f in fields) ...[
                    DynamicField(field: f),
                    const SizedBox(height: 16),
                  ],
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: controller.submitting ? null : () => _onSave(context),
                    child: controller.submitting
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white,),
                          )
                        : Text(
                            widget.isOutcome
                                // The scan is part of submitting only when the
                                // outcome needs it, so the CTA says so only then.
                                ? l.t(controller.requiresBatteryScan
                                    ? 'wizard.scanAndSubmit'
                                    : 'wizard.submit',)
                                : l.t('section.save'),
                            textAlign: TextAlign.center,
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// In-app calling (Rule 8a) — on Android "Start Call" dials the customer on the
/// device's own SIM without leaving the app, and the platform reports the call's
/// duration so it is logged automatically when the agent hangs up. This UI
/// starts the call and lists whatever recordings exist for this BP so far,
/// replacing the old screenshot upload.
class _CallRecordingPanel extends StatelessWidget {
  const _CallRecordingPanel({required this.palette});
  final AppPalette palette;

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m}m ${s}s';
  }

  /// Dials on the SIM (Android) or, where that isn't available, falls back to
  /// timing the call in-app so the flow still works on emulators/iOS.
  Future<void> _startCall(BuildContext context, AttemptController controller) async {
    final l = AppLocalizations.of(context);
    if (!controller.simCallSupported) {
      await _timeCallInApp(context, controller);
      return;
    }
    final errorKey = await controller.startSimCall();
    if (!context.mounted) return;
    if (errorKey != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.t(errorKey))));
      return;
    }
    // The call is up. With READ_PHONE_STATE granted the platform times it and
    // the recording is logged on hang-up; without it, the agent has to.
    if (!controller.simCallTracked) await _timeCallInApp(context, controller);
  }

  /// Stopwatch fallback: the agent taps End Call when the conversation is over
  /// and those seconds become the [CallRecording].
  Future<void> _timeCallInApp(BuildContext context, AttemptController controller) async {
    final l = AppLocalizations.of(context);
    final seconds = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _OngoingCallDialog(
        palette: palette,
        mobile: controller.simCallTargetNumber,
        // Only worth explaining when a real call is running behind this dialog.
        hint: controller.callInProgress ? l.t('call.manualTimerHint') : null,
      ),
    );
    if (seconds != null && seconds > 0) {
      await controller.saveCallRecording(seconds);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.t('call.recordingSaved'))));
      }
    }
    await controller.endSimCall();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final controller = context.watch<AttemptController>();
    // The customer's own numbers, from the ticket detail — primary first, the
    // alternate second, and only the ones that are valid 10-digit mobiles.
    final numbers = controller.callableNumbers;
    // The number the call will really go to, so the button never claims to be
    // calling one it isn't.
    final mobile = controller.simCallTargetNumber;
    // While a tracked call is live the button would only start a second one.
    final busy = controller.callInProgress && controller.simCallTracked;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StartCallButton(
            palette: palette,
            numbers: numbers,
            selected: mobile,
            enabled: !busy && numbers.isNotEmpty,
            onCall: (number) {
              controller.selectCallNumber(number);
              _startCall(context, controller);
            },
          ),
          if (numbers.isEmpty) ...[
            const SizedBox(height: 6),
            Text(l.t('call.noNumber'),
                style: TextStyle(color: palette.danger, fontSize: 12),),
          ],
          if (busy) ...[
            const SizedBox(height: 10),
            _SimCallBanner(palette: palette),
          ],
          const SizedBox(height: 14),
          Text(l.t('call.historicalRecordings'),
              style: TextStyle(fontWeight: FontWeight.w600, color: palette.onSurface),),
          const SizedBox(height: 6),
          if (controller.recordings.isEmpty)
            Text(l.t('call.noRecordings'),
                style: TextStyle(color: palette.muted, fontSize: 13),)
          else
            for (final r in controller.recordings)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: palette.border),
                ),
                child: Row(
                  children: [
                    Icon(Icons.play_circle_outline, color: palette.primaryDark),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${r.startedAt.toLocal()}'.split('.').first,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    Text(_formatDuration(r.durationSeconds),
                        style: TextStyle(color: palette.muted, fontSize: 12),),
                  ],
                ),
              ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

/// The Start Call CTA. With a single number on record it is a plain pill that
/// dials it. When the customer has a second valid number the pill grows a
/// dropdown on its right: it lists both numbers (primary / alternate) and the
/// one the agent picks becomes the number this call — and every later one on
/// this screen — goes to.
class _StartCallButton extends StatelessWidget {
  const _StartCallButton({
    required this.palette,
    required this.numbers,
    required this.selected,
    required this.enabled,
    required this.onCall,
  });

  final AppPalette palette;

  /// The customer's callable numbers, primary first.
  final List<String> numbers;

  /// The one the button currently dials — empty when [numbers] is.
  final String selected;
  final bool enabled;

  /// Called with the number to dial: the selected one from the button itself,
  /// or whichever entry was picked from the dropdown.
  final void Function(String number) onCall;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    // Masked for display only — [onCall] and the dropdown's item values still
    // carry the real number, so the dialer gets the full one.
    final label = numbers.isEmpty
        ? l.t('call.startCall')
        : '${l.t('call.startCall')} · ${Formatters.maskedPhone(selected)}';

    if (numbers.length < 2) {
      return SizedBox(
        width: double.infinity,
        child: PillButton.yellow(
          label,
          palette: palette,
          icon: Icons.call,
          onPressed: enabled ? () => onCall(selected) : null,
        ),
      );
    }

    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: palette.primary,
        shape: const StadiumBorder(),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: enabled ? () => onCall(selected) : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 17, horizontal: 22),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.call, size: 18, color: palette.onPrimary),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.onPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              width: 1,
              height: 26,
              color: palette.onPrimary.withValues(alpha: 0.25),
            ),
            PopupMenuButton<String>(
              enabled: enabled,
              tooltip: l.t('call.chooseNumber'),
              position: PopupMenuPosition.under,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              icon: Icon(Icons.arrow_drop_down, color: palette.onPrimary),
              onSelected: onCall,
              itemBuilder: (_) => [
                for (var i = 0; i < numbers.length; i++)
                  PopupMenuItem<String>(
                    value: numbers[i],
                    child: Row(
                      children: [
                        Icon(
                          numbers[i] == selected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          size: 18,
                          color: palette.primaryDark,
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(Formatters.maskedPhone(numbers[i]),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 14,),),
                            Text(
                              l.t(i == 0
                                  ? 'call.primaryNumber'
                                  : 'call.altNumber',),
                              style: TextStyle(color: palette.muted, fontSize: 11),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Inline "call is up" strip shown while the platform tracks a live SIM call.
/// The conversation itself happens on the OS in-call screen; this is what the
/// agent comes back to, and it disappears on its own once the hang-up is
/// reported and the duration logged.
class _SimCallBanner extends StatefulWidget {
  const _SimCallBanner({required this.palette});
  final AppPalette palette;

  @override
  State<_SimCallBanner> createState() => _SimCallBannerState();
}

class _SimCallBannerState extends State<_SimCallBanner> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // The platform only pushes state transitions, so the elapsed readout ticks
    // locally off the moment the call was placed.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = widget.palette;
    final controller = context.watch<AttemptController>();
    final placedAt = controller.simCallPlacedAt;
    final elapsed = placedAt == null
        ? Duration.zero
        : DateTime.now().difference(placedAt);
    final label = controller.simCallState == SimCallState.active
        ? l.t('call.inProgress')
        : l.t('call.dialing');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: palette.primaryLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Icon(Icons.phone_in_talk, size: 18, color: palette.primaryDark),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                  fontWeight: FontWeight.w600, color: palette.onSurface, fontSize: 13,),
            ),
          ),
          Text(
            '${elapsed.inMinutes.toString().padLeft(2, '0')}:'
            '${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: palette.onSurface,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

/// Modal shown while an in-app call is "connected": displays the on-going
/// status with a live stopwatch and an End Call button. Popping returns the
/// elapsed seconds so the caller can persist it as a [CallRecording].
class _OngoingCallDialog extends StatefulWidget {
  const _OngoingCallDialog({
    required this.palette,
    required this.mobile,
    this.hint,
  });
  final AppPalette palette;
  final String mobile;

  /// Explains why the agent is looking at a stopwatch while the real call runs
  /// on the OS in-call screen. Null when this dialog *is* the whole call (no
  /// SIM support).
  final String? hint;

  @override
  State<_OngoingCallDialog> createState() => _OngoingCallDialogState();
}

class _OngoingCallDialogState extends State<_OngoingCallDialog> {
  Timer? _timer;
  int _seconds = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _seconds++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _elapsed {
    final m = (_seconds ~/ 60).toString().padLeft(2, '0');
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = widget.palette;
    return AlertDialog(
      backgroundColor: palette.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: palette.primaryLight,
            child: Icon(Icons.phone_in_talk, size: 30, color: palette.primaryDark),
          ),
          const SizedBox(height: 14),
          Text(
            l.t('call.inProgress'),
            style: TextStyle(fontWeight: FontWeight.w600, color: palette.onSurface),
          ),
          const SizedBox(height: 4),
          Text(widget.mobile, style: TextStyle(color: palette.muted, fontSize: 13)),
          const SizedBox(height: 12),
          Text(
            _elapsed,
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: palette.onSurface,
            ),
          ),
          if (widget.hint != null) ...[
            const SizedBox(height: 10),
            Text(
              widget.hint!,
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.muted, fontSize: 12),
            ),
          ],
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: palette.danger,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: const StadiumBorder(),
            ),
            icon: const Icon(Icons.call_end),
            label: Text(l.t('call.endCall')),
            onPressed: () => Navigator.of(context).pop(_seconds),
          ),
        ),
      ],
    );
  }
}

/// Fetches the BP's live location (Rule 8b) and offers in-app + external
/// navigation to it.
class _LiveLocationBar extends StatelessWidget {
  const _LiveLocationBar({required this.palette});
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final controller = context.watch<AttemptController>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 110,
                child: Text(l.t('detail.lastTiu'),
                    style: TextStyle(color: palette.muted, fontSize: 13),),
              ),
              Expanded(
                child: Text(controller.lastTiuDisplay,
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: PillButton.outline(
                  controller.fetchingLiveLocation
                      ? l.t('map.fetchingLiveLocation')
                      : l.t('common.openInMaps'),
                  palette: palette,
                  icon: Icons.map_outlined,
                  onPressed: controller.fetchingLiveLocation
                      ? null
                      : () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => MapScreen(
                                focusBp: controller.battery,
                                focusLocation: controller.navigationTarget,
                              ),
                            ),
                          ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: l.t('common.refresh'),
                onPressed: controller.fetchingLiveLocation ? null : controller.fetchLiveLocation,
                icon: controller.fetchingLiveLocation
                    ? const SizedBox(
                        height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2),)
                    : const Icon(Icons.my_location),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
