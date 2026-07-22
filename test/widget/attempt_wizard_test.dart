import 'package:asset_recovery_app/domain/entities/battery.dart';
import 'package:asset_recovery_app/presentation/features/attempt/ticket_actions_hub.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Battery> seededBp(TestEnv env) async {
    final tickets = await env.repository.assignedTickets('FA-RM-01');
    return tickets
        .firstWhere((t) => t.ticketId == 'TKT-48217')
        .batteries
        .firstWhere((b) => b.bpId == 'BP-IF-09823-A');
  }

  testWidgets('hub shows all four free-choice actions, not a forced sequence',
      (tester) async {
    final env = await TestEnv.create();
    final bp = await seededBp(env);
    await tester.pumpWidget(await wrapApp(
        env, TicketActionsHub(ticketId: 'TKT-48217', battery: bp),),);
    await tester.pumpAndSettle();

    expect(find.text('Call Customer'), findsOneWidget);
    expect(find.text('Visit BP Location'), findsOneWidget);
    expect(find.text('Visit Customer Address'), findsOneWidget);
    expect(find.text('Update Status'), findsOneWidget);
    // All start untouched — none are gated behind another.
    expect(find.text('Not started'), findsNWidgets(4));
  });

  testWidgets('opening any action (e.g. Visit BP Location) works without '
      'completing Call first', (tester) async {
    final env = await TestEnv.create();
    final bp = await seededBp(env);
    await tester.pumpWidget(await wrapApp(
        env, TicketActionsHub(ticketId: 'TKT-48217', battery: bp),),);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Visit BP Location'));
    await tester.pumpAndSettle();

    expect(find.text('What happened at the location?'), findsWidgets);
  });

  testWidgets('blocks saving the call action while the call status is empty',
      (tester) async {
    final env = await TestEnv.create();
    final bp = await seededBp(env);
    await tester.pumpWidget(await wrapApp(
        env, TicketActionsHub(ticketId: 'TKT-48217', battery: bp),),);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Call Customer'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pump();
    expect(find.text('This field is required'), findsOneWidget);
  });

  testWidgets('saving the call action marks it done on the hub', (tester) async {
    final env = await TestEnv.create();
    final bp = await seededBp(env);
    await tester.pumpWidget(await wrapApp(
        env, TicketActionsHub(ticketId: 'TKT-48217', battery: bp),),);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Call Customer'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connected').last);
    await tester.pumpAndSettle();

    // callStatus is the only required field now — the call recording button
    // (Rule 8a) replaces the old mandatory screenshot upload.
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();

    // Back on the hub — the Call card is now Done, everything else untouched.
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Not started'), findsNWidgets(3));
  });
}
