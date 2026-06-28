import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/features/run_screen.dart';
import 'package:juice_oracle/shared/destination.dart';
import 'package:juice_oracle/shared/shell_route.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/interpreter.dart'
    show interpreterServiceProvider, InterpreterStatus, InterpreterPhase;
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
  String? threadsJson,
  String? rumorsJson,
  bool gm = false,
}) =>
    {
      'juice.sessions.v1':
          '{"active":"$_sid","sessions":[{"id":"$_sid","name":"C1"'
              '${gm ? ',"mode":"gm"' : ''}}]}',
      if (journalJson != null) 'juice.journal.v2.$_sid': journalJson,
      if (charsJson != null) 'juice.characters.v1.$_sid': charsJson,
      if (encounterJson != null) 'juice.encounter.v1.$_sid': encounterJson,
      if (crawlJson != null) 'juice.crawl.v1.$_sid': crawlJson,
      if (contextJson != null) 'juice.context.v1.$_sid': contextJson,
      if (threadsJson != null) 'juice.threads.v1.$_sid': threadsJson,
      if (rumorsJson != null) 'juice.rumors.v1.$_sid': rumorsJson,
    };

Future<ProviderContainer> _pump(
  WidgetTester tester,
  OracleData data,
  Map<String, Object> prefs, {
  Size size = const Size(1000, 2200),
  bool aiReady = false,
}) async {
  SharedPreferences.setMockInitialValues({
    ...prefs,
    if (aiReady) 'juice.ai_enabled.v1': true,
  });
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final oracle = Oracle(data, Dice(Random(1)));
  final fake = aiReady
      ? FakeInterpreterService(
          initial: const InterpreterStatus(InterpreterPhase.ready))
      : FakeInterpreterService();
  final container = ProviderContainer(overrides: [
    oracleProvider.overrideWith((ref) async => oracle),
    interpreterServiceProvider.overrideWithValue(fake),
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

  test('formatDuration', () {
    expect(formatDuration(0), '0:00');
    expect(formatDuration(5), '0:05');
    expect(formatDuration(65), '1:05');
    expect(formatDuration(600), '10:00');
    expect(formatDuration(3661), '1:01:01');
    expect(formatDuration(-5), '0:00');
  });

  testWidgets('timers: idle with no encounter, ticks + resets on turn change',
      (tester) async {
    await _pump(tester, data, _prefs());
    expect(find.byKey(const Key('run-timers-idle')), findsOneWidget);

    const enc =
        '{"combatants":[{"id":"a","name":"A","initiative":15,"track":{"current":5,"max":5},"tags":[],"defeated":false},{"id":"b","name":"B","initiative":10,"track":{"current":5,"max":5},"tags":[],"defeated":false}],"turnIndex":0,"round":1}';
    final c = await _pump(tester, data, _prefs(encounterJson: enc));
    expect(find.byKey(const Key('run-timers-readout')), findsOneWidget);
    // Discrete 1s pumps each fire the periodic timer exactly once.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('Turn 0:02'), findsOneWidget);
    // Advance the turn: rebuild resets the turn stopwatch, session keeps going.
    await c.read(encounterProvider.notifier).nextTurn();
    await tester.pump(); // process the provider rebuild (turn reset)
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('Turn 0:01 · Session 0:03'), findsOneWidget);
    // Dispose the tree so the periodic timer is cancelled (no pending timer).
    await tester.pumpWidget(const SizedBox());
  });

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

  testWidgets('dice: interpret appears after a roll when AI is ready',
      (tester) async {
    await _pump(tester, data, _prefs(crawlJson: '{"chaosFactor":5}'),
        aiReady: true);
    // Hidden until there's a result to interpret.
    expect(find.byKey(const Key('run-dice-interpret')), findsNothing);
    await tester.tap(find.byKey(const Key('run-dice-roll')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('run-dice-interpret')), findsOneWidget);
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

  testWidgets('threads panel: shows open threads; rumors GM-only; routes',
      (tester) async {
    const threads =
        '[{"id":"t1","title":"Find the Relic","open":true,"pinned":false,"progress":3,"progressMax":8}]';
    const rumors = '[{"id":"r1","text":"The mayor lies","resolved":false}]';
    // Party mode: thread shows, rumor hidden.
    final c = await _pump(tester, data,
        _prefs(threadsJson: threads, rumorsJson: rumors));
    expect(find.byKey(const Key('run-thread-t1')), findsOneWidget);
    expect(find.text('Find the Relic'), findsOneWidget);
    expect(find.byKey(const Key('run-rumor-r1')), findsNothing);
    // Tap a thread → routes to Track/threads.
    await tester.tap(find.byKey(const Key('run-thread-t1')));
    await tester.pumpAndSettle();
    expect(c.read(shellRouteProvider).destination, Destination.track);
    expect(c.read(shellRouteProvider).subtab, 'threads');

    // GM mode: rumor shows too.
    await _pump(tester, data,
        _prefs(threadsJson: threads, rumorsJson: rumors, gm: true));
    expect(find.byKey(const Key('run-rumor-r1')), findsOneWidget);
  });

  testWidgets('threads panel: empty state', (tester) async {
    await _pump(tester, data, _prefs());
    expect(find.byKey(const Key('run-threads-empty')), findsOneWidget);
  });

  testWidgets('party effect: bulk damage applies to selected members',
      (tester) async {
    const chars =
        '[{"id":"p1","name":"Vex","stats":[],"tracks":[{"label":"HP","current":10,"max":10}],"tags":[],"role":"pc"},'
        '{"id":"p2","name":"Brakk","stats":[],"tracks":[{"label":"HP","current":8,"max":8}],"tags":[],"role":"pc"}]';
    final c = await _pump(tester, data, _prefs(charsJson: chars));
    await tester.tap(find.byKey(const Key('run-party-effect')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('run-effect-target-p1')));
    await tester.tap(find.byKey(const Key('run-effect-target-p2')));
    await tester.enterText(find.byKey(const Key('run-effect-hp')), '-3');
    await tester.tap(find.byKey(const Key('run-effect-apply')));
    await tester.pumpAndSettle();
    final chs = await c.read(charactersProvider.future);
    expect(chs.firstWhere((x) => x.id == 'p1').tracks.first.current, 7);
    expect(chs.firstWhere((x) => x.id == 'p2').tracks.first.current, 5);
  });
}
