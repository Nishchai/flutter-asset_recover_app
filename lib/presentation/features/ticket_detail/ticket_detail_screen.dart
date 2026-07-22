import 'package:asset_recovery_app/core/di/app_services.dart';
import 'package:asset_recovery_app/core/localization/app_localizations.dart';
import 'package:asset_recovery_app/core/theme/app_theme.dart';
import 'package:asset_recovery_app/core/utils/formatters.dart';
import 'package:asset_recovery_app/domain/entities/battery.dart';
import 'package:asset_recovery_app/domain/entities/enums.dart';
import 'package:asset_recovery_app/domain/entities/ticket.dart';
import 'package:asset_recovery_app/presentation/features/attempt/ticket_actions_hub.dart';
import 'package:asset_recovery_app/presentation/features/map/map_screen.dart';
import 'package:asset_recovery_app/presentation/features/qr/qr_scan_screen.dart';
import 'package:asset_recovery_app/presentation/shared/widgets/info_chip.dart';
import 'package:asset_recovery_app/presentation/shared/widgets/pill_button.dart';
import 'package:asset_recovery_app/presentation/shared/widgets/status_badge.dart';
import 'package:asset_recovery_app/presentation/state/auth_provider.dart';
import 'package:asset_recovery_app/presentation/state/ticket_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// BP detail (Figma Navigation flow): dark header, SLA-critical banner,
/// customer + battery attributes, attempt history, and the recovery CTAs.
class TicketDetailScreen extends StatelessWidget {
  const TicketDetailScreen({super.key, required this.ticketId});

  final String ticketId;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = context.read<AppPalette>();
    final tickets = context.watch<TicketProvider>();
    final ticket = tickets.byId(ticketId);

    if (ticket == null) {
      return Scaffold(appBar: AppBar(), body: Center(child: Text(l.t('common.error'))));
    }

    final bp = ticket.primaryBp;
    final isClosed = ticket.status == TicketStatus.closed ||
        ticket.status == TicketStatus.unrecoverable;

    return Scaffold(
      backgroundColor: palette.background,
      body: Column(
        children: [
          _Header(ticket: ticket, bp: bp, palette: palette),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              children: [
                if (isClosed && ticket.reason.isNotEmpty) ...[
                  StatusBadge(label: ticket.reason, color: palette.muted),
                  const SizedBox(height: 12),
                ] else ...[
                  _SlaBanner(ticket: ticket, palette: palette),
                  const SizedBox(height: 12),
                ],
                _CaseDetailsCard(ticket: ticket, bp: bp, palette: palette),
                const SizedBox(height: 12),
                _CustomerCard(bp: bp, palette: palette),
                if (context.read<AppServices>().config.flag('features.riskVisibility') &&
                    bp.riskScore != null) ...[
                  const SizedBox(height: 12),
                  _RiskCard(bp: bp, palette: palette),
                ],
                const SizedBox(height: 12),
                _AttemptHistory(ticket: ticket, palette: palette),
              ],
            ),
          ),
          if (!isClosed) _Actions(ticket: ticket, bp: bp, palette: palette),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.ticket, required this.bp, required this.palette});
  final Ticket ticket;
  final Battery bp;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final daysLeft =
        ticket.slaDaysLeft(context.read<AppServices>().config.slaDays, DateTime.now());
    return Container(
      decoration: BoxDecoration(gradient: palette.heroGradient),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: palette.darkBorder),
                      ),
                      child: Icon(Icons.arrow_back, color: palette.onDark, size: 18),
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => MapScreen(focusBp: bp)),
                    ),
                    child: Icon(Icons.map_outlined, color: palette.onDark),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(l.t('detail.batteryPack'),
                  style: TextStyle(
                      color: palette.mutedDark,
                      fontSize: 11,
                      letterSpacing: 1,),),
              const SizedBox(height: 4),
              Text(bp.bpId,
                  style: TextStyle(
                      color: palette.primary,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,),),
              const SizedBox(height: 4),
              Text('${l.t('detail.vin')} - ${bp.vin}',
                  style: TextStyle(color: palette.onDark, fontSize: 13),),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  InfoChip(
                    label: l.t('card.daysLeft', {'days': daysLeft}),
                    palette: palette,
                    onDark: true,
                    textColor: palette.danger,
                  ),
                  if (bp.inactiveDays != null)
                    InfoChip(
                        label: l.t('card.inactiveDays', {'days': bp.inactiveDays}),
                        palette: palette,
                        onDark: true,),
                  InfoChip(
                      label: l.t('card.kmAway',
                          {'km': Formatters.distanceValue(bp.distanceKm)},),
                      palette: palette,
                      onDark: true,),
                  if (bp.zoneStatus == ZoneStatus.fir)
                    InfoChip(
                        label: l.t('detail.firStage'),
                        palette: palette,
                        onDark: true,
                        textColor: palette.danger,),
                ],
              ),
              if ((bp.inactiveDays ?? 0) >=
                  context.read<AppServices>().config.intValue(
                      'business.notReturnedWarningDays', fallback: 20,)) ...[
                const SizedBox(height: 10),
                _NotReturnedTag(days: bp.inactiveDays!, palette: palette),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A prominent, distinctly-colored tag (as opposed to the plain "Inactive
/// Xdays" info chip) once a vehicle has been gone long enough to warrant
/// calling it out at a glance — not just noting the day count in passing.
/// Threshold is `business.notReturnedWarningDays` (config-driven, not hard
/// coded) so ops can tune it without a code change.
class _NotReturnedTag extends StatelessWidget {
  const _NotReturnedTag({required this.days, required this.palette});
  final int days;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: palette.danger.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.directions_car_filled, size: 15, color: palette.danger),
          const SizedBox(width: 6),
          Text(l.t('caseDetails.notReturnedTag', {'days': days}),
              style: TextStyle(
                  color: palette.danger, fontWeight: FontWeight.bold, fontSize: 12.5,),),
        ],
      ),
    );
  }
}

class _SlaBanner extends StatelessWidget {
  const _SlaBanner({required this.ticket, required this.palette});
  final Ticket ticket;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final config = context.read<AppServices>().config;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.danger.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: palette.danger, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                text: '${l.t('detail.slaCritical')} ',
                style: TextStyle(
                    color: palette.danger, fontWeight: FontWeight.bold, fontSize: 12.5,),
                children: [
                  TextSpan(
                    text: l.t('detail.slaCriticalBody', {
                      'attempts': config.maxAttemptsPerBp,
                      'days': config.slaDays,
                    }),
                    style: TextStyle(
                        color: palette.onSurface,
                        fontWeight: FontWeight.normal,),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Comprehensive, at-a-glance case snapshot mirroring the coordinator web
/// console's "Case Details" panel — case/vehicle/assignment fields the field
/// agent previously had no way to see together on the BP detail screen.
class _CaseDetailsCard extends StatelessWidget {
  const _CaseDetailsCard({required this.ticket, required this.bp, required this.palette});
  final Ticket ticket;
  final Battery bp;
  final AppPalette palette;

  String _dash(String? v) => (v == null || v.isEmpty) ? '—' : v;

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

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final config = context.read<AppServices>().config;
    final agent = context.read<AuthProvider>().agent;
    final lastAttempt = bp.latestAttempt;

    final fields = <(String, String)>[
      (l.t('detail.batteryPack'), bp.bpId),
      (l.t('caseDetails.caseId'), _dash(ticket.caseId.isEmpty ? null : ticket.caseId)),
      (l.t('caseDetails.caseCreated'), Formatters.date(ticket.createdAt)),
      (l.t('caseDetails.caseSource'), _dash(ticket.caseSource.isEmpty ? null : ticket.caseSource)),
      (l.t('caseDetails.caseType'), bp.caseType),
      (l.t('detail.vin'), _dash(bp.vin.isEmpty ? null : bp.vin)),
      (l.t('caseDetails.vehicleType'), _dash(bp.vehicleType.isEmpty ? null : bp.vehicleType)),
      (l.t('caseDetails.vehicleId'), _dash(bp.vehicleId.isEmpty ? null : bp.vehicleId)),
      (l.t('caseDetails.customerName'), bp.customer.name),
      (l.t('caseDetails.customerPhone'), bp.customer.maskedMobile()),
      (l.t('caseDetails.zone'), _dash(bp.zone.isEmpty ? null : bp.zone)),
      (l.t('caseDetails.subzone'), _dash(bp.subzone.isEmpty ? null : bp.subzone)),
      (l.t('detail.lastSwap'), bp.lastSwap == null ? '—' : Formatters.date(bp.lastSwap!)),
      (l.t('caseDetails.lastSoc'), bp.soc == null ? '—' : '${bp.soc}%'),
      (l.t('detail.lastStation'), _dash(bp.lastStation.isEmpty ? null : bp.lastStation)),
      (l.t('caseDetails.assignedTo'), _dash(agent?.name)),
      (l.t('caseDetails.assignedOn'), Formatters.date(ticket.createdAt)),
      (l.t('caseDetails.recoveryAttempts'), '${bp.attemptCount} / ${config.maxAttemptsPerBp}'),
      (
        l.t('caseDetails.lastAttemptDate'),
        lastAttempt == null ? '—' : Formatters.date(lastAttempt.createdAt),
      ),
      (l.t('caseDetails.status'), _statusLabel(l)),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.t('caseDetails.title'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),),
          const SizedBox(height: 14),
          Wrap(
            runSpacing: 14,
            children: [
              for (final (label, value) in fields)
                FractionallySizedBox(
                  widthFactor: 0.5,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label.toUpperCase(),
                            style: TextStyle(
                                fontSize: 10.5, color: palette.muted, letterSpacing: 0.4,),),
                        const SizedBox(height: 3),
                        Text(value,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({required this.bp, required this.palette});
  final Battery bp;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(bp.customer.name,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold,),),
                    const SizedBox(height: 2),
                    Text(bp.vehicleType,
                        style: TextStyle(color: palette.muted, fontSize: 13),),
                  ],
                ),
              ),
              Column(
                children: [
                  Icon(Icons.ev_station, color: palette.primaryDark, size: 30),
                  const SizedBox(height: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: palette.chipBg,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(bp.vehicleRegNo,
                        style: const TextStyle(
                            fontSize: 10, fontWeight: FontWeight.w600,),),
                  ),
                ],
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Divider(height: 1, color: palette.border),
          ),
          _row(l.t('detail.mobile'), bp.customer.maskedMobile(), palette),
          _row(l.t('detail.address'), bp.customer.address, palette),
          if (bp.lastSwap != null)
            _row(l.t('detail.lastSwap'), Formatters.date(bp.lastSwap!), palette),
          _row(l.t('detail.lastStation'), bp.lastStation, palette),
          _row(l.t('detail.lastTiu'), bp.lastTiuTime, palette),
          _row(l.t('detail.lastSeen'), bp.lastKnownLocation.display, palette,
              last: true,),
        ],
      ),
    );
  }

  Widget _row(String k, String v, AppPalette palette, {bool last = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(k, style: TextStyle(color: palette.muted, fontSize: 13)),
          ),
          Expanded(
            child: Text(v,
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),),
          ),
        ],
      ),
    );
  }
}

/// M2-03 — read-only risk score/category from the ML layer. The app only
/// ever displays these (never computes/edits); visibility is gated by
/// `features.riskVisibility` so a coordinator can turn it off org-wide.
class _RiskCard extends StatelessWidget {
  const _RiskCard({required this.bp, required this.palette});
  final Battery bp;
  final AppPalette palette;

  Color _categoryColor(String? category) => switch (category) {
        'high' => palette.danger,
        'medium' => palette.warning,
        _ => palette.info,
      };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final score = bp.riskScore!;
    final categoryColor = _categoryColor(bp.riskCategory);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.t('risk.title'),
                    style: TextStyle(color: palette.muted, fontSize: 12),),
                const SizedBox(height: 4),
                Text('${l.t('risk.score')}: ${score.toStringAsFixed(0)}/100',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),),
              ],
            ),
          ),
          StatusBadge(
            label: l.t('risk.category.${bp.riskCategory ?? 'low'}'),
            color: categoryColor,
          ),
        ],
      ),
    );
  }
}

class _AttemptHistory extends StatelessWidget {
  const _AttemptHistory({required this.ticket, required this.palette});
  final Ticket ticket;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final config = context.read<AppServices>().config;
    final attempts = ticket.primaryBp.attempts;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.t('detail.attemptHistory'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),),
          const SizedBox(height: 2),
          Text(l.t('detail.attemptHistorySub', {'n': config.maxAttemptsPerBp}),
              style: TextStyle(color: palette.muted, fontSize: 12),),
          const SizedBox(height: 14),
          if (attempts.isEmpty)
            Text('—', style: TextStyle(color: palette.muted))
          else
            for (final a in attempts)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_circle, color: palette.info, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l.t('detail.attemptedOn',
                                {'date': Formatters.date(a.createdAt)},),
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13,),
                          ),
                          const SizedBox(height: 6),
                          if (a.resolution.isNotEmpty)
                            StatusBadge(
                              label: a.resolution,
                              color: palette.outcomeColor(a.resolution),
                            )
                          else
                            InfoChip(label: l.t('detail.autoLogged'), palette: palette),
                          if (a.remark.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(a.remark,
                                style: TextStyle(color: palette.muted, fontSize: 12),),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.ticket, required this.bp, required this.palette});
  final Ticket ticket;
  final Battery bp;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: PillButton.outline(
                  l.t('detail.scanQr'),
                  palette: palette,
                  icon: Icons.qr_code_scanner,
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          QrScanScreen(battery: bp, ticketId: ticket.ticketId),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: PillButton.dark(
                  l.t('detail.ticketActions'),
                  palette: palette,
                  trailingArrow: true,
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          TicketActionsHub(ticketId: ticket.ticketId, battery: bp),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Re-exported for the closed-ticket history view used elsewhere.
class TicketResolutionBadge extends StatelessWidget {
  const TicketResolutionBadge({super.key, required this.resolution, required this.palette});
  final String resolution;
  final AppPalette palette;
  @override
  Widget build(BuildContext context) =>
      StatusBadge(label: resolution, color: palette.outcomeColor(resolution));
}
