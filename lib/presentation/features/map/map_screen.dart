import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:asset_recovery_app/core/di/app_services.dart';
import 'package:asset_recovery_app/core/di/injector.dart';
import 'package:asset_recovery_app/core/error/result.dart';
import 'package:asset_recovery_app/core/localization/app_localizations.dart';
import 'package:asset_recovery_app/core/services/directions_service.dart';
import 'package:asset_recovery_app/core/services/location_service.dart';
import 'package:asset_recovery_app/core/theme/app_theme.dart';
import 'package:asset_recovery_app/core/utils/formatters.dart';
import 'package:asset_recovery_app/domain/entities/agent_route.dart';
import 'package:asset_recovery_app/domain/entities/battery.dart';
import 'package:asset_recovery_app/domain/entities/geo_point.dart';
import 'package:asset_recovery_app/domain/usecases/get_agent_route_usecase.dart';
import 'package:asset_recovery_app/presentation/features/ticket_detail/ticket_detail_screen.dart';
import 'package:asset_recovery_app/presentation/state/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// Map view (PRD §5.2 Map View).
///
/// In its default (route) mode the screen owns no planning logic of its own: it
/// calls `agent.route` (`GET /agents/{agentId}/route`) each time the agent opens
/// the Map tab and renders exactly what came back — a marker per stop in the
/// backend's `sequence` order, and one continuous drive that starts at the
/// agent's current position, runs to stop 1, then stop 1 → stop 2 → … through
/// the last stop. The route shape comes from Google Directions (origin =
/// the agent, waypoints = every stop but the last, in sequence); when that
/// service can't be reached the same chain is drawn as dashed straight lines so
/// the ordering is still readable.
///
/// The fetch is driven by [reloadSignal] rather than `initState`: the Map tab
/// lives in [HomeShell]'s `IndexedStack`, which builds every tab once at launch
/// and never disposes them, so a load in `initState` would fire on app start and
/// never again. HomeShell ticks the signal on each tap of the map icon, which is
/// exactly when the route should be re-read. A [MapScreen] built without a
/// signal (a direct push) loads once on open.
///
/// Pass [focusBp] (Rule 8b) to open straight onto one BP's location instead —
/// e.g. from "Visit BP Location", or from the BP detail header's map icon, using
/// the coordinates the Battery Master lookup on that screen already returned
/// ([focusLocation]). That single-BP view does not touch `agent.route`: "Start
/// navigation" draws the drivable route to that one BP on this map, with the
/// Maps-app hand-off as the secondary way out.
class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    this.focusBp,
    this.focusLocation,
    this.reloadSignal,
  });

  final Battery? focusBp;
  final GeoPoint? focusLocation;

  /// Notifies every time the agent taps the map icon in the bottom bar — each
  /// notification re-fetches `agent.route`. Null for a pushed [MapScreen],
  /// which loads once on open.
  final Listenable? reloadSignal;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  /// Index into [AgentRoute.stops] of the expanded row in the panel, or -1 when
  /// every row is collapsed — the state the screen opens in.
  int _selected = -1;

  /// Index of the stop whose popup card is open over the map, or -1 when none
  /// is. Set by tapping that stop's pin; cleared by its close button, by a tap
  /// on a panel row, and by a route reload. Kept apart from [_selected] so a pin
  /// tap doesn't also expand a row behind the popup — two copies of the same
  /// stop's actions on screen at once.
  int _popupIndex = -1;

  /// The route `agent.route` last returned, or null before the first call
  /// lands / after one that failed.
  AgentRoute? _route;

  /// The drive drawn over [_route] — its origin, its shape, and whether that
  /// shape follows roads. Null when there is nothing to draw.
  _PlannedRoute? _plan;

  bool _loadingRoute = false;

  /// Why the last `agent.route` call failed, or null when it didn't.
  String? _routeError;

  /// Where the device says the agent is — the origin of the drawn route and the
  /// map's home camera position. Null until a fix lands, and stays null when
  /// there is none, which is the only case that falls back to [kBengaluruCenter].
  GeoPoint? _deviceLocation;

  /// The bpId whose "Start navigation" is still resolving (device fix +
  /// Directions lookup), or null when none is — drives that button's spinner.
  String? _navigatingBpId;

  /// The single-BP navigation leg currently drawn on the map (focused mode
  /// only), or null. Set by [_startNavigation].
  _ActiveNavigation? _navigation;

  @override
  void initState() {
    super.initState();
    if (widget.focusBp != null) {
      // Focused mode never reads the route; it only needs somewhere to open.
      unawaited(_loadDeviceLocation());
      return;
    }
    final signal = widget.reloadSignal;
    if (signal == null) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => unawaited(_loadRoute()));
    } else {
      signal.addListener(_onReloadSignal);
    }
  }

  @override
  void dispose() {
    widget.reloadSignal?.removeListener(_onReloadSignal);
    super.dispose();
  }

  void _onReloadSignal() => unawaited(_loadRoute());

  /// Asks the device where the agent is so the focused map opens on them rather
  /// than on the city-centre fallback. Never blocks the screen.
  Future<void> _loadDeviceLocation() async {
    final fix = await context.read<AppServices>().location.currentLocation();
    if (!mounted || !fix.hasFix) return;
    setState(() => _deviceLocation = fix);
  }

  /// Reads `agent.route` for the signed-in agent and turns it into something
  /// drawable: the stops in the backend's sequence, plus the drive through them
  /// from wherever the agent is standing right now.
  ///
  /// The device fix is taken first and deliberately awaited — it is the origin
  /// of leg 1, so drawing before it lands would show a route that starts in the
  /// wrong place and then jump. A tap while a load is in flight is ignored
  /// rather than queued.
  Future<void> _loadRoute() async {
    if (_loadingRoute) return;
    final agentId = context.read<AuthProvider>().agent?.id ?? '';
    if (agentId.isEmpty) return;
    final services = context.read<AppServices>();

    setState(() {
      _loadingRoute = true;
      _routeError = null;
    });

    final fix = await services.location.currentLocation();
    final here = fix.hasFix ? fix : null;
    final result = await sl<GetAgentRouteUseCase>()(agentId);
    if (!mounted) return;

    if (result.isErr) {
      setState(() {
        _loadingRoute = false;
        _deviceLocation = here ?? _deviceLocation;
        _routeError = result.failureOrNull?.message ?? '';
      });
      return;
    }

    final route = result.valueOrNull ?? AgentRoute.empty;
    final plan = await _buildPlan(services.directions, route, here);
    if (!mounted) return;
    setState(() {
      _loadingRoute = false;
      _deviceLocation = here ?? _deviceLocation;
      _route = route;
      _plan = plan;
      // The stop that was expanded (or had its pin popup open) belongs to the
      // previous route.
      _selected = -1;
      _popupIndex = -1;
    });
  }

  /// Builds the single polyline that runs current location → sequence 1 →
  /// sequence 2 → … → last stop.
  ///
  /// One Directions request covers the whole chain (the intermediate stops ride
  /// as ordered waypoints), so the drawn shape is the actual drive rather than
  /// a set of disconnected legs. Without a device fix there is no leg 1, so the
  /// route starts at the first stop instead. A null answer from Directions —
  /// no key, a key not authorised for the web service, too many waypoints, or a
  /// failed call — degrades to the same chain drawn as straight lines, which
  /// [_PlannedRoute.isRoadRoute] marks so the UI can say so.
  static Future<_PlannedRoute?> _buildPlan(
    DirectionsService directions,
    AgentRoute route,
    GeoPoint? here,
  ) async {
    if (route.stops.isEmpty) return null;
    final origin = here ?? route.stops.first.location;
    // With no fix the first stop IS the origin, so it must not also be a leg
    // destination or the route would begin with a zero-length leg.
    final legs = here == null
        ? route.stops.skip(1).toList()
        : List<RouteStop>.of(route.stops);
    if (legs.isEmpty) {
      return _PlannedRoute(
          origin: origin, points: [origin], isRoadRoute: false,);
    }

    final road = await directions.fetch(
      origin: origin,
      destination: legs.last.location,
      waypoints: [for (final s in legs.take(legs.length - 1)) s.location],
    );
    if (road != null) {
      return _PlannedRoute(
        origin: origin,
        points: road.points,
        isRoadRoute: true,
        distanceKm: road.distanceKm,
        durationMinutes: road.durationMinutes,
      );
    }
    return _PlannedRoute(
      origin: origin,
      points: [origin, for (final s in legs) s.location],
      isRoadRoute: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.read<AppPalette>();
    final services = context.read<AppServices>();
    final agent = context.read<AuthProvider>().agent!;
    final focusBp = widget.focusBp;

    final stops = _route?.stops ?? const <RouteStop>[];
    // -1 (nothing expanded / no popup) travels through as-is; the map just
    // highlights no marker. Clamped so a shorter route can't leave a stale
    // index dangling.
    final selectedIndex = _selected >= stops.length ? -1 : _selected;
    final popupIndex = _popupIndex >= stops.length ? -1 : _popupIndex;
    // A pin's own popup wins the red marker over a row expanded in the panel.
    final highlightIndex = popupIndex >= 0 ? popupIndex : selectedIndex;
    final point = widget.focusLocation ?? focusBp?.lastKnownLocation;
    final here = _deviceLocation ?? agent.currentLocation;

    // Navigation mode (focused BP only) replaces the card with the leg's own.
    final nav = _navigation;

    return Scaffold(
      appBar: focusBp != null
          ? AppBar(title: Text(AppLocalizations.of(context).t('map.title')))
          : null,
      body: SafeArea(
        top: focusBp == null,
        child: Stack(
          children: [
            Positioned.fill(
              child: _GoogleMapView(
                stops: focusBp == null ? stops : const [],
                plan: focusBp == null ? _plan : null,
                highlightIndex: highlightIndex,
                // A pin tap opens that stop's popup card over the map — see
                // [_StopPopupCard]. Re-tapping the open one closes it.
                onSelect: (i) => setState(() {
                  _popupIndex = _popupIndex == i ? -1 : i;
                  _selected = -1;
                }),
                focusPoint: focusBp != null ? point : null,
                userLocation: here != null && here.hasFix ? here : null,
                palette: palette,
                navigation: nav,
              ),
            ),
            if (focusBp == null)
              Positioned(
                top: 12,
                left: 16,
                right: 16,
                child: _RouteHeader(
                  route: _route,
                  plan: _plan,
                  loading: _loadingRoute,
                  palette: palette,
                  onRefresh: _loadingRoute ? null : () => unawaited(_loadRoute()),
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
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // The tapped pin's card, floating above the stop list.
                        if (popupIndex >= 0) ...[
                          _StopPopupCard(
                            stop: stops[popupIndex],
                            palette: palette,
                            onOpen: () => _openDetails(stops[popupIndex]),
                            onClose: () => setState(() => _popupIndex = -1),
                          ),
                          const SizedBox(height: 8),
                        ],
                        _RouteStopsPanel(
                          stops: stops,
                          palette: palette,
                          selectedIndex: selectedIndex,
                          loading: _loadingRoute,
                          error: _routeError,
                          onRetry: () => unawaited(_loadRoute()),
                          onToggle: (i) => setState(() {
                            _selected = _selected == i ? -1 : i;
                            // The row carries the same actions as the popup —
                            // don't leave both on screen.
                            _popupIndex = -1;
                          }),
                          onViewDetails: _openDetails,
                          onOpenExternal: (stop) => _openExternalDirections(
                              stop.location, _deviceLocation,),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Opens the ticket behind [stop]. The detail screen resolves its ticket
  /// through [TicketProvider.byId], which is keyed by the human ticket number
  /// ([Ticket.ticketId]) — not the route's `ticketId` UUID.
  void _openDetails(RouteStop stop) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TicketDetailScreen(ticketId: stop.ticketNumber),
        ),
      );

  /// "Start navigation" on the focused-BP card: draws the drivable route from
  /// the agent's current position to [destination] on this screen's own map.
  ///
  /// The origin is a fresh device fix, falling back to the position the session
  /// last reported. With neither there is nothing to route *from*, so this hands
  /// off to the Maps app after all — that app can start from the device's own
  /// idea of where it is, which we do not have.
  Future<void> _startNavigation(
    AppServices services,
    Battery bp,
    GeoPoint? sessionLocation, {
    GeoPoint? destination,
  }) async {
    if (_navigatingBpId != null) return;
    setState(() => _navigatingBpId = bp.bpId);
    try {
      final to = destination ?? bp.lastKnownLocation;
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
      final route =
          await services.directions.fetch(origin: from, destination: to) ??
              DirectionsRoute.straightLine(from, to);
      if (!mounted) return;
      setState(() => _navigation = _ActiveNavigation(
            bp: bp,
            origin: from,
            destination: to,
            route: route,
          ),);
    } finally {
      if (mounted) setState(() => _navigatingBpId = null);
    }
  }

  /// Hands a leg to the device's Maps app — the escape hatch from the in-app
  /// route, and the only option when we have no origin to route from.
  static Future<void> _openExternalDirections(GeoPoint to, GeoPoint? from) {
    final origin =
        from != null && from.hasFix ? '&origin=${from.lat},${from.lng}' : '';
    return launchUrl(
      Uri.parse(
        'https://www.google.com/maps/dir/?api=1'
        '$origin&destination=${to.lat},${to.lng}&travelmode=driving',
      ),
      mode: LaunchMode.externalApplication,
    );
  }
}

/// The drive drawn across the whole route: where it starts, the shape it
/// follows, and how long it is. Built by [_MapScreenState._buildPlan].
class _PlannedRoute {
  const _PlannedRoute({
    required this.origin,
    required this.points,
    required this.isRoadRoute,
    this.distanceKm,
    this.durationMinutes,
  });

  /// Leg 1's start — the agent's current position, or the first stop when there
  /// is no device fix.
  final GeoPoint origin;

  /// The polyline itself: the road shape from Directions, or the plain
  /// origin → stop 1 → stop 2 → … chain when that was unavailable.
  final List<GeoPoint> points;

  /// False when [points] is the straight-line fallback rather than a driving
  /// route — the header says so, and the line is dashed.
  final bool isRoadRoute;

  /// Google's own totals for the whole chain; null on the fallback, where
  /// [AgentRoute.totalDistanceKm] from the backend is shown instead.
  final double? distanceKm;
  final int? durationMinutes;
}

/// One in-app navigation leg for the focused-BP view: the agent's position when
/// navigation started, the BP being driven to, and the route between them.
class _ActiveNavigation {
  const _ActiveNavigation({
    required this.bp,
    required this.origin,
    required this.destination,
    required this.route,
  });

  final Battery bp;
  final GeoPoint origin;
  final GeoPoint destination;
  final DirectionsRoute route;
}

/// The bar over the map: how many stops today's route has, how far it runs, and
/// a way to pull it again.
class _RouteHeader extends StatelessWidget {
  const _RouteHeader({
    required this.route,
    required this.plan,
    required this.loading,
    required this.palette,
    required this.onRefresh,
  });

  final AgentRoute? route;
  final _PlannedRoute? plan;
  final bool loading;
  final AppPalette palette;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final stopCount = route?.stops.length ?? 0;
    // Prefer Google's distance for the drive actually drawn; fall back to the
    // backend's own total when the shape came from the straight-line fallback.
    final km = plan?.distanceKm ?? route?.totalDistanceKm;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.alt_route, size: 18, color: palette.primaryDark),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.t('map.todaysRoute'),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: palette.onSurface,
                    ),),
                Text(
                  loading && route == null
                      ? l.t('map.loadingRoute')
                      : '${l.t('map.stops', {'count': stopCount})}'
                          '${km == null ? '' : ' · ${Formatters.distanceKm(km)}'}',
                  style: TextStyle(color: palette.muted, fontSize: 11.5),
                ),
              ],
            ),
          ),
          if (loading)
            Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: palette.primaryDark,),
              ),
            )
          else
            IconButton(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh, size: 20),
              tooltip: l.t('common.retry'),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}

/// Live Google Map showing either the whole planned route (a numbered, tappable
/// marker per stop plus the drive through them), an active navigation leg
/// ([_ActiveNavigation]), or a single focused BP marker (Rule 8b).
class _GoogleMapView extends StatefulWidget {
  const _GoogleMapView({
    required this.stops,
    required this.plan,
    required this.highlightIndex,
    required this.onSelect,
    required this.focusPoint,
    required this.palette,
    this.userLocation,
    this.navigation,
  });

  /// The route's stops, already in backend `sequence` order.
  final List<RouteStop> stops;

  /// The drive to draw across [stops], or null when there is none yet.
  final _PlannedRoute? plan;

  /// The stop drawn in red and centred on — the one whose pin popup is open, or
  /// failing that the one expanded in the panel. -1 for neither.
  final int highlightIndex;

  /// Fired when a stop's pin is tapped.
  final ValueChanged<int> onSelect;
  final GeoPoint? focusPoint;

  /// Where the agent is (device fix, else the session's last reported position),
  /// or null while there is neither — the overview map's home camera position.
  final GeoPoint? userLocation;
  final AppPalette palette;

  /// When set, the map draws this leg instead of the route overview.
  final _ActiveNavigation? navigation;

  @override
  State<_GoogleMapView> createState() => _GoogleMapViewState();
}

class _GoogleMapViewState extends State<_GoogleMapView> {
  GoogleMapController? _controller;

  /// Numbered pin bitmaps, keyed `'<sequence>:<highlighted>'` — see
  /// [_buildNumberedPin]. Painting one is asynchronous, so the markers fall back
  /// to plain coloured pins for the frame or two before the cache fills.
  final Map<String, BitmapDescriptor> _pins = {};

  /// The device pixel ratio [_pins] were rasterised at. A change (the app moved
  /// to another display) invalidates them.
  double _pinPixelRatio = 0;

  /// Guards against two [_ensurePins] passes painting the same pin twice when
  /// rebuilds land while one is still running.
  bool _paintingPins = false;

  static String _pinKey(int sequence, {required bool highlighted}) =>
      '$sequence:$highlighted';

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
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ratio = MediaQuery.of(context).devicePixelRatio;
    if (ratio != _pinPixelRatio) {
      _pinPixelRatio = ratio;
      _pins.clear();
    }
    unawaited(_ensurePins());
  }

  /// Paints whatever numbered pins the current stop list still needs, then
  /// rebuilds so the markers pick them up.
  ///
  /// Both the plain and the highlighted bitmap are painted for every sequence up
  /// front: the alternative is painting on selection, which would leave the
  /// tapped pin showing the wrong colour until its bitmap landed.
  Future<void> _ensurePins() async {
    if (_paintingPins || _pinPixelRatio == 0) return;
    _paintingPins = true;
    var painted = false;
    try {
      // Recomputed each pass rather than listed once: a route can reload while
      // this is still painting, and its stops would otherwise wait for another
      // rebuild to be noticed.
      for (var missing = _missingPins();
          missing.isNotEmpty;
          missing = _missingPins()) {
        for (final (sequence, highlighted) in missing) {
          _pins[_pinKey(sequence, highlighted: highlighted)] =
              await _buildNumberedPin(
            number: sequence,
            // The tapped stop wins red so it stays findable among the rest,
            // which share the brand's dark surface — the same split the plain
            // pins used before they carried numbers.
            fill:
                highlighted ? widget.palette.danger : widget.palette.secondary,
            label: Colors.white,
            pixelRatio: _pinPixelRatio,
          );
          painted = true;
        }
        if (!mounted) return;
      }
    } finally {
      _paintingPins = false;
    }
    if (painted && mounted) setState(() {});
  }

  /// The (sequence, highlighted) pairs the current stops need and [_pins] does
  /// not hold yet.
  List<(int, bool)> _missingPins() => [
        for (final sequence in {for (final s in widget.stops) s.sequence})
          for (final highlighted in const [false, true])
            if (!_pins.containsKey(_pinKey(sequence, highlighted: highlighted)))
              (sequence, highlighted),
      ];

  @override
  void didUpdateWidget(_GoogleMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A reloaded route brings sequences this cache may not hold yet.
    if (!identical(oldWidget.stops, widget.stops)) unawaited(_ensurePins());

    // Entering navigation (or switching destination): frame the whole leg so
    // the agent sees both ends of it at once.
    final nav = widget.navigation;
    if (nav != null && !identical(oldWidget.navigation, nav)) {
      _controller?.animateCamera(
        CameraUpdate.newLatLngBounds(_boundsOf(nav.route.points), 64),
      );
      return;
    }

    // A freshly loaded route: frame the whole drive — origin and every stop —
    // rather than leaving the camera wherever the last one left it.
    final plan = widget.plan;
    if (plan != null && !identical(oldWidget.plan, plan)) {
      _controller?.animateCamera(
        CameraUpdate.newLatLngBounds(_boundsOf(_frameOf(plan)), 72),
      );
      return;
    }

    // The device fix usually lands after the map is already built, so the
    // initial camera position missed it — centre on the agent once it arrives.
    // Only on the way from "no position" to a real one, and only while there is
    // no route to frame: a later fix must not yank the camera back while the
    // agent is panning around.
    final me = widget.userLocation;
    if (me != null &&
        oldWidget.userLocation == null &&
        widget.focusPoint == null &&
        widget.plan == null &&
        widget.navigation == null) {
      _controller?.animateCamera(
        CameraUpdate.newLatLngZoom(_toLatLng(me), _kUserLocationZoom),
      );
      return;
    }

    // -1 means nothing is highlighted; leave the camera where it is rather than
    // snapping back to the first stop.
    final i = widget.highlightIndex;
    if (oldWidget.highlightIndex != i && i >= 0 && i < widget.stops.length) {
      _controller?.animateCamera(
        CameraUpdate.newLatLng(_toLatLng(widget.stops[i].location)),
      );
    }
  }

  /// Everything the overview camera must contain: the drawn shape plus every
  /// stop marker. On the road shape the stops already sit on the line, but the
  /// straight-line fallback for a route with no device fix starts at stop 1,
  /// which would otherwise crop nothing — including the markers keeps the two
  /// cases identical.
  List<GeoPoint> _frameOf(_PlannedRoute plan) =>
      [...plan.points, for (final s in widget.stops) s.location];

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focus = widget.focusPoint;
    final nav = widget.navigation;
    final l = AppLocalizations.of(context);

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
            icon:
                BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
            infoWindow: InfoWindow(title: l.t('map.yourLocation')),
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

    final plan = widget.plan;
    final markers = <Marker>{
      if (focus != null)
        Marker(markerId: const MarkerId('focus'), position: _toLatLng(focus)),
      // Where the drive begins — only when it begins at the agent rather than
      // at stop 1 (no device fix), which already has its own pin.
      if (plan != null && widget.userLocation != null)
        Marker(
          markerId: const MarkerId('route_origin'),
          position: _toLatLng(plan.origin),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: InfoWindow(title: l.t('map.yourLocation')),
        ),
      for (var i = 0; i < widget.stops.length; i++)
        Marker(
          markerId: MarkerId('stop_${widget.stops[i].sequence}'),
          position: _toLatLng(widget.stops[i].location),
          // The pin carries the stop's sequence number, so the drive reads 1, 2,
          // 3 … straight off the map. The highlighted stop wins red so it stays
          // findable; the rest share the brand dark. Until the bitmap for a
          // sequence has been painted the marker falls back to a plain coloured
          // pin — the same position, just without its number for a frame.
          icon: _pins[_pinKey(widget.stops[i].sequence,
                  highlighted: i == widget.highlightIndex,)] ??
              BitmapDescriptor.defaultMarkerWithHue(
                i == widget.highlightIndex
                    ? BitmapDescriptor.hueRed
                    : BitmapDescriptor.hueAzure,
              ),
          // The tip is what points at the battery, not the middle of the head.
          anchor: const Offset(0.5, 1),
          // Deliberately NO `infoWindow`: the tap opens [_StopPopupCard]
          // instead, which a native info window cannot be — it takes no chevron
          // and no tap target of its own.
          onTap: () => widget.onSelect(i),
        ),
    };

    final polylines = <Polyline>{
      if (plan != null && plan.points.length > 1)
        Polyline(
          polylineId: const PolylineId('agent_route'),
          points: [for (final p in plan.points) _toLatLng(p)],
          color: widget.palette.primaryDark,
          width: 5,
          patterns: plan.isRoadRoute
              ? const []
              : [PatternItem.dash(20), PatternItem.gap(10)],
        ),
    };

    // The map opens on the agent, not on the city — the route starts at them.
    // kBengaluruCenter is the last resort: no fix, no session position, no stops.
    final me = widget.userLocation;
    final initialTarget = focus ??
        me ??
        (widget.stops.isEmpty ? kBengaluruCenter : widget.stops.first.location);

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
      onMapCreated: (controller) {
        _controller = controller;
        // The route may already have loaded before the platform view was ready
        // (didUpdateWidget fired with no controller) — frame it now.
        final plan = widget.plan;
        if (plan != null) {
          controller.animateCamera(
            CameraUpdate.newLatLngBounds(_boundsOf(_frameOf(plan)), 72),
          );
        }
      },
    );
  }
}

/// Logical size of a stop's map pin — the teardrop [_buildNumberedPin] paints.
/// Wide enough for a two-digit sequence inside the head without shrinking the
/// label; a route long enough for three digits falls back to a smaller one.
const double _kPinWidth = 38;
const double _kPinHeight = 50;

/// Paints the pin a route stop's marker carries: a teardrop with [number] — the
/// stop's `sequence` — set in its head, so the order of the drive is readable
/// off the map itself rather than only off the panel below it.
///
/// Rendered rather than shipped as an asset because the number is data: there is
/// one bitmap per (sequence, highlighted) pair, cached by
/// [_GoogleMapViewState._pins]. [pixelRatio] is the device's, so the bitmap is
/// rasterised at native resolution and handed to Google Maps at the logical size
/// above — a pin baked at 1× would be soft on every real phone.
Future<BitmapDescriptor> _buildNumberedPin({
  required int number,
  required Color fill,
  required Color label,
  required double pixelRatio,
}) async {
  const w = _kPinWidth;
  const h = _kPinHeight;
  // The rim is stroked centred on the path, so the head sits half a stroke in
  // from the edge to keep it from being clipped.
  const radius = w / 2 - 2;
  const center = Offset(w / 2, w / 2);
  const tipY = h - 2;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(pixelRatio);

  // Head and tail unioned into one outline: stroking them separately would draw
  // a rim across the seam where the tail meets the circle.
  final tail = Path()
    ..moveTo(center.dx - radius * 0.72, center.dy + radius * 0.62)
    ..quadraticBezierTo(center.dx - radius * 0.36, tipY - 7, center.dx, tipY)
    ..quadraticBezierTo(
        center.dx + radius * 0.36, tipY - 7, center.dx + radius * 0.72,
        center.dy + radius * 0.62,)
    ..close();
  final pin = Path.combine(
    PathOperation.union,
    Path()..addOval(Rect.fromCircle(center: center, radius: radius)),
    tail,
  );

  canvas
    // A soft drop shadow keeps the pin off a busy map tile.
    ..drawPath(
      pin.shift(const Offset(0, 1)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    )
    ..drawPath(pin, Paint()..color = fill)
    ..drawPath(
      pin,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = Colors.white,
    );

  final text = TextPainter(
    text: TextSpan(
      text: '$number',
      style: TextStyle(
        color: label,
        // Three digits only fit at a smaller size; two are the common case.
        fontSize: number >= 100 ? 12 : 15,
        fontWeight: FontWeight.w800,
        height: 1,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  text.paint(
    canvas,
    Offset(center.dx - text.width / 2, center.dy - text.height / 2),
  );

  final image = await recorder.endRecording().toImage(
        (w * pixelRatio).ceil(),
        (h * pixelRatio).ceil(),
      );
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return BitmapDescriptor.bytes(
    bytes!.buffer.asUint8List(),
    imagePixelRatio: pixelRatio,
  );
}

/// Height of a collapsed stop row and the gap between rows. Fixed so
/// [_RouteStopsPanelState] can scroll a row into view by arithmetic: every row
/// above the expanded one is collapsed, which makes the offset exact.
const double _kStopRowHeight = 56;
const double _kStopRowGap = 8;

/// Padding added to a degenerate route box so `newLatLngBounds` always gets a
/// non-empty rectangle. 0.001° is roughly 110 m — a sane zoom for a route that
/// starts and ends in the same place.
const double _kBoundsEpsilon = 0.001;

/// Zoom used when the map is centred on the agent's own position — close enough
/// to place them on a street, wide enough to show the stops around them.
const double _kUserLocationZoom = 14;

/// The card a stop's pin opens: its sequence number, ticket number and customer
/// name, with a chevron marking the whole thing as a way through to that
/// ticket's detail screen. Tapping anywhere on the card — chevron included —
/// opens it; the `×` just dismisses.
///
/// This is a Flutter widget rather than a Google `InfoWindow` because a native
/// info window is a flat bitmap: it can hold a title and a snippet, but not a
/// chevron, and not a tap target that leads somewhere.
class _StopPopupCard extends StatelessWidget {
  const _StopPopupCard({
    required this.stop,
    required this.palette,
    required this.onOpen,
    required this.onClose,
  });

  final RouteStop stop;
  final AppPalette palette;
  final VoidCallback onOpen;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(14),
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.2),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Row(
            children: [
              _StopBadge(number: stop.sequence, palette: palette),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(stop.ticketNumber,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),),
                    const SizedBox(height: 2),
                    Text(stop.customerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: palette.muted, fontSize: 12.5),),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: palette.primaryDark),
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close, size: 18),
                color: palette.muted,
                tooltip: l.t('common.close'),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The panel floating over the map: every stop on the planned route, in the
/// backend's sequence, one row each. Expanding a row (its `>`) reveals the
/// customer and the stop's two actions, and highlights its marker.
class _RouteStopsPanel extends StatefulWidget {
  const _RouteStopsPanel({
    required this.stops,
    required this.palette,
    required this.selectedIndex,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.onToggle,
    required this.onViewDetails,
    required this.onOpenExternal,
  });

  final List<RouteStop> stops;
  final AppPalette palette;

  /// Index of the expanded row, or -1 when they are all collapsed.
  final int selectedIndex;
  final bool loading;

  /// Message from a failed `agent.route` call, or null.
  final String? error;
  final VoidCallback onRetry;
  final ValueChanged<int> onToggle;
  final ValueChanged<RouteStop> onViewDetails;
  final ValueChanged<RouteStop> onOpenExternal;

  @override
  State<_RouteStopsPanel> createState() => _RouteStopsPanelState();
}

class _RouteStopsPanelState extends State<_RouteStopsPanel> {
  final ScrollController _scroll = ScrollController();

  /// Whether the stop list itself is hidden, leaving just the panel's header
  /// bar — so the map underneath stays visible when the route has enough
  /// stops to otherwise cover most of the screen. Toggled by the header's
  /// chevron; independent of [_MapScreenState._selected] and `_popupIndex`,
  /// neither of which this panel needs to change to collapse.
  bool _collapsed = false;

  @override
  void didUpdateWidget(_RouteStopsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A marker tap expands a row that may be scrolled out of sight — bring it
    // up. Deferred a frame so the list has already grown by the expansion.
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      // The row it's expanding is only visible once the list itself is.
      _collapsed = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
    }
  }

  void _scrollToSelected() {
    final i = widget.selectedIndex;
    if (i < 0 || !_scroll.hasClients) return;
    _scroll.animateTo(
      math.min(
          i * (_kStopRowHeight + _kStopRowGap), _scroll.position.maxScrollExtent,),
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
              Text(l.t('map.activeStops').toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    color: palette.muted,
                    letterSpacing: 0.5,
                  ),),
              const Spacer(),
              if (widget.stops.isNotEmpty) ...[
                Text(l.t('map.stops', {'count': widget.stops.length}),
                    style: TextStyle(fontSize: 11, color: palette.muted),),
                // Collapsing hides the list below, not this header — with many
                // stops the panel can otherwise cover most of the map.
                IconButton(
                  onPressed: () => setState(() => _collapsed = !_collapsed),
                  icon: Icon(
                    _collapsed ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    size: 20,
                    color: palette.muted,
                  ),
                  tooltip: _collapsed
                      ? l.t('map.expandStops')
                      : l.t('map.minimizeStops'),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
              ],
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _collapsed
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: widget.stops.isEmpty
                        ? _EmptyState(
                            loading: widget.loading,
                            error: widget.error,
                            palette: palette,
                            onRetry: widget.onRetry,
                          )
                        : ConstrainedBox(
                            // Never let the list swallow the map — it stays a
                            // panel over it.
                            constraints: BoxConstraints(
                              maxHeight:
                                  MediaQuery.of(context).size.height * 0.42,
                            ),
                            child: ListView.separated(
                              controller: _scroll,
                              shrinkWrap: true,
                              padding: EdgeInsets.zero,
                              itemCount: widget.stops.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: _kStopRowGap),
                              itemBuilder: (context, i) => _StopRow(
                                stop: widget.stops[i],
                                palette: palette,
                                expanded: i == widget.selectedIndex,
                                onToggle: () => widget.onToggle(i),
                                onViewDetails: () =>
                                    widget.onViewDetails(widget.stops[i]),
                                onOpenExternal: () =>
                                    widget.onOpenExternal(widget.stops[i]),
                              ),
                            ),
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// What the panel shows with no stops in hand: the route still loading, the
/// call that failed (with a way to try again), or a genuinely empty route.
class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.loading,
    required this.error,
    required this.palette,
    required this.onRetry,
  });

  final bool loading;
  final String? error;
  final AppPalette palette;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child:
                  CircularProgressIndicator(strokeWidth: 2, color: palette.muted),
            ),
            const SizedBox(width: 10),
            Text(l.t('map.loadingRoute'), style: TextStyle(color: palette.muted)),
          ],
        ),
      );
    }
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(Icons.error_outline, size: 18, color: palette.danger),
            const SizedBox(width: 8),
            Expanded(
              child: Text(l.t('map.routeError'),
                  style: TextStyle(color: palette.danger, fontSize: 12.5),),
            ),
            TextButton(onPressed: onRetry, child: Text(l.t('common.retry'))),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(l.t('map.noStops'), style: TextStyle(color: palette.muted)),
    );
  }
}

/// One stop on the route: collapsed it is its sequence number, ticket number and
/// the length of the leg that reaches it; expanded it opens into the customer
/// name and the stop's two actions.
class _StopRow extends StatelessWidget {
  const _StopRow({
    required this.stop,
    required this.palette,
    required this.expanded,
    required this.onToggle,
    required this.onViewDetails,
    required this.onOpenExternal,
  });

  final RouteStop stop;
  final AppPalette palette;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onViewDetails;
  final VoidCallback onOpenExternal;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
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
                  _StopBadge(number: stop.sequence, palette: palette),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(stop.ticketNumber,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                            ),),
                        const SizedBox(height: 2),
                        Text(stop.customerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                TextStyle(color: palette.muted, fontSize: 11.5),),
                      ],
                    ),
                  ),
                  if (stop.legDistanceKm != null)
                    Text(Formatters.distanceKm(stop.legDistanceKm),
                        style: TextStyle(
                          color: palette.muted,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),),
                  const SizedBox(width: 4),
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
                  Text('${stop.ticketNumber} · ${stop.customerName}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),),
                  const SizedBox(height: 4),
                  Text(stop.location.display,
                      style: TextStyle(color: palette.muted, fontSize: 11.5),),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: onViewDetails,
                      icon: const Icon(Icons.info_outline, size: 16),
                      label: Text(l.t('map.viewDetails')),
                    ),
                  ),
                  const SizedBox(height: 8),
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
            ),
        ],
      ),
    );
  }
}

/// The panel shown while the map is in navigation mode (focused BP): which BP is
/// being driven to, how far and how long the route is, and the two ways out —
/// hand the leg to the device's Maps app, or drop back.
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
                      fontSize: 11,
                      color: palette.muted,
                      letterSpacing: 0.5,
                    ),),
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
/// freshly-fetched live location, with two actions: draw the drivable route to
/// it on this map, or hand the leg to the device's Maps app.
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
                fontSize: 11,
                color: palette.muted,
                letterSpacing: 0.5,
              ),),
          const SizedBox(height: 4),
          Text('${bp.bpId} · ${bp.customer.name}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),),
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

/// The stop's position in the backend's planned route — the same number its map
/// pin carries (see [_buildNumberedPin]).
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
