# Custom / Homebrew Character Sheet — Design

**Date:** 2026-06-26
**System id:** `custom` (opt-in ruleset; NOT in `kAllSystems`)
**Status:** Design approved, pending implementation plan

## Summary

A user-defined "Custom / Homebrew" character sheet
(`lib/features/custom_sheet.dart`, rendered when `Character.custom` is set). It
exposes the **superset** of configurable mechanics found across the 11 existing
pre-made sheets (plus the spec'd DCC sheet), so a player can assemble a sheet for
an unsupported game without code.

A custom sheet is an **ordered list of configurable blocks** plus a live values
map. The same screen renders two ways: an **Edit** mode authors the schema
(add / configure / reorder / delete blocks), a **Play** mode uses it. Creation
offers a small set of **starter templates** that pre-seed the block list, then the
user customizes inline.

This is the generic creator deferred from the DCC spec
(`docs/superpowers/specs/2026-06-26-dcc-sheet-design.md`, "Out of scope"). It is
built on the shared `sheet_widgets.dart` bricks and introduces the
`luckTokensSection` brick that DCC also adopts.

## Scope (P1)

Eleven of the twelve surveyed block types ship in P1; only the **computed badge**
(derived read-only values like Knave `10+CON` slots or Argosa "Staggered") is
deferred, because it requires a cross-block reference / expression engine.

P1 block types: **stat, counter, hp, roll (with degrees), luck, conditions,
dropdown, freeform, timer, togglechips, progress.**

## Licensing posture — facts-only

The custom sheet ships **zero game content**. Every label, stat name, class
option, and condition is authored by the user at runtime. The four starter
templates contain only **generic, non-copyrightable mechanics** (e.g. "6 stats,
3–18, 5e modifier", "roll-under d20", "2d6 + stat") with **no game names, no
prose, no setting**. This is the strictest facts-only posture — there is nothing
to attribute because nothing is vendored.

## Data model

`Character.custom` triggers `CustomSheet` (a typed sheet field alongside
`Character.dnd`, `Character.shadowdark`, etc.). The sheet is:

```dart
class CustomSheet {
  final List<CustomBlock> blocks;       // the user-authored schema; order matters
  final Map<String, dynamic> values;    // live play state, keyed by block.id
}

class CustomBlock {
  final String id;                      // stable; keys into CustomSheet.values
  final CustomBlockType type;           // enum (see catalog)
  final String label;                   // user-facing heading
  final Map<String, dynamic> config;    // per-type configuration (see catalog)
}

enum CustomBlockType {
  stat, counter, hp, roll, luck, conditions,
  dropdown, freeform, timer, togglechips, progress,
}
```

- `id` is generated once at block creation (via the existing id helper used for
  characters / journal entries) and never changes, so reorders and config edits
  never orphan a value.
- `values` is `dynamic` per block (int, String, `List`, `Map`, `Set`-as-`List`).
  Each block type defines its own value shape and default.
- `toJson` / `fromJson` are tolerant: an unknown `type` string drops the block
  (forward-compat), a missing value falls back to the type default, malformed
  config falls back to an empty config (which renders with sane defaults). Pattern
  matches the rest of the app's `maybeFromJson` sheets.
- Persistence and export are free: `CustomSheet` rides the existing `Character`
  JSON the same way every other sheet does. No new SharedPreferences key.

## Block catalog

Every block type implements the same uniform contract: **{ config shape · value
shape · default value · play renderer · config editor }**. The play renderer and
config editor are small `switch`-on-`type` dispatchers in `custom_sheet.dart`.

| Type | Config | Value shape (default) | Reused brick |
|---|---|---|---|
| `stat` | `stats: [{key,label}]`, `min`, `max`, `modFormula` | `{key: int score}` (mid of range) | `statStepper` / `abilityBox` |
| `counter` | `min`, `max`, `step` | `int` (`min`) | `intStepper` |
| `hp` | `allowTemp: bool` | `{cur,max,temp?}` (`{0,0}`) | `intStepper` pair |
| `roll` | `rows: [{label,bonus}]`, `RollConfig` (§Roll model) | ephemeral — snackbar only | new `rollTrackRow` |
| `luck` | — | `{cur,max}` (`{0,0}`) | **new** `luckTokensSection` |
| `conditions` | — | shared `Character.conditions` (not in `values`) | `conditionsSection` |
| `dropdown` | `options: [String]` | selected `String` (`''`) | `DropdownButton` |
| `freeform` | `multiline: bool` | `String` (`''`) | `TextField` |
| `timer` | `start: int` | `int` count (`start`); lit = `>0` | torch −/+ pattern |
| `togglechips` | `options: [String]` | `List<String>` selected (`[]`) | `toggleChips` |
| `progress` | — | `List<ProgressTrack>` (`[]`) | `progressTrackRow` |

Notes:

- **stat** is the only block needing the modifier math (§Modifier formulas). It
  renders one stepper per stat with the derived modifier shown below, in a Wrap so
  any stat count fits a phone width.
- **conditions** has no per-block value — it edits the shared
  `Character.conditions` via `showConditionsEditor`, like every other sheet. At
  most one conditions block is meaningful; the editor allows duplicates but they
  reflect the same underlying set (acceptable, not guarded in P1).
- **timer** reuses the Shadowdark `torch` interaction (−/+ with a lit/out
  indicator); it is the per-sheet timer, distinct from the global `lightProvider`.
- **progress** reuses `progressTrackRow` + `addProgressTrackDialog` from
  `sheet_widgets.dart`; tracks serialize via the existing `ProgressTrack` JSON.

## Modifier formulas

`stat` blocks pick one `modFormula` (an enum) applied to every stat in the block:

| Enum | Formula | Source sheet |
|---|---|---|
| `raw` | none — show score only | Ironsworn family |
| `fived` | `((s - 10) / 2).floor()` | D&D 5e, Shadowdark |
| `dccTight` | ±3 table (3→−3 … 18→+3) | DCC |
| `scoreIsMod` | identity (`s`) | Nimble, Knave |
| `halfFloor` | `(s / 2).floor()` | Argosa-style |

A pure `customStatMod(formula, score)` helper, unit-tested at boundary values. The
`dccTight` branch reuses the same table the DCC sheet defines (shared helper).

## Roll model

A `roll` block holds **rows** (each a label + its own integer `bonus`) and one
shared `RollConfig`. Tapping a row's roll button produces an **ephemeral
snackbar** (no journal log) of the form `"<row label>: <total> — <outcome>"`.

`RollConfig`:

- `dice`: `{count, sides}` — e.g. `1d20`, `2d6`, `2d10` (default `1d20`).
- `addBonus`: `bool` — add the row's `bonus` to the rolled total.
- `direction`: `high` (compare total, `≥`) | `low` (roll-under: compare the raw
  dice result, `≤`).
- `target`: `fixed(int)` | `prompt` (ask a DC each roll) | `rowValue` (use the
  row's own `bonus` field as the target — i.e. roll-under-stat).
- `ladder`: optional ordered **outcome bands** for degrees (empty → simple
  Pass/Fail vs `target`):
  - `high`: bands `[{atLeast: int total, label}]`, evaluated high→low, with a
    catch-all bottom band.
  - `low`: bands `[{atMostFraction: double of target, label}]`, evaluated
    low→high (e.g. `0.5 → "Great"`, `1.0 → "Success"`).
- `crit`: `none` | `matchingDice` (all dice equal — 2d6 doubles, etc.) |
  `natural` (single-die max = crit success, min = crit fail). A crit overrides the
  band label with "Critical Success" / "Critical Failure".

This is **deliberately self-contained**: a roll row carries its own number, so
there are **no cross-block stat references and no expression parser** (the same
heavy bucket as the deferred computed badge). The rolling primitives reuse the
existing `Dice` engine.

Coverage proof (every observed mechanic maps to a `RollConfig`):

| Game | dice | addBonus | direction | target | ladder / crit |
|---|---|---|---|---|---|
| Cairn save | 1d20 | off | low | rowValue | — |
| Argosa | 1d20 | off | low | rowValue | `0.5→"Great Success", 1.0→"Success"` |
| D&D / DCC save | 1d20 | on | high | prompt (DC) | — |
| OSE save | 1d20 | off | high | fixed | — |
| Knave save | 1d20 | on | high | fixed (11) | — |
| PbtA move | 2d6 | on | high | — | `10→"Strong hit", 7→"Weak hit", 0→"Miss"` |
| Kal-Arath | 2d6 | on | high | fixed (8) | crit `matchingDice` (6-6 / 1-1) |
| Draw Steel | 2d10 | on | high | — | `17→"Tier 3", 12→"Tier 2", 0→"Tier 1"` |

A pure `resolveRoll(config, row, rolledDice, promptedTarget?)` →
`(total, outcomeLabel)` is the single tested seam; the widget only renders its
output.

## UI — inline editor

`custom_sheet.dart` is a `ConsumerStatefulWidget` (it owns the local
`_editing` flag). The shared `sheetNameHeader` gains a trailing Play⇄Edit toggle
(`custom-mode-toggle`).

**Play mode** — a `ListView` rendering each block's play widget in order, no
authoring chrome. This is the everyday sheet.

**Edit mode** — a `ReorderableListView` of block cards. Each card shows the block
label, a drag handle (reorder), a ⚙ button (opens the type-specific config
dialog), and a 🗑 delete. A footer `+ Add block` button (`custom-add-block`) opens
a type picker (`SimpleDialog` of the 11 types); choosing one appends a block with
default config + default value and immediately opens its config dialog.

Config dialogs are small and type-specific (e.g. stat → edit the stat-key list +
min/max + modFormula dropdown; dropdown/togglechips → edit the options list; roll
→ edit rows + the `RollConfig` fields). Every change persists immediately via
`charactersProvider.notifier.replace(character.copyWith(custom: next))`.

Widget keys: `custom-mode-toggle`, `custom-add-block`, `custom-block-<id>-config`,
`custom-block-<id>-delete`, and per-block play keys namespaced by block id
(e.g. `custom-<id>-stat-<key>-plus`, `custom-<id>-roll-<rowIndex>`).

## Templates

Creation (`addCustom`) shows a starter picker (`SimpleDialog`) sourced from a pure
`lib/engine/custom_templates.dart` (`kCustomTemplates`). Each template is just a
pre-seeded `List<CustomBlock>` (generic mechanics, no game names):

1. **Blank** — empty; opens straight into Edit mode.
2. **Generic d20** — stat (6 stats, 3–18, `fived`), hp (cur/max), counter "AC",
   roll "Saves" (3 rows, 1d20+bonus vs prompt DC), conditions, freeform "Notes".
3. **OSR roll-under** — stat (3 stats, 3–18, `raw`), roll "Saves" (1d20 low,
   rowValue), hp, conditions, freeform "Notes".
4. **2d6 PbtA** — stat (stats `scoreIsMod`), roll "Moves" (2d6+bonus high, ladder
   10/7/miss), conditions, freeform "Notes".

A test validates every template's blocks round-trip and reference only known
block types / formulas, so templates can't drift from the model.

## Shared widget — `luckTokensSection`

Add to `lib/features/sheet_widgets.dart` (the brick the DCC spec promised):

```dart
Widget luckTokensSection({
  required String label,
  required int current,
  required int max,
  required VoidCallback onDecrement,   // spend one
  required VoidCallback onReset,       // restore to max
});
```

The custom `luck` block wires it to its `{cur,max}` value. DCC adopts it when
built; there is no ordering dependency between the two specs (whichever lands
first creates the widget).

## System registration

- **`lib/engine/models.dart`**: `kKnownSystems += 'custom'`;
  `kSystemCategory['custom'] = SystemCategory.ruleset`; `Character.custom` field +
  `copyWith` + `maybeFromJson`; `CustomBlockType` enum; `customStatMod` helper;
  template/roll model types may live in `models.dart` or a sibling engine file as
  the plan decides.
- **`lib/state/providers.dart`**: `CharacterNotifier.addCustom({templateId})` →
  `addPreMadeSheet('custom')` seeding the chosen template's blocks. Roster action
  `new-custom`, gated on the `custom` system. Add the `surfacesFor` row.
- **`lib/shared/home_shell.dart`**: `kSystemBlurbs['custom']` →
  "Custom / Homebrew: build your own sheet from configurable blocks — stats,
  HP, rolls, luck, timers, conditions. Facts-only; you author all content."
- **`lib/engine/campaign_presets.dart`**: `'solo-custom'` →
  `(mode: party, systems: {custom, juice, party})`.
- **`lib/engine/system_primer.dart`**: the custom sheet contributes **no** system
  primer (no fixed setting/resolution to assert) — `resolveSystemPrimer` skips it,
  and the AI falls back to its generic grounding. Lowest/absent priority.

## Testing

`test/custom_sheet_test.dart`, pumping `CustomSheet` directly (per the
rootBundle-hang rule — no `JournalScreen`/`HomeShell`, no asset `.load()`):

- **Model:** `CustomSheet` round-trips through JSON; tolerant `fromJson` drops an
  unknown block type and defaults a missing value; reorder/delete preserve other
  blocks' values by id.
- **Modifier:** `customStatMod` boundary values for all five formulas.
- **Roll:** `resolveRoll` for each row of the coverage table (Cairn, Argosa great,
  DC prompt, OSE fixed, Knave, PbtA bands, Kal-Arath crit doubles, Draw Steel
  tiers); snackbar text on a rendered `roll` block.
- **Blocks:** each block type renders in Play mode and edits via its config dialog
  in Edit mode (add stat key, change range, edit dropdown options, step a counter,
  spend/reset luck, toggle a chip, tick a progress track, run down a timer).
- **Editor:** mode toggle hides/shows chrome; add-block appends with defaults;
  delete removes; reorder persists.
- **Templates:** each `kCustomTemplates` entry seeds valid blocks and round-trips.

## Phasing (for the implementation plan)

- **P1a — Foundation:** data model (`CustomSheet`/`CustomBlock`/enums),
  serialization, `customStatMod`, the Play⇄Edit editor framework, and the four
  core blocks (stat, counter, freeform, conditions). System registration + a
  Blank-only creation path. Ships a usable (if minimal) custom sheet.
- **P1b — Full block set:** hp, luck (+`luckTokensSection`), dropdown, timer,
  togglechips, progress, and the `roll` block with the full degrees/crit model.
- **P1c — Templates:** `custom_templates.dart` + the starter picker on creation.

## Out of scope (deferred)

- **Computed badge** — derived read-only values (Knave `10+CON` slots, Argosa
  "Staggered") needing cross-block references / an expression engine.
- **Cross-block references in rolls** — roll rows stay self-contained (their own
  number); referencing a stat block's score is the same expression-engine bucket.
- **Sharing / importing custom schemas** between campaigns or users.
- **Conditional sections** (DCC-style class-gated blocks) — every block always
  shows; the user adds/removes manually.
- **Backward compatibility** for pre-release campaigns (deliberately not handled).
