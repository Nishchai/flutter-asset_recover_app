import 'package:asset_recovery_app/core/config/config_service.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

void main() {
  // rootBundle access requires an initialized binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  late ConfigService config;

  setUpAll(() async {
    config = await ConfigService.load(
      environment: 'test',
      reader: rootBundle.loadString,
    );
  });

  test('loads business values from app_config.json', () {
    expect(config.slaDays, 90);
    expect(config.maxAttemptsPerBp, 3);
    expect(config.autoLogoutHours, 8);
    expect(config.geofenceRadiusMeters, 50);
  });

  test('dotted-path flag lookups work', () {
    expect(config.flag('proof.mandatoryForCall'), isTrue);
    expect(config.flag('features.multiLanguage'), isTrue);
    expect(config.flag('does.not.exist'), isFalse);
  });

  test('exposes all 6 supported languages', () {
    expect(config.supportedLanguages, hasLength(6));
    expect(config.supportedLanguages, containsAll(['en', 'hi', 'ta', 'te', 'kn', 'mr']));
  });

  test('outcome options carry resolution + approval metadata', () {
    // Swap is intentionally absent — it's system/TIU-detected, never a
    // Field Agent choice (Rule 1). FIR and Not Found/Refused ("Lost" folded
    // in) are separate (Rule 2); Customer Not Cooperating is a distinct
    // terminal outcome (Rule 6). 4 outcomes are FA-selectable.
    final outcomes = config.options('outcome');
    expect(outcomes, hasLength(4));
    expect(
      outcomes.map((o) => o.value),
      ['recovered', 'fir', 'not_found_refused', 'customer_not_cooperating'],
    );
    final recovered = config.optionByValue('outcome', 'recovered')!;
    expect(recovered.stringExtra('resolution'), 'Recovered');
    expect(recovered.boolExtra('requiresApproval'), isTrue);
    expect(recovered.boolExtra('requiresOtp'), isTrue);

    final notCooperating = config.optionByValue('outcome', 'customer_not_cooperating')!;
    expect(notCooperating.boolExtra('requiresApproval'), isFalse);
  });

  test('test environment forces deterministic seed + mock data', () {
    expect(config.env.environment, 'test');
    expect(config.env.useMockData, isTrue);
    expect(config.env.deterministicSeed, 42);
  });

  test('navigation items come from config', () {
    final ids = config.navItems.map((e) => e['id']).toList();
    expect(ids, ['tasks', 'map', 'profile']);
  });
}
