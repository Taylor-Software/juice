import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('Creature round-trips through JSON; tolerant', () {
    const c = Creature(
      id: 'g',
      name: 'Goblin',
      statBlock: StatBlock(ac: 13, attacks: [Attack(name: 'Scimitar')]),
      maxHp: 7,
    );
    final back = Creature.maybeFromJson(c.toJson())!;
    expect(back.id, 'g');
    expect(back.name, 'Goblin');
    expect(back.statBlock.ac, 13);
    expect(back.maxHp, 7);
    // tolerant: non-map -> null; missing name -> null
    expect(Creature.maybeFromJson('nope'), isNull);
    expect(Creature.maybeFromJson({'id': 'x'}), isNull);
    // empty statBlock + zero hp omitted from JSON
    expect(const Creature(id: 'a', name: 'A').toJson().containsKey('statBlock'),
        false);
    expect(const Creature(id: 'a', name: 'A').toJson().containsKey('maxHp'),
        false);
  });

  test('BestiaryNotifier add + remove persists (app-global)', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(bestiaryProvider.notifier);
    expect(await c.read(bestiaryProvider.future), isEmpty);
    await n.add(const Creature(id: 'g', name: 'Goblin', maxHp: 7));
    await n.add(const Creature(id: 'o', name: 'Orc', maxHp: 15));
    expect((await c.read(bestiaryProvider.future)).map((x) => x.id),
        ['g', 'o']);
    await n.remove('g');
    expect((await c.read(bestiaryProvider.future)).single.id, 'o');

    // Persisted under the app-global key (re-read in a fresh container).
    final c2 = ProviderContainer();
    addTearDown(c2.dispose);
    expect((await c2.read(bestiaryProvider.future)).single.name, 'Orc');
  });
}
