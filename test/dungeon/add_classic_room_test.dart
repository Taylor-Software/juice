import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/dungeon/footprint.dart';
import 'package:juice_oracle/engine/dungeon/tables.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

DungeonTables _tables() => DungeonTables.fromJson(jsonDecode('''
{"A1":${jsonEncode(List.filled(12, 'Somewhere'))},
 "A2":{"2":{"name":"V"},"3":{"name":"X"},"4":{"name":"X"},"5":{"name":"X"},
 "6":{"name":"X"},"7":{"name":"Ruins"},"8":{"name":"X"},"9":{"name":"X"},
 "10":{"name":"X"},"11":{"name":"X"},"12":{"name":"X"}},
 "B2":["Nothing","Nothing","Nothing","Nothing","Nothing","Nothing"],
 "B5":["W","W","W","W","W","W","W","W","W","W"],
 "C2":["Feature {ref:C3} + Monster","Nothing","Nothing","Nothing","Nothing","Nothing"],
 "G1":{"2":"a","3":"a","4":"a","5":"a","6":"a","7":"a","8":"a","9":"a","10":"a","11":"a","12":"a"},
 "G2":[{"text":"Goblins","count":"1","organized":true}],
 "faction_names":["Rotfangs"],
 "corridor_families":{"straight":[[11,66]]},
 "chamber_families":{"small":[[11,66]]},
 "label_fallbacks":{},
 "C3":["A fresco"]}
''') as Map<String, dynamic>);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('addClassicRoom places entrance then a mated room + corridor', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(sessionsProvider.future);

    final t = _tables();
    const effect = A2Type(name: 'Ruins');
    final notifier = container.read(mapProvider.notifier);
    await container.read(mapProvider.future);

    // entrance (no fromDoor)
    final ok1 = await notifier.addClassicRoom(
        fromRoomId: null,
        doorEdge: null,
        tables: t,
        effect: effect,
        dice: Dice(Random(1)));
    expect(ok1, isTrue);
    var map = container.read(mapProvider).requireValue;
    expect(map.rooms, hasLength(1));
    expect(map.rooms.single.doors, isNotEmpty);
    expect(
        map.rooms.single.doors.every((d) => d.kind == DoorKind.open), isTrue);
    expect(map.rooms.single.roomType, isNotNull);

    // explore the first open door
    final r0 = map.rooms.single;
    final d0 = r0.doors.first;
    final world = (cell: (r0.x + d0.cell.$1, r0.y + d0.cell.$2), side: d0.side);
    final ok2 = await notifier.addClassicRoom(
        fromRoomId: r0.id,
        doorEdge: world,
        tables: t,
        effect: effect,
        dice: Dice(Random(2)));
    expect(ok2, isTrue);
    map = container.read(mapProvider).requireValue;
    expect(map.rooms, hasLength(2));
    expect(map.corridors.any((c) => c.contains(r0.id)), isTrue);
    expect(map.currentRoomId, isNot(r0.id));
    final r1 = map.rooms.last;
    expect(r1.footprint, isNotEmpty);
    expect(r1.doors, isNotEmpty);
    // the two rooms don't overlap on the world grid
    final cells0 = {for (final c in r0.footprint) (r0.x + c.$1, r0.y + c.$2)};
    final cells1 = {for (final c in r1.footprint) (r1.x + c.$1, r1.y + c.$2)};
    expect(cells0.intersection(cells1), isEmpty);
  });

  test('faction persists via dungeonFactionsProvider with a real room id',
      () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(sessionsProvider.future);

    final t = _tables();
    const effect = A2Type(name: 'Ruins');
    final notifier = container.read(mapProvider.notifier);
    await container.read(mapProvider.future);
    await container.read(dungeonFactionsProvider.future);

    // Generate entrances until a chamber stocking rolls the organized
    // Goblins (C2 row 1; type die 4-6 = chamber). Bounded seed loop.
    var found = false;
    for (var s = 0; s < 60 && !found; s++) {
      await notifier.addClassicRoom(
          fromRoomId: null,
          doorEdge: null,
          tables: t,
          effect: effect,
          dice: Dice(Random(s)));
      final reg = container.read(dungeonFactionsProvider).requireValue;
      if (reg.factions.isNotEmpty) {
        found = true;
        expect(reg.factions.first.name, 'Rotfangs');
        // the faction's roomIds reference a REAL room id on the map
        final map = container.read(mapProvider).requireValue;
        final ids = map.rooms.map((r) => r.id).toSet();
        expect(ids.containsAll(reg.factions.first.roomIds), isTrue);
      } else {
        await notifier.resetDungeon();
      }
    }
    expect(found, isTrue, reason: 'no seed produced an organized monster');
  });

  test('dungeon_factions key is session-scoped (registered for export)', () {
    expect(sessionScopedKeys, contains('juice.dungeon_factions.v1'));
  });
}
