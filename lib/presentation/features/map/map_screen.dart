import 'dart:async';
import 'dart:math' as math;

import 'package:asset_recovery_app/core/di/app_services.dart';
import 'package:asset_recovery_app/core/localization/app_localizations.dart';
import 'package:asset_recovery_app/core/theme/app_theme.dart';
import 'package:asset_recovery_app/core/utils/formatters.dart';
import 'package:asset_recovery_app/domain/entities/agent.dart';
import 'package:asset_recovery_app/domain/entities/battery.dart';
import 'package:asset_recovery_app/domain/entities/geo_point.dart';
import 'package:asset_recovery_app/presentation/features/ticket_detail/ticket_detail_screen.dart';
import 'package:asset_recovery_app/presentation/state/auth_provider.dart';
import 'package:asset_recovery_app/presentation/state/ticket_provider.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// M3-01 — orders [stops] into a suggested visiting route via greedy
/// nearest-neighbor chaining from [origin] (each next stop = closest
/// unvisited to the *previous* stop, not just closest to the agent's start
/// point). This stands in for a backend route-optimization endpoint
/// (RP-01) — swap this for a real server-computed plan if/when one exists;
/// callers only depend on getting an ordered list back.
List<Battery> planRoute(List<Battery> stops, GeoPoint origin) {
  final remaining = List<Battery>.of(stops);
  final ordered = <Battery>[];
  var from = origin;
  while (remaining.isNotEmpty) {
    remaining.sort((a, b) => from
        .haversineMeters(a.lastKnownLocation)
        .compareTo(from.haversineMeters(b.lastKnownLocation)),);
    final next = remaining.removeAt(0);
    ordered.add(next);
    from = next.lastKnownLocation;
  }
  return ordered;
}

/// Map view (PRD §5.2 Map View). Renders a live `google_maps_flutter` widget
/// with numbered markers for each stop and a polyline for the suggested
/// route; the route sheet + navigation entries are wired to real data.
///
/// In its default (list) mode this shows every active job's BP as a numbered
/// stop, ordered nearest-first as the suggested route, with a connecting
/// route line and a "Start Full Route" action that opens real multi-stop
/// Google Maps directions across every stop.
///
/// Pass [focusBp] (Rule 8b) to open straight onto one BP's location instead —
/// e.g. from "Visit BP Location" using its freshly-fetched live coordinates.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key, this.focusBp, this.focusLocation});

  final Battery? focusBp;
  final GeoPoint? focusLocation;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  int _selected = 0;
  bool _tracking = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.read<AppPalette>();
    final services = context.read<AppServices>();
    final tickets = context.watch<TicketProvider>();
    final agent = context.read<AuthProvider>().agent!;
    final l = AppLocalizations.of(context);
    final focusBp = widget.focusBp;

    // Flatten all active BPs and map each to its ticket id, then order them
    // into a suggested route (M3-01) via nearest-neighbor chaining from the
    // agent's current position — a real "plan", not just a radial distance
    // sort.
    final unordered = <Battery>[];
    final ticketOf = <String, String>{};
    for (final t in tickets.activeTickets) {
      for (final bp in t.batteries) {
        unordered.add(bp);
        ticketOf[bp.bpId] = t.ticketId;
      }
    }
    final open = planRoute(
      unordered,
      agent.currentLocation ?? (unordered.isEmpty ? const GeoPoint(lat: 0, lng: 0) : unordered.first.lastKnownLocation),
    );

    final maxIndex = open.isEmpty ? 0 : open.length - 1;
    final selectedIndex = math.min(math.max(_selected, 0), maxIndex);
    final selectedBp = focusBp ?? (open.isEmpty ? null : open[selectedIndex]);
    final point = widget.focusLocation ?? selectedBp?.lastKnownLocation;

    return Scaffold(
      appBar: focusBp != null ? AppBar(title: Text(AppLocalizations.of(context).t('map.title'))) : null,
      floatingActionButton: focusBp != null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _showNearbyPickups(context, services, agent),
              icon: const Icon(Icons.add_location_alt_outlined),
              label: Text(l.t('pickup.nearbyButton')),
            ),
      body: SafeArea(
        top: focusBp == null,
        child: Stack(
          children: [
            // Live map with a numbered, tappable marker per route stop (or a
            // single marker when focused on one BP's freshly-fetched location).
            Positioned.fill(
              child: _GoogleMapView(
                open: focusBp == null ? open : const [],
                selectedIndex: selectedIndex,
                onSelect: (i) => setState(() => _selected = i),
                focusPoint: focusBp != null ? point : null,
                palette: palette,
              ),
            ),
            if (focusBp == null && open.isNotEmpty)
              Positioned(
                top: 12,
                left: 16,
                right: 16,
                child: _RouteHeader(stopCount: open.length, palette: palette),
              ),
            if (focusBp == null && _tracking)
              Positioned(
                top: 68,
                left: 16,
                right: 16,
                child: _TrackingControls(
                  palette: palette,
                  onStop: () => _stopTracking(services, agent.id),
                  onEmergency: () => _reportEmergency(context, services, agent.id, l),
                ),
              ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: selectedBp == null
                  ? const SizedBox.shrink()
                  : _NearestCard(
                      bp: selectedBp,
                      point: point,
                      palette: palette,
                      showInAppLabel: focusBp != null,
                      stopNumber: focusBp != null ? null : selectedIndex + 1,
                      stopTotal: focusBp != null ? null : open.length,
                      onNavigate: focusBp != null
                          ? null
                          : () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => TicketDetailScreen(
                                    ticketId: ticketOf[selectedBp.bpId]!,
                                  ),
                                ),
                              ),
                      onStartFullRoute: focusBp != null || open.length < 2
                          ? null
                          : () => _startFullRoute(services, open, agent.currentLocation),
                    ),
            ),
            if (focusBp == null)
              Positioned(
                top: 12,
                left: 16,
                child: Text(agent.shiftArea,
                    style: TextStyle(
                        color: palette.onSurface, fontWeight: FontWeight.w600,),),
              ),
          ],
        ),
      ),
    );
  }

  /// M1-02 — location-based pickup: shows unassigned cases within
  /// `business.nearbyPickupRadiusKm` of the agent's current position so they
  /// can self-assign a case that happens to sit on today's route.
  Future<void> _showNearbyPickups(
      BuildContext context, AppServices services, Agent agent,) async {
    final tickets = context.read<TicketProvider>();
    final near = agent.currentLocation ?? const GeoPoint(lat: 0, lng: 0);
    await tickets.loadNearbyUnassigned(near);
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _NearbyPickupSheet(agentId: agent.id),
    );
  }

  /// Opens real Google Maps multi-stop directions covering every active job
  /// in the suggested (nearest-first) order — the actual "route to take".
  static Future<void> _launchFullRoute(List<Battery> stops, GeoPoint? from) async {
    final points = [
      if (from != null) from,
      ...stops.map((b) => b.lastKnownLocation),
    ];
    if (points.length < 2) return;
    final origin = points.first;
    final destination = points.last;
    final waypoints = points.sublist(1, points.length - 1);
    final buffer = StringBuffer(
      'https://www.google.com/maps/dir/?api=1'
      '&origin=${origin.lat},${origin.lng}'
      '&destination=${destination.lat},${destination.lng}'
      '&travelmode=driving',
    );
    if (waypoints.isNotEmpty) {
      buffer.write('&waypoints=${waypoints.map((p) => '${p.lat},${p.lng}').join('|')}');
    }
    await launchUrl(Uri.parse(buffer.toString()), mode: LaunchMode.externalApplication);
  }

  /// M3-02 — starts actual-route GPS capture for plan-vs-actual comparison,
  /// then launches the same external-Maps turn-by-turn directions as before.
  Future<void> _startFullRoute(
      AppServices services, List<Battery> stops, GeoPoint? from,) async {
    final routeId = 'route-${DateTime.now().millisecondsSinceEpoch}';
    await services.routeTracking.start(routeId);
    setState(() => _tracking = true);
    await _launchFullRoute(stops, from);
  }

  Future<void> _stopTracking(AppServices services, String agentId) async {
    final points = await services.routeTracking.stop();
    setState(() => _tracking = false);
    if (points.isEmpty) return;
    // Reuses the audit pipeline (queued on failure per CC-04, same as every
    // other action) rather than a bespoke endpoint — this is exactly what
    // RP-03's plan-vs-actual comparison needs: an agent, a route, a trail.
    unawaited(services.auditLog.log(
      agentId: agentId,
      action: 'route_actual_capture',
      entityType: 'route',
      metadata: {'points': points.map((p) => p.toJson()).toList()},
    ),);
  }

  /// M3-03 — logs a deviation from the planned route with a reason, so the
  /// backend's plan-vs-actual view (RP-05) can distinguish "went off script
  /// for a good reason" from an unexplained gap.
  Future<void> _reportEmergency(
      BuildContext context, AppServices services, String agentId, AppLocalizations l,) async {
    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.t('route.emergencyFlag')),
        content: TextField(
          controller: reasonController,
          autofocus: true,
          decoration: InputDecoration(hintText: l.t('route.emergencyReasonHint')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l.t('common.cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(reasonController.text.trim()),
            child: Text(l.t('common.confirm')),
          ),
        ],
      ),
    );
    if (reason == null || reason.isEmpty || !context.mounted) return;
    unawaited(services.auditLog.log(
      agentId: agentId,
      action: 'route_emergency_deviation',
      entityType: 'route',
      metadata: {'reason': reason},
    ),);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l.t('route.emergencyLogged'))));
  }
}

class _TrackingControls extends StatelessWidget {
  const _TrackingControls({
    required this.palette,
    required this.onStop,
    required this.onEmergency,
  });
  final AppPalette palette;
  final VoidCallback onStop;
  final VoidCallback onEmergency;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.fiber_manual_record, size: 12, color: palette.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(l.t('route.trackingActive'),
                style: TextStyle(color: palette.onSurface, fontSize: 12.5),),
          ),
          TextButton(onPressed: onEmergency, child: Text(l.t('route.emergencyFlag'))),
          TextButton(onPressed: onStop, child: Text(l.t('common.stop'))),
        ],
      ),
    );
  }
}

class _RouteHeader extends StatelessWidget {
  const _RouteHeader({required this.stopCount, required this.palette});
  final int stopCount;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.alt_route, size: 18, color: palette.primaryDark),
          const SizedBox(width: 8),
          Text(l.t('map.todaysRoute'),
              style: TextStyle(fontWeight: FontWeight.w700, color: palette.onSurface),),
          const SizedBox(width: 6),
          Text('· ${l.t('map.stops', {'count': stopCount})}',
              style: TextStyle(color: palette.muted),),
        ],
      ),
    );
  }
}

/// Live Google Map showing either the full suggested route (numbered,
/// tappable markers + connecting polyline) or a single focused BP marker
/// (Rule 8b — freshly-fetched live location).
class _GoogleMapView extends StatefulWidget {
  const _GoogleMapView({
    required this.open,
    required this.selectedIndex,
    required this.onSelect,
    required this.focusPoint,
    required this.palette,
  });

  final List<Battery> open;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final GeoPoint? focusPoint;
  final AppPalette palette;

  @override
  State<_GoogleMapView> createState() => _GoogleMapViewState();
}

class _GoogleMapViewState extends State<_GoogleMapView> {
  GoogleMapController? _controller;

  static LatLng _toLatLng(GeoPoint p) => LatLng(p.lat, p.lng);

  @override
  void didUpdateWidget(_GoogleMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex && widget.open.isNotEmpty) {
      final i = widget.selectedIndex.clamp(0, widget.open.length - 1);
      _controller?.animateCamera(
        CameraUpdate.newLatLng(_toLatLng(widget.open[i].lastKnownLocation)),
      );
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focus = widget.focusPoint;
    final markers = <Marker>{
      if (focus != null)
        Marker(markerId: const MarkerId('focus'), position: _toLatLng(focus)),
      for (var i = 0; i < widget.open.length; i++)
        Marker(
          markerId: MarkerId(widget.open[i].bpId),
          position: _toLatLng(widget.open[i].lastKnownLocation),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            i == widget.selectedIndex ? BitmapDescriptor.hueRed : BitmapDescriptor.hueAzure,
          ),
          infoWindow: InfoWindow(title: '${i + 1}. ${widget.open[i].bpId}'),
          onTap: () => widget.onSelect(i),
        ),
    };

    final polylines = <Polyline>{
      if (widget.open.length > 1)
        Polyline(
          polylineId: const PolylineId('suggested_route'),
          points: [for (final bp in widget.open) _toLatLng(bp.lastKnownLocation)],
          color: widget.palette.primaryDark,
          width: 3,
          patterns: [PatternItem.dash(20), PatternItem.gap(10)],
        ),
    };

    final initialTarget = focus ??
        (widget.open.isEmpty
            ? const GeoPoint(lat: 12.9716, lng: 77.5946) // Bengaluru fallback.
            : widget.open.first.lastKnownLocation);

    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: _toLatLng(initialTarget),
        zoom: focus != null ? 15 : 12,
      ),
      markers: markers,
      polylines: polylines,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      onMapCreated: (controller) => _controller = controller,
    );
  }
}

class _NearestCard extends StatelessWidget {
  const _NearestCard({
    required this.bp,
    required this.palette,
    this.point,
    this.showInAppLabel = false,
    this.onNavigate,
    this.stopNumber,
    this.stopTotal,
    this.onStartFullRoute,
  });
  final Battery bp;
  final GeoPoint? point;
  final AppPalette palette;
  final bool showInAppLabel;
  final VoidCallback? onNavigate;

  /// This stop's 1-based position in today's suggested route, and the total
  /// stop count — null when showing a single-BP focus (Rule 8b), not a list.
  final int? stopNumber;
  final int? stopTotal;
  final VoidCallback? onStartFullRoute;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final eta = bp.distanceKm == null ? null : Formatters.etaMinutes(bp.distanceKm!);
    final loc = point ?? bp.lastKnownLocation;
    final label = showInAppLabel
        ? l.t('map.liveLocation')
        : (stopNumber != null && stopTotal != null)
            ? l.t('map.stopOf', {'current': stopNumber!, 'total': stopTotal!})
            : l.t('map.nearestCase');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 12),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: TextStyle(
                  fontSize: 11, color: palette.muted, letterSpacing: 0.5,),),
          const SizedBox(height: 4),
          Text('${bp.bpId} · ${bp.customer.name}',
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold,),),
          const SizedBox(height: 2),
          Text(
            '${Formatters.distanceKm(bp.distanceKm)}'
            '${eta != null ? ' · ${l.t('map.eta', {'minutes': eta})}' : ''}',
            style: TextStyle(color: palette.muted),
          ),
          const SizedBox(height: 12),
          if (onNavigate != null)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onNavigate,
                icon: const Icon(Icons.navigation, size: 16),
                label: Text(l.t('map.startNavigation')),
              ),
            ),
          if (onStartFullRoute != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onStartFullRoute,
                icon: const Icon(Icons.alt_route, size: 16),
                label: Text(l.t('map.startFullRoute')),
              ),
            ),
          ],
          if (showInAppLabel)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse(
                    'https://www.google.com/maps/dir/?api=1&destination=${loc.lat},${loc.lng}',
                  ),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: Text(l.t('map.openExternalMaps')),
              ),
            ),
        ],
      ),
    );
  }
}

/// M1-02 — location-based pickup sheet: unassigned cases near the agent's
/// current position, each self-assignable in one tap.
class _NearbyPickupSheet extends StatefulWidget {
  const _NearbyPickupSheet({required this.agentId});
  final String agentId;

  @override
  State<_NearbyPickupSheet> createState() => _NearbyPickupSheetState();
}

class _NearbyPickupSheetState extends State<_NearbyPickupSheet> {
  String? _pickingUpId;

  Future<void> _pickup(TicketProvider tickets, String ticketId) async {
    setState(() => _pickingUpId = ticketId);
    final ok = await tickets.pickup(ticketId, widget.agentId);
    if (!mounted) return;
    setState(() => _pickingUpId = null);
    final l = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? l.t('pickup.success') : l.t('pickup.failed')),
    ),);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = context.read<AppPalette>();
    final tickets = context.watch<TicketProvider>();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.t('pickup.title'),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),),
            const SizedBox(height: 4),
            Text(l.t('pickup.subtitle'),
                style: TextStyle(color: palette.muted, fontSize: 12.5),),
            const SizedBox(height: 14),
            if (tickets.loadingNearby)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (tickets.nearbyUnassigned.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(l.t('pickup.empty'),
                    style: TextStyle(color: palette.muted),),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: tickets.nearbyUnassigned.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final t = tickets.nearbyUnassigned[i];
                    final bp = t.primaryBp;
                    final busy = _pickingUpId == t.ticketId;
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: palette.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: palette.border),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${bp.bpId} · ${bp.customer.name}',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),),
                                const SizedBox(height: 2),
                                Text(
                                  '${bp.caseType} · ${Formatters.distanceKm(bp.distanceKm)}',
                                  style: TextStyle(color: palette.muted, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            height: 34,
                            child: ElevatedButton(
                              onPressed: busy ? null : () => _pickup(tickets, t.ticketId),
                              child: busy
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(strokeWidth: 2),)
                                  : Text(l.t('pickup.action')),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
