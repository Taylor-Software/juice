import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/shared/home_shell.dart' show campaignSubtitle;
import 'package:juice_oracle/state/providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Session models', () {
    test('SessionMeta json round-trip', () {
      const m = SessionMeta(id: 'abc', name: 'West Marches');
      final back = SessionMeta.fromJson(m.toJson());
      expect(back.id, 'abc');
      expect(back.name, 'West Marches');
    });

    test('SessionMeta identity color/icon survive json + copyWith', () {
      const m = SessionMeta(
        id: 'abc',
        name: 'West Marches',
        identityColor: 0xFF5B7A52,
        identityIcon: 'castle',
      );
      final json = m.toJson();
      expect(json['identityColor'], 0xFF5B7A52);
      expect(json['identityIcon'], 'castle');
      final back = SessionMeta.fromJson(json);
      expect(back.identityColor, 0xFF5B7A52);
      expect(back.identityIcon, 'castle');
      // copyWith preserves both, and can override.
      expect(back.copyWith().identityColor, 0xFF5B7A52);
      final swapped = back.copyWith(identityColor: 0xFF4A5A8A);
      expect(swapped.identityColor, 0xFF4A5A8A);
      expect(swapped.identityIcon, 'castle');
    });

    test('SessionMeta omits identity keys when null', () {
      const m = SessionMeta(id: 'abc', name: 'Plain');
      final json = m.toJson();
      expect(json.containsKey('identityColor'), isFalse);
      expect(json.containsKey('identityIcon'), isFalse);
      expect(SessionMeta.fromJson(json).identityColor, isNull);
      expect(SessionMeta.fromJson(json).identityIcon, isNull);
    });

    test('SessionMeta genre survives json + copyWith, omitted when null', () {
      const m =
          SessionMeta(id: 'abc', name: 'West Marches', genre: 'Dark fantasy');
      final json = m.toJson();
      expect(json['genre'], 'Dark fantasy');
      final back = SessionMeta.fromJson(json);
      expect(back.genre, 'Dark fantasy');
      // copyWith preserves, and can override.
      expect(back.copyWith().genre, 'Dark fantasy');
      expect(back.copyWith(genre: 'Cozy mystery').genre, 'Cozy mystery');

      const plain = SessionMeta(id: 'p', name: 'Plain');
      expect(plain.toJson().containsKey('genre'), isFalse);
      expect(SessionMeta.fromJson(plain.toJson()).genre, isNull);
    });

    test('campaignSubtitle prefixes genre when set, systems-only when null',
        () {
      const withGenre = SessionMeta(
        id: 'a',
        name: 'A',
        systems: ['dnd'],
        genre: 'Dark fantasy',
      );
      expect(campaignSubtitle(withGenre),
          'Dark fantasy · ${formatSystems(withGenre.enabledSystems)}');

      const noGenre = SessionMeta(id: 'b', name: 'B', systems: ['dnd']);
      expect(campaignSubtitle(noGenre), formatSystems(noGenre.enabledSystems));
      expect(campaignSubtitle(noGenre), isNot(contains('·')));
    });

    test('identityHueFor returns a palette hue and varies across campaigns',
        () {
      for (var i = 0; i < 5; i++) {
        expect(kIdentityHues, contains(identityHueFor('s$i', i)));
      }
      // Varied across at least two distinct hues for sequential campaigns.
      final hues = {for (var i = 0; i < 5; i++) identityHueFor('id', i)};
      expect(hues.length, greaterThan(1));
    });

    test('identityIconKeyFor picks the ruleset icon, else a mode default', () {
      expect(identityIconKeyFor({'dnd', 'juice', 'party'}, CampaignMode.party),
          'castle');
      expect(identityIconKeyFor({'shadowdark', 'juice'}, CampaignMode.party),
          'dark_mode');
      // No ruleset → casino (party) / book (gm).
      expect(identityIconKeyFor({'juice', 'mythic'}, CampaignMode.party),
          'casino');
      expect(identityIconKeyFor({'juice', 'mythic'}, CampaignMode.gm), 'book');
    });

    test('SessionsState json round-trip and activeMeta lookup', () {
      const s = SessionsState(active: 'b', sessions: [
        SessionMeta(id: 'a', name: 'One'),
        SessionMeta(id: 'b', name: 'Two'),
      ]);
      final back = SessionsState.fromJson(s.toJson());
      expect(back.active, 'b');
      expect(back.sessions.length, 2);
      expect(back.activeMeta.name, 'Two');
    });

    test('activeMeta falls back to first session when active id is stale', () {
      const s = SessionsState(active: 'gone', sessions: [
        SessionMeta(id: 'a', name: 'One'),
      ]);
      expect(s.activeMeta.name, 'One');
    });
  });

  group('Sessions provider', () {
    test('first run migrates legacy keys into a default session', () async {
      SharedPreferences.setMockInitialValues({
        'juice.threads.v1':
            '[{"id":"t1","title":"Old vow","note":"","open":true}]',
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final s = await container.read(sessionsProvider.future);
      expect(s.active, 'default');
      expect(s.sessions.single.name, 'Campaign 1');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('juice.threads.v1'), isNull);
      expect(prefs.getString('juice.threads.v1.default'), contains('Old vow'));
    });

    test('fresh install creates the default session with no key shuffling',
        () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final s = await container.read(sessionsProvider.future);
      expect(s.active, 'default');
      expect(s.sessions.length, 1);
    });

    test('create switches to the new session; remove purges its keys',
        () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(sessionsProvider.future);
      final notifier = container.read(sessionsProvider.notifier);

      await notifier.create('Hexcrawl');
      var s = await container.read(sessionsProvider.future);
      expect(s.sessions.length, 2);
      expect(s.activeMeta.name, 'Hexcrawl');
      final newId = s.active;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('juice.threads.v1.$newId', '["junk"]');
      await notifier.remove(newId);
      s = await container.read(sessionsProvider.future);
      expect(s.sessions.length, 1);
      expect(s.active, 'default');
      expect(prefs.getString('juice.threads.v1.$newId'), isNull);
    });

    test('exportActive carries journal v2', () async {
      SharedPreferences.setMockInitialValues({
        'juice.sessions.v1':
            '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
        'juice.journal.v2.default':
            '[{"id":"n","timestamp":"2026-06-11T10:00:00.000","title":"New","body":"x","kind":"text"}]',
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(sessionsProvider.future);
      final file =
          await container.read(sessionsProvider.notifier).exportActive();
      final data = (jsonDecode(file) as Map<String, dynamic>)['data']
          as Map<String, dynamic>;
      expect(data, contains('juice.journal.v2'));
    });

    test('cannot remove the last session', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(sessionsProvider.future);
      await container.read(sessionsProvider.notifier).remove('default');
      final s = await container.read(sessionsProvider.future);
      expect(s.sessions.length, 1);
    });

    test('editSystems replaces a session\'s enabled systems', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(sessionsProvider.future);
      final notifier = container.read(sessionsProvider.notifier);

      await notifier.editSystems('default', {'juice', 'lonelog'});
      final s = await container.read(sessionsProvider.future);
      final meta = s.sessions.firstWhere((m) => m.id == 'default');
      expect(meta.enabledSystems, {'juice', 'lonelog'});
    });

    test('exportActiveAsLonelog renders title + a thread tag', () async {
      SharedPreferences.setMockInitialValues({
        'juice.sessions.v1':
            '{"active":"default","sessions":[{"id":"default","name":"Lonelog Camp"}]}',
        'juice.threads.v1.default':
            '[{"id":"t1","title":"Slay the wyrm","note":"","open":true}]',
        'juice.journal.v2.default':
            '[{"id":"n","timestamp":"2026-06-11T10:00:00.000","title":"Note","body":"hi","kind":"text"}]',
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(sessionsProvider.future);

      final md = await container
          .read(sessionsProvider.notifier)
          .exportActiveAsLonelog();
      expect(md, contains('title: "Lonelog Camp"'));
      expect(md, contains('[Thread:Slay the wyrm|Open]'));
      expect(md, contains('## Session log'));
    });

    test('importLonelog creates a new session from the header + STATE',
        () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(sessionsProvider.future);
      const md = '---\ntitle: "Imported Game"\n---\n\n'
          '[STATE]\n[Thread:Find the heir|Open]\n[/STATE]\n\n'
          '## Session log\n\n### S1 *opening*\n';

      await container.read(sessionsProvider.notifier).importLonelog(md);
      final s = await container.read(sessionsProvider.future);
      expect(s.activeMeta.name, 'Imported Game');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('juice.threads.v1.${s.active}'),
          contains('Find the heir'));
    });

    test('importLonelog rejects a non-Lonelog file', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(sessionsProvider.future);
      expect(
        () => container
            .read(sessionsProvider.notifier)
            .importLonelog('just some prose, no markers'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('Session-scoped stores', () {
    test('threads are isolated per session and survive switching back',
        () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(sessionsProvider.future);

      await container.read(threadsProvider.future);
      await container.read(threadsProvider.notifier).add('Slay the wyrm');
      expect((await container.read(threadsProvider.future)).length, 1);

      await container.read(sessionsProvider.notifier).create('Second');
      expect(await container.read(threadsProvider.future), isEmpty);

      await container.read(sessionsProvider.notifier).switchTo('default');
      final back = await container.read(threadsProvider.future);
      expect(back.single.title, 'Slay the wyrm');
    });

    test('crawl state is isolated per session', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(sessionsProvider.future);

      await container.read(crawlProvider.future);
      await container
          .read(crawlProvider.notifier)
          .save(const CrawlState(envRow: 7, lost: true));

      await container.read(sessionsProvider.notifier).create('Second');
      final fresh = await container.read(crawlProvider.future);
      expect(fresh.envRow, isNull);
      expect(fresh.lost, isFalse);

      await container.read(sessionsProvider.notifier).switchTo('default');
      final restored = await container.read(crawlProvider.future);
      expect(restored.envRow, 7);
      expect(restored.lost, isTrue);
    });
  });
}
