# PDF Annotation + Blob Store — Epic Design

Successor to `2026-06-19-sketch-v2-pdf-annotation-design.md` (which decided to
keep the custom drawing engine). This designs the storage + feature work to
annotate **user-imported PDFs** and **user images / maps / handouts**, and to
keep a user **PDF library**.

## Why a new storage rail

Today all state is in **SharedPreferences** (key→string), backed by Android
SharedPreferences / iOS NSUserDefaults / **web localStorage (~5–10 MB per
origin)**. That cannot hold multi-MB PDFs, let alone a *library* of them, and
base64'ing blobs into the campaign-export JSON bloats exports. Keeping original
PDFs and a library both require a real **binary asset store**, separate from
prefs.

## Decisions (owner, 2026-06-19)

- **Persistence:** keep the **original PDF bytes** + a page reference (not just a
  flattened page image), so the library holds real PDFs and pages re-render live.
- **PDF library:** a user-managed library of imported PDFs is an explicit goal.
- **Web:** **defer.** B0 targets mobile/desktop (file store); web reports the
  library/annotation as unavailable (mirrors the on-device LLM already being
  disabled on web). IndexedDB web store is a later add.
- **Export:** **bundle blobs** into the campaign export → the export becomes a
  **zip container** (JSON manifest + a `blobs/` dir), not a plain `.json`.

## Architecture

```
SharedPreferences  → small structured state (unchanged): journal, sessions,
                     context, library index, annotation entries (metadata + ids)
BlobStore (NEW)    → binary assets by id: imported PDFs, (later) cached page PNGs
                     mobile/desktop: files under app documents dir (path_provider)
                     web: unavailable (throws/guarded) for now
Campaign export    → zip: manifest.json (today's per-key JSON) + blobs/<id>
```

Heavy bytes live in the BlobStore keyed by an opaque id; prefs/journal hold only
that id + metadata. New deps across the epic: `path_provider` (B0),
`archive` (export zip), `pdfrx` (B2) — each a real, committed need.

## Decomposition

- **B0 — BlobStore rail (this spec details; build first).**
- **B0b — Export-as-zip** (bundle blobs). Lands with/after the first blob
  producer (B1) so there are blobs to bundle.
- **B1 — Image-background annotation.** Generalize `SketchEditor` to an optional
  `ui.Image` background; import an image → store via BlobStore → annotate →
  persist an annotation entry (blob id + strokes). Ships maps/handouts.
- **B2 — PDF library + annotation.** `pdfrx`; import PDFs → BlobStore; library
  browser; pick page → `PdfPage.render` → page image as the editor background →
  annotate; the annotation entry references `{pdfBlobId, pageIndex}` + strokes.

## B0 — BlobStore (build now)

### Seam — `lib/state/blob_store.dart`

Abstract interface (mirrors the `InterpreterService` seam so tests use a fake,
never touching the disk):

```dart
abstract class BlobStore {
  /// Persist [bytes], returns the new blob id (content-addressed or uuid-ish).
  Future<String> put(List<int> bytes, {String? ext});
  Future<Uint8List?> get(String id);     // null if missing
  Future<void> delete(String id);
  Future<List<String>> list();           // all blob ids (for export + GC)
  Future<bool> exists(String id);
}
```

- `FileBlobStore` (mobile/desktop): writes `<appDocs>/blobs/<id>` via
  `path_provider`'s `getApplicationDocumentsDirectory`. Id = a pure
  `blobId(bytes)` (sha-like over length+sampled bytes, or a counter+timestamp
  passed in — note: `Date.now`/random are fine in app code, only workflow
  scripts forbid them). Keep id generation in a **pure, tested** helper.
- `UnavailableBlobStore` (web for now): every method throws
  `UnsupportedError('Blob store unavailable on web')`; callers gate on a
  capability flag so web hides the import/library affordances.
- `blobStoreProvider` selects by platform (`kIsWeb` → unavailable), overridable
  in tests with an in-memory fake.

### Pure core (tested without IO)

- `blobId(List<int> bytes)` — deterministic id from content (so re-importing the
  same file dedupes). Pure, unit-tested.
- An `InMemoryBlobStore` test fake implementing `BlobStore` over a `Map` — used
  by all widget/integration tests (the rootBundle/disk-hang rule: never hit real
  IO in tests).

### What B0 does NOT do

No UI, no export change, no pdfrx. Just the seam + file impl + fake + provider +
pure id helper. First consumer is B1.

## Testing (B0)

- `blobId` deterministic + collision-resistant on differing bytes (pure).
- `InMemoryBlobStore`: put→get round-trip, get-missing→null, delete, list,
  exists, dedupe (same bytes → same id, single stored copy).
- `FileBlobStore` is thin over `dart:io` + `path_provider`; covered by the shared
  `BlobStore` contract test run against the in-memory fake (the file impl is
  exercised manually / in integration, not unit — no disk in unit tests).

## Rollout

Pre-release; no migration. Web users keep everything except the (new) library /
annotation affordances, which are hidden when `blobStoreProvider` is the
unavailable impl. Export stays plain JSON until B0b.
