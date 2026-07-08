import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/emulator_data.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/engine/verdant_data.dart';
import 'package:juice_oracle/features/journal_screen.dart';
import 'package:juice_oracle/shared/ai_nudge_card.dart';
import 'package:juice_oracle/shared/card_image.dart';
import 'package:juice_oracle/shared/destination.dart';
import 'package:juice_oracle/shared/home_shell.dart';
import 'package:juice_oracle/shared/shell_route.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_interpreter.dart';
import 'package:juice_oracle/state/interpreter.dart';

/// Session + one payload entry seeded into shared prefs.
const _sessionPrefs = {
  'juice.sessions.v1':
      '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
};

Map<String, String> _journalPrefs(String entryJson) => {
      ..._sessionPrefs,
      'juice.journal.v2.default': '[$entryJson]',
    };

// A fate-check payload entry fixture.
const _entryId = 'e1';
const _entryTitle = 'Fate Check (Likely)';
// Dart string — literal newline for comparing against entry.body.
const _payloadBody = 'Yes\nAnswer: Yes (+04)';
// JSON string — \\n is JSON's newline escape (produces \n in the parsed string).
const _entryJson = '{'
    '"id":"$_entryId",'
    '"timestamp":"2026-06-12T10:00:00.000Z",'
    '"title":"$_entryTitle",'
    '"body":"Yes\\nAnswer: Yes (+04)",'
    '"kind":"result",'
    '"tags":[],'
    '"sourceTool":"fate-check",'
    '"payload":{"v":1,"command":"fate-juice","args":{"odds":"likely"},'
    '"summary":"Yes",'
    '"rolls":[{"label":"Answer","display":"Yes (+04)"}],'
    '"rerollable":true}'
    '}';

OracleData _loadData() {
  final raw = File('assets/oracle_data.json').readAsStringSync();
  return OracleData(jsonDecode(raw) as Map<String, dynamic>);
}

VerdantData _loadVerdant() =>
    VerdantData(jsonDecode(File('assets/verdant_data.json').readAsStringSync())
        as Map<String, dynamic>);

EmulatorData _loadEmulator() => EmulatorData(
    jsonDecode(File('assets/emulator_data.json').readAsStringSync())
        as Map<String, dynamic>);

/// Pump JournalScreen directly (no shell — for non-navigation tests).
Future<void> pumpJournal(WidgetTester tester, Map<String, Object> prefs) async {
  SharedPreferences.setMockInitialValues(prefs);
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: JournalScreen()),
    ),
  ));
  await tester.pumpAndSettle();
}

/// Pump HomeShell with a real Oracle (gives us the tabbed shell + search sheet
/// with the full registry). Overrides verdant + emulator providers so the
/// default all-systems session doesn't hang on rootBundle in headless tests.
Future<void> pumpShell(
    WidgetTester tester, Map<String, Object> prefs, OracleData data) async {
  SharedPreferences.setMockInitialValues(prefs);
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final fake = FakeInterpreterService();
  final verdant = _loadVerdant();
  final emu = _loadEmulator();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      interpreterServiceProvider.overrideWithValue(fake),
      verdantDataProvider.overrideWith((ref) async => verdant),
      emulatorDataProvider.overrideWith((ref) async => emu),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: HomeShell(oracle: Oracle(data)),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  const cardEntryJson = '{'
      '"id":"c1","timestamp":"2026-06-12T10:00:00.000Z","title":"Tarot",'
      '"body":"The Tower (reversed)\\nReversed — clinging.","kind":"result",'
      '"tags":[],"sourceTool":"cards",'
      '"payload":{"v":1,"summary":"The Tower (reversed)",'
      '"rolls":[{"label":"Card","display":"The Tower (reversed)"},'
      '{"label":"Deck","display":"1/78"}]}}';

  testWidgets('a logged tarot card entry renders its bundled image',
      (tester) async {
    await pumpJournal(tester, _journalPrefs(cardEntryJson));
    // Collapsed row shows the card name; no image until expanded.
    expect(find.text('The Tower (reversed)'), findsOneWidget);
    expect(find.byType(CardImage), findsNothing);

    await tester.tap(find.byKey(const Key('payload-expand-c1')));
    await tester.pumpAndSettle();

    expect(find.text('The Tower (reversed)'), findsWidgets); // summary + body
    expect(find.byType(CardImage), findsOneWidget);
  });

  testWidgets('a story-dice entry shows its icon images in the collapsed row',
      (tester) async {
    const iconEntryJson = '{'
        '"id":"i1","timestamp":"2026-06-12T10:00:00.000Z",'
        '"title":"Story Dice (2)","body":"Icon 1: d10 3, d6 2",'
        '"kind":"result","tags":[],"sourceTool":"gen-story",'
        '"payload":{"v":1,'
        '"rolls":[{"label":"Icon 1","display":"d10 3, d6 2"},'
        '{"label":"Icon 2","display":"d10 0, d6 6"}],'
        '"icons":["assets/abstract_icons/3_2.png",'
        '"assets/abstract_icons/0_6.png"]}}';
    await pumpJournal(tester, _journalPrefs(iconEntryJson));

    // The icons are the result — they render in the collapsed row (not text).
    final images = tester
        .widgetList<Image>(find.byType(Image))
        .map((w) => (w.image as AssetImage).assetName)
        .toList();
    expect(images, [
      'assets/abstract_icons/3_2.png',
      'assets/abstract_icons/0_6.png',
    ]);
    // No text roll-summary line for an icon entry.
    expect(find.textContaining('d10 3, d6 2'), findsNothing);
  });

  testWidgets(
      'a sketch map acts as a place: backlink chip counts stamped entries and '
      'the sketch menu offers Set as current location', (tester) async {
    // A sketch entry + a text entry stamped with it as its location.
    const sketchJson = '{'
        '"id":"s1","timestamp":"2026-06-12T09:00:00.000Z","title":"Cave map",'
        '"body":"","kind":"sketch","tags":[],'
        '"payload":{"v":1,"sketch":{"v":1,"strokes":[],"w":100,"h":100}}}';
    const noteJson = '{'
        '"id":"n1","timestamp":"2026-06-12T10:00:00.000Z","title":"",'
        '"body":"We enter the cave.","kind":"text","tags":[],'
        '"loc":{"sketch":"s1"}}';
    await pumpJournal(tester, {
      ..._sessionPrefs,
      'juice.journal.v2.default': '[$noteJson,$sketchJson]',
    });

    // The stamped note shows a place chip labeled with the sketch title.
    expect(find.byKey(const Key('entry-loc-n1')), findsOneWidget);
    expect(find.text('Cave map'), findsOneWidget);
    // The sketch card shows the backlink count chip.
    expect(find.byKey(const Key('sketch-entries-s1')), findsOneWidget);
    expect(find.text('1 entry'), findsOneWidget);

    // The sketch overflow menu offers Set as current location.
    await tester.tap(find
        .descendant(
            of: find.ancestor(
                of: find.byKey(const Key('sketch-thumb-s1')),
                matching: find.byType(Card)),
            matching: find.byType(PopupMenuButton<String>))
        .first);
    await tester.pumpAndSettle();
    expect(find.text('Set as current location'), findsOneWidget);
    await tester.tap(find.text('Set as current location'));
    await tester.pumpAndSettle();
    expect(find.text('Current location set'), findsOneWidget);
  });

  testWidgets(
      'payload entry collapses by default: one-line answer, no roll rows or actions',
      (tester) async {
    await pumpJournal(tester, _journalPrefs(_entryJson));

    // Summary text visible on the collapsed one-liner.
    expect(find.text('Yes'), findsOneWidget);
    // Roll rows are NOT shown until expanded.
    expect(find.text('Answer'), findsNothing);
    // Open-in-tool is inside the expanded header — not visible collapsed.
    expect(find.byKey(const Key('entry-open-tool-$_entryId')), findsNothing);
    // The raw flat body string is NOT rendered as a single Text widget.
    expect(find.text(_payloadBody), findsNothing);
  });

  testWidgets(
      'tapping the collapsed row expands to reveal roll rows, remainder, and actions',
      (tester) async {
    await pumpJournal(tester, _journalPrefs(_entryJson));

    expect(find.byKey(const Key('payload-expand-$_entryId')), findsOneWidget);
    await tester.tap(find.byKey(const Key('payload-expand-$_entryId')));
    await tester.pumpAndSettle();

    // Roll row label + value render as separate cells (label has no colon).
    expect(find.text('Answer'), findsOneWidget);
    expect(find.textContaining('Yes (+04)'), findsOneWidget);
    // Open-in-tool now reachable in the expanded header.
    expect(find.byKey(const Key('entry-open-tool-$_entryId')), findsOneWidget);
  });

  testWidgets('appended notes beyond the payload text still render',
      (tester) async {
    // Same payload but body has an appended oracle reading.
    const note = '— Oracle reading (literal): The guard nods.';
    const bodyWithNote = '$_payloadBody\n\n$note';
    final entryWithNote = '{'
        '"id":"$_entryId",'
        '"timestamp":"2026-06-12T10:00:00.000Z",'
        '"title":"$_entryTitle",'
        '"body":${jsonEncode(bodyWithNote)},'
        '"kind":"result",'
        '"tags":[],'
        '"sourceTool":"fate-check",'
        '"payload":{"v":1,"command":"fate-juice","args":{"odds":"likely"},'
        '"summary":"Yes",'
        '"rolls":[{"label":"Answer","display":"Yes (+04)"}],'
        '"rerollable":true}'
        '}';
    await pumpJournal(tester, _journalPrefs(entryWithNote));
    // Remainder text is inside the expanded body — not visible collapsed.
    expect(find.textContaining('Oracle reading'), findsNothing);
    await tester.tap(find.byKey(const Key('payload-expand-$_entryId')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Oracle reading'), findsOneWidget);
  });

  testWidgets('re-roll appends a new entry via the command registry',
      (tester) async {
    final data = _loadData();
    final oracle = Oracle(data, Dice(Random(1)));
    SharedPreferences.setMockInitialValues(_journalPrefs(_entryJson));
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fake = FakeInterpreterService();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        oracleProvider.overrideWith((ref) async => oracle),
        interpreterServiceProvider.overrideWithValue(fake),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: JournalScreen()),
      ),
    ));
    await tester.pumpAndSettle();

    // The re-roll icon should be visible because oracleProvider has a value.
    expect(find.byKey(const Key('entry-reroll-$_entryId')), findsOneWidget);
    await tester.tap(find.byKey(const Key('entry-reroll-$_entryId')));
    await tester.pumpAndSettle();

    final container =
        ProviderScope.containerOf(tester.element(find.byType(JournalScreen)));
    final entries = await container.read(journalProvider.future);
    // Original + new re-roll.
    expect(entries.length, 2);
    final newest = entries.first; // storage is newest-first
    expect(newest.payload!['command'], 'fate-juice');
    expect((newest.payload!['args'] as Map)['odds'], 'likely');
  });

  testWidgets('re-roll replays a dice-roller entry via its expression',
      (tester) async {
    const diceEntry = '{'
        '"id":"d1",'
        '"timestamp":"2026-06-12T10:00:00.000Z",'
        '"title":"Dice Roll",'
        '"body":"2d6 = 7",'
        '"kind":"result",'
        '"tags":[],'
        '"sourceTool":"dice",'
        '"payload":{"v":1,"summary":"2d6 = 7","rolls":[],"expression":"2d6"}'
        '}';
    final oracle = Oracle(_loadData(), Dice(Random(1)));
    SharedPreferences.setMockInitialValues(_journalPrefs(diceEntry));
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: [oracleProvider.overrideWith((ref) async => oracle)],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: JournalScreen()),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('entry-reroll-d1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('entry-reroll-d1')));
    await tester.pumpAndSettle();

    final container =
        ProviderScope.containerOf(tester.element(find.byType(JournalScreen)));
    final entries = await container.read(journalProvider.future);
    expect(entries.length, 2);
    final newest = entries.first;
    expect(newest.sourceTool, 'dice');
    // Re-rolled with the same expression, still rerollable.
    expect(newest.payload!['expression'], '2d6');
  });

  testWidgets('open-in-tool navigates to the source tool destination',
      (tester) async {
    final data = _loadData();
    await pumpShell(tester, _journalPrefs(_entryJson), data);

    // Open-in-tool lives in the expanded header — expand first.
    await tester.tap(find.byKey(const Key('payload-expand-$_entryId')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('entry-open-tool-$_entryId')), findsOneWidget);
    await tester.tap(find.byKey(const Key('entry-open-tool-$_entryId')));
    await tester.pumpAndSettle();

    // The fate-check source tool homes on the Oracles destination.
    final container =
        ProviderScope.containerOf(tester.element(find.byType(HomeShell)));
    expect(container.read(shellRouteProvider).destination, Destination.ask);
    expect(container.read(shellRouteProvider).subtab, 'oracle');
  });

  testWidgets('entry with unknown payload version falls back to flat',
      (tester) async {
    const weirdEntry = '{'
        '"id":"e2",'
        '"timestamp":"2026-06-12T10:00:00.000Z",'
        '"title":"Weird Result",'
        '"body":"some flat body",'
        '"kind":"result",'
        '"tags":[],'
        '"payload":{"v":99,"weird":true}'
        '}';
    await pumpJournal(tester, _journalPrefs(weirdEntry));
    // Falls back to flat ListTile rendering — body text visible.
    expect(find.text('some flat body'), findsOneWidget);
    // No re-roll icon.
    expect(find.byKey(const Key('entry-reroll-e2')), findsNothing);
  });

  testWidgets(
      'non-rerollable payload hides re-roll; gen-* sourceTool hides open-in-tool',
      (tester) async {
    // Tool-logged entry from a gen-* source (no toolLocation entry) — neither
    // icon should appear.
    const toolEntry = '{'
        '"id":"e3",'
        '"timestamp":"2026-06-12T10:00:00.000Z",'
        '"title":"NPC",'
        '"body":"Trait: Grim",'
        '"kind":"result",'
        '"tags":[],'
        '"sourceTool":"gen-npcs",'
        '"payload":{"v":1,"rolls":[{"label":"Trait","display":"Grim"}]}'
        '}';
    await pumpJournal(tester, _journalPrefs(toolEntry));
    // Open-in-tool icon absent: gen-npcs has no toolLocation entry (graceful
    // degrade — chip is omitted rather than firing a dead snackbar).
    expect(find.byKey(const Key('entry-open-tool-e3')), findsNothing);
    // Re-roll icon absent (no command/rerollable in payload).
    expect(find.byKey(const Key('entry-reroll-e3')), findsNothing);
  });

  testWidgets('hero card renders the comma summary + a working Pin button',
      (tester) async {
    // A fate-check result with a comma summary ("Yes, and…") — the trailing
    // qualifier renders as a separate italic span but the combined plain text
    // is still findable.
    const heroEntry = '{'
        '"id":"h1",'
        '"timestamp":"2026-06-12T10:00:00.000Z",'
        '"title":"Fate Check (Likely)",'
        '"body":"Yes, and…\\nAnswer: Yes (+04)",'
        '"kind":"result",'
        '"tags":[],'
        '"sourceTool":"fate-juice",'
        '"payload":{"v":1,"command":"fate-juice","args":{"odds":"likely"},'
        '"summary":"Yes, and…",'
        '"rolls":[{"label":"Answer","display":"Yes (+04)"}],'
        '"rerollable":true}'
        '}';
    await pumpJournal(tester, _journalPrefs(heroEntry));

    // Collapsed one-liner still shows the combined summary text.
    expect(find.text('Yes, and…'), findsOneWidget);
    // Pin lives in the expanded action row — expand first.
    await tester.tap(find.byKey(const Key('payload-expand-h1')));
    await tester.pumpAndSettle();

    // Big serif answer renders (combined rich-text run).
    expect(find.text('Yes, and…'), findsOneWidget);
    // The on-card Pin button exists and starts outlined (not pinned).
    final pin = find.byKey(const Key('pin-h1'));
    expect(pin, findsOneWidget);
    expect(find.byIcon(Icons.push_pin_outlined), findsOneWidget);
    expect(find.byIcon(Icons.push_pin), findsNothing);

    // Tapping Pin flips the entry's pinned flag and the icon fills in.
    await tester.tap(pin);
    await tester.pumpAndSettle();

    final container =
        ProviderScope.containerOf(tester.element(find.byType(JournalScreen)));
    final entries = await container.read(journalProvider.future);
    expect(entries.single.pinned, isTrue);
    expect(find.byIcon(Icons.push_pin), findsOneWidget);
    expect(find.byIcon(Icons.push_pin_outlined), findsNothing);
  });

  testWidgets('gen-story sourceTool shows chip text but no open-in-tool button',
      (tester) async {
    // Entries produced by the inspire sheet (gen-story etc.) have a sourceTool
    // that is not in toolLocation — the open-in-tool button must be absent so
    // tapping never triggers a "Tool not available" snackbar.
    const genEntry = '{'
        '"id":"e4",'
        '"timestamp":"2026-06-12T10:00:00.000Z",'
        '"title":"New Quest",'
        '"body":"A dragon stirs",'
        '"kind":"result",'
        '"tags":[],'
        '"sourceTool":"gen-story",'
        '"payload":{"v":1,"rolls":[{"label":"Quest","display":"A dragon stirs"}]}'
        '}';
    await pumpJournal(tester, _journalPrefs(genEntry));
    // No open-in-tool button — gen-story is not in toolLocation.
    expect(find.byKey(const Key('entry-open-tool-e4')), findsNothing);
    // No snackbar (nothing tappable to trigger it).
    expect(find.text('Tool not available'), findsNothing);
  });

  // Pump the journal with the AI-enable nudge showing (AI supported but not
  // enabled, nudge not yet seen) at a caller-chosen height. The fake
  // interpreter defaults to needsDownload → aiSupported true / aiReady false,
  // and aiNudgeSeen defaults to false, so the tall nudge card renders.
  Future<void> pumpJournalWithNudge(WidgetTester tester, double height) async {
    SharedPreferences.setMockInitialValues(_journalPrefs(_entryJson));
    final fake = FakeInterpreterService();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        interpreterServiceProvider.overrideWithValue(fake),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              // Wide enough to avoid unrelated horizontal squeeze; height is the
              // axis under test (the journal body's vertical overflow).
              width: 700,
              height: height,
              child: const JournalScreen(),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('AI nudge does not overflow the journal body at a short height',
      (tester) async {
    await pumpJournalWithNudge(tester, 400);

    // No RenderFlex overflow despite the tall nudge above a non-empty list.
    expect(tester.takeException(), isNull);
    // The nudge and the composer both render.
    expect(find.byType(AiNudgeCard), findsOneWidget);
    expect(find.byKey(const Key('ai-nudge-card')), findsOneWidget);
    expect(find.byKey(const Key('journal-composer')), findsOneWidget);
  });

  testWidgets('AI nudge + entries render normally at a comfortable height',
      (tester) async {
    await pumpJournalWithNudge(tester, 900);

    expect(tester.takeException(), isNull);
    expect(find.byType(AiNudgeCard), findsOneWidget);
    // The seeded entry's summary is visible.
    expect(find.text('Yes'), findsOneWidget);
    expect(find.byKey(const Key('journal-composer')), findsOneWidget);
  });

  testWidgets(
      'inline roll dock is always visible and writes a fate result on tap',
      (tester) async {
    final oracle = Oracle(_loadData(), Dice(Random(1)));
    SharedPreferences.setMockInitialValues(_journalPrefs(_entryJson));
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: [oracleProvider.overrideWith((ref) async => oracle)],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: JournalScreen()),
      ),
    ));
    await tester.pumpAndSettle();

    // The dock's Roll-oracle chip is visible WITHOUT expanding the rail (the
    // rail's expand header is still collapsed).
    expect(find.byKey(const Key('dock-roll-oracle')), findsOneWidget);
    expect(
        find.byKey(const Key('ask-gm-field')), findsNothing); // rail collapsed

    await tester.tap(find.byKey(const Key('dock-roll-oracle')));
    await tester.pumpAndSettle();

    final container =
        ProviderScope.containerOf(tester.element(find.byType(JournalScreen)));
    final entries = await container.read(journalProvider.future);
    // Seeded fixture + the new dock roll.
    expect(entries.length, 2);
    final newest = entries.first; // storage is newest-first
    expect(newest.kind, JournalKind.result);
    expect(newest.sourceTool, 'fate-check');
    expect(newest.title, contains('Fate Check'));
  });

  testWidgets(
      'collapsed payload card shows a one-liner and hides the Interpret/Voice/Pin row',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      ..._journalPrefs(_entryJson),
      'juice.ai_enabled.v1': true,
    });
    final fake = FakeInterpreterService(
        initial: const InterpreterStatus(InterpreterPhase.ready));
    await tester.pumpWidget(ProviderScope(
      overrides: [interpreterServiceProvider.overrideWithValue(fake)],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: JournalScreen()),
      ),
    ));
    await tester.pumpAndSettle();

    // Collapsed one-liner answer visible.
    expect(find.text('Yes'), findsOneWidget);
    // No action row until expanded, even though AI is ready.
    expect(find.text('Interpret'), findsNothing);
    expect(find.text('Voice line'), findsNothing);
    expect(find.byKey(const Key('pin-$_entryId')), findsNothing);
  });

  testWidgets(
      'tapping the collapsed row expands and reveals Interpret when AI is ready',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      ..._journalPrefs(_entryJson),
      'juice.ai_enabled.v1': true,
    });
    final fake = FakeInterpreterService(
        initial: const InterpreterStatus(InterpreterPhase.ready));
    await tester.pumpWidget(ProviderScope(
      overrides: [interpreterServiceProvider.overrideWithValue(fake)],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: JournalScreen()),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('payload-expand-$_entryId')));
    await tester.pumpAndSettle();

    expect(find.text('Interpret'), findsOneWidget);
    expect(find.byKey(const Key('pin-$_entryId')), findsOneWidget);
  });

  testWidgets('a pinned entry renders expanded by default', (tester) async {
    const pinnedEntry = '{'
        '"id":"p1",'
        '"timestamp":"2026-06-12T10:00:00.000Z",'
        '"title":"$_entryTitle",'
        '"body":"Yes\\nAnswer: Yes (+04)",'
        '"kind":"result",'
        '"tags":[],'
        '"sourceTool":"fate-check",'
        '"pinned":true,'
        '"payload":{"v":1,"command":"fate-juice","args":{"odds":"likely"},'
        '"summary":"Yes",'
        '"rolls":[{"label":"Answer","display":"Yes (+04)"}],'
        '"rerollable":true}'
        '}';
    await pumpJournal(tester, _journalPrefs(pinnedEntry));

    // Roll rows visible without tapping — pinned entries start expanded.
    expect(find.text('Answer'), findsOneWidget);
    expect(find.byIcon(Icons.push_pin), findsOneWidget);
  });
}
