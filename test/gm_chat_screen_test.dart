import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/features/gm_chat_screen.dart';
import 'package:juice_oracle/state/gm_chat.dart';
import 'package:juice_oracle/state/interpreter.dart';
import 'package:juice_oracle/state/play_context.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_interpreter.dart';

Future<ProviderContainer> pumpChat(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({
    'juice.sessions.v1':
        '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
  });
  final fake = FakeInterpreterService();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      interpreterServiceProvider.overrideWithValue(fake),
      aiReadyProvider.overrideWith((ref) => true),
    ],
    child: const MaterialApp(home: GmChatScreen()),
  ));
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(GmChatScreen)));
}

void main() {
  testWidgets('sending a message appends a player then a GM bubble',
      (tester) async {
    final container = await pumpChat(tester);
    await tester.enterText(
        find.byKey(const Key('gm-chat-input')), 'Is the bridge safe?');
    await tester.tap(find.byKey(const Key('gm-chat-send')));
    await tester.pumpAndSettle();
    final turns = container.read(gmChatProvider).valueOrNull!.turns;
    expect(turns, hasLength(2));
    expect(turns.first.text, 'Is the bridge safe?');
    expect(turns.last.text, 'A canned GM reply.'); // from the fake
    expect(find.text('A canned GM reply.'), findsOneWidget);
  });

  testWidgets('gm chat grounds on the pinned (older) scene', (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.journal.v2.default':
          '[{"id":"s2","timestamp":"2026-06-12T10:02:00.000","title":"Newer Scene","body":"","kind":"scene"},'
              '{"id":"s1","timestamp":"2026-06-12T10:00:00.000","title":"Pinned Scene","body":"","kind":"scene"}]',
    });
    final fake = FakeInterpreterService();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        interpreterServiceProvider.overrideWithValue(fake),
        aiReadyProvider.overrideWith((ref) => true),
      ],
      child: const MaterialApp(home: GmChatScreen()),
    ));
    await tester.pumpAndSettle();
    final c =
        ProviderScope.containerOf(tester.element(find.byType(GmChatScreen)));
    // The standalone chat screen doesn't display the journal, so load it
    // explicitly (in-app it's opened from the Journal verb, already loaded).
    await c.read(journalProvider.future);
    await c
        .read(playContextProvider.notifier)
        .setActiveScene('s1'); // pin older
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('gm-chat-input')), 'What now?');
    await tester.tap(find.byKey(const Key('gm-chat-send')));
    await tester.pumpAndSettle();
    expect(fake.lastGmChatSeed!.sceneTitle, 'Pinned Scene');
  });

  testWidgets('save-to-journal writes a gm-chat entry', (tester) async {
    final container = await pumpChat(tester);
    await tester.enterText(find.byKey(const Key('gm-chat-input')), 'Hello?');
    await tester.tap(find.byKey(const Key('gm-chat-send')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('gm-chat-save-1'))); // the GM turn
    await tester.pumpAndSettle();
    final entries = container.read(journalProvider).valueOrNull ?? const [];
    expect(entries.where((e) => e.sourceTool == 'gm-chat'), hasLength(1));
  });

  testWidgets('a GM error keeps the player turn + shows a snackbar',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    });
    final fake = FakeInterpreterService()..gmChatError = StateError('boom');
    await tester.pumpWidget(ProviderScope(
      overrides: [
        interpreterServiceProvider.overrideWithValue(fake),
        aiReadyProvider.overrideWith((ref) => true),
      ],
      child: const MaterialApp(home: GmChatScreen()),
    ));
    await tester.pumpAndSettle();
    final container =
        ProviderScope.containerOf(tester.element(find.byType(GmChatScreen)));
    await tester.enterText(find.byKey(const Key('gm-chat-input')), 'Hi?');
    await tester.tap(find.byKey(const Key('gm-chat-send')));
    await tester.pumpAndSettle();
    final turns = container.read(gmChatProvider).valueOrNull!.turns;
    expect(turns, hasLength(1)); // player turn stays; no GM turn
    expect(turns.single.text, 'Hi?');
    expect(find.textContaining('did not answer'), findsOneWidget);
  });

  testWidgets('clear empties the thread', (tester) async {
    final container = await pumpChat(tester);
    await tester.enterText(find.byKey(const Key('gm-chat-input')), 'Hi');
    await tester.tap(find.byKey(const Key('gm-chat-send')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('gm-chat-clear')));
    await tester.pumpAndSettle();
    expect(container.read(gmChatProvider).valueOrNull!.turns, isEmpty);
  });
}
