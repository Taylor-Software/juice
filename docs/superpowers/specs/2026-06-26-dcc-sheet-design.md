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

`Character.dcc` triggers `DccSheet`. All DCC data lives in `Character.payload`,
keyed by a `mode` discriminator. `fromJson`/payload reads are tolerant of both
shapes and of missing class-specific keys (default to 0 / empty).

### Funnel mode (`payload['mode'] == 'funnel'`)

```jsonc
{
  "mode": "funnel",
  "peasants": [
    {
      "name": "",
      "occupation": "",     // freeform (NO Appendix L table)
      "weapon": "",         // freeform
      "tradeGoods": "",     // freeform
      "hp": 4,              // 1..8
      "str": 10, "agi": 10, "sta": 10,
      "per": 10, "int": 10, "lck": 10,   // each 3..18
      "alive": true
    }
    // up to 4 peasants
  ]
}
```

A freshly created funnel sheet pre-populates **one** empty peasant slot.

### Leveled mode (`payload['mode'] == 'leveled'`, after graduation)

```jsonc
{
  "mode": "leveled",
  "class": "Warrior",       // one of kDccClasses
  "level": 1,               // 1..10
  "alignment": "Neutral",   // one of kDccAlignments
  "occupation": "",         // carried from the graduated peasant; editable
  "luckySign": "",          // birth augur, freeform

  "str": 10, "agi": 10, "sta": 10,
  "per": 10, "int": 10,
  "lck": 10,                // current LCK (spendable; permanent in DCC)
  "lckMax": 10,             // starting LCK score (token-stepper ceiling)

  "currentHp": 6, "maxHp": 6,
  "ac": 10,
  "attackBonus": 0,
  "actionDie": "d20",       // d20 | d24 | d30 (dice chain)
  "initNote": "",           // optional freeform speed/init

  "fort": 0, "ref": 0, "wil": 0,   // save bonuses

  // Warrior / Dwarf only:
  "deedDie": "d3",          // d3 | d4 | d5 | d6 | d7

  // Wizard / Elf / Cleric (casters):
  "strBurn": 0, "agiBurn": 0, "staBurn": 0, "perBurn": 0,

  // Cleric only:
  "disapprovalRange": 1,    // 1..10

  "notes": "",

  "peasants": [ /* preserved from funnel, hidden in leveled UI — history/export */ ]
}
```

**LCK is dual-purpose in DCC** — it is both an ability score (its modifier
affects rolls) and the spendable luck-token pool (spending LCK permanently
reduces the score). So `lck` is the current/spendable value and `lckMax` is the
starting score that bounds the token stepper. There is no separate "current Luck"
field — they are the same number.

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

## UI — Class-specific mechanics (conditional on `payload['class']`)

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
- Total shown: `"Spellburn: +N"`
- Spell-check roll button → DC prompt → rolls `actionDie + level +
  castingMod + totalSpellburn`, where `castingMod = dccAbilityMod('int')` for
  Wizard/Elf and `dccAbilityMod('per')` for Cleric
- Snackbar: `"Spell check: 18 (base 12 + 6 spellburn) vs DC 14 — Success"`
- Reset button clears all burns
- Keys: `dcc-spellburn-reset`, `dcc-spell-check-roll`

### Disapproval (Cleric only)

- Range stepper (1–10), label `"1–N"`
- Roll button → `d20`; if roll ≤ range → `"Disapproval check: 4 vs 1–3 —
  Disapproval!"` else `"Safe"`
- `[+1]` increments range (after a failed casting); `[Reset]` → 1 (on rest)
- Keys: `dcc-disapproval-roll`, `dcc-disapproval-inc`, `dcc-disapproval-reset`

## Shared widget — generic luck tokens

Luck-as-spendable-token recurs across the app: Shadowdark (luck), Kal-Arath
(Fate Points), Argosa (LCK stat). Add a generic widget to
`lib/features/sheet_widgets.dart`:

```dart
Widget luckTokensSection({
  required String label,
  required int current,
  required int max,
  required VoidCallback onDecrement,   // spend one
  required VoidCallback onReset,       // restore to max
});
```

- DCC wires it to `payload['lck']` / `payload['lckMax']`, rendered inline in the
  LCK stat cell.
- **Migrate Kal-Arath and Shadowdark** to use this shared widget instead of their
  bespoke luck/fate implementations (scoped cleanup, not new feature). Their
  existing tests must still pass after migration.

This widget is the seed of the eventual custom-character-creator "luck token"
configurable option (see Deferred).

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
`addPreMadeSheet('dcc')`, seeding `payload['mode'] = 'funnel'` with one empty
peasant. Roster action id `new-dcc`, gated on the `dcc` system. Add the
`surfacesFor` row.

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
- **Shared luck widget:** decrement reduces `lck`; reset restores to `lckMax`
- **Migration regression:** existing Kal-Arath + Shadowdark luck/fate tests pass
  after switching to `luckTokensSection`

## Out of scope (deferred)

- **Custom-character-creator superset** (user follow-up): a generic creator that
  exposes the union of every sheet's configurable parts (stat blocks, save
  tracks, luck tokens, condition badges, class-conditional sections). The
  `luckTokensSection` extraction here is the first brick. Tracked separately.
- OGL-permitted P2 content: occupation table (Appendix L), spell name lists,
  mercurial magic, corruption, patrons
- Dice-chain automation beyond the action-die / deed-die pickers
- Backward compatibility for pre-release campaigns (deliberately not handled)
