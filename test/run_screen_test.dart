import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/features/run_screen.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/interpreter.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

import 'fake_interpreter.dart';

const _sid = 'default';

OracleData _loadData() =>
    OracleData(jsonDecode(File('assets/oracle_data.json').readAsStringSync())
        as Map<String, dynamic>);

Map<String, Object> _prefs({
  String? journalJson,
  String? charsJson,
  String? encounterJson,
  String? crawlJson,
  String? contextJson,
}) =>
    {
      'juice.sessions.v1':
          '{"active":"$_sid","sessions":[{"id":"$_sid","name":"C1"}]}',
      if (journalJson != null) 'juice.journal.v2.$_sid': journalJson,
      if (charsJson != null) 'juice.characters.v1.$_sid': charsJson,
      if (encounterJson != null) 'juice.encounter.v1.$_sid': encounterJson,
      if (crawlJson != null) 'juice.crawl.v1.$_sid': crawlJson,
      if (contextJson != null) 'juice.context.v1.$_sid': contextJson,
    };

Future<ProviderContainer> _pump(
  WidgetTester tester,
  OracleData data,
  Map<String, Object> prefs, {
  Size size = const Size(1000, 2200),
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final oracle = Oracle(data, Dice(Random(1)));
  final container = ProviderContainer(overrides: [
    oracleProvider.overrideWith((ref) async => oracle),
    interpreterServiceProvider.overrideWithValue(FakeInterpreterService()),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: RunScreen())),
  ));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  late OracleData data;
  setUpAll(() => data = _loadData());

  testWidgets('run-screen renders the four panel headers', (tester) async {
    await _pump(tester, data, _prefs());
    expect(find.byKey(const Key('run-screen')), findsOneWidget);
    expect(find.byKey(const Key('run-panel-initiative')), findsOneWidget);
    expect(find.byKey(const Key('run-panel-party')), findsOneWidget);
    expect(find.byKey(const Key('run-panel-scene')), findsOneWidget);
    expect(find.byKey(const Key('run-panel-dice')), findsOneWidget);
    expect(find.byKey(const Key('run-panel-capture')), findsOneWidget);
  });

  testWidgets('initiative: next turn advances; roll-all fills unset', (tester) async {
    const enc =
        '{"combatants":[{"id":"a","name":"Ash","initiative":15,"track":{"current":5,"max":5},"tags":[],"defeated":false},{"id":"b","name":"Bog","initiative":0,"track":{"current":4,"max":4},"tags":[],"defeated":false}],"turnIndex":0,"round":1}';
    final c = await _pump(tester, data, _prefs(encounterJson: enc));
    expect(find.text('Ash'), findsOneWidget);
    expect(find.textContaining('Round 1'), findsOneWidget);

    await tester.tap(find.byKey(const Key('run-init-next')));
    await tester.pumpAndSettle();
    expect((await c.read(encounterProvider.future)).turnIndex, 1);

    await tester.tap(find.byKey(const Key('run-init-roll-all')));
    await tester.pumpAndSettle();
    expect((await c.read(encounterProvider.future))
        .combatants.firstWhere((x) => x.id == 'b').initiative, greaterThan(0));
  });

  testWidgets('initiative: empty state when no combatants', (tester) async {
    await _pump(tester, data, _prefs());
    expect(find.byKey(const Key('run-init-empty')), findsOneWidget);
  });

  testWidgets('party: shows PCs with HP and applies inline damage', (tester) async {
    const chars =
        '[{"id":"p1","name":"Vex","stats":[],"tracks":[{"label":"HP","current":10,"max":10}],"tags":[],"role":"pc"},{"id":"n1","name":"Goon","stats":[],"tracks":[],"tags":[],"role":"npc"}]';
    final c = await _pump(tester, data, _prefs(charsJson: chars));
    expect(find.text('Vex'), findsOneWidget);
    expect(find.text('Goon'), findsNothing); // npc not in party panel
    expect(find.textContaining('10/10'), findsOneWidget);

    await tester.tap(find.byKey(const Key('run-party-p1-dec')));
    await tester.pumpAndSettle();
    final vex = (await c.read(charactersProvider.future))
        .firstWhere((x) => x.id == 'p1');
    expect(vex.tracks.first.current, 9);
  });

  testWidgets('party: empty state when no PCs', (tester) async {
    await _pump(tester, data, _prefs());
    expect(find.byKey(const Key('run-party-empty')), findsOneWidget);
  });

  testWidgets('scene: shows active scene + steps chaos', (tester) async {
    const journal =
        '[{"id":"e1","timestamp":"2026-01-01T10:00:00.000Z","title":"The Vault","body":"Dust everywhere.","kind":"scene","chaosFactor":6,"tags":[]}]';
    final c = await _pump(tester, data,
        _prefs(journalJson: journal, crawlJson: '{"chaosFactor":6}'));
    expect(find.text('The Vault'), findsWidgets);
    expect(find.text('Dust everywhere.'), findsOneWidget);
    expect(find.textContaining('Chaos 6'), findsOneWidget);

    await tester.tap(find.byKey(const Key('run-scene-chaos-inc')));
    await tester.pumpAndSettle();
    expect((await c.read(crawlProvider.future)).chaosFactor, 7);
  });

  testWidgets('scene: empty state when no scene', (tester) async {
    await _pump(tester, data, _prefs());
    expect(find.byKey(const Key('run-scene-empty')), findsOneWidget);
  });

  testWidgets('dice: roll logs a journal result; interpret hidden when AI off',
      (tester) async {
    final c = await _pump(tester, data, _prefs(crawlJson: '{"chaosFactor":5}'));
    expect(find.byKey(const Key('run-dice-interpret')), findsNothing); // AI off
    await tester.tap(find.byKey(const Key('run-dice-roll')));
    await tester.pumpAndSettle();
    final entries = await c.read(journalProvider.future);
    expect(entries.where((e) => e.sourceTool == 'fate-check'), hasLength(1));
  });

  testWidgets('capture: logs a text note and clears', (tester) async {
    final c = await _pump(tester, data, _prefs());
    await tester.enterText(
        find.byKey(const Key('run-capture-field')), 'Brakk shoves the archer');
    await tester.tap(find.byKey(const Key('run-capture-log')));
    await tester.pumpAndSettle();
    final entries = await c.read(journalProvider.future);
    expect(entries.where((e) => e.body == 'Brakk shoves the archer'),
        hasLength(1));
  });

  testWidgets('initiative: tapping a combatant with a stat block shows it',
      (tester) async {
    const enc =
        '{"combatants":[{"id":"g","name":"Goblin","initiative":12,"track":{"label":"HP","current":7,"max":7},"tags":[],"defeated":false,"statBlock":{"ac":13,"attacks":[{"name":"Scimitar","detail":"+4"}]}}],"turnIndex":0,"round":1}';
    await _pump(tester, data, _prefs(encounterJson: enc));
    await tester.tap(find.byKey(const Key('run-init-row-g')));
    await tester.pumpAndSettle();
    expect(find.textContaining('AC 13'), findsOneWidget);
    expect(find.text('Scimitar'), findsOneWidget);
  });

  testWidgets('initiative: a combatant without a stat block does not open one',
      (tester) async {
    const enc =
        '{"combatants":[{"id":"g","name":"Goblin","initiative":12,"track":{"label":"HP","current":7,"max":7},"tags":[],"defeated":false}],"turnIndex":0,"round":1}';
    await _pump(tester, data, _prefs(encounterJson: enc));
    await tester.tap(find.byKey(const Key('run-init-row-g')));
    await tester.pumpAndSettle();
    expect(find.textContaining('AC '), findsNothing); // no glance dialog
  });

  testWidgets('layout: two columns when wide, one column when narrow',
      (tester) async {
    const chars =
        '[{"id":"p1","name":"Vex","stats":[],"tracks":[{"label":"HP","current":10,"max":10}],"tags":[],"role":"pc"}]';
    // Wide: initiative and scene panels sit in two side-by-side columns → the
    // initiative panel's left edge is left of the scene panel's left edge.
    await _pump(tester, data, _prefs(charsJson: chars),
        size: const Size(1100, 1600));
    final initWide =
        tester.getTopLeft(find.byKey(const Key('run-panel-initiative')));
    final sceneWide =
        tester.getTopLeft(find.byKey(const Key('run-panel-scene')));
    expect(initWide.dx, lessThan(sceneWide.dx));

    // Narrow: stacked → scene sits below initiative.
    await _pump(tester, data, _prefs(charsJson: chars),
        size: const Size(500, 2400));
    final initN =
        tester.getTopLeft(find.byKey(const Key('run-panel-initiative')));
    final sceneN = tester.getTopLeft(find.byKey(const Key('run-panel-scene')));
    expect(sceneN.dy, greaterThan(initN.dy));
  });
}
