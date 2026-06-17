# D&D 5e character sheet — Slice C, P1 (core playable)

**Date:** 2026-06-17
**Status:** Design approved, pending spec review
**Slice:** C of the pre-made-character-sheets feature (first non-Ironsworn system)

## Context

Slice A shipped bespoke sheets for the Ironsworn family (Classic #69, Starforged
#70, Sundered Isles #71) over the generic `Character` model. Slice C adds the
first **d20** system — **D&D 5e** — which shares none of the Ironsworn lineage:
6 ability scores with derived modifiers, classes/levels, AC, HP, saving throws,
skills with proficiency/expertise, conditions. It needs its own bespoke
`DndSheet` and its own opt-in system flag.

Research (with an adversarial license/scope check) established:

- **Edition:** target **D&D 5e SRD 5.1 (2014 rules)**. SRD 5.1 is CC-BY-4.0.
  SRD 5.2.1 (2024 rules) is also CC-BY-4.0 but has **no structured JSON** source
  yet, so 2014 is the practical target and matches the data we'd vendor in P2.
- **The P1 de-risking insight:** a genuinely-playable core sheet needs **no
  vendored SRD content and no attribution**. The P1 facts — the 12 class names +
  hit die + the two save proficiencies each, the 18 skill→ability map, the 15
  conditions, the proficiency-bonus-by-level table — are short *game-mechanic
  facts* (not copyrightable SRD prose). We author them directly in Dart, exactly
  like `kIronswornDebilities` / `kStarforgedImpacts`. The character's
  features/traits are freeform text the **user** types.
- Vendored 5e-bits SRD JSON (spell text, class-feature text, race traits,
  pickers) + a `build_dnd.py` rail + the CC-BY attribution notice are **P2** —
  needed only when we reproduce SRD prose.

## Goal & success criteria

With a new opt-in `dnd` system enabled on a campaign, a player can create a
pre-made D&D 5e character in one tap and play from a bespoke sheet: 6 ability
scores with live modifiers, derived proficiency bonus, AC, HP + hit dice, six
saving throws and eighteen skills (with proficiency/expertise), passive
perception, conditions, death saves, and a freeform features block.

Done when:

1. A new **opt-in `dnd` system** (NOT in `kAllSystems`, like `lonelog`/`hexcrawl`)
   can be enabled at campaign create and via the Edit-systems dialog.
2. With `dnd` enabled, the Threads & Characters create chooser offers **D&D 5e**,
   which creates a `Character` carrying a pre-filled `DndSheet` (standard array
   15/14/13/12/10/8 assigned to a Fighter, level 1, sensible defaults) and opens
   the bespoke editor.
3. The sheet edits ability scores (1..30) with **correct** live modifiers,
   class/subclass/level/race/background/alignment, AC, HP (current/max/temp),
   hit-dice remaining, speed, save proficiencies, skill proficiency + expertise,
   conditions + exhaustion (0..6), death saves (0..3 each), inspiration, and a
   features text block. Proficiency bonus, ability mods, save/skill bonuses, and
   passive perception are derived (shown, not stored).
4. A non-D&D character still opens its existing sheet (Ironsworn/Starforged/
   generic), unchanged.
5. JSON round-trips, tolerates malformed data, rides campaign export/import with
   no schema bump. `flutter analyze` + `flutter test` clean.

## Non-goals (this slice / P1)

- **Spellcasting** (slots grid + spell list) — its own later sub-object
  `DndSpellSheet`.
- **Attacks table** and **equipment/currency** — freeform features/notes for now.
- **Vendored SRD content + `build_dnd.py` + CC-BY attribution** — P2 (only when
  we reproduce SRD prose / add class/race/spell pickers with real text).
- **SRD 5.2.1 / 2024 rules.**
- Auto-applying racial ASIs, point-buy/rolled creation, AC-from-armor modelling.

## Architecture

### Game-mechanic constants — `lib/engine/models.dart`

Authored consts (facts, no SRD prose), mirroring `kIronswornDebilities`:

```
const kDndClasses = ['Barbarian','Bard','Cleric','Druid','Fighter','Monk',
  'Paladin','Ranger','Rogue','Sorcerer','Warlock','Wizard'];

const kDndClassHitDie = {Barbarian:12, Fighter:10, Paladin:10, Ranger:10,
  Bard:8, Cleric:8, Druid:8, Monk:8, Rogue:8, Warlock:8, Sorcerer:6, Wizard:6};

const kDndClassSaves = {  // the two save-proficiency ability ids per class
  Barbarian:{str,con}, Fighter:{str,con}, Cleric:{wis,cha}, Paladin:{wis,cha},
  Warlock:{wis,cha}, Sorcerer:{con,cha}, Bard:{dex,cha}, Monk:{str,dex},
  Ranger:{str,dex}, Rogue:{dex,int}, Druid:{int,wis}, Wizard:{int,wis} };

const kDndAbilities = ['str','dex','con','int','wis','cha'];  // labels: STR…CHA

const kDndSkills = [  // 18 skills → governing ability (id, label, ability)
  (athletics, STR), (acrobatics,sleight_of_hand,stealth → DEX),
  (arcana,history,investigation,nature,religion → INT),
  (animal_handling,insight,medicine,perception,survival → WIS),
  (deception,intimidation,performance,persuasion → CHA) ];

const kDndConditions = { 15 official: blinded, charmed, deafened, frightened,
  grappled, incapacitated, invisible, paralyzed, petrified, poisoned, prone,
  restrained, stunned, unconscious, exhaustion-tracked-separately };

const kDndProfBonusByLevel = [2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,6,6,6,6]; // L1..20
```

(`int` is a Dart type name and can't be a field identifier — ability scores are
therefore stored in a `Map<String,int> abilities` keyed by the 6 ability ids,
which also unifies them with the save/skill ability keys.)

### Data model — `DndSheet`

```
class DndSheet {
  Map<String,int> abilities;  // keys str/dex/con/int/wis/cha, each 1..30, default 10
  String className;           // one of kDndClasses (default 'Fighter')
  String subclass;            // blank until L3
  int level;                  // 1..20
  String race, background, alignment;  // freeform
  int ac;                     // user-editable (no armor modelling)
  int currentHp, maxHp, tempHp;
  int hitDiceRemaining;       // 0..level
  int speed;                  // default 30
  int initiativeOverride;     // 0 = use DEX mod
  Set<String> saveProficiencies;   // subset of the 6 ability ids
  Set<String> skillProficiencies;  // subset of the 18 skill ids
  Set<String> skillExpertise;      // subset of skillProficiencies
  Set<String> conditions;     // ids from kDndConditions
  int exhaustionLevel;        // 0..6
  int deathSaveSuccesses, deathSaveFailures;  // 0..3
  bool inspiration;
  int xp;                     // optional; 0 for milestone play
  String featuresText;        // freeform: class features, racial traits, feats, attacks

  // Derived (computed, never stored):
  int abilityMod(String id) => (((abilities[id] ?? 10) - 10) / 2).floor();  // NOTE: .floor(), not ~/
  int get proficiencyBonus => kDndProfBonusByLevel[(level - 1).clamp(0,19)];
  int get hitDie => kDndClassHitDie[className] ?? 8;
  int get initiative => initiativeOverride != 0 ? initiativeOverride : abilityMod('dex');
  int saveBonus(String ability) => abilityMod(ability) + (saveProficiencies.contains(ability) ? proficiencyBonus : 0);
  int skillBonus(String skillId);   // abilityMod(gov) + profBonus*(expertise?2:proficient?1:0)
  int get passivePerception => 10 + skillBonus('perception');

  factory DndSheet.premade();  // Fighter, std array, level 1, defaults
}
```

**Critical: the ability-modifier formula is `((score − 10) / 2).floor()`** — NOT
`(score − 10) ~/ 2`. Dart's `~/` truncates toward zero, which is wrong for odd
scores below 10 (score 7 → must be −2, `~/` yields −1; score 1 → −5, `~/`
yields −4). A model test pins scores 1→−5, 7→−2, 8→−1, 10→0, 15→+2, 20→+5.

Conventions match `IronswornSheet`/`StarforgedSheet`: `toJson` omits empty
sets/default scalars; `maybeFromJson` returns null for non-Map, clamps all ints,
drops unknown skill/save/condition ids and coerces `className` to a known class
(default 'Fighter'); `copyWith` clamps. Additive optional field on `Character`
(`DndSheet? dnd`) — same param→field→conditional-`toJson`→tolerant-`maybeFromJson`
→`copyWith(clearDnd)` wiring as `ironsworn`/`starforged`. **No schema bump.**

`premade()` defaults: className Fighter; abilities STR15/DEX13/CON14/INT8/WIS12/
CHA10; level 1; maxHp = `10 + conMod` (12), currentHp 12, hitDiceRemaining 1; AC
16; speed 30; saveProficiencies {str,con}; skillProficiencies {athletics,
perception}; everything else empty/zero.

### New opt-in `dnd` system flag

Mirror `lonelog`/`hexcrawl` (NOT added to `kAllSystems`):
- `lib/shared/home_shell.dart`: add `'dnd'` to `kSystemBlurbs`; add the checkbox
  (default off) to `NewCampaignDialog` add-ons + its result set; add a row to
  `_EditSystemsDialog`.
- No `rulesetsProvider` involvement (that's Ironsworn-family-only); D&D has no
  ruleset toggle in P1 (no vendored data).

### UI — `lib/features/dnd_sheet.dart` (new) + `tracker_screen.dart`

- **Render branch** (`CharactersPaneState.build`): add `if (c.dnd != null) →
  DndSheetView` ahead of the generic fallback (order: starforged → ironsworn →
  dnd → generic).
- **Create flow:** `_onAdd` guard becomes `systems.contains('ironsworn') ||
  systems.contains('dnd')`. When `dnd` is enabled the chooser shows a **D&D 5e**
  button (key `new-dnd`) → `_newDnd()` → `CharacterNotifier.addDnd()` (mirrors
  `addStarforged`) → opens. (Generic/Ironsworn/Starforged options appear per
  their own flags.)
- **`DndSheetView`** (ConsumerWidget), sections: header + rename (class dropdown
  from `kDndClasses`, level/subclass/race/background/alignment fields);
  Ability Scores (6 `abilityScoreBox` — score stepper + derived mod);
  Combat (AC, initiative, speed via `intStepper`; HP current/max/temp via a new
  `hpRow`; hit-dice type label + remaining `intStepper`); Saving Throws (6
  `savingThrowRow` — proficiency toggle + derived bonus); Skills (18 `skillRow` —
  proficiency + expertise toggles + derived bonus; passive perception line);
  Conditions (`toggleChips` over `kDndConditions` + exhaustion `intStepper` 0..6 +
  death-save successes/failures `intStepper` 0..3 + inspiration toggle); Features
  & Traits (freeform text). Edits persist via `replace(c.copyWith(dnd: …))`.

**Widgets — reuse vs new:**
- Reuse from `sheet_widgets.dart`: `sheetSection`, `intStepper`, `toggleChips`,
  `renameDialog`.
- New (in `dnd_sheet.dart`): `abilityScoreBox` (score + derived mod), `skillRow`,
  `savingThrowRow`, `hpRow` (current/max/temp). `meterStepper` is NOT reused
  (its 0..5 box model doesn't fit D&D) and is left untouched.

### No data rail this slice

No `build_dnd.py`, no `assets/dnd_*.json`, no `dndDataProvider`, no
`pubspec.yaml` change, no CC-BY attribution. All P1 facts are authored consts.

## Testing

- **Model** (`test/character_sheet_test.dart`): `abilityMod` boundary table
  (1→−5, 7→−2, 8→−1, 10→0, 15→+2, 20→+5); `proficiencyBonus` by level;
  `saveBonus`/`skillBonus`/`passivePerception` derivations incl. expertise;
  `premade()` defaults; JSON round-trip; tolerant parse (junk → null; unknown
  skill/condition ids dropped; bad className → 'Fighter'; clamps);
  `Character.copyWith` set + `clearDnd`; null omitted from `toJson`.
- **Widget** (`test/character_sheet_ui_test.dart`): open a D&D character → bespoke
  sheet; ability stepper updates the shown modifier + persists; AC/HP/level
  steppers persist; save proficiency toggle changes the shown save bonus; skill
  proficiency + expertise toggles change the skill bonus; condition toggle;
  death-save + exhaustion steppers; the `dnd`-gated create flow makes a premade
  D&D character; a non-D&D character is unaffected. No rootBundle (P1 reads no
  asset — nothing to override).
- **Systems** (extend `test/home_shell_test.dart` if it covers the systems
  dialogs): `dnd` checkbox enables the system.
- **Gate:** `flutter analyze` clean, `flutter test` green.

## Risks / open points

- **Modifier formula** — the single most important correctness detail; pinned by
  the boundary test above. (The research brief had it wrong as `~/`.)
- **Create-chooser growth** — Generic/Ironsworn/Starforged/D&D could be up to 4–5
  buttons when multiple systems are on; `AlertDialog` actions wrap via
  `OverflowBar`, no crash. If it gets unwieldy, switch to a `SimpleDialog` list
  (not now).
- **P2 attribution gate (documented, not built):** before P2 ships any vendored
  SRD prose, the exact CC-BY-4.0 attribution notice must be read from the
  official `SRD_CC_v5.1.pdf` (secondary sources disagree on the URL) and shipped
  in an About/legal screen, and `open5e`/`5e-bits` license terms re-confirmed.
- **Class change vs stored proficiencies:** changing `className` updates the
  derived hit die but does NOT rewrite the stored save/skill proficiency sets
  (user-controlled; `premade()`/create pre-fills class defaults once). Documented
  so it isn't mistaken for a bug.
