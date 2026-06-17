# D&D 5e spell slots — Slice C, P2a (lean)

**Date:** 2026-06-17
**Status:** Design approved, pending spec review
**Builds on:** `docs/superpowers/specs/2026-06-17-dnd5e-sheet-design.md` (D&D 5e P1 core sheet, shipped in PR #72)

## Context

D&D P1 shipped a core-playable sheet with everything except the content-heavy
extras (spells/attacks/equipment), all deferred to P2. This is **P2a**, the first
P2 increment: **spell slots** for spellcasting characters.

The licensing split established during brainstorming: spell **slots** are
game-mechanic *facts* (per-class slot tables) → authored Dart constants, **no
vendored SRD data, no `build_dnd.py`, no CC-BY attribution** (exactly the P1
approach). The spell **list/picker** (which reproduces SRD spell text) is the part
that forces the vendored data rail + attribution — that is **P2b**, out of scope
here. The app already has a pattern for in-app attribution when we do need it
(`moves_screen.dart` / `sidekick_screen.dart` render a license line from the
data's `meta`), so P2b has a clear home later.

## Goal & success criteria

A D&D character whose class is a spellcaster gets a **Spellcasting** section on the
sheet: a spell-slot grid (used/max per spell level, derived max from class+level),
Warlock Pact Magic where applicable, and derived spell save DC / spell attack
bonus / spellcasting ability. Non-casters (Fighter, Barbarian, Monk, Rogue) see no
spellcasting section.

Done when:

1. `DndSheet` gains spell state: `spellSlotsUsed` (9 entries), `pactSlotsUsed`,
   `preparedSpells` (freeform). Additive, tolerant, round-trips, **no schema bump**.
2. Derived (never stored): spellcasting ability + modifier (from class),
   `spellSaveDC = 8 + profBonus + mod`, `spellAttackBonus = profBonus + mod`,
   per-level slot **max** (from the class's slot table at the character's level),
   Warlock pact slot count + slot level.
3. The Spellcasting section renders only for caster classes; slot steppers expend
   /recover slots (remaining = max − used, clamped); the section is absent for the
   premade Fighter.
4. `flutter analyze` + `flutter test` clean; no rootBundle in tests.

## Non-goals

- The spell **list/picker** with SRD spell names + descriptions (P2b — needs the
  vendored 5e-bits data rail `build_dnd.py` + the CC-BY-4.0 attribution notice,
  read from `SRD_CC_v5.1.pdf`).
- Attacks table, equipment/currency (later P2 increments).
- Multiclass spell-slot aggregation, ritual/concentration tracking, prepared-spell
  count enforcement — freeform `preparedSpells` text covers solo needs.

## Architecture

### Model — `lib/engine/models.dart`

Authored constants (facts; no SRD prose):

```
const kDndSpellcastingAbility = {  // the 8 SRD caster classes → ability id
  'Bard':'cha','Sorcerer':'cha','Warlock':'cha','Paladin':'cha',
  'Cleric':'wis','Druid':'wis','Ranger':'wis','Wizard':'int' };
const kDndFullCasterClasses = {'Bard','Cleric','Druid','Sorcerer','Wizard'};
const kDndHalfCasterClasses = {'Paladin','Ranger'};
// kDndFullCasterSlots: 20 rows × 9 (spell levels 1..9) by character level.
// kDndHalfCasterSlots: 20 rows × 5 (Paladin/Ranger; none at L1).
// kDndPactSlots: 20 rows of (count, slotLevel) for Warlock.
```

Add to `DndSheet` (flat fields, mirroring the rest of P1):

```
List<int> spellSlotsUsed   // length 9, each 0..slotMax(level+1); default all 0
int pactSlotsUsed          // 0..pactMax; default 0
String preparedSpells      // freeform; default ''
```

Derived getters on `DndSheet`:
```
bool   get isCaster              => kDndSpellcastingAbility.containsKey(className);
String?get spellcastingAbility   => kDndSpellcastingAbility[className];
int?   get spellcastingMod       => isCaster ? abilityMod(spellcastingAbility!) : null;
int?   get spellSaveDC           => isCaster ? 8 + proficiencyBonus + spellcastingMod! : null;
int?   get spellAttackBonus      => isCaster ? proficiencyBonus + spellcastingMod! : null;
int    slotMax(int spellLevel)   // 1..9 → from full/half table by className + level; 0 if none
int    get pactSlotCount         // Warlock pact slots at this level (0 if not Warlock)
int    get pactSlotLevel         // Warlock pact slot spell-level
```

Conventions match the rest of `DndSheet`: `copyWith`/`maybeFromJson` clamp
`spellSlotsUsed` to length 9 with each entry ≥0, `pactSlotsUsed` ≥0; `toJson`
omits them when all-zero/empty; tolerant parse. (Used-not-remaining is stored so a
level-up naturally grants more max without rewriting state; a long rest = set used
back to 0.)

### UI — `lib/features/dnd_sheet.dart`

Insert a **Spellcasting** section (between Skills/Conditions and Notes — placement
finalized in the plan) rendered **only when `s.isCaster`**:
- A derived header line: `Spell save DC {dc} · Spell attack {+atk} · {ABILITY}`.
- For Warlock: a Pact Magic row — `Pact slots: used/{count} (level {slotLevel})`
  via `intStepper` (key `dnd-pact`).
- Otherwise: a slot row per spell level `L` where `slotMax(L) > 0` — label
  `Lv L`, an `intStepper` (key `dnd-slot-L`) adjusting `spellSlotsUsed[L-1]`, and a
  `remaining/max` display (remaining = max − used).
- A freeform `TextFormField` (key `dnd-prepared`) → `preparedSpells`.

Reuses `intStepper`; one small inline slot-row builder. No new shared widget.

### No data rail / attribution

No `build_dnd.py`, no `assets/dnd_*.json`, no provider, no pubspec change, no
attribution. All facts are authored consts (P2b owns the vendored-content rail).

## Testing

- **Model** (`test/character_sheet_test.dart`): slot-table verify (full-caster L1
  level-1 slots = 2; L5 = `[4,3,2,0,0,0,0,0,0]`; L20 = `[4,3,3,3,3,2,2,1,1]`;
  half-caster L1 = all 0, L2 lvl-1 = 2, L20 lvl-5 = 2; Warlock L1 = 1 slot @1,
  L11 = 3 @5, L20 = 4 @5); `isCaster` true for Wizard/false for Fighter;
  `spellSaveDC`/`spellAttackBonus`/`spellcastingMod` for a known build; `slotMax`
  clamps used; round-trip + tolerant parse (junk → defaults, length-9 enforced);
  `toJson` omits when all-zero.
- **Widget** (`test/character_sheet_ui_test.dart`): a Wizard character shows the
  Spellcasting section + the derived DC; a slot stepper expends/persists; a
  Warlock shows a Pact Magic row; the premade Fighter shows **no** spellcasting
  section. No rootBundle.
- **Gate:** `flutter analyze` clean, `flutter test` green.

## Risks / open points

- **Slot-table correctness** is the main risk — pinned by the verify test above
  against the standard SRD full/half/pact tables.
- **Section placement / sheet length:** the D&D sheet is already long; the
  spellcasting section adds rows for casters only. The lazy-ListView scroll-to-tap
  test pattern (`scrollUntilVisible`) applies.
- **`spellSlotsUsed` length drift:** always normalized to 9 in `copyWith`/
  `maybeFromJson` so a stored short/long list can't break indexing.
