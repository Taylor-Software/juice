# Rules QuickRef Cards — Design

**Date:** 2026-06-29
**Status:** Approved (brainstorming)
**Context:** A DM-screen-style mechanics quick reference — combat sequence, actions,
conditions, damage/death, rest — surfaced in-play. First of a two-part effort; a later
**user-authored ref cards** feature (#3 from the rules-reference discussion) complements
this with house-rules/freeform cards.

## Summary

Authored, **facts-only** per-system "QuickRef cards" — a small structured constant per
TTRPG system (sibling of `system_primer.dart`/`kSystemBlurbs`). One read-only `QuickRefView`
renders the active system's card, reachable from four surfaces: the Encounter screen, the
GM Run dashboard, a `/rules` slash command, and the Ask → Reference view.

**Licensing:** game *procedures* (initiative order, to-hit math, "0 HP → X") are
non-copyrightable facts — the same basis the sheets + `system_primer` already rely on. So
QuickRef cards carry **no attribution and no license gate** and work for every system
(including the no-license ones, later). The one rule: condition/action entries are **name +
a one-line generic effect**, never rulebook prose.

## Scope

**First batch (7 cards authored now):** `argosa`, `cairn`, `knave`, `ose`, `kal-arath`,
`dnd`, `ironsworn`. The remaining systems (`shadowdark`, `nimble`, `draw-steel`, `dcc`) are
trivial drop-in `const` additions later; `custom` gets no card (user-defined — covered by
the later user-authored cards feature).

**Cut:** no per-variant Ironsworn cards (one shared `ironsworn` card for classic/
starforged/sundered_isles in P1), no editing, no search-within-rules, no `custom` card.

## Architecture

### Engine — `lib/engine/quick_ref.dart` (new, pure — no Flutter)

```dart
class QuickRefSection {
  const QuickRefSection(this.title, this.lines);
  final String title;
  final List<String> lines;
}

class QuickRefCard {
  const QuickRefCard({
    required this.system,
    required this.title,
    required this.sections,
  });
  final String system;          // canonical system key
  final String title;           // e.g. "D&D 5e — Quick Reference"
  final List<QuickRefSection> sections;
}

/// Authored facts-only cards, keyed by canonical system id. 7 entries in P1.
const Map<String, QuickRefCard> kSystemQuickRefs = { /* see Content below */ };

/// The active system's card, or null when the resolved system has none.
/// Reuses the existing resolveSystem (no duplicated priority ladder).
QuickRefCard? resolveSystemQuickRef(Set<String> systems, Set<String> rulesets) =>
    kSystemQuickRefs[resolveSystem(systems, rulesets)];
```

`resolveSystem(systems, rulesets)` already exists in `system_primer.dart` (returns the
active system key by the dnd > shadowdark > … > ironsworn priority, ironsworn refined by
ruleset). Reusing it keeps QuickRef resolution identical to the primer's.

### Provider — `lib/state/providers.dart`

```dart
final systemQuickRefProvider = Provider<QuickRefCard?>(
    (ref) => kSystemQuickRefs[ref.watch(resolvedSystemProvider)]);
```

(`resolvedSystemProvider` already exposes the resolved system key.)

### Flexible sections (per-system, not a fixed combat struct)

Sections are an ordered `List<QuickRefSection>` so each system authors what fits its
mechanics. Representative shapes (terse, ~3-6 lines per section):

- **dnd:** Resolution (d20 + mod vs DC; adv/dis) · Combat round (initiative, your turn:
  move + action + bonus + reaction) · Common actions (Attack/Cast/Dash/Disengage/Dodge/
  Help/Hide/Ready) · Damage & death (0 HP → death saves; 3 fail/3 success) · Conditions
  (the `kDndConditions` names + one-line effect) · Rest (short/long).
- **ironsworn:** Resolution (action die + stat vs two challenge dice → strong/weak/miss) ·
  Momentum (burn to cancel challenge dice) · Combat = moves (Enter the Fray / Strike /
  Clash / Secure an Advantage) · Harm (suffer harm → lose health; 0 health → face death) ·
  Conditions (the debilities: wounded/shaken/etc.).
- **cairn / knave / ose / argosa / kal-arath:** Resolution (their save/roll-under or
  2d6/d20+mod) · Combat round (attacker rolls weapon die − armor → HP) · Damage & death
  (HP=avoidance; 0 HP → STR/critical-damage rule per system) · Conditions/fatigue ·
  Rest. Reuse authored consts where they exist (`kOseSaveLabels`, `kConditions`).

Exact authored line content is specified in the implementation plan (the bulk of the
work). All entries are facts (procedures + condition names + generic effects).

### UI — `lib/features/quick_ref_view.dart` (new)

`QuickRefView` — a read-only `ConsumerWidget` taking an optional `QuickRefCard?` (or
reading `systemQuickRefProvider`): renders `card.title` + each `QuickRefSection` as a
titled block of lines (e.g. a `Column` of section headers + bulleted lines, or
`ExpansionTile`s). Empty state when null: "No quick reference for this system yet."

A shared opener `showQuickRef(BuildContext, WidgetRef)` → `showModalBottomSheet` wrapping
`QuickRefView` (used by the Encounter button + `/rules`).

### Surfaces (one widget, four entry points)

1. **Encounter** (`lib/features/encounter_screen.dart`) — an `enc-rules` button in the
   `_header()` Row (an `IconButton`, `Icons.menu_book`, beside the Next-turn/end controls)
   → `showQuickRef`. The "combat rules during encounters" case.
2. **Run** (`lib/features/run_screen.dart`) — a `_QuickRefPanel` (`run-panel-quickref`)
   embedding `QuickRefView` in the standard `_Panel`, fixed height (~320, mirrors
   `run-panel-reference`), added to the panel layout.
3. **`/rules`** (`lib/features/journal_screen.dart`) — a `_BuiltinSlashRow`
   (`slash-cmd-rules`, `Icons.menu_book`, `/rules`) → `showQuickRef`.
4. **Reference** (`lib/features/reference_view.dart`) — add a **Rules** option to the
   All/Monsters/Spells `SegmentedButton`. When selected, the body shows `QuickRefView`
   (the active card) instead of the search results list. (The search field is hidden or
   ignored in Rules mode — rules aren't item-searchable in P1.)

## Testing

- **`test/quick_ref_test.dart`**
  - `resolveSystemQuickRef` returns the right card by priority (e.g. `{dnd, ironsworn}` →
    dnd; `{cairn}` → cairn; ironsworn-family → the ironsworn card); null for a system with
    no card (e.g. `{shadowdark}` in P1) and for the empty set.
  - **Structural self-check** (the build-script discipline, in Dart): for every card in
    `kSystemQuickRefs` — non-empty `title`, `system` key matches the map key, ≥3 sections,
    every section has a non-empty `title` and ≥1 non-empty line. Guards future drop-ins.
- **`test/quick_ref_view_test.dart`** — renders a card's section titles + lines; shows the
  empty-state text when given `null`.
- **Surface smoke (light):** Encounter header shows `enc-rules` and tapping opens a sheet
  containing a section title; `run-panel-quickref` renders; the `/rules` `_BuiltinSlashRow`
  is present. Follow the existing widget-test setup (mock prefs + fixture providers per the
  rootBundle-hang rule).

## Files touched

**New**
- `lib/engine/quick_ref.dart` — model + `kSystemQuickRefs` (7 cards) + `resolveSystemQuickRef`.
- `lib/features/quick_ref_view.dart` — `QuickRefView` + `showQuickRef`.
- `test/quick_ref_test.dart`, `test/quick_ref_view_test.dart`.

**Changed**
- `lib/state/providers.dart` — `systemQuickRefProvider`.
- `lib/features/encounter_screen.dart` — `enc-rules` header button.
- `lib/features/run_screen.dart` — `_QuickRefPanel` + layout slot.
- `lib/features/journal_screen.dart` — `/rules` slash row.
- `lib/features/reference_view.dart` — Rules filter option → `QuickRefView`.

## Non-goals / deferred

- ~~Remaining system cards (shadowdark/nimble/draw-steel/dcc) — drop-in consts later.~~
  **DONE** — 4 cards added, now 11 total (every `resolveSystem` key has one).
- User-authored / house-rules ref cards — the next feature (#3).
- Editing, search-within-rules, per-variant Ironsworn cards, a `custom` card.
