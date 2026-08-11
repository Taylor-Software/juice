import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loreseer/features/sheet_widgets.dart';
import 'package:loreseer/state/magic_controller.dart';
import 'package:loreseer/state/providers.dart';
import 'package:polarity_grammar/polarity_grammar.dart' as pg;
import 'package:shared_preferences/shared_preferences.dart';

/// Pumps `magicSection` for a character already linked to a Polarity Grammar
/// caster with `baseMana: 4, spellLevel: 1` and no `systemId`/`school` —
/// mirrors the hardcoded values `enableMagic` writes at creation, which is
/// exactly the gap this settings dialog closes.
Future<ProviderContainer> _pumpLinked(WidgetTester tester) async {
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
  return container;
}

pg.Character _pgChar(ProviderContainer c) =>
    c.read(magicProvider).value!.characters.single;

void main() {
  testWidgets(
      'magic-settings opens the dialog pre-filled with current Base Mana + '
      'Spell Level, and the Conversion button is absent (no systemId yet)',
      (tester) async {
    await _pumpLinked(tester);

    // Gap confirmed: no systemId was ever set, so Conversion is unreachable.
    expect(find.byKey(const Key('magic-convert')), findsNothing);

    await tester.tap(find.byKey(const Key('magic-settings')));
    await tester.pumpAndSettle();

    expect(find.text('Caster settings'), findsOneWidget);
    expect(find.byKey(const Key('magic-settings-basemana')), findsOneWidget);
    expect(
        tester
            .widget<Text>(find.byKey(const Key('magic-settings-basemana')))
            .data,
        '4');
    expect(
        tester
            .widget<Text>(find.byKey(const Key('magic-settings-spelllevel')))
            .data,
        '1');
  });

  testWidgets(
      'editing Base Mana + Spell Level and saving persists the new values',
      (tester) async {
    final c = await _pumpLinked(tester);

    await tester.tap(find.byKey(const Key('magic-settings')));
    await tester.pumpAndSettle();

    // Base Mana 4 -> 7 (three taps of +).
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const Key('magic-settings-basemana-plus')));
      await tester.pump();
    }
    // Spell Level 1 -> 3 (two taps of +).
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byKey(const Key('magic-settings-spelllevel-plus')));
      await tester.pump();
    }

    expect(
        tester
            .widget<Text>(find.byKey(const Key('magic-settings-basemana')))
            .data,
        '7');
    expect(
        tester
            .widget<Text>(find.byKey(const Key('magic-settings-spelllevel')))
            .data,
        '3');

    await tester.tap(find.byKey(const Key('magic-settings-save')));
    await tester.pumpAndSettle();

    final updated = _pgChar(c);
    expect(updated.baseMana, 7);
    expect(updated.spellLevel, 3);
  });

  testWidgets(
      'picking a game system and saving unlocks the Conversion Calculator '
      'button', (tester) async {
    await _pumpLinked(tester);

    expect(find.byKey(const Key('magic-convert')), findsNothing);

    await tester.tap(find.byKey(const Key('magic-settings')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('magic-settings-system')));
    await tester.pumpAndSettle();
    // Pick D&D 5e from the opened dropdown menu.
    await tester.tap(find.text('D&D 5e').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('magic-settings-save')));
    await tester.pumpAndSettle();

    // The gap this task closes: systemId now set -> Conversion button renders.
    expect(find.byKey(const Key('magic-convert')), findsOneWidget);
  });

  testWidgets('School + Gated casting + Enforce school toggles persist',
      (tester) async {
    final c = await _pumpLinked(tester);

    await tester.tap(find.byKey(const Key('magic-settings')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('magic-settings-school')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(pg.School.arcane.label).last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('magic-settings-gated')));
    await tester.tap(find.byKey(const Key('magic-settings-enforceschool')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('magic-settings-save')));
    await tester.pumpAndSettle();

    final updated = _pgChar(c);
    expect(updated.school, pg.School.arcane);
    expect(updated.gatedCasting, isTrue);
    expect(updated.enforceSchool, isTrue);
  });

  testWidgets('Cancel discards edits', (tester) async {
    final c = await _pumpLinked(tester);

    await tester.tap(find.byKey(const Key('magic-settings')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('magic-settings-basemana-plus')));
    await tester.pump();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    final updated = _pgChar(c);
    expect(updated.baseMana, 4);
  });
}
