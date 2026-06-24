# Sketch pan-zoom (hand tool)

**Date:** 2026-06-24
**Status:** Design — approved

## Problem

The sketch editor (freehand + image / PDF / map-snapshot annotation) draws on a
fixed, unzoomable canvas. You can't zoom in to annotate fine detail on a large
PDF page or a map snapshot — a real gap in the shipped annotation epic. This
adds pan + zoom via a "hand" tool, cross-platform (mouse + touch).

## Decisions (from brainstorming)

- **Hand tool** model (not two-finger): a `pan` tool joins pen/eraser/shape/text.
  When active, drag pans + pinch/scroll zooms; switch to a draw tool to draw on
  the zoomed view. Consistent with the editor's existing tool-switched gestures;
  works with a mouse and with touch.
- **View-only**: zoom/pan is ephemeral editor state, not persisted in the
  sketch. No model / export change.
- Zoom **persists across tool switches**; a reset button refits.

## Architecture

All changes are in `lib/features/sketch_editor.dart` (the `_SketchEditorState`).

### 1. The pan tool + transform

- `enum _SketchTool { pen, eraser, line, rect, ellipse, text, pan }` (add `pan`).
- State: `final TransformationController _tc = TransformationController();`
  (disposed in `dispose`).
- In `_canvasArea`, wrap the existing canvas `GestureDetector` in an
  `InteractiveViewer`:

```dart
InteractiveViewer(
  transformationController: _tc,
  panEnabled: _tool == _SketchTool.pan,
  scaleEnabled: _tool == _SketchTool.pan,
  minScale: 1.0,
  maxScale: 6.0,
  child: GestureDetector(/* … existing draw handlers … */),
)
```

The `LayoutBuilder` (which sets `_canvas` to the viewport size) stays outside, and
the `Center`/`AspectRatio` background wrapping is unchanged — `InteractiveViewer`
sits between them and the `GestureDetector`.

When the pan tool is active, `InteractiveViewer` intercepts the drag/pinch; when
a draw tool is active, `panEnabled`/`scaleEnabled` are false so it passes pointer
events through to the `GestureDetector` (drawing works as today, on the
zoomed/panned view).

### 2. Coordinate un-transform

Strokes/erase/shape/text points must be stored in **canvas (scene)** coordinates,
not viewport coordinates, so they land correctly when zoomed/panned. A helper:

```dart
Offset _scene(Offset viewport) => _tc.toScene(viewport);
```

Apply it at every gesture entry point in `_canvasArea` (replacing the raw
`d.localPosition` uses): the pen point (`_xy(_scene(d.localPosition))`), the
eraser (`_eraseAt(_scene(d.localPosition))`), the shape start/drag
(`_shapeStart = _scene(...)`, `_shapePoints(_shapeStart!, _scene(...))`), and the
text tap (`_handleTextTap(_scene(d.localPosition))`). At scale 1 / no pan,
`toScene` is the identity, so existing behavior is preserved exactly.

### 3. Disable drawing in pan mode

The draw handlers are currently gated `_tool == text ? null : (handler)`. Extend
the gate so the pan tool also disables them (belt-and-suspenders alongside
`InteractiveViewer` capturing the gesture): `onPanStart/Update/End` become
`(_tool == _SketchTool.text || _tool == _SketchTool.pan) ? null : (handler)`.
`onTapUp` stays text-only.

### 4. Toolbar + reset

- A `sketch-tool-pan` `IconButton` (hand icon, `Icons.pan_tool_outlined`) in the
  toolbar tool row, `isSelected: _tool == _SketchTool.pan`, selecting the tool.
- A `sketch-zoom-reset` `IconButton` (`Icons.zoom_out_map`) in the app-bar
  actions (beside undo/clear) → `setState(() => _tc.value = Matrix4.identity())`.

Pan-zoom never calls `_snapshot()` — it's not on the undo stack.

## Testing

- Widget test (existing harness): selecting `sketch-tool-pan` flips the
  `InteractiveViewer`'s `panEnabled` + `scaleEnabled` to true; selecting
  `sketch-tool-pen` flips them back to false.
- Widget test: setting the `InteractiveViewer.transformationController.value` to a
  scaled matrix, then tapping `sketch-zoom-reset`, restores `Matrix4.identity()`.
- The actual draw-while-zoomed coordinate mapping (gesture-driven) is
  **device-verified**, consistent with the editor's existing device-verified
  gesture code (per CLAUDE.md, the editor route is device-verified).

## Out of scope (YAGNI)

- Persisting zoom/pan in the sketch; a minimap; rotate; two-finger-while-drawing
  zoom (the hand tool covers it); fit-to-content (reset goes to 1:1); per-surface
  default zoom; zoom on the read-only inline thumbnail.

## Files touched

| File | Change |
|------|--------|
| `lib/features/sketch_editor.dart` | `_SketchTool.pan`, `TransformationController`, `InteractiveViewer` wrap, `_scene` un-transform at every gesture, pan-mode draw gate, pan tool button, reset-zoom button |
| `test/sketch_editor_test.dart` | pan-tool panEnabled flip + reset-zoom widget tests |
