import 'dart:async';
import 'dart:math' as math;

import 'package:asset_recovery_app/core/di/app_services.dart';
import 'package:asset_recovery_app/core/di/injector.dart';
import 'package:asset_recovery_app/core/error/result.dart';
import 'package:asset_recovery_app/core/localization/app_localizations.dart';
import 'package:asset_recovery_app/core/services/directions_service.dart';
import 'package:asset_recovery_app/core/services/location_service.dart';
import 'package:asset_recovery_app/core/theme/app_theme.dart';
import 'package:asset_recovery_app/core/utils/formatters.dart';
import 'package:asset_recovery_app/domain/entities/battery.dart';
import 'package:asset_recovery_app/domain/entities/geo_point.dart';
import 'package:asset_recovery_app/domain/usecases/get_battery_detail_usecase.dart';
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
/// In its default (list) mode this plots every **in-progress** ticket from the
/// home list as a numbered stop, ordered nearest-first as the suggested route,
/// with a connecting route line. The floating panel over the map lists all of
/// those stops — scrollable, one row each — and expanding a row (the `>`)
/// reveals that BP's id + customer name with its two actions: Start navigation
/// and View details. "Start navigation" draws the drivable route to that BP on
/// this same map (see [_ActiveNavigation]) rather than handing the agent off to
/// the external Maps app — that hand-off stays available as a button on the
/// navigation card.
///
/// Pass [focusBp] (Rule 8b) to open straight onto one BP's location instead —
/// e.g. from "Visit BP Location", or from the BP detail header's map icon,
/// using the coordinates the Battery Master lookup on that screen already
/// returned ([focusLocation]). That single-BP view gets the same in-app
/// navigation as a stop in the list: "Start navigation" draws the drivable
/// route to it on this map, with the Maps-app hand-off as the secondary way out.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key, this.focusBp, this.focusLocation});

  final Battery? focusBp;
  final GeoPoint? focusLocation;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  /// Index of the expanded stop in the panel (and the highlighted marker), or
  /// -1 when every row is collapsed — the state the screen opens in.
  int _selected = -1;
  bool _tracking = false;

  /// Where each BP actually is per the Battery Master API, keyed by bpId and
  /// filled when its row is expanded — see [_loadLiveLocation]. A key present
  /// with a null value means the call came back with no usable coordinates.
  final Map<String, GeoPoint?> _liveLocations = {};

  /// bpIds whose `battery.getBatteryDetails` call is still in flight.
  final Set<String> _loadingLocations = {};

  /// The bpId whose "Start navigation" is still resolving (device fix +
  /// Directions lookup), or null when none is — drives that button's spinner.
  String? _navigatingBpId;

  /// The navigation leg currently drawn on the map, or null when the screen is
  /// in its normal stop-list mode. Set by [_startNavigation].
  _ActiveNavigation? _navigation;

  /// Where the device says the agent is, read once when the screen opens — the
  /// map's home camera position and the origin the suggested route is planned
  /// from. Null until the fix lands, and stays null when there is none, which is
  /// the only case that falls back to [kBengaluruCenter].
  GeoPoint? _deviceLocation;

  @override
  void initState() {
    super.initState();
    unawaited(_loadDeviceLocation());
  }

  /// Asks the device where the agent is so the map opens on them rather than on
  /// the city-centre fallback. Never blocks the screen: the map builds on
  /// whatever it has and re-centres when (or if) the fix arrives.
  Future<void> _loadDeviceLocation() async {
    final fix = await context.read<AppServices>().location.currentLocation();
    if (!mounted || !fix.hasFix) return;
    setState(() => _deviceLocation = fix);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.read<AppPalette>();
    final services = context.read<AppServices>();
    final tickets = context.watch<TicketProvider>();
    final agent = context.read<AuthProvider>().agent!;
    final l = AppLocalizations.of(context);
    final focusBp = widget.focusBp;

    // Flatten the BPs of every in-progress ticket and map each to its ticket
    // id, then order them into a suggested route (M3-01) via nearest-neighbor
    // chaining from the agent's current position — a real "plan", not just a
    // radial distance sort.
    final unordered = <Battery>[];
    final ticketOf = <String, String>{};
    for (final t in tickets.inProgressTickets) {
      for (final bp in t.batteries) {
        unordered.add(bp);
        ticketOf[bp.bpId] = t.ticketId;
      }
    }
    // The device fix is the truest "where the agent is now"; the position the
    // session last reported stands in until it lands.
    final here = _deviceLocation ?? agent.currentLocation;
    final open = planRoute(
      unordered,
      here ??
          (unordered.isEmpty ? kBengaluruCenter : unordered.first.lastKnownLocation),
    );

    // -1 (nothing expanded) travels through as-is; the map just highlights no
    // marker. Clamped so a shrinking list can't leave a stale index dangling.
    final selectedIndex = _selected >= open.length ? -1 : _selected;
    final point = widget.focusLocation ?? focusBp?.lastKnownLocation;

    // Navigation mode replaces the stop list (or the focused-BP card) and the
    // route header with the single leg being driven.
    final nav = _navigation;

    return Scaffold(
      appBar: focusBp != null ? AppBar(title: Text(AppLocalizations.of(context).t('map.title'))) : null,
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
                userLocation: here != null && here.hasFix ? here : null,
                palette: palette,
                navigation: nav,
              ),
            ),
            if (focusBp == null && nav == null && open.isNotEmpty)
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
              child: nav != null
                  ? _NavigationCard(
                      navigation: nav,
                      palette: palette,
                      onOpenExternal: () =>
                          _openExternalDirections(nav.destination, nav.origin),
                      onEnd: () => setState(() => _navigation = null),
                    )
                  : focusBp != null
                  ? _FocusedBpCard(
                      bp: focusBp,
                      point: point,
                      palette: palette,
                      navigating: _navigatingBpId == focusBp.bpId,
                      // The screen was opened with this BP's coordinates
                      // already resolved, so route straight to them instead of
                      // repeating the Battery Master lookup.
                      onNavigate: () => _startNavigation(
                        services,
                        focusBp,
                        agent.currentLocation,
                        destination: point,
                      ),
                    )
                  : _StopsPanel(
                      stops: open,
                      palette: palette,
                      selectedIndex: selectedIndex,
                      liveLocations: _liveLocations,
                      loadingLocations: _loadingLocations,
                      navigatingBpId: _navigatingBpId,
                      onToggle: (i) => _toggleStop(i, open[i]),
                      onNavigate: (bp) =>
                          _startNavigation(services, bp, agent.currentLocation),
                      onViewDetails: (bp) => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              TicketDetailScreen(ticketId: ticketOf[bp.bpId]!),
                        ),
                      ),
                    ),
            ),
            if (focusBp == null && nav == null)
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

  /// Expands stop [i] (or collapses it when it is already open) and, on the way
  /// open, asks the Battery Master API where that BP actually is.
  void _toggleStop(int i, Battery bp) {
    final expanding = _selected != i;
    setState(() => _selected = expanding ? i : -1);
    if (expanding) unawaited(_loadLiveLocation(bp.bpId));
  }

  /// Fetches the BP's live coordinates from `battery.getBatteryDetails`
  /// (`GET .../WheelerBattery/SearchBattery/{bpId}`) so "Start navigation" can
  /// route to where the pack is now instead of the position the ticket list was
  /// loaded with.
  ///
  /// Cached per bpId for the life of the screen — re-expanding a row doesn't
  /// re-fetch. A rejected call, or a telemetry row without coordinates, caches
  /// null and navigation falls back to the ticket's last known location.
  Future<void> _loadLiveLocation(String bpId) async {
    if (bpId.isEmpty ||
        _liveLocations.containsKey(bpId) ||
        _loadingLocations.contains(bpId)) {
      return;
    }
    setState(() => _loadingLocations.add(bpId));
    final result = await sl<GetBatteryDetailUseCase>()(bpId);
    if (!mounted) return;
    setState(() {
      _loadingLocations.remove(bpId);
      _liveLocations[bpId] = result.valueOrNull?.location;
    });
  }

  /// "Start navigation" on an expanded stop (or on the focused-BP card): draws
  /// the drivable route from the agent's current position to the BP's live
  /// coordinates (falling back to its last known location when the Battery
  /// Master API had none) on this screen's own map — no hand-off to the external
  /// Maps app.
  ///
  /// [destination] overrides where to route to — passed by the focused-BP view,
  /// which was handed coordinates its caller had already fetched.
  ///
  /// The origin is a fresh device fix, falling back to the position the session
  /// last reported. With neither there is nothing to route *from*, so this
  /// hands off to the Maps app after all — that app can start from the device's
  /// own idea of where it is, which we do not have.
  ///
  /// A device fix plus a Directions round-trip takes long enough to look
  /// unresponsive, so [_navigatingBpId] spins the button until the route lands.
  Future<void> _startNavigation(
    AppServices services,
    Battery bp,
    GeoPoint? sessionLocation, {
    GeoPoint? destination,
  }) async {
    if (_navigatingBpId != null) return;
    setState(() => _navigatingBpId = bp.bpId);
    try {
      final to =
          destination ?? _liveLocations[bp.bpId] ?? bp.lastKnownLocation;
      final fix = await services.location.currentLocation();
      final from = fix.hasFix ? fix : sessionLocation;
      if (from == null || !from.hasFix) {
        await _openExternalDirections(to, null);
        return;
      }
      // A null route means the Directions web service could not be reached or
      // the key isn't authorised for it (see DirectionsService) — draw the
      // direct line instead of leaving "Start navigation" doing nothing. The
      // card labels that case so the agent knows it isn't a driving route.
      final route = await services.directions.fetch(origin: from, destination: to) ??
          DirectionsRoute.straightLine(from, to);
      if (!mounted) return;
      setState(() {
        _navigation = _ActiveNavigation(bp: bp, origin: from, destination: to, route: route);
        // The stop list is replaced by the navigation card, so an expanded row
        // underneath it would come back expanded on exit.
        _selected = -1;
      });
    } finally {
      if (mounted) setState(() => _navigatingBpId = null);
    }
  }

  /// Hands the leg to the device's Maps app — the escape hatch from the in-app
  /// route, and the only option when we have no origin to route from.
  static Future<void> _openExternalDirections(GeoPoint to, GeoPoint? from) {
    final origin = from != null && from.hasFix ? '&origin=${from.lat},${from.lng}' : '';
    return launchUrl(
      Uri.parse(
        'https://www.google.com/maps/dir/?api=1'
        '$origin&destination=${to.lat},${to.lng}&travelmode=driving',
      ),
      mode: LaunchMode.externalApplication,
    );
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

/// One in-app navigation leg: the agent's position when navigation started, the
/// BP being driven to, and the route between them. Held by [_MapScreenState]
/// while the map is in navigation mode.
class _ActiveNavigation {
  const _ActiveNavigation({
    required this.bp,
    required this.origin,
    required this.destination,
    required this.route,
  });

  final Battery bp;
  final GeoPoint origin;

  /// Where the BP actually is — its live coordinates when the Battery Master
  /// API had them, else its last known position.
  final GeoPoint destination;
  final DirectionsRoute route;
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
/// tappable markers + connecting polyline), an active navigation leg
/// ([_ActiveNavigation] — the drivable route to one BP), or a single focused BP
/// marker (Rule 8b — freshly-fetched live location).
class _GoogleMapView extends StatefulWidget {
  const _GoogleMapView({
    required this.open,
    required this.selectedIndex,
    required this.onSelect,
    required this.focusPoint,
    required this.palette,
    this.userLocation,
    this.navigation,
  });

  final List<Battery> open;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final GeoPoint? focusPoint;

  /// Where the agent is (device fix, else the session's last reported position),
  /// or null while there is neither — the overview map's home camera position.
  final GeoPoint? userLocation;
  final AppPalette palette;

  /// When set, the map draws this leg instead of the suggested-route overview
  /// and frames it — see [_MapScreenState._startNavigation].
  final _ActiveNavigation? navigation;

  @override
  State<_GoogleMapView> createState() => _GoogleMapViewState();
}

class _GoogleMapViewState extends State<_GoogleMapView> {
  GoogleMapController? _controller;

  static LatLng _toLatLng(GeoPoint p) => LatLng(p.lat, p.lng);

  /// The box containing every point, for framing a route. Google rejects
  /// bounds whose corners are equal, so a degenerate box (one point, or a
  /// perfectly straight N-S/E-W pair) is nudged open by [_kBoundsEpsilon].
  static LatLngBounds _boundsOf(List<GeoPoint> points) {
    var minLat = points.first.lat, maxLat = points.first.lat;
    var minLng = points.first.lng, maxLng = points.first.lng;
    for (final p in points) {
      minLat = math.min(minLat, p.lat);
      maxLat = math.max(maxLat, p.lat);
      minLng = math.min(minLng, p.lng);
      maxLng = math.max(maxLng, p.lng);
    }
    if (maxLat - minLat < _kBoundsEpsilon) {
      minLat -= _kBoundsEpsilon;
      maxLat += _kBoundsEpsilon;
    }
    if (maxLng - minLng < _kBoundsEpsilon) {
      minLng -= _kBoundsEpsilon;
      maxLng += _kBoundsEpsilon;
    }
    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  @override
  void didUpdateWidget(_GoogleMapView oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Entering navigation (or switching destination): frame the whole leg so
    // the agent sees both ends of it at once.
    final nav = widget.navigation;
    if (nav != null && !identical(oldWidget.navigation, nav)) {
      _controller?.animateCamera(
        CameraUpdate.newLatLngBounds(_boundsOf(nav.route.points), 64),
      );
      return;
    }

    // The device fix usually lands after the map is already built, so the
    // initial camera position missed it — centre on the agent once it arrives.
    // Only on the way from "no position" to a real one: a later fix must not
    // yank the camera back while the agent is panning around.
    final me = widget.userLocation;
    if (me != null &&
        oldWidget.userLocation == null &&
        widget.focusPoint == null &&
        widget.navigation == null) {
      _controller?.animateCamera(
        CameraUpdate.newLatLngZoom(_toLatLng(me), _kUserLocationZoom),
      );
      return;
    }

    // -1 means the panel collapsed every row; leave the camera where it is
    // rather than snapping back to the first stop.
    final i = widget.selectedIndex;
    if (oldWidget.selectedIndex != i && i >= 0 && i < widget.open.length) {
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
    final nav = widget.navigation;

    // Navigation mode owns the map: just the leg's two ends and the road route
    // between them, with the other stops' pins out of the way.
    if (nav != null) {
      return GoogleMap(
        initialCameraPosition: CameraPosition(
          target: _toLatLng(nav.origin),
          zoom: 14,
        ),
        markers: {
          Marker(
            markerId: const MarkerId('nav_origin'),
            position: _toLatLng(nav.origin),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
            infoWindow: InfoWindow(
              title: AppLocalizations.of(context).t('map.yourLocation'),
            ),
          ),
          Marker(
            markerId: MarkerId('nav_${nav.bp.bpId}'),
            position: _toLatLng(nav.destination),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            infoWindow: InfoWindow(title: nav.bp.bpId),
          ),
        },
        polylines: {
          Polyline(
            polylineId: const PolylineId('nav_route'),
            points: [for (final p in nav.route.points) _toLatLng(p)],
            color: widget.palette.primaryDark,
            width: 6,
            // A straight-line fallback is not a road route — dash it so it
            // never reads as one (see DirectionsRoute.straightLine).
            patterns: nav.route.isRoadRoute
                ? const []
                : [PatternItem.dash(20), PatternItem.gap(10)],
          ),
        },
        myLocationEnabled: true,
        myLocationButtonEnabled: false,
        zoomControlsEnabled: false,
        onMapCreated: (controller) {
          _controller = controller;
          // The map may be built already-in-navigation (a rebuild from
          // elsewhere), in which case didUpdateWidget never fires — frame the
          // leg once the controller exists.
          controller.animateCamera(
            CameraUpdate.newLatLngBounds(_boundsOf(nav.route.points), 64),
          );
        },
      );
    }

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

    // The map opens on the agent, not on the city — the stops are planned
    // nearest-first from there anyway, so the first one is right next to them.
    // kBengaluruCenter is the last resort: no fix, no session position, no stops.
    final me = widget.userLocation;
    final initialTarget = focus ??
        me ??
        (widget.open.isEmpty
            ? kBengaluruCenter
            : widget.open.first.lastKnownLocation);

    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: _toLatLng(initialTarget),
        zoom: focus != null
            ? 15
            : me != null
                ? _kUserLocationZoom
                : 12,
      ),
      markers: markers,
      polylines: polylines,
      // The blue dot: with the camera on the agent, they should be able to see
      // themselves on it.
      myLocationEnabled: true,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      onMapCreated: (controller) => _controller = controller,
    );
  }
}

/// Height of a collapsed stop row and the gap between rows. Fixed so
/// [_StopsPanelState] can scroll a row into view by arithmetic: every row above
/// the expanded one is collapsed, which makes the offset exact.
const double _kStopRowHeight = 56;
const double _kStopRowGap = 8;

/// Padding added to a degenerate route box so `newLatLngBounds` always gets a
/// non-empty rectangle. 0.001° is roughly 110 m — a sane zoom for a leg that
/// starts and ends in the same place.
const double _kBoundsEpsilon = 0.001;

/// Zoom used when the map is centred on the agent's own position — close enough
/// to place them on a street, wide enough to show the stops around them.
const double _kUserLocationZoom = 14;

/// The panel shown while the map is in navigation mode: which BP is being
/// driven to, how far and how long the route is, and the two ways out — hand
/// the leg to the device's Maps app, or drop back to the stop list.
class _NavigationCard extends StatelessWidget {
  const _NavigationCard({
    required this.navigation,
    required this.palette,
    required this.onOpenExternal,
    required this.onEnd,
  });

  final _ActiveNavigation navigation;
  final AppPalette palette;
  final VoidCallback onOpenExternal;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final route = navigation.route;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 14),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 12),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.navigation, size: 16, color: palette.primaryDark),
              const SizedBox(width: 6),
              Expanded(
                child: Text(l.t('map.navigatingTo').toUpperCase(),
                    style: TextStyle(
                        fontSize: 11, color: palette.muted, letterSpacing: 0.5,),),
              ),
              IconButton(
                onPressed: onEnd,
                icon: const Icon(Icons.close, size: 20),
                tooltip: l.t('map.endNavigation'),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          Text('${navigation.bp.bpId} · ${navigation.bp.customer.name}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),),
          const SizedBox(height: 2),
          Text(
            '${Formatters.distanceKm(route.distanceKm)} · '
            '${l.t('map.eta', {'minutes': route.durationMinutes})}',
            style: TextStyle(color: palette.muted),
          ),
          if (!route.isRoadRoute) ...[
            const SizedBox(height: 6),
            Text(l.t('map.approximateRoute'),
                style: TextStyle(fontSize: 12, color: palette.danger),),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onOpenExternal,
              icon: const Icon(Icons.open_in_new, size: 16),
              label: Text(l.t('map.openExternalMaps')),
            ),
          ),
        ],
      ),
    );
  }
}

/// The card shown when the map is focused on a single BP (Rule 8b) — its
/// freshly-fetched live location, with the same two actions a stop in the list
/// gets: draw the drivable route to it on this map, or hand the leg to the
/// device's Maps app.
class _FocusedBpCard extends StatelessWidget {
  const _FocusedBpCard({
    required this.bp,
    required this.palette,
    required this.navigating,
    required this.onNavigate,
    this.point,
  });
  final Battery bp;
  final GeoPoint? point;
  final AppPalette palette;

  /// True while this BP's route is being resolved (device fix + Directions
  /// lookup) — spins the button so the tap isn't repeated.
  final bool navigating;
  final VoidCallback onNavigate;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final eta = bp.distanceKm == null ? null : Formatters.etaMinutes(bp.distanceKm!);
    final loc = point ?? bp.lastKnownLocation;
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
          Text(l.t('map.liveLocation').toUpperCase(),
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
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: navigating ? null : onNavigate,
              icon: navigating
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      // Explicit colour: the button is disabled while it spins,
                      // and the theme's accent would wash out against the
                      // disabled fill.
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: palette.onSurface,),
                    )
                  : const Icon(Icons.navigation, size: 16),
              label: Text(navigating
                  ? l.t('map.openingNavigation')
                  : l.t('map.startNavigation'),),
            ),
          ),
          const SizedBox(height: 8),
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

/// The panel floating over the map: every in-progress stop, scrollable, one
/// row each. Expanding a row (its `>`) reveals that BP's id + customer name
/// with Start navigation / View details, and highlights its marker.
class _StopsPanel extends StatefulWidget {
  const _StopsPanel({
    required this.stops,
    required this.palette,
    required this.selectedIndex,
    required this.liveLocations,
    required this.loadingLocations,
    required this.navigatingBpId,
    required this.onToggle,
    required this.onNavigate,
    required this.onViewDetails,
  });

  final List<Battery> stops;
  final AppPalette palette;

  /// Index of the expanded row, or -1 when they are all collapsed.
  final int selectedIndex;

  /// Live BP coordinates by bpId, and the bpIds still being fetched — see
  /// [_MapScreenState._loadLiveLocation].
  final Map<String, GeoPoint?> liveLocations;
  final Set<String> loadingLocations;

  /// bpId whose navigation hand-off is in flight, or null — see
  /// [_MapScreenState._startNavigation].
  final String? navigatingBpId;
  final ValueChanged<int> onToggle;
  final ValueChanged<Battery> onNavigate;
  final ValueChanged<Battery> onViewDetails;

  @override
  State<_StopsPanel> createState() => _StopsPanelState();
}

class _StopsPanelState extends State<_StopsPanel> {
  final ScrollController _scroll = ScrollController();

  @override
  void didUpdateWidget(_StopsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A marker tap expands a row that may be scrolled out of sight — bring it
    // up. Deferred a frame so the list has already grown by the expansion.
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
    }
  }

  void _scrollToSelected() {
    final i = widget.selectedIndex;
    if (i < 0 || !_scroll.hasClients) return;
    _scroll.animateTo(
      math.min(i * (_kStopRowHeight + _kStopRowGap), _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = widget.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 12),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(l.t('map.inProgressStops').toUpperCase(),
                  style: TextStyle(
                      fontSize: 11, color: palette.muted, letterSpacing: 0.5,),),
              const Spacer(),
              if (widget.stops.isNotEmpty)
                Text(l.t('map.stops', {'count': widget.stops.length}),
                    style: TextStyle(fontSize: 11, color: palette.muted),),
            ],
          ),
          const SizedBox(height: 10),
          if (widget.stops.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(l.t('map.noStops'),
                  style: TextStyle(color: palette.muted),),
            )
          else
            ConstrainedBox(
              // Never let the list swallow the map — it stays a panel over it.
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.42,
              ),
              child: ListView.separated(
                controller: _scroll,
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: widget.stops.length,
                separatorBuilder: (_, __) => const SizedBox(height: _kStopRowGap),
                itemBuilder: (context, i) => _StopRow(
                  stopNumber: i + 1,
                  bp: widget.stops[i],
                  palette: palette,
                  expanded: i == widget.selectedIndex,
                  loadingLiveLocation:
                      widget.loadingLocations.contains(widget.stops[i].bpId),
                  liveLocation: widget.liveLocations[widget.stops[i].bpId],
                  navigating: widget.navigatingBpId == widget.stops[i].bpId,
                  onToggle: () => widget.onToggle(i),
                  onNavigate: () => widget.onNavigate(widget.stops[i]),
                  onViewDetails: () => widget.onViewDetails(widget.stops[i]),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One stop in [_StopsPanel]: collapsed it is the BP id + distance behind a
/// `>`; expanded it opens into the BP id · customer name with the stop's two
/// actions.
class _StopRow extends StatelessWidget {
  const _StopRow({
    required this.stopNumber,
    required this.bp,
    required this.palette,
    required this.expanded,
    required this.loadingLiveLocation,
    required this.liveLocation,
    required this.navigating,
    required this.onToggle,
    required this.onNavigate,
    required this.onViewDetails,
  });

  final int stopNumber;
  final Battery bp;
  final AppPalette palette;
  final bool expanded;

  /// True while `battery.getBatteryDetails` is in flight for this BP.
  final bool loadingLiveLocation;

  /// Where the Battery Master API says this BP is — null until the call lands,
  /// and still null when it answered without usable coordinates.
  final GeoPoint? liveLocation;

  /// True while this stop's navigation hand-off to the Maps app is in flight.
  final bool navigating;
  final VoidCallback onToggle;
  final VoidCallback onNavigate;
  final VoidCallback onViewDetails;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final eta = bp.distanceKm == null ? null : Formatters.etaMinutes(bp.distanceKm!);
    final distance = '${Formatters.distanceKm(bp.distanceKm)}'
        '${eta != null ? ' · ${l.t('map.eta', {'minutes': eta})}' : ''}';

    return Container(
      decoration: BoxDecoration(
        color: expanded ? palette.primaryLight : palette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: expanded ? palette.primaryDark : palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: _kStopRowHeight,
              child: Row(
                children: [
                  const SizedBox(width: 10),
                  _StopBadge(number: stopNumber, palette: palette),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(bp.bpId,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 13.5,),),
                        const SizedBox(height: 2),
                        Text(distance,
                            style: TextStyle(color: palette.muted, fontSize: 11.5),),
                      ],
                    ),
                  ),
                  Icon(expanded ? Icons.expand_more : Icons.chevron_right,
                      color: expanded ? palette.primaryDark : palette.muted,),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${bp.bpId} · ${bp.customer.name}',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold,),),
                  const SizedBox(height: 6),
                  _LiveLocationStatus(
                    loading: loadingLiveLocation,
                    location: liveLocation,
                    palette: palette,
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      // Held until the live coordinates land, so navigation
                      // never starts toward the stale position, and again while
                      // the Maps hand-off runs so the tap isn't repeated.
                      onPressed:
                          loadingLiveLocation || navigating ? null : onNavigate,
                      icon: navigating
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              // Explicit colour: the button is disabled while
                              // it spins, and the theme's accent would wash out
                              // against the disabled fill.
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: palette.onSurface,),
                            )
                          : const Icon(Icons.navigation, size: 16),
                      label: Text(navigating
                          ? l.t('map.openingNavigation')
                          : l.t('map.startNavigation'),),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: onViewDetails,
                      icon: const Icon(Icons.info_outline, size: 16),
                      label: Text(l.t('map.viewDetails')),
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

/// What the expanded stop knows about where its BP actually is: the Battery
/// Master lookup in flight, the live coordinates it returned, or a note that
/// navigation will use the ticket's last known location instead.
class _LiveLocationStatus extends StatelessWidget {
  const _LiveLocationStatus({
    required this.loading,
    required this.location,
    required this.palette,
  });

  final bool loading;
  final GeoPoint? location;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final style = TextStyle(color: palette.muted, fontSize: 11.5);
    if (loading) {
      return Row(
        children: [
          SizedBox(
            width: 11,
            height: 11,
            child: CircularProgressIndicator(strokeWidth: 1.8, color: palette.muted),
          ),
          const SizedBox(width: 8),
          Text(l.t('map.fetchingLiveLocation'), style: style),
        ],
      );
    }
    final loc = location;
    return Text(
      loc == null
          ? l.t('map.liveLocationUnavailable')
          : l.t('map.liveLocationAt', {
              'coords': '${loc.lat.toStringAsFixed(5)}, '
                  '${loc.lng.toStringAsFixed(5)}',
            }),
      style: style,
    );
  }
}

/// The stop's 1-based position in the suggested route — the same number its
/// map marker carries.
class _StopBadge extends StatelessWidget {
  const _StopBadge({required this.number, required this.palette});
  final int number;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) => Container(
        width: 24,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: palette.primary,
          shape: BoxShape.circle,
        ),
        child: Text('$number',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: palette.onPrimary,
            ),),
      );
}
