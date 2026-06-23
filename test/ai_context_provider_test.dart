import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/state/play_context.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('activeCharacterLineProvider resolves the active PC, else empty',
      () async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.characters.v1.default':
          '[{"id":"c1","name":"Taurin","role":"pc","conditions":["wounded"]}]',
      'juice.context.v1.default': '{"activeCharacterId":"c1"}',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(charactersProvider.future);
    await c.read(playContextProvider.future);
    expect(c.read(activeCharacterLineProvider), 'Taurin (PC) — wounded');
  });

  test('activeCharacterLineProvider is empty when no active character',
      () async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(charactersProvider.future);
    await c.read(playContextProvider.future);
    expect(c.read(activeCharacterLineProvider), '');
  });
}
