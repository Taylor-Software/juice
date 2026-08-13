# Streamline: cross-campaign character library + single-select capabilities

**Date:** 2026-08-12
**Status:** Approved (design), pending implementation
**Decisions made with user:** library-of-copies model; launcher-level library
screen; wizard-picks-one editable later; all four overlap groups in scope;
tables resolved by MERGING into one catalog (not a preference); per-row
"Save to library" on the roster confirmed.

## Goals

1. A character roster that lives OUTSIDE any campaign so heroes are reusable
   across campaigns.
2. Where multiple enabled tools do the same job (except oracles — explicitly
   out of scope), the player picks ONE; the UI never stacks overlapping
   control sets.

## Non-goals

- Live shared characters (damage in campaign A visible in campaign B). The
  library is a library of COPIES; play state diverges per campaign.
- Oracle consolidation. Multiple oracles side-by-side is a feature.
- Back-compat migrations beyond tolerant reads (pre-release posture).

---

## Part 1 — Character library (PR 1)

### Model & persistence

- `characterLibraryProvider` / `CharacterLibraryNotifier` in
  `lib/state/providers.dart`. Key `loreseer.charlibrary.v1` — **app-global**:
  NOT in `sessionScopedKeys`, NOT exported. Same posture as
  `bestiaryProvider` / `customTablesProvider`.
- Entries are full `Character` JSON (identity + sheet + play state as
  captured). No new model type; reuse `Character.fromJson/toJson` with the
  tolerant `decodePersistedList` rail.
- Operations: `add(Character)` (fresh library id), `remove(id)`,
  `rename(id, name)`.

### Copy semantics (both directions)

- **Save to library** (campaign → library): copy character JSON, mint fresh
  id, **drop `polarityId`** (Practical Magic link is campaign-local — the
  magic record lives in that campaign's `loreseer.magic.v1`).
- **Add from library** (library → campaign): copy JSON, mint fresh id, drop
  `polarityId`, reset `role` to `pc`, clear `starred`. Conditions/HP come
  along as captured (user manages).
- Fresh ids on every copy: no dangling journal `char:ID` mentions, no spine
  or encounter cross-links, no id collisions.

### UI

- **Launcher** (`launcher_screen.dart`): a "Characters" entry opens the
  library screen (`lib/features/character_library_screen.dart`): list rows
  (name, system/sheet badge, role), per-row rename + delete (delete gets the
  standard undo snackbar), and **"Copy from campaign"** — a two-step picker
  (campaign from the sessions registry → character from that campaign's
  `loreseer.characters.v1.<sid>` read via SharedPreferences, tolerant
  decode).
- **Roster** (Sheet verb, `tracker_screen.dart` roster): Add menu gains
  **"From library"** (`new-from-library`) → picker → copy in; each row's
  menu gains **"Save to library"** (`save-to-library-<id>`), confirmed by
  snackbar.

### Testing

- Notifier round-trip (add/remove/rename, persistence key, tolerant decode).
- Copy semantics unit tests: fresh id, polarityId dropped, role reset on
  import, original untouched.
- Widget: library screen list/delete/undo; roster "From library" adds a
  character; "Save to library" adds a library entry.

---

## Part 2 — Single-select capabilities (PR 2)

### Mechanism A: exclusive groups over the existing `systems` set

- Pure `kExclusiveGroups` in `lib/engine/campaign_surfaces.dart` (or
  models.dart beside `kSystemCategory`):
  `{'hex-flavor': ['verdant', 'hexcrawl']}` — one group for now; the dungeon
  and party cases use the mechanisms below. Structure is a
  `Map<String, List<String>>` so future overlap groups drop in.
- **Wizard** (`NewCampaignDialog` step 1) and **`_EditSystemsDialog`**: any
  system belonging to an exclusive group renders inside a labeled ChoiceChip
  row (options + "None") instead of loose FilterChips. Selecting one removes
  its siblings from the working set. Legacy campaigns with both enabled keep
  working (gates are unchanged); the edit dialog normalizes to one on next
  save (keeps the first, drops the rest — deterministic by group order).

### Dungeon generator exclusivity

- When `classic-dungeon` is enabled, the Dungeon pane runs classic mode
  ONLY: base-mode room generation controls hidden (today both stack).
  `classic-dungeon` off → base mode only, unchanged. UI gate in
  `map_screen.dart`; no engine change. Existing base-mode rooms in a
  classic campaign still render (data untouched, only the generation
  controls are gated).

### Party paradigm

- The three party surfaces (Party Emulator / Sidekick / NPC Behavior, all
  under the `party` flag in `party_tools_pane.dart`) become single-select:
  new `SessionMeta.partyTool` (`String`, `'emulator' | 'sidekick' |
  'behavior'`, default `'emulator'`; JSON key `partyTool`, omitted at
  default; tolerant parse). `SessionsNotifier.setPartyTool`.
- The party subtab renders ONLY the chosen pane; the SegmentedButton goes
  away. Switcher lives in `_EditSystemsDialog` (a small ChoiceChip row shown
  when `party` is enabled) and in the wizard step 1 under the party addon.
- Persisted state of the unchosen panes is untouched — switching back
  restores it (panes already keep their own state).

### Testing

- Pure: exclusive-group normalization (one survivor, deterministic).
- Widget: wizard renders ChoiceChip row for verdant/hexcrawl and result set
  never contains both; edit dialog same; party subtab renders exactly one
  pane per `partyTool`; dungeon pane hides base generation controls when
  classic-dungeon on.

---

## Part 3 — Unified inspiration catalog (PR 3, the big one)

One browsable catalog replaces three parallel surfaces (24 flavor
generators / built-in table sets + starter pack / My Tables).

### Engine

- `lib/engine/inspiration_catalog.dart` (pure):
  `CatalogEntry {id, name, CatalogKind kind (generator|table), category,
  genre, source, editable}` + `buildCatalog(List<GeneratorDef> generators,
  List<CustomTable> builtins, List<CustomTable> userTables)` returning
  category-grouped entries. Reuses the existing table taxonomy
  (`kTableCategories`, `groupTablesByCategory`, `matchesTableQuery`);
  generators map to categories via their `GenSection`.
- Built-in table sets ship as data through the existing starter rail:
  `starter_tables.json` entries appear IN the catalog directly as read-only
  built-ins; the one-tap "import starter pack" button dies (no more
  copy-into-My-Tables step). `build_starter_tables.py` unchanged as the
  source of truth.

### UI

- **Ask → Tables** (`tables_screen.dart`) becomes the catalog: one
  searchable, category-grouped tree of ALL entries. Generator rows roll via
  their existing `Oracle` functions; table rows via `rollCustomTable` /
  `rollNotation`. User entries keep edit affordances (`showCustomTableDialog`);
  built-ins read-only. Search spans name/genre/category/source across kinds.
- **GenerateSheet** (`generate_sheet.dart`) renders the SAME catalog in its
  category sections (Visual & Stateful section for the three bespoke
  generators is unchanged — those need their custom renderers).
- All rolls keep the `addResult` pipeline and existing `sourceTool`
  provenance tags (`gen-*`, `'custom-table'`) so journal history and Inspire
  keep working unchanged.
- My Tables authoring (editor, packs import/export) unchanged — user tables
  are simply entries in the same catalog.

### Testing

- Pure: `buildCatalog` merges three sources, category grouping, search
  matching across kinds, built-ins flagged read-only.
- Widget: Tables tab shows generators + built-ins + user tables in one tree;
  rolling each kind logs a journal entry with the right sourceTool; edit
  reachable only on user entries; GenerateSheet renders from the catalog.

---

## Rollout

Three PRs in order: (1) character library, (2) exclusivity + partyTool,
(3) catalog merge. Each PR: tests above + `flutter analyze` + full suite +
device verify (macOS) per repo habit. CLAUDE.md project-notes update rides
each PR.

## Risks / notes

- Library "Copy from campaign" reads another session's SharedPreferences
  key directly; uses the tolerant decode rail so a corrupt campaign can't
  brick the picker.
- Catalog merge touches the Inspire seed path only via provenance tags —
  no seam changes; `inspireGenResult`/`inspireEntry` contracts untouched.
- Exclusive groups deliberately do NOT hard-migrate stored `systems` sets;
  normalization happens on next edit-dialog save. Gates tolerate both-on.
