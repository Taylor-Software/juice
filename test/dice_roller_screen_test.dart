import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/features/dice_roller_screen.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> pump(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    });
    await tester.pumpWidget(ProviderScope(
        child:
            MaterialApp(home: Scaffold(body: DiceRollerScreen(dice: Dice())))));
    await tester.pumpAndSettle();
  }

  testWidgets('chips build expressions; repeat tap increments', (tester) async {
    await pump(tester);
    await tester.tap(find.widgetWithText(ActionChip, 'd6'));
    await tester.pump();
    expect(find.widgetWithText(TextField, 'd6'), findsOneWidget);
    await tester.tap(find.widgetWithText(ActionChip, 'd6'));
    await tester.pump();
    expect(find.widgetWithText(TextField, '2d6'), findsOneWidget);
    await tester.tap(find.widgetWithText(ActionChip, 'd20'));
    await tester.pump();
    expect(find.widgetWithText(TextField, '2d6+d20'), findsOneWidget);
  });

  testWidgets('invalid input shows error and disables Roll', (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(const Key('dice-input')), '2d6++3');
    await tester.pump();
    expect(find.textContaining('position'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.ancestor(
        of: find.text('Roll'),
        matching: find.byWidgetPredicate((w) => w is FilledButton)));
    expect(button.onPressed, isNull);
  });

  testWidgets('dice add-to-journal sets sourceTool and payload summary',
      (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(const Key('dice-input')), '2d6+3');
    await tester.pump();
    await tester.tap(find.text('Roll'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add to journal'));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
        tester.element(find.byType(DiceRollerScreen)));
    final entries = await container.read(journalProvider.future);
    expect(entries.single.sourceTool, 'dice');
    final summary = entries.single.payload?['summary'] as String?;
    expect(summary, isNotNull);
    expect(summary, matches(RegExp(r'^2d6\+3 = \d+$')));
  });

  testWidgets('roll renders breakdown and total; history rerolls; journal add',
      (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(const Key('dice-input')), '2d6+3');
    await tester.pump();
    await tester.tap(find.text('Roll'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dice-total')), findsOneWidget);
    expect(find.textContaining('2d6'), findsWidgets);
    await tester.tap(find.byKey(const Key('dice-history-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dice-total')), findsOneWidget);
    expect(find.byKey(const Key('dice-history-1')), findsOneWidget); // grew
    await tester.tap(find.byTooltip('Add to journal'));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
        tester.element(find.byType(DiceRollerScreen)));
    final entries = await container.read(journalProvider.future);
    expect(entries.single.title, 'Dice Roll');
    expect(entries.single.body, contains('= '));
  });
}
