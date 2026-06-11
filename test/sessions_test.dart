import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juice_oracle/engine/models.dart';
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
        'juice.threads.v1': '[{"id":"t1","title":"Old vow","note":"","open":true}]',
        'juice.log.v1': '[]',
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

    test('fresh install creates the default session with no key shuffling', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final s = await container.read(sessionsProvider.future);
      expect(s.active, 'default');
      expect(s.sessions.length, 1);
    });

    test('create switches to the new session; remove purges its keys', () async {
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
      await prefs.setString('juice.log.v1.$newId', '["junk"]');
      await notifier.remove(newId);
      s = await container.read(sessionsProvider.future);
      expect(s.sessions.length, 1);
      expect(s.active, 'default');
      expect(prefs.getString('juice.log.v1.$newId'), isNull);
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
  });
}
