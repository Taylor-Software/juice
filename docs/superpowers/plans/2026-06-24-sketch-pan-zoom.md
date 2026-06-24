# Sketch Pan-Zoom Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a pan/zoom "hand" tool to the sketch editor so you can zoom in to annotate fine detail on a PDF page or map snapshot.

**Architecture:** A new `_SketchTool.pan` wraps the canvas in an `InteractiveViewer` (a `TransformationController`); `panEnabled`/`scaleEnabled` are gated on the pan tool, and every gesture point is un-transformed via `_tc.toScene(...)` so strokes land in canvas coordinates. View-only — no `SketchData`/export change.

**Tech Stack:** Dart, Flutter, flutter_test. `InteractiveViewer` + `TransformationController` (Flutter SDK).

---

## File Structure

- **Modify** `lib/features/sketch_editor.dart` — `_SketchTool.pan`, `TransformationController` + dispose, `InteractiveViewer` wrap, `_scene` un-transform, pan-mode draw gate, pan tool button, reset-zoom button.
- **Modify** `test/sketch_editor_test.dart` — pan-tool flip + reset-zoom widget tests.
- **Modify** `CLAUDE.md` — note pan-zoom shipped.

All edits are in `_SketchEditorState`. NOTE: `_SketchEditorState` currently has NO `dispose()` override (the `dispose` near line 537 belongs to the text-input dialog) — Task 1 adds one for the `TransformationController`.

---

## Task 1: Pan tool + transform core

**Files:**
- Modify: `lib/features/sketch_editor.dart`
- Test: `test/sketch_editor_test.dart`

- [ ] **Step 1: Write the failing test** — add inside `void main()` in `test/sketch_editor_test.dart`:

```dart
  testWidgets('pan tool enables InteractiveViewer pan/zoom', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SketchEditor(onDone: (_) {})),
    ));
    await tester.pumpAndSettle();
    InteractiveViewer iv() =>
        tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    // Default tool is pen → pan/zoom disabled (drawing passes through).
    expect(iv().panEnabled, isFalse);
    expect(iv().scaleEnabled, isFalse);
    // The pan tool enables it.
    await tester.tap(find.byKey(const Key('sketch-tool-pan')));
    await tester.pumpAndSettle();
    expect(iv().panEnabled, isTrue);
    expect(iv().scaleEnabled, isTrue);
    // Back to a draw tool disables it again.
    await tester.tap(find.byKey(const Key('sketch-tool-pen')));
    await tester.pumpAndSettle();
    expect(iv().panEnabled, isFalse);
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/sketch_editor_test.dart`
Expected: FAIL — no `InteractiveViewer` in the tree / no `sketch-tool-pan`.

- [ ] **Step 3a: Add the enum value** — change:

```dart
enum _SketchTool { pen, eraser, line, rect, ellipse, text }
```
to
```dart
enum _SketchTool { pen, eraser, line, rect, ellipse, text, pan }
```

- [ ] **Step 3b: Add the controller + dispose** — in `_SketchEditorState`, beside the other state fields (after `_SketchTool _tool = _SketchTool.pen;`) add:

```dart
  // Pan/zoom viewport transform (view-only — never saved into the sketch).
  final TransformationController _tc = TransformationController();
```

and add a `dispose` override to `_SketchEditorState` (it has none yet):

```dart
  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }
```

- [ ] **Step 3c: Wrap the canvas + un-transform** — replace the whole `_canvasArea` method with this (wraps the `GestureDetector` in `InteractiveViewer`, routes every gesture point through `_scene`, and disables the draw handlers in pan mode):

```dart
  Widget _canvasArea(SketchData preview) {
    final surface = LayoutBuilder(builder: (context, constraints) {
      _canvas = Size(constraints.maxWidth, constraints.maxHeight);
      final canDraw = _tool != _SketchTool.text && _tool != _SketchTool.pan;
      return InteractiveViewer(
        transformationController: _tc,
        panEnabled: _tool == _SketchTool.pan,
        scaleEnabled: _tool == _SketchTool.pan,
        minScale: 1.0,
        maxScale: 6.0,
        child: GestureDetector(
          key: const Key('sketch-canvas'),
          // Tap and pan recognizers are mutually exclusive by mode: the text
          // tool places labels on a clean tap; every other DRAW tool draws on a
          // pan; the pan tool draws nothing (InteractiveViewer handles it).
          // Every point is un-transformed via _scene so strokes land in canvas
          // coordinates regardless of zoom/pan.
          onTapUp: _tool == _SketchTool.text
              ? (d) => _handleTextTap(_scene(d.localPosition))
              : null,
          onPanStart: !canDraw
              ? null
              : (d) {
                  final p = _scene(d.localPosition);
                  if (_tool == _SketchTool.eraser) {
                    _erasing = false;
                    _eraseAt(p);
                  } else if (_tool == _SketchTool.pen) {
                    setState(() => _current = [_xy(p)]);
                  } else {
                    setState(() {
                      _shapeStart = p;
                      _current = [];
                    });
                  }
                },
          onPanUpdate: !canDraw
              ? null
              : (d) {
                  final p = _scene(d.localPosition);
                  if (_tool == _SketchTool.eraser) {
                    _eraseAt(p);
                  } else if (_tool == _SketchTool.pen) {
                    setState(() => _current.add(_xy(p)));
                  } else if (_shapeStart != null) {
                    setState(() => _current = _shapePoints(_shapeStart!, p));
                  }
                },
          onPanEnd: !canDraw
              ? null
              : (_) {
                  if (_tool == _SketchTool.eraser) {
                    _erasing = false;
                    return;
                  }
                  setState(() {
                    if (_current.isNotEmpty) {
                      _snapshot();
                      _strokes = [
                        ..._strokes,
                        SketchStroke(
                            color: _color, width: _width, points: _current),
                      ];
                    }
                    _current = [];
                    _shapeStart = null;
                  });
                },
          child: CustomPaint(
            painter: SketchPainter(preview, background: widget.background),
            size: Size.infinite,
          ),
        ),
      );
    });
    final bg = widget.background;
    if (bg == null) return surface;
    return Center(
      child: AspectRatio(aspectRatio: bg.width / bg.height, child: surface),
    );
  }

  /// Viewport point → canvas (scene) point, inverting the zoom/pan transform.
  /// At scale 1 / no pan this is the identity, so drawing is unchanged.
  Offset _scene(Offset viewport) => _tc.toScene(viewport);
```

(`_xy(Offset)`, `_handleTextTap`, `_eraseAt`, `_shapePoints`, `_shapeStart`,
`_erasing`, `_current` are all existing — only the points feeding them change.)

- [ ] **Step 3d: Add the pan tool button** — in `_toolbar`, after the `sketch-tool-text` `IconButton` (the last tool, before the closing `]` of the `Row` children), add:

```dart
                IconButton(
                  key: const Key('sketch-tool-pan'),
                  icon: const Icon(Icons.pan_tool_outlined),
                  tooltip: 'Pan & zoom',
                  isSelected: _tool == _SketchTool.pan,
                  color: _tool == _SketchTool.pan ? Colors.blue : null,
                  onPressed: () => setState(() => _tool = _SketchTool.pan),
                ),
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/sketch_editor_test.dart`
Expected: PASS (the new test + the existing draw/undo/shape/text tests — drawing at scale 1 is unchanged because `_scene` is the identity).

- [ ] **Step 5: Commit**

```bash
git add lib/features/sketch_editor.dart test/sketch_editor_test.dart
git commit -m "feat(sketch): pan/zoom hand tool (InteractiveViewer + scene-coord un-transform)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 2: Reset-zoom button

**Files:**
- Modify: `lib/features/sketch_editor.dart`
- Test: `test/sketch_editor_test.dart`

- [ ] **Step 1: Write the failing test** — add inside `void main()` in `test/sketch_editor_test.dart`:

```dart
  testWidgets('reset-zoom restores the identity transform', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SketchEditor(onDone: (_) {})),
    ));
    await tester.pumpAndSettle();
    final tc = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!;
    tc.value = Matrix4.identity()..scale(2.0);
    expect(tc.value, isNot(Matrix4.identity()));
    await tester.tap(find.byKey(const Key('sketch-zoom-reset')));
    await tester.pumpAndSettle();
    expect(tc.value, Matrix4.identity());
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/sketch_editor_test.dart`
Expected: FAIL — no `sketch-zoom-reset` widget.

- [ ] **Step 3: Implement** — in the `AppBar`'s `actions`, before the `sketch-undo` `IconButton`, add:

```dart
          IconButton(
            key: const Key('sketch-zoom-reset'),
            icon: const Icon(Icons.zoom_out_map),
            tooltip: 'Reset zoom',
            onPressed: () => setState(() => _tc.value = Matrix4.identity()),
          ),
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/sketch_editor_test.dart`
Expected: PASS.

- [ ] **Step 5: Full verification**

Run: `flutter analyze` → expect `No issues found!`
Run: `flutter test` → expect All tests passed.

- [ ] **Step 6: Commit**

```bash
git add lib/features/sketch_editor.dart test/sketch_editor_test.dart
git commit -m "feat(sketch): reset-zoom button

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 3: Doc sync — CLAUDE.md

**Files:** Modify `CLAUDE.md` (the journal-sketch bullet).

- [ ] **Step 1: Update the deferred list** — in `CLAUDE.md`, find the sketch deferred note that reads `shapes/text/layers/pan-zoom` (in the PDF-annotation-pdfrx "Deferred:" sentence of the journal-sketch bullet). Since pan-zoom now ships, change `shapes/text/layers/pan-zoom` to `layers` and add a sentence after the relevant spec reference:

```
  **Pan-zoom shipped:** the editor wraps its canvas in an `InteractiveViewer`
  driven by a `_SketchTool.pan` hand tool (toolbar) — `panEnabled`/`scaleEnabled`
  gated on the tool, `minScale 1`/`maxScale 6`; every gesture point is
  un-transformed via `_tc.toScene` so strokes land in canvas coords at any zoom,
  and a `sketch-zoom-reset` app-bar button refits. View-only (no `SketchData`/
  export change). The pan-tool flip + reset are widget-tested; draw-while-zoomed
  is device-verified. See
  `docs/superpowers/specs/2026-06-24-sketch-pan-zoom-design.md`.
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: note sketch pan-zoom in CLAUDE.md

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:**
- §1 pan tool + transform (`_SketchTool.pan`, `_tc`, `InteractiveViewer`, gating) → Task 1. ✓
- §2 coordinate un-transform (`_scene` at every gesture) → Task 1 Step 3c. ✓
- §3 disable drawing in pan mode (`canDraw` gate) → Task 1 Step 3c. ✓
- §4 toolbar pan button → Task 1 Step 3d; reset-zoom button → Task 2. ✓
- View-only (no model change), no `_snapshot` on pan-zoom → Task 1 (the transform is only `_tc`, never touched in `_snapshot`/save). ✓
- Testing (pan-tool flip, reset) → Tasks 1, 2; draw-while-zoomed device-verified. ✓
- Doc → Task 3. ✓

**Type consistency:**
- `_SketchTool.pan` (Task 1 enum) used in the gating + tool button (Task 1) consistently.
- `TransformationController _tc` (Task 1) used by `InteractiveViewer` + `_scene` (Task 1) + reset (Task 2). ✓
- `_scene(Offset) -> Offset` defined Task 1 Step 3c, used at every gesture in the same method. ✓
- Keys `sketch-tool-pan` (Task 1) + `sketch-zoom-reset` (Task 2) consistent between impl + tests. ✓

**Placeholder scan:** No TBD/TODO; complete code per step. ✓

**Risk notes:**
- Existing draw/undo/shape/text tests must still pass — `_scene` is the identity at scale 1, so coordinates are byte-identical to before. If any existing test now finds two `InteractiveViewer`s (it won't — there's one), adjust the finder, but the editor adds exactly one.
- The reset test sets `tc.value` directly (the controller is reachable via the `InteractiveViewer` widget) to simulate a zoomed state without driving gestures.
