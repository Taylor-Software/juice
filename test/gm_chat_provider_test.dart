import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/gm_chat.dart';
import 'package:juice_oracle/state/gm_chat.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('appendTurn accumulates + persists; clear empties; key is scoped',
      () async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(gmChatProvider.future);

    await c
        .read(gmChatProvider.notifier)
        .appendTurn(const ChatTurn(ChatRole.player, 'Hi'));
    await c
        .read(gmChatProvider.notifier)
        .appendTurn(const ChatTurn(ChatRole.gm, 'Hello, traveler.'));
    expect(c.read(gmChatProvider).valueOrNull!.turns, hasLength(2));

    // Persisted: a fresh container reads it back.
    final c2 = ProviderContainer();
    addTearDown(c2.dispose);
    final reloaded = await c2.read(gmChatProvider.future);
    expect(reloaded.turns, hasLength(2));
    expect(reloaded.turns.last.text, 'Hello, traveler.');

    await c.read(gmChatProvider.notifier).clear();
    expect(c.read(gmChatProvider).valueOrNull!.turns, isEmpty);
  });

  test('gmchat key is exported with the campaign', () {
    expect(sessionScopedKeys, contains('juice.gmchat.v1'));
  });
}
