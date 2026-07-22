import 'package:asset_recovery_app/core/config/config_service.dart';
import 'package:asset_recovery_app/core/di/app_services.dart';
import 'package:asset_recovery_app/core/di/injector.dart';
import 'package:asset_recovery_app/core/localization/app_localizations.dart';
import 'package:asset_recovery_app/core/localization/locale_provider.dart';
import 'package:asset_recovery_app/core/services/location_service.dart';
import 'package:asset_recovery_app/core/services/proof_service.dart';
import 'package:asset_recovery_app/core/theme/app_theme.dart';
import 'package:asset_recovery_app/data/repositories/mock_ticket_repository.dart';
import 'package:asset_recovery_app/presentation/state/auth_provider.dart';
import 'package:asset_recovery_app/presentation/state/shift_provider.dart';
import 'package:asset_recovery_app/presentation/state/ticket_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

/// Shared test fixtures.
///
/// Loads the REAL config + localization assets (so tests also validate those
/// files), wires the DI container with a zero-latency, fixed-seed mock backend
/// for deterministic, instant runs, and exposes the key fixtures for direct
/// unit-test access.
class TestEnv {
  TestEnv({
    required this.config,
    required this.services,
    required this.repository,
    required this.location,
  });

  final ConfigService config;
  final AppServices services;
  final MockTicketRepository repository;
  final StubLocationService location;

  // Cached after the first load. Re-reading assets via `rootBundle.loadString`
  // a second time in the same test file — after a widget has been pumped —
  // hangs under this Flutter SDK's AutomatedTestWidgetsFlutterBinding (a
  // pre-existing test-framework quirk, unrelated to app code). Loading once
  // and reusing the parsed config for every subsequent `TestEnv.create()`
  // call sidesteps it entirely.
  static ConfigService? _cachedConfig;

  static Future<TestEnv> create() async {
    final config = _cachedConfig ??= await ConfigService.load(
      environment: 'test',
      reader: rootBundle.loadString,
    );
    final location = StubLocationService(seed: 42);
    final proof = StubProofService(location);
    final repository = MockTicketRepository(seed: 42, latency: Duration.zero);

    await resetDependencies();
    await configureDependencies(
      config: config,
      repository: repository,
      location: location,
      proof: proof,
    );

    return TestEnv(
      config: config,
      services: sl<AppServices>(),
      repository: repository,
      location: location,
    );
  }

  AppTheme get theme => AppTheme(config);
}

/// Wraps [child] with the full provider + localization scaffold used in the
/// real app, resolving providers from the DI container, with an authenticated
/// agent and tickets pre-loaded.
Future<Widget> wrapApp(TestEnv env, Widget child, {bool authed = true}) async {
  final auth = sl<AuthProvider>();
  final tickets = sl<TicketProvider>();
  if (authed) {
    await auth.requestOtp('9876543210');
    await auth.verifyOtp('123456');
    await tickets.load('FA-RM-01');
  }

  final theme = env.theme;

  return MultiProvider(
    providers: [
      Provider<AppServices>.value(value: env.services),
      Provider<AppPalette>.value(value: theme.palette),
      ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ChangeNotifierProvider<TicketProvider>.value(value: tickets),
      ChangeNotifierProvider<ShiftProvider>(create: (_) => sl<ShiftProvider>()),
      ChangeNotifierProvider<LocaleProvider>(
        create: (_) => LocaleProvider(
          defaultLanguage: 'en',
          supportedLanguages: env.config.supportedLanguages,
        ),
      ),
    ],
    child: MaterialApp(
      theme: theme.build(),
      locale: const Locale('en'),
      supportedLocales: env.config.supportedLanguages.map(Locale.new).toList(),
      localizationsDelegates: [
        AppLocalizationsDelegate(env.config.supportedLanguages),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: child,
    ),
  );
}
