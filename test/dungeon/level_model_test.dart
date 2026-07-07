import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';

void main() {
  test('P1-shape JSON (bare rooms) loads as one depth-1 dungeon level', () {
    final s = MapState.fromJson({
      'rooms': [
        {'id': 'a', 'x': 0, 'y': 0, 'title': 'T'}
      ],
      'corridors': <dynamic>[],
      'currentRoomId': 'a',
    });
    expect(s.levels, hasLength(1));
    expect(s.levels.first.depth, 1);
    expect(s.rooms.single.id, 'a');
    expect(s.currentRoomId, 'a');
  });

  test('levels round-trip with meta and active index', () {
    const lvl1 = DungeonLevel(
        depth: 1,
        typeName: 'Ruins',
        rooms: [DungeonRoom(id: 'a', x: 0, y: 0, title: 'T')],
        currentRoomId: 'a');
    const lvl2 = DungeonLevel(
        depth: 2,
        branch: 'cave',
        typeName: 'Grotto',
        note: 'n',
        stone: 'Basalt');
    const s = MapState(
        dungeons: [DungeonSite(id: 'd1', levels: [lvl1, lvl2], activeLevel: 1)],
        activeDungeonId: 'd1');
    final back = MapState.fromJson(s.toJson());
    expect(back.levels[1].stone, 'Basalt');
    expect(back.activeLevel, 1);
    expect(back.rooms, isEmpty); // views follow the ACTIVE level (index 1)
    expect(back.levelAt(2)!.typeName, 'Grotto');
  });

  test('copyWith room edits apply to the active level and seed level 1', () {
    const s = MapState(); // no levels
    final s2 =
        s.copyWith(rooms: const [DungeonRoom(id: 'a', x: 0, y: 0, title: 'T')]);
    expect(s2.levels, hasLength(1));
    expect(s2.rooms.single.id, 'a');
    final s3 = const MapState(dungeons: [
      DungeonSite(
          id: 'd1',
          levels: [DungeonLevel(depth: 1), DungeonLevel(depth: 2)],
          activeLevel: 1),
    ], activeDungeonId: 'd1')
        .copyWith(
            currentRoomId: 'x',
            rooms: const [DungeonRoom(id: 'x', x: 0, y: 0, title: 'X')]);
    expect(s3.levels[0].rooms, isEmpty); // level 1 untouched
    expect(s3.levels[1].rooms.single.id, 'x');
    expect(s3.currentRoomId, 'x');
  });

  test('DungeonRoom levelDelta + crossTo round-trip and default off', () {
    const r = DungeonRoom(id: 'a', x: 0, y: 0, title: 'T');
    expect(DungeonRoom.fromJson(r.toJson()).levelDelta, 0);
    expect(r.toJson().containsKey('ld'), isFalse);
    const d = DungeonRoom(
        id: 'b', x: 0, y: 0, title: 'S', levelDelta: -1, crossTo: 'cave');
    final back = DungeonRoom.fromJson(d.toJson());
    expect(back.levelDelta, -1);
    expect(back.crossTo, 'cave');
  });
}
