import 'dart:async';

import 'package:asset_recovery_app/core/localization/app_localizations.dart';
import 'package:asset_recovery_app/core/theme/app_theme.dart';
import 'package:asset_recovery_app/domain/entities/form_field_config.dart';
import 'package:asset_recovery_app/presentation/features/attempt/dynamic_field.dart';
import 'package:asset_recovery_app/presentation/features/map/map_screen.dart';
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

class _AttemptSectionScreenState extends State<AttemptSectionScreen> {
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.section.id == 'call') controller.loadCallRecordings();
      if (widget.section.id == 'location_visit') controller.fetchLiveLocation();
    });
  }

  Future<void> _onSave(BuildContext context) async {
    final controller = context.read<AttemptController>();
    final l = AppLocalizations.of(context);

    if (widget.isOutcome) {
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

    final error = await controller.saveSection(widget.section, l.t);
    if (!context.mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l.t('attempt.draftSaved'))));
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
                        : Text(widget.isOutcome ? l.t('wizard.submit') : l.t('section.save')),
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

/// In-app calling via Ozonetel (Rule 8a) — the call is proxied + recorded
/// server-side by the provider; this UI starts the call and lists whatever
/// recordings exist for this BP so far, replacing the old screenshot upload.
class _CallRecordingPanel extends StatelessWidget {
  const _CallRecordingPanel({required this.palette});
  final AppPalette palette;

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m}m ${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final controller = context.watch<AttemptController>();
    final mobile = controller.battery.customer.mobile;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: PillButton.yellow(
              '${l.t('call.startRecording')} · $mobile',
              palette: palette,
              icon: Icons.call,
              onPressed: () async {
                final seconds = await showDialog<int>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => _OngoingCallDialog(palette: palette, mobile: mobile),
                );
                if (seconds != null && seconds > 0) {
                  await controller.saveCallRecording(seconds);
                }
              },
            ),
          ),
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

/// Modal shown while an in-app call is "connected": displays the on-going
/// status with a live stopwatch and an End Call button. Popping returns the
/// elapsed seconds so the caller can persist it as a [CallRecording].
class _OngoingCallDialog extends StatefulWidget {
  const _OngoingCallDialog({required this.palette, required this.mobile});
  final AppPalette palette;
  final String mobile;

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
