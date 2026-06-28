# GM Run-Screen

**Date:** 2026-06-28
**Status:** Design approved, pending implementation plan
**Builds on:** the live-session feature audit (this session) and the verb-nav /
PlayContext spine (`docs/superpowers/specs/2026-06-18-context-spine-verb-nav-design.md`)

## Summary

A single live "run the session" screen for a GM (or solo player) at the table — a
**read-and-act dashboard** that composes the app's existing play state into one
place so the GM stops tab-hopping mid-session. It is the first slice of turning
the app from a solo-journal-with-GM-mode into a tool that runs a live table.

Five panels: **Initiative**, **Party HP & conditions**, **Active scene + chaos**,
**Quick dice + oracle**, and a **Quick-capture note**. It is **pure composition**
over existing providers — every mutation routes through an existing notifier
method; the only genuinely new behaviors are a *roll-initiative-for-all* helper
and the capture box. No new persistence keys, nothing new to export.

### Non-goals (deferred)

- Monster/NPC **stat-block cards** (Tier-2 combat depth; user-authored later).
- Per-combatant **initiative modifiers** config (roll-all uses flat d20 in v1).
- **Reorderable / collapsible** panels with persisted layout (YAGNI for v1).
- **Threads & rumors** panel on the run-screen (fold in a later pass).
- **Multiplayer / players-on-devices** (Tier-3 architectural fork; out of scope).

## Decisions (from brainstorming)

- **Form factor:** responsive — adapts wide (multi-panel) ↔ narrow (stacked).
- **Panels:** Initiative + Party + Scene/chaos + Dice/oracle (+ capture as a given).
- **Placement:** a new top-level **`Run` verb** (6th destination), not a Track
  sub-pane or an overlay — most discoverable, one tap, works in GM and solo modes.
- **Posture:** **act-in-place** — the GM applies damage, advances turns, rolls,
  and edits the scene without leaving the screen.
- **Approach:** fixed responsive grid (approach A), panels as self-contained
  widgets over existing providers; rejected reorderable-panels (B, extra state)
  and tabbed (C, more taps, loses "everything at once").

## Architecture

### Placement & shell wiring

- Add `run` to the `Destination` enum and the home-shell nav (icon: `play`,
  label "Run"). Thread it through the shell body switch like the existing verbs.
- `landingDestination(CampaignMode.gm)` returns `Destination.run` (was `track`)
  so a GM campaign lands on the run-screen on entry. Party/solo landing is
  unchanged; Run is reachable by tapping the verb. Update the
  `landingDestination` test accordingly.
- New file `lib/features/run_screen.dart`: `RunScreen extends ConsumerWidget`
  (no new notifier — pure composition). Mounted by the shell for `Destination.run`.

### Layout (responsive, approach A)

- `RunScreen.build` uses `LayoutBuilder`. Width ≥ `kRunWideBreakpoint` (~720) →
  a 2-column grid: **left** = Initiative + Party; **right** = Scene + Dice/oracle
  + Capture. Narrow → a single scrolling column in priority order:
  Initiative → Party → Scene → Dice/oracle → Capture.
- A compact top bar shows the round/turn chip, the global light chip, and the
  mode chip — reusing the data the `CampaignHeader`
  (`lib/shared/play_context_hud.dart`) already exposes (the HUD itself still
  renders at the shell level above the body; the run-screen's bar is a thin
  in-panel echo of round/turn, not a second HUD).
- Each panel is a private widget in `run_screen.dart`: `_InitiativePanel`,
  `_PartyPanel`, `_ScenePanel`, `_DiceOraclePanel`, `_CapturePanel`. Each reads
  only the providers it needs, so each renders and tests independently.

## Panels (read + act-in-place)

Each panel below lists what it **reads** and how it **acts** (every action is an
existing notifier method unless marked NEW).

### Initiative — `_InitiativePanel`
- **Reads:** `encounterProvider` (`EncounterState`: combatants, turnIndex, round).
- **Shows:** combatant rows (initiative badge, name, HP `cur/max`), current-turn
  highlight, defeated rows struck through; round + "Next turn".
- **Acts:** `EncounterNotifier.nextTurn()`; inline ±HP per combatant (existing
  encounter HP path); "Add" (existing add-combatant flow); **"Roll all init"**
  (NEW: `EncounterNotifier.rollInitiativeForAll()` — assigns `d20` to each
  combatant whose initiative is unset/zero, then re-sorts via the existing
  descending-initiative insert logic; flat d20, no per-combatant modifier in v1).
- **Empty state:** if no encounter combatants, show a one-line "No encounter —
  Add a combatant" affordance (invites, not apologizes).

### Party — `_PartyPanel`
- **Reads:** `charactersProvider`, filtered to `role == pc` (and `companion`);
  the active PC (`playContextProvider.activeCharacterId`) marked "lead".
- **Shows:** a card per party member: name, HP pool, conditions (as chips).
- **Acts:** inline ±HP via `Character.withHpDelta` (D&D/Shadowdark `currentHp` or
  first track; no-pool sheets unchanged) → `CharacterNotifier.replace`; an
  "Effect…" button opening the existing `applyPartyEffect` modal (bulk
  HP/condition over a checkbox set).
- **Empty state:** if no PCs, "No party yet — add characters in Sheet".

### Scene — `_ScenePanel`
- **Reads:** the active scene via `activeSceneEntry(journal, activeSceneId)`
  (`play_context.dart`) + the chaos provider.
- **Shows:** scene title + description; chaos factor with −/+ steppers.
- **Acts:** inline edit of title/description → `JournalNotifier.replace` (the
  scene entry's `body`); chaos −/+ via the existing chaos notifier (same path the
  HUD uses). Optional aiReady-gated "Flesh out" reuse is **deferred** (keep v1 lean).
- **Empty state:** if no scene, "No active scene — New scene" → `addScene` +
  `setActiveScene`.

### Dice & oracle — `_DiceOraclePanel`
- **Reads:** `oracleProvider` (guard on `valueOrNull`), the default-oracle
  selection, `aiReadyProvider`.
- **Acts:** quick default-oracle roll + a Yes/No pull, each logged through the
  existing `oracle → journalProvider.addResult` pipeline (the shared
  `fateCheckGenResult` path the assistant rail/HUD already use); an
  **Interpret** action shown only when `aiReadyProvider` is true
  (`InterpreterService` interpret seam). Shows the latest result inline.

### Capture — `_CapturePanel`
- **Acts (only NEW affordance besides roll-all-init):** a text field + "Log"
  button writing a journal note via `JournalNotifier.addNote` (or the existing
  note-kind add). Clears on submit. No payload, no AI — a fast jot.

## Data flow

- The run-screen owns **no state**. It is a projection of existing providers;
  every write goes through an existing notifier (`nextTurn`, `applyPartyEffect`,
  `withHpDelta` + `replace`, chaos notifier, `addResult`, `addNote`,
  `addScene`/`setActiveScene`, scene `replace`).
- **One new engine/notifier method:** `EncounterNotifier.rollInitiativeForAll()`
  (uses the existing `Dice` util for d20; reuses the existing
  insert-in-descending-order logic so the turn pointer stays consistent).
- **No new persistence keys**, no new export surface, no schema bump. A run-screen
  session is whatever the providers already persist (encounter, characters,
  journal, playContext, chaos, light all already session-scoped + exported).

## Error handling / edge cases

- Every panel has an empty state (no encounter / no party / no scene) that
  invites the next action rather than rendering blank.
- AI affordances (Interpret) stay hidden unless `aiReadyProvider` — web and
  AI-off builds simply omit them (consistent with the rest of the app).
- Narrow layout never truncates: it stacks and scrolls; no nested scroll.
- `rollInitiativeForAll` only fills combatants with unset/zero initiative so it
  won't clobber values the GM typed; if all are set it is a no-op (still re-sorts).

## Testing

Widget tests pump `RunScreen` with seeded providers (the
`campaign_header_test` harness pattern — override the data providers, mock prefs):

- initiative: "Next turn" advances `turnIndex`/`round`; "Roll all init" fills
  unset initiatives and re-sorts; defeated rows are skipped by next-turn.
- party: inline ±HP writes back through `withHpDelta`; "Effect…" opens the modal.
- scene: editing title/description persists; chaos −/+ steps the value.
- dice/oracle: a roll logs a `result` journal entry; Interpret hidden when AI off.
- capture: "Log" writes a note journal entry and clears the field.
- shell: `landingDestination(CampaignMode.gm) == Destination.run` (unit);
  responsive reflow renders 2 columns wide and 1 column narrow (widget, via
  `tester.view.physicalSize`).

Model test: `rollInitiativeForAll` over a fixed `Dice` seed produces expected
initiative values + sort order; a no-op when all initiatives are already set.

## File structure

- **Create** `lib/features/run_screen.dart` — `RunScreen` + the 5 private panels.
- **Modify** `lib/engine/models.dart` (or the shell's destination file) — add
  `Destination.run`; add `EncounterNotifier.rollInitiativeForAll` in
  `lib/state/providers.dart`.
- **Modify** `lib/shared/home_shell.dart` — nav item, body switch, `landingFor`.
- **Modify** `lib/engine/<landing>.dart` — `landingDestination` gm → run.
- **Create/Modify** tests: `test/run_screen_test.dart`,
  `test/encounter_*_test.dart` (roll-all-init), the landing test.
- **Modify** `CLAUDE.md` — a Run-screen bullet.

## Out of scope (deferred, recap)

Stat-block cards; per-combatant init modifiers; reorderable/collapsible panels;
threads/rumors panel; pacing timers beyond the existing light chip; multiplayer.
Each is a clean follow-up that this v1 does not block.
