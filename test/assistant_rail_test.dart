import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/oracle_interpreter.dart';
import 'package:juice_oracle/features/assistant_rail.dart';
import 'package:juice_oracle/features/gm_chat_screen.dart';
import 'package:juice_oracle/shared/destination.dart';
import 'package:juice_oracle/shared/shell_route.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/interpreter.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_interpreter.dart';

/// [AssistantSection] owns no header and no collapse state — the "Next" panel
/// that hosts it (see `PlayScreen`) builds it only while expanded, so these
/// tests pump the section bare. The collapse behaviour itself, including the
/// no-LLM-spend-when-collapsed guarantee, is covered in
/// `play_screen_layout_test.dart`.
Future<ProviderContainer> _pumpRankSection(
    WidgetTester tester, FakeInterpreterService fake,
    {bool aiEnabled = true}) async {
  // Empty journal (no scenes) + one open thread → two navigate chips
  // (start-scene, advance-thread) to rank. Inline rolls moved to the dock, so
  // ranking now reorders navigate chips only.
  SharedPreferences.setMockInitialValues({
    'juice.sessions.v1':
        '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    'juice.journal.v2.default': '[]',
    'juice.threads.v1.default':
        '[{"id":"t1","title":"The missing heir","open":true}]',
    if (aiEnabled) 'juice.ai_enabled.v1': true,
  });
  final c = ProviderContainer(
      overrides: [interpreterServiceProvider.overrideWithValue(fake)]);
  addTearDown(c.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: AssistantSection()))));
  await tester.pumpAndSettle();
  return c;
}

Future<ProviderContainer> pumpSection(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({
    'juice.sessions.v1':
        '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    'juice.journal.v2.default': '[]',
    'juice.threads.v1.default': '[]',
  });
  final c = ProviderContainer();
  await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: AssistantSection()))));
  await tester.pumpAndSettle();
  return c;
}

void main() {
  testWidgets('navigate chips render as soon as the section is mounted',
      (tester) async {
    await pumpSection(tester);
    expect(find.text('Start a scene'), findsOneWidget);
  });

  testWidgets('section no longer renders the inline roll chips (moved to dock)',
      (tester) async {
    // The inline rolls (roll-oracle / scene-event) live in the journal's
    // always-visible InlineRollDock now; this section shows navigate chips only.
    await pumpSection(tester);
    expect(find.text('Roll the oracle'), findsNothing);
    expect(find.text('Scene event'), findsNothing);
    expect(find.byKey(const Key('suggest-roll-oracle')), findsNothing);
    expect(find.byKey(const Key('suggest-scene-event')), findsNothing);
    // A navigate chip still renders (empty campaign → start-scene).
    expect(find.byKey(const Key('suggest-start-scene')), findsOneWidget);
  });

  testWidgets('navigate chip routes via shellRouteProvider', (tester) async {
    final c = await pumpSection(tester); // empty campaign → start-scene present
    await tester.tap(find.text('Start a scene'));
    await tester.pumpAndSettle();
    final route = c.read(shellRouteProvider);
    expect(route.destination, Destination.track);
    expect(route.subtab, 'scenes');
  });

  testWidgets('shows Develop a rumor and routes to Rumors', (tester) async {
    final c = await pumpSection(tester);
    expect(find.text('Develop a rumor'), findsOneWidget);
    await tester.tap(find.text('Develop a rumor'));
    await tester.pumpAndSettle();
    final route = c.read(shellRouteProvider);
    expect(route.destination, Destination.track);
    expect(route.subtab, 'rumors');
  });

  testWidgets('develop-rumor and seed-npc are always present (no mode gate)',
      (tester) async {
    await pumpSection(tester);
    expect(find.text('Develop a rumor'), findsOneWidget);
    expect(find.text('Add an NPC'), findsOneWidget);
  });

  testWidgets('ask-the-Oracle box opens the multi-turn GM chat', (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.journal.v2.default': '[]',
      'juice.threads.v1.default': '[]',
      'juice.ai_enabled.v1': true,
    });
    final fake = FakeInterpreterService(
      initial: const InterpreterStatus(InterpreterPhase.ready),
    );
    final c = ProviderContainer(overrides: [
      interpreterServiceProvider.overrideWith((ref) => fake),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: AssistantSection()))));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('ask-gm-field')), 'Locked?');
    await tester.tap(find.byKey(const Key('ask-gm-send')));
    await tester.pumpAndSettle();

    // Opens the multi-turn chat (no single-shot auto-log); the first message
    // is sent into it.
    expect(find.byType(GmChatScreen), findsOneWidget);
    expect(fake.gmChatCalls, 1);
    final entries = c.read(journalProvider).valueOrNull ?? const [];
    expect(entries.where((e) => e.sourceTool == 'ask-gm'), isEmpty);
  });

  testWidgets('ask-the-Oracle box is hidden when the model is not ready',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.journal.v2.default': '[]',
      'juice.threads.v1.default': '[]',
      'juice.ai_enabled.v1': true, // enabled, but model not downloaded
    });
    final fake = FakeInterpreterService(); // default: needsDownload
    final c = ProviderContainer(overrides: [
      interpreterServiceProvider.overrideWith((ref) => fake),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: AssistantSection()))));
    await tester.pumpAndSettle();
    // Suggestion chips still render; the AI ask box is gone.
    expect(find.byKey(const Key('ask-gm-field')), findsNothing);
    expect(find.byKey(const Key('ask-gm-send')), findsNothing);
  });

  testWidgets('AI-ranked: navigate chips reordered + why caption when AI ready',
      (tester) async {
    // The section renders navigate chips only now; ranking reorders those.
    final fake = FakeInterpreterService(
        initial: const InterpreterStatus(InterpreterPhase.ready));
    fake.queuedRank.add(const RankResult(
        order: ['advance-thread', 'start-scene'], why: 'A thread is open'));
    await _pumpRankSection(tester, fake); // mount + post-frame rank + setState
    final keys = tester
        .widgetList<ActionChip>(find.byType(ActionChip))
        .map((w) => (w.key! as ValueKey).value)
        .toList();
    expect(keys.indexOf('suggest-advance-thread'),
        lessThan(keys.indexOf('suggest-start-scene')));
    expect(find.byKey(const Key('suggest-why')), findsOneWidget);
    expect(find.textContaining('A thread is open'), findsOneWidget);
  });

  testWidgets('AI off: rule order, no why caption', (tester) async {
    final fake = FakeInterpreterService(
        initial: const InterpreterStatus(InterpreterPhase.unsupported));
    await _pumpRankSection(tester, fake, aiEnabled: false);
    expect(find.byKey(const Key('suggest-why')), findsNothing);
    // First navigate chip in rule order is start-scene (inline rolls dropped).
    final keys = tester
        .widgetList<ActionChip>(find.byType(ActionChip))
        .map((w) => (w.key! as ValueKey).value)
        .toList();
    expect(keys.first, 'suggest-start-scene');
  });
}
