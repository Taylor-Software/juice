import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loreseer/engine/models.dart';
import 'package:loreseer/features/sheet_widgets.dart';
import 'package:loreseer/state/magic_controller.dart';
import 'package:loreseer/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Map<String, Object> baseFixture({
    List<Map<String, Object?>> hanging = const [],
    List<Map<String, Object?>> running = const [],
  }) =>
      {
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
          'schemaVersion': 2,
          'characters': [
            {
              'id': 'pg-1',
              'name': 'Ash',
              'baseMana': 8,
              'currentMana': 8,
              'spellLevel': 3,
            }
          ],
          'spells': [],
          'hanging': hanging,
          'running': running,
        }),
      };

  Future<Character> pumpSection(
      WidgetTester tester, ProviderContainer container) async {
    final char = (await container.read(charactersProvider.future)).single;
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(builder: (context, ref, __) {
            final live =
                ref.watch(charactersProvider).valueOrNull?.firstOrNull ?? char;
            return SingleChildScrollView(
                child: magicSection(context, ref, live));
          }),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return char;
  }

  testWidgets('hanging spell renders HangingList; absent when none',
      (tester) async {
    SharedPreferences.setMockInitialValues(baseFixture());
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await pumpSection(tester, container);

    expect(find.byKey(const Key('hanging-count')), findsNothing);
  });

  testWidgets(
      'a hanging spell shows in HangingList; firing removes it from state',
      (tester) async {
    SharedPreferences.setMockInitialValues(baseFixture(hanging: [
      {
        'id': 'h1',
        'characterId': 'pg-1',
        'spellName': 'Ward the Door',
        'incantation': 'Let none but us pass',
        'cost': 3,
        'trigger': 'when anyone but us crosses this threshold',
        'at': '2026-01-01T00:00:00.000Z',
      }
    ]));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await pumpSection(tester, container);

    expect(find.textContaining('Ward the Door'), findsOneWidget);
    expect(find.byKey(const Key('hanging-fired-h1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('hanging-fired-h1')));
    await tester.pumpAndSettle();

    final lib = container.read(magicProvider).value!;
    expect(lib.hanging.where((h) => h.id == 'h1'), isEmpty);
    expect(find.textContaining('Ward the Door'), findsNothing);
  });

  testWidgets('a hanging spell can be defused, also removing it from state',
      (tester) async {
    SharedPreferences.setMockInitialValues(baseFixture(hanging: [
      {
        'id': 'h2',
        'characterId': 'pg-1',
        'spellName': 'Sense Danger',
        'incantation': 'Warn me',
        'cost': 2,
        'trigger': 'when danger nears',
        'at': '2026-01-01T00:00:00.000Z',
      }
    ]));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await pumpSection(tester, container);

    await tester.tap(find.byKey(const Key('hanging-defused-h2')));
    await tester.pumpAndSettle();

    final lib = container.read(magicProvider).value!;
    expect(lib.hanging.where((h) => h.id == 'h2'), isEmpty);
  });

  testWidgets('running spell renders RunningList; absent when none',
      (tester) async {
    SharedPreferences.setMockInitialValues(baseFixture());
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await pumpSection(tester, container);

    expect(find.byKey(const Key('running-count')), findsNothing);
  });

  testWidgets(
      'a running spell shows in RunningList; ending removes it from state',
      (tester) async {
    SharedPreferences.setMockInitialValues(baseFixture(running: [
      {
        'id': 'r1',
        'characterId': 'pg-1',
        'spellName': 'Glow',
        'incantation': 'Light the way',
        'cost': 1,
        'timing': 1,
        'at': '2026-01-01T00:00:00.000Z',
      }
    ]));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await pumpSection(tester, container);

    expect(find.textContaining('Glow'), findsOneWidget);
    expect(find.byKey(const Key('running-end-r1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('running-end-r1')));
    await tester.pumpAndSettle();

    final lib = container.read(magicProvider).value!;
    expect(lib.running.where((r) => r.id == 'r1'), isEmpty);
    expect(find.textContaining('Glow'), findsNothing);
  });
}
