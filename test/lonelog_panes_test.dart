import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/features/battle_pane.dart';
import 'package:juice_oracle/features/resources_pane.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The two Lonelog addon panes sat at ~1% line coverage with no test importing
/// them. They are ordinary widget code — nothing platform-bound — so the gap
/// was just a gap.
Future<ProviderContainer> _pump(WidgetTester tester, Widget pane) async {
  SharedPreferences.setMockInitialValues({
    'juice.sessions.v1':
        '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
  });
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: pane),
    ),
  ));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  group('ResourcesPane', () {
    testWidgets('starts empty', (tester) async {
      await _pump(tester, const ResourcesPane());
      expect(find.text('No items yet.'), findsOneWidget);
    });

    testWidgets('adding an item persists it and clears the field',
        (tester) async {
      final c = await _pump(tester, const ResourcesPane());
      await tester.enterText(find.byKey(const Key('inv-add')), 'Rope');
      await tester.tap(find.byKey(const Key('inv-add-btn')));
      await tester.pumpAndSettle();

      final items = c.read(inventoryProvider).valueOrNull ?? const <InvItem>[];
      expect(items.single.name, 'Rope');
      expect(items.single.qty, 1);
      expect(find.text('No items yet.'), findsNothing);
      expect(
          tester
              .widget<TextField>(find.byKey(const Key('inv-add')))
              .controller!
              .text,
          isEmpty);
    });

    testWidgets('a blank name is refused', (tester) async {
      final c = await _pump(tester, const ResourcesPane());
      await tester.enterText(find.byKey(const Key('inv-add')), '   ');
      await tester.tap(find.byKey(const Key('inv-add-btn')));
      await tester.pumpAndSettle();
      expect(c.read(inventoryProvider).valueOrNull ?? const [], isEmpty);
    });

    testWidgets('quantity steps up and down, and the row shows the count',
        (tester) async {
      final c = await _pump(tester, const ResourcesPane());
      await tester.enterText(find.byKey(const Key('inv-add')), 'Torch');
      await tester.tap(find.byKey(const Key('inv-add-btn')));
      await tester.pumpAndSettle();

      // Scope to the row: the add-item button also renders an Icons.add.
      final id = c.read(inventoryProvider).valueOrNull!.single.id;
      final row = find.byKey(Key('inv-$id'));
      Finder inRow(IconData icon) =>
          find.descendant(of: row, matching: find.byIcon(icon));

      // A single item shows no multiplier; two show '×2'.
      expect(find.text('Torch'), findsOneWidget);
      await tester.tap(inRow(Icons.add));
      await tester.pumpAndSettle();
      expect(find.text('Torch ×2'), findsOneWidget);

      await tester.tap(inRow(Icons.remove));
      await tester.pumpAndSettle();
      expect(find.text('Torch'), findsOneWidget);
      expect((c.read(inventoryProvider).valueOrNull!).single.qty, 1);
    });

    testWidgets('an item can be deleted', (tester) async {
      final c = await _pump(tester, const ResourcesPane());
      await tester.enterText(find.byKey(const Key('inv-add')), 'Rations');
      await tester.tap(find.byKey(const Key('inv-add-btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      expect(c.read(inventoryProvider).valueOrNull, isEmpty);
      expect(find.text('No items yet.'), findsOneWidget);
    });

    testWidgets('tapping a row edits its properties', (tester) async {
      final c = await _pump(tester, const ResourcesPane());
      await tester.enterText(find.byKey(const Key('inv-add')), 'Blade');
      await tester.tap(find.byKey(const Key('inv-add-btn')));
      await tester.pumpAndSettle();

      final id = c.read(inventoryProvider).valueOrNull!.single.id;
      await tester.tap(find.byKey(Key('inv-$id')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('inv-props-input')), 'notched');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(c.read(inventoryProvider).valueOrNull!.single.props, 'notched');
      expect(find.text('notched'), findsOneWidget);
    });
  });

  group('BattlePane', () {
    testWidgets('adding a unit persists it', (tester) async {
      final c = await _pump(tester, const BattlePane());
      await tester.enterText(find.byKey(const Key('unit-add')), 'Shield Wall');
      await tester.tap(find.byKey(const Key('unit-add-btn')));
      await tester.pumpAndSettle();

      final units = c.read(unitsProvider).valueOrNull ?? const <Unit>[];
      expect(units.single.name, 'Shield Wall');
    });

    testWidgets('a blank unit name is refused', (tester) async {
      final c = await _pump(tester, const BattlePane());
      await tester.enterText(find.byKey(const Key('unit-add')), '  ');
      await tester.tap(find.byKey(const Key('unit-add-btn')));
      await tester.pumpAndSettle();
      expect(c.read(unitsProvider).valueOrNull ?? const [], isEmpty);
    });

    testWidgets('tapping a unit edits its size', (tester) async {
      final c = await _pump(tester, const BattlePane());
      await tester.enterText(find.byKey(const Key('unit-add')), 'Skirmishers');
      await tester.tap(find.byKey(const Key('unit-add-btn')));
      await tester.pumpAndSettle();

      final id = c.read(unitsProvider).valueOrNull!.single.id;
      await tester.tap(find.byKey(Key('unit-$id')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('unit-size-input')), '12');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(c.read(unitsProvider).valueOrNull!.single.size, '12');
    });

    testWidgets('the journal button writes a BATTLE block', (tester) async {
      final c = await _pump(tester, const BattlePane());
      await tester.enterText(find.byKey(const Key('unit-add')), 'Vanguard');
      await tester.tap(find.byKey(const Key('unit-add-btn')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('battle-to-journal')));
      await tester.pumpAndSettle();

      final entries =
          c.read(journalProvider).valueOrNull ?? const <JournalEntry>[];
      expect(entries, isNotEmpty);
      expect(entries.first.body, contains('BATTLE'));
      expect(entries.first.body, contains('Vanguard'));
    });
  });
}
