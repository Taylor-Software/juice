import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/features/journal_screen.dart';
import 'package:juice_oracle/shared/home_shell.dart';
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

/// Pump JournalScreen directly (no ToolHost — for non-tool tests).
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

/// Pump HomeShell with a real Oracle (gives us ToolHost with full registry).
Future<void> pumpShell(
    WidgetTester tester, Map<String, Object> prefs, OracleData data) async {
  SharedPreferences.setMockInitialValues(prefs);
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final fake = FakeInterpreterService();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      interpreterServiceProvider.overrideWithValue(fake),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: HomeShell(oracle: Oracle(data)),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('payload entry renders summary, roll rows, and actions',
      (tester) async {
    await pumpJournal(tester, _journalPrefs(_entryJson));

    // Summary text visible.
    expect(find.text('Yes'), findsOneWidget);
    // Roll row label + value render as separate cells (label has no colon).
    expect(find.text('Answer'), findsOneWidget);
    expect(find.textContaining('Yes (+04)'), findsOneWidget);
    // Re-roll icon present (oracle not loaded in plain JournalScreen so
    // _canReroll may be false; but open-in-tool is unconditional on sourceTool).
    expect(find.byKey(const Key('entry-open-tool-$_entryId')), findsOneWidget);
    // The raw flat body string is NOT rendered as a single Text widget.
    expect(find.text(_payloadBody), findsNothing);
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

  testWidgets('open-in-tool opens the source tool panel', (tester) async {
    final data = _loadData();
    await pumpShell(tester, _journalPrefs(_entryJson), data);

    // The open-in-tool icon should be visible in the journal.
    expect(find.byKey(const Key('entry-open-tool-$_entryId')), findsOneWidget);
    await tester.tap(find.byKey(const Key('entry-open-tool-$_entryId')));
    await tester.pumpAndSettle();

    // The Fate Check tool header is now visible in the panel.
    expect(find.text('Fate Check'), findsWidgets);
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

  testWidgets('non-rerollable payload hides re-roll, shows open-in-tool',
      (tester) async {
    // Tool-logged entry: has sourceTool and payload but no command/rerollable.
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
    // Open-in-tool icon present.
    expect(find.byKey(const Key('entry-open-tool-e3')), findsOneWidget);
    // Re-roll icon absent (no command/rerollable in payload).
    expect(find.byKey(const Key('entry-reroll-e3')), findsNothing);
  });
}
