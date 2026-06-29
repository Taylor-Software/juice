import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/engine/spell.dart';
import 'package:juice_oracle/features/dnd_sheet.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kFireball = SpellEntry(
  id: 'dnd-fireball',
  system: 'dnd',
  name: 'Fireball',
  level: 3,
  school: 'Evocation',
  description: 'Boom.',
);

/// Wizard sheet — isCaster is true so the Spellcasting section renders.
DndSheet _wizardSheet({List<String> spellIds = const []}) => DndSheet(
      className: 'Wizard',
      level: 3,
      abilities: const {
        'str': 10,
        'dex': 14,
        'con': 13,
        'int': 16,
        'wis': 12,
        'cha': 8,
      },
      currentHp: 14,
      maxHp: 14,
      spellIds: spellIds,
    );

Future<ProviderContainer> _pumpDnd(
    WidgetTester tester, DndSheet sheet) async {
  tester.view.physicalSize = const Size(1200, 6000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({
    'juice.sessions.v1':
        '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    'juice.characters.v1.default': jsonEncode([
      {
        'id': 'c1',
        'name': 'Aryn',
        'stats': [],
        'tracks': [],
        'tags': [],
        'dnd': sheet.toJson(),
      }
    ]),
  });
  final container = ProviderContainer(overrides: [
    contentSpellsProvider.overrideWith((ref) async => [_kFireball]),
  ]);
  addTearDown(container.dispose);
  final char = (await container.read(charactersProvider.future)).single;
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Consumer(builder: (_, ref, __) {
          final live =
              ref.watch(charactersProvider).valueOrNull?.firstOrNull ?? char;
          return DndSheetView(character: live, onBack: () {});
        }),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('attach a spell then glance it', (t) async {
    await _pumpDnd(t, _wizardSheet());

    // Spellcasting section is visible for Wizard.
    expect(find.text('Spellcasting'), findsOneWidget);

    // Tap "Add spell".
    await t.tap(find.byKey(const Key('dnd-spell-add')));
    await t.pumpAndSettle();

    // Picker dialog is open; Fireball item is present.
    expect(find.byKey(const Key('dnd-spell-pick-dnd-fireball')), findsOneWidget);

    // Pick Fireball.
    await t.tap(find.byKey(const Key('dnd-spell-pick-dnd-fireball')));
    await t.pumpAndSettle();

    // Fireball now appears in the prepared list.
    expect(find.text('Fireball'), findsWidgets);

    // Tap the Fireball row to glance the SpellCard.
    await t.tap(find.byKey(const Key('dnd-spell-view-dnd-fireball')));
    await t.pumpAndSettle();

    // SpellCard is shown with description.
    expect(find.textContaining('Boom.'), findsOneWidget);
  });

  testWidgets('duplicate add is ignored', (t) async {
    await _pumpDnd(t, _wizardSheet(spellIds: ['dnd-fireball']));

    // Fireball already attached — add again.
    await t.tap(find.byKey(const Key('dnd-spell-add')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('dnd-spell-pick-dnd-fireball')));
    await t.pumpAndSettle();

    // Still only one Fireball row.
    expect(find.byKey(const Key('dnd-spell-view-dnd-fireball')), findsOneWidget);
  });

  testWidgets('remove a spell via delete button', (t) async {
    await _pumpDnd(t, _wizardSheet(spellIds: ['dnd-fireball']));

    expect(find.byKey(const Key('dnd-spell-view-dnd-fireball')), findsOneWidget);

    await t.tap(find.byKey(const Key('dnd-spell-del-dnd-fireball')));
    await t.pumpAndSettle();

    expect(find.byKey(const Key('dnd-spell-view-dnd-fireball')), findsNothing);
  });
}
