import 'package:asset_recovery_app/core/config/config_service.dart';
import 'package:asset_recovery_app/core/error/result.dart';
import 'package:asset_recovery_app/core/services/location_service.dart';
import 'package:asset_recovery_app/core/services/sync_queue_service.dart';
import 'package:asset_recovery_app/domain/entities/agent.dart';
import 'package:asset_recovery_app/domain/entities/attempt.dart';
import 'package:asset_recovery_app/domain/entities/battery.dart';
import 'package:asset_recovery_app/domain/entities/enums.dart';
import 'package:asset_recovery_app/domain/entities/geo_point.dart';
import 'package:asset_recovery_app/domain/entities/shift_stats.dart';
import 'package:asset_recovery_app/domain/entities/ticket.dart';
import 'package:asset_recovery_app/domain/usecases/get_assigned_tickets_usecase.dart';
import 'package:asset_recovery_app/domain/usecases/get_road_distance_usecase.dart';
import 'package:asset_recovery_app/domain/usecases/get_shift_stats_usecase.dart';
import 'package:asset_recovery_app/domain/usecases/submit_attempt_usecase.dart';
import 'package:asset_recovery_app/domain/usecases/ticket_pickup_usecase.dart';
import 'package:flutter/foundation.dart';

/// Home tabs (item 1): All Tasks (every ticket the API returned, any status) /
/// In Progress (at least one action taken, including outcomes still awaiting AC
/// approval) / Completed (closed or unrecoverable).
enum TicketFilter { allTasks, inProgress, completed }

/// Presentation state for the ticket list. Talks to the domain exclusively
/// through use cases; applies the home filters + sorting and refreshes
/// road distances on demand.
class TicketProvider extends ChangeNotifier {
  TicketProvider({
    required GetAssignedTicketsUseCase getAssigned,
    required GetShiftStatsUseCase getStats,
    required SubmitAttemptUseCase submitAttempt,
    required GetRoadDistanceUseCase roadDistance,
    required ConfigService config,
    required LocationService location,
    required SyncQueueService syncQueue,
    required GetNearbyUnassignedTicketsUseCase getNearbyUnassigned,
    required PickupTicketUseCase pickupTicket,
  })  : _getAssigned = getAssigned,
        _getStats = getStats,
        _submitAttempt = submitAttempt,
        _roadDistance = roadDistance,
        _config = config,
        _location = location,
        _syncQueue = syncQueue,
        _getNearbyUnassigned = getNearbyUnassigned,
        _pickupTicket = pickupTicket;

  final GetAssignedTicketsUseCase _getAssigned;
  final GetShiftStatsUseCase _getStats;
  final SubmitAttemptUseCase _submitAttempt;
  final GetRoadDistanceUseCase _roadDistance;
  final ConfigService _config;
  final LocationService _location;
  final SyncQueueService _syncQueue;
  final GetNearbyUnassignedTicketsUseCase _getNearbyUnassigned;
  final PickupTicketUseCase _pickupTicket;

  bool _loading = false;
  bool _refreshing = false;
  bool _hasLoaded = false;
  String? _error;
  List<Ticket> _all = [];
  ShiftStats _stats = ShiftStats.empty;
  String _sort = 'distance';
  String? _lastAgentId;
  final Set<String> _pendingSyncTicketIds = {};
  List<Ticket> _nearbyUnassigned = [];
  bool _loadingNearby = false;

  bool get loading => _loading;

  /// True while a pull-to-refresh is in flight. Unlike [loading] it never
  /// blanks the list — the RefreshIndicator owns the progress affordance.
  bool get refreshing => _refreshing;
  bool get hasLoaded => _hasLoaded;
  String? get error => _error;
  String get sort => _sort;
  ShiftStats get stats => _stats;
  List<String> get availableSorts =>
      _config.stringList('taskList.availableSorts');

  /// True right after [submitAttempt] queued the write instead of confirming
  /// it against the server (CC-04 — the agent was offline or the API was
  /// unreachable). Checked by the caller immediately after the call to show
  /// "saved offline" instead of the normal success/pending message.
  bool lastSubmitWasQueued = false;

  bool isPendingSync(String ticketId) => _pendingSyncTicketIds.contains(ticketId);
  int get pendingSyncCount => _syncQueue.pendingCount;

  /// The agent id the current list was loaded for — the signed-in agent's id
  /// (the `commonLogin` partnerId). Null before the first [load] and after
  /// [reset]. The task list compares it against the signed-in agent so a new
  /// sign-in never renders the previous agent's tickets.
  String? get loadedAgentId => _lastAgentId;

  Future<void> load(String agentId) async {
    // A different agent is signing in on this provider (it outlives the
    // session): drop the previous agent's tickets/stats rather than showing
    // them while the new list loads.
    if (_lastAgentId != null && _lastAgentId != agentId) _clearAgentScopedState();
    _lastAgentId = agentId;
    _loading = true;
    _error = null;
    notifyListeners();

    await _fetchAgentTickets(agentId);

    _sort = _config.stringValue('taskList.defaultSort', fallback: 'distance');
    _loading = false;
    _hasLoaded = true;
    notifyListeners();
  }

  /// Pull-to-refresh on the home list: re-runs the tickets (and stats) API for
  /// [agentId] and replaces the list with what came back, without flipping
  /// [loading] — the current tickets stay on screen under the RefreshIndicator
  /// instead of being swapped for a full-screen spinner. The agent's chosen
  /// [sort] is preserved (unlike [load], which resets it to the default).
  Future<void> refresh(String agentId) async {
    if (_loading || _refreshing) return;
    // First load for this agent (or a different one signed in): that's a plain
    // load, including the reset of agent-scoped state.
    if (!_hasLoaded || _lastAgentId != agentId) {
      await load(agentId);
      return;
    }
    _refreshing = true;
    _error = null;
    notifyListeners();

    await _fetchAgentTickets(agentId);

    _refreshing = false;
    notifyListeners();
  }

  /// Fetches the agent's tickets + shift stats and folds the response into
  /// state. On a ticket failure the previous list is kept and [error] is set,
  /// so a failed refresh degrades to "nothing changed" rather than an empty
  /// list. Shared by [load] and [refresh]; neither notifies from here.
  Future<void> _fetchAgentTickets(String agentId) async {
    final ticketsResult = await _getAssigned(agentId);
    if (ticketsResult.isOk) {
      _all = ticketsResult.valueOrNull ?? const [];
      _applyAutoExpiry();
    } else {
      _error = ticketsResult.failureOrNull?.message;
    }

    // Stats are non-critical — keep last known on failure.
    final statsResult = await _getStats(agentId);
    if (statsResult.isOk) {
      _stats = statsResult.valueOrNull ?? ShiftStats.empty;
    }
  }

  /// Drops everything that belonged to the signed-out agent — tickets, stats
  /// and, crucially, [loadedAgentId], the id [registerAttemptSyncHandler]'s
  /// replay refreshes against. Called on logout (see
  /// `AuthProvider.addLogoutListener`): this provider is created once for the
  /// app's lifetime, so without it the next agent would see the previous one's
  /// list and a queued write would refresh under the previous one's id.
  void reset() {
    _clearAgentScopedState();
    notifyListeners();
  }

  void _clearAgentScopedState() {
    _all = [];
    _stats = ShiftStats.empty;
    _error = null;
    _hasLoaded = false;
    _lastAgentId = null;
    _nearbyUnassigned = [];
    _pendingSyncTicketIds.clear();
    lastSubmitWasQueued = false;
  }

  /// Rule 7 — a ticket with no action/outcome reached within the configured
  /// SLA window auto-expires so it drops off the active work list, tagged
  /// distinctly from a normal closure so it's identifiable as auto-expired.
  void _applyAutoExpiry() {
    final now = DateTime.now();
    final slaDays = _config.slaDays;
    for (final t in _all) {
      if (t.status != TicketStatus.assigned && t.status != TicketStatus.inProgress) {
        continue;
      }
      if (now.difference(t.createdAt).inDays >= slaDays) {
        t.status = TicketStatus.unrecoverable;
        t.closedAt = now;
        t.reason = 'Auto-expired — no action within $slaDays days';
      }
    }
  }

  List<Ticket> ticketsFor(TicketFilter filter) {
    final now = DateTime.now();
    final filtered = _all.where((t) {
      switch (filter) {
        case TicketFilter.allTasks:
          // Every ticket the tickets API returned for this agent, whatever its
          // status — the In Progress / Completed tabs are the narrowed views.
          return true;
        case TicketFilter.inProgress:
          // Any BP with at least one action taken but not yet closed —
          // includes outcomes (Recovered / FIR-Lost) still awaiting AC
          // approval, since the Field Agent never closes a ticket directly.
          return t.status == TicketStatus.inProgress ||
              t.status == TicketStatus.pending;
        case TicketFilter.completed:
          return t.status == TicketStatus.closed ||
              t.status == TicketStatus.unrecoverable;
      }
    }).toList();
    _applySort(filtered, now);
    return filtered;
  }

  /// Closed/unrecoverable tickets, for the history view.
  List<Ticket> get closedTickets => _all
      .where((t) =>
          t.status == TicketStatus.closed ||
          t.status == TicketStatus.unrecoverable,)
      .toList();

  /// Every non-completed ticket (All Tasks + In Progress), for the map view.
  List<Ticket> get activeTickets => _all
      .where((t) =>
          t.status != TicketStatus.closed &&
          t.status != TicketStatus.unrecoverable,)
      .toList();

  void _applySort(List<Ticket> list, DateTime now) {
    switch (_sort) {
      case 'pendingDuration':
        list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      case 'slaRemaining':
        list.sort((a, b) => a
            .slaDaysLeft(_config.slaDays, now)
            .compareTo(b.slaDaysLeft(_config.slaDays, now)),);
      case 'distance':
      default:
        double d(Ticket t) => t.primaryBp.distanceKm ?? double.infinity;
        list.sort((a, b) => d(a).compareTo(d(b)));
    }
  }

  void setSort(String sort) {
    if (sort == _sort) return;
    _sort = sort;
    notifyListeners();
  }

  Ticket? byId(String ticketId) {
    for (final t in _all) {
      if (t.ticketId == ticketId) return t;
    }
    return null;
  }

  int countFor(TicketFilter filter) => ticketsFor(filter).length;

  // Derived live from `_all` (not the one-shot `_stats` snapshot) so the
  // header recounts on every notifyListeners() — e.g. right after
  // submitAttempt() changes a ticket's status.
  int get assignedCount =>
      _all.where((t) => t.status == TicketStatus.assigned).length;
  int get inProgressCount =>
      _all.where((t) => t.status == TicketStatus.inProgress).length;
  int get pendingCount =>
      _all.where((t) => t.status == TicketStatus.pending).length;

  /// Recomputes road distance from the agent to every BP (PRD §4.8).
  ///
  /// A no-op without a usable device fix: distances measured from Null Island
  /// would be thousands of km and would reorder the whole distance-sorted
  /// list. Keeping the previous numbers is the lesser wrong.
  Future<void> refreshDistances(Agent agent) async {
    final from = agent.currentLocation ?? await _location.currentLocation();
    if (!from.hasFix) return;
    for (final t in _all) {
      for (final bp in t.batteries) {
        final result = await _roadDistance(RoadDistanceParams(from, bp.lastKnownLocation));
        bp.distanceKm = result.valueOrNull ?? bp.distanceKm;
      }
    }
    notifyListeners();
  }

  /// Persists a submitted attempt then refreshes local state. CC-04: on
  /// failure (offline or the API unreachable), the write is queued for retry
  /// instead of lost — [lastSubmitWasQueued] tells the caller which happened.
  Future<Attempt> submitAttempt(
      String ticketId, Battery bp, Attempt attempt,) async {
    final result = await _submitAttempt(SubmitAttemptParams(
      ticketId: ticketId,
      bpId: bp.bpId,
      attempt: attempt,
    ),);
    if (result.isOk) {
      lastSubmitWasQueued = false;
      _pendingSyncTicketIds.remove(ticketId);
      notifyListeners();
      return result.valueOrNull!;
    }
    await _syncQueue.enqueue('submit_attempt', {
      'ticketId': ticketId,
      'bpId': bp.bpId,
      'attempt': attempt.toJson(),
    });
    lastSubmitWasQueued = true;
    _pendingSyncTicketIds.add(ticketId);
    notifyListeners();
    return attempt;
  }

  /// Registers how a queued attempt-submission action is replayed once
  /// connectivity returns. Called once from the DI container.
  void registerAttemptSyncHandler() {
    _syncQueue.registerHandler('submit_attempt', (payload) async {
      final result = await _submitAttempt(SubmitAttemptParams(
        ticketId: payload['ticketId'] as String,
        bpId: payload['bpId'] as String,
        attempt: Attempt.fromJson(Map<String, dynamic>.from(payload['attempt'] as Map)),
      ),);
      if (result.isErr) throw StateError(result.failureOrNull!.message);
      // A queued write just landed server-side — local ticket state (e.g.
      // status transitions the mock/API decided) is stale until refreshed.
      if (_lastAgentId != null) await load(_lastAgentId!);
    });
  }

  // --- Location-based pickup (M1-02) ------------------------------------------

  List<Ticket> get nearbyUnassigned => _nearbyUnassigned;
  bool get loadingNearby => _loadingNearby;

  /// Refreshes the unassigned-ticket pool within `business.nearbyPickupRadiusKm`
  /// of [near] — cases nobody's working yet that happen to sit on the agent's
  /// current route.
  Future<void> loadNearbyUnassigned(GeoPoint near) async {
    _loadingNearby = true;
    notifyListeners();
    final radiusKm = _config.doubleValue('business.nearbyPickupRadiusKm', fallback: 8);
    final result = await _getNearbyUnassigned(NearbyUnassignedParams(near, radiusKm));
    _nearbyUnassigned = result.valueOrNull ?? const [];
    _loadingNearby = false;
    notifyListeners();
  }

  /// Self-assigns [ticketId], moving it from the nearby pool into the
  /// agent's own ticket list.
  Future<bool> pickup(String ticketId, String agentId) async {
    final result = await _pickupTicket(PickupTicketParams(ticketId, agentId));
    if (result.isErr) return false;
    _nearbyUnassigned = _nearbyUnassigned.where((t) => t.ticketId != ticketId).toList();
    _all = [..._all, result.valueOrNull!];
    notifyListeners();
    return true;
  }
}
