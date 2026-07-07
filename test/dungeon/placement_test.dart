import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/dungeon/footprint.dart';
import 'package:juice_oracle/engine/dungeon/placement.dart';

void main() {
  test('places a straight corridor south of an existing cell, no overlap', () {
    final occupied = {(0, 0)};
    final p = placeRoom(occupied, (cell: (0, 0), side: Side.s),
        kCorridorShapes['straight']!, Dice(Random(1)));
    expect(p, isNotNull);
    expect(p!.cells.toSet().intersection(occupied), isEmpty);
    expect(p.entryDoor.side, Side.n);
    expect(p.entryDoor.cell, (0, 1));
  });

  test('mates an east-facing exit: new room sits to the right, entry on west',
      () {
    final occupied = {(0, 0)};
    final p = placeRoom(occupied, (cell: (0, 0), side: Side.e),
        kCorridorShapes['straight']!, Dice(Random(1)));
    expect(p, isNotNull);
    expect(p!.cells.toSet().intersection(occupied), isEmpty);
    expect(p.entryDoor.side, Side.w);
    expect(p.entryDoor.cell, (1, 0)); // directly east of (0,0)
  });

  test('all placed cells are unique (no self-overlap in the footprint)', () {
    final p = placeRoom({(0, 0)}, (cell: (0, 0), side: Side.s),
        kCorridorShapes['l-bend']!, Dice(Random(2)));
    expect(p, isNotNull);
    expect(p!.cells.toSet().length, p.cells.length);
  });

  test('returns null when fully boxed in', () {
    final occupied = {(0, 0), (0, 1), (0, 2), (1, 1), (-1, 1)};
    final p = placeRoom(occupied, (cell: (0, 1), side: Side.s),
        kCorridorShapes['long']!, Dice(Random(1)));
    expect(p, isNull);
  });
}
