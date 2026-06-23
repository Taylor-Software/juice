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

    test('round-trips backgroundBlobId; an image-only sketch is not empty', () {
      const d =
          SketchData(canvasWidth: 10, canvasHeight: 10, backgroundBlobId: 'b1');
      expect(d.isEmpty, isFalse); // a background image alone is worth keeping
      final back = SketchData.fromJson(d.toJson());
      expect(back.backgroundBlobId, 'b1');
      expect(back.isEmpty, isFalse);
    });

    test('round-trips PDF provenance (pdfBlobId + pdfPage)', () {
      const d = SketchData(
        canvasWidth: 10,
        canvasHeight: 10,
        backgroundBlobId: 'raster.png',
        pdfBlobId: 'src.pdf',
        pdfPage: 3,
      );
      final back = SketchData.fromJson(d.toJson());
      expect(back.pdfBlobId, 'src.pdf');
      expect(back.pdfPage, 3);
      expect(back.backgroundBlobId, 'raster.png');
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

    test('eraseStrokesAt removes hits, keeps misses, preserves & no mutate',
        () {
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

  group('SketchText', () {
    test('round-trips through JSON', () {
      const t =
          SketchText(text: 'Throne', x: 10, y: 20, color: 0xFF112233, size: 22);
      final back = SketchText.fromJson(t.toJson());
      expect(back.text, 'Throne');
      expect(back.x, 10);
      expect(back.y, 20);
      expect(back.color, 0xFF112233);
      expect(back.size, 22);
    });

    test('fromJson tolerates missing keys with defaults', () {
      final t = SketchText.fromJson(const {});
      expect(t.text, '');
      expect(t.x, 0);
      expect(t.y, 0);
      expect(t.size, 18); // default
    });
  });

  group('SketchData.texts', () {
    test('texts round-trip and a text-only sketch is not empty', () {
      const data = SketchData(
        canvasWidth: 100,
        canvasHeight: 100,
        texts: [SketchText(text: 'Hi', x: 1, y: 2, color: 0xFF000000)],
      );
      expect(data.isEmpty, isFalse); // text-only is worth keeping
      final back = SketchData.fromJson(data.toJson());
      expect(back.texts, hasLength(1));
      expect(back.texts.single.text, 'Hi');
    });

    test('empty when no strokes, texts, or background', () {
      const data = SketchData(canvasWidth: 1, canvasHeight: 1);
      expect(data.isEmpty, isTrue);
    });
  });

  group('eraseTextsAt', () {
    test('removes a label within radius, keeps one outside', () {
      const texts = [
        SketchText(text: 'near', x: 10, y: 10, color: 0xFF000000),
        SketchText(text: 'far', x: 200, y: 200, color: 0xFF000000),
      ];
      final after = eraseTextsAt(texts, 12, 12, 20);
      expect(after.map((t) => t.text), ['far']);
    });
  });
}
