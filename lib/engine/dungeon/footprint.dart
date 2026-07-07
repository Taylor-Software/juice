/// Pure grid geometry for classic-dungeon rooms. A footprint is a set of cell
/// offsets plus authored OPENINGS (which sides can connect). Door KIND is not
/// stored here — the generator assigns it from the type die (see spec).
library;

enum Side { n, e, s, w }

Side _rotSide(Side s) => switch (s) {
      // one clockwise quarter-turn
      Side.n => Side.e,
      Side.e => Side.s,
      Side.s => Side.w,
      Side.w => Side.n,
    };

Side oppositeSide(Side s) => switch (s) {
      Side.n => Side.s,
      Side.s => Side.n,
      Side.e => Side.w,
      Side.w => Side.e,
    };

class Opening {
  const Opening(this.cell, this.side);
  final (int, int) cell;
  final Side side;
}

enum DoorKind { locked, door, open }

class DoorEdge {
  const DoorEdge(this.cell, this.side, this.kind);
  final (int, int) cell;
  final Side side;
  final DoorKind kind;
  Map<String, dynamic> toJson() =>
      {'x': cell.$1, 'y': cell.$2, 's': side.index, 'k': kind.index};
  factory DoorEdge.fromJson(Map<String, dynamic> j) => DoorEdge(
      (j['x'] as int, j['y'] as int),
      Side.values[j['s'] as int],
      DoorKind.values[j['k'] as int]);
}

class RoomFootprint {
  const RoomFootprint(
      {required this.family, required this.cells, required this.openings});
  final String family;
  final List<(int, int)> cells;
  final List<Opening> openings;

  /// Clockwise quarter-turn: (x,y) -> (-y, x); sides rotate with it.
  RoomFootprint rotate(int quarterTurns) {
    var f = this;
    for (var i = 0; i < (quarterTurns % 4); i++) {
      f = RoomFootprint(
        family: f.family,
        cells: [for (final c in f.cells) (-c.$2, c.$1)],
        openings: [
          for (final o in f.openings)
            Opening((-o.cell.$2, o.cell.$1), _rotSide(o.side))
        ],
      );
    }
    return f;
  }

  /// Cells shifted so min x/y == 0 (rotation can push them negative).
  List<(int, int)> get normalizedCells {
    final minX = cells.map((c) => c.$1).reduce((a, b) => a < b ? a : b);
    final minY = cells.map((c) => c.$2).reduce((a, b) => a < b ? a : b);
    return [for (final c in cells) (c.$1 - minX, c.$2 - minY)];
  }
}

/// Authored corridor catalog. Family ids MUST match corridor_families in the
/// JSON range map. Openings are on the sides the zine shape shows arrows.
const kCorridorShapes = <String, List<RoomFootprint>>{
  'straight': [
    RoomFootprint(
        family: 'straight',
        cells: [(0, 0), (0, 1)],
        openings: [Opening((0, 0), Side.n), Opening((0, 1), Side.s)]),
  ],
  'l-bend': [
    RoomFootprint(
        family: 'l-bend',
        cells: [(0, 0), (0, 1), (1, 1)],
        openings: [Opening((0, 0), Side.n), Opening((1, 1), Side.e)]),
  ],
  't-junction': [
    RoomFootprint(family: 't-junction', cells: [
      (0, 0),
      (1, 0),
      (2, 0),
      (1, 1)
    ], openings: [
      Opening((0, 0), Side.w),
      Opening((2, 0), Side.e),
      Opening((1, 1), Side.s)
    ]),
  ],
  'cross': [
    RoomFootprint(family: 'cross', cells: [
      (1, 0),
      (0, 1),
      (1, 1),
      (2, 1),
      (1, 2)
    ], openings: [
      Opening((1, 0), Side.n),
      Opening((0, 1), Side.w),
      Opening((2, 1), Side.e),
      Opening((1, 2), Side.s)
    ]),
  ],
  'offset': [
    RoomFootprint(
        family: 'offset',
        cells: [(0, 0), (0, 1), (1, 1), (1, 2)],
        openings: [Opening((0, 0), Side.n), Opening((1, 2), Side.s)]),
  ],
  'long': [
    RoomFootprint(
        family: 'long',
        cells: [(0, 0), (0, 1), (0, 2), (0, 3)],
        openings: [Opening((0, 0), Side.n), Opening((0, 3), Side.s)]),
  ],
};

/// Authored chamber catalog. Family ids MUST match chamber_families in the JSON.
const kChamberShapes = <String, List<RoomFootprint>>{
  'small': [
    RoomFootprint(family: 'small', cells: [
      (0, 0),
      (1, 0),
      (0, 1),
      (1, 1)
    ], openings: [
      Opening((0, 0), Side.w),
      Opening((1, 0), Side.n),
      Opening((1, 1), Side.e)
    ]),
  ],
  'medium': [
    RoomFootprint(family: 'medium', cells: [
      (0, 0),
      (1, 0),
      (2, 0),
      (0, 1),
      (1, 1),
      (2, 1)
    ], openings: [
      Opening((0, 0), Side.w),
      Opening((2, 0), Side.e),
      Opening((1, 1), Side.s)
    ]),
  ],
  'large': [
    RoomFootprint(family: 'large', cells: [
      (0, 0),
      (1, 0),
      (2, 0),
      (0, 1),
      (1, 1),
      (2, 1),
      (0, 2),
      (1, 2),
      (2, 2)
    ], openings: [
      Opening((1, 0), Side.n),
      Opening((0, 1), Side.w),
      Opening((2, 1), Side.e),
      Opening((1, 2), Side.s)
    ]),
  ],
  'round': [
    RoomFootprint(family: 'round', cells: [
      (1, 0),
      (0, 1),
      (1, 1),
      (2, 1),
      (1, 2)
    ], openings: [
      Opening((1, 0), Side.n),
      Opening((1, 2), Side.s),
      Opening((0, 1), Side.w)
    ]),
  ],
  'cross': [
    RoomFootprint(family: 'cross', cells: [
      (1, 0),
      (0, 1),
      (1, 1),
      (2, 1),
      (1, 2)
    ], openings: [
      Opening((1, 0), Side.n),
      Opening((0, 1), Side.w),
      Opening((2, 1), Side.e),
      Opening((1, 2), Side.s)
    ]),
  ],
  'l-room': [
    RoomFootprint(
        family: 'l-room',
        cells: [(0, 0), (1, 0), (0, 1), (0, 2), (1, 2)],
        openings: [Opening((1, 0), Side.e), Opening((1, 2), Side.e)]),
  ],
};

/// Maps a D66 roll (11..66) to a family id via the JSON range map, then returns
/// the candidate footprints for that family. [rangeMap] is corridorFamilies or
/// chamberFamilies from DungeonTables; [catalog] the matching kCorridor/Chamber.
List<RoomFootprint> shapesForRoll(
    int d66,
    Map<String, List<List<int>>> rangeMap,
    Map<String, List<RoomFootprint>> catalog) {
  for (final e in rangeMap.entries) {
    for (final r in e.value) {
      if (d66 >= r[0] && d66 <= r[1]) return catalog[e.key] ?? const [];
    }
  }
  return catalog.values.first; // defensive: covered map never reaches here
}
