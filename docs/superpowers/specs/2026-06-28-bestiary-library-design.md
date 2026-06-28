# Bestiary Library (Tier-2.5)

**Date:** 2026-06-28
**Status:** Approved (batch consent + scope confirmed: app-global); shipped.
**Part of:** GM-tool epic — the final item of the Tier-2 batch.

## Summary

An **app-global** saved-creature library. Save a combatant (with its stat block)
to the bestiary, then add it to any encounter later — across campaigns. Reuses
the `StatBlock` model; facts-only (the GM authored the stat block).

## Decisions

- **Scope: app-global** (user choice). Key `juice.bestiary.v1`, NOT
  session-scoped, NOT part of campaign export — a bestiary is reusable across
  campaigns (same posture as `aiEnabledProvider`).
- **Model:** `Creature {id, name, statBlock (StatBlock), maxHp}` — a named stat
  block plus a default HP used to seed a combatant's track. Tolerant JSON; empty
  statBlock / zero maxHp omitted.
- **Store:** `BestiaryNotifier extends AsyncNotifier<List<Creature>>` /
  `bestiaryProvider` — `add(Creature)`, `remove(id)`, persists the list as JSON.
- **No dedicated management screen** — save from the encounter, pick/delete from
  the add picker. Edit = re-save (facts-only, lean).

## UI (`lib/features/encounter_screen.dart`)

- **Save:** a `bookmark_add` row button (`enc-save-bestiary-<id>`, shown only when
  the combatant has a non-empty stat block) → `bestiaryProvider.add(Creature(name,
  statBlock, maxHp = track.max))` + a confirmation snackbar.
- **Add:** a 4th `_addButtons` entry `Bestiary` (`add-bestiary`) → a
  `_BestiaryPickerDialog` (ConsumerWidget) listing saved creatures (`bestiary-pick-
  <id>`, subtitle AC/HP) with a per-row delete (`bestiary-del-<id>`). Tap a row →
  `addCombatant(Combatant(name, initiative: 0, track: maxHp>0 ? HP track : null,
  statBlock))`. Empty library → a hint to save one first.

## Testing

- Model: `Creature` JSON round-trip + tolerant (non-map/missing-name → null; empty
  statBlock + zero hp omitted).
- Notifier: `add`/`remove` persist; re-read in a fresh container confirms the
  app-global key.
- Encounter widget: save a combatant-with-statblock → bestiary has it (name/ac/hp);
  add-from-bestiary → picker shows the creature → tap → a combatant is added with
  the HP track + stat block.

## Out of scope

- Per-campaign or hybrid storage (chose app-global).
- A dedicated bestiary-management screen, in-place editing, dedup, import/export of
  the library, categories/tags.
- Rollable attacks (still display text; needs a parser).
