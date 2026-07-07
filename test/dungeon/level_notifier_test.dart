import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/dungeon/generator.dart';
import 'package:juice_oracle/engine/dungeon/tables.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final tables = DungeonTables.fromJson(
      jsonDecode(File('assets/dungeon_data.json').readAsStringSync())
          as Map<String, dynamic>);

  Future<(ProviderContainer, MapNotifier)> setUpContainer() async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    await container.read(sessionsProvider.future);
    final notifier = container.read(mapProvider.notifier);
    await container.read(mapProvider.future);
    return (container, notifier);
  }

  test('enterClassicDungeon(cave) makes a cave level with stone + entrance',
      () async {
    final (container, notifier) = await setUpContainer();
    addTearDown(container.dispose);

    await notifier.enterClassicDungeon(
        branch: DungeonBranch.cave, tables: tables, dice: Dice(Random(1)));

    final s = container.read(mapProvider).requireValue;
    expect(s.levels, hasLength(1));
    final lvl = s.levels.single;
    expect(lvl.branch, 'cave');
    expect(lvl.depth, 1);
    expect(lvl.typeName, isNotEmpty);
    expect(lvl.stone, isNotEmpty);
    expect(lvl.rooms, hasLength(1));
    expect(lvl.rooms.single.roomType, isIn(['tunnel', 'cave']));
    expect(lvl.rooms.single.detail, contains('Entrance:'));
    expect(lvl.rooms.single.detail, contains('Stone:'));
  });

  test('enterClassicDungeon(dungeon) makes a dungeon level, no stone',
      () async {
    final (container, notifier) = await setUpContainer();
    addTearDown(container.dispose);

    await notifier.enterClassicDungeon(
        branch: DungeonBranch.dungeon, tables: tables, dice: Dice(Random(2)));

    final s = container.read(mapProvider).requireValue;
    expect(s.levels, hasLength(1));
    final lvl = s.levels.single;
    expect(lvl.branch, 'dungeon');
    expect(lvl.stone, isEmpty);
    expect(lvl.rooms, hasLength(1));
    expect(lvl.rooms.single.roomType, isIn(['corridor', 'chamber']));
    expect(lvl.rooms.single.detail, contains('Entrance:'));
  });

  test('descendFrom goes deeper on levelDelta -1 and back up on +1', () async {
    final (container, notifier) = await setUpContainer();
    addTearDown(container.dispose);

    await notifier.enterClassicDungeon(
        branch: DungeonBranch.dungeon, tables: tables, dice: Dice(Random(3)));

    // Inject a down-stairs room (zine "-1 lvl" = descend one level).
    var s = container.read(mapProvider).requireValue;
    await notifier.save(s.copyWith(rooms: [
      ...s.rooms,
      const DungeonRoom(id: 'stairs', x: 9, y: 9, title: 'S', levelDelta: -1),
    ]));

    await notifier.descendFrom('stairs', tables: tables, dice: Dice(Random(4)));
    s = container.read(mapProvider).requireValue;
    expect(s.levels, hasLength(2));
    expect(s.levels[s.activeLevel].depth, 2);
    expect(s.levelAt(2)!.rooms, hasLength(1)); // fresh entrance room

    // Inject an up-transition on depth 2; +1 returns to EXISTING depth 1.
    await notifier.save(s.copyWith(rooms: [
      ...s.rooms,
      const DungeonRoom(id: 'up', x: 12, y: 12, title: 'U', levelDelta: 1),
    ]));
    await notifier.descendFrom('up', tables: tables, dice: Dice(Random(5)));
    s = container.read(mapProvider).requireValue;
    expect(s.levels, hasLength(2), reason: 'no third level created');
    expect(s.levels[s.activeLevel].depth, 1);
  });

  test('descendFrom is a no-op for levelDelta 0', () async {
    final (container, notifier) = await setUpContainer();
    addTearDown(container.dispose);

    await notifier.enterClassicDungeon(
        branch: DungeonBranch.dungeon, tables: tables, dice: Dice(Random(6)));
    var s = container.read(mapProvider).requireValue;
    final entrance = s.rooms.single;
    await notifier.descendFrom(entrance.id,
        tables: tables, dice: Dice(Random(7)));
    s = container.read(mapProvider).requireValue;
    expect(s.levels, hasLength(1));
  });

  test('switchLevel flips activeLevel without changing rooms; unknown no-op',
      () async {
    final (container, notifier) = await setUpContainer();
    addTearDown(container.dispose);

    await notifier.enterClassicDungeon(
        branch: DungeonBranch.dungeon, tables: tables, dice: Dice(Random(8)));
    var s = container.read(mapProvider).requireValue;
    await notifier.save(s.copyWith(rooms: [
      ...s.rooms,
      const DungeonRoom(id: 'stairs', x: 9, y: 9, title: 'S', levelDelta: -1),
    ]));
    await notifier.descendFrom('stairs', tables: tables, dice: Dice(Random(9)));

    s = container.read(mapProvider).requireValue;
    final countD1 = s.levelAt(1)!.rooms.length;
    final countD2 = s.levelAt(2)!.rooms.length;

    await notifier.switchLevel(1);
    s = container.read(mapProvider).requireValue;
    expect(s.levels[s.activeLevel].depth, 1);

    await notifier.switchLevel(2);
    s = container.read(mapProvider).requireValue;
    expect(s.levels[s.activeLevel].depth, 2);

    await notifier.switchLevel(99); // no such level -> no-op
    s = container.read(mapProvider).requireValue;
    expect(s.levels[s.activeLevel].depth, 2);
    expect(s.levelAt(1)!.rooms.length, countD1);
    expect(s.levelAt(2)!.rooms.length, countD2);
  });

  test('crossover: exploring from a crossTo room generates the OTHER branch',
      () async {
    final (container, notifier) = await setUpContainer();
    addTearDown(container.dispose);

    await notifier.enterClassicDungeon(
        branch: DungeonBranch.dungeon, tables: tables, dice: Dice(Random(10)));
    var s = container.read(mapProvider).requireValue;
    final entrance = s.rooms.single;
    // Mark the (real, placed) entrance as a cave crossover.
    await notifier.save(s.copyWith(rooms: [
      for (final r in s.rooms)
        if (r.id == entrance.id) r.copyWith(crossTo: 'cave') else r,
    ]));

    s = container.read(mapProvider).requireValue;
    final r0 = s.rooms.single;
    final d0 = r0.doors.first;
    final ok = await notifier.addClassicRoom(
      fromRoomId: r0.id,
      doorEdge: (
        cell: (r0.x + d0.cell.$1, r0.y + d0.cell.$2),
        side: d0.side,
      ),
      tables: tables,
      dice: Dice(Random(11)),
    );
    expect(ok, isTrue);
    s = container.read(mapProvider).requireValue;
    expect(s.rooms, hasLength(2));
    expect(s.rooms.last.roomType, isIn(['tunnel', 'cave']));
  });

  test('resetDungeon clears all levels', () async {
    final (container, notifier) = await setUpContainer();
    addTearDown(container.dispose);

    await notifier.enterClassicDungeon(
        branch: DungeonBranch.dungeon, tables: tables, dice: Dice(Random(12)));
    expect(container.read(mapProvider).requireValue.levels, isNotEmpty);

    await notifier.resetDungeon();
    final s = container.read(mapProvider).requireValue;
    expect(s.levels, isEmpty);
    expect(s.activeLevel, 0);
  });
}
