# Shadowdark character sheet — Slice C (lean, facts-only)

**Date:** 2026-06-17
**Status:** Design approved, pending spec review
**Builds on:** the D&D 5e P1 sheet pattern (`docs/superpowers/specs/2026-06-17-dnd5e-sheet-design.md`)

## Context

Shadowdark RPG (The Arcane Library) is the third originally-requested system.
It is a lean OSR d20-ish game. The sheet reuses the established bespoke-sheet
pattern (optional typed field on `Character` + new opt-in system flag + render
branch + create chooser + `sheet_widgets.dart`), exactly like Ironsworn /
Starforged / D&D.

### Licensing — the load-bearing constraint (verified)

Unlike Ironsworn/Starforged (CC-BY) and D&D (CC-BY SRD 5.1), **Shadowdark has no
open/CC license**. Its **Third-Party License V1.1 explicitly excludes
character-builder apps / digital tools** — those require *direct, case-by-case
written permission* from The Arcane Library (which existing tools obtained
individually). The app owner has chosen to proceed **without** that permission,
on the **facts-only** basis:

- Bare game-mechanic **facts** are not copyrightable (idea/expression
  dichotomy; Baker v. Selden): the six ability names, the four class names
  (Fighter/Priest/Thief/Wizard), the six ancestries, three alignments, hit dice
  by class, the ability-modifier rule, gear-slots = `max(STR,10)`, the luck
  token, level cap 10, and the cast rule `DC = 10 + spell tier`. These we author.
- **Copyrightable expression we must NOT ship:** the 120-entry **Title table**
  (invented flavor titles), talent text, spell descriptions, deity names/lore,
  class-feature prose. These are **freeform user-entered text** — the app ships
  none of them and provides no pickers.
- The app must NOT use the Shadowdark logo/wordmark or claim "compatible with
  Shadowdark RPG." The system is named "Shadowdark" descriptively in the picker.

This is grayer than the CC-BY systems; it is a deliberate, owner-approved risk
posture. If real talent/spell/title content is ever wanted, it requires Arcane
Library permission (a separate slice) — out of scope here.

## Goal & success criteria

With a new opt-in `shadowdark` system enabled, the player creates a pre-made
Shadowdark character in one tap and plays from a bespoke sheet: six ability
scores with modifiers, class/ancestry/alignment, level/XP, AC/HP, gear slots,
luck token, and freeform title/deity/background/talents/spells.

Done when:

1. Opt-in `shadowdark` system (NOT in `kAllSystems`) is toggleable in the New
   campaign + Edit-systems dialogs.
2. With it enabled, the create chooser offers **Shadowdark**, which creates a
   `Character` with a pre-filled `ShadowdarkSheet` (L1 Human Fighter, abilities
   10s, HP from the d8) and opens the bespoke editor.
3. The sheet edits: 6 ability scores (1..20) with live modifiers; class /
   ancestry / alignment (dropdowns from the fact lists); level (1..10) / XP;
   AC; HP (current/max); gear-slots used (vs derived capacity); luck token
   (0/1); and freeform title, deity, background, talents, spells.
4. A non-Shadowdark character still opens its existing sheet, unchanged.
5. JSON round-trips, tolerant parse, rides campaign export/import, no schema bump.
   `flutter analyze` + `flutter test` clean.

## Non-goals

- Talent / spell / title **pickers** or any Shadowdark prose (licensing — needs
  Arcane Library permission).
- The 120-entry title table (creative expression → Title is freeform).
- A gear catalog, deity list, ancestry-ability automation, multi-source content.

## Architecture

### Constants (facts only) — `lib/engine/models.dart`

```
const kShadowdarkClasses = ['Fighter', 'Priest', 'Thief', 'Wizard'];
const kShadowdarkAncestries =
    ['Dwarf', 'Elf', 'Goblin', 'Half-Orc', 'Halfling', 'Human'];
const kShadowdarkAlignments = ['Lawful', 'Neutral', 'Chaotic'];
const kShadowdarkClassHitDie = {Fighter:8, Priest:6, Thief:4, Wizard:4};
const kShadowdarkCastingAbility = {Priest:'wis', Wizard:'int'};
```

The six ability ids/labels are the generic stat set already in `models.dart`
(`kDndAbilities` / `kDndAbilityLabels` — plain `str..cha` / `STR..CHA`, not
D&D-specific); reuse them. The modifier rule `((score - 10) / 2).floor()`
reproduces Shadowdark's printed −4..+4 band table exactly for scores 3..18, so
it is used directly (a mechanic, not the printed table).

### Data model — `ShadowdarkSheet`

```
class ShadowdarkSheet {
  Map<String,int> abilities;     // 6 ids, each 1..20, default 10
  String className;              // kShadowdarkClasses, default 'Fighter'
  String ancestry;               // kShadowdarkAncestries, default 'Human'
  String alignment;              // kShadowdarkAlignments, default 'Neutral'
  int level;                     // 1..10
  int xp;                        // >=0
  int ac;                        // user-editable
  int currentHp, maxHp;
  int gearSlotsUsed;             // 0..capacity
  bool luckToken;
  String title, deity, background, talentsText, spellsText;  // freeform

  int abilityMod(String a) => ((score(a) - 10) / 2).floor();
  int get gearSlotCapacity => score('str') > 10 ? score('str') : 10;
  int get hitDie => kShadowdarkClassHitDie[className] ?? 8;
  bool get isCaster => kShadowdarkCastingAbility.containsKey(className);
  String? get castingAbility => kShadowdarkCastingAbility[className];
  int? get castingMod => isCaster ? abilityMod(castingAbility!) : null;
  factory ShadowdarkSheet.premade();   // L1 Human Fighter, 10s, HP=8
}
```

Conventions mirror `DndSheet`/`IronswornSheet`: `toJson` omits empty/default;
`maybeFromJson` returns null for non-Map, clamps all ints, coerces
class/ancestry/alignment to a known value (else the default); `copyWith` clamps;
abilities normalized to the 6 keys. Additive optional `Character.shadowdark`
(param → field → conditional `toJson` → tolerant `maybeFromJson` →
`copyWith(clearShadowdark)`), same wiring as `dnd`. **No schema bump.**

### New opt-in `shadowdark` system flag

Mirror the `dnd` flag (NOT in `kAllSystems`): `kSystemBlurbs['shadowdark']`
(neutral wording, no logo/"compatible" claim), a `NewCampaignDialog` add-on
checkbox (default off) + its result-set entry, and an `_EditSystemsDialog` row.

### UI — `lib/features/shadowdark_sheet.dart` (new) + `tracker_screen.dart`

- **Render branch** (`CharactersPaneState.build`): add `if (c.shadowdark != null)
  → ShadowdarkSheetView` alongside the others.
- **Create flow:** `_onAdd` guard also allows `shadowdark`; a `new-shadowdark`
  chooser button (guarded by `systems.contains('shadowdark')`) →
  `_newShadowdark()` → `CharacterNotifier.addShadowdark()` → opens.
- **`ShadowdarkSheetView`** (ConsumerWidget): header (rename + class/ancestry/
  alignment dropdowns + level stepper + freeform title/deity[if Priest]/
  background); Ability Scores (6 boxes: score stepper + derived mod); Combat
  (AC / HP current+max / XP via `intStepper`); Gear & Luck (gear-slots used
  stepper + derived "/ capacity"; luck-token toggle); Talents (freeform);
  Spellcasting (casters only: freeform spells + a derived "casts d20 + WIS/INT
  vs DC 10 + tier" line); Notes. Reuses `sheetSection`/`intStepper`/`toggleChips`/
  `renameDialog`; one small local ability-box widget. Keys `sd-`-prefixed.

No `build_*.py`, no `assets/`, no `pubspec` change, no attribution.

## Testing

- **Model** (`test/character_sheet_test.dart`): `abilityMod` boundary (3→−4,
  7→−2, 10→0, 18→+4); `gearSlotCapacity` (STR 8→10, STR 15→15); `isCaster` +
  `castingAbility`/`castingMod` (Wizard→int, Fighter→none); `premade` defaults;
  round-trip; tolerant parse (junk→null; bad class/ancestry/alignment→default;
  clamps); `Character.copyWith` set + `clearShadowdark`; null omitted from toJson.
- **Widget** (`test/character_sheet_ui_test.dart`): open a Shadowdark character →
  bespoke sheet; ability stepper updates mod + persists; class dropdown changes
  derived hit-die/caster-ness; a caster (Wizard) shows the Spells section + cast
  line, a non-caster (Fighter) does not; gear-used + luck toggle persist; the
  `shadowdark`-gated create flow makes a premade character; a non-Shadowdark
  character is unaffected. No rootBundle.
- **Systems** (`test/home_shell_test.dart`): the `shadowdark` checkbox enables
  the system.
- **Gate:** `flutter analyze` clean, `flutter test` green.

## Risks / open points

- **Licensing posture** (documented above) is the chief risk — owner-accepted,
  facts-only, no prose/title-table/logo. Keep it that way; any future content
  picker is a separate, permission-gated slice.
- **Shared ability-box widget:** D&D and Shadowdark both want a "score + derived
  mod" box. To avoid churning the merged `dnd_sheet.dart`, this slice writes a
  small local box; extracting a shared `abilityScoreBox` into `sheet_widgets.dart`
  is a future cleanup, not done here (YAGNI).
- **Modifier formula:** same `floor((score-10)/2)` as D&D — correct for the
  Shadowdark band table over 3..18; a model boundary test pins it.
