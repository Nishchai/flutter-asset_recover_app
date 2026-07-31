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
import 'package:asset_recovery_app/presentation/state/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Bottom-tab shell. Tabs are built from `app_config.json navigation.items`,
/// so adding/reordering tabs needs no code change. Hosts the auto-logout timer.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with RouteAware {
  int _index = 0;
  SessionManager? _session;

  /// Index of the tasks tab in `navigation.items` — the home screen proper.
  /// -1 when the config has no such tab.
  int _tasksTabIndex = 0;

  @override
  void initState() {
    super.initState();
    final config = context.read<AppServices>().config;
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
    // a post-frame callback so the GPS read never runs mid-build.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _reportAgentLocation());
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
  void didPopNext() => _reportAgentLocation();

  /// Reports where the device is to `PATCH /agents/location`. Fire-and-forget:
  /// this is passive telemetry, so a denied permission or an unreachable
  /// backend must never interrupt what the agent came to the screen to do.
  ///
  /// Skipped without a real GPS fix — reporting (0, 0) would put the agent in
  /// the Gulf of Guinea, which is worse for dispatch than reporting nothing.
  Future<void> _reportAgentLocation() async {
    final agentId = context.read<AuthProvider>().agent?.id;
    if (agentId == null || agentId.isEmpty) return;
    final position = await context.read<AppServices>().location.currentLocation();
    if (!position.hasFix) return;
    await sl<UpdateAgentLocationUseCase>()(
      UpdateAgentLocationParams(agentId, position),
    );
  }

  @override
  void dispose() {
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
            if (i == _tasksTabIndex) unawaited(_reportAgentLocation());
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
