# Generalized 0-Level Funnel — Design

**Date:** 2026-06-27
**System id:** `funnel` (opt-in tool; NOT in `kAllSystems`)
**Status:** Design approved, pending implementation plan

## Summary

Generalize the DCC 0-level **funnel** (run a pack of doomed peasants, kill most,
promote survivors into full characters) into a **system-agnostic** feature any
game can use. A funnel becomes its own standalone roster entity (`Character.funnel`)
that **spawns new hero Characters** of any enabled sheet system when survivors
graduate. Each sheet system contributes a small `FunnelProfile` (what its peasants
look like + how to build one of its heroes from a survivor).

This **replaces** the DCC-specific funnel: `DccSheet` loses its funnel mode and
becomes leveled-only; the funnel logic + DCC's peasant fields move into the generic
`FunnelSheet` + a DCC `FunnelProfile`. All 12 sheet systems register a profile in
P1.

This is the funnel generalization deferred from the DCC spec
(`docs/superpowers/specs/2026-06-26-dcc-sheet-design.md`). It is distinct from, and
composes with, the in-progress Custom/homebrew sheet
(`docs/superpowers/specs/2026-06-26-custom-character-creator-design.md`).

## Decisions (from brainstorming)

1. **Graduate target:** any enabled sheet system, chosen at graduation; survivor
   stats map into that sheet.
2. **DCC's funnel:** replaced by the generic funnel (one codebase, no duplication).
3. **Peasant schema:** per-system **funnel profiles** declare peasant stat keys +
   flavor fields + HP rule + a graduate-mapper.
4. **P1 coverage:** all 12 sheet systems get a profile + mapper.
5. **Entry/gating:** opt-in `funnel` system (tools), also surfaced at campaign
   creation.
6. **Graduation cardinality:** **spawn a new hero, funnel stays** — graduate
   multiple survivors into separate roster Characters; the funnel persists until
   the user deletes it.

## Data model

A funnel is a **standalone roster entity** via a new typed sheet field
`Character.funnel` (sibling of `.dcc`, `.dnd`, …), wired exactly like the other
sheets (constructor param, field, `forSheet`, `copyWith` + `clearFunnel`, `toJson`,
`fromJson`, tolerant `maybeFromJson`). New engine types live in
`lib/engine/funnel.dart` (pure).

```dart
class FunnelSheet {
  final String seedSystem;            // which system's profile shaped the peasants
  final List<FunnelPeasant> peasants;
}

class FunnelPeasant {
  final String name;
  final int hp;                       // death tracking
  final bool alive;
  final bool graduated;               // promoted already → not graduable again
  final Map<String, int> stats;       // keyed by the seed profile's stat keys
  final Map<String, String> flavor;   // keyed by the seed profile's flavor fields
}
```

- Immutable value classes with `copyWith` / `toJson` / `maybeFromJson` (same pattern
  as `OseSheet`/`DccSheet`). All numeric fields clamped; `maybeFromJson` returns
  null for a non-map and tolerates missing keys.
- `FunnelSheet.premade(String seedSystem)` seeds **one** empty peasant from the
  seed profile's defaults (stat keys at mid-range, flavor fields empty, hp at
  `hpMin`, alive, not graduated).
- `Character.funnel` rides the existing `Character` JSON; no new SharedPreferences
  key. `withHpDelta` ignores funnel Characters (peasant HP is edited in the funnel
  UI, not via the party-effect broadcast).
- A funnel Character has `funnel != null` and no other sheet field set. Graduating
  does **not** mutate the funnel Character's identity — it creates a separate hero
  Character.

## Per-system funnel profiles

`lib/engine/funnel.dart` holds the extension point. Each sheet system registers a
`FunnelProfile`:

```dart
class FunnelProfile {
  final String system;                                   // 'dcc', 'dnd', …
  final List<({String key, String label})> statKeys;     // peasant stats
  final int statMin, statMax;                            // stepper bounds
  final List<({String key, String label})> flavorFields; // extra text fields
  final int hpMin, hpMax;                                // peasant HP bounds
  final List<FunnelChoice> graduateChoices;              // graduation dropdowns
  final Character Function(String id, FunnelPeasant p, Map<String, String> picks)
      graduate;                                          // builds the target hero
}

class FunnelChoice {
  final String key, label;        // e.g. 'class' / 'Class'
  final List<String> options;     // e.g. kDccClasses
}
```

- Registry: a `const`/final `kFunnelProfiles` map (system → profile) + a lookup
  `funnelProfileFor(String system)` (returns null for unprofiled systems). **All 12
  sheet systems** register one in P1.
- **`graduate(id, peasant, picks)`** builds the hero: `Character.forSheet(system,
  id)` then `copyWith` the target sheet, mapping `peasant.stats` **by matching key**
  into that sheet's stat storage (same key → copy, clamped to the sheet's range;
  unmatched key → sheet default), setting the peasant's HP into the sheet's HP pool
  where one exists, and applying `picks` (class/alignment/ancestry/…). The hero's
  `name` carries from the peasant (falling back to a system default if blank).
- **Per-system specifics** (illustrative — the plan pins exact stat-storage fields
  per sheet):
  - DCC: statKeys `kDccStats` (6), flavor occupation/weapon/tradeGoods, hp 1–8,
    choices class (`kDccClasses`) + alignment (`kDccAlignments`); graduate = the old
    `DccSheet.graduate` logic (copy stats, set `lckMax`, hp, occupation).
  - D&D: statKeys = `kDndAbilities` (6), flavor background, choices class; graduate
    maps abilities, sets currentHp/maxHp.
  - Shadowdark: 6 abilities, choices class + ancestry + alignment.
  - Cairn: 3 stats (str/dex/wil), choices background.
  - Ironsworn/Starforged: the 5 stats; **no** class choice (empty `graduateChoices`);
    HP maps to the health meter.
  - Remaining systems (Nimble, Draw Steel, Argosa, Knave, OSE, Kal-Arath) follow the
    same shape against their own stat keys + class/archetype choices.
- Each profile is small + pure → unit-testable in isolation. The **seed** profile
  shapes peasant creation; the **target** profile (chosen at graduation, defaulting
  to the seed) builds the hero. Same-system graduation is 1:1; cross-system is
  best-effort by key (documented; no rename table).

## UI — funnel sheet & graduation

`lib/features/funnel_sheet.dart` → `FunnelSheetView` (a `ConsumerWidget` reading
`character.funnel!` directly; parent rebuilds on edit — same pattern as the other
sheet views). The seed system's profile drives which fields render.

**Header:** "0-Level Funnel — <seed system>", a live count
`"3 / 5 alive · 1 graduated"`.

**Per peasant** — a `Card`/`ExpansionTile` (key `funnel-peasant-<i>`):
- Name field; one text field per profile `flavorFields`; HP stepper
  (`hpMin..hpMax`).
- A stat row (a `Wrap`): one stepper per profile `statKeys` (labels from the
  profile, bounds `statMin..statMax`).
- State buttons: `Mark dead` / `Mark alive` (`funnel-peasant-<i>-kill` / `-revive`);
  **`Graduate →`** (`funnel-peasant-<i>-graduate`, shown only when alive and not yet
  graduated).
- Graduated peasants render with a "graduated" badge + disabled controls; dead
  peasants render greyed with a strikethrough name.

**Add peasant** button (`funnel-add-peasant`), capped at `kFunnelMaxPeasants`
(default 6).

**Graduate dialog** (opened from a peasant's Graduate button):
1. **Target system** dropdown — the campaign's enabled sheet systems that have a
   profile; defaults to the funnel's `seedSystem`.
2. The selected target profile's `graduateChoices` dropdowns (class/alignment/…),
   re-rendered when the target changes.
3. Confirm (`funnel-graduate-confirm`) → `profile.graduate(newId, peasant, picks)`
   → the new hero Character is **added to the roster** (top, like other adds); the
   peasant is marked `graduated` (funnel `copyWith`); the funnel entry persists. A
   snackbar confirms `"<name> graduated as a <system> <class>"`.

The funnel never auto-deletes — the user removes it via the normal roster delete
when the session-zero is done. Roster grouping: a funnel Character shows under a
dedicated "Funnels" affordance or the NPC group (plan decides; not load-bearing).

## System registration & campaign creation

**Opt-in `funnel` system** (`SystemCategory.tools`, NOT in `kAllSystems`):
- `lib/engine/models.dart`: `kKnownSystems += 'funnel'`;
  `kSystemCategory['funnel'] = SystemCategory.tools`.
- `lib/shared/home_shell.dart`: `kSystemBlurbs['funnel']` → "0-Level Funnel: run a
  pack of doomed peasants, then graduate survivors into full characters of any
  enabled system."

**Roster entry point** (`lib/features/tracker_screen.dart`): when `funnel` is
enabled, the Add menu gains **"0-Level Funnel"** (`new-funnel`). Choosing it opens a
**seed-system picker** (the enabled sheet systems that have a profile) → creates a
`Character.funnel` via `CharacterNotifier.addFunnel(seedSystem)` seeded from that
profile (one empty peasant). Sheet dispatch: `c.funnel != null → FunnelSheetView`.

**DCC change:** "Add DCC" now creates a leveled DCC hero directly (no auto-funnel).
To funnel into DCC, enable `funnel` and seed it with DCC.

**Campaign creation** ("ask at new campaign"):
- `funnel` appears as a **tools chip** (`cat-funnel`) in the `NewCampaignDialog`
  Custom picker; the live preview pane shows a "0-Level Funnel" Sheet-surface row
  when enabled (via a `surfacesFor` row, `requiresSystem: 'funnel'`).
- The **`solo-dcc` preset gains `funnel`** so DCC's iconic funnel is on
  out-of-the-box (preserving today's experience).
- A new **`solo-funnel` preset** — "Character funnel → any system" (mode party,
  systems `{funnel, juice, party}`; the player adds a ruleset) — gives funnels a
  one-tap start.

**Primer/AI:** `funnel` contributes no system primer (it's a tool, no setting);
`resolveSystemPrimer`/`resolveSystem` skip it.

## DCC refactor specifics

- **Removed from `DccSheet`:** `mode`, `peasants`, `graduate()`, `isFunnel`, and the
  `DccPeasant` class (the generic `FunnelPeasant` replaces it). `DccSheet` is now
  always the leveled hero; `premade()` returns a level-1 hero.
- **`Character.forSheet('dcc')`** → a leveled DCC hero (`name: 'New DCC character'`).
- **DCC `FunnelProfile`** (in `funnel.dart`) carries the moved bits (stat keys, the
  occupation/weapon/tradeGoods flavor, hp 1–8, class + alignment choices) and a
  `graduate` reproducing the old DCC promotion (copy stats, `lckMax`, hp,
  occupation).
- **`DccSheetView`** drops its funnel branch (`_buildFunnel`/`_peasantCard`/
  `_graduateDialog` removed); renders the leveled sheet only.
- The DCC funnel/graduate tests move to the funnel test files (exercised through the
  generic path + DCC profile); `dcc_sheet_test.dart`/`_ui_test.dart` keep only
  leveled coverage.

## Testing

`test/funnel_test.dart` (model/unit) + `test/funnel_sheet_ui_test.dart` (widget,
pumping `FunnelSheetView` directly per the rootBundle-hang rule — no
`JournalScreen`/`HomeShell`, no asset `.load()`):

- **Model:** `FunnelSheet`/`FunnelPeasant` round-trip JSON; tolerant `maybeFromJson`
  (non-map → null, missing keys → defaults); `Character.funnel` wiring
  (forSheet/copyWith/clearFunnel/toJson/fromJson); `withHpDelta` leaves a funnel
  Character unchanged.
- **Profiles:** a parameterized test over **all 12** `kFunnelProfiles` — each has
  non-empty `statKeys`, valid `statMin<statMax` + `hpMin≤hpMax`, every
  `graduateChoices` entry has non-empty options, and `graduate()` returns a
  Character whose target sheet field is non-null with HP populated where the sheet
  has a pool. A test asserts every ruleset in `kKnownSystems` has a profile (no
  drift).
- **Graduation mapping:** same-system DCC funnel → DCC hero copies all 6 stats 1:1 +
  `lckMax` + hp + occupation; a cross-system case (DCC seed → D&D target) copies
  matching keys (str/int) and defaults the rest.
- **UI:** add/kill/revive peasant + the survivor/graduated count; the graduate flow
  spawns a new roster Character (funnel persists, peasant flips to `graduated`);
  add-peasant disabled at `kFunnelMaxPeasants`; target-system dropdown re-renders
  the choice dropdowns.
- **Registration:** `funnel` in `kKnownSystems`/`kSystemCategory.tools`; `solo-dcc`
  preset includes `funnel`; `solo-funnel` preset resolves; a `surfacesFor` row for
  `funnel`; the `kSystemBlurbs['funnel']` exists.
- **DCC regression:** "Add DCC" yields a leveled hero; the full suite stays green
  after the refactor (existing DCC tests updated, not weakened).

## Phasing (for the implementation plan)

- **P1a — Generic core:** `FunnelSheet`/`FunnelPeasant`/`FunnelProfile`/`FunnelChoice`
  + `Character.funnel` wiring + the registry skeleton, with **one** profile (DCC) so
  the path is end-to-end testable. `FunnelSheetView` + graduation flow.
- **P1b — DCC refactor:** rip funnel out of `DccSheet`/`DccSheetView`; move DCC's
  fields into the DCC profile; "Add DCC" → leveled hero; migrate the DCC funnel
  tests.
- **P1c — Remaining 11 profiles:** add a profile + mapper for each other sheet
  system; the parameterized profile test covers them.
- **P1d — Registration & creation:** `funnel` system, roster Add action + dispatch,
  blurb, `surfacesFor`, `solo-dcc` + `solo-funnel` presets, campaign-creation chip.

## Out of scope (deferred)

- **Cross-system stat mapping** beyond matching keys (no rename/alias table).
- **Custom/homebrew sheet as a graduate target** — lands when the in-progress
  custom sheet merges (it then registers its own profile).
- **Batch "graduate all survivors"**, funnel→funnel graduation, and funnel
  auto-archive.
- **Computed/rolled peasant generation** (e.g. auto-rolling occupation tables) —
  peasants are hand-entered (facts-only; no vendored occupation tables).
- **Backward compatibility** for any pre-release `DccSheet`-funnel data.
