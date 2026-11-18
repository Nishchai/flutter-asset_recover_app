import 'package:asset_recovery_app/core/config/environment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EnvironmentConfig.enableBatteryMovementReport', () {
    test('true shows the feature', () {
      final env = EnvironmentConfig.fromJson(
          {'enableBatteryMovementReport': true},);
      expect(env.enableBatteryMovementReport, isTrue);
    });

    test('false, or a missing key, hides it', () {
      expect(
        EnvironmentConfig.fromJson({'enableBatteryMovementReport': false})
            .enableBatteryMovementReport,
        isFalse,
      );
      expect(
        EnvironmentConfig.fromJson(const {}).enableBatteryMovementReport,
        isFalse,
      );
    });
  });
}
