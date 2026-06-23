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
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/interpreter.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_interpreter.dart';

OracleData _loadData() {
  final raw = File('assets/oracle_data.json').readAsStringSync();
  return OracleData(jsonDecode(raw) as Map<String, dynamic>);
}

const _sessionPrefs = {
  'juice.sessions.v1':
      '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
};

Future<void> pumpPalette(WidgetTester tester, OracleData data,
    {Map<String, Object>? prefs}) async {
  SharedPreferences.setMockInitialValues(prefs ?? _sessionPrefs);
  final fake = FakeInterpreterService();
  final oracle = Oracle(data, Dice(Random(1)));
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
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
}

void main() {
  late OracleData data;
  setUpAll(() => data = _loadData());

  testWidgets('typing / opens the palette listing commands', (tester) async {
    await pumpPalette(tester, data);

    await tester.enterText(find.byKey(const Key('journal-composer')), '/');
    await tester.pump();

    expect(find.byKey(const Key('slash-palette')), findsOneWidget);
    expect(find.text('Fate Check (Juice)'), findsOneWidget);
    expect(find.text('Roll Dice'), findsOneWidget);
  });

  testWidgets('typing /di filters to the dice command', (tester) async {
    await pumpPalette(tester, data);

    await tester.enterText(find.byKey(const Key('journal-composer')), '/di');
    await tester.pump();

    expect(find.text('Roll Dice'), findsOneWidget);
    expect(find.text('Fate Check (Juice)'), findsNothing);
  });

  const cardsPrefs = {
    'juice.sessions.v1': '{"active":"default","sessions":[{"id":"default",'
        '"name":"C1","systems":["cards"]}]}',
  };

  testWidgets('/card suggestion hidden when cards is off', (tester) async {
    await pumpPalette(tester, data); // default: cards off (not in kAllSystems)
    await tester.enterText(find.byKey(const Key('journal-composer')), '/car');
    await tester.pump();
    expect(find.byKey(const Key('slash-cmd-card')), findsNothing);
  });

  testWidgets('/card and /tarot suggestions appear when cards is on',
      (tester) async {
    await pumpPalette(tester, data, prefs: cardsPrefs);
    await tester.enterText(find.byKey(const Key('journal-composer')), '/car');
    await tester.pump();
    expect(find.byKey(const Key('slash-cmd-card')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('journal-composer')), '/tar');
    await tester.pump();
    expect(find.byKey(const Key('slash-cmd-tarot')), findsOneWidget);
  });

  testWidgets('tapping Draw a tarot card logs a cards entry', (tester) async {
    await pumpPalette(tester, data, prefs: cardsPrefs);
    await tester.enterText(find.byKey(const Key('journal-composer')), '/tarot');
    await tester.pump();
    await tester.tap(find.byKey(const Key('slash-cmd-tarot')));
    await tester.pumpAndSettle();
    final container =
        ProviderScope.containerOf(tester.element(find.byType(JournalScreen)));
    final entries = await container.read(journalProvider.future);
    expect(entries.where((e) => e.sourceTool == 'cards'), hasLength(1));
  });

  testWidgets('/spread suggestion hidden when cards is off', (tester) async {
    await pumpPalette(tester, data); // cards off (not in kAllSystems)
    await tester.enterText(find.byKey(const Key('journal-composer')), '/spr');
    await tester.pump();
    expect(find.byKey(const Key('slash-cmd-spread')), findsNothing);
  });

  testWidgets('/spread suggestion appears when cards is on', (tester) async {
    await pumpPalette(tester, data, prefs: cardsPrefs);
    await tester.enterText(find.byKey(const Key('journal-composer')), '/spr');
    await tester.pump();
    expect(find.byKey(const Key('slash-cmd-spread')), findsOneWidget);
  });

  testWidgets('tapping the spread chip logs a default 3-card spread entry',
      (tester) async {
    await pumpPalette(tester, data, prefs: cardsPrefs);
    await tester.enterText(
        find.byKey(const Key('journal-composer')), '/spread');
    await tester.pump();
    await tester.tap(find.byKey(const Key('slash-cmd-spread')));
    await tester.pumpAndSettle();
    final container =
        ProviderScope.containerOf(tester.element(find.byType(JournalScreen)));
    final entries = await container.read(journalProvider.future);
    expect(entries.where((e) => e.sourceTool == 'cards'), hasLength(1));
    expect(entries.first.body, contains('Past'));
    expect(entries.first.body, contains('Future'));
  });

  testWidgets('/spread celtic via Enter logs the 10-card spread',
      (tester) async {
    await pumpPalette(tester, data, prefs: cardsPrefs);
    await tester.enterText(
        find.byKey(const Key('journal-composer')), '/spread celtic');
    await tester.pump();
    await tester.tap(find.byKey(const Key('journal-send')));
    await tester.pumpAndSettle();
    final container =
        ProviderScope.containerOf(tester.element(find.byType(JournalScreen)));
    final entries = await container.read(journalProvider.future);
    expect(entries.where((e) => e.sourceTool == 'cards'), hasLength(1));
    expect(entries.first.body, contains('Foundation')); // Celtic-Cross position
  });

  testWidgets('selecting a no-arg command runs it and clears the composer',
      (tester) async {
    await pumpPalette(tester, data);

    await tester.enterText(find.byKey(const Key('journal-composer')), '/name');
    await tester.pump();

    await tester.tap(find.byKey(const Key('slash-cmd-name')));
    await tester.pumpAndSettle();

    // Composer cleared.
    final composerField =
        tester.widget<TextField>(find.byKey(const Key('journal-composer')));
    expect(composerField.controller?.text, '');

    // Palette gone.
    expect(find.byKey(const Key('slash-palette')), findsNothing);

    // Journal has 1 entry with sourceTool 'gen-details'.
    final container =
        ProviderScope.containerOf(tester.element(find.byType(JournalScreen)));
    final entries = await container.read(journalProvider.future);
    expect(entries.length, 1);
    expect(entries.first.sourceTool, 'gen-details');
  });

  testWidgets('/dice with notation runs the dice command on tap',
      (tester) async {
    await pumpPalette(tester, data);

    await tester.enterText(
        find.byKey(const Key('journal-composer')), '/dice 2d6+1');
    await tester.pump();

    // Dice command is visible in the palette.
    expect(find.byKey(const Key('slash-cmd-dice')), findsOneWidget);
    await tester.tap(find.byKey(const Key('slash-cmd-dice')));
    await tester.pumpAndSettle();

    final container =
        ProviderScope.containerOf(tester.element(find.byType(JournalScreen)));
    final entries = await container.read(journalProvider.future);
    expect(entries.length, 1);
    expect(entries.first.sourceTool, 'dice');
    // Payload summary matches '2d6+1 = <number>'.
    final summary = entries.first.payload?['summary'] as String?;
    expect(summary, isNotNull);
    expect(summary, matches(RegExp(r'2d6\+1 = \d+')));
  });

  testWidgets('a fate command shows odds chips; picking one runs at that odds',
      (tester) async {
    await pumpPalette(tester, data);

    await tester.enterText(find.byKey(const Key('journal-composer')), '/fate');
    await tester.pump();

    // Tap fate-juice to expand odds chips.
    await tester.tap(find.byKey(const Key('slash-cmd-fate-juice')));
    await tester.pump();

    // Odds chip for 'likely' is now visible.
    expect(find.byKey(const Key('slash-odds-likely')), findsOneWidget);
    await tester.tap(find.byKey(const Key('slash-odds-likely')));
    await tester.pumpAndSettle();

    final container =
        ProviderScope.containerOf(tester.element(find.byType(JournalScreen)));
    final entries = await container.read(journalProvider.future);
    expect(entries.length, 1);
    expect(entries.first.sourceTool, 'fate-check');
    final args = entries.first.payload?['args'] as Map?;
    expect(args?['odds'], 'likely');
  });

  testWidgets('/scene opens the scene dialog', (tester) async {
    await pumpPalette(tester, data);

    await tester.enterText(find.byKey(const Key('journal-composer')), '/scene');
    await tester.pump();

    await tester.tap(find.byKey(const Key('slash-cmd-scene')));
    await tester.pumpAndSettle();

    // The existing _SceneDialog title is visible.
    expect(find.text('New scene'), findsOneWidget);
  });

  testWidgets('clearing the slash dismisses the palette', (tester) async {
    await pumpPalette(tester, data);

    await tester.enterText(find.byKey(const Key('journal-composer')), '/');
    await tester.pump();
    expect(find.byKey(const Key('slash-palette')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('journal-composer')), '');
    await tester.pump();
    expect(find.byKey(const Key('slash-palette')), findsNothing);
  });

  testWidgets('plain text send still works (no palette)', (tester) async {
    await pumpPalette(tester, data);

    await tester.enterText(
        find.byKey(const Key('journal-composer')), 'just a note');
    await tester.pump();

    // No palette.
    expect(find.byKey(const Key('slash-palette')), findsNothing);

    await tester.tap(find.byKey(const Key('journal-send')));
    await tester.pumpAndSettle();

    final container =
        ProviderScope.containerOf(tester.element(find.byType(JournalScreen)));
    final entries = await container.read(journalProvider.future);
    expect(entries.length, 1);
    expect(entries.first.body, 'just a note');
    expect(entries.first.sourceTool, isNull);
  });

  testWidgets('Enter routes a slash command to the top match', (tester) async {
    await pumpPalette(tester, data);

    await tester.enterText(find.byKey(const Key('journal-composer')), '/name');
    await tester.pump();
    // Submit the field (Enter) — _send should run the top match, not log text.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    final container =
        ProviderScope.containerOf(tester.element(find.byType(JournalScreen)));
    final entries = await container.read(journalProvider.future);
    expect(entries.length, 1);
    expect(entries.first.sourceTool, 'gen-details');
    expect((entries.first.payload?['rolls'] as List?), isNotEmpty);
    // Composer cleared, palette gone.
    expect(find.byKey(const Key('slash-palette')), findsNothing);
  });

  testWidgets('built-in scene row uses prefix match, not substring',
      (tester) async {
    await pumpPalette(tester, data);

    // '/e' is a substring of 'scene' but not a prefix — the scene row must
    // NOT appear (guards the contains-vs-startsWith bug).
    await tester.enterText(find.byKey(const Key('journal-composer')), '/e');
    await tester.pump();
    expect(find.byKey(const Key('slash-cmd-scene')), findsNothing);

    // '/sc' IS a prefix of 'scene' — the row appears.
    await tester.enterText(find.byKey(const Key('journal-composer')), '/sc');
    await tester.pump();
    expect(find.byKey(const Key('slash-cmd-scene')), findsOneWidget);
  });

  testWidgets('juice-only profile hides the Mythic command', (tester) async {
    await pumpPalette(tester, data, prefs: const {
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1","systems":["juice"]}]}',
    });
    await tester.enterText(find.byKey(const Key('journal-composer')), '/fate');
    await tester.pump();
    expect(find.text('Fate Check (Juice)'), findsOneWidget);
    expect(find.text('Fate Check (Roll High)'), findsOneWidget); // rides juice
    expect(find.text('Fate Check (Mythic)'), findsNothing); // mythic off
  });

  testWidgets('bare / then Enter does nothing (no silent roll)',
      (tester) async {
    await pumpPalette(tester, data);

    await tester.enterText(find.byKey(const Key('journal-composer')), '/');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    final container =
        ProviderScope.containerOf(tester.element(find.byType(JournalScreen)));
    final entries = await container.read(journalProvider.future);
    expect(entries, isEmpty);
  });
}
