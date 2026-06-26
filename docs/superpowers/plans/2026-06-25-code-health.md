# Code Health Implementation Plan

**Source:** `docs/code-analysis/2026-06-25-analysis.md`
**Date:** 2026-06-25
**Status:** proposed

Phases 1–6 are independent — any order, any parallelism. Phase 7 (models split) is last
because it touches ~80 import sites across every prior phase's output. Each phase is one
shippable PR off `main`.

---

## Phase 1 — Quick wins (lint + dead seam) ~1 hr

**Branch:** `code-health-quick`

### Task 1.1 — Fix deprecated `TextFormField.value`

**File:** `lib/features/kal_arath_sheet.dart`

- [ ] Line 86: `value:` → `initialValue:`
- [ ] Line 102: `value:` → `initialValue:`
- [ ] Run `flutter analyze` — 0 deprecated_member_use warnings remain.

### Task 1.2 — Fix missing `const` in test constructors

**File:** `test/campaign_preview_pane_test.dart`

- [ ] Run `dart fix --apply test/campaign_preview_pane_test.dart`
- [ ] Confirm 8 `prefer_const_constructors` infos gone.

### Task 1.3 — Remove unused `askGm` seam

CLAUDE.md confirms `askGm()` is app-unused (multi-turn `gmChat` replaced it).

**File:** `lib/engine/oracle_interpreter.dart`

- [ ] Delete `buildAskGmPrompt(...)` function and `parseAskGmResponse(...)` function (~30 LOC).
- [ ] Delete `AskGmSeed` class if present in same file; remove from any barrel exports.
- [ ] Grep for all call sites: `grep -r 'buildAskGmPrompt\|parseAskGmResponse\|AskGmSeed\|askGm' lib/` — confirm zero after removal.
- [ ] `flutter test` — full suite green.

**Verify:** `flutter analyze` shows 0 issues (or info-only on other files). 1406+ tests pass.

---

## Phase 2 — Performance hot paths ~2 hr

**Branch:** `code-health-perf`

### Task 2.1 — Cache `mentionedCharIds`

**Problem:** `mentionedCharIds(entry)` called inside `entries.where(...)` on every rebuild —
O(n × m) per frame, redone on every provider tick.

**File:** `lib/state/providers.dart` (or nearby providers file)

- [ ] Add `mentionedCharIdsProvider` as a derived `Provider<Map<String, Set<String>>>` that
  maps `entryId → Set<characterId>`, computed once when `journalProvider` ticks:
  ```dart
  final mentionedCharIdsProvider = Provider<Map<String, Set<String>>>((ref) {
    final entries = ref.watch(journalProvider).valueOrNull ?? [];
    return {for (final e in entries) e.id: mentionedCharIds(e)};
  });
  ```
- [ ] In `journal_screen.dart`, replace the inline `mentionedCharIds(e)` calls in filter/render
  with a lookup into the cached map (read via `ref.watch(mentionedCharIdsProvider)[e.id]`).
- [ ] `flutter test` — full suite green.

### Task 2.2 — Move dungeon bounds out of `paint`

**Problem:** `DungeonMapPane`'s `CustomPainter.paint` recomputes bounding box over all rooms
every frame.

**File:** `lib/features/map_screen.dart` (locate `_DungeonMapPainter` or equivalent)
**File:** `lib/engine/models.dart` (`MapState`)

- [ ] Add `Rect? _cachedBounds` to the `MapState` or `MapNotifier`; compute in `addRoom`,
  `moveRoom`, `removeRoom` paths rather than in `paint`.
  ```dart
  // MapState or computed getter:
  Rect get boundingBox => _computeBoundingBox(rooms);
  ```
  Alternatively: make the painter take a pre-computed `Rect bounds` parameter so the
  `CustomPainter` is pure (no compute, just paint).
- [ ] Confirm `paint` no longer contains a loop over rooms for bounds computation.
- [ ] `flutter test` — full suite green.

**Verify:** both providers and painters are covered by existing tests; no behavior change.

---

## Phase 3 — Anti-pattern hardening ~2 hr

**Branch:** `code-health-antipatterns`

### Task 3.1 — Force-unwrap diagnostics on asset lookups

**Files:** `lib/engine/oracle.dart`, `lib/features/map_screen.dart`

- [ ] `oracle.dart` — replace `_fateMap[key]![likelihood.key]!` with:
  ```dart
  final outer = _fateMap[key] ?? (throw StateError('oracle: missing key "$key" — rebuild oracle_data.json'));
  final value = outer[likelihood.key] ?? (throw StateError('oracle: missing likelihood "${likelihood.key}" for "$key"'));
  ```
- [ ] `map_screen.dart` — replace `data.monsterEnvFormula['$envRow']!` with:
  ```dart
  data.monsterEnvFormula['$envRow'] ?? (throw StateError('missing monsterEnvFormula row "$envRow"'))
  ```
- [ ] Grep for remaining `!` on map-lookup chains in `lib/engine/`: address or document each
  as intentionally verified.
- [ ] `flutter test` — full suite green (no behavior change; same throw semantics, better message).

### Task 3.2 — Extract `_primerFor` helper

**File:** `lib/engine/system_primer.dart`

- [ ] Add:
  ```dart
  String _primerFor(String key) =>
      kSystemPrimers[key] ?? (throw StateError('no primer for system "$key"'));
  ```
- [ ] Replace all 11 `kSystemPrimers[key]!` call sites with `_primerFor(key)`.
- [ ] `flutter test` — full suite green.

### Task 3.3 — `allTags()` as derived provider

**Problem:** `JournalEntry.allTags()` called inside list-build loops; O(n·m) per frame.

**File:** `lib/state/providers.dart`

- [ ] Add:
  ```dart
  final allTagsProvider = Provider<Set<String>>((ref) {
    final entries = ref.watch(journalProvider).valueOrNull ?? [];
    return {for (final e in entries) ...e.allTags()};
  });
  ```
- [ ] Replace inline `allTags()` aggregation in the journal filter dropdown (and any other
  build-time usage) with `ref.watch(allTagsProvider)`.
- [ ] `flutter test` — full suite green.

---

## Phase 4 — Journal screen extraction ~4 hr

**Branch:** `code-health-journal-extract`

**Problem:** `journal_screen.dart` ~2957 LOC. Entry renderers are independently testable;
extraction unblocks per-kind widget tests without pumping the full journal scaffold.

**Files:**
- Create: `lib/features/journal_entry_tile.dart`
- Modify: `lib/features/journal_screen.dart`

- [ ] Identify all per-kind render functions inside `journal_screen.dart`:
  - `_PayloadCard` (result hero card with gradient)
  - `_DiceLogRow` (compact dice log row)
  - `_SceneDivider` (scene divider tile)
  - `_SketchThumbnail` / sketch entry tile
  - `_EntryTile` (the dispatch widget itself)
- [ ] Move each into `lib/features/journal_entry_tile.dart`. Keep private helpers
  (`_formatTimestamp`, etc.) that are tile-local in the new file; keep journal-global
  helpers (`rollInlineSuggestion`, etc.) in `journal_screen.dart`.
- [ ] `journal_screen.dart` imports `journal_entry_tile.dart`; the `ListView.builder` body
  becomes a single `JournalEntryTile(entry: e, ...)`.
- [ ] Add / extend `test/journal_entry_tile_test.dart`:
  - seed each `JournalKind` variant, pump `JournalEntryTile`, assert key widget renders.
  - Reuse the `journal_payload_ui_test.dart` fixture harness (prefs + oracle override).
- [ ] `flutter test` — 1406+ tests green.

**Verify:** `journal_screen.dart` is under 1500 LOC after extraction.

---

## Phase 5 — Notifier cleanup ~3 hr

**Branch:** `code-health-notifiers`

Two independent sub-tasks; do in any order within the branch.

### Task 5.1 — Extract I/O from `SessionsNotifier`

**Problem:** `SessionsNotifier` (~278 LOC) owns both state-mutation logic and
campaign-file I/O. The I/O methods belong in `campaign_io.dart` as pure functions.

**Files:** `lib/state/campaign_io.dart`, `lib/state/providers.dart`

- [ ] Move `exportActiveFile()` body into a pure `exportCampaign(SessionMeta, ...)` function
  in `campaign_io.dart` (already imported by the notifier).
- [ ] Move `importCampaignData()` body into a pure `importCampaign(String json)` /
  `importCampaignBundle(Uint8List zip)` in `campaign_io.dart`.
- [ ] `SessionsNotifier` methods become thin dispatchers that call the pure functions and
  then call `_persist()`.
- [ ] Existing `campaign_io_test.dart` (or add one) covers the pure functions directly.
- [ ] `flutter test` — full suite green.

### Task 5.2 — Collapse `CharacterNotifier` `add*` boilerplate

**Problem:** 20+ `addIronsworn`, `addDnd`, `addShadowdark`, … methods, each 5–10 LOC of
identical `_mutate` + `Character.fromPreset` boilerplate.

**File:** `lib/state/providers.dart` (`CharacterNotifier`)
**File:** `lib/engine/models.dart` (`Character`)

- [ ] Add a `SheetPreset` enum (or reuse the sheet-system string key) and a
  `Character.forPreset(SheetPreset)` factory that dispatches to the current per-preset
  field initializations.
- [ ] Replace the 20 `add*` methods with:
  ```dart
  Future<void> addPreMadeSheet(String systemKey) async { ... }
  ```
  Keep named methods as one-line wrappers for any external call sites in tests:
  ```dart
  Future<void> addIronsworn() => addPreMadeSheet('ironsworn');
  ```
  Or update call sites if they're all internal.
- [ ] `flutter test` — full suite green.

---

## Phase 6 — Coverage gaps ~2 hr

**Branch:** `code-health-coverage`

Three independent test additions; lowest priority.

### Task 6.1 — `enter_campaign.dart` edge cases

- [ ] In `test/enter_campaign_test.dart` (create):
  - Zero entries → `enterCampaign` calls `landFor` (not resume).
  - Non-zero entries → `enterCampaign` pushes `SessionResumeScreen`.
  - `enterCampaignWith` guard: when called with empty entries, navigates without crash.
- [ ] Coverage for `enter_campaign.dart` rises above 60%.

### Task 6.2 — `interpreter.dart` error-phase paths

- [ ] In `test/interpreter_test.dart` (create or extend):
  - Use `FakeInterpreterService` initialized with `InterpreterPhase.error`.
  - Assert `aiReadyProvider` resolves `false`.
  - Assert `aiSupportedProvider` still resolves `true` (error ≠ unsupported).
- [ ] Coverage for `lib/state/interpreter.dart` rises above 60%.

### Task 6.3 — `help_nav.dart` smoke test

- [ ] In `test/help_nav_test.dart` (create):
  - Pump `HelpNav()` with minimal scaffold + overridden providers.
  - Assert it renders without overflow.
- [ ] Coverage for `lib/shared/help_nav.dart` rises above 50%.

---

## Phase 7 — `models.dart` split (invasive) ~1 day

**Branch:** `code-health-models-split`

**Last** — done after all other phases are merged to avoid compounding conflict surface.

### Plan

Split `lib/engine/models.dart` (3920 LOC, 43 classes) into focused sub-modules:

| Sub-module | Classes / constants |
|---|---|
| `lib/engine/models/journal.dart` | `JournalEntry`, `JournalKind`, `GenResult`, `JournalEntryExt` |
| `lib/engine/models/character.dart` | `Character`, `CharacterRole`, `kConditions`, sheet constants (`kDndClasses`, `kOseClasses`, …) |
| `lib/engine/models/thread.dart` | `Thread`, `Track`, `Rumor`, `Encounter`, `EncounterState` |
| `lib/engine/models/session.dart` | `SessionMeta`, `CampaignMode`, `CampaignSettings`, `kAllSystems`, `kKnownSystems`, `kSystemCategory`, `CampaignPreset` |
| `lib/engine/models/map.dart` | `MapState`, `HexCell`, `Room`, `LocationRef` |

`lib/engine/models.dart` becomes a barrel:
```dart
export 'models/journal.dart';
export 'models/character.dart';
export 'models/thread.dart';
export 'models/session.dart';
export 'models/map.dart';
```

### Steps

- [ ] Create the 5 sub-module files, move classes verbatim (no logic changes).
- [ ] Add necessary cross-imports (e.g. `character.dart` may reference `session.dart` for
  system-key types; keep the dependency graph acyclic).
- [ ] Update `lib/engine/models.dart` to be a pure barrel export.
- [ ] Run `flutter analyze` — fix any "unused import" or "missing import" errors by updating
  any file that imported `models.dart` directly and now needs a sub-module.
  (Most will continue to work via the barrel; only files that use IDE auto-import on the
  specific class path will need updating.)
- [ ] `flutter test` — full suite green.
- [ ] Confirm `models.dart` itself is ≤20 LOC (barrel only).

**Risk:** mechanical rename only — no logic change. If a circular import appears, resolve
by moving the shared type to the module that is depended upon (typically `session.dart`).

---

## Deferred (not in this plan)

- **Lint tightening to `very_good_analysis`** — evaluate separately; will surface 20-40 new
  infos most auto-fixable. Good follow-up after models split settles.
- **`SubtabHost` contract in CLAUDE.md** — doc-only change; add to any PR touching
  `tracking_tab.dart`.
- **Thread `progressMax` system-aware default** — deferred to when a system editor lands.

---

## Execution order

```
Phase 1 (quick wins)   ─┐
Phase 2 (perf)         ─┤── any order, any parallelism
Phase 3 (anti-patterns)─┤
Phase 4 (journal)      ─┤
Phase 5 (notifiers)    ─┤
Phase 6 (coverage)     ─┘
                         └─→ Phase 7 (models split) — must be last
```

Total: 6 small PRs (1–3 hr each) + 1 large PR (~1 day). All mechanical — no user-facing
behavior change. Full suite must stay green after each.
