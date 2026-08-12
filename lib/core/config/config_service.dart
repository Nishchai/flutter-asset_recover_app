import 'dart:convert';

import 'package:asset_recovery_app/core/config/environment.dart';
import 'package:asset_recovery_app/core/config/option_item.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Signature for reading a text asset. Defaults to [rootBundle]; tests inject a
/// fake reader to supply config without a running Flutter asset bundle.
typedef AssetReader = Future<String> Function(String path);

/// Central, immutable holder of all runtime configuration.
///
/// Loads every JSON config file once at startup and exposes typed accessors so
/// the rest of the app never parses JSON or hard-codes business values. This is
/// the single source for the "everything is configurable" requirement.
class ConfigService {
  ConfigService._({
    required this.env,
    required Map<String, dynamic> app,
    required Map<String, dynamic> theme,
    required Map<String, dynamic> dropdowns,
    required Map<String, dynamic> attemptFlow,
    required Map<String, dynamic> endpoints,
  })  : _app = app,
        _theme = theme,
        _dropdowns = dropdowns,
        _attemptFlow = attemptFlow,
        _endpoints = endpoints;

  final EnvironmentConfig env;
  final Map<String, dynamic> _app;
  final Map<String, dynamic> _theme;
  final Map<String, dynamic> _dropdowns;
  final Map<String, dynamic> _attemptFlow;
  final Map<String, dynamic> _endpoints;

  Map<String, dynamic> get appConfig => _app;
  Map<String, dynamic> get themeConfig => _theme;
  Map<String, dynamic> get attemptFlow => _attemptFlow;
  Map<String, dynamic> get endpoints => _endpoints;

  /// Loads all configuration for [environment]. Pass [reader] in tests.
  static Future<ConfigService> load({
    String? environment,
    AssetReader? reader,
  }) async {
    final readerFn = reader ?? rootBundle.loadString;
    final app = jsonDecode(await readerFn('assets/config/app_config.json'))
        as Map<String, dynamic>;

    final envName = environment ??
        const String.fromEnvironment('ENV', defaultValue: '').ifEmpty(
          app['defaultEnvironment'] as String? ?? 'dev',
        );

    final env = EnvironmentConfig.fromJson(
      jsonDecode(await readerFn('assets/config/environments/$envName.json'))
          as Map<String, dynamic>,
    );

    final theme = jsonDecode(await readerFn('assets/config/theme_config.json'))
        as Map<String, dynamic>;
    final dropdowns = jsonDecode(await readerFn('assets/config/dropdowns.json'))
        as Map<String, dynamic>;
    final attemptFlow =
        jsonDecode(await readerFn('assets/config/attempt_flow.json'))
            as Map<String, dynamic>;
    final endpoints =
        jsonDecode(await readerFn('assets/config/api_endpoints.json'))
            as Map<String, dynamic>;

    return ConfigService._(
      env: env,
      app: app,
      theme: theme,
      dropdowns: dropdowns,
      attemptFlow: attemptFlow,
      endpoints: endpoints,
    );
  }

  // --- Generic dotted-path lookups into app_config.json -----------------------

  /// Reads any value by dotted path, e.g. `value('business.slaDays')`.
  dynamic value(String dottedPath) {
    dynamic current = _app;
    for (final key in dottedPath.split('.')) {
      if (current is Map<String, dynamic> && current.containsKey(key)) {
        current = current[key];
      } else {
        return null;
      }
    }
    return current;
  }

  /// Boolean flag by dotted path, e.g. `flag('proof.mandatoryForCall')`.
  bool flag(String dottedPath, {bool fallback = false}) {
    final v = value(dottedPath);
    return v is bool ? v : fallback;
  }

  int intValue(String dottedPath, {int fallback = 0}) {
    final v = value(dottedPath);
    return v is num ? v.toInt() : fallback;
  }

  double doubleValue(String dottedPath, {double fallback = 0}) {
    final v = value(dottedPath);
    return v is num ? v.toDouble() : fallback;
  }

  String stringValue(String dottedPath, {String fallback = ''}) {
    final v = value(dottedPath);
    return v is String ? v : fallback;
  }

  List<String> stringList(String dottedPath) {
    final v = value(dottedPath);
    return v is List ? v.map((e) => e.toString()).toList() : const [];
  }

  // --- Convenience business accessors -----------------------------------------

  String get appName => stringValue('appName', fallback: 'Asset Recovery');

  /// Version string reported to the backend (audit log). Mirrors pubspec's
  /// `version:` — see the note in app_config.json.
  String get appVersion => stringValue('appVersion');
  int get slaDays => intValue('business.slaDays', fallback: 90);
  int get slaWarnDays => intValue('business.slaWarnDays', fallback: 7);
  int get autoLogoutHours => intValue('session.autoLogoutHours', fallback: 12);
  double get geofenceRadiusMeters =>
      doubleValue('location.geofenceRadiusMeters', fallback: 50);
  bool get enforceGeofence =>
      flag('location.enforceGeofenceOnRecovery', fallback: true);

  /// Cadence of the foreground `PATCH /agents/location` heartbeat. 0 turns the
  /// heartbeat off and leaves only the landing-triggered reports.
  int get locationReportIntervalMinutes =>
      intValue('location.reportIntervalMinutes', fallback: 5);
  String get defaultLanguage =>
      stringValue('localization.defaultLanguage', fallback: 'en');
  List<String> get supportedLanguages =>
      stringList('localization.supportedLanguages');

  /// Navigation items for the home shell bottom bar.
  List<Map<String, dynamic>> get navItems {
    final items = value('navigation.items');
    return items is List ? items.cast<Map<String, dynamic>>() : const [];
  }

  /// Task-list segments (my_tasks / in_progress / completed).
  List<String> get taskSegments => stringList('taskList.segments');

  // --- Dropdown option sets ---------------------------------------------------

  List<OptionItem> options(String ref) {
    final raw = _dropdowns[ref];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(OptionItem.fromJson)
        .toList();
  }

  OptionItem? optionByValue(String ref, String value) {
    for (final o in options(ref)) {
      if (o.value == value) return o;
    }
    return null;
  }
}

extension _StringIfEmpty on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
