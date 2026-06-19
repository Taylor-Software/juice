import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/state/play_context.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:juice_oracle/state/suggestions_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('empty campaign → roll-oracle + start-scene', () async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.journal.v2.default': '[]',
      'juice.threads.v1.default': '[]',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    // Sync provider over async sources: await the sources first, then read.
    await c.read(journalProvider.future);
    await c.read(threadsProvider.future);
    final ids = c.read(suggestionsProvider).map((e) => e.id).toList();
    expect(ids, contains('roll-oracle'));
    expect(ids, contains('start-scene'));
  });

  test('open thread + a scene → advance-thread + scene-event', () async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.journal.v2.default':
          '[{"id":"s1","timestamp":"2026-06-18T00:00:00.000","title":"Scene","body":"","kind":"scene","tags":[]}]',
      'juice.threads.v1.default':
          '[{"id":"t1","title":"Find it","note":"","open":true,"pinned":false}]',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(journalProvider.future);
    await c.read(threadsProvider.future);
    final ids = c.read(suggestionsProvider).map((e) => e.id);
    expect(ids, containsAll(['scene-event', 'advance-thread']));
  });

  // Ironsworn family + focus character: make-move is party-only — present in
  // party mode (Moves visible), absent in gm mode (Moves hidden).
  Map<String, Object> seedMove(String mode) => {
        'juice.sessions.v1':
            '{"active":"default","sessions":[{"id":"default","name":"C1",'
                '"systems":["ironsworn"],"mode":"$mode"}]}',
        'juice.journal.v2.default':
            '[{"id":"s1","timestamp":"2026-06-18T00:00:00.000","title":"Scene","body":"","kind":"scene","tags":[]}]',
        'juice.threads.v1.default': '[]',
        'juice.rulesets.v1': '["classic"]',
        'juice.context.v1.default': '{"activeCharacterId":"c1"}',
      };

  Future<List<String>> resolveIds(ProviderContainer c) async {
    await c.read(journalProvider.future);
    await c.read(threadsProvider.future);
    await c.read(rulesetsProvider.future);
    await c.read(playContextProvider.future);
    await c.read(sessionsProvider.future);
    return c.read(suggestionsProvider).map((e) => e.id).toList();
  }

  test('ironsworn focus character → make-move present in party mode', () async {
    SharedPreferences.setMockInitialValues(seedMove('party'));
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(await resolveIds(c), contains('make-move'));
  });

  test('ironsworn focus character → make-move absent in gm mode', () async {
    SharedPreferences.setMockInitialValues(seedMove('gm'));
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(await resolveIds(c), isNot(contains('make-move')));
  });
}
