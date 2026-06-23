# Sketch Text Tool Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a text-label tool to the sketch editor — tap to place a typed label, edit/erase it, all undoable, persisted with the sketch.

**Architecture:** A new `SketchText` value type rides alongside `SketchStroke` in `SketchData` (JSON round-trip, tolerant parse). `SketchPainter` draws labels via `TextPainter`. The editor gets a `text` tool: a clean tap (`onTapUp`, since a tap fires no pan) opens a dialog to place/edit a label; the eraser also removes labels; the undo stack becomes a `(strokes, texts)` snapshot record so every op is undoable.

**Tech Stack:** Dart, Flutter, flutter_test. Pure model in `lib/engine/sketch.dart`; editor in `lib/features/sketch_editor.dart`.

---

## File Structure

- **Modify** `lib/engine/sketch.dart` — add `SketchText`, `SketchData.texts` (+ JSON/`isEmpty`), `distanceToText`, `eraseTextsAt`. Pure.
- **Modify** `lib/features/sketch_editor.dart` — painter draws texts; `_texts` state; undo→record snapshots; `text` tool + tap dialog; eraser removes texts; toolbar button (+ horizontal-scroll hardening).
- **Modify** `test/sketch_test.dart` — `SketchText`/`texts` round-trip + `eraseTextsAt`.
- **Modify** `test/sketch_editor_test.dart` — text-tool place/edit/undo/erase widget tests.

---

## Task 1: Model — SketchText, texts, erase

**Files:**
- Modify: `lib/engine/sketch.dart`
- Test: `test/sketch_test.dart`

- [ ] **Step 1: Write the failing test**

Add to `test/sketch_test.dart` inside `void main()` (after the existing tests):

```dart
  group('SketchText', () {
    test('round-trips through JSON', () {
      const t = SketchText(text: 'Throne', x: 10, y: 20, color: 0xFF112233, size: 22);
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/sketch_test.dart`
Expected: FAIL — `SketchText` / `texts` / `eraseTextsAt` undefined.

- [ ] **Step 3: Implement**

In `lib/engine/sketch.dart`:

(a) Add the `SketchText` class after the `SketchStroke` class (after its closing `}` near line 26):

```dart
/// A text label at a logical canvas position ([x],[y] = top-left anchor).
/// [size] is in logical px and scales with the canvas like stroke coordinates.
class SketchText {
  const SketchText(
      {required this.text,
      required this.x,
      required this.y,
      required this.color,
      this.size = 18});
  final String text;
  final double x;
  final double y;
  final int color;
  final double size;

  Map<String, dynamic> toJson() =>
      {'s': text, 'x': x, 'y': y, 'c': color, 'z': size};

  factory SketchText.fromJson(Map<String, dynamic> j) => SketchText(
        text: (j['s'] as String?) ?? '',
        x: (j['x'] as num?)?.toDouble() ?? 0,
        y: (j['y'] as num?)?.toDouble() ?? 0,
        color: (j['c'] as num?)?.toInt() ?? 0xFF000000,
        size: (j['z'] as num?)?.toDouble() ?? 18,
      );
}
```

(b) In `SketchData`, add the field. Change the constructor from:

```dart
  const SketchData({
    required this.canvasWidth,
    required this.canvasHeight,
    this.strokes = const [],
    this.backgroundBlobId,
    this.pdfBlobId,
    this.pdfPage,
  });
  final double canvasWidth;
  final double canvasHeight;
  final List<SketchStroke> strokes;
```

to:

```dart
  const SketchData({
    required this.canvasWidth,
    required this.canvasHeight,
    this.strokes = const [],
    this.texts = const [],
    this.backgroundBlobId,
    this.pdfBlobId,
    this.pdfPage,
  });
  final double canvasWidth;
  final double canvasHeight;
  final List<SketchStroke> strokes;
  final List<SketchText> texts;
```

(c) Update `isEmpty`. Change:

```dart
  bool get isEmpty => strokes.isEmpty && backgroundBlobId == null;
```

to:

```dart
  bool get isEmpty =>
      strokes.isEmpty && texts.isEmpty && backgroundBlobId == null;
```

(d) Update `toJson`. Change:

```dart
        'strokes': strokes.map((s) => s.toJson()).toList(),
        if (backgroundBlobId != null) 'bg': backgroundBlobId,
```

to:

```dart
        'strokes': strokes.map((s) => s.toJson()).toList(),
        'texts': texts.map((t) => t.toJson()).toList(),
        if (backgroundBlobId != null) 'bg': backgroundBlobId,
```

(e) Update `fromJson`. Change:

```dart
        strokes: (j['strokes'] is List
                ? (j['strokes'] as List<dynamic>)
                : const <dynamic>[])
            .whereType<Map<dynamic, dynamic>>()
            .map((m) => SketchStroke.fromJson(m.cast<String, dynamic>()))
            .toList(),
        backgroundBlobId: j['bg'] as String?,
```

to:

```dart
        strokes: (j['strokes'] is List
                ? (j['strokes'] as List<dynamic>)
                : const <dynamic>[])
            .whereType<Map<dynamic, dynamic>>()
            .map((m) => SketchStroke.fromJson(m.cast<String, dynamic>()))
            .toList(),
        texts: (j['texts'] is List ? (j['texts'] as List<dynamic>) : const <dynamic>[])
            .whereType<Map<dynamic, dynamic>>()
            .map((m) => SketchText.fromJson(m.cast<String, dynamic>()))
            .toList(),
        backgroundBlobId: j['bg'] as String?,
```

(f) Add the erase helpers at the end of the file (after `eraseStrokesAt`):

```dart
/// Distance from `(x,y)` to a text label's anchor point.
double distanceToText(SketchText t, double x, double y) =>
    math.sqrt((x - t.x) * (x - t.x) + (y - t.y) * (y - t.y));

/// Returns [texts] with every label whose anchor the eraser at `(x,y)` touches
/// (within [radius]) removed. Order preserved; input not mutated.
List<SketchText> eraseTextsAt(
        List<SketchText> texts, double x, double y, double radius) =>
    [for (final t in texts) if (distanceToText(t, x, y) > radius) t];
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/sketch_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/sketch.dart test/sketch_test.dart
git commit -m "feat(sketch): SketchText model + texts on SketchData + eraseTextsAt

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 2: Painter renders texts + editor persists them + undo→record

**Files:**
- Modify: `lib/features/sketch_editor.dart`
- Test: `test/sketch_editor_test.dart`

This task makes existing sketches with texts render + save, and refactors undo to
snapshot `(strokes, texts)` — WITHOUT adding the text tool yet (Task 3).

- [ ] **Step 1: Write the failing test**

Add to `test/sketch_editor_test.dart` inside `void main()` (after the existing tests):

```dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/sketch_editor_test.dart`
Expected: FAIL — `_save` drops `texts` (result.texts is empty).

- [ ] **Step 3: Implement**

In `lib/features/sketch_editor.dart`:

(a) `SketchPainter.paint` — after the strokes `for` loop (after its closing `}`, before `paint`'s closing `}`), draw texts. The `sx`/`sy` scale vars are already in scope:

```dart
    for (final t in data.texts) {
      final tp = TextPainter(
        text: TextSpan(
          text: t.text,
          style: TextStyle(color: Color(t.color), fontSize: t.size * sy),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(t.x * sx, t.y * sy));
    }
```

(b) Add the `_texts` state field. After `late List<SketchStroke> _strokes = [...?widget.initial?.strokes];` add:

```dart
  late List<SketchText> _texts = [...?widget.initial?.texts];
```

(c) Refactor the undo stack to snapshot both lists. Change:

```dart
  final List<List<SketchStroke>> _undo = [];
```

to:

```dart
  // Undo history: snapshots of (strokes, texts) before each mutation, so every
  // op (draw, shape, erase, clear, text add/edit) is one undo step.
  final List<({List<SketchStroke> strokes, List<SketchText> texts})> _undo = [];

  void _snapshot() => _undo.add((strokes: _strokes, texts: _texts));
```

(d) Update the undo button. Change:

```dart
            onPressed: _undo.isEmpty
                ? null
                : () => setState(() => _strokes = _undo.removeLast()),
```

to:

```dart
            onPressed: _undo.isEmpty
                ? null
                : () => setState(() {
                      final snap = _undo.removeLast();
                      _strokes = snap.strokes;
                      _texts = snap.texts;
                    }),
```

(e) Update the clear button. Change:

```dart
            onPressed: () => setState(() {
              if (_strokes.isNotEmpty) _undo.add(_strokes);
              _strokes = [];
              _current = [];
            }),
```

to:

```dart
            onPressed: () => setState(() {
              if (_strokes.isNotEmpty || _texts.isNotEmpty) _snapshot();
              _strokes = [];
              _texts = [];
              _current = [];
            }),
```

(f) Update `_eraseAt` to also erase texts in the same snapshot. Change the whole method:

```dart
  void _eraseAt(Offset o) {
    final before = _strokes;
    final after = eraseStrokesAt(before, o.dx, o.dy, _eraserRadius);
    if (after.length == before.length) return; // nothing under the pointer
    if (!_erasing) {
      _undo.add(before);
      _erasing = true;
    }
    setState(() => _strokes = after);
  }
```

to:

```dart
  void _eraseAt(Offset o) {
    final beforeStrokes = _strokes;
    final beforeTexts = _texts;
    final afterStrokes = eraseStrokesAt(beforeStrokes, o.dx, o.dy, _eraserRadius);
    final afterTexts = eraseTextsAt(beforeTexts, o.dx, o.dy, _eraserRadius);
    if (afterStrokes.length == beforeStrokes.length &&
        afterTexts.length == beforeTexts.length) {
      return; // nothing under the pointer
    }
    if (!_erasing) {
      _undo.add((strokes: beforeStrokes, texts: beforeTexts));
      _erasing = true;
    }
    setState(() {
      _strokes = afterStrokes;
      _texts = afterTexts;
    });
  }
```

(g) Update the stroke-commit in `onPanEnd`. Change:

```dart
            if (_current.isNotEmpty) {
              _undo.add(_strokes);
              _strokes = [
```

to:

```dart
            if (_current.isNotEmpty) {
              _snapshot();
              _strokes = [
```

(h) Pass `texts` into the `build` preview. Change:

```dart
    final preview = SketchData(
      canvasWidth: _canvas.width,
      canvasHeight: _canvas.height,
      strokes: [
        ..._strokes,
        if (_current.isNotEmpty)
          SketchStroke(color: _color, width: _width, points: _current),
      ],
    );
```

to:

```dart
    final preview = SketchData(
      canvasWidth: _canvas.width,
      canvasHeight: _canvas.height,
      strokes: [
        ..._strokes,
        if (_current.isNotEmpty)
          SketchStroke(color: _color, width: _width, points: _current),
      ],
      texts: _texts,
    );
```

(i) Pass `texts` into `_save`. Change:

```dart
    widget.onDone(SketchData(
      canvasWidth: _canvas.width,
      canvasHeight: _canvas.height,
      strokes: _strokes,
      backgroundBlobId: widget.backgroundBlobId,
      pdfBlobId: widget.pdfBlobId,
      pdfPage: widget.pdfPage,
    ));
```

to:

```dart
    widget.onDone(SketchData(
      canvasWidth: _canvas.width,
      canvasHeight: _canvas.height,
      strokes: _strokes,
      texts: _texts,
      backgroundBlobId: widget.backgroundBlobId,
      pdfBlobId: widget.pdfBlobId,
      pdfPage: widget.pdfPage,
    ));
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/sketch_editor_test.dart`
Expected: PASS (the new test + all existing editor tests, which now exercise the record-based undo).

- [ ] **Step 5: Commit**

```bash
git add lib/features/sketch_editor.dart test/sketch_editor_test.dart
git commit -m "feat(sketch): render + persist sketch texts; undo snapshots (strokes,texts)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 3: Text tool — tap to place/edit, eraser removes, toolbar button

**Files:**
- Modify: `lib/features/sketch_editor.dart`
- Test: `test/sketch_editor_test.dart`

- [ ] **Step 1: Write the failing tests**

Add to `test/sketch_editor_test.dart` inside `void main()` (after Task 2's test):

```dart
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
    // Tap the same spot with the text tool still active → edit dialog seeded.
    await tester.tapAt(tester.getTopLeft(find.byKey(const Key('sketch-canvas'))) +
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

  testWidgets('eraser removes a placed label', (tester) async {
    SketchData? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SketchEditor(onDone: (d) => result = d)),
    ));
    await tester.pumpAndSettle();
    await placeText(tester, 'Trap', at: const Offset(40, 40));
    await tester.tap(find.byKey(const Key('sketch-tool-eraser')));
    await tester.pumpAndSettle();
    // Drag the eraser across the label's anchor.
    final canvas = find.byKey(const Key('sketch-canvas'));
    final g = await tester.startGesture(
        tester.getTopLeft(canvas) + const Offset(38, 38));
    await g.moveBy(const Offset(8, 8));
    await g.up();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sketch-save')));
    await tester.pumpAndSettle();
    expect(result!.texts, isEmpty);
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/sketch_editor_test.dart`
Expected: FAIL — no `sketch-tool-text` button.

- [ ] **Step 3: Implement**

In `lib/features/sketch_editor.dart`:

(a) Add `text` to the tool enum. Change:

```dart
enum _SketchTool { pen, eraser, line, rect, ellipse }
```

to:

```dart
enum _SketchTool { pen, eraser, line, rect, ellipse, text }
```

(b) Add a tap-radius constant + the tap handler. Add this field near `_eraserRadius`:

```dart
  static const _textHitRadius = 22.0;
```

Add this method (place it after `_eraseAt`):

```dart
  /// Text-tool tap: edit the label under the tap if one is near, else place a
  /// new one. Cancel (null) leaves everything unchanged.
  Future<void> _handleTextTap(Offset o) async {
    SketchText? hit;
    for (final t in _texts) {
      if (distanceToText(t, o.dx, o.dy) <= _textHitRadius) {
        hit = t;
        break;
      }
    }
    final controller = TextEditingController(text: hit?.text ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('sketch-text-dialog'),
        title: const Text('Text label'),
        content: TextField(
          key: const Key('sketch-text-field'),
          controller: controller,
          autofocus: true,
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text),
              child: const Text('OK')),
        ],
      ),
    );
    controller.dispose();
    if (result == null || !mounted) return; // cancelled
    final value = result.trim();
    setState(() {
      if (hit != null) {
        _snapshot();
        _texts = [
          for (final t in _texts)
            if (!identical(t, hit))
              t
            else if (value.isNotEmpty)
              SketchText(
                  text: value, x: t.x, y: t.y, color: t.color, size: t.size),
        ];
      } else if (value.isNotEmpty) {
        _snapshot();
        _texts = [
          ..._texts,
          SketchText(text: value, x: o.dx, y: o.dy, color: _color),
        ];
      }
    });
  }
```

(c) Wire the tap + make pan handlers ignore the text tool. In `_canvasArea`'s `GestureDetector`, add an `onTapUp` (right after the `key:` line, before `onPanStart`):

```dart
        onTapUp: (d) {
          if (_tool == _SketchTool.text) _handleTextTap(d.localPosition);
        },
```

Then guard the three pan handlers so the text tool never draws. At the very start of `onPanStart`'s body, `onPanUpdate`'s body, and `onPanEnd`'s body, add:

```dart
          if (_tool == _SketchTool.text) return;
```

(For `onPanEnd` the signature is `(_)`, so the guard is the first statement inside the braces.)

(d) Add the toolbar button + harden the toolbar against overflow. The toolbar's outer `Row` (inside `_toolbar()`'s `Padding`) currently holds the palette, a `Spacer()`, two width buttons, and five tool buttons. Two changes:

First, after the `sketch-tool-ellipse` `IconButton` (the last one), add:

```dart
              IconButton(
                key: const Key('sketch-tool-text'),
                icon: const Icon(Icons.title),
                tooltip: 'Text',
                isSelected: _tool == _SketchTool.text,
                color: _tool == _SketchTool.text ? Colors.blue : null,
                onPressed: () => setState(() => _tool = _SketchTool.text),
              ),
```

Second, prevent the now-six-tool row from overflowing on a narrow phone: wrap the `Row` in a horizontal scroll view and replace the `Spacer` with a fixed gap. Change the `Padding`'s child from:

```dart
          child: Row(
            children: [
              for (final c in _palette)
```

to:

```dart
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final c in _palette)
```

and change the `const Spacer(),` (between the palette loop and the width buttons) to:

```dart
                const SizedBox(width: 16),
```

(A `Spacer` can't live inside a horizontally-scrolling `Row` — it needs bounded width — so it becomes a fixed gap. At the tests' default 800px width every button is on-screen, so taps by key work without scrolling; narrow phones scroll instead of overflowing.) Re-indent the moved children by two spaces and add the matching closing `)` for the new `SingleChildScrollView` (the implementer should run `dart format` / rely on the format hook, then verify the braces balance via `flutter analyze`).

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/sketch_editor_test.dart`
Expected: PASS (all existing + the 4 new text-tool tests).

- [ ] **Step 5: Run analyze + full suite**

Run: `flutter analyze` → expect `No issues found!`
Run: `flutter test` → expect All tests passed.

- [ ] **Step 6: Commit**

```bash
git add lib/features/sketch_editor.dart test/sketch_editor_test.dart
git commit -m "feat(sketch): text tool — tap to place/edit labels, eraser removes them

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 4: Doc sync — CLAUDE.md sketch note

**Files:**
- Modify: `CLAUDE.md` (the journal-sketch bullet, the sentence listing the tools)

- [ ] **Step 1: Update the tools sentence**

In `CLAUDE.md`, find the sketch bullet text listing the tools:
`pen/eraser/shape tools (`sketch-tool-pen`/`sketch-tool-eraser`/`sketch-tool-line`/ `sketch-tool-rect`/`sketch-tool-ellipse`; ...`. Change the tool-key list to include text and note the new model field. Replace:

```
  pen/eraser/shape tools (`sketch-tool-pen`/`sketch-tool-eraser`/`sketch-tool-line`/
  `sketch-tool-rect`/`sketch-tool-ellipse`; eraser = whole-stroke delete via pure
  `eraseStrokesAt`/`distanceToStroke` in `sketch.dart`, radius scales with width;
  shapes = `SketchStroke` with computed points — line 2 pts, rect 5 closed pts,
  ellipse 37-pt polyline — no schema change), undo (now a snapshot history stack
  covering draw+erase+clear), clear, save/cancel.
```

with:

```
  pen/eraser/shape/text tools (`sketch-tool-pen`/`sketch-tool-eraser`/`sketch-tool-line`/
  `sketch-tool-rect`/`sketch-tool-ellipse`/`sketch-tool-text`; eraser = whole-element
  delete via pure `eraseStrokesAt`/`distanceToStroke` + `eraseTextsAt`/`distanceToText`
  in `sketch.dart`, radius scales with width; shapes = `SketchStroke` with computed
  points — line 2 pts, rect 5 closed pts, ellipse 37-pt polyline; text = `SketchText`
  {text,x,y,color,size} on `SketchData.texts`, tap-to-place/edit via a dialog, drawn
  with `TextPainter` — both no-blob, JSON round-trip), undo (a snapshot history stack
  of (strokes,texts) covering draw+shape+text+erase+clear), clear, save/cancel.
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: note the sketch text tool in CLAUDE.md

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:**
- §1 Model (`SketchText`, `SketchData.texts`, JSON, `isEmpty`, `distanceToText`/`eraseTextsAt`) → Task 1. ✓
- §2 Painter draws texts → Task 2 (a). ✓
- §3 Editor: `text` tool → Task 3(a); `_texts` state → Task 2(b); undo→record → Task 2(c-g); tap place/edit dialog → Task 3(b,c); eraser removes texts → Task 2(f); `_save`/`build` include texts → Task 2(h,i). ✓
- §4 Toolbar button → Task 3(d). ✓
- §5 Export round-trip (texts in `SketchData` JSON, no blob change) → Task 1(d,e). ✓
- Testing: model/erase (Task 1), painter+persist (Task 2), tool/dialog/undo/erase (Task 3). ✓
- "tap (onTapUp) not pan; pan handlers early-return for text" → Task 3(c). ✓
- "shouldRepaint needs no change" → not touched (correct). ✓

**Type consistency:**
- `SketchText` ctor `{text,x,y,color,size}` identical in Tasks 1 & 3. ✓
- `_undo` record type `({List<SketchStroke> strokes, List<SketchText> texts})` consistent across Task 2 (def, button, clear, erase, commit) and Task 3 (`_snapshot()` reuse). ✓
- `_snapshot()` defined Task 2(c), used Task 2(g) + Task 3(b). ✓
- Keys: `sketch-tool-text`, `sketch-text-dialog`, `sketch-text-field` consistent between Task 3 impl + tests. ✓

**Placeholder scan:** No TBD/TODO; every code step has complete code. The toolbar re-indent note (Task 3d) leans on `dart format` + `flutter analyze` to confirm brace balance — acceptable since the exact re-indent is mechanical and analyze is a hard gate in Step 5. ✓

**Risk note:** Task 3(d) restructures the toolbar (Row → scroll view); the existing width/tool buttons must remain inside. The `flutter analyze` gate (Step 5) catches an unbalanced brace, and the existing tool-button tests (pen/eraser/shape taps) regression-cover that the buttons still resolve.
