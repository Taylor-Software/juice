# PDF Annotation (pdfrx) — Design (epic B2)

## Goal

Import a PDF, render a chosen page to an image, and annotate it with the
existing sketch engine — completing the PDF-annotation epic. Scope: **user-
imported** PDFs (handouts, the user's own material), never bundled rulebooks.

## Key decisions

- **A PDF-page annotation is a B1 image-background sketch** whose background is a
  rendered page. B2 reuses B1's editor/painter/persistence/thumbnail wholesale;
  the only new work is the import+render step.
- **Cache the rendered raster** (chosen): render the page once to a PNG, store it
  as a blob, and use it as the B1 `backgroundBlobId`. Thumbnails/opens then need
  no pdfrx (fast, and web can *view* PDF annotations). The source PDF blob +
  page index are kept as provenance (`pdfBlobId`/`pdfPage`) for a future
  sharper-re-render feature.
- **Desktop/mobile-first** (chosen): PDF *import* is gated on a
  `pdfAvailableProvider` (false on web initially, like the blob store). Web still
  views imported-PDF annotations via the cached raster. Web PDF import (pdfium
  WASM init) is a later step.

## Dependency

`pdfrx` (MIT; Android/iOS/desktop/web-WASM; `PdfDocument.openData` +
`page.render` → `PdfImage`). Wrapped behind a service seam so tests never touch
native code (mirrors the `InterpreterService` pattern).

## Components

### `PdfRasterizer` — `lib/state/pdf_rasterizer.dart` (new, service seam)

```dart
abstract class PdfRasterizer {
  Future<int> pageCount(Uint8List pdfBytes);
  /// Render [pageIndex] (0-based) to PNG bytes at ~[targetWidth] px wide,
  /// or null on failure / unsupported.
  Future<Uint8List?> renderPage(Uint8List pdfBytes, int pageIndex,
      {int targetWidth = 1500});
}
```

- `PdfrxRasterizer` (real): `PdfDocument.openData(bytes)` → `doc.pages[i]` →
  `page.render(width:.., height:..)` → `PdfImage` → encode to PNG
  (`img.createImage()` → `ui.Image.toByteData(png)`), then `doc.dispose()`.
  This is thin glue; it is the one part not unit-tested (needs native/WASM —
  verified on device, like the Gemma4 templating).
- `FakePdfRasterizer` (tests): returns a canned page count + a tiny PNG.
- Providers: `pdfRasterizerProvider` (real impl) and `pdfAvailableProvider`
  (`!kIsWeb`, AND-ed with `blobStoreAvailableProvider` at call sites).

### `SketchData` provenance — `lib/engine/sketch.dart`

Add `String? pdfBlobId` (JSON `pdf`) + `int? pdfPage` (JSON `pp`). Pure
provenance — rendering still uses `backgroundBlobId` (the cached raster). JSON
round-trips; absent → null. (`isEmpty` unchanged — a PDF annotation always has a
`backgroundBlobId`.)

### Import flow — `lib/features/journal_screen.dart`

A composer button `composer-annotate-pdf`, shown only when
`blobStoreAvailableProvider && pdfAvailableProvider`:
1. Pick a PDF (`file_picker`, `FileType.custom` `['pdf']`, `withData`).
2. Store the PDF bytes as a blob → `pdfBlobId`.
3. `pageCount`; if > 1, a simple page-picker dialog (`pdf-page-<n>`), default 0.
4. `renderPage(bytes, page)` → PNG; if null, snackbar + abort.
5. Store the PNG as a blob → `backgroundBlobId`; decode to `ui.Image`.
6. `showSketchEditor(background:, backgroundBlobId:, pdfBlobId:, pdfPage:)` →
   on save, `addSketch` persists a sketch carrying all three.

`SketchEditor`/`showSketchEditor` gain `pdfBlobId`/`pdfPage` params, carried
into the saved `SketchData` (like `backgroundBlobId`); `_openSketch` threads them
back through on re-edit.

### Export bundling — `lib/state/campaign_bundle.dart`

`referencedBlobIds` also collects `payload.sketch.pdf`, so the source PDF blob is
bundled alongside the cached raster on export (B0b zip).

## Data flow

Import PDF → store PDF blob (`pdfBlobId`) → render page → store raster blob
(`backgroundBlobId`) → B1 editor → `SketchData{backgroundBlobId, pdfBlobId,
pdfPage, strokes}`. Open/thumbnail → B1 resolves `backgroundBlobId` (no pdfrx).
Export → bundles both blobs.

## Error / edge handling

- Render failure / unsupported PDF → null → snackbar, no entry; the stored PDF
  blob is an orphan (same GC-deferred story as B0b).
- Web: import button hidden (`pdfAvailable` false); existing PDF annotations
  still render from the cached raster.
- A multi-dot or no-ext blob id round-trips via the existing `blobExtFromId`.

## Testing

- `SketchData` round-trips `pdfBlobId`/`pdfPage`.
- `referencedBlobIds` includes the `pdf` blob.
- Import flow with `FakePdfRasterizer` (provider override): render → raster blob
  stored → sketch carries `backgroundBlobId` + `pdfBlobId` + `pdfPage`.
- `PdfrxRasterizer` real render: device-verified only (native/WASM), not unit-
  tested — noted in the PR.

## Rollout

Pre-release; no migration. New `SketchData` fields are additive + tolerant.
