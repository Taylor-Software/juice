// Device integration tests for this session's AI affordances, driven end-to-end
// through the REAL app shell (HomeShell) with real rootBundle assets and the
// fake interpreter. Unit tests pump isolated panes; these exercise the full
// shell + real pushed routes (the GM-chat dialog) + the journal composer popup,
// catching navigation/wiring bugs the isolated tests miss.
//
// AI runs on the fake interpreter (the real Gemma model is a multi-GB download).
// Drive by widget Key — the app's UI resists synthetic OS clicks (see the
// juice-browser-verify note).
//
// Run: flutter test integration_test/ai_flows_test.dart -d macos

import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/engine/oracle_interpreter.dart';
import 'package:juice_oracle/shared/home_shell.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/interpreter.dart';
import 'package:juice_oracle/state/providers.dart';

import '../test/fake_interpreter.dart';

Future<Oracle> _oracle() async {
  final raw = await rootBundle.loadString('assets/oracle_data.json');
  return Oracle(
      OracleData(jsonDecode(raw) as Map<String, dynamic>), Dice(Random(1)));
}

/// Pump the real HomeShell with a seeded AI-enabled campaign + the fake
/// interpreter. HomeShell lands on the Journal verb (its `build` default), which
/// hosts the assistant rail + the journal composer.
Future<(ProviderContainer, FakeInterpreterService)> _pumpShell(
    WidgetTester tester,
    {Map<String, Object> extraPrefs = const {}}) async {
  SharedPreferences.setMockInitialValues({
    'juice.sessions.v1':
        '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    'juice.ai_enabled.v1': true,
    ...extraPrefs,
  });
  final fake = FakeInterpreterService(
      initial: const InterpreterStatus(InterpreterPhase.ready));
  final oracle = await _oracle();
  await tester.pumpWidget(ProviderScope(
    overrides: [interpreterServiceProvider.overrideWithValue(fake)],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: HomeShell(oracle: oracle),
    ),
  ));
  await tester.pumpAndSettle();
  final c = ProviderScope.containerOf(tester.element(find.byType(HomeShell)));
  return (c, fake);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('narrate: composer popup logs a Narration journal entry',
      (tester) async {
    await _pumpShell(tester);
    await tester.tap(find.byKey(const Key('composer-narrate')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('narrate-continue')));
    await tester.pumpAndSettle();
    // The fake's default narration lands as a journal entry titled "Narration".
    expect(find.text('Narration'), findsWidgets);
    expect(find.textContaining('A canned narration.'), findsWidgets);
  });

  testWidgets('gm-chat: rail Ask-GM opens the chat route and replies',
      (tester) async {
    await _pumpShell(tester);
    await tester.tap(find.byKey(const Key('assistant-expand')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('ask-gm-field')), 'What lurks here?');
    await tester.tap(find.byKey(const Key('ask-gm-send')));
    await tester.pumpAndSettle();
    // showGmChat pushed a fullscreen route; the player turn + the fake GM reply
    // both render in the bubble thread.
    expect(find.textContaining('What lurks here?'), findsWidgets);
    expect(find.textContaining('A canned GM reply.'), findsWidgets);
  });

  testWidgets('ranked chips: expanding the rail shows the AI why caption',
      (tester) async {
    final (_, fake) = await _pumpShell(tester);
    fake.queuedRank.add(const RankResult(
        order: ['scene-event', 'roll-oracle'], why: 'The scene is live'));
    await tester.tap(find.byKey(const Key('assistant-expand')));
    await tester.pumpAndSettle(); // expand + post-frame rank + setState
    expect(find.byKey(const Key('suggest-why')), findsOneWidget);
    expect(find.textContaining('The scene is live'), findsOneWidget);
  });

  testWidgets('scene flesh-out: Track > Scenes appends to the scene body',
      (tester) async {
    await _pumpShell(tester, extraPrefs: {
      'juice.journal.v2.default':
          '[{"id":"s1","timestamp":"2026-06-12T10:00:00.000","title":"At the gate","body":"","kind":"scene"}]',
    });
    // Navigate Journal → Track verb (Scenes is the default subtab).
    await tester.tap(find.text('Track'));
    await tester.pumpAndSettle();
    // Flesh out the seeded scene; accept the review → appends to the body.
    await tester.tap(find.byKey(const Key('flesh-out-scene-s1')));
    await tester.pumpAndSettle(); // fleshOut() + review dialog
    await tester.tap(find.byKey(const Key('flesh-out-append')));
    await tester.pumpAndSettle();
    // The fake's default flesh-out text now shows in the scene row subtitle.
    expect(find.textContaining('Fleshed-out detail.'), findsWidgets);
  });

  // The #146 character + thread flesh-out use the _EditDialog append path (not
  // showFleshOutReview), so they add coverage the scene test doesn't.

  testWidgets('character flesh-out: Sheet roster appends to the note',
      (tester) async {
    final (c, _) = await _pumpShell(tester, extraPrefs: {
      'juice.characters.v1.default':
          '[{"id":"ch1","name":"Ash","note":"A scout.","stats":[],"tracks":[],"tags":[],"role":"npc"}]',
    });
    await tester.tap(find.text('Sheet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ash')); // open the character sheet
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('flesh-out-character')));
    await tester
        .pumpAndSettle(); // fleshOut() + the _EditDialog (note appended)
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final chars = c.read(charactersProvider).valueOrNull!;
    expect(chars.single.note, contains('A scout.')); // preserved
    expect(chars.single.note, contains('Fleshed-out detail.')); // appended
  });

  testWidgets('thread flesh-out: Track > Threads appends to the note',
      (tester) async {
    final (c, _) = await _pumpShell(tester, extraPrefs: {
      'juice.threads.v1.default':
          '[{"id":"t1","title":"Find the Relic","note":"Rumored lost.","open":true}]',
    });
    await tester.tap(find.text('Track'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Threads')); // Track defaults to Scenes; switch
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('flesh-out-thread-t1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final threads = c.read(threadsProvider).valueOrNull!;
    expect(threads.single.note, contains('Rumored lost.')); // preserved
    expect(threads.single.note, contains('Fleshed-out detail.')); // appended
  });
}
