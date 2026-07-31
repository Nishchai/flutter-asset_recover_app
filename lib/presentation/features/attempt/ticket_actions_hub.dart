import 'dart:async';

import 'package:asset_recovery_app/core/di/app_services.dart';
import 'package:asset_recovery_app/core/di/injector.dart';
import 'package:asset_recovery_app/core/localization/app_localizations.dart';
import 'package:asset_recovery_app/core/theme/app_theme.dart';
import 'package:asset_recovery_app/domain/entities/battery.dart';
import 'package:asset_recovery_app/domain/entities/battery_detail.dart';
import 'package:asset_recovery_app/domain/entities/form_field_config.dart';
import 'package:asset_recovery_app/domain/entities/ticket_detail.dart';
import 'package:asset_recovery_app/domain/usecases/call_usecase.dart';
import 'package:asset_recovery_app/domain/usecases/draft_attempt_usecase.dart';
import 'package:asset_recovery_app/domain/usecases/get_live_location_usecase.dart';
import 'package:asset_recovery_app/domain/usecases/submit_attempt_record_usecase.dart';
import 'package:asset_recovery_app/domain/usecases/update_customer_details_usecase.dart';
import 'package:asset_recovery_app/domain/usecases/update_customer_usecase.dart';
import 'package:asset_recovery_app/presentation/features/attempt/attempt_section_screen.dart';
import 'package:asset_recovery_app/presentation/shared/mark_ticket_in_progress.dart';
import 'package:asset_recovery_app/presentation/state/attempt_controller.dart';
import 'package:asset_recovery_app/presentation/state/auth_provider.dart';
import 'package:asset_recovery_app/presentation/state/ticket_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Entry point for the free-choice recovery actions (item 4). Unlike the old
/// forced Call → Location → Home → Outcome wizard, every card here is an
/// independent action the Field Agent can open, fill and save in any order,
/// any number of times — progress persists as a draft (item 13) until the
/// Outcome action is submitted.
class TicketActionsHub extends StatelessWidget {
  const TicketActionsHub({
    super.key,
    required this.ticketId,
    required this.battery,
    this.batteryDetail,
    this.ticketDetail,
  });

  final String ticketId;
  final Battery battery;

  /// Live battery telemetry from `battery.getBatteryDetails`, already fetched by
  /// the BP detail screen. Forwarded to [AttemptController] so the Visit BP
  /// Location section can show the telemetry's last lat/long + last TIU and
  /// navigate "View on Map" to those coordinates. Null when the call hasn't
  /// landed (or returned no row) — the section then falls back to the cached
  /// battery values.
  final BatteryDetail? batteryDetail;

  /// Full ticket detail from `GET /tickets/{UUID}`, already fetched by the BP
  /// detail screen. Forwarded to [AttemptController] so the Visit Customer
  /// Address section's "Customer Address" card shows the same parsed address
  /// (line 1, city, state, pincode) as that screen's customer card. Null until
  /// the call lands — the card then falls back to the cached customer address.
  final TicketDetail? ticketDetail;

  static const _icons = {
    'phone': Icons.phone,
    'location': Icons.location_on,
    'home': Icons.home_outlined,
    'package': Icons.inventory_2_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final services = context.read<AppServices>();
    final agent = context.read<AuthProvider>().agent!;
    // agentName comes from the tickets API (Ticket.agentName from the list /
    // detail response), not the signed-in session.
    final ticketAgentName =
        context.read<TicketProvider>().byId(ticketId)?.agentName ?? '';
    return ChangeNotifierProvider<AttemptController>(
      create: (_) {
        final c = AttemptController(
          flow: services.attemptFlow,
          ticketId: ticketId,
          battery: battery,
          batteryDetail: batteryDetail,
          ticketDetail: ticketDetail,
          agentId: agent.id,
          agentName: ticketAgentName,
          submitAttemptRecord: sl<SubmitAttemptRecordUseCase>(),
          config: services.config,
          location: services.location,
          proof: services.proof,
          blobUpload: services.blobUpload,
          getDraft: sl<GetDraftUseCase>(),
          saveDraft: sl<SaveDraftUseCase>(),
          updateCustomer: sl<UpdateCustomerUseCase>(),
          updateCustomerDetails: sl<UpdateCustomerDetailsUseCase>(),
          auditLog: services.auditLog,
          getLiveLocation: sl<GetLiveLocationUseCase>(),
          startCallUseCase: sl<StartCallUseCase>(),
          getCallRecordings: sl<GetCallRecordingsUseCase>(),
          syncQueue: services.syncQueue,
          simCall: services.simCall,
        )..init();
        return c;
      },
      child: const _HubBody(),
    );
  }
}

class _HubBody extends StatelessWidget {
  const _HubBody();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = context.read<AppPalette>();
    final controller = context.watch<AttemptController>();

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        title: Text(l.t('hub.title')),
        backgroundColor: palette.surface,
      ),
      body: controller.loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(l.t('hub.subtitle'),
                    style: TextStyle(color: palette.muted, fontSize: 13),),
                const SizedBox(height: 16),
                for (final section in controller.actionSections)
                  _ActionCard(section: section, palette: palette),
                const Divider(height: 32),
                _ActionCard(
                    section: controller.outcomeSection, palette: palette, isOutcome: true,),
              ],
            ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.section,
    required this.palette,
    this.isOutcome = false,
  });

  final StepConfig section;
  final AppPalette palette;
  final bool isOutcome;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final controller = context.watch<AttemptController>();
    final status = controller.sectionStatus(section);

    final Color statusColor;
    final String statusLabel;
    switch (status) {
      case SectionStatus.done:
        statusColor = palette.success;
        statusLabel = l.t('hub.status.done');
      case SectionStatus.partial:
        statusColor = palette.warning;
        statusLabel = l.t('hub.status.partial');
      case SectionStatus.empty:
        statusColor = palette.muted;
        statusLabel = l.t('hub.status.empty');
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: palette.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: palette.border),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: isOutcome ? palette.primaryLight : palette.chipBg,
          child: Icon(
            TicketActionsHub._icons[section.icon] ?? Icons.circle_outlined,
            color: isOutcome ? palette.primaryDark : palette.onSurface,
          ),
        ),
        title: Text(l.t(section.titleKey),
            style: const TextStyle(fontWeight: FontWeight.w600),),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(statusLabel,
                style: TextStyle(
                    color: statusColor, fontSize: 11, fontWeight: FontWeight.w600,),),
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          // Opening any of the three action cards (Call Customer, Visit BP
          // Location, Visit Customer Address) means the agent has started
          // working the case, so move the ticket to `inProgress`. Not fired for
          // the Outcome card, which closes the case rather than starting it.
          if (!isOutcome) {
            unawaited(markTicketInProgress(controller.ticketId));
          }
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ChangeNotifierProvider.value(
                value: controller,
                child:
                    AttemptSectionScreen(section: section, isOutcome: isOutcome),
              ),
            ),
          );
        },
      ),
    );
  }
}
