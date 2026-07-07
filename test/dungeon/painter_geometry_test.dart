import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dungeon/footprint.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/features/map_screen.dart';

void main() {
  test('multi-cell footprint hit-tests each of its cells', () {
    final rooms = [
      const DungeonRoom(
          id: 'a',
          x: 0,
          y: 0,
          title: 'A',
          footprint: [(0, 0), (0, 1)],
          doors: [DoorEdge((0, 1), Side.s, DoorKind.open)]),
    ];
    // a point inside the second cell (0,1) still resolves to room 'a'
    final center = cellCenterFor(rooms.first, (0, 1), 0, 0, 56.0);
    expect(roomIdAt(rooms, center, 56.0), 'a');
    // and the first cell still hits too
    final center0 = cellCenterFor(rooms.first, (0, 0), 0, 0, 56.0);
    expect(roomIdAt(rooms, center0, 56.0), 'a');
  });

  test('legacy single-cell room hit-test unchanged', () {
    final rooms = [
      const DungeonRoom(id: 'a', x: 2, y: 3, title: 'A'),
    ];
    final center = cellCenterFor(rooms.first, (0, 0), 2, 3, 56.0);
    expect(roomIdAt(rooms, center, 56.0), 'a');
  });

  test('door hit-test finds the open door edge under a point', () {
    final rooms = [
      const DungeonRoom(
          id: 'a',
          x: 0,
          y: 0,
          title: 'A',
          footprint: [(0, 0)],
          doors: [DoorEdge((0, 0), Side.s, DoorKind.open)]),
    ];
    final p =
        doorMarkerCenter(rooms.first, rooms.first.doors.single, 0, 0, 56.0);
    final hit = doorEdgeAt(rooms, p, 56.0);
    expect(hit, isNotNull);
    expect(hit!.roomId, 'a');
    expect(hit.door.side, Side.s);
  });

  test('locked doors are not returned by the open-door hit-test', () {
    final rooms = [
      const DungeonRoom(
          id: 'a',
          x: 0,
          y: 0,
          title: 'A',
          footprint: [(0, 0)],
          doors: [DoorEdge((0, 0), Side.s, DoorKind.locked)]),
    ];
    final p =
        doorMarkerCenter(rooms.first, rooms.first.doors.single, 0, 0, 56.0);
    expect(doorEdgeAt(rooms, p, 56.0), isNull);
  });

  test('far-away point hits no door', () {
    final rooms = [
      const DungeonRoom(
          id: 'a',
          x: 0,
          y: 0,
          title: 'A',
          footprint: [(0, 0)],
          doors: [DoorEdge((0, 0), Side.s, DoorKind.open)]),
    ];
    expect(doorEdgeAt(rooms, const Offset(500, 500), 56.0), isNull);
  });
}
