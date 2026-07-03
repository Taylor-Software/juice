import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/features/encounter_screen.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _enc(List<Map<String, dynamic>> cs) =>
    jsonEncode({'combatants': cs, 'turnIndex': 0, 'round': 1});

Map<String, dynamic> _c(
  String id,
  String name,
  int init, {
  int ac = 0,
  Map<String, dynamic>? track,
  List<Map<String, dynamic>> attacks = const [],
}) =>
    {
      'id': id,
      'name': name,
      'characterId': null,
      'initiative': init,
      'track': track,
      'tags': <String>[],
      'defeated': false,
      if (ac != 0 || attacks.isNotEmpty)
        'statBlock': {
          if (ac != 0) 'ac': ac,
          if (attacks.isNotEmpty) 'attacks': attacks,
        },
    };

void main() {
  // Pumps EncounterScreen under the REAL AppTheme (so the dialog's
  // FilledButton-beside-Expanded rows are guarded against infinite-width) with a
  // file-loaded oracle (the attack/damage dice need it).
  Future<ProviderContainer> pump(WidgetTester t, String encJson,
      {Size size = const Size(1000, 1000)}) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.encounter.v1.default': encJson,
    });
    final oracle = Oracle(OracleData(
        jsonDecode(File('assets/oracle_data.json').readAsStringSync())
            as Map<String, dynamic>));
    final c = ProviderContainer(
        overrides: [oracleProvider.overrideWith((ref) async => oracle)]);
    addTearDown(c.dispose);
    await c.read(oracleProvider.future);
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: EncounterScreen())),
    ));
    await t.pumpAndSettle();
    return c;
  }

  testWidgets('auto-hit vs low AC applies damage and logs a combat entry',
      (t) async {
    final c = await pump(
        t,
        _enc([
          _c('g', 'Goblin', 15, attacks: [
            {'name': 'Scimitar', 'detail': '1d6'}
          ]),
          _c('m', 'Mira', 10,
              ac: 1, track: {'label': 'HP', 'current': 10, 'max': 10}),
        ]));

    await t.tap(find.byKey(const Key('enc-attack-g')));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull); // dialog lays out under AppTheme

    // 1d20 always >= AC 1 => auto Hit; the damage step appears.
    await t.tap(find.byKey(const Key('attack-roll-go')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('attack-apply')), findsOneWidget);

    await t.tap(find.byKey(const Key('attack-apply')));
    await t.pumpAndSettle();

    final entries = c.read(journalProvider).valueOrNull ?? const [];
    expect(entries.single.sourceTool, 'combat');
    expect(entries.single.body, contains('Hit'));
    final mira = (await c.read(encounterProvider.future))
        .combatants
        .firstWhere((x) => x.id == 'm');
    expect(mira.track!.current, lessThan(10));
  });

  testWidgets('auto-miss vs high AC logs a miss and leaves HP untouched',
      (t) async {
    final c = await pump(
        t,
        _enc([
          _c('g', 'Goblin', 15),
          _c('m', 'Mira', 10,
              ac: 30, track: {'label': 'HP', 'current': 10, 'max': 10}),
        ]));

    await t.tap(find.byKey(const Key('enc-attack-g')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('attack-roll-go')));
    await t.pumpAndSettle();

    // 1d20 < AC 30 => Miss: no damage step, a Log-miss action instead.
    expect(find.byKey(const Key('attack-apply')), findsNothing);
    expect(find.byKey(const Key('attack-log-miss')), findsOneWidget);

    await t.tap(find.byKey(const Key('attack-log-miss')));
    await t.pumpAndSettle();

    final entries = c.read(journalProvider).valueOrNull ?? const [];
    expect(entries.single.body, contains('Miss'));
    final mira = (await c.read(encounterProvider.future))
        .combatants
        .firstWhere((x) => x.id == 'm');
    expect(mira.track!.current, 10); // unchanged
  });

  testWidgets('unknown AC (0) prompts a manual Hit/Miss choice', (t) async {
    final c = await pump(
        t,
        _enc([
          _c('g', 'Goblin', 15),
          _c('m', 'Mira', 10,
              track: {'label': 'HP', 'current': 10, 'max': 10}), // ac 0
        ]));

    await t.tap(find.byKey(const Key('enc-attack-g')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('attack-roll-go')));
    await t.pumpAndSettle();

    // No AC => the GM decides.
    expect(find.byKey(const Key('attack-hit')), findsOneWidget);
    expect(find.byKey(const Key('attack-miss')), findsOneWidget);

    await t.tap(find.byKey(const Key('attack-hit')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('attack-apply')));
    await t.pumpAndSettle();

    final mira = (await c.read(encounterProvider.future))
        .combatants
        .firstWhere((x) => x.id == 'm');
    expect(mira.track!.current, lessThan(10));
  });

  testWidgets('row with the attack button does not overflow when narrow',
      (t) async {
    await pump(
        t,
        _enc([
          _c('g', 'Grizzled Veteran Longname', 15,
              ac: 14, track: {'label': 'HP', 'current': 8, 'max': 8}),
          _c('m', 'Mira', 10,
              ac: 12, track: {'label': 'HP', 'current': 10, 'max': 10}),
        ]),
        size: const Size(380, 800));
    // The attack button is present and the row lays out without overflow.
    expect(find.byKey(const Key('enc-attack-g')), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('tapping a stat-block attack chip fills the dice fields',
      (t) async {
    final c = await pump(
        t,
        _enc([
          _c('g', 'Goblin', 15, attacks: [
            {'name': 'Bite', 'detail': '1d20+4, 2d6+2'}
          ]),
          _c('m', 'Mira', 10,
              ac: 1, track: {'label': 'HP', 'current': 10, 'max': 10}),
        ]));

    await t.tap(find.byKey(const Key('enc-attack-g')));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const Key('attack-pick-0')));
    await t.pumpAndSettle();

    // The attack field is always visible; it now holds the parsed attack die.
    expect(
        t
            .widget<TextField>(find.byKey(const Key('attack-roll')))
            .controller!
            .text,
        '1d20+4');

    // Roll (1d20+4 vs AC 1 => hit) reveals the damage field, prefilled too.
    await t.tap(find.byKey(const Key('attack-roll-go')));
    await t.pumpAndSettle();
    expect(
        t
            .widget<TextField>(find.byKey(const Key('attack-damage')))
            .controller!
            .text,
        '2d6+2');

    await t.tap(find.byKey(const Key('attack-apply')));
    await t.pumpAndSettle();
    final mira = (await c.read(encounterProvider.future))
        .combatants
        .firstWhere((x) => x.id == 'm');
    expect(mira.track!.current, lessThan(10));
  });
}
