# Sketch shape tools: line, rectangle, ellipse

**Date:** 2026-06-23
**Status:** Shipped

## Problem

The sketch editor supports only freehand pen and eraser. Straight lines,
rectangles, and ellipses are impossible to draw accurately freehand. These
are the three shapes sufficient to annotate maps, box out regions, and mark
up PDF pages.

## Decision

Add three shape tools alongside pen/eraser. No new data model: a shape is a
`SketchStroke` with computed points, so it renders, erases, and exports with
all existing code unchanged.

- **Line** — 2 points (start → end)
- **Rectangle** — 5 closed corner points (start, 3 corners, back to start)
- **Ellipse** — 37-point polyline (steps 0..36 inclusive, ≈10° each)

## Architecture

### `lib/features/sketch_editor.dart`

`_SketchTool` extended: `{ pen, eraser, line, rect, ellipse }`.

State field `_shapeStart: Offset?` holds the anchor when a shape drag is in
progress.

`_shapePoints(Offset start, Offset end) → List<List<double>>` — pure method
that returns the computed points for the active tool (switch on `_tool`).

Pan handler logic:

| event | pen | eraser | shape tool |
|-------|-----|--------|-----------|
| `onPanStart` | begin `_current` | begin erase | save `_shapeStart` |
| `onPanUpdate` | append to `_current` | erase at pos | `_current = _shapePoints(_shapeStart!, pos)` |
| `onPanEnd` | commit stroke | reset flag | commit stroke, clear `_shapeStart` |

Live preview: `_current` is fed into the existing `SketchData` preview in
`build()`, so the shape outline updates on every drag tick — same path as pen.

Three `IconButton`s added after eraser in `_toolbar()`:
- `sketch-tool-line` — `Icons.remove`
- `sketch-tool-rect` — `Icons.crop_square`
- `sketch-tool-ellipse` — `Icons.radio_button_unchecked`

All use the same `isSelected` / `color: Colors.blue` highlight pattern as
existing tools.

## Testing (`test/sketch_editor_test.dart`)

- Parametric test over `['line', 'rect', 'ellipse']`: select tool, drag,
  save → 1 stroke with the expected point count (2 / 5 / 37).
- Shape stroke undo: draw rect, undo → empty on save.

## Files touched

| File | Change |
|------|--------|
| `lib/features/sketch_editor.dart` | `_SketchTool` enum, `_shapeStart`, `_shapePoints`, pan handlers, toolbar buttons |
| `test/sketch_editor_test.dart` | parametric shape test + undo test |
