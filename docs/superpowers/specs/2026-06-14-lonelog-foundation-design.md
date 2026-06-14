# Lonelog Foundation (P1) — Design

**Date:** 2026-06-14
**Status:** Approved (brainstorm) — ready for implementation plan
**Author:** John Taylor + Claude

## Context

Lonelog (en v1.5.0) is a **system-agnostic journaling notation** for solo RPGs —
not a game system and not a set of oracle tables. Its core is 5 symbols
(`@` action, `?` oracle question, `d:` roll, `->` result, `=>` consequence)
plus bracket tags (`[N:]` NPC, `[L:]` location, `[Thread:]`, `[Clock:/Track:/Timer:]`,
`[PC:]`). It ships a core rulebook plus 7 modular, opt-in addons (Combat, Dungeon
Crawling, Resource Tracking, Dice Notation, Cards, Wargaming, and the addon-authoring
Guidelines).

juice's usual pipeline (PDF → oracle table → JSON asset → tool) mostly does **not**
apply: almost nothing in the 8 PDFs is rollable content. juice already implements
~70% of Lonelog's *concepts* in its own UI-native markup — a structured journal
(`JournalEntry` kinds `text/result/scene`, threads, tags, structured roll payloads),
entity mentions `@[Name](char:ID)`, Threads/Characters/Tracks tools, scene dividers,
`journal_export.dart`, and its own `dice_notation.dart` — but **not** in Lonelog's
plaintext `@ ? d: -> =>` + `[N:]` grammar.

The 7 addons mostly map onto tools juice already has (Combat→Encounter Tracker,
Dungeon→Maps, etc.). "Support Lonelog" is therefore a **journaling-notation + interop**
story, decomposed into phases.

## Decision: scope is "all of it, integrated into core, opt-in via settings"

Lonelog is itself modular opt-in addons, and juice already gates optional systems
(`verdant`, `party`) through per-session `enabledSystems`. 1:1 mapping: Lonelog core =
a system flag; each addon = a sub-toggle added incrementally as its feature ships.

### Phased roadmap (each phase = own spec → plan → build)

- **P1 — Foundation (this spec).** `lonelog` system flag + gate; notation grammar as a
  self-verified data asset; a minimal highlighting parser; a gated read-only reference
  tool. The conformance backbone everything else builds on.
- **P2 — Interop bridge.** Export juice journal → Lonelog Markdown (YAML front matter +
  fenced beats); import `.md` → entries/entities/threads/clocks. Defines the canonical
  juice↔Lonelog mapping; introduces the full bidirectional serializer.
- **P3 — Notation in the journal.** Render entries with symbol/tag styling; composer
  symbol palette + tag quick-insert; entity index from `[N:]/[L:]/[Thread:]` (reconciled
  with existing `@[..](char:ID)` mentions).
- **P4 — Addon modules** (each its own sub-toggle, ordered value÷effort):
  4a Combat → extend Encounter Tracker (emit `[COMBAT]/Rd#/[F:]`); 4b Dungeon → Maps room
  `status`/`exits`; 4c Cards → data asset + token parser; 4d Resource → Inv/Wealth/usage-die
  tracker; 4e Dice Notation → upgrade dice engine to the rpg-dice-roller superset;
  4f Wargaming → new Battle Tracker.

## P1 goal

Make Lonelog an opt-in, per-campaign system in juice: a settings gate, the canonical
notation grammar as self-verified data, a minimal highlighting parser, and a gated
read-only reference tool that renders the legend with live-highlighted examples.
**No journal behavior changes yet; no bidirectional `.md` serializer yet (P2).**

## P1 scope

### In scope
1. `lonelog` system flag + gating (campaign-creation checkbox + post-creation edit).
2. `build_lonelog.py` → `assets/lonelog_data.json` — the notation legend as a self-verified data asset.
3. `lib/engine/lonelog_data.dart` — Dart model + loader; `lonelogDataProvider`.
4. `lib/engine/lonelog_highlight.dart` — the "proven parser": a line/token classifier for
   syntax highlighting (NOT a full `.md` parser/serializer).
5. `lib/features/lonelog_reference_screen.dart` — gated read-only reference tool (consumes 3+4).
6. Registry/route + edit-systems plumbing.

### Out of scope (deferred)
- Bidirectional Lonelog Markdown import/export → **P2**.
- Journal rendering/composing in notation → **P3**.
- Addon *behavior* (combat blocks, room status, resource/cards/dice/wargaming) → **P4**.
  Their *notation* is **documented** in the P1 legend; only their *behavior* is later.
- Global app-settings screen — juice is per-session; not building one.

## Data asset — `assets/lonelog_data.json` (built by `build_lonelog.py`)

Fields:
- `version` — spec version (`"1.5.0"`).
- `symbols` — 5 core (`@ ? d: -> =>`) + `@(Name)` variant: `{symbol, name, role, example}`.
- `comparators` — `≥ >= ≤ <= vs S F`: `{op, meaning}`.
- `tagPrefixes` — the **reserved-prefix registry** (conformance contract):
  `N L E PC Thread Clock Track Timer # Inv Wealth R F` with `{prefix, name, meaning, source}`
  (source = `core | combat | dungeon | resource`).
- `blocks` — `COMBAT, DUNGEON STATUS, RESOURCES, BATTLE, CAMPAIGN`:
  `{name, openTag, closeTag, analogOpen, analogClose, purpose}`.
- `addons` — the 7 addons: `{key, title, version, summary, addsTags, addsBlocks, status}`;
  `status: "documented"` now → flips to `"implemented"` per phase. This list is also the
  menu the per-addon sub-toggles key off in later phases.
- `examples` — worked snippets rendered live-highlighted: `{title, lines[]}`.
- `headerFields` — campaign YAML schema (documents the front-matter P2 reads/writes).

`build_lonelog.py` **self-verifies** (same rail as `build_verdant.py`): every reserved
prefix unique (Guidelines collision rule — e.g. `R:` vs `Rd#`), all 5 symbols present,
block tags balanced, every `examples` line classifiable by the highlighter's rule table,
and literals cross-checked against `pdftotext` extracts of the 8 PDFs when present. Script
is source of truth; **never hand-edit the JSON.**

## Highlighter — `lib/engine/lonelog_highlight.dart`

Pure function `List<LonelogSpan> highlight(String line)` → classified spans for rendering.
Recognizes: leading symbol (`@ ? d: -> => tbl: gen:`), `(Name)` actor, bracket tags
`[Prefix:Body]`, `#`-references, comparators, block delimiters, `(note:)` meta. **Tolerant**
— unknown/freeform → plain text (Lonelog encourages house-rule extensions). It is the real
consumer that *proves* the grammar: the reference renders examples through it, and
`build_lonelog.py` cross-checks against the same rule table.

Explicitly **not**: dice evaluation (P4e), `.md` round-trip (P2), entity-state extraction (P3).

## Reference tool — `lib/features/lonelog_reference_screen.dart`

`ToolDef(id:'lonelog-ref', label:'Lonelog Notation', badge:'Lonelog')`, gated
`toolSystem['lonelog-ref']='lonelog'`, in the reference group (where Table Browser lives).
Read-only scroll, sections: Core symbols · Comparators · Tags & references · Progress
(clocks/tracks/timers) · Blocks · Addons (one card each, marked *Documented*/*Coming*) ·
Campaign header · Worked examples (live-highlighted via the highlighter). Read-only + no
`TabBarView`/non-flex Material buttons → dodges the loose-constraint freeze (project memory).

## Gating — `lonelog` flag

- `kAllSystems += 'lonelog'` (`lib/engine/models.dart`).
- New Campaign dialog (`_NewCampaignDialog`, `home_shell.dart`): add a "Lonelog journaling" `CheckboxListTile`.
- `SessionsNotifier.editSystems(String id, Set<String> systems)` — new, beside `rename()`;
  persists `SessionMeta.systems`, refilters the tool registry.
- "Edit campaign" action (campaign menu) → dialog reusing the system-checkbox body to toggle
  systems on an existing campaign.
- `lonelog-ref` appears only when `systems.contains('lonelog')`.

## Success criteria / testing

- `build_lonelog.py` runs; self-verify passes (unique prefixes, examples classify, blocks
  balanced, PDF cross-check where extracts present).
- `lonelog_highlight` unit tests: each symbol/tag/block/comparator classified; unknown
  tolerated as text; **all** asset `examples` classify without error.
- Widget test: reference renders; gated hidden→shown; examples highlight. Override
  `lonelogDataProvider` with a file fixture (per the rootBundle-hang memory).
- Gating test: `editSystems` adds/removes `lonelog`; registry shows/hides `lonelog-ref`.

## Files

**New:** `build_lonelog.py`, `assets/lonelog_data.json`, `lib/engine/lonelog_data.dart`,
`lib/engine/lonelog_highlight.dart`, `lib/features/lonelog_reference_screen.dart`,
`test/lonelog_highlight_test.dart`, `test/lonelog_reference_test.dart`.

**Edit:** `pubspec.yaml` (asset), `lib/engine/models.dart` (`kAllSystems`),
`lib/state/providers.dart` (`lonelogDataProvider`, `SessionsNotifier.editSystems`),
`lib/shared/tool_registry.dart` (ToolDef + toolSystem + group),
`lib/shared/destination.dart` (route `lonelog-ref`),
`lib/shared/home_shell.dart` (New Campaign checkbox + Edit-campaign action/dialog).

## Open judgment calls (resolved)

- **Data-asset rail vs Dart constants:** use `build_lonelog.py` rail, per CLAUDE.md
  convention (PDF-sourced, self-verified). The legend is small but PDF-sourced from 8 docs.
- **Legend documents all addon notation now** (not just core), since the Guidelines addon
  defines the full reserved-prefix registry; addon *features* arrive in P4.
- **Reference lives in the same group as Table Browser** (read-only reference).
