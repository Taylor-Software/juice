# Contextual Generators — Design

**Status:** Approved

## Problem

The 27 content generators currently live in one standalone surface (`Ask >
Generators`, `GeneratorsScreen` — a flat list of chips across 5 sections). The
streamlining vision is to dissolve that drawer so generation happens *where you
use it*, filtered to relevance.

Investigation showed the 27 split into two kinds, which drives the design:
- **~4 entity generators** map to an existing creation point: `npc()` → the
  roster, `newScene()` → Scenes, `monsterEncounter()` → Encounter, and
  `generateName()` → any name field.
- **~23 flavor generators** (Pay the Price, Random Event, Challenge, Discover
  Meaning, Detail, Treasure, Plot Point, …) produce a **journal oracle-roll**,
  not an entity. Their natural home is the journal, reached from where you write.

So this thread re-homes generation: entity generators become contextual
create-affordances; flavor generators move to a journal-composer "inspire"
sheet; the standalone `Ask > Generators` tab is removed. No new engine code —
all generators already exist on `Oracle` and return `GenResult`.

## Scope

**In:**
- **P1 — flavor home + tab removal:**
  - A `GenerateSheet` bottom sheet listing the flavor generators grouped by
    section; tap rolls a `GenResult` and appends it to the journal via the
    existing `journalProvider.notifier.addResult` path.
  - An "inspire" button in the journal composer that opens it.
  - Remove the `Generators` tab from `OraclesTab` (Ask → Oracle / Tables /
    lonelog); drop the `gen-*` ids from `tool_registry`/`toolLocation`.
- **P2 — entity contextual affordances (generate → prefill the editable
  create dialog):**
  - Roster: "Generate NPC" → `npc()` + `generateName()` → prefilled
    New-character dialog (name + note).
  - Scenes: "Generate" → `newScene()` → prefilled scene-title dialog.
  - Encounter: "Generate" → `monsterEncounter()` → prefilled ad-hoc combatant
    dialog (name/HP).
  - Inline name roll: a dice affordance on the name field in those dialogs →
    `generateName()` fills it.

**Out (later / v2):**
- LLM-elaborated generator output (the on-device interpret already exists for
  oracle results; not wired into the generate sheet here).
- Per-system generator packs; generator favorites/history.
- Auto-linking a generated NPC to a journal mention.

## Components

### `GenerateSheet` — `lib/features/generate_sheet.dart` (new)

A `ConsumerWidget` shown via `showModalBottomSheet`. Reuses the generator
registry (move the `_Gen` list + `GenSection` out of `generators_screen.dart`
into a shared spot — see "Registry" below). Renders the **flavor** generators
(all except the entity ones consumed in P2: `npc`, `newScene`,
`monsterEncounter`, `generateName`) grouped by section. Tapping a chip:
1. rolls `gen.run(oracle)` → `GenResult`,
2. `ref.read(journalProvider.notifier).addResult(g.title, g.asText, sourceTool:
   <section id>, payload: g.toPayload())`,
3. closes the sheet (or shows the result then closes — keep simple: close +
   the entry appears in the journal).

The sheet reads `oracleProvider.valueOrNull`; if null (loading), the inspire
button is disabled / the sheet shows "still loading".

### Registry — `lib/engine/generator_registry.dart` (new, pure-ish)

Extract the `GenSection` enum, its labels, and the generator list (currently
private `_gens` in `generators_screen.dart`) into a shared module so both the
(retained) any callers and `GenerateSheet` use one source. Each entry:
`(String label, GenSection section, GenResult Function(Oracle) run)`. A
`flavorGenerators` getter excludes the four entity generators by label/run.
This is the only "engine-ish" change and it is a move, not new logic.

### Journal composer — `lib/features/journal_screen.dart`

Add an "inspire" `IconButton` (Tabler `auto_awesome`/sparkles) to `_composerBar`
beside the existing dice button. `onPressed` → `showModalBottomSheet(builder:
GenerateSheet)`. No other composer change.

### Ask tab — `lib/features/oracles_tab.dart`

Remove the `generators` `SubtabDef` + `GeneratorsScreen` child. Ask becomes
Oracle / Tables (/ lonelog). The system-aware `initialTabIndex` math still holds
(dnd/shadowdark → tables index; else 0). `GeneratorsScreen` itself can be
deleted once nothing references it (the registry it held moves to
`generator_registry.dart`).

### Tool registry — `lib/shared/tool_registry.dart` + `destination.dart`

Remove the `gen-story` / `gen-npcs` / `gen-exploration` / `gen-encounters` /
`gen-details` `ToolDef`s and their `toolLocation` entries. The inspire sheet is
their replacement; they no longer have a tab home.

### Entity affordances (P2)

Each reuses the existing create dialog, prefilled:
- `tracker_screen.dart` (CharactersPane): a "Generate NPC" action (in the add
  flow / FAB menu) rolls `npc()` + `generateName()`, then opens the existing
  `_EditDialog` with `initialA` = generated name, `initialB` = the npc result's
  `asText`; on save it creates a generic character (existing path).
- `scenes_pane.dart`: a "Generate" button beside *New scene* rolls `newScene()`
  and opens the new-scene dialog with the title prefilled from the result
  summary/title.
- `encounter_screen.dart`: a "Generate" affordance on the ad-hoc add rolls
  `monsterEncounter()` and prefills the ad-hoc dialog name (HP left to the user).
- Inline name roll: add a trailing dice `IconButton` to the name `TextField`
  in the character `_EditDialog` and the scene dialog → `generateName()` →
  `controller.text = result.summary`.

All entity affordances guard `oracleProvider.valueOrNull == null` → no-op.

## Data flow

Composer inspire → `GenerateSheet` → `oracle.<flavorGen>()` →
`journalProvider.addResult`. Entity affordance → `oracle.<entityGen>()` →
prefill existing create dialog → existing `add*`/`addScene`/`addCombatant`.

## Error handling

- Oracle still loading: inspire button disabled; entity "Generate" is a no-op
  (matches the assistant-rail convention `oracleProvider.valueOrNull == null`).
- Empty/blank prefilled name after a roll: the create dialog's existing
  validation applies (no entity created on empty).

## Testing

- `generate_sheet_test.dart` — sheet lists flavor generators (and NOT the four
  entity ones); tapping a chip adds a journal entry with the right `sourceTool`;
  override `oracleProvider` with the asset fixture (`dart:io` read, no rootBundle
  hang) per the assistant-rail tests.
- `generator_registry_test.dart` — `flavorGenerators` excludes exactly `npc` /
  `newScene` / `monsterEncounter` / `generateName`; the full list still has 27.
- Ask tab: update `oracles_tab`/`party_oracles_tab` tests — no `Generators`
  tab; Oracle/Tables present; system-aware default still correct.
- `destination_test` — `gen-*` removed from `toolLocation` (assert absent).
- P2: widget tests that "Generate NPC" opens the dialog prefilled and saving
  creates a character; the scene/encounter prefill; the inline name dice fills
  the field. Pump panes directly (not the full shell) with `oracleProvider`
  overridden.
- Full suite green; `dart format` + `flutter analyze` clean.

## Docs

- `CLAUDE.md` note: generators re-homed — flavor in the journal-composer inspire
  sheet (`GenerateSheet`, registry in `generator_registry.dart`), entity
  generators as contextual prefill affordances; `Ask > Generators` removed;
  `gen-*` tool ids dropped.
- No new licensed content — generators are existing authored tables.
