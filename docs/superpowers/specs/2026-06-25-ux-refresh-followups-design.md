# UX Refresh — Follow-ups Design

**Status:** proposed · **Date:** 2026-06-25 · **Depends on:** the 7-phase UX refresh (PRs #170–#176, all merged to `main`).

These four items were deliberately deferred during the UX-refresh epic — each was out of scope for the phase that surfaced it, or blocked on a primitive that a later phase introduced. They are small and independent; implement in any order (suggested order below = ascending effort). One combined spec because none warrants its own; split into per-item plans at implementation time if useful.

Style everything against the Phase-0 `JuiceTokens` (`context.juice`). No new pub deps. Pre-release → no backward-compat for old persisted JSON.

---

## 1. Directive empty state for the empty journal

**Why deferred:** Phase 0 shipped the shared `EmptyState` widget and adopted it at the empty roster, but the journal's directive empty state named a primary action — "Roll the oracle or write your first line" — whose roll affordance (the inline oracle dock) did not exist until Phase 1. The dock now exists (`InlineRollDock`, `lib/features/inline_roll_dock.dart`), so the blocker is gone.

**Current state:** `lib/features/journal_screen.dart` — the entry list builder returns `const SizedBox.shrink()` for an empty journal (around the `if (entries.isEmpty)` guards, ~line 151); the player sees the composer + dock but no orientation.

**Approach:** When the journal has zero entries, render `EmptyState` above the dock/composer instead of an empty list:
- title `'A blank page.'`
- body `'Roll the oracle or write your first line.'`
- primary `'Roll oracle'` → fire the dock's `roll-oracle` action (reuse the extracted `rollInlineSuggestion(ref, oracle, <roll-oracle suggestion>)` from `lib/state/suggestions_provider.dart` — already the single roll pipeline; do NOT duplicate it).
- optional secondary `'Write a line'` → focus the composer `TextField`.

Keep the dock + composer visible beneath (the empty state is orientation, not a takeover). Mind the loose-constraint trap: the journal body has bounded height, so wrap the `EmptyState` in `Expanded`/`Flexible` within the existing Column rather than letting it fight the list.

**Tests:** extend a journal pump test (reuse the `journal_payload_ui_test.dart` harness) — seed an empty journal, assert `Key('empty-state-primary')` present; tap it, assert a `result` entry appears (the roll fired through the shared pipeline).

**Effort:** S (one screen, one widget already exists).

---

## 2. Standardize the `✦` badge on the flesh-out affordances

**Why deferred:** Phase 2 introduced the shared `AiBadge` (`✦`, `lib/shared/ai_badge.dart`) and applied it to the prominent AI actions (Interpret / Voice / Recap / Narrate / Ask-GM) but explicitly left the **flesh-out** call sites for a later sweep to keep the phase reviewable.

**Current state — the flesh-out entry points (all AI, `interpreterServiceProvider.fleshOut`):**
- `lib/features/tracker_screen.dart` — `flesh-out-thread-<id>` (`_fleshOutThread`, ~line 69/107) and `flesh-out-character` (`_fleshOutCharacter`, ~line 1222/1300).
- `lib/features/map_screen.dart` — the dungeon-room and world-hex-site flesh-out actions (grep `fleshOut`/`appendRoomDetail`/`appendSiteLine`; verify the exact keys).
- The scene flesh-out in the scenes pane (`flesh-out-scene-<id>`, per CLAUDE.md AI-expansion #5) — include for completeness.

**Approach:** Give each flesh-out trigger the shared `AiBadge` leading glyph (matching the `✦ Interpret`/`✦ Narrate` treatment from Phase 2) so every AI-assisted action reads consistently. These triggers are already `aiReady`-gated, so no gating change — purely the leading icon. Where a trigger is an `IconButton`, swap its icon to `const AiBadge()`; where it's a labeled button, use `AiBadge(label: '…')`. Confirm the Phase-2 footnote ("✦ marks an AI-assisted action · all on-device") is reachable from these surfaces or add a local one if a surface has no AI footnote yet.

**Tests:** assert the `✦` (`AiBadge`/`Icons.auto_awesome`) renders on a flesh-out trigger in a tracker/map pump test; no behavior change to assert beyond presence.

**Effort:** S (icon swaps across ~4–5 call sites).

---

## 3. `Thread` numeric progress (clock)

**Why deferred:** Both the session-resume screen (#1) and the Track dashboard (#5) wanted to show thread progress as `n/10`, but the `Thread` model has no progress field — so both shipped showing Open/Pinned **status** instead. Adding the field unblocks the design's progress bars in three places at once.

**Current state:** `lib/engine/models.dart` `class Thread { id, title, note='', open=true, pinned=false }` (~line 181) — no progress. (Contrast `Track {filled, max}`, which the dashboard already renders as a real bar.)

**Approach:**
1. Add to `Thread`: `final int progress;` (default 0) and `final int progressMax;` (default 10 — the "/10" the design assumes). Thread through the constructor, `copyWith`, `toJson` (emit when non-zero/non-default), `fromJson` (tolerant defaults). Clamp `progress` to `0..progressMax`.
2. `ThreadNotifier` (`lib/state/providers.dart`) — add `setProgress(String id, int value)` (clamped) + likely a `±` step, mirroring the existing mutate-and-persist idiom (`toggleOpen`/`add`).
3. Render the bar (a `LinearProgressIndicator`, `tk.hairline` track / `tk.terracotta` fill + `progress/progressMax` readout) in the three surfaces that already enumerate threads:
   - the Threads pane / thread rows (`threads_pane.dart` / `tracker_screen.dart`) — with `−`/`+` steppers.
   - the **resume screen** open-threads list (`session_resume_screen.dart`) — replace the Open/Pinned pill with the bar.
   - the **Track dashboard** Threads card (`track_home_pane.dart`) — replace the status line with thin bars.

**Decision:** `progressMax` default 10 (matches the design + Ironsworn-ish "progress track" feel) but kept editable per thread, so non-tens still work. Don't hardcode `/10` in render — read `progressMax`.

**Tests:** model round-trip (progress/progressMax survive JSON + copyWith, clamp at bounds); `setProgress` clamps; a render assertion in one of the three surfaces that a thread with `progress=3,max=10` shows the bar/readout. Update the resume + dashboard tests that currently assert the status pill → assert the bar.

**Effort:** M (model + notifier + 3 render sites + their tests).

---

## 4. Genre/mood subtitle in the campaign lists

**Why deferred:** Phase 6 added the identity color spine + icon tile to the launcher/shell campaign rows but showed *systems* as the subtitle, not the **genre/mood** line the design wanted — because genre lives in per-campaign `CampaignSettings` (`juice.settings.v1.<id>`) and `settingsProvider` only resolves the **active** campaign, so a genre subtitle for every (mostly non-active) row would mean a heavy async `SharedPreferences` read per row.

**Current state:** `CampaignSettings {genre, tone}` persisted at create (`providers.dart` ~1377); `settingsProvider` (~1226) is active-campaign-scoped. Launcher rows (`launcher_screen.dart:196`) + shell rows show `formatSystems(...)`. `SessionMeta` already carries `identityColor`/`identityIcon` (Phase 6) — set at create, sync, cheap.

**Approach (recommended — denormalize):** add `final String? genre;` to `SessionMeta` (alongside the identity fields), set at create from the dialog's genre string (already passed to `create`). Render rows as `genre · <systems>` when genre present, else systems. Rationale: genre is chosen at create and rarely edited; mirroring it onto `SessionMeta` keeps the list render **sync + cheap** (the same pattern Phase 6 used for identity), avoiding a per-row async settings read. `CampaignSettings.genre` remains the source the interpreter reads; `SessionMeta.genre` is a display mirror.
- **Dual-write caveat:** if/when a genre *editor* is added (today genre is create-only), it must update both `CampaignSettings` and `SessionMeta.genre`. Note this at the edit site. Until then there is no second writer.

**Alternative (single-source):** a `campaignGenresProvider` that bulk-reads `juice.settings.v1.<id>` for all registered sessions once and caches a `Map<id,genre>`. Single source of truth, but adds an async provider + cache-invalidation on create/edit. Heavier than the denormalize for a cosmetic subtitle — prefer the denormalize unless a genre editor lands first.

**Tests:** `SessionMeta` round-trip with `genre`; a launcher/shell row test asserting the `genre · systems` subtitle when genre is set, systems-only when not.

**Effort:** S–M (model field + create wiring + 2 row render sites; the alternative is M+).

---

## Sequencing

Independent — ship separately. Ascending effort: **1 (empty journal)** → **2 (✦ badges)** → **4 (genre subtitle)** → **3 (thread progress)**. Items 1, 2, 4 are each a small PR; item 3 is the one with real surface area (model + notifier + three render sites). None blocks another.
