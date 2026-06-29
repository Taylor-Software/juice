# Content Library — Spells & Monsters + GM Quick-Reference

**Date:** 2026-06-29
**Status:** Approved (design)

## Goal

Add bundled **spells** and **monsters** for every system whose license permits it,
surface that content in the opportunistic places it's needed (encounter combatants,
caster sheets), and add a first-class **quick-reference** surface so a player or GM
can search/glance any monster or spell at any time. Build the reusable rails once and
prove them end-to-end with **D&D 5e (SRD 5.1)**; every other system then ships as a
content-only follow-up on the same rails.

## Licensing posture (policy shift)

This supersedes the prior strictly-facts-only rule. The owner's decision (2026-06-29):

> **Vendoring rulebook content + carrying the required attribution is OK, as long as
> the license is free/open.**

- **In scope (free license):** D&D 5e (SRD 5.1, CC-BY-4.0), Cairn (CC-BY-SA-4.0),
  Argosa (CC-BY-SA-4.0), Knave 2e (CC-BY-4.0), OSE / B-X (OGL-1.0a + non-copyrightable
  facts), Nimble (open 3rd-party creator license), Draw Steel (MCDM Creator License),
  DCC (OGL-1.0a).
- **Hard-blocked (no app license):** Shadowdark (no open license / 3rd-party license
  excludes apps), Kal-Arath (personal-use-only). These ship **no** spell/monster
  content.

The true test stays: *does the content's license permit free redistribution in an
app?* If yes, vendor it and carry attribution. If it needs paid permission, it's out.

## Architecture (Approach A — unified content registry)

One registry behind a single interface aggregates every content source. Every surface
(reference UI, Run lookup, slash commands, encounter monster picker, caster-sheet
spell picker) reads the registry. Adding a new system is **data-only**: drop an asset
file + register it; no UI changes.

```
                       ┌──────────────────────┐
 bundled creatures ───▶│                      │
 (foes_*.json)         │                      │──▶ ReferenceView (Ask tab)
 ruleset npc_collections│   contentRegistry    │──▶ Run lookup panel
 user bestiary  ───────▶│  (pure aggregate +   │──▶ /lookup /spell /monster
 bundled spells  ──────▶│   searchContent)     │──▶ encounter add-monster
 (spells_*.json)       │                      │──▶ caster-sheet spell picker
                       └──────────────────────┘
```

## Components

### 1. Data model (`lib/engine/`, pure — no Flutter)

**`SpellEntry`** (new, `lib/engine/spell.dart`):

```dart
class SpellEntry {
  final String id;          // e.g. "dnd-fireball" (edition-scoped: "dnd-2024-fireball")
  final String system;      // "dnd"
  final String? edition;    // "5.1" | "5.2" | null (non-D&D); see Forward compatibility
  final String name;
  final int level;          // 0 = cantrip
  final String school;      // "Evocation"
  final String castingTime; // "1 action"
  final String range;       // "150 feet"
  final String components;  // "V, S, M (a tiny ball of bat guano and sulfur)"
  final String duration;    // "Instantaneous"
  final bool concentration;
  final bool ritual;
  final List<String> classes; // ["Sorcerer","Wizard"]
  final String description;   // full SRD body text
  final String? higherLevels; // "At Higher Levels" paragraph, if any
}
```

- Tolerant `static SpellEntry? maybeFromJson(dynamic)` — returns null on missing
  `id`/`name`; defaults level 0, empty strings, empty lists.
- `Map<String,dynamic> toJson()` round-trips.

**`StatBlock` enrichment** (`lib/engine/models.dart`, existing model): add optional,
nullable, back-compat fields so D&D monsters carry full quick-reference detail while
existing combatant stat blocks keep working:

```dart
final String? cr;                 // "5" or "1/4"
final String? creatureType;       // "Dragon", "Undead"
final String? size;               // "Large"
final Map<String,int>? abilities; // {"STR":19,"DEX":10,...}
final List<StatTrait>? traits;    // [{name, text}] — traits/actions/legendary
```

- `StatTrait { String name; String text; }` (new, small value class in models.dart).
- `StatBlock.maybeFromJson` / `toJson` / `copyWith` extended; all new fields optional,
  so persisted encounters and `foes_cairn.json` / `foes_ose.json` parse unchanged.
- Monsters reuse `Creature { id, name, statBlock, maxHp }`, plus an optional nullable
  `edition` field (same role as `SpellEntry.edition`; null for non-D&D). Back-compat:
  existing creature files omit it and parse unchanged.

### 2. Content registry (`lib/engine/content_registry.dart` pure + `lib/state/`)

- **Pure** `searchContent({required String query, ContentType filter, String? system,
  required List<Creature> monsters, required List<SpellEntry> spells})` →
  `ContentResults { List<Creature> monsters; List<SpellEntry> spells }`. Case-insensitive
  substring match on name (+ type/school); empty query returns all (filtered). Unit-testable
  with no Flutter.
- `enum ContentType { all, monsters, spells }`.
- **Providers** (`lib/state/providers.dart`):
  - `systemSpellsProvider = FutureProvider.family<List<SpellEntry>, String>` — loads
    `assets/spells_$system.json`, empty list on missing/malformed (mirrors the existing
    `systemFoesProvider`).
  - `contentMonstersProvider = FutureProvider<List<Creature>>` — aggregates, for enabled
    systems: `systemFoesProvider(sys)` for each system with a bundled file, the Ironsworn
    `foesProvider` collections adapted to `Creature` (rank→maxHp via the existing rank×10,
    tactics/features→notes), and the user `bestiaryProvider`. De-duped by id.
  - `contentSpellsProvider = FutureProvider<List<SpellEntry>>` — aggregates
    `systemSpellsProvider(sys)` across enabled systems.
- `kContentSystemsWithFiles` lists which systems have bundled files (cairn, ose, dnd…),
  so the providers only attempt files that exist.

### 3. Build rail + D&D SRD data

- Vendor a free CC-BY/OGL SRD JSON dataset (e.g. the `5e-bits/5e-SRD-API` database JSON,
  CC-BY-4.0 / OGL) into `data/dnd_srd/` (committed — reproducible offline thereafter).
- `build_dnd_content.py` reads the vendored data → emits **full SRD**:
  - `assets/spells_dnd.json` — all SRD spells (~319) as `SpellEntry` JSON.
  - `assets/foes_dnd.json` — all SRD monsters (~330) as `Creature` JSON with the enriched
    `StatBlock` (cr/type/size/abilities/traits/attacks).
- Self-verifies: non-zero counts, unique ids, non-empty `name`+`description` (spells),
  valid `level` 0–9, parseable `cr`, non-empty `abilities` (monsters). Same rail discipline
  as `build_datasworn.py` — **edit the script, never the emitted JSON**.
- Register both files in `pubspec.yaml` (explicit asset list).

### 4. Attribution

- `kContentAttributions` (`lib/engine/content_registry.dart`): `Map<String,String>` of
  system → credit/license line. D&D entry: "Includes content from the System Reference
  Document 5.1, © Wizards of the Coast LLC, licensed under CC-BY-4.0."
- Rendered: a "Sources & licenses" expandable in the Reference footer, and a matching
  section in the Settings sheet. Only systems with bundled content appear.

### 5. Reference surface (always available — NOT mode-gated)

- **`ReferenceView`** (`lib/features/reference_view.dart`, shared): search field +
  segmented type filter (All / Monsters / Spells) + system filter dropdown (default =
  active resolved system, "All systems" option) + results `ListView` → tap → glance.
  - Monster glance → `StatBlockView` (existing, `sheet_widgets.dart`), extended to render
    the new cr/type/size/abilities/traits fields when present.
  - Spell glance → new `SpellCard` (level·school header, casting time/range/components/
    duration line, concentration/ritual chips, description, higher-levels).
  - Footer: "Sources & licenses".
- **Entry points:**
  - **Ask → "Reference" tab** — added to the Ask verb's tab set, present in **both** GM and
    party modes (mode does not gate tools). System-aware ordering only.
  - **Run screen** — a `run-panel-reference` lookup panel: compact search field + result list
    reusing the same search + glance, for live play.
  - **Slash commands** (`/lookup <q>`, `/spell <q>`, `/monster <q>`) — reachable from any
    verb. `/lookup` opens `ReferenceView` pre-filtered to the query (type All); `/spell` and
    `/monster` open it pre-filtered to that type. Wired through the existing slash-command
    dispatch alongside `/card`/`/tarot`/`/spread`.

### 6. Opportunistic wiring

- **Encounter:** existing per-system "add creatures" buttons auto-extend — `foes_dnd.json`
  surfaces through `systemFoesProvider('dnd')`, so a D&D campaign gets an "Add D&D monster"
  button with no new code beyond registration. Picking seeds a combatant with the full
  enriched `StatBlock`. Add a generic **"Add from reference"** button → the unified monster
  picker (all enabled systems) for cross-system encounters.
- **D&D caster sheet** (`lib/features/dnd_sheet.dart`): add `DndSheet.spellIds`
  (`List<String>`, ordered) persisted via `copyWith`/JSON. A spell-picker dialog
  (`dnd-spell-pick`) lists registry spells (filterable by level/class), tapping adds the id.
  The Spellcasting section renders attached spells grouped by level; tapping a prepared spell
  opens `SpellCard`. The old freeform prepared-list text is retained as optional notes. Other
  caster sheets adopt this when their spell content lands (follow-up).

### 7. Scope & decomposition

**This spec / plan ships:**
- `SpellEntry` + `StatTrait` + `StatBlock` enrichment.
- `content_registry` pure search + the three aggregating providers.
- `build_dnd_content.py` + vendored SRD data + `spells_dnd.json` + `foes_dnd.json` + pubspec.
- `kContentAttributions` + Reference/Settings attribution UI.
- `ReferenceView` + `SpellCard` + `StatBlockView` extension.
- Ask Reference tab + Run lookup panel + `/lookup` `/spell` `/monster` commands.
- Encounter "Add from reference" + D&D monster auto-extend.
- D&D sheet spell picker (`spellIds` + glance).

**Follow-up content-only specs (same rails, no UI work):** Argosa, Knave, Nimble,
Draw Steel, DCC spells/monsters; deeper Cairn/OSE spells. Each = a `build_<sys>_content.py`
(or extend the foes script) + asset files + registration + attribution entry.

### 7a. Forward compatibility — D&D editions (5.1 / 5.2)

D&D now has two free SRDs: **SRD 5.1** (the 2014 "5e" rules, CC-BY-4.0) and **SRD 5.2**
(the 2024 "5.5e" rules, CC-BY-4.0). Both are in scope; we ship **5.1 first** and add 5.2
**one at a time** as a content-only follow-up — handled by the model now so no rework:

- **`edition` field** on `SpellEntry` and `Creature` ("5.1" | "5.2"; null for non-D&D).
  Ids are edition-scoped (`dnd-fireball` vs `dnd-2024-fireball`) so the two sets coexist
  without id collisions in the registry.
- **Separate asset files per edition:** `spells_dnd.json` / `foes_dnd.json` = 5.1 now;
  `spells_dnd_2024.json` / `foes_dnd_2024.json` = 5.2 later. The build script
  (`build_dnd_content.py`) takes an `--edition` parameter and reuses one transform over
  the matching vendored source — only the input data differs.
- **Reference filter:** the system filter exposes "D&D 5e (2014)" and "D&D 5e (2024)" as
  edition sub-filters when both sets are present; a campaign-level edition preference
  (default 5.1) sets the initial filter. Until 5.2 ships, the filter shows only 5.1.
- **Delta management:** the 5.2 build can diff against the committed 5.1 output to surface
  changed/added/removed entries, keeping the follow-up review focused on the delta rather
  than the full set. (Diff is a build-time aid, not shipped data.)

This is a forward-compatibility note only — **no 5.2 content or edition UI ships in this
spec**; the field + file-naming convention exist so the later 5.2 PR is pure data.

## Data flow

1. Build time: `build_dnd_content.py` (vendored SRD → `assets/spells_dnd.json` +
   `assets/foes_dnd.json`), self-verified.
2. Runtime load: `systemSpellsProvider`/`systemFoesProvider` load per-system files;
   `contentSpellsProvider`/`contentMonstersProvider` aggregate across enabled systems.
3. Query: a surface calls `searchContent(...)` (pure) with the loaded lists + the user's
   query/filters → `ContentResults`.
4. Glance: tap → `SpellCard` or `StatBlockView`.
5. Act: encounter add → combatant w/ `StatBlock`; sheet pick → `DndSheet.spellIds`.

## Error handling

- Missing/malformed asset file → provider returns empty list (no crash); the surface shows
  an empty state. Mirrors `systemFoesProvider`'s existing try/catch.
- `maybeFromJson` on `SpellEntry`/`StatBlock`/`StatTrait` drops malformed rows tolerantly.
- Build script aborts (non-zero exit) on any verification failure — bad data never reaches
  assets.
- Slash command with no match → opens the reference with an empty result + the query
  preserved (user can broaden).

## Testing

- **Pure engine** (no Flutter, fast): `SpellEntry` + `StatBlock`(+traits/abilities/cr)
  JSON round-trip + tolerant parse; `searchContent` filter/type/system/empty-query cases;
  registry aggregation + de-dup using small fixtures.
- **Build script:** `build_dnd_content.py` self-verifies on run (counts, ids, required
  fields, level/cr ranges).
- **Widget tests** (provider overrides + file fixtures, never `*.load()` in tests, per the
  rootBundle-hang rule): Reference tab renders + search filters + glance opens; Run lookup
  panel; D&D sheet spell picker attaches + glance opens; `/lookup` `/spell` `/monster`
  dispatch opens the reference pre-filtered.
- **Full suite** `flutter analyze` + `flutter test` clean before ship.

## Non-goals (this round)

- No rules adjudication / automatic spell effects — content is reference + display only.
- No homebrew spell/monster authoring UI (the Custom sheet + bestiary already cover
  user-authored content; a homebrew spell editor is a possible later follow-up).
- No web-specific handling beyond what bundled JSON already gives (assets ship everywhere).
- No per-system content beyond D&D in this spec (follow-ups).
