import 'dart:convert';

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

pg.Spell _spell(String id, String characterId, String name) => pg.Spell(
      id: id,
      characterId: characterId,
      name: name,
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

String _envelope() => jsonEncode({
      'practicalmagicCharacter': 1,
      'schemaVersion': pg.kSchemaVersion,
      'character': const pg.Character(
              id: 'ext-1', name: 'Vex', baseMana: 6, currentMana: 6)
          .toJson(),
      'spells': [_spell('ext-s1', 'ext-1', 'Spark').toJson()],
    });

Future<MagicController> _readyController(ProviderContainer container) async {
  await container.read(magicProvider.future);
  final ctrl = container.read(magicProvider.notifier);
  await ctrl.upsertCharacter(
    const pg.Character(id: 'pg-1', name: 'Ash', baseMana: 4, currentMana: 4),
  );
  return ctrl;
}

void main() {
  test('importSpells: envelope spells land on the target with fresh ids',
      () async {
    final container = _container();
    addTearDown(container.dispose);
    final ctrl = await _readyController(container);

    final added = await ctrl.importSpells('pg-1', _envelope());

    expect(added, hasLength(1));
    final lib = container.read(magicProvider).valueOrNull!;
    final got = lib.spellsFor('pg-1').single;
    expect(got.name, 'Spark');
    expect(got.characterId, 'pg-1');
    expect(got.id, isNot('ext-s1'));
    // The exported caster is NOT imported — spells only.
    expect(lib.characters.map((c) => c.id), ['pg-1']);
  });

  test('importSpells: library blob flattens all characters\' spells', () async {
    final container = _container();
    addTearDown(container.dispose);
    final ctrl = await _readyController(container);

    final blob = jsonEncode(const pg.Library.empty().copyWith(
      characters: [
        const pg.Character(id: 'a', name: 'A', baseMana: 4, currentMana: 4),
        const pg.Character(id: 'b', name: 'B', baseMana: 4, currentMana: 4),
      ],
      spells: [_spell('sa', 'a', 'Alpha'), _spell('sb', 'b', 'Beta')],
    ).toJson());

    final added = await ctrl.importSpells('pg-1', blob);
    expect(added, hasLength(2));
    expect(
      container
          .read(magicProvider)
          .valueOrNull!
          .spellsFor('pg-1')
          .map((s) => s.name)
          .toSet(),
      {'Alpha', 'Beta'},
    );
  });

  test('importing twice duplicates rather than collides', () async {
    final container = _container();
    addTearDown(container.dispose);
    final ctrl = await _readyController(container);

    await ctrl.importSpells('pg-1', _envelope());
    await ctrl.importSpells('pg-1', _envelope());
    final spells = container.read(magicProvider).valueOrNull!.spellsFor('pg-1');
    expect(spells, hasLength(2));
    expect(spells[0].id, isNot(spells[1].id));
  });

  test('junk throws and the library is untouched', () async {
    final container = _container();
    addTearDown(container.dispose);
    final ctrl = await _readyController(container);

    await expectLater(ctrl.importSpells('pg-1', '{{{'), throwsFormatException);
    expect(
        container.read(magicProvider).valueOrNull!.spellsFor('pg-1'), isEmpty);
  });

  test('unknown target caster throws StateError', () async {
    final container = _container();
    addTearDown(container.dispose);
    final ctrl = await _readyController(container);

    await expectLater(ctrl.importSpells('nope', _envelope()), throwsStateError);
  });

  test('deleteSpells removes exactly the given ids in one commit', () async {
    final container = _container();
    addTearDown(container.dispose);
    final ctrl = await _readyController(container);
    final added = await ctrl.importSpells('pg-1', _envelope());
    await ctrl.upsertSpell(_spell('keep', 'pg-1', 'Keeper'));

    await ctrl.deleteSpells([for (final s in added) s.id]);
    expect(
      container.read(magicProvider).valueOrNull!.spellsFor('pg-1').single.name,
      'Keeper',
    );
  });
}
