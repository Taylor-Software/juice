import 'package:flutter_test/flutter_test.dart';
import 'package:loreseer/state/magic_controller.dart';
import 'package:polarity_grammar/polarity_grammar.dart' as pg;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('JuiceMagicStore round-trips a Library through SharedPreferences',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = JuiceMagicStore(prefs, 'campaign-1');
    const lib = pg.Library(
      characters: [
        pg.Character(id: 'pg-1', name: 'Ash', baseMana: 4, currentMana: 4),
      ],
      spells: [],
    );
    await store.save(lib);
    final loaded = await store.load();
    expect(loaded.characters.single.id, 'pg-1');
    expect(prefs.getString('loreseer.magic.v1.campaign-1'), isNotNull);
  });

  test('JuiceMagicStore quarantines corrupt data and returns an empty library',
      () async {
    SharedPreferences.setMockInitialValues({
      'loreseer.magic.v1.campaign-1': 'not json',
    });
    final prefs = await SharedPreferences.getInstance();
    final store = JuiceMagicStore(prefs, 'campaign-1');
    final loaded = await store.load();
    expect(loaded.characters, isEmpty);
    expect(
      prefs.getString('loreseer.magic.v1.campaign-1.quarantine.0'),
      'not json',
    );
  });

  test('JuiceMagicStore is scoped per session — two sessions do not collide',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storeA = JuiceMagicStore(prefs, 'a');
    final storeB = JuiceMagicStore(prefs, 'b');
    await storeA.save(const pg.Library(
      characters: [
        pg.Character(id: 'x', name: 'X', baseMana: 4, currentMana: 4)
      ],
      spells: [],
    ));
    final loadedB = await storeB.load();
    expect(loadedB.characters, isEmpty);
  });
}
