# Map Snapshot → Journal Annotation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Snapshot the World and Dungeon maps into the journal as annotatable image-background sketches.

**Architecture:** A new `map_snapshot.dart` captures a `RepaintBoundary` to PNG and feeds it into the existing sketch-image-background flow (blob → sketch editor → `addSketch`) — the exact tail of `_annotatePdf`. The World (`HexMapPane`) and Dungeon (`DungeonMapPane`) panes wrap their `CustomPaint` in a `RepaintBoundary` and add a web-gated snapshot button. No model change.

**Tech Stack:** Dart, Flutter (`RenderRepaintBoundary.toImage`), flutter_riverpod, flutter_test. Reuses `BlobStore`, `showSketchEditor`/`decodeSketchBackground`, `JournalNotifier.addSketch`.

---

## File Structure

- **Create** `lib/features/map_snapshot.dart` — `captureBoundaryPng` + `snapshotMapToJournal`.
- **Modify** `lib/features/map_screen.dart` — `RepaintBoundary` + snapshot button on `HexMapPane` (World) and `DungeonMapPane` (Dungeon).
- **Create** `test/map_snapshot_test.dart` — capture-primitive widget tests.

---

## Task 1: Snapshot utility

**Files:**
- Create: `lib/features/map_snapshot.dart`
- Test: `test/map_snapshot_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/map_snapshot_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/features/map_snapshot.dart';

void main() {
  testWidgets('captureBoundaryPng returns PNG bytes for a painted boundary',
      (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: RepaintBoundary(
            key: key,
            child: Container(
                width: 40, height: 40, color: const Color(0xFFFF0000)),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    Uint8List? png;
    await tester.runAsync(() async {
      png = await captureBoundaryPng(key);
    });
    expect(png, isNotNull);
    // PNG magic header: 0x89 'P' 'N' 'G'.
    expect(png!.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
  });

  testWidgets('captureBoundaryPng returns null for an unmounted key',
      (tester) async {
    final key = GlobalKey();
    Uint8List? png = Uint8List(0);
    await tester.runAsync(() async {
      png = await captureBoundaryPng(key);
    });
    expect(png, isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/map_snapshot_test.dart`
Expected: FAIL — `map_snapshot.dart` / `captureBoundaryPng` not defined.

- [ ] **Step 3: Implement**

Create `lib/features/map_snapshot.dart`:

```dart
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/blob_store.dart';
import '../state/providers.dart';
import 'sketch_editor.dart';

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

void _snack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/map_snapshot_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/map_snapshot.dart test/map_snapshot_test.dart
git commit -m "feat(maps): captureBoundaryPng + snapshotMapToJournal utility

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 2: World map (HexMapPane) snapshot button

**Files:**
- Modify: `lib/features/map_screen.dart`

(No new unit test — pane wiring is device-verified per the spec; analyze + the existing map tests are the gate.)

- [ ] **Step 1: Add the import + snapshot key**

At the top of `lib/features/map_screen.dart`, add beside the other `package`/relative imports:

```dart
import 'map_snapshot.dart';
```

In `HexMapPaneState` (the `State` for `HexMapPane`, class around line 610), add a field near the top of the state class:

```dart
  final GlobalKey _hexSnapKey = GlobalKey();
```

- [ ] **Step 2: Wrap the hex CustomPaint in a RepaintBoundary**

Find the `CustomPaint(key: const Key('hex-canvas'), ...)` (around line 853, it is the `child:` of a `GestureDetector`). Wrap it:

Change:

```dart
          child: CustomPaint(
            key: const Key('hex-canvas'),
```

to:

```dart
          child: RepaintBoundary(
            key: _hexSnapKey,
            child: CustomPaint(
              key: const Key('hex-canvas'),
```

Then add ONE extra closing `)` after that `CustomPaint`'s closing `)` (the `CustomPaint(...)` currently ends with `),` as the `GestureDetector`'s `child`; it becomes `RepaintBoundary(child: CustomPaint(...))`). Run `flutter analyze` after — it flags an unbalanced paren immediately. The dart-format hook will re-indent the now-nested `CustomPaint`.

- [ ] **Step 3: Add the snapshot button to `_controls`**

In `HexMapPane`'s `_controls` `Row` (around line 768), add this `IconButton` immediately after the `hex-journal` `IconButton` (before `hex-reset`):

```dart
          if (ref.watch(blobStoreAvailableProvider))
            IconButton(
              key: const Key('map-snapshot'),
              icon: const Icon(Icons.draw_outlined),
              tooltip: 'Annotate in journal',
              onPressed: () => snapshotMapToJournal(context, ref, _hexSnapKey),
            ),
```

- [ ] **Step 4: Verify**

Run: `flutter analyze` → expect `No issues found!` (catches an unbalanced RepaintBoundary paren).
Run: `flutter test test/map_screen_test.dart` (if present) and `flutter test test/home_shell_test.dart` → expect pass (no regression to the map pane).

- [ ] **Step 5: Commit**

```bash
git add lib/features/map_screen.dart
git commit -m "feat(maps): snapshot+annotate button on the World hex map

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 3: Dungeon map (DungeonMapPane) snapshot button

**Files:**
- Modify: `lib/features/map_screen.dart`

- [ ] **Step 1: Add the snapshot key**

In `DungeonMapPaneState` (the `State` for `DungeonMapPane`, class around line 109), add:

```dart
  final GlobalKey _dungeonSnapKey = GlobalKey();
```

(The `import 'map_snapshot.dart';` was added in Task 2.)

- [ ] **Step 2: Wrap the dungeon CustomPaint in a RepaintBoundary**

Change:

```dart
          child: CustomPaint(
            key: const Key('dungeon-canvas'),
            size: Size(width, height),
            painter: _DungeonPainter(
              rooms: s.rooms,
              corridors: s.corridors,
              currentRoomId: s.currentRoomId,
              scheme: scheme,
              encounterRoomId:
                  ref.watch(encounterProvider).valueOrNull?.locationRef?.roomId,
            ),
          ),
```

to:

```dart
          child: RepaintBoundary(
            key: _dungeonSnapKey,
            child: CustomPaint(
              key: const Key('dungeon-canvas'),
              size: Size(width, height),
              painter: _DungeonPainter(
                rooms: s.rooms,
                corridors: s.corridors,
                currentRoomId: s.currentRoomId,
                scheme: scheme,
                encounterRoomId: ref
                    .watch(encounterProvider)
                    .valueOrNull
                    ?.locationRef
                    ?.roomId,
              ),
            ),
          ),
```

- [ ] **Step 3: Add the snapshot button to `_controls`**

In `DungeonMapPane`'s `_controls` `Row` (around line 162), add immediately after the `dungeon-journal` `IconButton` (before `dungeon-reset`):

```dart
          if (ref.watch(blobStoreAvailableProvider))
            IconButton(
              key: const Key('dungeon-snapshot'),
              icon: const Icon(Icons.draw_outlined),
              tooltip: 'Annotate in journal',
              onPressed: () =>
                  snapshotMapToJournal(context, ref, _dungeonSnapKey),
            ),
```

- [ ] **Step 4: Run analyze + full suite**

Run: `flutter analyze` → expect `No issues found!`
Run: `flutter test` → expect All tests passed.

- [ ] **Step 5: Commit**

```bash
git add lib/features/map_screen.dart
git commit -m "feat(maps): snapshot+annotate button on the Dungeon map

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 4: Doc sync — CLAUDE.md

**Files:**
- Modify: `CLAUDE.md` (the generic-hexcrawl / map note, or the journal-sketch bullet)

- [ ] **Step 1: Add a sentence to the journal-sketch bullet**

In `CLAUDE.md`, find the journal-sketch bullet (the one describing
`composer-annotate-image` / `composer-annotate-pdf`). Append a sentence noting
the map-snapshot path. After the PDF-annotation sentence (the one ending with
the pdfrx design-doc reference), add:

```
  **Map snapshot → annotate:** the World (`HexMapPane`) and Dungeon
  (`DungeonMapPane`) panes wrap their `CustomPaint` in a `RepaintBoundary` and
  show a web-gated `map-snapshot`/`dungeon-snapshot` button that rasterizes the
  full map to PNG (`captureBoundaryPng`) and opens it as a sketch-image-bg
  annotation (`snapshotMapToJournal` in `lib/features/map_snapshot.dart`, the
  shared tail of `_annotatePdf`). No model change — a map snapshot is an ordinary
  `backgroundBlobId` sketch. See
  `docs/superpowers/specs/2026-06-23-map-snapshot-annotate-design.md`.
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: note map snapshot → journal annotation in CLAUDE.md

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:**
- §1 `captureBoundaryPng` + `snapshotMapToJournal` → Task 1. ✓
- §2 RepaintBoundary + button on World → Task 2; on Dungeon → Task 3. ✓
- §3 result (image-bg sketch, no model change) → inherent (reuses `addSketch`). ✓
- Testing: capture primitive (Task 1); pane buttons device-verified (Tasks 2/3 rely on analyze + existing map tests). ✓
- Out-of-scope items absent. ✓

**Type consistency:**
- `captureBoundaryPng(GlobalKey, {double pixelRatio}) -> Future<Uint8List?>` defined Task 1, used by `snapshotMapToJournal`. ✓
- `snapshotMapToJournal(BuildContext, WidgetRef, GlobalKey)` defined Task 1, called in Tasks 2/3 with `_hexSnapKey`/`_dungeonSnapKey`. ✓
- Keys `map-snapshot` / `dungeon-snapshot` distinct; `_hexSnapKey` / `_dungeonSnapKey` per-pane fields. ✓
- Reused identifiers (`blobStoreAvailableProvider`, `blobStoreProvider.put`, `decodeSketchBackground`, `showSketchEditor`, `journalProvider…addSketch`) verified to exist. ✓

**Placeholder scan:** No TBD/TODO; complete code in each step. The RepaintBoundary wrap (Tasks 2/3) is the one brace-sensitive edit — `flutter analyze` is the hard gate and is run before each commit. ✓

**Risk note:** `ref.watch(blobStoreAvailableProvider)` inside `_controls` (a build-helper) is valid — `_controls` runs during `build`, so the watch registers normally; the State is a `ConsumerState`, so `ref` is in scope. `blobStoreAvailableProvider` is a plain `Provider<bool>` (`!kIsWeb`), constant per platform, so it never rebuilds spuriously.
