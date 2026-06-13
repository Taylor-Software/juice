import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juice_oracle/state/providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('togglePinned flips fresh and persists', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(threadsProvider.notifier);
    await c.read(threadsProvider.future);
    await n.add('Vow');
    final id = (await c.read(threadsProvider.future)).first.id;
    await n.togglePinned(id);
    expect((await c.read(threadsProvider.future)).first.pinned, isTrue);
    await n.togglePinned(id);
    expect((await c.read(threadsProvider.future)).first.pinned, isFalse);
  });

  test('toggleStarred flips fresh and persists', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(charactersProvider.notifier);
    await c.read(charactersProvider.future);
    await n.add('Hero');
    final id = (await c.read(charactersProvider.future)).first.id;
    await n.toggleStarred(id);
    expect((await c.read(charactersProvider.future)).first.starred, isTrue);
    await n.toggleStarred(id);
    expect((await c.read(charactersProvider.future)).first.starred, isFalse);
  });

  test('setDefaultOracle persists and preserves genre/tone', () async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.settings.v1.default':
          '{"genre":"noir","tone":"grim","defaultOracle":"juice"}',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(settingsProvider.future);
    await c.read(settingsProvider.notifier).setDefaultOracle('mythic');
    final s = await c.read(settingsProvider.future);
    expect(s.defaultOracle, 'mythic');
    expect(s.genre, 'noir');
    expect(s.tone, 'grim');
  });

  test('setHeaderCollapsed persists and preserves genre/tone', () async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.settings.v1.default':
          '{"genre":"space","tone":"terse","defaultOracle":"juice"}',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(settingsProvider.future);
    await c.read(settingsProvider.notifier).setHeaderCollapsed(true);
    final s = await c.read(settingsProvider.future);
    expect(s.headerCollapsed, isTrue);
    expect(s.genre, 'space');
    expect(s.tone, 'terse');
  });

  test('setChaos clamps and persists', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(crawlProvider.future);
    await c.read(crawlProvider.notifier).setChaos(7);
    expect((await c.read(crawlProvider.future)).chaosFactor, 7);
    await c.read(crawlProvider.notifier).setChaos(0);
    expect((await c.read(crawlProvider.future)).chaosFactor, 1);
    await c.read(crawlProvider.notifier).setChaos(12);
    expect((await c.read(crawlProvider.future)).chaosFactor, 9);
  });
}
