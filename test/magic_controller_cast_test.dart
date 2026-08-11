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
  return ProviderContainer();
}

void main() {
  test('cast deducts mana and logs history; undoCast refunds it', () async {
    final container = _container();
    addTearDown(container.dispose);
    await container.read(magicProvider.future);
    final ctrl = container.read(magicProvider.notifier);
    await ctrl.upsertCharacter(
      const pg.Character(id: 'pg-1', name: 'Ash', baseMana: 8, currentMana: 8),
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

    final result = await ctrl.cast(spell);
    var lib = container.read(magicProvider).valueOrNull!;
    expect(lib.characters.single.currentMana, lessThan(8));
    expect(lib.history.length, 1);

    await ctrl.undoCast('pg-1', result.refund, result.recordId);
    lib = container.read(magicProvider).valueOrNull!;
    expect(lib.characters.single.currentMana, 8);
    expect(lib.history, isEmpty);
  });

  test('rest refills mana to max and logs a rest marker', () async {
    final container = _container();
    addTearDown(container.dispose);
    await container.read(magicProvider.future);
    final ctrl = container.read(magicProvider.notifier);
    await ctrl.upsertCharacter(
      const pg.Character(id: 'pg-1', name: 'Ash', baseMana: 8, currentMana: 2),
    );
    await ctrl.rest('pg-1');
    final lib = container.read(magicProvider).valueOrNull!;
    expect(lib.characters.single.currentMana, 8);
    expect(lib.history.single.kind, pg.CastKind.rest);
  });
}
