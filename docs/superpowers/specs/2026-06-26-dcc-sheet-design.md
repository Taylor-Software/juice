# Dungeon Crawl Classics (DCC) Character Sheet — Design

**Date:** 2026-06-26
**System id:** `dcc` (opt-in ruleset; NOT in `kAllSystems`)
**Status:** Design approved, pending implementation plan

## Summary

A pre-made Dungeon Crawl Classics character sheet (`lib/features/dcc_sheet.dart`,
rendered when `Character.dcc` is set). DCC's signature is the **0-level funnel**:
a player runs a small group of peasants, most die in the first dungeon, survivors
graduate to 1st level with a class. This sheet models that full arc in a single
roster entry — a funnel tracker that **graduates one survivor in place** into a
leveled hero sheet.

The sheet ships the full set of DCC interactive mechanics (save rolls, Luck
spending, Mighty Deeds deed die, spellburn, Cleric disapproval) while remaining
**facts-only** on content (no occupation table, spell lists, corruption tables,
or class-feature prose).

This is the 12th pre-made sheet, following the OSE/Knave/Nimble facts-only
pattern, and reusing the shared `sheet_widgets.dart` widgets.

## Licensing posture — facts-only

DCC's core rulebook is published under the **OGL 1.0a**, which would technically
permit reproducing the occupation table, spell lists, and class features.
However, per the repo's strict NEW-content rule (existing CC-BY datasworn is
grandfathered; everything new is facts-only), this sheet ships **zero vendored
prose**:

- **No** occupation table (Appendix L) — occupation is a freeform text field
- **No** spell names, spell lists, or spell text
- **No** corruption / mercurial-magic / patron tables
- **No** class-feature prose
- **Only** non-copyrightable game mechanics: stat names, class names, hit dice,
  dice-chain values, the ability-modifier table, save labels

The system blurb carries a courtesy non-affiliation note: **"Not affiliated with
Goodman Games."** No "compatible-with" claim (matching the strictest sheets like
Shadowdark/Kal-Arath). A richer OGL-permitted P2 (occupation table, spell name
lists) is genuinely allowed later but deliberately deferred for consistency and
speed.

## Data model

DCC follows the codebase's **typed-sheet pattern** (like `OseSheet`/`ShadowdarkSheet`),
NOT a generic payload map. A `Character.dcc` field (`DccSheet?`) is added to
`Character` alongside the existing sheet fields, wired into `forSheet`, `copyWith`
(+`clearDcc`), `toJson`, `fromJson`, and `withHpDelta`. `DccSheet` is an immutable
class with `copyWith` / `toJson` / `maybeFromJson` / `premade()`, and a `mode`
discriminator field. All numeric fields are clamped in `copyWith`/`maybeFromJson`,
and `maybeFromJson` tolerates missing keys (defaults) so both funnel and leveled
shapes round-trip.

### `DccPeasant` (a 0-level funnel character)

A small immutable value class (own `copyWith`/`toJson`/`maybeFromJson`):

```dart
class DccPeasant {
  final String name, occupation, weapon, tradeGoods;  // all freeform (NO Appendix L)
  final int hp;                                        // 1..8
  final Map<String, int> stats;                        // kDccStats keys, each 3..18
  final bool alive;
}
```

### `DccSheet`

```dart
class DccSheet {
  final String mode;            // 'funnel' | 'leveled'
  final List<DccPeasant> peasants;   // funnel roster; preserved after graduation

  // leveled fields (defaults until graduation):
  final String className;       // one of kDccClasses
  final int level;              // 1..10
  final String alignment;       // one of kDccAlignments
  final String occupation;      // carried from the graduated peasant; editable
  final String luckySign;       // birth augur, freeform
  final Map<String, int> stats; // kDccStats keys (str/agi/sta/per/int/lck), 3..18
  final int lckMax;             // starting LCK score (luck-token ceiling)
  final int currentHp, maxHp;
  final int ac, attackBonus;
  final String actionDie;       // 'd20' | 'd24' | 'd30' (dice chain)
  final String initNote;        // optional freeform speed/init
  final Map<String, int> saves; // {'fort','ref','wil'} bonuses
  final String deedDie;         // 'd3'|'d4'|'d5'|'d6'|'d7' (Warrior/Dwarf)
  final Map<String, int> burns; // spellburn {'str','agi','sta','per'} (casters)
  final int disapprovalRange;   // 1..10 (Cleric)
  final String notes;
}
```

A freshly created (`premade()`) sheet is `mode: 'funnel'` with **one** empty
`DccPeasant`. `stats['lck']` is the current/spendable LCK; `lckMax` is its
starting ceiling.

**LCK is dual-purpose in DCC** — it is both an ability score (its modifier
affects rolls) and the spendable luck-token pool (spending LCK permanently
reduces the score). So `stats['lck']` is the current/spendable value and `lckMax`
is the starting score that bounds the token stepper. There is no separate
"current Luck" field — they are the same number.

### Graduation

`DccSheet.graduate(int peasantIndex, String className, String alignment)` returns
a new `DccSheet` with `mode: 'leveled'`, the chosen class/alignment, the peasant's
6 stats copied into `stats`, `lckMax = stats['lck']`, `currentHp = maxHp =
peasant.hp`, `occupation` carried from the peasant, and the `peasants` list
preserved (hidden in leveled UI, survives export). The graduated character's
name is set on the owning `Character` (not the sheet) at the call site.

### Ability modifier table (DCC-specific — NOT the 5e table)

DCC uses a tighter modifier curve capped at ±3. This is **distinct** from the
D&D 5e `((score-10)/2).floor()` helper (which yields 18→+4, 3→−4). A dedicated
`dccAbilityMod(score)` helper implements:

| Score | Mod |
|-------|-----|
| 3     | −3  |
| 4–5   | −2  |
| 6–8   | −1  |
| 9–12  | 0   |
| 13–15 | +1  |
| 16–17 | +2  |
| 18    | +3  |

(Scores are clamped 3–18 by the steppers; the helper is defined over that range.
Game-mechanic table = non-copyrightable fact.)

## UI — Funnel sheet

Header: title "0-Level Funnel" + live survivor count (e.g., **"3 / 4 alive"**).

Each peasant is a `Card` with an `ExpansionTile` (collapsed shows name + HP +
alive badge):

**Expanded peasant card:**
- Name field
- Occupation / Weapon / Trade goods (3 freeform text fields)
- HP stepper (1–8)
- Stat row: STR / AGI / STA / PER / INT / LCK — each a stepper (3–18) with the
  derived `dccAbilityMod` shown below it
- Action row: `[Mark Dead]` (if alive) / `[Mark Alive]` (if dead) +
  `[Graduate →]` (alive only)

Dead peasants render greyed with a strikethrough name.

**Graduate flow:** `[Graduate →]` opens a dialog with a class picker
(`kDccClasses`) + alignment picker. Confirm:
1. Copies the peasant's 6 stats into the top-level payload fields
2. Sets `mode: 'leveled'`, `class`, `alignment`, `occupation` (from peasant),
   `lckMax = lck`, `maxHp = currentHp = peasant.hp`
3. Preserves the `peasants` list (hidden in leveled UI; survives in export)
4. The sheet relabels to the character's name and re-renders as the leveled sheet

**Add Peasant** button at the bottom, disabled when count == 4.

Widget keys: `dcc-peasant-<i>-graduate`, `dcc-peasant-<i>-kill`,
`dcc-peasant-<i>-revive`, `dcc-add-peasant`.

## UI — Leveled sheet (core)

Sectioned `ListView`, following the OSE/D&D layout pattern.

**Header:** character name (editable), class badge, level stepper (1–10),
alignment chip.

**Stats section** — 6 stats in a 2×3 grid (D&D-sheet pattern):
```
STR | AGI | STA
PER | INT | LCK
```
Each cell: score stepper (3–18) + derived `dccAbilityMod` label (`±N`). The LCK
cell additionally renders the generic luck-token controls inline (current/max +
spend/reset), since LCK is both stat and token. A small caption appears under the
LCK cell for **Thief / Halfling**: `"Recovers 1 / level on rest"` (no extra UI).

**Lucky Sign** — freeform text field below the stats grid (label "Lucky Sign /
Birth Augur").

**Combat section:**
- HP stepper pair (current / max)
- AC stepper
- Attack bonus stepper
- Action die picker: `d20 / d24 / d30`
- `initNote` freeform text field (optional speed/init)

**Saves section** — Fort / Ref / Will, each a bonus stepper + roll button. Tap →
number-input dialog for **DC** → rolls `d20 + bonus`, snackbar:
`"Fort: 14 vs DC 11 — Pass"` / `"Fort: 6 vs DC 11 — Fail"` (ephemeral, no journal
log). Keys: `dcc-fort-roll`, `dcc-ref-roll`, `dcc-wil-roll`.

**Occupation** — freeform text field (carried from funnel; editable).

**Notes** — freeform multiline.

## UI — Class-specific mechanics (conditional on `_s.className`)

### Mighty Deeds (Warrior / Dwarf — `kDccDeedDieClasses`)

- Deed die picker: `d3 / d4 / d5 / d6 / d7` (dice-chain progression)
- Roll button → rolls `d20 + attackBonus` AND the deed die together
- Snackbar: `"Attack: 14, Deed: 4 — Deed succeeds!"` (deed ≥ 3) or
  `"Attack: 8, Deed: 2 — Miss"`
- Keys: `dcc-deed-die-picker`, `dcc-deed-roll`

### Spellburn (Wizard / Elf / Cleric — `kDccCasterClasses`)

Burnable stats per class (`kDccSpellburnStats`): Wizard/Elf → STR/AGI/STA,
Cleric → PER.

- Each burnable stat has a "Burned" stepper inline; that stat cell displays
  `score − burned`
- Total shown: `"Spellburn: +N"` (sum of `burns` over the class's burnable stats)
- Spell-check roll button → DC prompt → rolls `dN(actionDie) + level +
  castingMod + totalSpellburn`, where `castingMod = dccAbilityMod(stats['int'])`
  for Wizard/Elf and `dccAbilityMod(stats['per'])` for Cleric
- Snackbar: `"Spell check: 18 (base 12 + 6 spellburn) vs DC 14 — Success"`
- Reset button clears all burns (sets `burns` entries to 0)
- Keys: `dcc-spellburn-reset`, `dcc-spell-check-roll`, `dcc-burn-<stat>` (steppers)

### Disapproval (Cleric only)

- Range stepper (1–10), label `"1–N"`
- Roll button → `d20`; if roll ≤ range → `"Disapproval check: 4 vs 1–3 —
  Disapproval!"` else `"Safe"`
- `[+1]` increments range (after a failed casting); `[Reset]` → 1 (on rest)
- Keys: `dcc-disapproval-roll`, `dcc-disapproval-inc`, `dcc-disapproval-reset`

## Shared widget — generic luck tokens

DCC's LCK is a spend-down-from-a-ceiling token pool with a "restore" action. Add
a generic widget to `lib/features/sheet_widgets.dart`:

```dart
Widget luckTokensSection({
  required String keyPrefix,           // e.g. 'dcc-luck'
  required String label,               // e.g. 'Luck (LCK)'
  required int current,
  required int max,
  required ValueChanged<int> onSet,    // spend/gain one (clamped 0..max by caller)
  required VoidCallback onReset,       // restore to max
});
```

- DCC wires it to `stats['lck']` / `lckMax`, rendered inline in the LCK stat cell.

**Migration is intentionally NOT forced.** A code check found the other "luck"
fields are different mechanics that do not fit a current/max/spend/restore shape:
- **Shadowdark** `luckToken` is a **bool** (a single binary reroll token).
- **Kal-Arath** `fatePoints` is an **unbounded counter** (no max, no restore).

Coercing those into this widget would distort their semantics, so they stay as-is.
This widget serves DCC now and is the seed of the eventual custom-character-creator
"luck token" configurable option (see Deferred), where the generic shape earns its
keep across user-defined sheets.

## System registration

**`lib/engine/models.dart`:**
- `kKnownSystems` += `'dcc'`
- `kSystemCategory['dcc']` = `SystemCategory.ruleset`
- `kDccClasses` = `['Warrior', 'Wizard', 'Cleric', 'Thief', 'Elf', 'Dwarf', 'Halfling']`
- `kDccClassHitDie` = `{Warrior:12, Wizard:4, Cleric:8, Thief:6, Elf:6, Dwarf:10, Halfling:6}`
- `kDccAlignments` = `['Lawful', 'Neutral', 'Chaotic']`
- `kDccStats` = `['str','agi','sta','per','int','lck']`
- `kDccStatLabels` = `{str:'STR', agi:'AGI', sta:'STA', per:'PER', int:'INT', lck:'LCK'}`
- `kDccDeedDieClasses` = `{'Warrior','Dwarf'}`
- `kDccCasterClasses` = `{'Wizard','Elf','Cleric'}`
- `kDccSpellburnStats` = `{Wizard:['str','agi','sta'], Elf:['str','agi','sta'], Cleric:['per']}`
- `dccAbilityMod(int score)` helper (the table above)

**`lib/shared/home_shell.dart`** — `kSystemBlurbs['dcc']`:
> "Dungeon Crawl Classics: 0-level funnel, dice chain, mighty deeds, spellburn,
> disapproval. Facts-only mechanics. Not affiliated with Goodman Games."

**`lib/engine/campaign_presets.dart`** — `'solo-dcc'` →
`(mode: party, systems: {dcc, juice, party})`.

**`lib/state/providers.dart`** — `CharacterNotifier.addDcc()` →
`addPreMadeSheet('dcc')`; `Character.forSheet('dcc', id)` returns
`DccSheet.premade()` (`mode: 'funnel'`, one empty peasant). Roster action id
`new-dcc` (in `tracker_screen.dart`'s add menu), gated on the `dcc` system; sheet
dispatch `if (c.dcc != null) return DccSheetView(...)`. Add the `surfacesFor` row.

**`lib/engine/system_primer.dart`** — DCC primer line:
> "Pulpy sword-and-sorcery; roll d20+mod vs DC; warriors roll a deed die;
> casters make spell checks and can spellburn; spend Luck to boost rolls;
> Fort/Ref/Will saves."

Priority sits between `shadowdark` and the Ironsworn-family in
`resolveSystemPrimer` / `resolveSystem`.

## Testing

`test/dcc_sheet_test.dart`, pumping `DccSheet` directly (per the rootBundle-hang
rule — no `JournalScreen`/`HomeShell`, no asset `.load()`):

- **Funnel:** add/remove peasant; mark dead/alive toggles survivor count;
  add-peasant disabled at 4; graduate flow flips `mode` → `leveled`, copies the 6
  stats, sets `lckMax`, `maxHp`/`currentHp`, carries occupation, preserves
  `peasants`
- **Leveled core:** `dccAbilityMod` boundary values (3→−3, 9→0, 12→0, 13→+1,
  18→+3); save roll DC-prompt → pass/fail snackbar text
- **Class gating:** deed die section renders only for Warrior/Dwarf; spellburn
  only for casters; disapproval only for Cleric; recovery caption only for
  Thief/Halfling
- **Spellburn:** burned stepper reduces displayed stat; spell-check total folds
  level + casting mod + burn; reset clears
- **Shared luck widget:** `onSet` reduces `stats['lck']`; reset restores to `lckMax`
- **Round-trip:** `DccSheet` (both funnel + leveled shapes) survives
  `toJson`→`maybeFromJson`; `Character` with a `dcc` sheet survives
  `toJson`→`fromJson`

## Out of scope (deferred)

- **Custom-character-creator superset** (user follow-up): a generic creator that
  exposes the union of every sheet's configurable parts (stat blocks, save
  tracks, luck tokens, condition badges, class-conditional sections). The
  `luckTokensSection` extraction here is the first brick. Tracked separately.
- OGL-permitted P2 content: occupation table (Appendix L), spell name lists,
  mercurial magic, corruption, patrons
- Dice-chain automation beyond the action-die / deed-die pickers
- Backward compatibility for pre-release campaigns (deliberately not handled)
