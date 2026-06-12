# Party Emulator Phase 1 (Pipeline + Behavior Tables) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The verified-data pipeline for the party emulator (`build_emulator.py` → `assets/emulator_data.json`) and the first tool: **Behavior Tables** — all 13 Triple-O d66 tables rollable from a new Party launcher group, with licensing attribution.

**Spec:** docs/superpowers/specs/2026-06-12-party-emulator-design.md (read first — Architecture §1-2, Licensing).

**Branch:** `feat/party-emulator-p1` off `main`.

**Source text extracts** (regenerate if missing):
- `/tmp/triple_o.txt` — `pdftotext -layout ~/Library/Mobile\ Documents/com~apple~CloudDocs/Downloads/Triple-O_zine_printer-friendly_v102b.pdf /tmp/triple_o.txt`
- `/tmp/pettish.txt` — same for `Pettish.pdf`

Hard rules: analyze exactly 1 pre-existing info (lib/engine/models.dart:2);
suite green (currently 340); TDD for Dart; exact commit messages, no
co-author lines; no new dependencies. The PIPELINE SCRIPT is the source of
truth — never hand-edit the emitted JSON.

---

### Task 1: build_emulator.py + asset

**Files:**
- Create: `build_emulator.py`
- Create (generated): `assets/emulator_data.json`
- Modify: `pubspec.yaml` (assets list)

- [ ] **Step 1: transcribe.** From `/tmp/triple_o.txt`, transcribe ALL 13
  d66 tables as Python dict literals `{11: '...', 12: '...', ..., 66: '...'}`:
  - Spark (inside front cover, near top of extract): ACTION, FOCUS,
    METHOD. Spark cont. (back cover, near end of extract): DISPOSITION,
    MOTIVATION, DYNAMICS.
  - Specific (pages ~38-51 of the zine): COMBAT, SOCIAL, EXPLORATION,
    DELVING, INTERPRETATION, DOWNTIME, PLANNING — each spans two columns
    across two extract regions (11-36 then 41-66); the extract preserves
    `NN  text` lines.
  Transcribe Pettish tables from `/tmp/pettish.txt` into the same script
  (used by later phases; emit now so the asset is complete):
  - `pet.agenda`: 11 entries keyed 2-12 — group (Drama/Action/Power/
    System/Story/Friendship — two agendas per group except Friendship),
    name (DRAMA, INSTIGATOR, IMPULSIVE, TEAM PLAYER, SELFISH, HERO, SAFE,
    VIRTUOSO, AUTHOR, EXPLORER, AGREEABLE), the full "Ask:" question text,
    and the flavor sentence(s) before it.
  - `pet.focus`: 11 entries keyed 2-12 — name (PLAYFUL, SERIOUS, POWER,
    BUILDING, AMBITIOUS, HELPING HAND, CONFORMING, REBELLIOUS, MY NEEDS,
    OUR NEEDS, APATHETIC) + blurb.
  - `pet.personality_tags`: 36 (six columns of six, in column order 1-6).
  - `pet.consequences`: 6. `pet.real_life`: 6.
  - `sidekick.dialogue`: six moods — default, taciturn, savvy,
    high_strung, sassy, selfish — each 11 lines keyed 2-12 (the extract
    lists them under headers `1 Default` … `6 Selfish`).
  - `sidekick.tone` (6), `sidekick.topic` (6), `sidekick.said_how_a` (6:
    wailed…neutrally), `sidekick.said_how_b` (6: ruefully…sharply).
  - `sidekick.hexflower`: encode the 19-hex flower from the spec's
    description of page 10's figure: center hex index 0; hexes have
    {topic: fact|query|want|need|action|support|denial, context:
    'red'|'gray'}. Layout per the figure (rows top→bottom): gray row
    [denial], [want, query], [action(red-edge), query(gray), denial];
    then [need(red), query(gray)], [need(red), fact(center, red),
    fact(gray)], [query(red), action(red)], [support(red), query(red),
    denial(red)], [query(red), want(red)], [support(red)].
    **IMPORTANT**: this figure is visual; encode your best reading with an
    explicit `# FLAGGED: derived from a figure; reviewer must re-derive
    independently` comment, plus the 2d6 direction overlay
    {12: 'N', 2-3: 'NE', 4-5: 'SE', 6-7: 'S', 8-9: 'SW', 10-11: 'NW'}
    (aggressive/defensive/helpful/aggressive/defensive/neutral tone
    labels) and an `adjacency` map (axial or index-based) consistent with
    a hexflower (19 hexes, center + ring1 ×6 + ring2 ×12). Movement off
    the flower edge = stay (clamped), interrupts handled by UI later.
  - `meta.attribution`: ["PET & Sidekick © Tam H (hedonic.ink), CC-BY 4.0",
    "Triple-O © Cezar Capacle / Critical Kit, CC-BY-SA 4.0"]; plus
    `meta.license_note`: 'Data derived from Triple-O is CC-BY-SA 4.0;
    data derived from Pettish is CC-BY 4.0.'

- [ ] **Step 2: verify().** Following build_oracle.py's failures-list
  style: every d66 table exactly 36 keys = {11..16,21..26,...,61..66},
  values non-empty distinct strings; agenda/focus/dialogue keyed exactly
  2-12; tags exactly 36 distinct; tone/topic/said_how/consequences/
  real_life exactly 6; hexflower exactly 19 hexes, adjacency symmetric,
  every hex ≤6 neighbors, center has 6; direction overlay covers 2-12.
  Cross-check (best-effort): for each d66 table, count lines in
  /tmp/triple_o.txt matching `^\s*NN\s` for its keys within the table's
  region and assert ≥30 of 36 literal values appear verbatim in the
  extract (catches paraphrase/typo drift; visual-only content exempt).

- [ ] **Step 3: emit + wire.** Emit JSON (sorted keys, indent 1) to repo
  root `emulator_data.json` mirroring build_oracle.py's flow; copy to
  `assets/emulator_data.json`; add to pubspec assets. Run
  `python3 build_emulator.py` → verifications pass.

- [ ] **Step 4: commit.**

```bash
git add build_emulator.py assets/emulator_data.json pubspec.yaml
git commit -m "feat: party emulator data pipeline — Triple-O + Pettish tables, verified"
```

---

### Task 2: Dart data layer + engine rollers (TDD)

**Files:**
- Create: `lib/engine/emulator_data.dart`
- Create: `lib/engine/party_emulator.dart`
- Modify: `lib/state/providers.dart` (one FutureProvider)
- Tests: `test/emulator_data_test.dart`, `test/party_emulator_test.dart`

- [ ] **Step 1: failing tests.** EmulatorData wraps the decoded JSON
  (load pattern: see OracleData; tests read the asset file directly like
  test/location_test.dart): accessors `sparkTable(name)`,
  `specificTable(name)`, `d66Entry(table, key)`, attribution list; throws
  on unknown table. Engine (party_emulator.dart, pure Dart + Dice):
  `D66Result rollD66(Dice)` → key from two d6 (tens, units) + lookup
  helper; `TableRollResult rollBehavior(EmulatorData, String table, Dice)`
  → {table, key, text}; combo helper `rollCombo(... List<String> tables)`
  rolling each. Determinism via seeded Dice (fate_engine_test pattern).
  Assert a few known cells (e.g. combat 11 = 'Aim carefully, wait for an
  opening', social 25 = 'Confide a secret', action 11 = 'Abort',
  dynamics 66 = 'Uneasy') — these pin transcription too.

- [ ] **Step 2: implement.** Provider:
  `final emulatorDataProvider = FutureProvider<EmulatorData>(...)` loading
  `assets/emulator_data.json` via rootBundle (rulesetDataProvider
  pattern).

- [ ] **Step 3: gates + commit.**

```bash
git add lib/engine/emulator_data.dart lib/engine/party_emulator.dart lib/state/providers.dart test/emulator_data_test.dart test/party_emulator_test.dart
git commit -m "feat: emulator data accessors + d66 behavior rollers"
```

---

### Task 3: Behavior Tables tool (TDD)

**Files:**
- Create: `lib/features/behavior_tables_screen.dart`
- Modify: `lib/shared/tool_registry.dart` (+ 'Party' in toolGroups after 'NPCs & Dialog'; ToolDef id 'behavior-tables')
- Tests: `test/behavior_tables_test.dart`; update `test/tool_registry_test.dart` counts (13→14 base, 14→15 with family)

- [ ] **Step 1: failing tests.** Screen pumped with mock prefs +
  ProviderScope (asset read via dart:io for the data provider override —
  follow how map/generator tests construct engine data; simplest:
  override emulatorDataProvider with data loaded from the file). Tests:
  every spark/specific chip present (Key('bt-<table>')); tapping
  `bt-combat` shows a result card whose text is one of the combat table's
  36 values; combo chip `bt-combo-action-focus` shows two results;
  add-to-journal (Key('bt-log')) writes entry titled 'Behavior: Combat'
  (or 'Behavior: Action + Focus'); attribution texts visible.
  Registry test: group 'Party' in toolGroups; id 'behavior-tables'
  present; counts updated.

- [ ] **Step 2: implement.** Screen shape: section headers 'Spark' /
  'Specific' with ActionChip rows (generators_screen pattern), one result
  slot (latest roll, card with table name + key + text), combo chips row
  (Action + Focus, Action + Method, Disposition + Motivation), bookmark
  add-to-journal, attribution footer (bodySmall, onSurfaceVariant — both
  meta.attribution lines). Registry: icon Icons.groups_outlined, label
  'Behavior Tables', badge 'Triple-O', builder needs EmulatorData — tool
  builders receive Oracle only; follow how the screen itself watches
  emulatorDataProvider internally (builder returns
  const BehaviorTablesScreen(); screen watches the provider with
  loading/error states like JuiceApp does for oracleProvider).

- [ ] **Step 3: gates + commit.** Full suite + analyze + `flutter build
  web`.

```bash
git add lib/features/behavior_tables_screen.dart lib/shared/tool_registry.dart test/behavior_tables_test.dart test/tool_registry_test.dart
git commit -m "feat: Behavior Tables tool — 13 Triple-O d66 tables in a new Party group"
```

---

### Task 4: Docs

- [ ] README: feature sentence in the features area ("A **Party** toolkit
  begins with Behavior Tables — all thirteen Triple-O spark and specific
  d66 tables (© Cezar Capacle / Critical Kit, CC-BY-SA 4.0) for deciding
  what characters do"); licensing list near the Mythic/Datasworn notes
  gains both attributions. CLAUDE.md project-notes bullet: emulator assets
  generated by `build_emulator.py` (same rail as build_oracle).

```bash
git add README.md CLAUDE.md
git commit -m "docs: party emulator pipeline + Behavior Tables notes, attributions"
```

---

## Verification (controller)

`python3 build_emulator.py` green; reviewer spot-checks ≥3 random rows per
table against the PDFs and re-derives the hexflower; browser: Party group
→ Behavior Tables → roll Combat + a combo → journal entries. PR → CI →
merge → spec/roadmap bookkeeping.
