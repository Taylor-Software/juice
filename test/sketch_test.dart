import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/sketch.dart';

void main() {
  group('SketchData', () {
    test('round-trips strokes', () {
      const d = SketchData(canvasWidth: 300, canvasHeight: 200, strokes: [
        SketchStroke(color: 0xFF000000, width: 3, points: [
          [10, 10],
          [20, 25],
          [30, 40]
        ]),
      ]);
      final back = SketchData.fromJson(d.toJson());
      expect(back.canvasWidth, 300);
      expect(back.canvasHeight, 200);
      expect(back.strokes.length, 1);
      expect(back.strokes.first.color, 0xFF000000);
      expect(back.strokes.first.width, 3);
      expect(back.strokes.first.points, [
        [10, 10],
        [20, 25],
        [30, 40]
      ]);
    });
    test('empty + tolerant fromJson', () {
      expect(const SketchData(canvasWidth: 1, canvasHeight: 1).isEmpty, isTrue);
      expect(SketchData.fromJson(const {}).isEmpty, isTrue);
      expect(SketchData.fromJson(const {'strokes': 'garbage'}).isEmpty, isTrue);
    });
  });

  group('eraser geometry', () {
    SketchStroke line(List<List<double>> pts) =>
        SketchStroke(color: 0xFF000000, width: 4, points: pts);

    test('distanceToStroke: on, beside, and beyond a segment', () {
      final s = line([
        [0, 0],
        [10, 0]
      ]);
      expect(distanceToStroke(s, 5, 0), closeTo(0, 1e-9));
      expect(distanceToStroke(s, 5, 3), closeTo(3, 1e-9));
      expect(distanceToStroke(s, 15, 0), closeTo(5, 1e-9)); // past endpoint
    });

    test('distanceToStroke: single point and empty', () {
      expect(
          distanceToStroke(
              line([
                [2, 2]
              ]),
              5,
              6),
          closeTo(5, 1e-9)); // 3-4-5
      expect(distanceToStroke(line(const []), 0, 0), double.infinity);
    });

    test('eraseStrokesAt removes hits, keeps misses, preserves & no mutate', () {
      final a = line([
        [0, 0],
        [10, 0]
      ]);
      final b = line([
        [100, 100],
        [110, 100]
      ]);
      final input = [a, b];
      // (5,1) is ~1px from a (≤ radius 4 + width/2 2) → a removed, b kept.
      expect(eraseStrokesAt(input, 5, 1, 4), [b]);
      expect(input, [a, b]); // input untouched
      // A miss removes nothing.
      expect(eraseStrokesAt(input, 500, 500, 4), [a, b]);
    });
  });
}
