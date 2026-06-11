/// Pure placement geometry for the Maps tool: dungeon rooms on an integer
/// grid and wilderness hexes in odd-q offset coordinates. No state, no I/O;
/// deterministic under a seeded [Dice].
library;

import 'dice.dart';
import 'models.dart';

/// Dungeon 4-neighbor offsets in the binding order N, E, S, W
/// (y grows downward, matching screen coordinates).
const _roomDirs = [(0, -1), (1, 0), (0, 1), (-1, 0)];

/// Grid position for the next room: a free 4-neighbor cell of the current
/// room, picked by [dice]; if the current room is boxed in, walk along
/// connected rooms (BFS, neighbors enqueued in insertion order, so only the
/// final cell pick consumes dice) until one has a free neighbor. Returns the
/// chosen position AND the room it attaches to. First room (empty list) goes
/// to (0,0) attached to nothing.
///
/// The walk uses grid 4-adjacency — a SUPERGRAPH of corridor connectivity
/// (branches that double back can touch without a corridor), so the chosen
/// attach room may differ from a corridor-only walk. Chosen because this
/// function carries no corridor data; every output invariant still holds:
/// no overlap, deterministic under seeded dice, and the resulting map stays
/// connected because callers add corridor `[attachTo, newId]` per new room.
({int x, int y, String? attachTo}) nextRoomPosition(
    List<DungeonRoom> rooms, String? currentId, Dice dice) {
  if (rooms.isEmpty) return (x: 0, y: 0, attachTo: null);
  final occupied = {for (final r in rooms) (r.x, r.y)};
  final start = rooms.firstWhere(
    (r) => r.id == currentId,
    orElse: () => rooms.first,
  );
  final visited = {start.id};
  final queue = [start];
  while (queue.isNotEmpty) {
    final room = queue.removeAt(0);
    final free = [
      for (final d in _roomDirs)
        if (!occupied.contains((room.x + d.$1, room.y + d.$2)))
          (x: room.x + d.$1, y: room.y + d.$2),
    ];
    if (free.isNotEmpty) {
      final pick = free[dice.dN(free.length) - 1];
      return (x: pick.x, y: pick.y, attachTo: room.id);
    }
    for (final r in rooms) {
      if (visited.contains(r.id)) continue;
      final adjacent =
          _roomDirs.any((d) => r.x == room.x + d.$1 && r.y == room.y + d.$2);
      if (adjacent) {
        visited.add(r.id);
        queue.add(r);
      }
    }
  }
  // Unreachable: rooms occupying a visited room's neighbor cells are
  // themselves visited, so the visited set is closed under adjacency and
  // its boundary (e.g. the max-x room's east cell) is always free.
  throw StateError('nextRoomPosition: no free cell found');
}

/// Odd-q offset hex neighbors (flat-top, odd columns shifted half a hex
/// DOWN), as 6 (col,row) pairs in fixed clockwise-from-north order.
///
/// Derived from flat-top axial neighbors via q = col,
/// r = row - (col - (col & 1)) ~/ 2; verified symmetric in tests.
List<({int col, int row})> hexNeighbors(int col, int row) => col.isOdd
    ? [
        (col: col, row: row - 1),
        (col: col + 1, row: row),
        (col: col + 1, row: row + 1),
        (col: col, row: row + 1),
        (col: col - 1, row: row + 1),
        (col: col - 1, row: row),
      ]
    : [
        (col: col, row: row - 1),
        (col: col + 1, row: row - 1),
        (col: col + 1, row: row),
        (col: col, row: row + 1),
        (col: col - 1, row: row),
        (col: col - 1, row: row - 1),
      ];

/// Position for the next revealed hex: a dice-picked neighbor of the
/// current hex that is not yet revealed; if all 6 are revealed, the
/// dice-picked neighbor anyway (travel re-enters a known hex — returns
/// that existing cell's coords, flagged [alreadyRevealed]). Empty field
/// -> (0,0). A missing current falls back to the first revealed hex.
({int col, int row, bool alreadyRevealed}) nextHexPosition(
    List<HexCell> hexes, int? curCol, int? curRow, Dice dice) {
  if (hexes.isEmpty) return (col: 0, row: 0, alreadyRevealed: false);
  final (col, row) = curCol != null && curRow != null
      ? (curCol, curRow)
      : (hexes.first.col, hexes.first.row);
  final revealed = {for (final h in hexes) (h.col, h.row)};
  final neighbors = hexNeighbors(col, row);
  final unrevealed =
      neighbors.where((n) => !revealed.contains((n.col, n.row))).toList();
  if (unrevealed.isNotEmpty) {
    final pick = unrevealed[dice.dN(unrevealed.length) - 1];
    return (col: pick.col, row: pick.row, alreadyRevealed: false);
  }
  final pick = neighbors[dice.dN(6) - 1];
  return (col: pick.col, row: pick.row, alreadyRevealed: true);
}
