import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/state/play_context.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('sets and persists the active character per session', () async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);

    await c.read(playContextProvider.future);
    await c.read(playContextProvider.notifier).setActiveCharacter('c1');
    expect(c.read(playContextProvider).valueOrNull?.activeCharacterId, 'c1');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('juice.context.v1.default'), isNotNull);
  });

  test('reload restores persisted context', () async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.context.v1.default': '{"activeSceneId":"s9"}',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final ctx = await c.read(playContextProvider.future);
    expect(ctx.activeSceneId, 's9');
  });

  test('setActiveCharacter(null) clears only that pointer', () async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.context.v1.default':
          '{"activeCharacterId":"c1","activeSceneId":"s1"}',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(playContextProvider.future);
    await c.read(playContextProvider.notifier).setActiveCharacter(null);
    final ctx = c.read(playContextProvider).valueOrNull!;
    expect(ctx.activeCharacterId, isNull);
    expect(ctx.activeSceneId, 's1');
  });

  test('context is scoped per session id', () async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"a","sessions":[{"id":"a","name":"A"},{"id":"b","name":"B"}]}',
      'juice.context.v1.a': '{"activeCharacterId":"ca"}',
      'juice.context.v1.b': '{"activeCharacterId":"cb"}',
    });
    final ca = ProviderContainer();
    addTearDown(ca.dispose);
    expect((await ca.read(playContextProvider.future)).activeCharacterId, 'ca');

    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"b","sessions":[{"id":"a","name":"A"},{"id":"b","name":"B"}]}',
      'juice.context.v1.a': '{"activeCharacterId":"ca"}',
      'juice.context.v1.b': '{"activeCharacterId":"cb"}',
    });
    final cb = ProviderContainer();
    addTearDown(cb.dispose);
    expect((await cb.read(playContextProvider.future)).activeCharacterId, 'cb');
  });
}
