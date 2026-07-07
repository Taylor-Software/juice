import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dungeon/footprint.dart';
import 'package:juice_oracle/engine/models.dart';

void main() {
  test('legacy single-cell room round-trips and defaults footprint to [(0,0)]',
      () {
    const r = DungeonRoom(id: 'a', x: 2, y: 3, title: 'Old');
    final j = r.toJson();
    // legacy JSON unchanged: no new keys at defaults
    expect(j.containsKey('fp'), isFalse);
    expect(j.containsKey('dr'), isFalse);
    expect(j.containsKey('rt'), isFalse);
    final back = DungeonRoom.maybeFromJson(j)!;
    expect(back.footprint, [(0, 0)]);
    expect(back.doors, isEmpty);
    expect(back.roomType, isNull);
  });

  test('footprint + doors + type round-trip', () {
    const r = DungeonRoom(
        id: 'b',
        x: 0,
        y: 0,
        title: 'New',
        footprint: [(0, 0), (0, 1)],
        doors: [DoorEdge((0, 1), Side.s, DoorKind.open)],
        roomType: 'chamber');
    final back = DungeonRoom.maybeFromJson(r.toJson())!;
    expect(back.footprint, [(0, 0), (0, 1)]);
    expect(back.doors.single.kind, DoorKind.open);
    expect(back.doors.single.side, Side.s);
    expect(back.roomType, 'chamber');
  });

  test('copyWith threads the new fields and preserves them by default', () {
    const r = DungeonRoom(
        id: 'c',
        x: 0,
        y: 0,
        title: 'T',
        footprint: [(0, 0), (1, 0)],
        doors: [DoorEdge((1, 0), Side.e, DoorKind.locked)],
        roomType: 'corridor');
    final t = r.copyWith(title: 'T2');
    expect(t.footprint, [(0, 0), (1, 0)]);
    expect(t.doors.single.kind, DoorKind.locked);
    expect(t.roomType, 'corridor');
  });
}
