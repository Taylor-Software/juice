# Spec: Optional Ironsworn-family rulesets

Status: draft · 2026-06-11
Covers: Ironsworn, Ironsworn: Delve, Starforged, Sundered Isles —
moves and oracle tables, individually toggleable.

## Problem statement

Ironsworn-family players are the largest openly-licensed solo-RPG
community, and they journal — threads, vows, NPCs — which is exactly
what our Tracker does. Today they get nothing from us; juice-roll
offers them dice math but no moves text, no oracles, no journal.
Supporting these rulesets turns our journaling differentiator into a
multi-system home base instead of a Juice-only niche.

## Goals

1. A player can enable any licensed ruleset and get its full moves
   list (browsable, rollable) and oracle tables (rollable) offline.
2. Juice-only users see zero change: no new tabs, no payload growth,
   no settings noise beyond one "Rulesets" entry.
3. All ruleset content ships from Datasworn (official JSON), never
   hand-transcribed — correctness by construction, updatable by
   re-running the build pipeline.
4. App remains free, offline, server-less, with correct attribution.

## Non-goals (v1)

- **Character sheets / assets**: stats are entered at roll time
  (stepper inputs), not stored. Asset cards are a large content and UI
  surface; revisit after moves prove out.
- **Progress track automation**: Threads can represent vows manually;
  rank/ticks mechanics deferred (P2 — design Thread model so a rank
  field can be added without migration).
- **Momentum tracking**: burn-momentum math shown on result, but no
  persistent momentum meter without character state (P2).
- **Mixing base games in one view**: see exclusivity rules.

## Ruleset toggles and exclusivity

Settings → Rulesets:

| Toggle | Rule |
|---|---|
| Juice | always on (the app's core) |
| Ironsworn | base game; mutually exclusive with Starforged |
| Ironsworn: Delve | requires Ironsworn on; auto-off when Ironsworn turns off |
| Starforged | base game; mutually exclusive with Ironsworn |
| Sundered Isles | requires Starforged on; auto-off when Starforged turns off |

Mutual exclusivity of the two base games keeps moves/oracle lists
coherent (no fantasy/sci-fi interleave) and matches how the games are
played. Enforced in the settings UI: enabling one base game disables
the other (with its expansion) after a confirm dialog. Toggles are
global in v1; stored per-session once Sessions ship (a campaign is
one ruleset family).

## Data pipeline

- New `build_datasworn.py` (sibling of `build_oracle.py`): reads
  Datasworn JSON packages (`ironsworn-classic`,
  `ironsworn-classic-delve`, `starforged`, `sundered-isles`), emits
  one compact asset per ruleset: `assets/ruleset_<id>.json`
  containing move categories → moves (markdown text, roll type,
  stat options) and oracle collections → tables (d100 ranges, roll
  templates).
- Self-verifies like `build_oracle.py`: every oracle covers 1–100
  with no gaps/overlaps, every move has a known roll type
  (action / progress / no-roll), attribution `source` present on
  every item.
- Assets lazy-load on toggle enable (keeps Juice-only startup
  payload unchanged).

## Mechanics (engine additions)

- **Action roll**: 1d6 + stat + adds vs 2d10. Strong hit (beats
  both), weak hit (beats one), miss (beats neither); match flag on
  equal challenge dice. Burn-momentum comparison shown when the
  entered momentum would improve the outcome.
- **Progress roll**: entered progress score vs 2d10, same outcome
  ladder.
- **Oracle roll**: d100 against ranged tables; supports
  roll-twice/template results (Datasworn `oracle_rolls` templates).

All pure functions in `lib/engine/`, unit-tested with seeded RNG and
outcome-distribution checks (mirroring the Fate Check test approach).

## UI

- **Moves tab** appears in the NavigationBar only when a base
  ruleset is enabled (Juice-only stays 4 tabs). Categorized list →
  move detail (markdown) → inline roll controls (stat/adds steppers)
  → result card with outcome + match, bookmarkable to Log.
- **Tables tab** gains a ruleset section listing its oracle
  collections, same browse-and-roll pattern as Juice tables.
- **Attribution**: about/settings screen renders per-ruleset license
  and author lines from Datasworn `source` data.

## Requirements

**P0**
- [ ] Settings screen with the five toggles and the exclusivity rules above
- [ ] `build_datasworn.py` emits verified per-ruleset assets for all four rulesets
- [ ] Action, progress, and d100 oracle rolls in engine, tested
- [ ] Moves tab (browse, read, roll, log) for enabled rulesets
- [ ] Oracle tables rollable from Tables tab for enabled rulesets
- [ ] Delve moves/oracles merge into Ironsworn's lists when both on (likewise Sundered Isles → Starforged)
- [ ] Attribution screen; app remains free
- [ ] Juice-only experience byte-identical when all toggles off

**P1**
- [ ] Move search/filter
- [ ] Oracle "roll twice" template support beyond simple ranges
- [ ] Momentum burn suggestion on action-roll result

**P2 (architectural insurance)**
- [ ] Per-session ruleset selection (after Sessions ship)
- [ ] Progress tracks on Threads (rank + ticks + progress roll from thread)
- [ ] Asset cards

## Acceptance criteria (key flows)

- Given all ruleset toggles off, when the app launches, then tabs,
  assets loaded, and behavior match current release exactly.
- Given Ironsworn enabled, when the user enables Starforged, then a
  confirm dialog explains Ironsworn (+Delve) will turn off, and on
  confirm the Moves/Tables content swaps accordingly.
- Given Delve toggle tapped with Ironsworn off, then Ironsworn is
  offered to be enabled too (single dialog), never Delve alone.
- Given Starforged enabled, when the user rolls "Face Danger" with
  stat 2 and adds 1, then result shows action die, both challenge
  dice, total, strong/weak/miss outcome, and match flag when dice
  are equal; bookmark stores it to Log.
- Given any enabled ruleset, when the user opens attribution, then
  each enabled ruleset shows author/license/link from Datasworn
  source data.

## Licensing

- Datasworn tooling: MIT. Ruleset text: CC-BY-4.0 or CC-BY-NC-4.0,
  embedded per item in `source`. App is free (already required by
  the Mythic stance), attribution rendered in-app.
- Open question (blocking P0 ship, not start): confirm per-ruleset
  license split — verify Delve and Sundered Isles terms from the
  packages' own license files during pipeline work, and render
  whichever applies.

## Open questions

- [eng] Datasworn oracle templates: how much of the template
  grammar (`{{result>...}}` interpolation) must v1 implement vs
  flatten at build time? Prefer flattening in `build_datasworn.py`.
- [eng] Sundered Isles package maturity — pin Datasworn version in
  the build script; check whether sundered-isles is still preview.
- [product] Moves tab name when Mythic also lands later ("Moves" vs
  system-named tab).

## Phasing

1. Pipeline + engine + tests (no UI) — proves data and math.
2. Starforged-only vertical slice (toggle, Moves tab, oracles).
3. Ironsworn + Delve + Sundered Isles + exclusivity dialogs.
4. P1 polish.
