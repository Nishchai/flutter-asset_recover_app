import 'package:asset_recovery_app/core/di/app_services.dart';
import 'package:asset_recovery_app/core/localization/app_localizations.dart';
import 'package:asset_recovery_app/core/services/session_manager.dart';
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

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  SessionManager? _session;

  @override
  void initState() {
    super.initState();
    final config = context.read<AppServices>().config;
    _session = SessionManager(
      sessionDuration: Duration(hours: config.autoLogoutHours),
      onExpired: () {
        if (mounted) context.read<AuthProvider>().logout();
      },
    )..start();
  }

  @override
  void dispose() {
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
          onDestinationSelected: (i) => setState(() => _index = i),
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
