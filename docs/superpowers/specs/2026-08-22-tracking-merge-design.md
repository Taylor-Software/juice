# Tracking Merge — Threads + Tracks + Rumors Become One Entity

**Date:** 2026-08-22
**Status:** Approved design, pre-implementation
**Sub-project:** 1 of 7 in the tool-consolidation epic (see "Epic context" below)

## Problem

The Track verb offers three ways to track a thing the player cares about:

- **Threads** (`Thread`, `juice.threads.v1`, `ThreadsPane`) — title, note, open flag,
  pinned flag, progress clock (`progress`/`progressMax`), optional bidirectional
  `Tally`, journal backlinks via `JournalEntry.threadId`, `@[title](thread:ID)`
  mentions.
- **Tracks** (`Track`, `tracksProvider`, `TracksPane`) — name, filled/max progress
  bar, note. A strict subset of a thread's clock.
- **Rumors** (`Rumor`, `rumorsProvider`, `RumorsPane`) — text, resolved flag, note,
  AI flesh-out. Narratively "a thread that isn't confirmed yet".

Three panes, three models, three providers — one job. The user chose a true merge:
one integrated entity taking the best of each, old tools deleted.

## Decisions already made (user-confirmed)

1. **True merge** — one entity, one pane; separate tools deleted (not just UI unification).
2. **All three merge** — a rumor is a thread in a pre-confirmation stage; a track is a
   thread with only a clock.
3. **Fresh start for rumors/tracks data** — existing `Rumor`/`Track` persisted data is
   not migrated. Existing threads keep loading (tolerant JSON).
4. **Model approach A** — a stage enum on `Thread` (not a frozen kind, not a new entity).

## Design

### 1. Model (`lib/engine/models/journal.dart`)

`Thread` gains a stage:

```dart
enum ThreadStage { rumor, active, done }
```

- New field `ThreadStage stage`, default `active`. JSON key `stage`, omitted at default.
- The `open` bool is **replaced** by stage. Tolerant `fromJson`: when no `stage` key is
  present, `open == false` reads as `done`, anything else as `active` — so existing
  persisted threads load unchanged in meaning.
- `copyWith` gains `stage`. `toJson` writes `stage` only when not `active` and stops
  writing `open`.
- Rumor absorption: rumor text maps to `title`, rumor note to `note`. "Resolve true"
  is a promotion to `active`; "resolve false" is `done` (or delete).
- Track absorption: `filled`/`max` map to the existing `progress`/`progressMax`.
  Nothing remains — `Track` is a strict subset.
- `Rumor` and `Track` classes are deleted.
- Unchanged: `pinned`, progress clock, optional `Tally`, `note`, backlinks, mentions.

### 2. Persistence + providers (`lib/state/providers.dart`)

- Threads stay under `juice.threads.v1`. No new key, no re-keying.
- `ThreadNotifier` gains `setStage(String id, ThreadStage stage)`.
- `rumorsProvider`, `tracksProvider`, `RumorNotifier`, `TrackNotifier`, and their
  storage keys are deleted. Keys are removed from `sessionScopedKeys` (they stop
  being exported). Campaign import stays tolerant: old files that carry rumor/track
  keys import fine; those keys are ignored.

### 3. UI — one pane (`lib/features/tracker_screen.dart`)

`ThreadsPane` becomes the single tracking pane:

- Stage filter chips above the list: All / Rumors / Active / Done.
- A rumor-stage card shows a **Confirm** button that promotes the thread to `active`.
- Every card keeps the existing affordances: clock stepper, tally row
  (`ThreadTallyRow`), pin, entries backlink chip, edit/delete with undo.
- New-thread creation defaults to `active`; a second "New rumor" button beside
  "New" creates at `rumor` stage. No stage choice inside the create dialog.
- The AI flesh-out affordance that lived on rumor cards (`flesh-out-rumor-<id>`)
  moves onto rumor-stage thread rows (same `buildFleshOutSeed` +
  `showFleshOutReview` flow, appending to `note`).
- `RumorsPane` (`lib/features/rumors_pane.dart`) and `TracksPane`
  (`lib/features/tracks_pane.dart`) are deleted.
- In `lib/features/tracking_tab.dart`: the `rumors` and `tracks` subtabs are removed;
  the `threads` subtab's aliases grow to `['tasks', 'rumors', 'tracks']` so legacy
  routes land on the unified pane.

### 4. Touch points

All readers re-point to `threadsProvider`:

- **Run screen** `_ThreadsRumorsPanel` (`lib/features/run_screen.dart`): renders
  active threads plus a rumor-stage section from the one provider; row taps navigate
  to the `threads` subtab.
- **Suggestions** (`lib/engine/suggestions.dart`): `develop-rumor` navigates to the
  `threads` subtab; `hasTally` logic is unchanged.
- **Campaign search** (`lib/engine/campaign_search.dart`): `SearchResultKind.rumor`
  and `.track` are removed along with the `rumors`/`tracks` list parameters;
  thread results carry the stage. `campaign_search_sheet.dart` follows.
- **Provider consumers** (verified by grep): only `rumors_pane.dart`,
  `run_screen.dart`, and `campaign_search_sheet.dart` consume `rumorsProvider` —
  all covered above. No other surface writes rumors.
- **Track-verb help card** (`track_home_pane.dart` `_helpCard`): the
  Rumors/Tracks/Tasks lines collapse into the Threads line.
- **Unchanged by design** (same provider, same semantics): the encounter
  end-of-fight thread clock stepper, HUD pinned-thread chips, Loop pane tally step,
  thread mentions and journal backlinks.
- **Counts/overviews**: `track_home_pane.dart` and `session_resume_screen.dart`
  update their rumor/track references to stage-filtered thread queries.

### 5. Testing + success criteria

Tests:

- Unit: `ThreadStage` JSON round-trip; legacy `open:false` fallback to `done`;
  default-omission byte-compatibility for an `active` thread.
- Widget: unified `ThreadsPane` — stage filtering, rumor Confirm promotion, tally
  roll still works; campaign search returns staged threads and no rumor/track kinds;
  Run panel renders both sections from one provider.
- Existing thread tests stay green.

Success criteria:

- `flutter analyze` clean; full test suite green.
- `RumorsPane`, `TracksPane`, `Rumor`, `Track`, `rumorsProvider`, `tracksProvider`
  no longer exist in `lib/`.
- Legacy `rumors`/`tracks` subtab routes resolve to the unified Threads pane.
- One pane answers "what am I tracking?" with rumors, goals, and clocks in one list.

## Epic context — tool-consolidation roadmap (model-first order)

User-selected clusters, one sub-project each, in order:

1. **Tracking merge** — this spec.
2. **Combat merge** — Encounter screen + Run initiative panel become one encounter
   surface.
3. **Rolling merge** — one shared roll surface (dice + default oracle + likelihood +
   interpret) used by HUD, Run, Loop, composer.
4. **Inspiration browse merge** — one catalog browser widget behind both the
   composer inspire sheet and Ask → Tables.
5. **Tables unify** — residual editor/roll-path unification after PR #332.
6. **Party tool merge** — one integrated companion tool from emulator (Triple-O) +
   behavior (Pettish) + sidekick; the radio picker retires.
7. **Map generation merge** — one hex-travel tool (generic hexcrawl engine with
   Verdant flavor inside) and one dungeon generator; licensing
   (CC-BY-NC-SA Roll 4 Ruin, Verdant attribution) rides along.

Oracles are explicitly excluded from consolidation per the user.

Each subsequent sub-project gets its own brainstorm, spec, and plan.
