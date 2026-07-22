import 'package:asset_recovery_app/app/asset_recovery_app.dart';
import 'package:asset_recovery_app/core/config/config_service.dart';
import 'package:asset_recovery_app/core/di/injector.dart';
import 'package:asset_recovery_app/core/localization/locale_provider.dart';
import 'package:flutter/material.dart';

/// Entry point. Configures the DI container (which loads config and builds the
/// data → domain → presentation graph), then runs the app. The environment is
/// chosen by `defaultEnvironment` in app_config.json, overridable with
/// `--dart-define=ENV=test`.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await configureDependencies();
  final config = sl<ConfigService>();

  final localeProvider = LocaleProvider(
    defaultLanguage: config.defaultLanguage,
    supportedLanguages: config.supportedLanguages,
  );
  await localeProvider.loadSaved();

  runApp(AssetRecoveryApp(localeProvider: localeProvider));
}
