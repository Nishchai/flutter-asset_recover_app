import 'package:asset_recovery_app/core/localization/app_localizations.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('English loads the full key set', () async {
    final en = await AppLocalizations.loadLanguage('en', reader: rootBundle.loadString);
    expect(en['wizard.title'], 'Submit Attempt');
    expect(en['nav.tasks'], 'Home');
    expect(en['shift.active'], 'SHIFT ACTIVE');
  });

  test('Hindi overrides core strings', () async {
    final hi = await AppLocalizations.loadLanguage('hi', reader: rootBundle.loadString);
    expect(hi['wizard.title'], isNotNull);
    expect(hi['wizard.title'], isNot('Submit Attempt'));
  });

  test('partial languages fall back to English for missing keys', () async {
    final en = await AppLocalizations.loadLanguage('en', reader: rootBundle.loadString);
    final ta = await AppLocalizations.loadLanguage('ta', reader: rootBundle.loadString);
    final l = AppLocalizations(const Locale('ta'), ta, en);
    // 'wizard.title' exists in Tamil…
    expect(l.t('wizard.title'), ta['wizard.title']);
    // …but a key only present in English falls back cleanly (no crash, no key echo).
    expect(l.t('attempt.success'), en['attempt.success']);
  });

  test('placeholder interpolation works', () async {
    final en = await AppLocalizations.loadLanguage('en', reader: rootBundle.loadString);
    final l = AppLocalizations(const Locale('en'), en, en);
    expect(l.t('card.daysLeft', {'days': 87}), '87 Days Left');
  });

  test('all six languages load without error', () async {
    for (final code in ['en', 'hi', 'ta', 'te', 'kn', 'mr']) {
      final map = await AppLocalizations.loadLanguage(code, reader: rootBundle.loadString);
      expect(map, isNotEmpty, reason: '$code should have strings');
      expect(map['nav.tasks'], isNotNull, reason: '$code missing nav.tasks');
    }
  });
}
