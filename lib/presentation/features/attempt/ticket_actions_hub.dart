import 'package:asset_recovery_app/core/di/app_services.dart';
import 'package:asset_recovery_app/core/di/injector.dart';
import 'package:asset_recovery_app/core/localization/app_localizations.dart';
import 'package:asset_recovery_app/core/theme/app_theme.dart';
import 'package:asset_recovery_app/domain/entities/battery.dart';
import 'package:asset_recovery_app/domain/entities/form_field_config.dart';
import 'package:asset_recovery_app/domain/usecases/call_usecase.dart';
import 'package:asset_recovery_app/domain/usecases/draft_attempt_usecase.dart';
import 'package:asset_recovery_app/domain/usecases/get_live_location_usecase.dart';
import 'package:asset_recovery_app/domain/usecases/update_customer_usecase.dart';
import 'package:asset_recovery_app/presentation/features/attempt/attempt_section_screen.dart';
import 'package:asset_recovery_app/presentation/state/attempt_controller.dart';
import 'package:asset_recovery_app/presentation/state/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Entry point for the free-choice recovery actions (item 4). Unlike the old
/// forced Call → Location → Home → Outcome wizard, every card here is an
/// independent action the Field Agent can open, fill and save in any order,
/// any number of times — progress persists as a draft (item 13) until the
/// Outcome action is submitted.
class TicketActionsHub extends StatelessWidget {
  const TicketActionsHub({super.key, required this.ticketId, required this.battery});

  final String ticketId;
  final Battery battery;

  static const _icons = {
    'phone': Icons.phone,
    'location': Icons.location_on,
    'home': Icons.home_outlined,
    'package': Icons.inventory_2_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final services = context.read<AppServices>();
    final agentId = context.read<AuthProvider>().agent!.id;
    return ChangeNotifierProvider<AttemptController>(
      create: (_) {
        final c = AttemptController(
          flow: services.attemptFlow,
          ticketId: ticketId,
          battery: battery,
          agentId: agentId,
          config: services.config,
          location: services.location,
          proof: services.proof,
          getDraft: sl<GetDraftUseCase>(),
          saveDraft: sl<SaveDraftUseCase>(),
          updateCustomer: sl<UpdateCustomerUseCase>(),
          auditLog: services.auditLog,
          getLiveLocation: sl<GetLiveLocationUseCase>(),
          startCallUseCase: sl<StartCallUseCase>(),
          getCallRecordings: sl<GetCallRecordingsUseCase>(),
          syncQueue: services.syncQueue,
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
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ChangeNotifierProvider.value(
              value: controller,
              child: AttemptSectionScreen(section: section, isOutcome: isOutcome),
            ),
          ),
        ),
      ),
    );
  }
}
