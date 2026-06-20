# Sketch v2 + PDF Annotation — Design

## Goal

Grow the journal sketch feature toward a single drawing engine that serves both
freehand sketches and annotation of **user-imported PDFs / user-generated maps
& handouts** (never the bundled rulebooks — that would re-open the content-
licensing posture the app avoids).

## Engine decision: keep the custom engine (do NOT adopt a drawing package)

Evaluated pub.dev drawing packages against our hard requirement — **re-editable
vector strokes serialized to JSON** (sketches persist in the `juice.journal.v2`
payload AND in campaign-export files, and re-open into the editor) — plus an
image background (for PDF pages) and Flutter web support:

| engine | JSON serialize (re-edit) | image background | eraser | web | health |
|--------|:---:|:---:|:---:|:---:|---|
| flutter_painter_v2 | ❌ PNG export only | ✓ | ✓ | canvaskit only | ~17mo stale |
| scribble | ✓ | ❌ (Stack workaround) | ✓ | ✓ | ~2yr stale, pre-1.0 |
| **custom (`lib/engine/sketch.dart`)** | ✓ (owned, already exported) | ✓ trivial (already paints over `_paper`) | ➕ add | ✓ | ours |

No package jointly meets the requirements. `flutter_painter_v2`'s PNG-only
persistence is a hard mismatch with our re-editable + exported sketch model;
adopting it would lose vector re-editability and force migrating existing
sketches. The custom engine already nails serialization + background + web +
re-edit; it only lacks an eraser (cheap) and shapes/text (future, build on the
model we own). Conclusion: extend the custom engine; stay on the lean stack.

## Decomposition

- **Sub-project A — Eraser (this spec's implementation).**
- **Sub-project B — PDF annotation (future epic, own spec).** Add `pdfrx`
  (open/BSD, web via pdf.js + canvaskit) to render a user-imported PDF page to a
  `ui.Image`; generalize `SketchEditor`'s background from the `_paper` constant
  to an optional `ui.Image` (added then, with `pdfrx` as its first real caller —
  not speculatively now); persist annotation strokes in the existing
  `SketchStroke` JSON keyed to a page index. Content scope: user-imported PDFs +
  user-generated maps/handouts only.

## Sub-project A — Eraser

### Behavior

A pen/eraser tool toggle in the editor. Erasing is **whole-stroke delete**
(vector-clean, matches the model — no paper-colored fake strokes): dragging in
eraser mode removes any stroke the pointer passes within a radius.

### Pure core — `lib/engine/sketch.dart` (unit-tested)

- `double distanceToStroke(SketchStroke s, double x, double y)` — minimum
  distance from `(x,y)` to the stroke's polyline (point-to-segment over
  consecutive points; a single-point stroke → distance to that point; empty
  stroke → `double.infinity`).
- `List<SketchStroke> eraseStrokesAt(List<SketchStroke> strokes, double x,
  double y, double radius)` — returns `strokes` with every stroke whose
  `distanceToStroke ≤ radius` removed (accounting for half the stroke's own
  width in the threshold). Order preserved; never mutates the input.

### Editor — `lib/features/sketch_editor.dart`

- `enum _SketchTool { pen, eraser }`, default `pen`.
- Toolbar gains a pen/eraser toggle: `sketch-tool-pen` / `sketch-tool-eraser`.
  The palette + width row stay; in eraser mode the width toggle sizes the eraser
  radius (`eraserRadius = max(_width * 1.5, 10)`).
- Pan handlers branch on tool: pen = current freehand capture; eraser =
  `eraseStrokesAt` on pan start + each pan update (live erase as you drag).
- **Undo becomes a history stack.** Today `sketch-undo` is `_strokes.removeLast()`
  — which can't restore an *erased* stroke. Replace with an `_undo` stack of
  `List<SketchStroke>` snapshots: push the prior list before each mutation
  (draw-end, an erase gesture, clear); `sketch-undo` pops and restores; disabled
  when empty. This makes draw, erase, and clear all undoable.

### Tests

- Pure (`sketch_test` or new): `distanceToStroke` segment math; `eraseStrokesAt`
  removes a hit within radius, keeps a miss, is empty-safe, preserves order,
  doesn't mutate input.
- Widget (`sketch_editor_test`): in eraser mode, a drag over an existing stroke
  removes it; `sketch-undo` restores it; pen mode still draws.

## Rollout

Pre-release; no migration. The `SketchData` JSON schema (`v:1`) is unchanged —
the eraser only adds/removes whole strokes, which already round-trip.
