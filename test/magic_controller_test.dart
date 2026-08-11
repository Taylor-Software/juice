import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loreseer/state/magic_controller.dart';
import 'package:polarity_grammar/polarity_grammar.dart' as pg;
import 'package:shared_preferences/shared_preferences.dart';

ProviderContainer _container() {
  SharedPreferences.setMockInitialValues({
    'loreseer.sessions.v1':
        '{"active":"c1","sessions":[{"id":"c1","name":"Test"}]}',
  });
  final container = ProviderContainer();
  return container;
}

void main() {
  test('upsertCharacter creates then setMana updates a caster, persisted',
      () async {
    final container = _container();
    addTearDown(container.dispose);
    await container.read(magicProvider.future);
    final ctrl = container.read(magicProvider.notifier);

    await ctrl.upsertCharacter(
      const pg.Character(id: 'pg-1', name: 'Ash', baseMana: 4, currentMana: 4),
    );
    var lib = container.read(magicProvider).valueOrNull!;
    expect(lib.characters.single.name, 'Ash');

    await ctrl.setMana('pg-1', 2);
    lib = container.read(magicProvider).valueOrNull!;
    expect(lib.characters.single.currentMana, 2);
  });

  test('upsertSpell then deleteSpell round-trips the spellbook', () async {
    final container = _container();
    addTearDown(container.dispose);
    await container.read(magicProvider.future);
    final ctrl = container.read(magicProvider.notifier);
    await ctrl.upsertCharacter(
      const pg.Character(id: 'pg-1', name: 'Ash', baseMana: 4, currentMana: 4),
    );

    final spell = pg.Spell(
      id: 's1',
      characterId: 'pg-1',
      name: 'Spark',
      effects: const [
        pg.EffectChoice(pg.CardChoice('effect.sensory.numb', pg.PoleSide.a), 1),
      ],
      form: const pg.CardChoice('form.link', pg.PoleSide.a),
      targets: const [pg.TargetPhrase(count: 1, targetType: 1)],
      size: 0,
      distance: 0,
      timing: 0,
      favorite: false,
      createdAt: DateTime(2026, 1, 1),
      editedAt: DateTime(2026, 1, 1),
    );
    await ctrl.upsertSpell(spell);
    expect(
        container
            .read(magicProvider)
            .valueOrNull!
            .spellsFor('pg-1')
            .single
            .name,
        'Spark');

    await ctrl.deleteSpell('s1');
    expect(
        container.read(magicProvider).valueOrNull!.spellsFor('pg-1'), isEmpty);
  });

  test('deleteCharacter removes the caster and their spells', () async {
    final container = _container();
    addTearDown(container.dispose);
    await container.read(magicProvider.future);
    final ctrl = container.read(magicProvider.notifier);
    await ctrl.upsertCharacter(
      const pg.Character(id: 'pg-1', name: 'Ash', baseMana: 4, currentMana: 4),
    );
    await ctrl.deleteCharacter('pg-1');
    final lib = container.read(magicProvider).valueOrNull!;
    expect(lib.characters, isEmpty);
  });
}
