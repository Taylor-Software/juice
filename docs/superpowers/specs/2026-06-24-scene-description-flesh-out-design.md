# Scene descriptions + flesh-out (extend flesh-out #4 to scenes)

**Date:** 2026-06-24
**Status:** Design — approved

## Problem

Flesh-out (#4) expands NPCs, threads, dungeon rooms, and hex sites, but skipped
**scenes** — the spine of solo play. Adding scenes is a natural extension of the
generic `fleshOut` seam. But scenes have **no description today**: a scene is a
`JournalKind.scene` entry with `title` + `chaosFactor` and an always-empty
`body` that is rendered nowhere (the journal shows a title+chaos divider; the
scenes pane shows title+chaos). So "flesh out a scene" needs three things: a
**visible** scene description, a way to **write** one without AI (so flesh-out's
"build on existing notes" has something to build on), and the AI **append**.

## Decisions (from brainstorming)

- Give scenes a real, visible **description** (the `body` field, rendered when
  non-empty) — AI-independent.
- A **manual edit** (title + description) so anyone can write/curate a scene
  description.
- A **flesh-out** entry point that AI-appends to the description, mirroring #4's
  room/hex (review dialog → append).
- DRY: the Append/Cancel review dialog is now shared by 3 surfaces, so extract
  it.

## Architecture

### 1. Shared review dialog — `lib/features/flesh_out_review.dart` (new)

Move the existing top-level `Future<bool> showFleshOutReview(BuildContext,
String generated)` out of `map_screen.dart` into this new file (verbatim — the
`flesh-out-review` / `flesh-out-append` keys unchanged). `map_screen.dart`
imports it; `scenes_pane.dart` imports it. No behavior change (the existing
room/hex flesh-out tests still pass).

### 2. Visible scene body

- **Journal feed** (`journal_screen.dart`, the `JournalKind.scene` case): keep
  the title+chaos divider `Row`, but wrap it in a `Column` and, when
  `e.body.trim().isNotEmpty`, render the description below it
  (`Key('scene-body-${e.id}')`, `bodyMedium`, padded).
- **Scenes pane** (`scenes_pane.dart` row): the `ListTile` subtitle shows the
  chaos line and the description (when present), joined by a newline.

### 3. Manual edit — `scenes_pane.dart`

A per-row `scene-edit-${s.id}` `IconButton` → `_editScene(context, ref, s)` opens
a `_SceneEditDialog` (a small `StatefulWidget`: a title `TextField`
`scene-edit-title` + a multiline description `TextField` `scene-edit-body` + a
`scene-edit-save` button, returning `({String title, String body})`). On save
(non-empty title) → `journalProvider.replace(s.copyWith(title:, body:))`.

### 4. Flesh-out scene — `scenes_pane.dart`

A per-row aiReady-gated `flesh-out-scene-${s.id}` `IconButton` →
`_fleshOutScene(context, ref, s)`:

```dart
final seed = buildFleshOutSeed(ref,
    entityKind: 'scene', name: s.title, existingDetail: s.body);
final String detail;
try {
  detail = await ref.read(interpreterServiceProvider).fleshOut(seed);
} catch (e) {
  if (context.mounted) { /* "Flesh out failed: $e" SnackBar */ }
  return;
}
if (!context.mounted) return;
if (await showFleshOutReview(context, detail) != true) return;
final body = [s.body, detail].where((t) => t.trim().isNotEmpty).join('\n\n');
await ref.read(journalProvider.notifier).replace(s.copyWith(body: body));
```

`buildFleshOutSeed` is already imported by `scenes_pane.dart` (via
`play_context.dart`); add imports for `interpreterServiceProvider`
(`state/interpreter.dart`) and `showFleshOutReview` (the new file).
`aiReadyProvider` is already reachable (`providers.dart`).

The trailing `Row` holds the edit button then (when aiReady) the flesh-out
button; the existing row `onTap` (navigate to the journal) is unchanged.

## Testing

- `scenes_pane` widget test (fake interpreter): with AI ready, tapping
  `flesh-out-scene-<id>` then `flesh-out-append` appends the generated detail to
  the scene's `body` (persisted via `journalProvider`); the button is **absent
  when AI is not ready**.
- Manual edit: tapping `scene-edit-<id>`, changing the description, saving →
  `body` persisted and shown in the row subtitle.
- Journal render: a scene entry with a non-empty `body` shows `scene-body-<id>`;
  an empty-body scene does not.
- The extracted `showFleshOutReview` is covered by the existing room/hex
  flesh-out tests (unchanged keys); no new test for the move.

## Out of scope (YAGNI)

- A scene-body field in the new-scene dialog (edit-after-create covers it); rich
  text / formatting; regenerate/variants; flesh-out from the journal scene
  divider or the HUD; reordering scenes; per-scene tags.

## Files touched

| File | Change |
|------|--------|
| `lib/features/flesh_out_review.dart` | NEW — `showFleshOutReview` (moved from map_screen) |
| `lib/features/map_screen.dart` | remove the local `showFleshOutReview`; import the new file |
| `lib/features/journal_screen.dart` | render the scene `body` under the scene divider |
| `lib/features/scenes_pane.dart` | body in subtitle + `_SceneEditDialog` + `_editScene` + `_fleshOutScene` + the two per-row buttons |
| tests | `scenes_pane` flesh-out + edit + render widget tests |
