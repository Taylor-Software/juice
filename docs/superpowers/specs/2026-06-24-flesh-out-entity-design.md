# AI expansion #4: Flesh out an entity

**Date:** 2026-06-24
**Status:** Design — approved

## Problem

A solo player accretes thin entities — an NPC that's just a name, a one-line
plot thread, a freshly-mapped room or hex site. The richest GM move is "tell me
more about this": expand the stub into concrete, consistent detail. This adds a
one-tap **flesh out** affordance across the app's entity surfaces, on the #1
richer-context foundation, as the fourth AI affordance (after interpret / voice
/ recap / askGm / gmChat / narrate).

## Decisions (from brainstorming)

- **One generic seam**, four thin entry points: roster **character**, **thread**,
  dungeon **room**, world **hex site** (full "characters + locations + threads"
  scope; locations = both map surfaces).
- Output lands by **appending** generated detail to the entity's existing
  free-text field, always **after a review step** (no silent writes):
  - character + thread → the existing name/note **edit dialog**, pre-appended.
  - room + hex → a lightweight **Append / Cancel** review dialog.
- Every entry point is **aiReady-gated** (hidden when AI off / not downloaded).

## Architecture

### 1. Seam — `oracle_interpreter.dart` + `interpreter.dart`

```dart
class FleshOutSeed {
  const FleshOutSeed({
    required this.entityKind,   // human label: 'NPC' | 'story thread' | 'location'
    required this.name,
    this.existingDetail = '',
    this.systemPrimer = '',
    this.sceneTitle,
    this.journalContext = const [],
  });
  final String entityKind;
  final String name;
  final String existingDetail;
  final String systemPrimer;
  final String? sceneTitle;
  final List<String> journalContext;
}
```

`buildFleshOutPrompt(FleshOutSeed)` — a fixed instruction, then the **#1
grounding** (`system:` / `scene:` / `recall:` via the existing `_flat` /
`_capped` helpers + `kRecallMaxEntries` / `kRecallMaxChars`), then a `name:`
line, an `existing:` line (the current detail, capped; omitted when empty), and
a trailing `Detail:` cue. Instruction:

> "You are the game master for a solo tabletop RPG. Flesh out the following
> {entityKind} with 2-4 sentences of vivid, concrete detail consistent with the
> established facts. Build on any existing notes — do not contradict them. Output
> only the description — no preamble, no headers, no lists."

`parseFleshOutResponse(String)` — strip `<think>`, trim, throw `FormatException`
on empty (mirrors `parseNarrateResponse`).

`InterpreterService.fleshOut(FleshOutSeed) → Future<String>`:
- `GemmaInterpreterService`:
  `parseFleshOutResponse(await _generate(buildFleshOutPrompt(seed)))`.
- `FakeInterpreterService`: counter + optional error + canned reply
  (`fleshOutCalls` / `fleshOutError` / `lastFleshOutSeed` / `queuedFleshOut`,
  default `'Fleshed-out detail.'`).

### 2. Shared seed assembler — `lib/state/play_context.dart`

To keep the four entry points thin and the grounding DRY, a **pure** core
assembles the seed (unit-testable), with a thin ref-reading wrapper for the call
sites:

```dart
// Pure — no Riverpod; takes the already-read campaign state.
FleshOutSeed fleshOutSeedFrom({
  required String entityKind,
  required String name,
  required String existingDetail,
  required String systemPrimer,
  required List<JournalEntry> journal,
}) { … }

// Wrapper — reads providers, delegates to the pure core.
FleshOutSeed buildFleshOutSeed(
  WidgetRef ref, {
  required String entityKind,
  required String name,
  required String existingDetail,
}) =>
    fleshOutSeedFrom(
      entityKind: entityKind,
      name: name,
      existingDetail: existingDetail,
      systemPrimer: ref.read(systemPrimerProvider),
      journal: ref.read(journalProvider).valueOrNull ?? const [],
    );
```

`fleshOutSeedFrom` derives `sceneTitle` from the newest `JournalKind.scene`
entry's title (or null) and sets `journalContext = searchEntries(journal,
name).take(kRecallMaxEntries)` mapped to `'title: body'`-style recall lines —
journal entries that mention the entity by name (`[]` when none). Lives beside
`activeCharacterLineProvider` (already the grounding-assembly home; already
imports providers + journal_search).

> Recall here uses the **name-query** `searchEntries` (journal_search.dart),
> distinct from narrate/interpret's entry-target `recallLines` — the entity has
> no single anchor entry, so we rank by mentions of its name.

### 3. Entry points (4) — each aiReady-gated

Each: build seed via `buildFleshOutSeed` → `fleshOut(seed)` (busy guard + error
SnackBar) → review → append → persist.

1. **Character** (`tracker_screen.dart`, the character sheet view). An aiReady
   `flesh-out-character` IconButton beside the existing "Edit name & notes"
   icon → generate → open `_editNameNote`'s `_EditDialog` with `initialB =
   [c.note, detail].where(notEmpty).join('\n\n')` → user trims → Save via
   `charactersProvider.replace(c.copyWith(note:))`. `entityKind` = `'NPC'` when
   `role == npc`, else `'character'`.
2. **Thread** (`tracker_screen.dart`, `ThreadsPane`). A per-row aiReady
   `flesh-out-thread-<id>` action → generate → `_EditDialog` (title=t.title,
   note appended) → `threadsProvider.replace(t.copyWith(note:))`. `entityKind` =
   `'story thread'`.
3. **Dungeon room** (`map_screen.dart`, `_detailCard`). An aiReady
   `flesh-out-room` button beside Linger → generate → **Append/Cancel review
   dialog** → on Append, `mapProvider.appendRoomDetail(room.id, detail)` (the
   same notifier `_linger` uses). `entityKind` = `'location'`.
4. **World hex site** (`map_screen.dart`, hex detail card, shown when
   `h.site != null`). An aiReady `flesh-out-site` button → generate →
   Append/Cancel review → on Append, `mapProvider.appendSiteLine(col, row,
   detail)`. `entityKind` = `'location'`.

### 4. Notifier addition — `appendSiteLine`

`MapState` notifier (`providers.dart`) gains:

```dart
Future<void> appendSiteLine(int col, int row, String text) async { … }
```

mirroring `appendRoomDetail` (855): map over cells, append `text` to the
matching `HexCell.siteLines`, persist. (The existing site-line method *rolls* a
table line; this one takes arbitrary LLM text.)

### 5. Shared review dialog — `map_screen.dart`

A small `_fleshOutReview(context, generated) → Future<bool>` AlertDialog
(scrollable text + Cancel / `flesh-out-append` Append) reused by the room + hex
entry points. (Characters + threads reuse `_EditDialog`, which is itself the
review surface.)

## Testing

- `oracle_interpreter` test: `buildFleshOutPrompt` renders the instruction with
  the interpolated `{entityKind}`, the grounding (`system:`/`scene:`/`recall:`),
  the `name:`/`existing:` lines (and omits `existing:` when empty), ends with
  `Detail:`; `parseFleshOutResponse` strips think / throws on empty.
- `fleshOut` exercised through the fake.
- Widget tests (fake interpreter, aiReady):
  - character flesh-out appends generated text to the note and saves;
  - thread flesh-out appends + saves;
  - room flesh-out → Append → `room.detail` grows;
  - hex flesh-out → Append → `siteLines` grows;
  - each surface's button is **absent when AI is not ready** (spot-checked on at
    least the character + room surfaces).
- `fleshOutSeedFrom` unit test (pure): name-query recall picks entries
  mentioning the name, scene title from the newest scene, primer passthrough,
  empty journal → `[]` context.

## Out of scope (future)

- Fleshing out scenes, factions, items; structured-field fill (vs free-text
  append); regenerate/variants; streaming; flesh-out from the assistant rail.
- LLM-ranked suggestion chips (#5) remains the last queued AI affordance.

## Files touched

| File | Change |
|------|--------|
| `lib/engine/oracle_interpreter.dart` | `FleshOutSeed`, `buildFleshOutPrompt`, `parseFleshOutResponse` |
| `lib/state/interpreter.dart` | `fleshOut` on the interface |
| `lib/state/interpreter_gemma.dart` | `fleshOut` impl |
| `lib/state/play_context.dart` | `buildFleshOutSeed` assembler |
| `lib/state/providers.dart` | `appendSiteLine` notifier method |
| `test/fake_interpreter.dart` | `fleshOut` fake |
| `lib/features/tracker_screen.dart` | character + thread entry points |
| `lib/features/map_screen.dart` | room + hex entry points + review dialog |
| tests | prompt + seed-assembler + 4 entry-point widget tests |
