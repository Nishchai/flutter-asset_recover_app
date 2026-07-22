import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

/// JSON-backed localization with automatic English fallback.
///
/// Strings live in `assets/l10n/<code>.json`. Any key missing from the active
/// language falls back to English, then to the raw key — so partial
/// translations never crash the UI. Supports `{param}` interpolation.
class AppLocalizations {
  AppLocalizations(this.locale, this._strings, this._fallback);

  final Locale locale;
  final Map<String, String> _strings;
  final Map<String, String> _fallback;

  static AppLocalizations of(BuildContext context) {
    final instance = Localizations.of<AppLocalizations>(context, AppLocalizations);
    assert(instance != null, 'No AppLocalizations found in context');
    return instance!;
  }

  /// Translates [key], substituting `{name}` placeholders from [params].
  String t(String key, [Map<String, Object?> params = const {}]) {
    var value = _strings[key] ?? _fallback[key] ?? key;
    params.forEach((k, v) {
      value = value.replaceAll('{$k}', '${v ?? ''}');
    });
    return value;
  }

  /// Loader for a single language file; injectable for tests.
  static Future<Map<String, String>> loadLanguage(
    String code, {
    Future<String> Function(String)? reader,
  }) async {
    final readerFn = reader ?? rootBundle.loadString;
    try {
      final raw = await readerFn('assets/l10n/$code.json');
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return {};
    }
  }
}

/// Delegate parameterised by the supported language list from config.
class AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  AppLocalizationsDelegate(
    this.supportedCodes, {
    Future<String> Function(String)? reader,
  }) : reader = reader ?? rootBundle.loadString;

  final List<String> supportedCodes;
  final Future<String> Function(String) reader;

  @override
  bool isSupported(Locale locale) => supportedCodes.contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async {
    final fallback = await AppLocalizations.loadLanguage('en', reader: reader);
    final strings = locale.languageCode == 'en'
        ? fallback
        : await AppLocalizations.loadLanguage(locale.languageCode, reader: reader);
    return AppLocalizations(locale, strings, fallback);
  }

  @override
  bool shouldReload(AppLocalizationsDelegate old) => false;
}
