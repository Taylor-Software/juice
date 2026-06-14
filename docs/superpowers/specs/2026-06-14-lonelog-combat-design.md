# Lonelog Combat addon (P4a) — Design

**Date:** 2026-06-14
**Status:** Approved (autonomous, goal: continue to completion)
**Depends on:** P1 (lonelog flag), P3 (journal highlights the emitted block)

## Goal

When the `lonelog` system is on, "End encounter" in the Encounter Tracker writes a Lonelog
Combat-addon `[COMBAT]` block to the journal (rendered highlighted by P3) instead of the
plain one-line summary.

## Design

- **Pure serializer** `lib/engine/lonelog_combat.dart` — `encounterToLonelog(EncounterState)`:
  `[COMBAT]` / `Rd<round> Roster:` / one `[F:<name>|HP c/m, <status…>, defeated]` foe tag per
  combatant / `=> <outcome>` / `[/COMBAT]`. Names/statuses sanitized (`[`,`]`,`|`,newline)
  exactly like the export.
- **Wiring** — `EncounterScreen._endEncounter` computes
  `enabledSystems.contains('lonelog')`; when on, the journal body is `encounterToLonelog(s)`,
  else the existing summary. Unchanged otherwise (still a `text` entry via `journalProvider.add`).

## Gating

Addon features ride under the existing `lonelog` umbrella flag (no per-addon flag) — turning
on Lonelog enables its addon behaviours. (Refines the P1 "per-addon sub-toggle" idea to avoid
toggle proliferation; whole new *tools* may still get their own gate.)

## Testing
- `lonelog_combat_test.dart`: block shape with HP+status+defeated foe tags + outcome; the
  no-defeated and bare-combatant cases; delimiter sanitization.
- Existing encounter-screen tests confirm the default (lonelog-off) summary path is unchanged.

## Files
**New:** `lib/engine/lonelog_combat.dart`, `test/lonelog_combat_test.dart`.
**Edit:** `lib/features/encounter_screen.dart`.
