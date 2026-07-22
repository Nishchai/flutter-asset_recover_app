import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the active [Locale] and persists the user's choice.
///
/// Language switching from Profile updates this provider; [MaterialApp]
/// rebuilds with the new locale. Persisted via SharedPreferences so the
/// selection survives restarts.
class LocaleProvider extends ChangeNotifier {
  LocaleProvider({
    required String defaultLanguage,
    required this.supportedLanguages,
  }) : _locale = Locale(defaultLanguage);

  static const _prefsKey = 'app_locale';

  final List<String> supportedLanguages;
  Locale _locale;

  Locale get locale => _locale;

  Future<void> loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    if (saved != null && supportedLanguages.contains(saved)) {
      _locale = Locale(saved);
      notifyListeners();
    }
  }

  Future<void> setLanguage(String code) async {
    if (!supportedLanguages.contains(code) || code == _locale.languageCode) {
      return;
    }
    _locale = Locale(code);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, code);
  }

  List<Locale> get supportedLocales =>
      supportedLanguages.map(Locale.new).toList();
}
