import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juice_oracle/engine/oracle_interpreter.dart';
import 'package:juice_oracle/features/journal_screen.dart';
import 'package:juice_oracle/state/interpreter.dart';
import 'package:juice_oracle/state/providers.dart';

import 'fake_interpreter.dart';

void main() {
  const journalJson =
      '[{"id":"2","timestamp":"2026-06-11T12:00:00.000","title":"Fate Check (Likely)","body":"Yes, and…","kind":"result"},'
      '{"id":"1","timestamp":"2026-06-11T11:00:00.000","title":"The burned mill","body":"","kind":"scene","chaosFactor":5}]';

  Future<(FakeInterpreterService, ProviderContainer)> pump(
      WidgetTester tester,
      {InterpreterStatus? initial, String journal = journalJson}) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.journal.v2.default': journal,
    });
    final fake = FakeInterpreterService(
        initial: initial ?? const InterpreterStatus(InterpreterPhase.ready));
    await tester.pumpWidget(ProviderScope(
      overrides: [interpreterServiceProvider.overrideWithValue(fake)],
      child: const MaterialApp(home: Scaffold(body: JournalScreen())),
    ));
    await tester.pumpAndSettle();
    final container =
        ProviderScope.containerOf(tester.element(find.byType(JournalScreen)));
    return (fake, container);
  }

  Future<void> openMenuFor(WidgetTester tester, String entryTitle) async {
    final entry = find.ancestor(
        of: find.text(entryTitle), matching: find.byType(Card));
    await tester.tap(find.descendant(
        of: entry, matching: find.byType(PopupMenuButton<String>)));
    await tester.pumpAndSettle();
  }

  testWidgets('result entries get Interpret; accept appends the reading',
      (tester) async {
    final (fake, container) = await pump(tester);
    fake.queuedResults.add(const [
      OracleInterpretation(lens: 'symbolic', reading: 'The road closes'),
    ]);
    await openMenuFor(tester, 'Fate Check (Likely)');
    await tester.tap(find.text('Interpret…'));
    await tester.pumpAndSettle();
    // Sheet generated one card from the queue; accept it.
    await tester.tap(find.byKey(const Key('interp-accept-0')));
    await tester.pumpAndSettle();
    final entries = container.read(journalProvider).valueOrNull!;
    final entry = entries.firstWhere((e) => e.id == '2');
    expect(entry.body,
        'Yes, and…\n\n— Oracle reading (symbolic): The road closes');
    // Sheet closed after accept.
    expect(find.byKey(const Key('interp-accept-0')), findsNothing);
    // Seed carried the entry text and the latest scene as context.
    expect(fake.lastSeed?.resultText, 'Fate Check (Likely)\nYes, and…');
    expect(fake.lastSeed?.sceneContext, 'Scene: The burned mill (Chaos 5)');
  });

  testWidgets('interpret seed recalls related entries, not unrelated ones',
      (tester) async {
    // Newest-first: target, a related result (shares 'Magistrate'), an
    // unrelated result, and the scene divider.
    const recallJournal =
        '[{"id":"4","timestamp":"2026-06-11T13:00:00.000","title":"Fate Check (Likely)","body":"The Magistrate relents.","kind":"result"},'
        '{"id":"3","timestamp":"2026-06-11T12:00:00.000","title":"Omen draw","body":"The Magistrate sealed the mill.","kind":"result"},'
        '{"id":"2","timestamp":"2026-06-11T11:00:00.000","title":"Supply roll","body":"Rations run low.","kind":"result"},'
        '{"id":"1","timestamp":"2026-06-11T10:00:00.000","title":"The burned mill","body":"","kind":"scene","chaosFactor":5}]';
    final (fake, _) = await pump(tester, journal: recallJournal);
    await openMenuFor(tester, 'Fate Check (Likely)');
    await tester.tap(find.text('Interpret…'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('interp-accept-0')));
    await tester.pumpAndSettle();
    // Related entry rides along as 'title — body'; the unrelated entry and
    // the target's own text do not.
    expect(fake.lastSeed!.journalContext,
        ['Omen draw — The Magistrate sealed the mill.']);
  });

  testWidgets('accepting after the entry was deleted drops the reading',
      (tester) async {
    final (fake, container) = await pump(tester);
    fake.queuedResults.add(const [
      OracleInterpretation(lens: 'symbolic', reading: 'The road closes'),
    ]);
    await openMenuFor(tester, 'Fate Check (Likely)');
    await tester.tap(find.text('Interpret…'));
    await tester.pumpAndSettle();
    // Entry vanishes while the sheet is still open.
    await container.read(journalProvider.notifier).remove('2');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('interp-accept-0')));
    await tester.pumpAndSettle();
    // No crash, nothing resurrected: only the scene remains.
    final entries = container.read(journalProvider).valueOrNull!;
    expect(entries.where((e) => e.id == '2'), isEmpty);
    expect(entries, hasLength(1));
  });

  testWidgets('scene/text entries do not offer Interpret', (tester) async {
    await pump(tester);
    // The scene row's menu (scene renders as a divider row, not a Card):
    final sceneMenu = find.byType(PopupMenuButton<String>).last;
    await tester.tap(sceneMenu);
    await tester.pumpAndSettle();
    expect(find.text('Interpret…'), findsNothing);
  });

  testWidgets('unsupported service hides Interpret on result entries',
      (tester) async {
    await pump(tester,
        initial: const InterpreterStatus(InterpreterPhase.unsupported));
    await openMenuFor(tester, 'Fate Check (Likely)');
    expect(find.text('Interpret…'), findsNothing);
  });
}
