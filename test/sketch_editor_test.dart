import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/sketch.dart';
import 'package:juice_oracle/features/sketch_editor.dart';

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
}
