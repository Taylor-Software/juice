import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice_oracle/engine/lonelog_wargaming.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/state/providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Unit round-trips; empty fields omitted', () {
    const u = Unit(id: '1', name: 'Goblins', size: '×5', status: 'Steady');
    final back = Unit.fromJson(u.toJson());
    expect(back.name, 'Goblins');
    expect(back.size, '×5');
    expect(back.status, 'Steady');
    final bare = const Unit(id: '2', name: 'Rats').toJson();
    expect(bare.containsKey('size'), isFalse);
    expect(bare.containsKey('status'), isFalse);
  });

  test('battleToLonelog renders a [BATTLE] block of [Unit:] tags', () {
    const units = [
      Unit(id: '1', name: 'Goblins', size: '×5', status: 'Steady'),
      Unit(id: '2', name: 'Ogre', status: 'Engaged'),
      Unit(id: '3', name: 'Scouts'),
    ];
    final out = battleToLonelog(units);
    expect(out, startsWith('[BATTLE]'));
    expect(out, contains('[Unit:Goblins|×5|Steady]'));
    expect(out, contains('[Unit:Ogre|Engaged]'));
    expect(out, contains('[Unit:Scouts]'));
    expect(out, endsWith('[/BATTLE]'));
  });

  test('battleToLonelog sanitizes delimiter chars', () {
    const units = [Unit(id: '1', name: 'A|B]C', size: 'x|2')];
    expect(battleToLonelog(units), contains('[Unit:A/B)C|x/2]'));
  });

  test('kUnitStatuses is the addon palette', () {
    expect(kUnitStatuses, contains('Routed'));
    expect(kUnitStatuses.toSet().length, kUnitStatuses.length);
  });

  test('UnitNotifier add/update/remove persist', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(sessionsProvider.future);
    final n = c.read(unitsProvider.notifier);
    await c.read(unitsProvider.future);

    await n.add('Goblins', size: '×5');
    final u = (await c.read(unitsProvider.future)).single;
    expect(u.size, '×5');

    await n.updateUnit(u.copyWith(status: 'Broken'));
    expect((await c.read(unitsProvider.future)).single.status, 'Broken');

    await n.remove(u.id);
    expect(await c.read(unitsProvider.future), isEmpty);
  });
}
