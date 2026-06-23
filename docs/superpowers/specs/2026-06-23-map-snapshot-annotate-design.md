# Map snapshot → journal annotation

**Date:** 2026-06-23
**Status:** Design — approved

## Problem

The journal annotates imported images and PDF pages (sketch over an
image-background blob: `composer-annotate-image` / `composer-annotate-pdf`).
The app's own **maps** (the World hex map and the Dungeon room map) can't be
captured into that flow — to mark up a map you'd have to screenshot it
externally and re-import. Players want to snapshot a map and annotate it in
the journal directly.

## Scope (from brainstorming)

- **Two maps have a paint canvas:** World (`HexMapPane`) and Dungeon
  (`DungeonMapPane`), both `CustomPaint`. The Verdant and Hexcrawl panes are
  roll-table/journey forms with **no map of their own** — Verdant drives the
  shared World map (`mapProvider`), so a Verdant player annotates the World
  snapshot. Scope is World + Dungeon.
- **Static snapshot**, not a live-map overlay: the captured map raster becomes
  a sketch background (re-editable strokes/shapes/text over a frozen image).
  A live overlay (strokes pinned to hexes, redrawn as the map mutates) was the
  rejected alternative.
- **Full map, not the viewport:** capturing the `CustomPaint`'s boundary yields
  the whole map at its natural `SizedBox` size, regardless of the
  `InteractiveViewer`'s current zoom/pan.

## Architecture

**No model change.** A map snapshot is an ordinary image-background `SketchData`
(`backgroundBlobId` → a PNG blob). We add only a new *source* for that PNG: a
captured map render instead of a picked file. The save path, export bundling,
re-edit, and thumbnail all reuse the existing sketch-image-background machinery.

### 1. Shared utility — `lib/features/map_snapshot.dart` (new)

```dart
/// Captures [key]'s RenderRepaintBoundary as PNG bytes (the full painted area
/// at [pixelRatio]). Null when the boundary isn't mounted/painted yet.
Future<Uint8List?> captureBoundaryPng(GlobalKey key,
    {double pixelRatio = 2.0}) async {
  final obj = key.currentContext?.findRenderObject();
  if (obj is! RenderRepaintBoundary) return null;
  final image = await obj.toImage(pixelRatio: pixelRatio);
  try {
    final bd = await image.toByteData(format: ui.ImageByteFormat.png);
    return bd?.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// Snapshots the map under [boundaryKey] into a new journal sketch the player
/// can annotate. No-op when the blob store is unavailable (web). Mirrors the
/// tail of journal_screen `_annotatePdf`.
Future<void> snapshotMapToJournal(
    BuildContext context, WidgetRef ref, GlobalKey boundaryKey) async {
  if (!ref.read(blobStoreAvailableProvider)) return;
  final png = await captureBoundaryPng(boundaryKey);
  if (png == null) {
    if (context.mounted) _snack(context, 'Could not capture the map.');
    return;
  }
  final bgBlobId = await ref.read(blobStoreProvider).put(png, ext: 'png');
  final bg = await decodeSketchBackground(png);
  try {
    if (!context.mounted) return;
    final data = await showSketchEditor(context,
        background: bg, backgroundBlobId: bgBlobId);
    if (data != null && !data.isEmpty) {
      await ref.read(journalProvider.notifier).addSketch(data);
      if (context.mounted) _snack(context, 'Saved to journal.');
    }
  } finally {
    bg?.dispose();
  }
}
```

(`_snack` is a tiny local `ScaffoldMessenger` helper. `addSketch(SketchData)`,
`showSketchEditor`, `decodeSketchBackground`, `blobStoreProvider`,
`blobStoreAvailableProvider` are all existing identifiers.)

### 2. Per-pane wiring — `lib/features/map_screen.dart`

For **both** `HexMapPane` (World) and `DungeonMapPane` (Dungeon):

- Add a `final GlobalKey _snapKey = GlobalKey();` field to the State.
- Wrap the pane's `CustomPaint` (the one keyed `hex-canvas` / `dungeon-canvas`,
  inside its `SizedBox` under the `InteractiveViewer`) in
  `RepaintBoundary(key: _snapKey, child: CustomPaint(...))`.
- In the pane's `_controls` `Row`, add an `IconButton` (key `map-snapshot` for
  World, `dungeon-snapshot` for Dungeon; icon `Icons.draw_outlined`, tooltip
  "Annotate in journal"), rendered only when
  `ref.watch(blobStoreAvailableProvider)` (hidden on web). On press →
  `snapshotMapToJournal(context, ref, _snapKey)`.

A `RepaintBoundary` around the `CustomPaint` is cheap (the map is already its
own paint layer) and isolates the capture to the map, excluding the toolbar.

### 3. Result

A journal `JournalKind.sketch` entry whose `backgroundBlobId` is the map raster
— re-editable via the existing sketch-thumb tap, exported in the `.juice.zip`
bundle by the existing `referencedBlobIds` scan (it already collects
`backgroundBlobId`). Desktop/mobile only (web hides the button + has no blob
store), matching image/PDF annotation.

## Testing

- `map_snapshot_test` (widget): pump a `RepaintBoundary(key:k, child: a colored
  SizedBox)`, then `await tester.runAsync(() => captureBoundaryPng(k))` →
  non-null PNG bytes whose header is the PNG magic (`\x89PNG`). A missing/unkeyed
  boundary → null.
- Per-pane button gating (widget, best-effort): with `blobStoreAvailableProvider`
  overridden true, the `map-snapshot` / `dungeon-snapshot` button is present;
  overridden false (web), absent. Only if the pane pumps cleanly with map +
  oracle provider overrides; if it pulls asset data and hangs, this gating is
  asserted at the call-site/registry level instead and the button is
  **device-verified**.
- The full capture → blob → sketch-editor route → `addSketch` orchestration is
  **device-verified** (the sketch editor is a pushed modal route; `toImage`
  needs a real painted layer), consistent with how `PdfrxRasterizer` is
  device-verified rather than unit-tested.

## Out of scope (YAGNI)

- Live-map annotation overlay (strokes pinned to map coordinates); Verdant /
  Hexcrawl (no canvas); capturing only the visible viewport; a `mapBlobId`
  provenance field on `SketchData`; a composer-side "insert a map" button;
  re-snapshot/refresh of an existing map annotation.

## Files touched

| File | Change |
|------|--------|
| `lib/features/map_snapshot.dart` | new: `captureBoundaryPng`, `snapshotMapToJournal` |
| `lib/features/map_screen.dart` | `RepaintBoundary` + snapshot button on `HexMapPane` and `DungeonMapPane` |
| tests | `map_snapshot_test` (capture primitive); best-effort pane button-gating |
