import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
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

// Reads the real asset via dart:io (not rootBundle), so no test hang.
Oracle _oracle() => Oracle(OracleData(
    jsonDecode(File('assets/oracle_data.json').readAsStringSync())
        as Map<String, dynamic>));

Future<ProviderContainer> _pumpRankRail(
    WidgetTester tester, FakeInterpreterService fake,
    {bool aiEnabled = true}) async {
  SharedPreferences.setMockInitialValues({
    'juice.sessions.v1':
        '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    'juice.journal.v2.default':
        '[{"id":"s1","timestamp":"2026-06-12T10:00:00.000","title":"At the gate","body":"x","kind":"scene"}]',
    'juice.threads.v1.default': '[]',
    if (aiEnabled) 'juice.ai_enabled.v1': true,
  });
  final c = ProviderContainer(
      overrides: [interpreterServiceProvider.overrideWithValue(fake)]);
  addTearDown(c.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: AssistantRail()))));
  await tester.pumpAndSettle();
  return c;
}

Future<ProviderContainer> pumpRail(WidgetTester tester) async {
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
          home: const Scaffold(body: AssistantRail()))));
  await tester.pumpAndSettle();
  return c;
}

/// The rail is collapsed by default; reveal the chips + ask box.
Future<void> expandRail(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('assistant-expand')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('collapsed by default; chips hidden until expanded',
      (tester) async {
    await pumpRail(tester);
    expect(find.text('Roll the oracle'), findsNothing);
    await expandRail(tester);
    expect(find.text('Roll the oracle'), findsOneWidget);
  });

  testWidgets('inline oracle chip writes a result to the journal',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.journal.v2.default': '[]',
      'juice.threads.v1.default': '[]',
    });
    final c = ProviderContainer(overrides: [
      oracleProvider.overrideWith((ref) async => _oracle()),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: AssistantRail()))));
    await tester.pumpAndSettle();
    await c.read(oracleProvider.future); // resolve the FutureProvider first
    await expandRail(tester);
    await tester.tap(find.text('Roll the oracle'));
    await tester.pumpAndSettle();
    final entries = await c.read(journalProvider.future);
    expect(entries.length, 1);
    expect(entries.first.sourceTool, 'fate-check');
    expect(entries.first.title, contains('Fate Check'));
  });

  testWidgets('inline chip before oracle loads is a safe no-op',
      (tester) async {
    final c = await pumpRail(tester); // oracleProvider not overridden
    await expandRail(tester);
    await tester.tap(find.text('Roll the oracle'));
    await tester.pump();
    // Oracle data isn't loaded in this harness → guarded skip, no entry, no throw.
    expect(c.read(journalProvider).valueOrNull ?? const [], isEmpty);
  });

  testWidgets('navigate chip routes via shellRouteProvider', (tester) async {
    final c = await pumpRail(tester); // empty campaign → start-scene present
    await expandRail(tester);
    await tester.tap(find.text('Start a scene'));
    await tester.pumpAndSettle();
    final route = c.read(shellRouteProvider);
    expect(route.destination, Destination.track);
    expect(route.subtab, 'scenes');
  });

  testWidgets('gm-mode rail shows Develop a rumor and routes to Rumors',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1': '{"active":"default","sessions":[{"id":"default",'
          '"name":"C1","mode":"gm"}]}',
      'juice.journal.v2.default': '[]',
      'juice.threads.v1.default': '[]',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: AssistantRail()))));
    await tester.pumpAndSettle();
    await expandRail(tester);
    expect(find.text('Develop a rumor'), findsOneWidget);
    await tester.tap(find.text('Develop a rumor'));
    await tester.pumpAndSettle();
    final route = c.read(shellRouteProvider);
    expect(route.destination, Destination.track);
    expect(route.subtab, 'rumors');
  });

  testWidgets('party-mode rail omits the gm-only suggestions', (tester) async {
    await pumpRail(tester); // default session → party mode
    await expandRail(tester);
    expect(find.text('Develop a rumor'), findsNothing);
    expect(find.text('Add an NPC'), findsNothing);
  });

  testWidgets('ask-the-GM box opens the multi-turn GM chat', (tester) async {
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
            home: const Scaffold(body: AssistantRail()))));
    await tester.pumpAndSettle();

    await expandRail(tester);
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

  testWidgets('ask-the-GM box is hidden when the model is not ready',
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
            home: const Scaffold(body: AssistantRail()))));
    await tester.pumpAndSettle();
    await expandRail(tester);
    // Suggestion chips still render; the AI ask box is gone.
    expect(find.byKey(const Key('ask-gm-field')), findsNothing);
    expect(find.byKey(const Key('ask-gm-send')), findsNothing);
  });

  testWidgets('AI-ranked: chips reordered + why caption when AI ready',
      (tester) async {
    final fake = FakeInterpreterService(
        initial: const InterpreterStatus(InterpreterPhase.ready));
    fake.queuedRank.add(const RankResult(
        order: ['scene-event', 'roll-oracle'], why: 'The scene is live'));
    await _pumpRankRail(tester, fake);
    await tester.tap(find.byKey(const Key('assistant-expand')));
    await tester.pumpAndSettle(); // expand + post-frame rank + setState
    final keys = tester
        .widgetList<ActionChip>(find.byType(ActionChip))
        .map((w) => (w.key as ValueKey).value)
        .toList();
    expect(keys.indexOf('suggest-scene-event'),
        lessThan(keys.indexOf('suggest-roll-oracle')));
    expect(find.byKey(const Key('suggest-why')), findsOneWidget);
    expect(find.textContaining('The scene is live'), findsOneWidget);
  });

  testWidgets('AI off: rule order, no why caption', (tester) async {
    final fake = FakeInterpreterService(
        initial: const InterpreterStatus(InterpreterPhase.unsupported));
    await _pumpRankRail(tester, fake, aiEnabled: false);
    await tester.tap(find.byKey(const Key('assistant-expand')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('suggest-why')), findsNothing);
    final keys = tester
        .widgetList<ActionChip>(find.byType(ActionChip))
        .map((w) => (w.key as ValueKey).value)
        .toList();
    expect(keys.first, 'suggest-roll-oracle');
  });
}
