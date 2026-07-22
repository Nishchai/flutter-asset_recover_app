import 'package:asset_recovery_app/app/asset_recovery_app.dart';
import 'package:asset_recovery_app/core/localization/locale_provider.dart';
import 'package:asset_recovery_app/presentation/features/home/widgets/ticket_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/test_harness.dart';

/// End-to-end happy path against the real app widget tree:
/// login → open a ticket → BP detail → Call Customer → complete the
/// config-driven documentation wizard (Call → Location → Battery → Outcome →
/// Review) with an Organic Swap → submit. Runs on the zero-latency mock backend.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> selectOption(WidgetTester tester, String optionLabel) async {
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(optionLabel).last);
    await tester.pumpAndSettle();
  }

  Future<void> captureProofIfPresent(WidgetTester tester) async {
    final proof = find.text('Click a photo');
    if (proof.evaluate().isNotEmpty) {
      await tester.tap(proof.first);
      await tester.pumpAndSettle();
    }
  }

  Future<void> tapNext(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(ElevatedButton, 'Next'));
    await tester.pumpAndSettle();
  }

  testWidgets('agent completes an organic-swap recovery end to end',
      (tester) async {
    final env = await TestEnv.create();
    final localeProvider = LocaleProvider(
      defaultLanguage: 'en',
      supportedLanguages: env.config.supportedLanguages,
    );

    await tester.pumpWidget(
      AssetRecoveryApp(localeProvider: localeProvider),
    );
    await tester.pumpAndSettle();

    // 1. Login
    await tester.tap(find.widgetWithText(ElevatedButton, 'Log in'));
    await tester.pumpAndSettle();
    expect(find.text('Rohan M.'), findsOneWidget);

    // 2. Open a ticket → BP detail
    await tester.tap(find.byType(TicketCard).first);
    await tester.pumpAndSettle();
    expect(find.text('BATTERY PACK'), findsOneWidget);

    // 3. Start the recovery documentation flow
    await tester.tap(find.text('Call Customer'));
    await tester.pumpAndSettle();
    expect(find.text('Call Documentation'), findsWidgets);

    // 4. Step 1 — Call Documentation
    await selectOption(tester, 'Connected');
    await captureProofIfPresent(tester);
    await tapNext(tester);

    // 5. Step 2 — Location Documentation
    await selectOption(tester, 'Yes, I saw a customer');
    await captureProofIfPresent(tester);
    await tapNext(tester);

    // 6. Step 3 — Battery Documentation
    await selectOption(tester, 'Yes, I saw a customer');
    await captureProofIfPresent(tester);
    await tapNext(tester);

    // 7. Step 4 — Outcome: Organic Swap
    await selectOption(tester, 'Swap (Organic)');
    await tapNext(tester);

    // 8. Step 5 — Review & Submit
    await tester.tap(find.widgetWithText(ElevatedButton, 'Submit Attempt'));
    await tester.pumpAndSettle();

    // Back on BP detail after submission.
    expect(find.text('BATTERY PACK'), findsOneWidget);
  });
}
