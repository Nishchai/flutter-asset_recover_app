import 'package:asset_recovery_app/presentation/shared/widgets/distance_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('DistanceChip renders formatted km', (tester) async {
    final env = await TestEnv.create();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DistanceChip(km: 5.2, palette: env.theme.palette),
        ),
      ),
    );
    expect(find.text('5.2 km'), findsOneWidget);
  });

  testWidgets('DistanceChip shows em-dash when distance unknown', (tester) async {
    final env = await TestEnv.create();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DistanceChip(km: null, palette: env.theme.palette),
        ),
      ),
    );
    expect(find.text('—'), findsOneWidget);
  });
}
