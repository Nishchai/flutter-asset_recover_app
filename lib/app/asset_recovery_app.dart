import 'package:asset_recovery_app/core/config/config_service.dart';
import 'package:asset_recovery_app/core/di/app_services.dart';
import 'package:asset_recovery_app/core/di/injector.dart';
import 'package:asset_recovery_app/core/localization/app_localizations.dart';
import 'package:asset_recovery_app/core/localization/locale_provider.dart';
import 'package:asset_recovery_app/core/theme/app_theme.dart';
import 'package:asset_recovery_app/presentation/features/auth/login_screen.dart';
import 'package:asset_recovery_app/presentation/features/home/home_shell.dart';
import 'package:asset_recovery_app/presentation/state/auth_provider.dart';
import 'package:asset_recovery_app/presentation/state/shift_provider.dart';
import 'package:asset_recovery_app/presentation/state/ticket_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

/// Root widget. Resolves all dependencies from the DI container ([sl]) and
/// wires Provider scopes, theme, localization and top-level auth routing.
/// [configureDependencies] must be awaited before this is built.
class AssetRecoveryApp extends StatelessWidget {
  const AssetRecoveryApp({super.key, required this.localeProvider});

  final LocaleProvider localeProvider;

  @override
  Widget build(BuildContext context) {
    final config = sl<ConfigService>();
    final theme = AppTheme(config);

    return MultiProvider(
      providers: [
        Provider<AppServices>(create: (_) => sl<AppServices>()),
        Provider<AppPalette>.value(value: theme.palette),
        ChangeNotifierProvider<LocaleProvider>.value(value: localeProvider),
        ChangeNotifierProvider<AuthProvider>(create: (_) => sl<AuthProvider>()),
        ChangeNotifierProvider<TicketProvider>(
          create: (context) {
            final tickets = sl<TicketProvider>()..registerAttemptSyncHandler();
            // This provider outlives the session, so logout has to empty it:
            // otherwise the next agent to sign in sees the previous agent's
            // tickets and refreshes them under the previous agent's id.
            // AuthProvider is declared above, so it is already available here.
            context.read<AuthProvider>().addLogoutListener(tickets.reset);
            return tickets;
          },
        ),
        ChangeNotifierProvider<ShiftProvider>(
          create: (context) {
            final shift = sl<ShiftProvider>();
            // Ending the shift signs the agent out, so this provider has to be
            // rearmed for whoever signs in next — otherwise they inherit the
            // previous agent's ended shift.
            context.read<AuthProvider>().addLogoutListener(shift.reset);
            return shift;
          },
        ),
      ],
      child: Consumer<LocaleProvider>(
        builder: (context, locale, _) {
          return MaterialApp(
            title: config.appName,
            debugShowCheckedModeBanner: false,
            theme: theme.build(),
            locale: locale.locale,
            supportedLocales: locale.supportedLocales,
            localizationsDelegates: [
              AppLocalizationsDelegate(config.supportedLanguages),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const _RootRouter(),
          );
        },
      ),
    );
  }
}

/// Shows login or the home shell depending on auth state.
class _RootRouter extends StatelessWidget {
  const _RootRouter();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return auth.isLoggedIn ? const HomeShell() : const LoginScreen();
  }
}
