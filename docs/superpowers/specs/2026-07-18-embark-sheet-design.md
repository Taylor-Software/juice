# Embark 2E character sheet (facts-only P1)

**Date:** 2026-07-18
**Status:** Design — approved

## Problem

Add a pre-made **Embark** (2nd Edition) character sheet — an indie OSR fantasy
TTRPG by Infinite Fractal. Next bespoke sheet after the existing facts-only
roster (Cairn / Knave / OSE / Argosa / Nimble / Draw Steel / Shadowdark / …).
Embark is a clean, medium-lean OSR system: 4 attributes, a d12 core resolution
die, freeform skills, slot inventory, and 6 classes each with their own resource
pool.

## Licensing

Embark's **writing and game content are licensed CC BY-SA 4.0** (per its credits
page: *"free to adapt, remix, edit, or hack … as long as you provide attribution
… under CC BY-SA 4.0"*). Fully open — same tier as Cairn/Knave/OSE. Vendoring
rulebook content + carrying attribution is permitted (see [[licensing-constraint]]).
**P1 still ships facts-only** for consistency with the other P1 sheets and
fastest delivery: authored, non-copyrightable **mechanic facts only** (the 4
attribute names, the 6 class names, the core resolution rule) — NO rulebook
prose, NO content pickers. A courtesy attribution line rides `kSystemBlurbs`
(CC BY-SA requires attribution when content is reused; the mechanic facts are
non-copyrightable, but the line is cheap goodwill and consistent with the OSE
posture). A **P2** (deferred) could add Embark spell lists / monster bestiary /
magic items as a Content Library follow-up — genuinely allowed by the license.

## Approach: author names + core rule, freeform the rest

Authoritative for P1: the **attribute names** (`str/dex/wil/int`, range −1..4),
the **6 class names**, and the **core resolution rule** (d12 + attribute ≥ 8 to
succeed; each Injury is a −1 penalty to Checks). NOT asserted: per-class feature
lists, spell lists, exact starting gear — those are left **editable/freeform**
(the player fills their character's actual details). Robust without
over-asserting.

Attributes ARE the number added to the d12 (not a score→modifier curve) — so a
plain signed stepper (−1..4), like Nimble/Knave, NOT the D&D `abilityBox`.

## Architecture (mirrors the Knave / Nimble sheets)

### 1. Model + constants — `lib/engine/models.dart`

```dart
const kEmbarkStats = <String>['str', 'dex', 'wil', 'int'];
const kEmbarkStatLabels = <String, String>{
  'str': 'STR', 'dex': 'DEX', 'wil': 'WIL', 'int': 'INT',
};
const kEmbarkClasses = <String>[
  'Warrior', 'Scout', 'Mage', 'Invoker', 'Bard', 'Barbarian',
];
```

Pure helper (top-level, unit-tested) — the class's resource-pool name for the
sheet's single RESOURCE box (the official sheet unifies Grit / Spell Dice /
Flair into one box):

```dart
String embarkResourceLabel(String className) {
  switch (className) {
    case 'Warrior': return 'Grit';
    case 'Mage':
    case 'Invoker': return 'Spell Dice';
    case 'Bard': return 'Flair';
    default: return 'Resource'; // Scout (Talents) / Barbarian (Feats): no pool
  }
}
```

`class EmbarkSheet` (const ctor + `copyWith` + tolerant `maybeFromJson`/`toJson`,
mirroring `KnaveSheet`):
- `Map<String,int> stats` — the 4 attributes, default `0` each (range −1..4).
- `String className` (default `'Warrior'`).
- `int level` (default `1`, range 1..6).
- `int maxHp` (default `1`), `int currentHp` (default `1`).
- `int injuries` (default `0`, range 0..3 — third = death; each = −1 to Checks).
- `int av` (default `0`, range 0..4 — Armor Value).
- `int resource` (default `0`), `int resourceMax` (default `0`) — the
  Grit/Spell-Dice/Flair pool.
- `String skills` (''), `String languages` (''), `String sp` ('') — freeform
  (Embark skills + languages have no fixed list; SP is the currency).
- `String notes` ('') — freeform (Item Slots: 12 total / 6 body / 6 pack, noted
  in the field label).

No computed getters needed.

### 2. `Character.embark` — `lib/engine/models.dart`

Add `final EmbarkSheet? embark;` to `Character` (ctor, `copyWith` with a
`clearEmbark`), `if (embark != null) 'embark': embark!.toJson()` in `toJson`,
`embark: EmbarkSheet.maybeFromJson(j['embark'])` in `fromJson`.

`withHpDelta` gains an `embark` branch (adjusts `currentHp`) — the #121 lesson
(cover sheet pools, not just tracks).

### 3. System registration (mirror where `'knave'` appears, exactly)

- `kKnownSystems`, `kSystemCategory` (`SystemCategory.ruleset`), `kSystemBlurbs`
  (facts-only blurb + CC BY-SA attribution / non-affiliation courtesy line),
  `kSystemShortName`, `kPresetIcons`, `kSystemLabels` — add an `embark` entry
  mirroring `knave`.
- Confirm **NOT** in `kAllSystems` (opt-in only).
- `solo-embark` preset (mirror `solo-knave`) + a `surfacesFor` row.
- New-campaign wizard + edit-systems dialog: an `embark` opt-in toggle
  (mirror the `knave` add-on toggle).

### 4. System primer + QuickRef

- `lib/engine/system_primer.dart`: add an `embark` line to `kSystemPrimers`
  (e.g. *"Embark: heroic-yet-deadly OSR fantasy. Resolution: d12 + attribute
  (STR/DEX/WIL/INT) ≥ 8; advantage/disadvantage; HP + 3-Injury death track;
  slot inventory; classes with resource pools."*) + `embark` in
  `resolveSystemPrimer` / `resolveSystem` priority (place beside the other
  facts-only OSR sheets).
- `lib/engine/quick_ref.dart`: an `embark` `QuickRefCard` in `kSystemQuickRefs`
  (resolution / combat / damage-death / conditions / rest — procedures +
  generic effects only, non-copyrightable facts, matching the existing cards).

### 5. Sheet view — `lib/features/embark_sheet.dart` (new)

`EmbarkSheetView` (ConsumerWidget, mirroring `KnaveSheetView`):
- `sheetNameHeader` + `Text('Embark', labelSmall)`.
- `embark-class` `DropdownButton` (`kEmbarkClasses`); `embark-level` stepper (1..6).
- A `Wrap` of 4 attribute blocks (`embark-stat-<key>` stepper, range −1..4) each
  with a **Check** roll button (`embark-check-<key>`): rolls `d12 + stat −
  injuries`, snackbar `"STR: 11 — Success"` (≥ 8 Success else Failure). Ephemeral,
  no journal log (matches Knave/Argosa saves).
- HP steppers (`embark-hp` current / `embark-maxhp`).
- **Injuries** stepper (`embark-injuries`, 0..3) with a note *"3rd Injury = death;
  each Injury = −1 to Checks"* — the signature death track.
- `embark-av` stepper (0..4).
- **Resource** stepper pair (`embark-resource` cur / `embark-resourcemax` max),
  labeled by `embarkResourceLabel(className)` — the Grit/Spell-Dice/Flair box.
- `embark-sp` freeform (SP); `embark-skills` + `embark-languages` freeform
  (multi-line).
- Shared `conditionsSection(context, ref, character, 'embark')`.
- `embark-notes` freeform (label notes the 12 Item Slots / 6 body / 6 pack).
- All edits persist via `CharacterNotifier.replace(character.copyWith(embark:
  _s.copyWith(...)))`.

### 6. Render + creation

- Sheet dispatch (wherever `KnaveSheetView` is returned): add
  `if (c.embark != null) return EmbarkSheetView(character: c, onBack: …);`.
- `CharacterNotifier.addEmbark` (mirror `addKnave`) → new `Character` with
  `embark: const EmbarkSheet()`, role `pc`.
- Roster Add affordance gated on the `embark` system (mirror `new-knave`).

## Testing

- `EmbarkSheet` model round-trip (`toJson`→`maybeFromJson`, tolerant of junk /
  missing keys; defaults applied).
- `Character` round-trip carries `embark`.
- `withHpDelta` adjusts an embark character's `currentHp`.
- `embarkResourceLabel` mapping (pure).
- `EmbarkSheetView` widget test (override data providers per the rootbundle-hang
  note; enable no AI needed): class dropdown persists; a stat stepper persists;
  HP + Injuries steppers persist; rendered under the `embark` system.

## Out of scope (P2, deferred — ALLOWED by CC BY-SA)

- Embark spell lists (Arcane / Divine / the Bard Spoken-Spell d8+d100 generator),
  monster bestiary (Content Library `foes_embark.json`), magic items, the NPC
  generator tables, class-feature text + pickers, asset ruleset, level-up
  automation.

## Files touched

| File | Change |
|------|--------|
| `lib/engine/models.dart` | `kEmbarkStats`/`kEmbarkStatLabels`/`kEmbarkClasses`, `embarkResourceLabel`, `EmbarkSheet`, `Character.embark`, `withHpDelta` branch, system-label/known-systems registries |
| `lib/engine/system_primer.dart` | `embark` primer + `resolveSystemPrimer`/`resolveSystem` |
| `lib/engine/quick_ref.dart` | `embark` QuickRef card |
| `lib/features/embark_sheet.dart` | NEW — `EmbarkSheetView` |
| `lib/features/tracker_screen.dart` (or sheet dispatch) | render `EmbarkSheetView`; roster creation |
| `lib/state/providers.dart` | `CharacterNotifier.addEmbark` |
| creation wizard + edit-systems dialog | `embark` opt-in toggle |
| tests | model + `Character` round-trip, `withHpDelta`, `embarkResourceLabel`, `EmbarkSheetView` widget |
