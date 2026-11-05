import 'dart:async';

import 'package:asset_recovery_app/core/di/app_services.dart';
import 'package:asset_recovery_app/core/di/injector.dart';
import 'package:asset_recovery_app/core/error/result.dart';
import 'package:asset_recovery_app/core/localization/app_localizations.dart';
import 'package:asset_recovery_app/core/services/sync_queue_service.dart';
import 'package:asset_recovery_app/core/theme/app_theme.dart';
import 'package:asset_recovery_app/core/utils/formatters.dart';
import 'package:asset_recovery_app/domain/entities/battery.dart';
import 'package:asset_recovery_app/domain/entities/battery_detail.dart';
import 'package:asset_recovery_app/domain/entities/enums.dart';
import 'package:asset_recovery_app/domain/entities/geo_point.dart';
import 'package:asset_recovery_app/domain/entities/ticket.dart';
import 'package:asset_recovery_app/domain/entities/ticket_detail.dart';
import 'package:asset_recovery_app/domain/usecases/get_battery_detail_usecase.dart';
import 'package:asset_recovery_app/domain/usecases/get_ticket_full_detail_usecase.dart';
import 'package:asset_recovery_app/presentation/features/attempt/ticket_actions_hub.dart';
import 'package:asset_recovery_app/presentation/features/map/map_screen.dart';
import 'package:asset_recovery_app/presentation/shared/widgets/info_chip.dart';
import 'package:asset_recovery_app/presentation/shared/widgets/photo_gallery_viewer.dart';
import 'package:asset_recovery_app/presentation/shared/widgets/pill_button.dart';
import 'package:asset_recovery_app/presentation/shared/widgets/status_badge.dart';
import 'package:asset_recovery_app/presentation/state/auth_provider.dart';
import 'package:asset_recovery_app/presentation/state/ticket_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// BP detail (Figma Navigation flow): dark header, SLA-critical banner,
/// customer + battery attributes, attempt history, and the recovery CTAs.
class TicketDetailScreen extends StatefulWidget {
  const TicketDetailScreen({super.key, required this.ticketId});

  final String ticketId;

  @override
  State<TicketDetailScreen> createState() => _TicketDetailScreenState();
}

class _TicketDetailScreenState extends State<TicketDetailScreen> {
  /// Full nested detail from `GET /tickets/{UUID}`. Fetched once, lazily, using
  /// the ticket's backend resource UUID. Null until it arrives (or if it fails)
  /// — the screen renders from the already-loaded [Ticket] regardless, so this
  /// is a non-critical enrichment.
  TicketDetail? _detail;

  /// Live battery telemetry from the Battery Master API
  /// (`battery.getBatteryDetails`), keyed by the ticket's `bpId`. Supplies the
  /// customer card's "Last Seen" (last lat/long) and "Last TIU" (last TIU
  /// timestamp). Null until it arrives (or if it fails) — same non-critical
  /// enrichment contract as [_detail].
  BatteryDetail? _batteryDetail;
  bool _fetchStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_fetchStarted) return;
    final ticket = context.read<TicketProvider>().byId(widget.ticketId);
    if (ticket == null) return;
    _fetchStarted = true;
    // The detail endpoint is keyed by the backend UUID (`id` in the list
    // response, kept as [Ticket.caseId]); fall back to the ticket number if the
    // UUID isn't populated (e.g. mock data).
    final uuid = ticket.caseId.isNotEmpty ? ticket.caseId : ticket.ticketId;
    _detailId = uuid;
    _loadDetail(uuid);
    // The battery telemetry endpoint is keyed by the BP id from the ticket.
    _loadBatteryDetail(ticket.primaryBp.bpId);
  }

  /// Key [_loadDetail] was started with, kept so the screen can refetch after
  /// an attempt is recorded.
  String _detailId = '';

  Future<void> _loadDetail(String uuid) async {
    // Attempts made offline sit on the sync queue until they are replayed, and
    // the history below is read from the server — so give a pending flush a
    // moment to land first, or the new attempt would be missing from the list.
    await _flushPendingSync();
    if (!mounted) return;
    final result = await sl<GetTicketFullDetailUseCase>()(uuid);
    if (!mounted || result.isErr) return;
    setState(() => _detail = result.valueOrNull);
  }

  Future<void> _flushPendingSync() async {
    final queue = sl<SyncQueueService>();
    if (queue.pendingCount == 0) return;
    try {
      await queue.drain().timeout(const Duration(seconds: 8));
    } catch (_) {
      // Still offline or slow — show what the server has; the queue keeps
      // retrying in the background.
    }
  }

  /// The Ticket Actions hub was closed: a new attempt may have been recorded
  /// (or queued), so reload the detail instead of leaving the old history up.
  Future<void> _refreshAfterAttempt() {
    if (_detailId.isEmpty) return Future.value();
    return _loadDetail(_detailId);
  }

  Future<void> _loadBatteryDetail(String bpId) async {
    if (bpId.isEmpty) return;
    final result = await sl<GetBatteryDetailUseCase>()(bpId);
    if (!mounted || result.isErr) return;
    setState(() => _batteryDetail = result.valueOrNull);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = context.read<AppPalette>();
    final tickets = context.watch<TicketProvider>();
    final ticket = tickets.byId(widget.ticketId);

    if (ticket == null) {
      return Scaffold(appBar: AppBar(), body: Center(child: Text(l.t('common.error'))));
    }

    final bp = ticket.primaryBp;
    final isClosed = ticket.status == TicketStatus.closed ||
        ticket.status == TicketStatus.unrecoverable;

    // Coordinates behind the customer card's "Last Seen" — passed to the map
    // opened from the header map icon so both show the same spot.
    final lastSeen = resolveLastSeenPoint(bp, _detail, _batteryDetail);

    return Scaffold(
      backgroundColor: palette.background,
      body: Column(
        children: [
          _Header(
              ticket: ticket,
              bp: bp,
              palette: palette,
              lastSeen: lastSeen,
              detail: _detail,),
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
                _CaseDetailsCard(
                    ticket: ticket,
                    bp: bp,
                    palette: palette,
                    batteryDetail: _batteryDetail,
                    detail: _detail,),
                const SizedBox(height: 12),
                _CustomerCard(
                    bp: bp,
                    palette: palette,
                    detail: _detail,
                    batteryDetail: _batteryDetail,),
                if (context.read<AppServices>().config.flag('features.riskVisibility') &&
                    bp.riskScore != null) ...[
                  const SizedBox(height: 12),
                  _RiskCard(bp: bp, palette: palette),
                ],
                const SizedBox(height: 12),
                _AttemptHistory(detail: _detail, palette: palette),
              ],
            ),
          ),
          if (!isClosed)
            _Actions(
                ticket: ticket,
                bp: bp,
                palette: palette,
                batteryDetail: _batteryDetail,
                detail: _detail,
                onReturned: _refreshAfterAttempt,),
        ],
      ),
    );
  }
}

/// Resolves the coordinates behind the customer card's "Last Seen" value,
/// following the SAME source precedence as `_CustomerCard._lastSeen`: battery
/// telemetry lat/lng → ticket-detail customer `geoLocation` (parsed from its
/// normalised "lat, lng" string) → the base battery's last-known location. The
/// header map icon feeds this to [MapScreen] as its `focusLocation` so the map
/// centres on exactly what the card shows.
GeoPoint resolveLastSeenPoint(
  Battery bp,
  TicketDetail? detail,
  BatteryDetail? batteryDetail,
) {
  final telemetry = batteryDetail?.location;
  if (telemetry != null) return telemetry;
  final parsed = _parseLatLng(detail?.customer?.geoLocation);
  if (parsed != null) return parsed;
  return bp.lastKnownLocation;
}

/// Parses a `"lat, lng"` string (the shape `TicketDetailCustomer.geoLocation`
/// is normalised to) into a [GeoPoint]. Returns null for null/empty input or
/// anything that isn't two parseable comma-separated doubles.
GeoPoint? _parseLatLng(String? s) {
  if (s == null || s.isEmpty) return null;
  final parts = s.split(',');
  if (parts.length != 2) return null;
  final lat = double.tryParse(parts[0].trim());
  final lng = double.tryParse(parts[1].trim());
  if (lat == null || lng == null) return null;
  return GeoPoint(lat: lat, lng: lng);
}

class _Header extends StatelessWidget {
  const _Header({
    required this.ticket,
    required this.bp,
    required this.palette,
    required this.lastSeen,
    this.detail,
  });
  final Ticket ticket;
  final Battery bp;
  final AppPalette palette;

  /// "Last Seen" coordinates (see [resolveLastSeenPoint]) forwarded to the live
  /// tracking page as its `lat`/`lng` params.
  final GeoPoint lastSeen;

  /// Full ticket detail from `tickets.fullDetail`, when it has arrived. Source
  /// of the "VIN" readout's `battery.vehicleId`.
  final TicketDetail? detail;

  /// VIN — the `tickets.fullDetail` response's `battery.vehicleId` wins; falls
  /// back to the list-summary [Battery.vehicleId] until the detail fetch lands.
  String _vehicleId() {
    final fromDetail = detail?.battery?.vehicleId ?? '';
    return fromDetail.isNotEmpty ? fromDetail : bp.vehicleId;
  }

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
                    // The app's own map (same widget the Map tab and the
                    // attempt screen use), focused on this one BP at the
                    // coordinates the Battery Master lookup on this screen
                    // returned — no backend tracking web page.
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            MapScreen(focusBp: bp, focusLocation: lastSeen),
                      ),
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
              Text('${l.t('detail.vin')} - ${_vehicleId()}',
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
  const _CaseDetailsCard({
    required this.ticket,
    required this.bp,
    required this.palette,
    this.batteryDetail,
    this.detail,
  });
  final Ticket ticket;
  final Battery bp;
  final AppPalette palette;

  /// Live battery telemetry from `battery.getBatteryDetails`, when it has
  /// arrived. Takes precedence for "Last SOC" (`lastSoc`).
  final BatteryDetail? batteryDetail;

  /// Full ticket detail from the ticket-detail endpoint, when it has arrived.
  /// Source of "Recovery Attempts" — the same `attempts` array the Attempt
  /// History card renders.
  final TicketDetail? detail;

  String _dash(String? v) => (v == null || v.isEmpty) ? '—' : v;

  /// Recovery attempts — the `attempts` array from the ticket-detail response
  /// is authoritative; until it lands, the list summary's `attemptCount` fills
  /// in (the paged home response can leave it stale).
  String _recoveryAttempts() =>
      '${detail?.attempts.length ?? bp.attemptCount}';

  /// Last SOC — the battery telemetry's `lastSoc` wins; then the base
  /// battery's `soc`; em-dash when neither is present. Rendered as a whole
  /// percent to match the base `soc` display.
  String _lastSoc() {
    final soc = batteryDetail?.lastSoc ?? bp.soc?.toDouble();
    return soc == null ? '—' : '${soc.toStringAsFixed(0)}%';
  }

  /// VIN — the `tickets.fullDetail` response's `battery.vehicleId` wins; falls
  /// back to the list-summary [Battery.vehicleId] until the detail fetch lands.
  String _vehicleId() {
    final fromDetail = detail?.battery?.vehicleId ?? '';
    return fromDetail.isNotEmpty ? fromDetail : bp.vehicleId;
  }

  String _statusLabel(AppLocalizations l) {
    switch (ticket.status) {
      case TicketStatus.assigned:
        return l.t('filter.open');
      case TicketStatus.inProgress:
        return l.t('filter.inProgress');
      // `pending` covers the backend's `pending_verification` — see
      // [TicketCard._statusLabel].
      case TicketStatus.pending:
        return l.t('filter.pendingVerification');
      case TicketStatus.closed:
      case TicketStatus.unrecoverable:
        return l.t('detail.closedIn');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final agent = context.read<AuthProvider>().agent;
    final lastAttempt = bp.latestAttempt;

    final fields = <(String, String)>[
      (l.t('detail.batteryPack'), bp.bpId),
      (l.t('caseDetails.caseId'), _dash(ticket.ticketId.isEmpty ? null : ticket.ticketId)),
      (l.t('caseDetails.caseCreated'), Formatters.date(ticket.createdAt)),
      (l.t('caseDetails.caseSource'), _dash(ticket.caseSource.isEmpty ? null : ticket.caseSource)),
      (l.t('caseDetails.caseType'), bp.caseType),
      (l.t('detail.vin'), _dash(_vehicleId().isEmpty ? null : _vehicleId())),
      (l.t('caseDetails.vehicleType'), _dash(bp.vehicleType.isEmpty ? null : bp.vehicleType)),
      (l.t('caseDetails.vehicleRegNo'), _dash(bp.vehicleRegNo.isEmpty ? null : bp.vehicleRegNo)),
      (l.t('caseDetails.customerName'), bp.customer.name),
      (l.t('caseDetails.customerPhone'), bp.customer.maskedMobile()),
      (l.t('caseDetails.zone'), _dash(bp.zone.isEmpty ? null : bp.zone)),
      (l.t('caseDetails.subzone'), _dash(bp.subzone.isEmpty ? null : bp.subzone)),
      (l.t('detail.lastSwap'), bp.lastSwap == null ? '—' : Formatters.date(bp.lastSwap!)),
      (l.t('caseDetails.lastSoc'), _lastSoc()),
      (l.t('detail.lastStation'), _dash(bp.lastStation.isEmpty ? null : bp.lastStation)),
      (l.t('caseDetails.assignedTo'), _dash(agent?.name)),
      (l.t('caseDetails.assignedOn'), Formatters.date(ticket.createdAt)),
      // Attempts are uncapped, so the count stands on its own — there is no
      // "of N" allowance left to render against it.
      (l.t('caseDetails.recoveryAttempts'), _recoveryAttempts()),
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
  const _CustomerCard({
    required this.bp,
    required this.palette,
    this.detail,
    this.batteryDetail,
  });
  final Battery bp;
  final AppPalette palette;

  /// Full ticket detail from `GET /tickets/{UUID}`, when it has arrived. Its
  /// customer sub-object supplies three fields the list summary lacks:
  ///   • `geoLocation`         → Last Seen
  ///   • `lastSwapDate`        → Last TIU
  ///   • `lastSwapStationCode` → Last Swap
  /// Each falls back to the base [Battery] value until the detail loads.
  final TicketDetail? detail;

  /// Live battery telemetry from `battery.getBatteryDetails`, when it has
  /// arrived. Takes precedence for the two fields it carries:
  ///   • `lastLatitude`/`lastLongitude` → Last Seen
  ///   • `lastTiuTimestamp`             → Last TIU
  final BatteryDetail? batteryDetail;

  String _dash(String v) => v.isEmpty ? '—' : v;

  /// Mobile → phonePrimary + phoneSecondary. Attaches whichever of the two is
  /// non-empty (both, joined, when both are present; empty when neither is).
  /// Falls back to the base customer's mobile until the detail loads.
  ///
  /// Every number is masked to its first five digits for display. Masking is
  /// applied per number, BEFORE the join, so a second number is not left
  /// readable by a mask that only counts from the start of the joined string.
  String _mobile() {
    final c = detail?.customer;
    if (c == null) return Formatters.maskedPhone(bp.customer.mobile);
    final parts = [c.phonePrimary, c.phoneSecondary]
        .where((p) => p.isNotEmpty)
        .map(Formatters.maskedPhone)
        .toList();
    return _dash(parts.join(', '));
  }

  /// Address → all address components concatenated (line 1, city, state,
  /// pincode), skipping empties. Falls back to the base customer address.
  String _address() {
    final parsed = detail?.customer?.fullAddress ?? '';
    return parsed.isEmpty ? bp.customer.address : parsed;
  }

  /// Last Seen — the battery telemetry's last lat/long wins; then the ticket
  /// detail's customer geoLocation; then the base battery's last known location.
  String _lastSeen() {
    final loc = batteryDetail?.location;
    if (loc != null) return loc.display;
    final geo = detail?.customer?.geoLocation;
    if (geo != null && geo.isNotEmpty) return geo;
    return bp.lastKnownLocation.display;
  }

  /// Last TIU — the battery telemetry's last TIU timestamp wins; then the ticket
  /// detail's lastSwapDate; then the base battery's lastTiuTime string.
  String _lastTiu() {
    final tiu = batteryDetail?.lastTiuTimestamp;
    if (tiu != null) return Formatters.dateTime(tiu);
    final date = detail?.customer?.lastSwapDate;
    if (date != null) return Formatters.date(date);
    return _dash(bp.lastTiuTime);
  }

  /// lastSwapStationCode → Last Swap.
  String _lastSwap() {
    final code = detail?.customer?.lastSwapStationCode;
    if (code != null && code.isNotEmpty) return code;
    return bp.lastSwap != null ? Formatters.date(bp.lastSwap!) : '—';
  }

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
          _row(l.t('detail.mobile'), _mobile(), palette),
          _row(l.t('detail.address'), _address(), palette),
          // The next three are enriched from `GET /tickets/{UUID}` when it
          // loads (customer geoLocation / lastSwapDate / lastSwapStationCode),
          // falling back to the base battery values until then.
          _row(l.t('detail.lastSwap'), _lastSwap(), palette),
          _row(l.t('detail.lastStation'), _dash(bp.lastStation), palette),
          _row(l.t('detail.lastTiu'), _lastTiu(), palette),
          _row(l.t('detail.lastSeen'), _lastSeen(), palette, last: true),
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
  const _AttemptHistory({required this.detail, required this.palette});

  /// Full ticket detail (source of the persisted [TicketDetailAttempt] records).
  /// Null until the detail endpoint responds — the section renders an empty
  /// state in the meantime.
  final TicketDetail? detail;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final attempts = detail?.attempts ?? const <TicketDetailAttempt>[];
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
          Text(l.t('detail.attemptHistorySub'),
              style: TextStyle(color: palette.muted, fontSize: 12),),
          const SizedBox(height: 14),
          if (attempts.isEmpty)
            Text('—', style: TextStyle(color: palette.muted))
          else
            for (var i = 0; i < attempts.length; i++) ...[
              if (i > 0) ...[
                const SizedBox(height: 14),
                Divider(height: 1, color: palette.border),
                const SizedBox(height: 14),
              ],
              _AttemptTile(attempt: attempts[i], palette: palette),
            ],
        ],
      ),
    );
  }
}

/// A single persisted attempt: a highlighted header row (type · outcome), a
/// label/value block (the two timestamps plus any remark reasons), a meta row
/// (agent · geo), and proof photos.
///
/// No elapsed-time readout — the raw `attemptedAt`/`completedAt` stamps are
/// shown as received instead of a derived "in 7 min" duration.
class _AttemptTile extends StatelessWidget {
  const _AttemptTile({required this.attempt, required this.palette});

  final TicketDetailAttempt attempt;
  final AppPalette palette;

  /// Secondary text size shared by every readout in the tile.
  static const double _bodySize = 12;

  /// The service sends both stamps in UTC; the agent reads them in IST.
  static String _stamp(DateTime? dt) =>
      dt == null ? '—' : Formatters.dateTimeIst(dt);

  @override
  Widget build(BuildContext context) {
    // `proofUrls` mixes real image proofs with the call section's audio
    // recording file (`callRecordingFile`, `fileType: "audio"` in
    // attempt_flow.json) — forcing the audio URL through Image.network left
    // it rendering as a blank/broken second tile, so it's split out and
    // rendered as its own tappable "Recording" tile instead.
    final urls = attempt.proofUrls.where((u) => !_isAudioUrl(u)).toList();
    final recordingUrls = attempt.proofUrls.where(_isAudioUrl).toList();
    final type = _attemptTypeLabel(attempt.attemptType);
    final outcome = _humanizeWireValue(attempt.outcome);
    final batteryRemark = _humanizeWireValue(attempt.batteryRemarkReason);
    final customerRemark = _humanizeWireValue(attempt.customerRemarkReason);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Row 1: attempt type and outcome, both bold and highlighted. Wrapped
        // rather than a Row so a long outcome drops to its own line instead of
        // squeezing the type chip.
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            if (type.isNotEmpty)
              _HighlightTag(
                label: type,
                background: palette.chipBg,
                foreground: palette.onSurface,
                fontSize: _bodySize,
              ),
            if (outcome.isNotEmpty)
              _HighlightTag(
                label: outcome,
                background: palette.primaryLight,
                foreground: palette.onSurface,
                fontSize: _bodySize,
              ),
          ],
        ),
        // Row 2: the attempt's own timestamps, plus the remark reasons when
        // the attempt carried them.
        //
        // The response's `notes` is deliberately NOT shown: it's a composed
        // string the app writes at submit time ("Battery: … | Customer: …"),
        // so it only restates the remark reasons rendered below it.
        const SizedBox(height: 10),
        _AttemptField(
          label: 'Attempted At',
          value: _stamp(attempt.attemptedAt),
          palette: palette,
          fontSize: _bodySize,
        ),
        _AttemptField(
          label: 'Completed At',
          value: _stamp(attempt.completedAt),
          palette: palette,
          fontSize: _bodySize,
        ),
        if (batteryRemark.isNotEmpty)
          _AttemptField(
            label: 'Battery Remark',
            value: batteryRemark,
            palette: palette,
            fontSize: _bodySize,
          ),
        if (customerRemark.isNotEmpty)
          _AttemptField(
            label: 'Customer Remark',
            value: customerRemark,
            palette: palette,
            fontSize: _bodySize,
          ),
        // Row 4: agent · geo. No customer-presence readout — neither the
        // outcome screen nor the visit sections capture that signal, so it
        // always reported "Customer absent" regardless of what happened.
        const SizedBox(height: 6),
        Wrap(
          spacing: 16,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (attempt.agentName.isNotEmpty)
              Text(attempt.agentName,
                  style: TextStyle(color: palette.muted, fontSize: _bodySize),),
            if (attempt.latitude != null && attempt.longitude != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.place_outlined, size: 14, color: palette.muted),
                  const SizedBox(width: 3),
                  Text(
                    '${attempt.latitude!.toStringAsFixed(4)}, '
                    '${attempt.longitude!.toStringAsFixed(4)}',
                    style:
                        TextStyle(color: palette.muted, fontSize: _bodySize),
                  ),
                ],
              ),
          ],
        ),
        // Proof photos and/or the call section's recording file.
        if (urls.isNotEmpty || recordingUrls.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < urls.length; i++)
                _ProofImage(
                  urls: urls,
                  index: i,
                  // The attempt id keeps hero tags unique when two attempts of
                  // the same ticket carry the same proof URL.
                  heroTagPrefix: attempt.id,
                  palette: palette,
                ),
              for (final url in recordingUrls)
                _RecordingTile(url: url, palette: palette),
            ],
          ),
        ],
      ],
    );
  }
}

/// Matches the call section's `callRecordingFile` proof (an audio upload,
/// `fileType: "audio"` in attempt_flow.json) by extension so it can be routed
/// to [_RecordingTile] instead of [_ProofImage] — Image.network can't decode
/// it, which is what made the second "photo" on a call attempt show blank.
bool _isAudioUrl(String url) {
  final path = Uri.tryParse(url)?.path ?? url;
  final lower = path.toLowerCase();
  const audioExtensions = ['.mp3', '.m4a', '.wav', '.aac', '.ogg'];
  return audioExtensions.any(lower.endsWith);
}

/// A tappable tile for the call section's recorded-call audio file — opened
/// in an external player/browser rather than decoded as an image.
class _RecordingTile extends StatelessWidget {
  const _RecordingTile({required this.url, required this.palette});

  final String url;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => unawaited(
        launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      ),
      child: Container(
        width: 240,
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: palette.chipBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.mic_outlined, color: palette.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Call Recording',
                style: TextStyle(color: palette.onSurface, fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.open_in_new, size: 16, color: palette.muted),
          ],
        ),
      ),
    );
  }
}

/// Backend enums arrive underscored (`field_visit`, `not_found_refused`,
/// `bp_not_with_customer`); render them as words — "Not Found Refused".
/// Returns '' for an empty value so callers can omit the row entirely.
String _humanizeWireValue(String raw) => raw
    .split(RegExp(r'[_\s]+'))
    .where((w) => w.isNotEmpty)
    .map((w) => w[0].toUpperCase() + w.substring(1))
    .join(' ');

/// The `attemptType` an attempt was recorded under, named as the ticket action
/// the agent took — the same three labels the actions hub shows. The attempt
/// controller sends one enum member per action (`_sectionAttempts`), so this is
/// that mapping read back; anything else (e.g. `recovery`, or the Update Status
/// flow's `field_visit`) falls through to the generic humanizer.
String _attemptTypeLabel(String raw) => switch (raw) {
      'call' => 'Call Customer',
      'field_visit' => 'Visit BP Location',
      'home_visit' => 'Visit Customer Address',
      _ => _humanizeWireValue(raw),
    };

/// Filled, bold pill used for the attempt's type and outcome — the two values
/// the history card leads with.
class _HighlightTag extends StatelessWidget {
  const _HighlightTag({
    required this.label,
    required this.background,
    required this.foreground,
    required this.fontSize,
  });

  final String label;
  final Color background;
  final Color foreground;
  final double fontSize;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            color: foreground,
          ),
        ),
      );
}

/// One muted-label / bold-value line inside an attempt tile (e.g.
/// "Attempted At   30 Jul 2026, 04:15 PM").
class _AttemptField extends StatelessWidget {
  const _AttemptField({
    required this.label,
    required this.value,
    required this.palette,
    required this.fontSize,
  });

  final String label;
  final String value;
  final AppPalette palette;
  final double fontSize;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: Text(
                label,
                style: TextStyle(color: palette.muted, fontSize: fontSize),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w600,
                  color: palette.onSurface,
                ),
              ),
            ),
          ],
        ),
      );
}

/// A single proof photo thumbnail with a "Photo" caption overlay, loaded from a
/// network URL with graceful loading/error placeholders.
///
/// Tapping it opens [PhotoGalleryViewer] on this photo, from where the attempt's
/// other proofs can be swiped through and each one zoomed — the same handling
/// as the device gallery.
class _ProofImage extends StatelessWidget {
  const _ProofImage({
    required this.urls,
    required this.index,
    required this.heroTagPrefix,
    required this.palette,
  });

  /// Every proof URL of the owning attempt — handed to the viewer so it can
  /// page through the whole set, not just the tapped photo.
  final List<String> urls;

  /// Position of this thumbnail within [urls].
  final int index;

  /// Namespace for the hero tag shared with the viewer.
  final String heroTagPrefix;

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    const w = 240.0;
    const h = 130.0;
    Widget placeholder(IconData icon) => Container(
          width: w,
          height: h,
          alignment: Alignment.center,
          color: palette.chipBg,
          child: Icon(icon, color: palette.muted),
        );

    return GestureDetector(
      onTap: () => unawaited(
        PhotoGalleryViewer.open(
          context,
          urls: urls,
          initialIndex: index,
          heroTagPrefix: heroTagPrefix,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            Hero(
              tag: PhotoGalleryViewer.heroTag(heroTagPrefix, index),
              child: Image.network(
                urls[index],
                width: w,
                height: h,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : placeholder(Icons.image_outlined),
                errorBuilder: (context, error, stack) =>
                    placeholder(Icons.broken_image_outlined),
              ),
            ),
            Positioned(
              left: 8,
              bottom: 8,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.image_outlined, size: 13, color: Colors.white),
                    SizedBox(width: 4),
                    Text('Photo',
                        style: TextStyle(color: Colors.white, fontSize: 11),),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.ticket,
    required this.bp,
    required this.palette,
    this.batteryDetail,
    this.detail,
    this.onReturned,
  });
  final Ticket ticket;
  final Battery bp;
  final AppPalette palette;

  /// Called when the Ticket Actions hub is popped, so the detail screen can
  /// refresh its attempt history.
  final Future<void> Function()? onReturned;

  /// Battery telemetry fetched on this screen, handed to the Ticket Actions hub
  /// so the Visit BP Location section reuses the same last lat/long + last TIU
  /// instead of re-fetching them.
  final BatteryDetail? batteryDetail;

  /// Ticket detail fetched on this screen, handed to the hub so the Visit
  /// Customer Address section shows the same parsed customer address as the
  /// customer card above instead of re-fetching it.
  final TicketDetail? detail;

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
          // Ticket Actions is the only CTA here — the battery scan is no longer
          // a standalone action off this screen; it now runs as the first half
          // of Update Status → "Scan Battery and Submit Attempt", so a scan
          // always belongs to the attempt it verifies.
          child: SizedBox(
            width: double.infinity,
            child: PillButton.dark(
              l.t('detail.ticketActions'),
              palette: palette,
              trailingArrow: true,
              onPressed: () async {
                // No attempt cap: an agent may log as many attempts as a BP
                // needs, so the hub always opens.
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => TicketActionsHub(
                          ticketId: ticket.ticketId,
                          battery: bp,
                          batteryDetail: batteryDetail,
                          ticketDetail: detail,
                        ),
                  ),
                );
                // A section save or the outcome may have added an attempt.
                unawaited(onReturned?.call());
              },
            ),
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
