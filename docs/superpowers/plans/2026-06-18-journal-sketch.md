# Journal Sketch (drawing) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A freehand sketch journal entry — draw on a canvas, save as a `JournalKind.sketch` entry, see it inline, tap to re-edit.

**Architecture:** A pure `SketchData` (vector strokes) stored in the journal entry `payload`. A `SketchPainter` (paper background + colored strokes) renders both the editor and the inline thumbnail. A `SketchEditor` full-screen widget captures freehand strokes. The composer gets a draw button; `_entry` gets a sketch case; `JournalNotifier.addSketch` + `JournalEntry.copyWith(payload:)` persist new/edited sketches.

**Tech Stack:** Flutter (`CustomPainter`, `GestureDetector`), `flutter_riverpod`, `package:flutter_test`.

---

## File Structure

**Create:**
- `lib/engine/sketch.dart` — `SketchStroke`, `SketchData` (pure).
- `lib/features/sketch_editor.dart` — `SketchPainter`, `SketchEditor`, `showSketchEditor`.
- `test/sketch_test.dart`, `test/sketch_editor_test.dart`.

**Modify:**
- `lib/engine/models.dart` — `JournalKind.sketch`; `JournalEntry.copyWith(payload:)`.
- `lib/state/providers.dart` — `JournalNotifier.addSketch`.
- `lib/features/journal_screen.dart` — `_entry` sketch case + composer draw button.
- `CLAUDE.md`.

**Test:** `test/journal_test.dart` (or models test), `test/journal_screen_test.dart`.

---

## P1 — model + journal wiring

### Task 1: SketchData model

**Files:**
- Create: `lib/engine/sketch.dart`
- Test: `test/sketch_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/sketch.dart';

void main() {
  group('SketchData', () {
    test('round-trips strokes', () {
      const d = SketchData(canvasWidth: 300, canvasHeight: 200, strokes: [
        SketchStroke(color: 0xFF000000, width: 3, points: [
          [10, 10], [20, 25], [30, 40]
        ]),
      ]);
      final back = SketchData.fromJson(d.toJson());
      expect(back.canvasWidth, 300);
      expect(back.canvasHeight, 200);
      expect(back.strokes.length, 1);
      expect(back.strokes.first.color, 0xFF000000);
      expect(back.strokes.first.width, 3);
      expect(back.strokes.first.points, [[10, 10], [20, 25], [30, 40]]);
    });
    test('empty + tolerant fromJson', () {
      expect(const SketchData(canvasWidth: 1, canvasHeight: 1).isEmpty, isTrue);
      expect(SketchData.fromJson(const {}).isEmpty, isTrue);
      expect(SketchData.fromJson(const {'strokes': 'garbage'}).isEmpty, isTrue);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/sketch_test.dart`
Expected: FAIL — `sketch.dart` not found.

- [ ] **Step 3: Create `lib/engine/sketch.dart`**

```dart
/// A single freehand stroke: an ARGB color, a width, and its points.
class SketchStroke {
  const SketchStroke(
      {required this.color, required this.width, required this.points});
  final int color;
  final double width;
  final List<List<double>> points; // [[x,y], ...]

  Map<String, dynamic> toJson() => {
        'c': color,
        'w': width,
        'p': points,
      };

  factory SketchStroke.fromJson(Map<String, dynamic> j) => SketchStroke(
        color: (j['c'] as num?)?.toInt() ?? 0xFF000000,
        width: (j['w'] as num?)?.toDouble() ?? 3,
        points: ((j['p'] as List?) ?? const [])
            .whereType<List>()
            .map((pt) => pt.whereType<num>().map((n) => n.toDouble()).toList())
            .where((pt) => pt.length == 2)
            .toList(),
      );
}

/// A vector sketch drawn at a known logical canvas size; round-trips via JSON.
class SketchData {
  const SketchData({
    required this.canvasWidth,
    required this.canvasHeight,
    this.strokes = const [],
  });
  final double canvasWidth;
  final double canvasHeight;
  final List<SketchStroke> strokes;

  bool get isEmpty => strokes.isEmpty;

  Map<String, dynamic> toJson() => {
        'v': 1,
        'w': canvasWidth,
        'h': canvasHeight,
        'strokes': strokes.map((s) => s.toJson()).toList(),
      };

  factory SketchData.fromJson(Map<String, dynamic> j) => SketchData(
        canvasWidth: (j['w'] as num?)?.toDouble() ?? 1,
        canvasHeight: (j['h'] as num?)?.toDouble() ?? 1,
        strokes: ((j['strokes'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => SketchStroke.fromJson(m.cast<String, dynamic>()))
            .toList(),
      );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/sketch_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/sketch.dart test/sketch_test.dart
git commit -m "feat(sketch): SketchData vector model"
```

---

### Task 2: JournalKind.sketch + copyWith(payload) + fix switches

**Files:**
- Modify: `lib/engine/models.dart` (JournalKind line 80; JournalEntry.copyWith 117-135)
- Test: `test/journal_test.dart` (append) or models test

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';

void main() {
  test('JournalKind.sketch round-trips', () {
    final e = JournalEntry(
        id: 's1', timestamp: DateTime(2026), title: 'Sketch', body: '',
        kind: JournalKind.sketch, payload: const {'v': 1, 'sketch': {}});
    final back = JournalEntry.fromJson(e.toJson());
    expect(back.kind, JournalKind.sketch);
    expect(back.payload?['v'], 1);
  });
  test('copyWith(payload:) replaces, omitted keeps', () {
    final e = JournalEntry(
        id: 's1', timestamp: DateTime(2026), title: 'S', body: '',
        kind: JournalKind.sketch, payload: const {'a': 1});
    expect(e.copyWith(payload: const {'b': 2}).payload, const {'b': 2});
    expect(e.copyWith(title: 'X').payload, const {'a': 1});
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/journal_test.dart`
Expected: FAIL — `JournalKind.sketch` undefined / copyWith has no payload.

- [ ] **Step 3: Add the enum value + copyWith param**

In `lib/engine/models.dart`: `enum JournalKind { text, result, scene, sketch }`.
Extend `JournalEntry.copyWith` with `Map<String, dynamic>? payload` →
`payload: payload ?? this.payload` (keep all other fields preserved as today).

- [ ] **Step 4: Fix exhaustive switches**

Run `flutter analyze`. Every `switch` on `JournalKind` without a default now
errors (non-exhaustive). Add a `case JournalKind.sketch:` to each. The
`_entry` renderer (journal_screen.dart) is handled fully in Task 5 — for now,
give it a minimal `case JournalKind.sketch: return const SizedBox.shrink();`
placeholder so analyze passes, to be replaced in Task 5. Any OTHER switch (e.g.
an icon/label helper) gets a sensible case. List each file you touched.

- [ ] **Step 5: Run test + analyze**

Run: `flutter test test/journal_test.dart` → PASS.
Run: `flutter analyze` → No issues (all switches exhaustive).

- [ ] **Step 6: Commit**

```bash
git add lib/engine/models.dart lib/features/journal_screen.dart test/journal_test.dart
git commit -m "feat(sketch): JournalKind.sketch + JournalEntry.copyWith(payload)"
```

---

### Task 3: JournalNotifier.addSketch

**Files:**
- Modify: `lib/state/providers.dart` (`JournalNotifier`, after `addScene`)
- Test: `test/journal_test.dart` or a provider test (append)

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:juice_oracle/engine/sketch.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

// inside main():
  test('addSketch creates a sketch entry with payload', () async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.journal.v2.default': '[]',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(journalProvider.future);
    await c.read(journalProvider.notifier).addSketch(const SketchData(
        canvasWidth: 300, canvasHeight: 200, strokes: [
      SketchStroke(color: 0xFF000000, width: 3, points: [[1, 1], [2, 2]])
    ]));
    final e = (await c.read(journalProvider.future)).first;
    expect(e.kind, JournalKind.sketch);
    expect(e.payload?['sketch'], isNotNull);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/journal_test.dart -n nothing` → run the file; expected FAIL — `addSketch` undefined.

(Use `flutter test test/journal_test.dart`.)

- [ ] **Step 3: Add `addSketch`**

In `JournalNotifier` (after `addScene`):

```dart
  Future<void> addSketch(SketchData data) async {
    await _persist([
      JournalEntry(
          id: _newId(),
          timestamp: DateTime.now(),
          title: 'Sketch',
          body: '',
          kind: JournalKind.sketch,
          payload: {'v': 1, 'sketch': data.toJson()}),
      ...await _ready,
    ]);
  }
```

Add `import '../engine/sketch.dart';` to providers.dart if needed.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/journal_test.dart` → PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/state/providers.dart test/journal_test.dart
git commit -m "feat(sketch): JournalNotifier.addSketch"
```

---

## P2 — editor + journal UI

### Task 4: SketchPainter + SketchEditor

**Files:**
- Create: `lib/features/sketch_editor.dart`
- Test: `test/sketch_editor_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
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
    await tester.drag(
        find.byKey(const Key('sketch-canvas')), const Offset(80, 60));
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
    await tester.drag(
        find.byKey(const Key('sketch-canvas')), const Offset(50, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sketch-undo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sketch-save')));
    await tester.pumpAndSettle();
    expect(result!.strokes, isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/sketch_editor_test.dart`
Expected: FAIL — `sketch_editor.dart` not found.

- [ ] **Step 3: Create `lib/features/sketch_editor.dart`**

```dart
import 'package:flutter/material.dart';

import '../engine/sketch.dart';

const _paper = Color(0xFFFAF7F0);
const _palette = <int>[
  0xFF222222, 0xFFD83A2A, 0xFF2A6FD8, 0xFF2E9E5B, 0xFFFFFFFF,
];

/// Paints a [SketchData]'s strokes on a paper background (theme-independent so
/// stored colors render the same in light and dark mode).
class SketchPainter extends CustomPainter {
  const SketchPainter(this.data);
  final SketchData data;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _paper);
    final sx = data.canvasWidth == 0 ? 1.0 : size.width / data.canvasWidth;
    final sy = data.canvasHeight == 0 ? 1.0 : size.height / data.canvasHeight;
    for (final s in data.strokes) {
      if (s.points.isEmpty) continue;
      final paint = Paint()
        ..color = Color(s.color)
        ..strokeWidth = s.width
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final path = Path()..moveTo(s.points.first[0] * sx, s.points.first[1] * sy);
      for (final p in s.points.skip(1)) {
        path.lineTo(p[0] * sx, p[1] * sy);
      }
      // A single tap (one point) draws a dot.
      if (s.points.length == 1) {
        canvas.drawCircle(Offset(s.points.first[0] * sx, s.points.first[1] * sy),
            s.width / 2, paint..style = PaintingStyle.fill);
      } else {
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(SketchPainter old) => old.data != data;
}

/// Full-screen freehand editor. Calls [onDone] with the drawing (or null on
/// cancel) and pops.
class SketchEditor extends StatefulWidget {
  const SketchEditor({super.key, this.initial, required this.onDone});
  final SketchData? initial;
  final void Function(SketchData? result) onDone;

  @override
  State<SketchEditor> createState() => _SketchEditorState();
}

class _SketchEditorState extends State<SketchEditor> {
  late List<SketchStroke> _strokes = [...?widget.initial?.strokes];
  List<List<double>> _current = [];
  int _color = _palette.first;
  double _width = 3;
  Size _canvas = const Size(1, 1);

  void _save() {
    widget.onDone(SketchData(
      canvasWidth: _canvas.width,
      canvasHeight: _canvas.height,
      strokes: _strokes,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final preview = SketchData(
      canvasWidth: _canvas.width,
      canvasHeight: _canvas.height,
      strokes: [
        ..._strokes,
        if (_current.isNotEmpty)
          SketchStroke(color: _color, width: _width, points: _current),
      ],
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sketch'),
        leading: IconButton(
          key: const Key('sketch-cancel'),
          icon: const Icon(Icons.close),
          onPressed: () => widget.onDone(null),
        ),
        actions: [
          IconButton(
            key: const Key('sketch-undo'),
            icon: const Icon(Icons.undo),
            tooltip: 'Undo',
            onPressed: _strokes.isEmpty
                ? null
                : () => setState(() => _strokes.removeLast()),
          ),
          IconButton(
            key: const Key('sketch-clear'),
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear',
            onPressed: () => setState(() {
              _strokes = [];
              _current = [];
            }),
          ),
          IconButton(
            key: const Key('sketch-save'),
            icon: const Icon(Icons.check),
            tooltip: 'Save',
            onPressed: _save,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(builder: (context, constraints) {
              _canvas = Size(constraints.maxWidth, constraints.maxHeight);
              return GestureDetector(
                key: const Key('sketch-canvas'),
                onPanStart: (d) =>
                    setState(() => _current = [_xy(d.localPosition)]),
                onPanUpdate: (d) =>
                    setState(() => _current.add(_xy(d.localPosition))),
                onPanEnd: (_) => setState(() {
                  if (_current.isNotEmpty) {
                    _strokes.add(SketchStroke(
                        color: _color, width: _width, points: _current));
                  }
                  _current = [];
                }),
                child: CustomPaint(
                  painter: SketchPainter(preview),
                  size: Size.infinite,
                ),
              );
            }),
          ),
          _toolbar(),
        ],
      ),
    );
  }

  List<double> _xy(Offset o) => [o.dx, o.dy];

  Widget _toolbar() => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              for (final c in _palette)
                GestureDetector(
                  onTap: () => setState(() => _color = c),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Color(c),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _color == c ? Colors.blue : Colors.black26,
                        width: _color == c ? 3 : 1,
                      ),
                    ),
                  ),
                ),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.circle, size: _width <= 3 ? 22 : 14),
                tooltip: 'Thin',
                onPressed: () => setState(() => _width = 3),
              ),
              IconButton(
                icon: Icon(Icons.circle, size: _width > 3 ? 22 : 14),
                tooltip: 'Thick',
                onPressed: () => setState(() => _width = 8),
              ),
            ],
          ),
        ),
      );
}

/// Opens the editor full-screen; returns the drawing or null on cancel.
Future<SketchData?> showSketchEditor(BuildContext context,
    {SketchData? initial}) {
  return Navigator.of(context).push<SketchData>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => SketchEditor(
      initial: initial,
      onDone: (d) => Navigator.of(context).pop(d),
    ),
  ));
}
```

(Note: `showSketchEditor` wires `onDone` → `Navigator.pop(result)`. The widget
tests pass `onDone` directly without a route, so they assert on the callback.)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/sketch_editor_test.dart`
Expected: PASS. (If `tester.drag` produces a single pan with start+end, the
stroke has ≥1 point — adjust the test's drag offset if needed so a pan fires.)
Run: `flutter analyze lib/features/sketch_editor.dart`
Expected: No issues.

- [ ] **Step 5: Commit**

```bash
git add lib/features/sketch_editor.dart test/sketch_editor_test.dart
git commit -m "feat(sketch): SketchPainter + freehand SketchEditor"
```

---

### Task 5: Journal inline render + composer draw button

**Files:**
- Modify: `lib/features/journal_screen.dart` (`_entry` sketch case + `_composerBar`)
- Test: `test/journal_screen_test.dart` (append) or a new `test/journal_sketch_ui_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
  testWidgets('a sketch entry renders a CustomPaint thumbnail', (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.journal.v2.default':
          '[{"id":"s1","timestamp":"2026-06-18T00:00:00.000","title":"Sketch",'
          '"body":"","kind":"sketch","tags":[],'
          '"payload":{"v":1,"sketch":{"v":1,"w":300,"h":200,"strokes":'
          '[{"c":4278190080,"w":3,"p":[[10,10],[40,40]]}]}}}]',
    });
    final c = await pumpJournal(tester); // use the file's journal pump helper
    expect(find.byType(CustomPaint), findsWidgets); // thumbnail present
  });

  testWidgets('composer has a draw button', (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.journal.v2.default': '[]',
    });
    await pumpJournal(tester);
    expect(find.byKey(const Key('composer-draw')), findsOneWidget);
  });
```

(Use `journal_screen_test.dart`'s existing pump harness — it overrides
`interpreterServiceProvider` + seeds prefs. `find.byType(CustomPaint)` matches
many widgets; scope to the sketch card via a `Key('sketch-thumb-s1')` you add in
Step 3 and assert on that instead for precision.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/journal_screen_test.dart -n sketch` (or the new file).
Expected: FAIL — sketch renders the Task-2 placeholder `SizedBox.shrink()`; no
`composer-draw`.

- [ ] **Step 3: Implement the sketch case + draw button**

In `journal_screen.dart`, replace the Task-2 placeholder `case
JournalKind.sketch:` in `_entry` with:

```dart
      case JournalKind.sketch:
        final data = SketchData.fromJson(
            (e.payload?['sketch'] as Map?)?.cast<String, dynamic>() ??
                const {});
        return Card(
          child: InkWell(
            onTap: () async {
              final edited = await showSketchEditor(context, initial: data);
              if (edited != null) {
                await ref.read(journalProvider.notifier).replace(e.copyWith(
                    payload: {'v': 1, 'sketch': edited.toJson()}));
              }
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  key: Key('sketch-thumb-${e.id}'),
                  height: 180,
                  child: CustomPaint(painter: SketchPainter(data)),
                ),
                Row(
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(left: 12),
                      child: Text('Sketch'),
                    ),
                    const Spacer(),
                    menu,
                  ],
                ),
              ],
            ),
          ),
        );
```

Add imports `'../engine/sketch.dart'` and `'sketch_editor.dart'` to
journal_screen.dart. (`menu` is the `PopupMenuButton` already built at the top of
`_entry`.)

In `_composerBar`, insert between `composer-inspire` and `journal-send`:

```dart
          IconButton(
            key: const Key('composer-draw'),
            icon: const Icon(Icons.draw_outlined),
            tooltip: 'Draw a sketch',
            onPressed: () async {
              final data = await showSketchEditor(context);
              if (data != null && !data.isEmpty) {
                await ref.read(journalProvider.notifier).addSketch(data);
              }
            },
          ),
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/journal_screen_test.dart` (+ the new sketch UI test).
Expected: PASS.
Run: `flutter analyze lib/features/journal_screen.dart`
Expected: No issues.

- [ ] **Step 5: Commit**

```bash
git add lib/features/journal_screen.dart test/
git commit -m "feat(sketch): inline sketch thumbnail + composer draw button"
```

---

### Task 6: Full verify + docs

- [ ] **Step 1:** `flutter analyze` → No issues; `flutter test` → all pass.
- [ ] **Step 2:** `CLAUDE.md` note:

```markdown
- **Journal sketches (drawing).** `JournalKind.sketch` entries store vector
  strokes in `payload['sketch']` as `SketchData` (`lib/engine/sketch.dart`,
  pure: strokes = color/width/points + canvas size). `SketchEditor` +
  `SketchPainter` (`lib/features/sketch_editor.dart`) draw freehand on a
  fixed paper background (so colors read the same in light/dark); palette,
  two widths, undo, clear, save/cancel. The composer `composer-draw` button
  opens it for a new sketch (→ `JournalNotifier.addSketch`); a sketch entry
  renders an inline `CustomPaint` thumbnail (`sketch-thumb-<id>`) and taps open
  the editor seeded with its strokes, saving via
  `JournalEntry.copyWith(payload:)` + `JournalNotifier.replace`. See
  `docs/superpowers/specs/2026-06-18-journal-sketch-design.md`. Deferred:
  shapes/eraser/image import/pan-zoom.
```

- [ ] **Step 3:** Commit `docs(sketch): document journal sketches`.

---

## Self-Review

**1. Spec coverage:** SketchData (T1), JournalKind.sketch + copyWith payload + switch fixes (T2), addSketch (T3), SketchPainter+Editor (T4), inline thumbnail + composer draw + edit-in-place (T5), docs (T6). ✓
**2. Placeholder scan:** none; the Task-2 `SizedBox.shrink()` is an explicit, named interim replaced in Task 5 (not a vague TODO). "Use the file's pump helper" points at the concrete journal_screen_test harness.
**3. Type consistency:** `SketchStroke{color,width,points}`, `SketchData{canvasWidth,canvasHeight,strokes,isEmpty}`, payload shape `{'v':1,'sketch':SketchData.toJson}`, `JournalKind.sketch`, `JournalEntry.copyWith(payload:)`, `addSketch(SketchData)`, `SketchPainter(SketchData)`, `SketchEditor(initial,onDone)`, `showSketchEditor(context,{initial})`, keys `sketch-canvas/undo/clear/save/cancel`, `composer-draw`, `sketch-thumb-<id>` — consistent across tasks.

**Ordering note:** Task 2 must precede Task 5 (the enum value + the interim placeholder keep the tree compiling); Task 5 replaces the placeholder. Tasks 1–3 are P1 (logic), 4–5 P2 (UI).
