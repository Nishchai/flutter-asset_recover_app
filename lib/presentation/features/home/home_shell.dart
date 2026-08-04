import 'dart:async';

import 'package:asset_recovery_app/app/asset_recovery_app.dart';
import 'package:asset_recovery_app/core/di/app_services.dart';
import 'package:asset_recovery_app/core/di/injector.dart';
import 'package:asset_recovery_app/core/localization/app_localizations.dart';
import 'package:asset_recovery_app/core/services/location_service.dart';
import 'package:asset_recovery_app/core/services/session_manager.dart';
import 'package:asset_recovery_app/core/services/session_store.dart';
import 'package:asset_recovery_app/domain/usecases/update_agent_location_usecase.dart';
import 'package:asset_recovery_app/presentation/features/home/task_list_screen.dart';
import 'package:asset_recovery_app/presentation/features/map/map_screen.dart';
import 'package:asset_recovery_app/presentation/features/profile/profile_screen.dart';
import 'package:asset_recovery_app/presentation/shared/location_gate.dart';
import 'package:asset_recovery_app/presentation/state/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Bottom-tab shell. Tabs are built from `app_config.json navigation.items`,
/// so adding/reordering tabs needs no code change. Hosts the auto-logout timer
/// and the foreground agent-location heartbeat.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell>
    with RouteAware, WidgetsBindingObserver {
  int _index = 0;
  SessionManager? _session;

  /// Index of the tasks tab in `navigation.items` — the home screen proper.
  /// -1 when the config has no such tab.
  int _tasksTabIndex = 0;

  /// Foreground location heartbeat (`location.reportIntervalMinutes`). Chained
  /// single-shot timers rather than [Timer.periodic] so the gap is measured
  /// from the *end* of the last report — a landing-triggered report pushes the
  /// next tick out instead of letting the two fire seconds apart.
  Timer? _locationTimer;

  /// Interval between heartbeats. [Duration.zero] means the heartbeat is off.
  Duration _locationInterval = Duration.zero;

  /// Set while a report is in flight so a tick can never stack a second GPS
  /// read + PATCH on top of one a landing already started.
  bool _reportingLocation = false;

  /// Set while the blocking location gate is on screen. Home is the single
  /// enforcement point for location access, and every landing runs the check —
  /// so this stops a resume, a pop and a tab switch from stacking three
  /// dialogs on top of each other.
  bool _locationGateOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final config = context.read<AppServices>().config;
    _locationInterval =
        Duration(minutes: config.locationReportIntervalMinutes.clamp(0, 1440));
    _tasksTabIndex = config.navItems
        .indexWhere((item) => item['id'] == 'tasks');
    _session = SessionManager(
      store: sl<SessionStore>(),
      sessionDuration: Duration(hours: config.autoLogoutHours),
      onExpired: () {
        if (!mounted) return;
        // Whatever is pushed over the shell (ticket detail, actions hub,
        // scanner…) has to come down first: the root router only swaps
        // HomeShell for LoginScreen, so a pushed route would otherwise sit on
        // top of the login form and let the agent keep working.
        Navigator.of(context).popUntil((route) => route.isFirst);
        // Auto-logout also wipes the stored session, so the next launch asks
        // for the OTP again (PRD §4.9).
        unawaited(context.read<AuthProvider>().logout());
      },
    )..start();
    // Landing #1: the agent just signed in / relaunched onto home. Deferred to
    // a post-frame callback so the permission request and GPS read never run
    // mid-build. This first report also starts the heartbeat chain, which then
    // re-arms itself.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => unawaited(_ensureLocationThenReport()));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is ModalRoute<void>) appRouteObserver.subscribe(this, route);
  }

  /// Landing #2: a screen pushed on top of home (ticket detail, actions hub,
  /// map, scanner…) has popped and home is in front again.
  @override
  void didPopNext() => unawaited(_ensureLocationThenReport());

  /// Landing #4 / heartbeat: the app came back to the foreground. Dispatch may
  /// have been stale for however long it sat in the background, so report at
  /// once and restart the heartbeat; a backgrounded app stops reporting because
  /// the GPS read needs a foreground (there is no background location grant).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_ensureLocationThenReport());
    } else {
      _locationTimer?.cancel();
      _locationTimer = null;
    }
  }

  /// Every landing on home goes through here: hold the app until location is
  /// usable, then report. Home is the only place that enforces this, so the
  /// gate has to run on all four landings — sign-in/relaunch, a pushed screen
  /// popping, a tab switch back, and a foreground resume — or an agent who
  /// switches location off mid-shift keeps working without coordinates until
  /// the next cold start.
  ///
  /// The report is deliberately *after* the gate: with location off there is no
  /// fix to send, and the heartbeat this call arms would only be spinning up a
  /// GPS read every few minutes to throw the result away.
  Future<void> _ensureLocationThenReport() async {
    // The gate is already up and owns the retry loop; a second landing while
    // it's showing has nothing to add. It re-reports once it closes.
    if (_locationGateOpen || !mounted) return;
    _locationGateOpen = true;
    try {
      await enforceLocationAccess(context);
    } finally {
      _locationGateOpen = false;
    }
    if (!mounted) return;
    await _reportAgentLocation();
  }

  /// Reports where the device is to `PATCH /agents/location`. Fire-and-forget:
  /// this is passive telemetry, so a denied permission or an unreachable
  /// backend must never interrupt what the agent came to the screen to do.
  ///
  /// Skipped without a real GPS fix — reporting (0, 0) would put the agent in
  /// the Gulf of Guinea, which is worse for dispatch than reporting nothing.
  /// Every call re-arms the heartbeat, whatever the outcome: a skip (no fix, no
  /// permission) or a failed PATCH must not end periodic reporting for the rest
  /// of the shift.
  Future<void> _reportAgentLocation() async {
    // An in-flight report already owns the re-arm, so bailing here keeps the
    // chain intact.
    if (_reportingLocation) return;
    _reportingLocation = true;
    try {
      if (!mounted) return;
      final agentId = context.read<AuthProvider>().agent?.id;
      if (agentId == null || agentId.isEmpty) return;
      final position =
          await context.read<AppServices>().location.currentLocation();
      if (!position.hasFix) return;
      await sl<UpdateAgentLocationUseCase>()(
        UpdateAgentLocationParams(agentId, position),
      );
    } finally {
      _reportingLocation = false;
      _scheduleLocationReport();
    }
  }

  /// Arms the next heartbeat, replacing any pending one. No-op unless the app
  /// is actually in front: a report that was still in flight when the agent
  /// backgrounded the app would otherwise re-arm the chain behind
  /// [didChangeAppLifecycleState]'s cancel. Resuming re-arms it.
  void _scheduleLocationReport() {
    _locationTimer?.cancel();
    _locationTimer = null;
    if (!mounted || _locationInterval == Duration.zero) return;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    _locationTimer = Timer(_locationInterval, _reportAgentLocation);
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    appRouteObserver.unsubscribe(this);
    _session?.dispose();
    super.dispose();
  }

  static const _iconMap = {
    'checklist': Icons.checklist_rounded,
    'map': Icons.map_outlined,
    'person': Icons.person_outline,
  };

  Widget _screenFor(String id) {
    switch (id) {
      case 'map':
        return const MapScreen();
      case 'profile':
        return const ProfileScreen();
      case 'tasks':
      default:
        return const TaskListScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final navItems = context.read<AppServices>().config.navItems;

    return Listener(
      onPointerDown: (_) => _session?.touch(),
      child: Scaffold(
        body: IndexedStack(
          index: _index,
          children: [
            for (final item in navItems) _screenFor(item['id'] as String),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) {
            setState(() => _index = i);
            // Landing #3: back on the tasks tab from Map/Profile. The tabs
            // live in an IndexedStack, so TaskListScreen is never rebuilt and
            // nothing else would notice the agent returned to home.
            if (i == _tasksTabIndex) unawaited(_ensureLocationThenReport());
          },
          destinations: [
            for (final item in navItems)
              NavigationDestination(
                icon: Icon(_iconMap[item['icon']] ?? Icons.circle_outlined),
                label: l.t(item['labelKey'] as String),
              ),
          ],
        ),
      ),
    );
  }
}
