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

  testWidgets('undo removes the last stroke; clear empties', (tester) async {
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
}
