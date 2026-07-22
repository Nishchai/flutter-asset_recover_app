import 'package:asset_recovery_app/presentation/features/home/task_list_screen.dart';
import 'package:asset_recovery_app/presentation/features/home/widgets/ticket_card.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows shift header, agent and assigned tickets', (tester) async {
    final env = await TestEnv.create();
    await tester.pumpWidget(await wrapApp(env, const TaskListScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Rohan M.'), findsOneWidget);
    expect(find.text('My Tickets'), findsOneWidget);
    expect(find.text('TKT-48217'), findsWidgets);
    expect(find.text('BP-IF-09823-A'), findsWidgets);
    expect(find.byType(TicketCard), findsWidgets);
  });

  testWidgets('shift stats render the header counters', (tester) async {
    final env = await TestEnv.create();
    await tester.pumpWidget(await wrapApp(env, const TaskListScreen()));
    await tester.pumpAndSettle();

    expect(find.text('27'), findsOneWidget); // assigned
    expect(find.text('16'), findsOneWidget); // in progress
    expect(find.text('11'), findsOneWidget); // pending
  });

  testWidgets('In Progress tab shows the FIR-pending ticket', (tester) async {
    // FIR/Recovered outcomes await AC approval (item 12) and surface under
    // "In Progress", not a separate "Pending" tab (item 1's 3-tab redesign).
    final env = await TestEnv.create();
    await tester.pumpWidget(await wrapApp(env, const TaskListScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('In Progress'));
    await tester.pumpAndSettle();
    expect(find.text('BP-IF-10097-P'), findsWidgets);
  });
}
