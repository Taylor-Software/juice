import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:loreseer/engine/models.dart';
import 'package:loreseer/state/play_context.dart';
import 'package:loreseer/state/providers.dart';

/// Audit F3: corrupt user-persisted storage (partial write, manual edit)
/// must degrade to the default state — never leave a provider in permanent
/// AsyncError, which the app-wide `valueOrNull ?? default` convention
/// renders as a silently empty screen.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const garbage = '{not json[';

  ProviderContainer container(Map<String, Object> prefs) {
    SharedPreferences.setMockInitialValues(prefs);
    return ProviderContainer();
  }

  test('corrupt sessions registry rebuilds a fresh default', () async {
    final c = container({'loreseer.sessions.v1': garbage});
    addTearDown(c.dispose);
    final s = await c.read(sessionsProvider.future);
    expect(s.active, 'default');
    expect(s.sessions, hasLength(1));
  });

  test('corrupt session-scoped blobs yield defaults, not AsyncError', () async {
    final c = container({
      'loreseer.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'loreseer.crawl.v1.default': garbage,
      'loreseer.decks.v1.default': garbage,
      'loreseer.encounter.v1.default': garbage,
      'loreseer.map.v1.default': garbage,
      'loreseer.settings.v1.default': garbage,
      'loreseer.context.v1.default': garbage,
      'loreseer.journal.v2.default': garbage,
      'loreseer.threads.v1.default': garbage,
    });
    addTearDown(c.dispose);

    expect((await c.read(crawlProvider.future)).chaosFactor,
        const CrawlState().chaosFactor);
    expect((await c.read(decksProvider.future)).standard.drawn,
        const DecksState().standard.drawn);
    expect((await c.read(encounterProvider.future)).combatants, isEmpty);
    expect((await c.read(mapProvider.future)).rooms, isEmpty);
    expect(await c.read(settingsProvider.future), const CampaignSettings());
    expect((await c.read(playContextProvider.future)).activeSceneId, isNull);
    expect(await c.read(journalProvider.future), isEmpty);
    expect(await c.read(threadsProvider.future), isEmpty);
  });

  test('a corrupt row is skipped; surviving rows load', () async {
    final c = container({
      'loreseer.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      // Row 1 is fine; row 2 is missing required fields; row 3 isn't a map.
      'loreseer.journal.v2.default': '['
          '{"id":"good","timestamp":"2026-07-11T00:00:00.000",'
          '"title":"Kept","body":"x","kind":"text"},'
          '{"id":"bad"},'
          '42]',
    });
    addTearDown(c.dispose);
    final journal = await c.read(journalProvider.future);
    expect(journal, hasLength(1));
    expect(journal.single.id, 'good');
  });

  test('corrupt app-global stores yield empty defaults', () async {
    final c = container({
      'loreseer.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'loreseer.bestiary.v1': garbage,
      'loreseer.custom_tables.v1': garbage,
      'loreseer.oracles.v1': garbage,
      'loreseer.userrefcards.v1': garbage,
      'loreseer.rulesets.v1': garbage,
    });
    addTearDown(c.dispose);
    expect(await c.read(bestiaryProvider.future), isEmpty);
    expect(await c.read(customTablesProvider.future), isEmpty);
    expect(await c.read(constructedOraclesProvider.future), isEmpty);
    expect(await c.read(userRefCardsProvider.future), isEmpty);
    expect(await c.read(rulesetsProvider.future), isEmpty);
  });

  test('suggestDismissed + recap are registered session-scoped keys', () {
    expect(sessionScopedKeys, contains('loreseer.suggestDismissed'));
    expect(sessionScopedKeys, contains('loreseer.recap'));
  });

  test('deleting a campaign purges its suggestDismissed/recap keys', () async {
    final c = container({
      'loreseer.sessions.v1': '{"active":"a","sessions":['
          '{"id":"a","name":"A"},{"id":"b","name":"B"}]}',
      'loreseer.suggestDismissed.b': '["chip"]',
      'loreseer.recap.b': '{"sinceId":"x","text":"y"}',
    });
    addTearDown(c.dispose);
    await c.read(sessionsProvider.future);
    await c.read(sessionsProvider.notifier).remove('b');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('loreseer.suggestDismissed.b'), isNull);
    expect(prefs.getString('loreseer.recap.b'), isNull);
  });
}
