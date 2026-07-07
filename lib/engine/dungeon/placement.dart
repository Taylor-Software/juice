/// Pure placement: rotate + translate a footprint so one of its openings mates
/// the explored door edge, without overlapping occupied cells. Deterministic
/// under a seeded [Dice].
library;

import '../dice.dart';
import 'footprint.dart';

class Placement {
  const Placement(
      {required this.cells, required this.entryDoor, required this.openDoors});
  final List<(int, int)> cells; // absolute grid cells
  final DoorEdge entryDoor; // the edge back to the room we came from
  final List<DoorEdge> openDoors; // remaining openings, kind == open
}

/// The neighbor cell across [side] from [cell].
(int, int) _across((int, int) cell, Side side) => switch (side) {
      Side.n => (cell.$1, cell.$2 - 1),
      Side.s => (cell.$1, cell.$2 + 1),
      Side.e => (cell.$1 + 1, cell.$2),
      Side.w => (cell.$1 - 1, cell.$2),
    };

/// [fromDoor] is the explored opening on the SOURCE room (its world cell+side).
/// The new room must present an opening on the OPPOSITE side, and the cell
/// carrying that opening sits in `_across(fromDoor.cell, fromDoor.side)`.
Placement? placeRoom(
  Set<(int, int)> occupied,
  ({(int, int) cell, Side side}) fromDoor,
  List<RoomFootprint> candidates,
  Dice dice,
) {
  final target = _across(fromDoor.cell, fromDoor.side);
  final wantSide = oppositeSide(fromDoor.side);
  final cand = [...candidates];
  for (var i = cand.length - 1; i > 0; i--) {
    final j = dice.dN(i + 1) - 1;
    final t = cand[i];
    cand[i] = cand[j];
    cand[j] = t;
  }
  for (final base in cand) {
    for (var q = 0; q < 4; q++) {
      final f = base.rotate(q);
      for (final o in f.openings.where((o) => o.side == wantSide)) {
        final dx = target.$1 - o.cell.$1, dy = target.$2 - o.cell.$2;
        final placed = [for (final c in f.cells) (c.$1 + dx, c.$2 + dy)];
        if (placed.toSet().intersection(occupied).isNotEmpty) continue;
        final entry = DoorEdge(target, wantSide, DoorKind.open);
        final others = <DoorEdge>[];
        for (final op in f.openings) {
          final oc = (op.cell.$1 + dx, op.cell.$2 + dy);
          if (oc == target && op.side == wantSide) continue;
          others.add(DoorEdge(oc, op.side, DoorKind.open));
        }
        return Placement(cells: placed, entryDoor: entry, openDoors: others);
      }
    }
  }
  return null;
}
