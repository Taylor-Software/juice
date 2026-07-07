import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dungeon/organic.dart';

void main() {
  test('perimeter of a 2x1 footprint is a closed jittered loop', () {
    final pts = organicPerimeter(const [(0, 0), (0, 1)],
        seed: 42, cellSize: 56, jitter: 5);
    expect(pts.length, greaterThan(8));
    expect(pts.first, pts.last);
  });

  test('deterministic for the same seed, different for another', () {
    final a =
        organicPerimeter(const [(0, 0)], seed: 7, cellSize: 56, jitter: 5);
    final b =
        organicPerimeter(const [(0, 0)], seed: 7, cellSize: 56, jitter: 5);
    final c =
        organicPerimeter(const [(0, 0)], seed: 8, cellSize: 56, jitter: 5);
    expect(a, b);
    expect(a, isNot(c));
  });

  test('jitter never exceeds the bound', () {
    final pts =
        organicPerimeter(const [(0, 0)], seed: 3, cellSize: 56, jitter: 4);
    for (final p in pts) {
      expect(p.$1, inInclusiveRange(-4.0, 60.0));
      expect(p.$2, inInclusiveRange(-4.0, 60.0));
    }
  });

  test('L-shaped footprint (concave corner) still closes', () {
    final pts = organicPerimeter(const [(0, 0), (0, 1), (1, 1)],
        seed: 1, cellSize: 56, jitter: 5);
    expect(pts.first, pts.last);
    expect(pts.length, greaterThan(12));
  });
}
