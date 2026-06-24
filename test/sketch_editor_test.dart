import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/sketch.dart';
import 'package:juice_oracle/features/sketch_editor.dart';

Future<ui.Image> _redImage() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 4, 4),
      Paint()..color = const Color(0xFFFF0000));
  return recorder.endRecording().toImage(4, 4);
}

void main() {
  testWidgets('draw a stroke then save returns SketchData', (tester) async {
    SketchData? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SketchEditor(onDone: (d) => result = d),
      ),
    ));
    await tester.pumpAndSettle();
    // Drag across the canvas to draw one stroke.
    final canvas = find.byKey(const Key('sketch-canvas'));
    final center = tester.getCenter(canvas);
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(80, 60));
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sketch-save')));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.strokes, isNotEmpty);
  });

  testWidgets('undo removes the last stroke', (tester) async {
    SketchData? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SketchEditor(onDone: (d) => result = d)),
    ));
    await tester.pumpAndSettle();
    final canvas = find.byKey(const Key('sketch-canvas'));
    final center = tester.getCenter(canvas);
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(50, 0));
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sketch-undo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sketch-save')));
    await tester.pumpAndSettle();
    expect(result!.strokes, isEmpty);
  });

  testWidgets('clear empties all strokes', (tester) async {
    SketchData? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SketchEditor(onDone: (d) => result = d)),
    ));
    await tester.pumpAndSettle();
    final canvas = find.byKey(const Key('sketch-canvas'));
    final center = tester.getCenter(canvas);
    // Two separate strokes.
    for (final dx in [30.0, -30.0]) {
      final gesture = await tester.startGesture(center);
      await gesture.moveBy(Offset(dx, 20));
      await gesture.up();
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const Key('sketch-clear')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sketch-save')));
    await tester.pumpAndSettle();
    expect(result!.strokes, isEmpty);
  });

  Future<void> drawStroke(WidgetTester tester) async {
    final center = tester.getCenter(find.byKey(const Key('sketch-canvas')));
    final g = await tester.startGesture(center);
    await g.moveBy(const Offset(60, 0));
    await g.up();
    await tester.pumpAndSettle();
  }

  testWidgets('eraser drag deletes a stroke it passes over', (tester) async {
    SketchData? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SketchEditor(onDone: (d) => result = d)),
    ));
    await tester.pumpAndSettle();
    await drawStroke(tester);
    await tester.tap(find.byKey(const Key('sketch-tool-eraser')));
    await tester.pumpAndSettle();
    // Drag from the stroke's start across part of its path.
    final center = tester.getCenter(find.byKey(const Key('sketch-canvas')));
    final g = await tester.startGesture(center);
    await g.moveBy(const Offset(30, 0));
    await g.up();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sketch-save')));
    await tester.pumpAndSettle();
    expect(result!.strokes, isEmpty);
  });

  testWidgets('undo restores an erased stroke', (tester) async {
    SketchData? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SketchEditor(onDone: (d) => result = d)),
    ));
    await tester.pumpAndSettle();
    await drawStroke(tester);
    await tester.tap(find.byKey(const Key('sketch-tool-eraser')));
    await tester.pumpAndSettle();
    final center = tester.getCenter(find.byKey(const Key('sketch-canvas')));
    final g = await tester.startGesture(center);
    await g.moveBy(const Offset(30, 0));
    await g.up();
    await tester.pumpAndSettle();
    // Erased; undo brings it back.
    await tester.tap(find.byKey(const Key('sketch-undo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sketch-save')));
    await tester.pumpAndSettle();
    expect(result!.strokes.length, 1);
  });

  testWidgets('editor with a background image saves its backgroundBlobId',
      (tester) async {
    final img = await _redImage();
    SketchData? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SketchEditor(
          background: img,
          backgroundBlobId: 'blob-1',
          onDone: (d) => result = d,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    // An imported image with no strokes still saves (the image is the content).
    await tester.tap(find.byKey(const Key('sketch-save')));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.backgroundBlobId, 'blob-1');
    expect(result!.isEmpty, isFalse);
  });

  testWidgets('a background image aspect-locks the canvas; plain does not',
      (tester) async {
    final img = await _redImage();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SketchEditor(
            background: img, backgroundBlobId: 'b', onDone: (_) {}),
      ),
    ));
    await tester.pumpAndSettle();
    expect(
        find.ancestor(
            of: find.byKey(const Key('sketch-canvas')),
            matching: find.byType(AspectRatio)),
        findsOneWidget);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SketchEditor(onDone: (_) {})),
    ));
    await tester.pumpAndSettle();
    expect(
        find.ancestor(
            of: find.byKey(const Key('sketch-canvas')),
            matching: find.byType(AspectRatio)),
        findsNothing);
  });

  group('decodeSketchBackground', () {
    test('null or empty bytes → null', () async {
      expect(await decodeSketchBackground(null), isNull);
      expect(await decodeSketchBackground(const []), isNull);
    });
    test('valid PNG bytes → an image', () async {
      final png =
          await (await _redImage()).toByteData(format: ui.ImageByteFormat.png);
      final decoded = await decodeSketchBackground(png!.buffer.asUint8List());
      expect(decoded, isNotNull);
      expect(decoded!.width, 4);
    });
  });

  group('disposeSketchBackgroundLater', () {
    test('null is a no-op', () {
      expect(() => disposeSketchBackgroundLater(null), returnsNormally);
    });
    testWidgets('defers dispose past the editor pop, then releases it',
        (tester) async {
      final img = await _redImage();
      disposeSketchBackgroundLater(img);
      // The regression: disposing inline races the editor's exit transition
      // (the painter keeps drawing the image for a few frames → "Cannot paint
      // an image that is disposed"). It must still be live right after the call.
      expect(img.debugDisposed, isFalse);
      // ...and freed once the deferral elapses, so we don't leak it.
      await tester.pump(const Duration(seconds: 1));
      expect(img.debugDisposed, isTrue);
    });
  });

  for (final tool in ['line', 'rect', 'ellipse']) {
    testWidgets('$tool tool drag commits a stroke', (tester) async {
      SketchData? result;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SketchEditor(onDone: (d) => result = d)),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('sketch-tool-$tool')));
      await tester.pumpAndSettle();
      final canvas = find.byKey(const Key('sketch-canvas'));
      final g = await tester
          .startGesture(tester.getTopLeft(canvas) + const Offset(10, 10));
      await g.moveBy(const Offset(80, 60));
      await g.up();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sketch-save')));
      await tester.pumpAndSettle();
      expect(result!.strokes, hasLength(1));
      final pts = result!.strokes.single.points;
      if (tool == 'line') expect(pts, hasLength(2));
      if (tool == 'rect') expect(pts, hasLength(5));
      if (tool == 'ellipse') expect(pts, hasLength(37)); // 0..36 inclusive
    });
  }

  testWidgets('shape stroke is undoable', (tester) async {
    SketchData? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SketchEditor(onDone: (d) => result = d)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sketch-tool-rect')));
    await tester.pumpAndSettle();
    final canvas = find.byKey(const Key('sketch-canvas'));
    final g = await tester
        .startGesture(tester.getTopLeft(canvas) + const Offset(10, 10));
    await g.moveBy(const Offset(50, 40));
    await g.up();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sketch-undo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sketch-save')));
    await tester.pumpAndSettle();
    expect(result!.strokes, isEmpty);
  });

  testWidgets('cancel returns null', (tester) async {
    SketchData? result;
    var called = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SketchEditor(onDone: (d) {
        called = true;
        result = d;
      })),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sketch-cancel')));
    await tester.pumpAndSettle();
    expect(called, isTrue);
    expect(result, isNull);
  });

  testWidgets('initial texts are preserved on save', (tester) async {
    SketchData? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SketchEditor(
          initial: const SketchData(
            canvasWidth: 100,
            canvasHeight: 100,
            texts: [SketchText(text: 'Keep', x: 5, y: 5, color: 0xFF000000)],
          ),
          onDone: (d) => result = d,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sketch-save')));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.texts, hasLength(1));
    expect(result!.texts.single.text, 'Keep');
  });

  Future<void> placeText(WidgetTester tester, String value,
      {Offset at = const Offset(40, 40)}) async {
    await tester.tap(find.byKey(const Key('sketch-tool-text')));
    await tester.pumpAndSettle();
    final canvas = find.byKey(const Key('sketch-canvas'));
    await tester.tapAt(tester.getTopLeft(canvas) + at);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('sketch-text-field')), value);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  testWidgets('text tool places a label that is saved', (tester) async {
    SketchData? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SketchEditor(onDone: (d) => result = d)),
    ));
    await tester.pumpAndSettle();
    await placeText(tester, 'Trap');
    await tester.tap(find.byKey(const Key('sketch-save')));
    await tester.pumpAndSettle();
    expect(result!.texts, hasLength(1));
    expect(result!.texts.single.text, 'Trap');
  });

  testWidgets('placing a label is undoable', (tester) async {
    SketchData? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SketchEditor(onDone: (d) => result = d)),
    ));
    await tester.pumpAndSettle();
    await placeText(tester, 'Trap');
    await tester.tap(find.byKey(const Key('sketch-undo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sketch-save')));
    await tester.pumpAndSettle();
    expect(result!.texts, isEmpty);
  });

  testWidgets('tapping an existing label reopens the dialog to edit it',
      (tester) async {
    SketchData? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SketchEditor(onDone: (d) => result = d)),
    ));
    await tester.pumpAndSettle();
    await placeText(tester, 'Trap', at: const Offset(40, 40));
    await tester.tapAt(
        tester.getTopLeft(find.byKey(const Key('sketch-canvas'))) +
            const Offset(40, 40));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Trap'), findsOneWidget); // seeded
    await tester.enterText(find.byKey(const Key('sketch-text-field')), 'Pit');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sketch-save')));
    await tester.pumpAndSettle();
    expect(result!.texts.single.text, 'Pit'); // replaced, not duplicated
  });

  testWidgets('clearing an existing label on edit deletes it', (tester) async {
    SketchData? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SketchEditor(onDone: (d) => result = d)),
    ));
    await tester.pumpAndSettle();
    await placeText(tester, 'Trap', at: const Offset(40, 40));
    // Reopen the label and clear its text → it should be removed.
    await tester.tapAt(
        tester.getTopLeft(find.byKey(const Key('sketch-canvas'))) +
            const Offset(40, 40));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('sketch-text-field')), '');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sketch-save')));
    await tester.pumpAndSettle();
    expect(result!.texts, isEmpty);
  });

  testWidgets('eraser removes a placed label', (tester) async {
    SketchData? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SketchEditor(onDone: (d) => result = d)),
    ));
    await tester.pumpAndSettle();
    await placeText(tester, 'Trap', at: const Offset(40, 40));
    await tester.tap(find.byKey(const Key('sketch-tool-eraser')));
    await tester.pumpAndSettle();
    final canvas = find.byKey(const Key('sketch-canvas'));
    final g = await tester
        .startGesture(tester.getTopLeft(canvas) + const Offset(38, 38));
    await g.moveBy(const Offset(8, 8));
    await g.up();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sketch-save')));
    await tester.pumpAndSettle();
    expect(result!.texts, isEmpty);
  });
}
