# Context Spine + Verb Nav — Design

**Status:** Approved

## Problem

The app exposes ~24 tools across a 5-tab bottom nav (Journal / Maps / Party /
Tracking / Oracles) and ~8 Tracking subtabs. The families overlap heavily —
5 oracles, 5 generators, 3 map/travel tools, 8+ trackers — and nothing tells
the user which of them matters *right now*. The vision is an assistant that
holds the solo player's hand: a slim, relevance-filtered surface backed by a
single notion of "where am I in play."

This is the **foundation** thread of a larger redesign (decomposed below). It
does two things and nothing more:

1. Introduce a **PlayContext** — the play-state object every relevance filter
   reads.
2. Replace the 5-tab nav with **5 consolidated verbs**, reorganizing existing
   panes underneath without rewriting them.

Default lens: **party of adventurers** (the user's primary play style). The
GM/Party mode-switch is a separate, later thread.

## Scope

**In:**
- `PlayContext` provider + a per-campaign persisted pointer store.
- Bottom nav becomes 5 verbs: `Journal · Sheet · Ask · Map · Track`.
- Existing panes reparented under the verbs (presentation only).
- Relevance: sub-options filter by `enabledSystems`; `Ask` default keyed by
  `resolvedSystem`; `Sheet`/`Map`/`Track` honor focus pointers.
- Encounter model gains an optional `locationRef {mapId, cellId}` + a minimal
  "set location" affordance.

**Out (each its own spec):**
- GM ↔ Party mode-switch (re-skins the app by role).
- Assistant rail (LLM next-move suggestions, ask-the-GM box).
- Journal-as-canvas (typed blocks) + drawing block type.
- **Contextual generator distribution** — the fast-follow to this spec.
- Formal party model (lead PC + subordinates grouping).
- Rich encounter-pin-on-map UI.

## PlayContext — `lib/state/play_context.dart` (new)

A provider that composes derived + stored state into one object the UI reads.

- **Derived** (from existing providers, not stored here):
  - `enabledSystems: Set<String>` — from `SessionMeta.enabledSystems`.
  - `resolvedSystem: String` — the existing priority resolver
    (`dnd > shadowdark > Ironsworn-family`, family refined by ruleset).
  - `openThreadIds: List<String>` — from the threads provider where `open`.
- **Stored** (new, mutable, per-campaign, key `juice.context.v1.<sessionId>`):
  - `activeCharacterId: String?`
  - `activeSceneId: String?`
  - `activeLocation: ({String mapId, String cellId})?`

All stored pointers are nullable. Null = fall back to defaults (no focus). The
store follows the existing session-scoped persistence convention
(`<base>.<sessionId>`, registry-aware) used by journal/characters/etc.

`playContextProvider` exposes the combined immutable snapshot;
`playContextProvider.notifier` exposes setters (`setActiveCharacter`,
`setActiveScene`, `setActiveLocation`, plus `clear*`). Setting a pointer to an
id that no longer exists resolves to null on read (defensive — entities can be
deleted).

## Party + focus model

Foundation treats the **existing flat character list as "the party."**
`activeCharacterId` is the *focused* member — whose moves/stats `Ask` defaults
to and whose sheet `Sheet` opens first. The user's real play is "a PC with
subordinates, or several PCs," so the focus pointer is deliberately
*one-focus-among-many*; a formal lead+subordinate grouping is a later thread and
will not force a redo of this pointer.

## Map + encounter linkage

- `activeLocation {mapId, cellId}` lives in `PlayContext`. Tapping a hex/room
  sets it; the `Map` verb opens to it.
- `Encounter` gains optional `locationRef {mapId, cellId}` (nullable, JSON
  round-trips, absent in legacy data). Foundation adds the field + a "set
  location" link that writes the current `activeLocation` (or a picked cell).
  The map-side rendering of encounter pins is deferred to the Map thread.

## Nav reorg — `lib/shared/home_shell.dart` + `tracking_tab.dart`

Five verbs replace the five tabs. Each verb aggregates **existing panes** via
the existing `tool_host` / keep-alive panel machinery — no pane is rewritten.

| Verb | Aggregates |
|------|-----------|
| `Journal` | current home / journal screen |
| `Sheet` | `CharactersPane` + Moves (Ironsworn family) + focus character |
| `Ask` | Fate Check · Roll High · Mythic GME · Dice · LLM interpreter — generators parked under a `Generate` segment (distributed by the fast-follow) |
| `Map` | Maps (world/dungeon) · Hexcrawl · Verdant Journey |
| `Track` | Scenes · NPCs · Threads · Rumors · Clocks/Tracks · Encounter · Resources · Battle · Party Emulator · Sidekick |
| Overflow (top bar/menu) | Table Browser · Lonelog Notation · Behavior Tables · Help · Campaigns/settings |

Nav always shows all 5 verbs (stable muscle memory). Filtering happens
*inside* a verb.

## Relevance behaviors

- **Sub-option gating by `enabledSystems`** — generalizes the sheet-picker gate
  already shipped (`tracker_screen.dart`): Moves only if `ironsworn`; Lonelog
  panes only if `lonelog`; D&D/Shadowdark sheet options only if those systems;
  etc. One shared helper reads `PlayContext.enabledSystems`.
- **`Ask` default tool by `resolvedSystem`** — Ironsworn-family → Moves/Fate;
  D&D / Shadowdark → Dice; generic → Fate / Roll High. User can still reach any
  oracle; this only sets the landing default.
- **`Sheet`** opens the focused character (else the list).
- **`Map`** opens `activeLocation` (else last/first map).
- **`Track`** pins the active scene at the top of the Scenes pane.

## Backward compatibility — out of scope

Explicitly **not a concern for this thread** (pre-release, solo dev). No
migration scaffolding; existing saved campaigns/journals may break and that is
acceptable. Build the cleanest model, not a compatible one. Revisit
compatibility/migration as a release gate, separately. The new
`juice.context.v1.<sessionId>` store is simply created when first written.

## Testing

- `play_context_test.dart` — provider composes derived + stored; setters
  persist; stale id resolves to null; session-scoped key isolation.
- `play_context_persist_test.dart` — pointers survive a notifier rebuild
  (mock prefs), per the session-scoped persistence pattern.
- Nav: widget tests that the 5 verbs render and each opens its aggregated
  pane(s); sub-option gating by `enabledSystems` holds (reuse the
  `character_sheet_ui_test.dart` harness pattern — pump panes directly, seed
  `juice.sessions.v1` with chosen systems, avoid the rootBundle hang by not
  pumping the full shell where data providers aren't overridden).
- `Ask` default-tool-by-system selection.
- Encounter `locationRef` JSON round-trip (nullable, absent → null).
- Regression: existing pane tests stay green; full suite green.

## Decomposition (sequence after this spec)

1. **This spec** — context spine + verb nav + reorg.
2. Contextual generator distribution (fast-follow).
3. Assistant rail (reads `PlayContext` — scene + threads + focus).
4. GM/Party mode-switch.
5. Journal-as-canvas + drawing.
6. Formal party grouping; encounter-pin-on-map UI.

## Docs & memory

- Update `CLAUDE.md` project notes: the `PlayContext` spine, the verb nav, and
  the deferred-thread sequence.
- This is a navigation/architecture change, not new licensed content — no
  licensing implications.
