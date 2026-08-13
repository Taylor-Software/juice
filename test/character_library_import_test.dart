import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loreseer/engine/models.dart';
import 'package:loreseer/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('addFromLibrary copies with fresh id, pc role, no star/magic link',
      () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    const entry = Character(
        id: 'lib-1',
        name: 'Brakka',
        starred: true,
        role: CharacterRole.npc,
        polarityId: 'pg-9');
    final id =
        await container.read(charactersProvider.notifier).addFromLibrary(entry);
    final roster = await container.read(charactersProvider.future);
    final added = roster.firstWhere((c) => c.id == id);
    expect(id, isNot('lib-1'));
    expect(added.name, 'Brakka');
    expect(added.role, CharacterRole.pc);
    expect(added.starred, isFalse);
    expect(added.polarityId, isNull);
  });

  test('sessionCharactersFromPrefs reads another session tolerantly', () async {
    SharedPreferences.setMockInitialValues({
      'loreseer.characters.v1.other':
          '[{"id":"x","name":"Xa"},{"corrupt":true}]',
    });
    final prefs = await SharedPreferences.getInstance();
    final list = sessionCharactersFromPrefs(prefs, 'other');
    expect(list.single.name, 'Xa');
    expect(sessionCharactersFromPrefs(prefs, 'missing'), isEmpty);
  });
}
