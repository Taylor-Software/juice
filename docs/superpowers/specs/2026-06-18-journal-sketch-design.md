# Journal Sketch (drawing) — Design

**Status:** Approved

## Problem

The journal records text, rolls, and scenes, but the player can't **draw** —
maps, faces, symbols, doodles — which the vision explicitly calls for ("some
drawings (need to add)"). This thread adds a freehand **sketch** journal entry:
draw on a canvas, save it as an entry, see it inline in the journal, and tap to
re-edit. (The broader "typed-block canvas" — inline NPC/map cards — is largely
already covered by payload entries and is out of scope here.) Backward
compatibility is out of scope (pre-release).

## Scope

**In:**
- A `JournalKind.sketch` entry whose vector strokes live in `payload`.
- A `SketchData` model (vector strokes; pure, JSON round-trips).
- A `SketchEditor` (full-screen): freehand drawing, a small color palette, two
  stroke widths, undo, clear, save/cancel.
- Inline rendering of sketch entries in the journal (a bounded `CustomPaint`
  thumbnail) that opens the editor on tap (edit-in-place).
- A **draw** button in the journal composer to start a new sketch.

**Out (later / v2):**
- Shapes/fill/text-on-canvas, eraser, layers, pan/zoom of the canvas.
- Image import / export to PNG.
- Pressure/tilt; multi-page sketches.

## Components

### `SketchData` — `lib/engine/sketch.dart` (new, pure)

Vector strokes, JSON-friendly, no Flutter `dart:ui` dependency for storage
(store plain numbers; the painter converts to `Offset`).

```dart
class SketchStroke {
  const SketchStroke({required this.color, required this.width, required this.points});
  final int color;                 // ARGB int
  final double width;
  final List<List<double>> points; // [[x,y], ...]
  Map<String,dynamic> toJson();
  factory SketchStroke.fromJson(Map<String,dynamic>);
}

class SketchData {
  const SketchData({required this.canvasWidth, required this.canvasHeight, this.strokes = const []});
  final double canvasWidth;        // logical size the strokes were drawn in
  final double canvasHeight;
  final List<SketchStroke> strokes;
  bool get isEmpty => strokes.isEmpty;
  Map<String,dynamic> toJson();    // {'v':1,'w':..,'h':..,'strokes':[...]}
  factory SketchData.fromJson(Map<String,dynamic>); // tolerant: missing → empty
}
```

The journal payload for a sketch entry is `{'v':1, 'sketch': sketchData.toJson()}`.
Storing `canvasWidth/Height` lets any size thumbnail scale faithfully.

### `SketchPainter` — `lib/features/sketch_editor.dart` (new)

A `CustomPainter` that draws a `SketchData`'s strokes (each as a `Path` through
its points, stroked with its color/width, round caps/joins) onto a **paper
background** (a fixed light fill, so stored colors render predictably in light
*and* dark mode — the canvas is "paper," not theme surface). Used by both the
editor and the inline thumbnail.

### `SketchEditor` — `lib/features/sketch_editor.dart` (new)

A full-screen `StatefulWidget` (pushed as a route / `showDialog` full-screen):
- A drawing area (`LayoutBuilder` → known size = the stored `canvasWidth/Height`)
  with a `GestureDetector` (`onPanStart`/`onPanUpdate`/`onPanEnd`) accumulating
  the in-progress stroke's points; committed strokes + the live stroke render via
  `SketchPainter`.
- Toolbar: a small color palette (e.g. black, red, blue, green, white), two
  stroke widths (thin/thick), **undo** (pop last stroke), **clear** (all),
  **cancel** (discard) and **save** (return the `SketchData`).
- Opens empty for a new sketch, or seeded with an existing entry's `SketchData`
  for editing.
- Returns `SketchData?` (null = cancel).

### Journal wiring — `lib/state/providers.dart` + `lib/features/journal_screen.dart`

- `JournalKind` gains `sketch`. Fix every exhaustive `switch (kind)` to add the
  case (the `_entry` renderer; any other — the compiler lists them).
- `JournalNotifier.addSketch(SketchData data)` → a `JournalEntry(kind: sketch,
  title: 'Sketch', body: '', payload: {'v':1,'sketch':data.toJson()})`.
- `JournalEntry.copyWith` gains an optional `Map<String,dynamic>? payload` so an
  edited sketch can be persisted via the existing `JournalNotifier.replace`
  (used today by `_interpret`).
- `_entry`'s `switch` gains `case JournalKind.sketch:` → a `Card` with a bounded
  (e.g. 180px tall) `FittedBox`/`SizedBox(canvasW,canvasH)` → `CustomPaint(
  SketchPainter)` thumbnail + the standard menu; `onTap` opens `SketchEditor`
  seeded with the entry's `SketchData`; on save → `replace(e.copyWith(payload:
  {'v':1,'sketch':edited.toJson()}))`.
- Composer `_composerBar`: a **draw** `IconButton` (key `composer-draw`,
  `Icons.draw_outlined`) between inspire and send → open `SketchEditor` (empty);
  on non-null/non-empty save → `addSketch(data)`.

## Data flow

Composer draw → `SketchEditor` → `SketchData` → `addSketch` → journal entry
(kind sketch, payload). Render: entry payload → `SketchData.fromJson` →
`SketchPainter` thumbnail. Tap thumbnail → `SketchEditor(initial)` → save →
`replace` with new payload.

## Error handling

- Empty sketch (no strokes) on save → no-op (don't add an empty entry); editing
  to empty then save → keep/replace with empty is allowed (user cleared it).
- Malformed/absent payload → `SketchData.fromJson` returns empty; thumbnail
  renders blank paper, never throws.
- Very large stroke lists: acceptable for v1 (vector, session-scoped); no cap.

## Testing

- `sketch_test.dart` — `SketchData`/`SketchStroke` round-trip (strokes, colors,
  widths, points, canvas size); `fromJson` tolerant of missing/garbage → empty;
  `isEmpty`.
- `journal` model test — `JournalKind.sketch` round-trips; `JournalEntry.copyWith
  (payload:)` replaces payload (and preserves it when omitted).
- `providers` test — `addSketch` creates a `kind==sketch` entry with the sketch
  payload.
- `sketch_editor_test.dart` — a drag adds a stroke (painter receives it); undo
  removes it; clear empties; save returns the `SketchData`; cancel returns null.
- `journal_screen` widget test — a seeded sketch entry renders a `CustomPaint`
  (not a crash); the composer `composer-draw` button exists and opens the editor.
- Full suite green; `dart format` + `flutter analyze` clean.

## Docs

- `CLAUDE.md` note: `JournalKind.sketch` + `SketchData` (`lib/engine/sketch.dart`)
  + `SketchEditor`/`SketchPainter` (`lib/features/sketch_editor.dart`, paper-bg
  vector strokes) + the composer draw button + inline thumbnail + edit-in-place
  via `JournalEntry.copyWith(payload:)` + `addSketch`. Deferred: shapes/eraser/
  image import/pan-zoom.
- No new licensed content (user-drawn vectors).
