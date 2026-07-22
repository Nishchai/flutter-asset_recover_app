import 'package:asset_recovery_app/core/localization/app_localizations.dart';
import 'package:asset_recovery_app/core/theme/app_theme.dart';
import 'package:asset_recovery_app/core/utils/formatters.dart';
import 'package:asset_recovery_app/domain/entities/enums.dart';
import 'package:asset_recovery_app/domain/entities/ticket.dart';
import 'package:asset_recovery_app/presentation/shared/widgets/info_chip.dart';
import 'package:flutter/material.dart';

/// Home ticket card (Figma): TKT id + BP serial + View, with a chip row for
/// distance / days-left / inactivity and a second row for vehicle + status.
class TicketCard extends StatelessWidget {
  const TicketCard({
    super.key,
    required this.ticket,
    required this.slaDays,
    required this.slaWarnDays,
    required this.palette,
    required this.onTap,
  });

  final Ticket ticket;
  final int slaDays;
  final int slaWarnDays;
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final bp = ticket.primaryBp;
    final daysLeft = ticket.slaDaysLeft(slaDays, DateTime.now());
    final urgent = daysLeft <= slaWarnDays;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(ticket.ticketId,
                          style: TextStyle(fontSize: 11, color: palette.muted),),
                      const SizedBox(height: 2),
                      Text(bp.bpId,
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.bold,),),
                    ],
                  ),
                ),
                Row(
                  children: [
                    Text(l.t('card.view'),
                        style: TextStyle(
                            color: palette.onSurface,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,),),
                    const SizedBox(width: 2),
                    const Icon(Icons.arrow_forward, size: 14),
                  ],
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Divider(height: 1, color: palette.border),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                InfoChip(
                  label: l.t('card.km', {'km': Formatters.distanceValue(bp.distanceKm)}),
                  palette: palette,
                  icon: Icons.location_on_outlined,
                ),
                InfoChip(
                  label: l.t('card.daysLeft', {'days': daysLeft}),
                  palette: palette,
                  textColor: urgent ? palette.danger : null,
                ),
                if (bp.inactiveDays != null)
                  InfoChip(
                    label: l.t('card.inactiveDays', {'days': bp.inactiveDays}),
                    palette: palette,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                InfoChip(label: _vehicleShort(bp.vehicleType), palette: palette),
                InfoChip(label: _statusLabel(l), palette: palette),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _vehicleShort(String type) =>
      type.contains('-') ? type.split('-').last.trim() : type;

  String _statusLabel(AppLocalizations l) {
    switch (ticket.status) {
      case TicketStatus.assigned:
        return l.t('filter.open');
      case TicketStatus.inProgress:
        return l.t('filter.inProgress');
      case TicketStatus.pending:
        return l.t('filter.pending');
      case TicketStatus.closed:
      case TicketStatus.unrecoverable:
        return l.t('detail.closedIn');
    }
  }
}
