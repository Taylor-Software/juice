# Journal-first redesign — design spec

Date: 2026-06-11. Status: approved by user (brainstorming session).

## Goal

Turn the app from a tool-first oracle roller (4 tabs, log buried in Tracker)
into a journal-first companion for solo TTRPG players. The journal is the
home surface; every tool — oracles, generators, dice, characters, encounters,
maps — is summoned over it and feeds results back into it.

User decisions (validated via visual companion + Q&A):

- Layout: **journal full-screen + slide-in tool drawer** (desktop end-drawer
  ~400dp, mobile modal bottom sheet; breakpoint 840dp).
- Journal structure: **scenes + entries** (lightweight scene dividers).
- Dice roller: **notation engine** (no exploding/success pools in v1).
- Character sheet: **flexible blocks** (stats, tracks, tags, notes).
- Encounter tracker: **initiative + tracks** (no auto-population in v1).
- Maps: **dungeon rooms-and-corridors + wilderness hex** (no point-crawl v1).
- Tool grouping: **by activity**, with system badges and search.

## Phasing (one PR per phase, in order)

1. Journal core (data model + migration + journal screen)
2. Shell swap (journal home + tool drawer + activity-grouped registry)
3. Dice roller
4. Character sheets (flexible blocks)
5. Encounter tracker
6. Maps (6a dungeon, 6b hex — may split into two PRs)

Rationale: every new tool is built once, inside the final shell. The
highest-regression phase (2) happens before the codebase grows.

## Phase 1 — Journal core

**Model.** `LogEntry` becomes `JournalEntry`:

- `kind`: `text` (player prose) | `result` (tool output) | `scene` (divider)
- `title`, `body`, `threadId?` as today
- `scene` entries: scene title + optional `chaosFactor` snapshot (int)
- `createdAt` timestamp. Migrated entries are stamped at migration time;
  original order preserved.

**Persistence.** Session-scoped key `juice.journal.v2`. One-shot,
non-destructive migration from `juice.log.v1` (same pattern as
`SessionsNotifier.build`); migrated entries get `kind: result`. Campaign file
`schemaVersion` bumps to 2; import accepts v1 (log list maps to journal).

**Screen.** Chronological stream, oldest at top, newest at bottom (journal
reads forward — reverses the current log order). Scene dividers render
full-width with title + chaos chip. Composer pinned at bottom: text field +
"New scene" action. Kept from current log: thread filter chips,
link-to-thread, in-place edit, delete. `result` entries render their roll
detail as today.

**Integration point.** Every "Log" button becomes "Add to journal" (same
provider call, renamed).

## Phase 2 — Shell + tool drawer

**Shell.** `HomeShell` drops the 4-tab `NavigationBar`. Journal fills the
screen. Tools open over it: `endDrawer` ≥840dp, modal bottom sheet below.
Closing a tool returns to the journal in place. Tool widget state (last
result, selected odds) survives reopen within a session (keep-alive hosting,
not rebuild-per-open).

**Registry.** `ToolDef {id, label, icon, group, systemBadge?, builder}` in one
declarative list. Groups (activity-based):

| Group | Contents |
|---|---|
| Ask the Oracle | Fate Check, Roll High, Mythic (Fate Chart / Scene Test / Event Focus / Meaning) |
| Dice | dice roller (phase 3) |
| Story & Scenes | quest, scene, random event, plot point, pay the price, challenge |
| NPCs & Dialog | NPC, behavior, combat stance, dialog walk, dialog topics, companion |
| Exploration | wilderness travel, dungeon room/linger/name, settlement, hazard, maps (phase 6) |
| Encounters & Combat | monster encounter, creature tracks, encounter tracker (phase 5) |
| Names & Details | name, discover meaning, detail, property, treasure, abstract icons, immersion, random idea |
| Characters & Threads | character sheets, threads (current Tracker tabs become tools) |
| Reference | table browser, Ironsworn moves/oracles (shown only when ruleset enabled, license badge) |

**Launcher.** App-bar button opens the launcher in the same drawer/sheet:
search field on top, most-recently-used row pinned, grouped list below,
system badges (Juice/Mythic/Ironsworn) per item.

**Scope guard.** No new tools, no screen rewrites in this phase. Existing
screens are re-hosted with minimal change. The Fate screen's three sections
become three launcher entries anchored into one widget.

## Phase 3 — Dice roller

Pure-Dart notation engine (no table data, so `build_oracle.py` not involved).

**Grammar.** `NdX` with `d%` and `dF`; integer modifiers `+k`/`-k`;
multi-group sums `2d6+1d8+3`; keep/drop `4d6kh3`, `kl`, `dh`, `dl`;
shorthand `d20adv` / `d20dis` (sugar for `2d20kh1` / `2d20kl1`). Hand-written
recursive-descent parser; malformed input throws with position-anchored
message. No exploding dice or success pools in v1.

**Result.** Total + per-group breakdown: every die shown, kept highlighted,
dropped struck through.

**UI.** Text field with live validation; quick-tap chips
(d4 d6 d8 d10 d12 d20 d100 dF) — tapping again increments count (`d6`→`2d6`);
session roll history with tap-to-reroll; add-to-journal.

**Tests.** Parser accept/reject table, kh/kl correctness by enumeration,
distribution sanity per die, dF range.

## Phase 4 — Character sheets

`Character` grows from `{name, notes}` to flexible blocks:

- `stats`: ordered label/value pairs; value is free text ("17", "+2", "d8")
- `tracks`: label + current/max, +/- steppers (HP, momentum, supply…)
- `tags`: chips (conditions, bonds, gear)
- `notes`: free text (existing field)

Migration: existing characters → name + notes, empty blocks. The Characters
tool is the sheet editor; list rows show name + first track summary bar.
Threads untouched.

## Phase 5 — Encounter tracker

Session-scoped state, key `juice.encounter.v1.<sessionId>`.

- Combatants: pick from characters (links sheet, reads its first track) or
  ad-hoc name + HP.
- Initiative value per combatant; sorted; drag-reorder override; turn pointer
  + Next button; round counter increments on wrap.
- Per-combatant: track stepper, status tags, defeated toggle (greys out,
  skipped by Next).
- End Encounter → summary (rounds, defeated) offered as journal result entry.

## Phase 6 — Maps

**6a Dungeon.** Each dungeon-room generation places a room node on a grid
(drunkard's-walk placement, corridors as edges), stamped with its oracle
results. Tap room → detail + linger re-roll. `CustomPainter` +
`InteractiveViewer` (pan/zoom). State key `juice.map.v1.<sessionId>`, in
campaign export. "Add snapshot to journal" inserts a text summary entry
(journal stays text-only).

**6b Hex.** Hex grid revealed by wilderness travel: crawl env seeds start
hex; each travel roll reveals the next hex via the existing 2dF drift; Lost
marks the hex. Manual reveal/edit supported for prep. Same painter and
persistence approach.

No new table data — both consume existing verified tables. Placement
algorithms are Dart with seeded-RNG tests: determinism, full connectivity
(every room reachable), valid hex adjacency.

## Cross-cutting

- **Campaign schema v2**: phase 1 bumps the version and adds the journal;
  later phases add character blocks, encounter, and map state as *optional*
  v2 keys (no further version bumps — parsers treat absent keys as empty).
  Import accepts v1 and v2.
- **Stack rail unchanged**: parser, painters, hex math hand-rolled; deps stay
  `flutter_riverpod` + `shared_preferences` + `file_picker`.
- **Testing**: TDD per phase; widget smoke tests updated for the new shell;
  browser verify per PR; text-input flows (composer, sheet editor) get widget
  tests since headless preview cannot drive Flutter text input.
- **Docs**: README architecture section and CLAUDE.md persistence notes
  updated in the phase that changes them.

## Out of scope (v1)

Markdown rendering in journal, image attachments, map image export,
exploding/success-pool dice, point-crawl maps, per-system character
templates, encounter auto-population from monster tables, any
network/cloud features.
