/// Deterministic wobbly perimeter for cave rooms: walks the outer boundary of
/// a fused cell footprint, subdivides each edge, and jitters interior points
/// with a seeded PRNG so repaints are stable. Pure.
library;

import 'dart:math';

/// Ordered closed loop (first == last) of jittered points around [cells]
/// (unit-cell offsets), scaled by [cellSize]. Corner points keep at most
/// [jitter]/2 displacement; edge midpoints up to [jitter].
List<(double, double)> organicPerimeter(List<(int, int)> cells,
    {required int seed, required double cellSize, required double jitter}) {
  final cellSet = cells.toSet();
  // Boundary edges as directed segments (each cell side with no neighbor),
  // wound clockwise so chaining yields one outer loop.
  final segs = <((int, int), (int, int))>[];
  for (final c in cellSet) {
    final (x, y) = c;
    if (!cellSet.contains((x, y - 1))) segs.add(((x, y), (x + 1, y)));
    if (!cellSet.contains((x + 1, y))) segs.add(((x + 1, y), (x + 1, y + 1)));
    if (!cellSet.contains((x, y + 1))) segs.add(((x + 1, y + 1), (x, y + 1)));
    if (!cellSet.contains((x - 1, y))) segs.add(((x, y + 1), (x, y)));
  }
  final byStart = {for (final s in segs) s.$1: s};
  final loop = <(int, int)>[];
  var cur = segs.first;
  do {
    loop.add(cur.$1);
    cur = byStart[cur.$2]!;
  } while (cur.$1 != segs.first.$1);
  loop.add(loop.first);

  final rng = Random(seed);
  double j(double range) => (rng.nextDouble() * 2 - 1) * range;
  final out = <(double, double)>[];
  for (var i = 0; i < loop.length - 1; i++) {
    final a = loop[i], b = loop[i + 1];
    final ax = a.$1 * cellSize, ay = a.$2 * cellSize;
    final bx = b.$1 * cellSize, by = b.$2 * cellSize;
    out.add((ax + j(jitter / 2), ay + j(jitter / 2)));
    for (final t in const [0.33, 0.66]) {
      out.add((ax + (bx - ax) * t + j(jitter), ay + (by - ay) * t + j(jitter)));
    }
  }
  out.add(out.first);
  return out;
}
