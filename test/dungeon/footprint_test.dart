import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dungeon/footprint.dart';

void main() {
  test('rotate 4 quarter-turns is identity', () {
    const f = RoomFootprint(
        family: 'l-bend',
        cells: [(0, 0), (0, 1), (1, 1)],
        openings: [Opening((0, 0), Side.n), Opening((1, 1), Side.e)]);
    var r = f;
    for (var i = 0; i < 4; i++) {
      r = r.rotate(1);
    }
    expect(r.normalizedCells.toSet(), f.normalizedCells.toSet());
    expect(r.openings.map((o) => o.side).toSet(),
        f.openings.map((o) => o.side).toSet());
  });

  test('rotate 1 turns North opening to East', () {
    const f = RoomFootprint(
        family: 'straight',
        cells: [(0, 0)],
        openings: [Opening((0, 0), Side.n)]);
    expect(f.rotate(1).openings.single.side, Side.e);
  });

  test('every catalog family has >=1 footprint', () {
    for (final fam in kCorridorShapes.keys) {
      expect(kCorridorShapes[fam], isNotEmpty, reason: fam);
    }
    for (final fam in kChamberShapes.keys) {
      expect(kChamberShapes[fam], isNotEmpty, reason: fam);
    }
  });

  test('DoorEdge round-trips through JSON', () {
    const d = DoorEdge((2, -1), Side.w, DoorKind.locked);
    final back = DoorEdge.fromJson(d.toJson());
    expect(back.cell, (2, -1));
    expect(back.side, Side.w);
    expect(back.kind, DoorKind.locked);
  });

  test('shapesForRoll maps d66 range boundaries to the right family', () {
    const ranges = {
      'straight': [
        [11, 22]
      ],
      'l-bend': [
        [23, 34]
      ],
    };
    expect(shapesForRoll(22, ranges, kCorridorShapes).first.family, 'straight');
    expect(shapesForRoll(23, ranges, kCorridorShapes).first.family, 'l-bend');
    expect(shapesForRoll(34, ranges, kCorridorShapes).first.family, 'l-bend');
  });

  test('catalog family ids match the JSON range-map families', () {
    // corridor_families / chamber_families keys in dungeon_data.json:
    const corridor = {
      'straight',
      'l-bend',
      't-junction',
      'cross',
      'offset',
      'long'
    };
    const chamber = {'small', 'medium', 'large', 'round', 'cross', 'l-room'};
    expect(kCorridorShapes.keys.toSet(), corridor);
    expect(kChamberShapes.keys.toSet(), chamber);
  });
}
