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
}
