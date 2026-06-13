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

const _juiceSessionPrefs = {
  'juice.sessions.v1':
      '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
};

const _mythicSessionPrefs = {
  'juice.sessions.v1':
      '{"active":"default","sessions":[{"id":"default","name":"C1","systems":["mythic"]}]}',
  'juice.settings.v1.default':
      '{"genre":"","tone":"","defaultOracle":"mythic"}',
};

Future<void> pumpAsk(WidgetTester tester, OracleData data,
    {Map<String, Object>? prefs}) async {
  SharedPreferences.setMockInitialValues(prefs ?? _juiceSessionPrefs);
  final fake = FakeInterpreterService(
      initial: const InterpreterStatus(InterpreterPhase.ready));
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

  testWidgets('typing a question ending in ? shows the ask chip',
      (tester) async {
    await pumpAsk(tester, data);

    await tester.enterText(
        find.byKey(const Key('journal-composer')), 'Is the door locked?');
    await tester.pump();

    expect(find.byKey(const Key('ask-chip')), findsOneWidget);
  });

  testWidgets('plain text does NOT show the ask chip', (tester) async {
    await pumpAsk(tester, data);

    await tester.enterText(
        find.byKey(const Key('journal-composer')), 'just a note');
    await tester.pump();

    expect(find.byKey(const Key('ask-chip')), findsNothing);
  });

  testWidgets('? chip not shown when slash is active', (tester) async {
    await pumpAsk(tester, data);

    await tester.enterText(find.byKey(const Key('journal-composer')), '/fate?');
    await tester.pump();

    // slash is active, so ask chip must not show
    expect(find.byKey(const Key('ask-chip')), findsNothing);
    expect(find.byKey(const Key('slash-palette')), findsOneWidget);
  });

  testWidgets(
      'tapping ask chip for juice campaign shows Unlikely/Normal/Likely options',
      (tester) async {
    await pumpAsk(tester, data);

    await tester.enterText(
        find.byKey(const Key('journal-composer')), 'Is the door locked?');
    await tester.pump();

    await tester.tap(find.byKey(const Key('ask-chip')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ask-odds-unlikely')), findsOneWidget);
    expect(find.byKey(const Key('ask-odds-normal')), findsOneWidget);
    expect(find.byKey(const Key('ask-odds-likely')), findsOneWidget);
  });

  testWidgets(
      'picking Likely logs one entry with question as title and clears composer',
      (tester) async {
    await pumpAsk(tester, data);

    const question = 'Is the door locked?';
    await tester.enterText(find.byKey(const Key('journal-composer')), question);
    await tester.pump();

    await tester.tap(find.byKey(const Key('ask-chip')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ask-odds-likely')));
    await tester.pumpAndSettle();

    // Composer cleared
    final composerField =
        tester.widget<TextField>(find.byKey(const Key('journal-composer')));
    expect(composerField.controller?.text, '');

    // One entry with the question as title, command = fate-juice, odds = likely
    final container =
        ProviderScope.containerOf(tester.element(find.byType(JournalScreen)));
    final entries = await container.read(journalProvider.future);
    expect(entries.length, 1);
    expect(entries.first.title, question);
    expect(entries.first.sourceTool, 'fate-check');
    final args = entries.first.payload?['args'] as Map?;
    expect(args?['odds'], 'likely');
  });

  testWidgets('/ask appears in the slash palette when typed', (tester) async {
    await pumpAsk(tester, data);

    await tester.enterText(find.byKey(const Key('journal-composer')), '/ask');
    await tester.pump();

    expect(find.byKey(const Key('slash-cmd-ask')), findsOneWidget);
  });

  testWidgets('tapping slash-cmd-ask with question in rest opens odds picker',
      (tester) async {
    await pumpAsk(tester, data);

    await tester.enterText(
        find.byKey(const Key('journal-composer')), '/ask Is the guard asleep?');
    await tester.pump();

    await tester.tap(find.byKey(const Key('slash-cmd-ask')));
    await tester.pumpAndSettle();

    // Odds picker should appear
    expect(find.byKey(const Key('ask-odds-normal')), findsOneWidget);
  });

  testWidgets('mythic campaign shows kMythicOdds in the picker',
      (tester) async {
    await pumpAsk(tester, data, prefs: _mythicSessionPrefs);

    await tester.enterText(
        find.byKey(const Key('journal-composer')), 'Is the gate open?');
    await tester.pump();

    await tester.tap(find.byKey(const Key('ask-chip')));
    await tester.pumpAndSettle();

    // 50/50 is one of the mythic odds options
    expect(find.byKey(const Key('ask-odds-50/50')), findsOneWidget);
    // Juice-only option should not appear
    expect(find.byKey(const Key('ask-odds-normal')), findsNothing);
  });

  testWidgets('/ask <question> via Enter runs the picker and logs the entry',
      (tester) async {
    await pumpAsk(tester, data);

    await tester.enterText(find.byKey(const Key('journal-composer')),
        '/ask Is the guard sleeping?');
    await tester.pump();
    // Submit via Enter — same path other slash commands use.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ask-odds-normal')), findsOneWidget);
    await tester.tap(find.byKey(const Key('ask-odds-normal')));
    await tester.pumpAndSettle();

    final container =
        ProviderScope.containerOf(tester.element(find.byType(JournalScreen)));
    final entries = await container.read(journalProvider.future);
    expect(entries.length, 1);
    expect(entries.first.title, 'Is the guard sleeping?');
  });
}
