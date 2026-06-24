# AI seams respect the pinned active scene

**Date:** 2026-06-24
**Status:** Design — approved

## Problem

The PlayContext spine has an `activeSceneId` pointer — the scene the player has
explicitly pinned (set on scene creation; the campaign HUD's scene line follows
it, falling back to the newest scene entry). But the **AI seams ignore it**: they
all derive "the current scene" as the *newest* `JournalKind.scene` entry:
`_sceneContext()` (narrate / interpret / voice), `fleshOutSeedFrom` (flesh-out),
and the assistant rail (ranked chips). So when the player pins an earlier scene,
the HUD shows it but the AI grounds on a different (newer) scene — an
inconsistency flagged during the #5 (ranked) and #149 (scene flesh-out) reviews.

This unifies all scene resolution behind one shared resolver so every seam
honors the pin.

## Architecture

### 1. Shared resolver — `lib/state/play_context.dart`

Extract the HUD's logic (currently inlined in `play_context_hud.dart`) into a
pure function:

```dart
/// The campaign's current scene: the spine's pinned [activeSceneId] when set
/// and present, else the newest scene entry (journal is newest-first), else
/// null. The single source of truth for "which scene" across the HUD + AI seams.
JournalEntry? activeSceneEntry(List<JournalEntry> journal, String? activeSceneId) {
  final scenes = journal.where((e) => e.kind == JournalKind.scene);
  return (activeSceneId == null
          ? null
          : scenes.where((e) => e.id == activeSceneId).firstOrNull) ??
      scenes.firstOrNull;
}
```

### 2. Apply at the four scene-derivation sites

- **HUD** (`play_context_hud.dart`): replace the inline `sceneEntries … firstOrNull`
  block (lines ~41-46) with `final scene = activeSceneEntry(entries,
  ref.watch(playContextProvider).valueOrNull?.activeSceneId);`. Behavior-identical
  (it *is* the source) — pure DRY.

- **`_sceneContext()`** (`journal_screen.dart`): currently returns the first
  (newest) scene's `Scene: <title> (Chaos N)`. Resolve via the resolver instead:

  ```dart
  String _sceneContext() {
    final journal = ref.read(journalProvider).valueOrNull ?? const [];
    final scene = activeSceneEntry(
        journal, ref.read(playContextProvider).valueOrNull?.activeSceneId);
    if (scene == null) return '';
    final chaos =
        scene.chaosFactor != null ? ' (Chaos ${scene.chaosFactor})' : '';
    return 'Scene: ${scene.title}$chaos';
  }
  ```

  This fixes **narrate**, **interpret**, and **voice** (all feed `_sceneContext()`).

- **`fleshOutSeedFrom` / `buildFleshOutSeed`** (`play_context.dart`): add an
  optional `String? activeSceneId` to `fleshOutSeedFrom`; derive `sceneTitle`
  from `activeSceneEntry(journal, activeSceneId)` (its title, when non-empty)
  instead of the newest-scene walk. `buildFleshOutSeed` passes
  `ref.read(playContextProvider).valueOrNull?.activeSceneId`. Fixes **flesh-out**
  (character / thread / room / hex; scene flesh-out is unaffected — the scene is
  the entity, and its own id stays excluded via `excludeId`).

- **`assistant_rail`** (`_signature` + `_maybeRank`): both currently use
  `journal.where(scene).firstOrNull`. Resolve via `activeSceneEntry(journal,
  activeSceneId)` (read `playContextProvider.activeSceneId` in `build` and thread
  it in). Fixes **ranked chips** — the rank signature + grounding now key on the
  pinned scene (so re-pinning re-ranks).

- **Not touched:** `recap`'s "entries since the last scene divider" — a
  session-boundary mechanism that should stay newest-scene regardless of the pin.

## Testing

- `activeSceneEntry` pure unit test: pinned id present → that scene; pin null →
  newest scene; pin id not found → newest scene; no scene entries → null.
- `fleshOutSeedFrom` test (extend): with `activeSceneId` pointing at an *older*
  scene, `sceneTitle` is that older scene's title, not the newest.
- narrate widget test (extend `narrate_test`): seed two scenes + pin the older
  via `playContextProvider` (`setActiveScene`); `fake.lastNarrateSeed.sceneTitle`
  reflects the pinned (older) scene.
- HUD: the existing `campaign_header` test still passes (the resolver is
  behavior-identical to the inlined logic).
- assistant rail: covered by the resolver unit test + the existing rail tests
  (which have one scene, so newest == pinned).

## Out of scope

- Changing `recap` / session-boundary semantics; a reactive "re-pin → re-narrate"
  trigger; surfacing the active scene in more places. This is purely unifying the
  scene **resolution** the seams already do.

## Files touched

| File | Change |
|------|--------|
| `lib/state/play_context.dart` | `activeSceneEntry` resolver; `fleshOutSeedFrom`/`buildFleshOutSeed` use it (+ `activeSceneId`) |
| `lib/shared/play_context_hud.dart` | DRY onto `activeSceneEntry` |
| `lib/features/journal_screen.dart` | `_sceneContext()` resolves via the spine |
| `lib/features/assistant_rail.dart` | `_signature` + `_maybeRank` resolve via the spine |
| tests | `activeSceneEntry` unit; `fleshOutSeedFrom` + `narrate` pinned-scene cases |
