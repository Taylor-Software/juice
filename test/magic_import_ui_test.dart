import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loreseer/features/sheet_widgets.dart';
import 'package:loreseer/state/providers.dart';
import 'package:polarity_grammar/polarity_grammar.dart' as pg;
import 'package:shared_preferences/shared_preferences.dart';

String _envelope() => jsonEncode({
      'practicalmagicCharacter': 1,
      'schemaVersion': pg.kSchemaVersion,
      'character': const pg.Character(
              id: 'ext-1', name: 'Vex', baseMana: 6, currentMana: 6)
          .toJson(),
      'spells': [
        pg.Spell(
          id: 'ext-s1',
          characterId: 'ext-1',
          name: 'Spark',
          effects: const [
            pg.EffectChoice(
                pg.CardChoice('effect.sensory.numb', pg.PoleSide.a), 1),
          ],
          form: const pg.CardChoice('form.link', pg.PoleSide.a),
          targets: const [pg.TargetPhrase(count: 1, targetType: 1)],
          size: 0,
          distance: 0,
          timing: 0,
          favorite: false,
          createdAt: DateTime(2026, 1, 1),
          editedAt: DateTime(2026, 1, 1),
        ).toJson(),
      ],
    });

Future<void> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({
    'loreseer.sessions.v1':
        '{"active":"c1","sessions":[{"id":"c1","name":"Test"}]}',
    'loreseer.characters.v1.c1': jsonEncode([
      {
        'id': 'ch1',
        'name': 'Ash',
        'stats': [],
        'tracks': [],
        'tags': [],
        'polarityId': 'pg-1',
      }
    ]),
    'loreseer.magic.v1.c1': jsonEncode({
      'characters': [
        {'id': 'pg-1', 'name': 'Ash', 'baseMana': 4, 'currentMana': 4}
      ],
      'spells': [],
    }),
  });
  final container = ProviderContainer();
  addTearDown(container.dispose);
  final char = (await container.read(charactersProvider.future)).single;
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(
        body: Consumer(builder: (context, ref, __) {
          final live =
              ref.watch(charactersProvider).valueOrNull?.firstOrNull ?? char;
          return SingleChildScrollView(child: magicSection(context, ref, live));
        }),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('import button opens dialog; valid paste imports with undo',
      (tester) async {
    await _pump(tester);

    await tester.scrollUntilVisible(find.byKey(const Key('magic-import')), 200);
    await tester.tap(find.byKey(const Key('magic-import')));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('magic-import-field')), _envelope());
    await tester.tap(find.byKey(const Key('magic-import-confirm')));
    await tester.pumpAndSettle();

    // Dialog closed, snackbar up, spell in the book.
    expect(find.byKey(const Key('magic-import-field')), findsNothing);
    expect(find.text('Imported 1 spell'), findsOneWidget);
    expect(find.text('Spark'), findsOneWidget);

    // Undo removes it again.
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Spark'), findsNothing);
  });

  testWidgets('junk paste shows an inline error and stays open',
      (tester) async {
    await _pump(tester);

    await tester.scrollUntilVisible(find.byKey(const Key('magic-import')), 200);
    await tester.tap(find.byKey(const Key('magic-import')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('magic-import-field')), '{{{');
    await tester.tap(find.byKey(const Key('magic-import-confirm')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('magic-import-error')), findsOneWidget);
    expect(find.text('Not valid JSON'), findsOneWidget);
    // Still open.
    expect(find.byKey(const Key('magic-import-field')), findsOneWidget);
  });
}
