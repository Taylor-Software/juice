# Sketch text tool: tappable text labels on sketches

**Date:** 2026-06-23
**Status:** Design — approved

## Problem

The sketch editor draws freehand strokes and shapes (line/rect/ellipse) but
can't place **text labels**. Annotating an imported map or PDF page — "Throne
Room", "Trap here", a hex number — needs typed labels, not freehand scrawl.
This is the natural next sketch primitive after shapes.

## Decisions (from brainstorming)

- **Tap-to-place + dialog** (not drag-to-place): tap the canvas with the text
  tool → an `AlertDialog` with a `TextField` → the label lands at the tap point.
  Robust on every platform; repositioning is deferred.
- **Eraser deletes text** (no separate delete tool): consistent whole-element
  erase, same as strokes.
- **Fixed default size** in v1 (no per-text size/font UI). Color from the
  existing palette.

## Architecture

### 1. Model — `lib/engine/sketch.dart`

New value type, parallel to `SketchStroke`:

```dart
/// A text label at a logical canvas position (top-left anchor). Size is in
/// logical px and scales with the canvas like stroke coordinates.
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

`SketchData` gains `texts`:

```dart
final List<SketchText> texts; // defaults to const []
```

- Constructor: `this.texts = const []`.
- `toJson`: add `'texts': texts.map((t) => t.toJson()).toList()` (always emit,
  beside — and consistent with — the existing `'strokes'` key).
- `fromJson`: parse `j['texts']` the same tolerant way as `strokes` (whereType
  `Map`, map to `SketchText.fromJson`).
- `isEmpty`: becomes `strokes.isEmpty && texts.isEmpty && backgroundBlobId ==
  null` (a sketch with only text labels is worth keeping).

Erase hit-test helper (pure):

```dart
/// Distance from (x,y) to a text label's anchor point.
double distanceToText(SketchText t, double x, double y) =>
    math.sqrt((x - t.x) * (x - t.x) + (y - t.y) * (y - t.y));

/// [texts] with every label whose anchor the eraser at (x,y) touches removed.
List<SketchText> eraseTextsAt(
        List<SketchText> texts, double x, double y, double radius) =>
    [for (final t in texts) if (distanceToText(t, x, y) > radius) t];
```

### 2. Painter — `lib/features/sketch_editor.dart` (`SketchPainter`)

After drawing strokes, draw each text. Reuse the existing `sx`/`sy` scale
factors:

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

`shouldRepaint` needs no change: `SketchData` has no value-equality override, so
`old.data != data` is reference inequality and the painter already repaints on
every new `SketchData` instance (one is built each frame in `build`).

### 3. Editor — `_SketchEditorState`

- `_SketchTool` gains a `text` case.
- New state: `late List<SketchText> _texts = [...?widget.initial?.texts];`.
- **Undo refactor**: the snapshot stack changes from
  `List<List<SketchStroke>>` to a record list
  `final List<({List<SketchStroke> strokes, List<SketchText> texts})> _undo`.
  A `_snapshot()` helper pushes `(strokes: _strokes, texts: _texts)` before any
  mutation; undo pops and restores both. Every existing push site
  (`_eraseAt`, the pen/shape commit in `onPanEnd`, clear) switches to
  `_snapshot()`; the undo button restores both lists.
- **Place/edit via a tap** (NOT pan — a clean tap places no pan event, so use a
  dedicated `onTapUp` on the canvas `GestureDetector`): when `_tool == text`,
  hit-test `_texts` for an existing label within a tap radius:
  - hit → open the dialog seeded with that label's text; on save, `_snapshot()`
    then replace it (empty result → remove it);
  - miss → open the dialog empty; on save (non-empty), `_snapshot()` then append
    a `SketchText` at the tap point in `_color` (default size).
  Dialog: `showDialog` with a `TextField` (autofocus) + Cancel/OK; key
  `sketch-text-dialog`, field key `sketch-text-field`.
  The existing pan handlers (`onPanStart/Update/End`) early-return when
  `_tool == text`, so the text tool is tap-only and never draws a stroke.
- `_save`: include `texts: _texts` in the emitted `SketchData`.
- `build` preview: the `SketchData` passed to the painter includes `texts:
  _texts` (the live `_current` stroke is still appended to `strokes` only).
- Eraser drag (`_eraseAt`): also run `eraseTextsAt` so an erase pass removes both
  strokes and text under the pointer in one snapshot.

### 4. Toolbar

Add a text-tool `IconButton` (`Key('sketch-tool-text')`, `Icons.title` /
`Icons.text_fields`) beside the shape tools, same `isSelected`/blue-highlight
pattern.

### 5. Export / round-trip

Texts ride the existing `SketchData` JSON — no bundle changes (text references
no blobs). The `campaign_bundle` `referencedBlobIds` scan is unaffected.

## Testing

- `sketch_test` (pure): `SketchText` JSON round-trips; tolerant `fromJson`
  (missing keys → defaults); `SketchData` with texts round-trips and
  `isEmpty` is false when only texts exist; `eraseTextsAt` removes a label
  within radius and keeps one outside.
- `sketch_editor_test` (widget): with the text tool, tapping the canvas opens
  the dialog; entering text + OK adds one text (saved `SketchData.texts` has
  length 1); tapping an existing label reopens the dialog seeded with its text;
  clearing it on edit removes it; **text add is undoable** (undo → empty);
  the eraser removes a placed label.

## Out of scope (YAGNI)

- Drag-to-reposition; per-text size/font/bold controls; rich text; rotation;
  multi-line auto-wrap (a single `TextPainter` honors typed `\n` but no wrap UI);
  selection handles.

## Files touched

| File | Change |
|------|--------|
| `lib/engine/sketch.dart` | `SketchText` type; `SketchData.texts` + JSON/isEmpty; `distanceToText`/`eraseTextsAt` |
| `lib/features/sketch_editor.dart` | painter draws texts; `text` tool; undo→record snapshot; place/edit dialog; eraser removes texts; toolbar button |
| tests | `sketch_test` (model/erase), `sketch_editor_test` (tool/dialog/undo/erase) |
