import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juice_oracle/features/encounter_screen.dart';
import 'package:juice_oracle/state/providers.dart';

Map<String, dynamic> _c(
  String id,
  String name,
  int init, {
  bool defeated = false,
  String? characterId,
  Map<String, dynamic>? track,
  List<String> tags = const [],
}) =>
    <String, dynamic>{
      'id': id,
      'name': name,
      'characterId': characterId,
      'initiative': init,
      'track': track,
      'tags': tags,
      'defeated': defeated,
    };

String _enc(List<Map<String, dynamic>> combatants,
        {int turnIndex = 0, int round = 1}) =>
    jsonEncode(
        {'combatants': combatants, 'turnIndex': turnIndex, 'round': round});

void main() {
  Future<ProviderContainer> pump(
    WidgetTester tester, {
    String? encounterJson,
    String? charactersJson,
  }) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      if (charactersJson != null) 'juice.characters.v1.default': charactersJson,
      if (encounterJson != null) 'juice.encounter.v1.default': encounterJson,
    });
    await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: Scaffold(body: EncounterScreen()))));
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
        tester.element(find.byType(EncounterScreen)));
  }

  ListTile tileOf(WidgetTester tester, String combatantId) =>
      tester.widget<ListTile>(find.descendant(
          of: find.byKey(ValueKey(combatantId)),
          matching: find.byType(ListTile)));

  testWidgets('seeded combatants render in order; round header; turn row 0',
      (tester) async {
    await pump(tester,
        encounterJson: _enc([
          _c('w', 'Wolf', 18,
              track: {'label': 'HP', 'current': 5, 'max': 5}),
          _c('g', 'Goblin', 12,
              track: {'label': 'HP', 'current': 4, 'max': 6}),
        ]));
    expect(find.text('Round 1'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Wolf')).dy,
        lessThan(tester.getTopLeft(find.text('Goblin')).dy));
    expect(tileOf(tester, 'w').selected, isTrue);
    expect(tileOf(tester, 'g').selected, isFalse);
  });

  testWidgets('Next turn skips defeated and wraps with round increment',
      (tester) async {
    await pump(tester,
        encounterJson: _enc([
          _c('a', 'A', 20),
          _c('b', 'B', 15, defeated: true),
          _c('c', 'C', 10),
        ]));
    await tester.tap(find.byKey(const Key('next-turn')));
    await tester.pumpAndSettle();
    expect(tileOf(tester, 'c').selected, isTrue);
    await tester.tap(find.byKey(const Key('next-turn')));
    await tester.pumpAndSettle();
    expect(tileOf(tester, 'a').selected, isTrue);
    expect(find.text('Round 2'), findsOneWidget);
  });

  testWidgets('ad-hoc stepper updates track text and persists',
      (tester) async {
    final container = await pump(tester,
        encounterJson: _enc([
          _c('g', 'Goblin', 12,
              track: {'label': 'HP', 'current': 4, 'max': 6}),
        ]));
    expect(find.text('4/6'), findsOneWidget);
    await tester.tap(find.byKey(const Key('enc-plus-0')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<Text>(find.byKey(const Key('enc-track-0')))
            .data,
        '5/6');
    final s = await container.read(encounterProvider.future);
    expect(s.combatants.single.track!.current, 5);
  });

  testWidgets('linked stepper writes through to the character',
      (tester) async {
    final container = await pump(
      tester,
      charactersJson:
          '[{"id":"c1","name":"Ash","note":"","stats":[],"tracks":[{"label":"HP","current":7,"max":10}],"tags":[]}]',
      encounterJson: _enc([_c('l1', 'Ash', 17, characterId: 'c1')]),
    );
    expect(find.text('7/10'), findsOneWidget);
    await tester.tap(find.byKey(const Key('enc-plus-0')));
    await tester.pumpAndSettle();
    final chars = await container.read(charactersProvider.future);
    expect(chars.single.tracks.single.current, 8);
    expect(
        tester
            .widget<Text>(find.byKey(const Key('enc-track-0')))
            .data,
        '8/10');
  });

  testWidgets('End encounter writes journal summary and resets',
      (tester) async {
    final container = await pump(tester,
        encounterJson: _enc([
          _c('a', 'A', 20),
          _c('g', 'Goblin', 12, defeated: true),
        ], round: 3));
    await tester.tap(find.byKey(const Key('end-encounter')));
    await tester.pumpAndSettle();
    expect(find.text('End encounter?'), findsOneWidget);
    await tester.tap(find.text('End'));
    await tester.pumpAndSettle();
    final journal = await container.read(journalProvider.future);
    expect(journal.single.title, 'Encounter ended');
    expect(journal.single.body, 'Round 3 — defeated: Goblin');
    final s = await container.read(encounterProvider.future);
    expect(s.combatants, isEmpty);
    expect(s.round, 1);
    expect(find.text('Added to journal'), findsOneWidget);
    // Drain the snackbar timer.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('defeat toggle strikes the name and Next skips it',
      (tester) async {
    await pump(tester,
        encounterJson: _enc([
          _c('a', 'A', 20),
          _c('b', 'B', 10),
        ]));
    await tester.tap(find.byKey(const Key('enc-defeat-1')));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.text('B')).style?.decoration,
        TextDecoration.lineThrough);
    await tester.tap(find.byKey(const Key('next-turn')));
    await tester.pumpAndSettle();
    // B skipped: pointer wraps back to A and the round advances.
    expect(tileOf(tester, 'a').selected, isTrue);
    expect(find.text('Round 2'), findsOneWidget);
  });

  testWidgets('drag reorder persists new order and turn pointer follows',
      (tester) async {
    final container = await pump(tester,
        encounterJson: _enc([
          _c('a', 'A', 20),
          _c('b', 'B', 15),
          _c('c', 'C', 10),
        ]));
    // Long-press drag A down one slot (incremental moves so the reorder
    // gap tracks the pointer): order becomes B, A, C.
    final from = tester.getCenter(find.byKey(const ValueKey('a')));
    final rowHeight = tester.getCenter(find.byKey(const ValueKey('b'))).dy -
        from.dy;
    final gesture = await tester.startGesture(from);
    await tester.pump(kLongPressTimeout + kPressTimeout);
    var moved = 0.0;
    while (moved < rowHeight + 15) {
      await gesture.moveBy(const Offset(0, 10));
      moved += 10;
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    final s = await container.read(encounterProvider.future);
    expect(s.combatants.map((c) => c.id), ['b', 'a', 'c']);
    // Pointer was on A (turn 0) and follows it to index 1.
    expect(s.turnIndex, 1);
    expect(tileOf(tester, 'a').selected, isTrue);
  });

  testWidgets('status tag add persists; chip delete removes it',
      (tester) async {
    final container = await pump(tester,
        encounterJson: _enc([
          _c('g', 'Goblin', 12,
              track: {'label': 'HP', 'current': 4, 'max': 6}),
        ]));
    await tester.tap(find.byKey(const Key('enc-tag-add-0')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('enc-tag-input')), 'stunned');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('stunned'), findsOneWidget);
    var s = await container.read(encounterProvider.future);
    expect(s.combatants.single.tags, ['stunned']);
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('stunned'), findsNothing);
    s = await container.read(encounterProvider.future);
    expect(s.combatants.single.tags, isEmpty);
  });
}
