# Word Oracle — Design

**Date:** 2026-06-29
**Status:** Approved (brainstorming)
**Context:** Deferred follow-up from the Solo Loop + Success Tally feature
(`docs/superpowers/specs/2026-06-29-solo-loop-success-tally-design.md`). A word
oracle was cut from that feature because *Cairn Solo*'s list is ShareAlike-encumbered
creative content. This ships an **original, authored** word list (no vendored content,
no attribution), so it stands alone.

## Summary

A **Word Oracle**: a 3-column d66 inspiration table (Action / Descriptor / Subject).
One tap rolls all three columns and logs a single combined prompt
(e.g. *"Betray / Decaying / Shelter"*) to the journal. It slots into the existing
generator registry, so it appears automatically in the journal composer's **Inspire**
sheet (`GenerateSheet`) and the Solo Loop's Inspire step — **no widget changes**.

## Goals / Non-goals

**Goals**
- A generic, system-agnostic word-prompt oracle for open-ended "what does this mean?"
  questions, available everywhere generators already surface.
- Follow the repo's data convention exactly: authored tables live in the build
  script (source of truth, self-verifying) → `assets/oracle_data.json`.

**Non-goals**
- No per-column re-roll, no "descriptor on demand" two-step (one tap = all three).
- No user-editable word lists (that is what Custom Tables already are).
- No new asset file or build script (extend the existing oracle data rail).
- No new UI widget or surface (rides the generator registry + GenerateSheet).

## Architecture

### Data — `build_oracle.py` → `assets/oracle_data.json`

`build_oracle.py` is the source of truth for `oracle_data.json` (CLAUDE.md). Add three
**original authored** word tables to the emitted `TABLES` dict:

- `word_action` — 36 transitive verbs (e.g. Abandon, Betray, Conquer, Reveal…).
- `word_descriptor` — 36 adjectives (e.g. Ancient, Fragile, Hidden, Radiant…).
- `word_subject` — 36 nouns (e.g. Shelter, Debt, Omen, Weapon…).

Each list holds exactly 36 entries in **d66 order** (rows 11,12,…,16,21,…,66), so a
two-d6 roll maps directly to a list index (see the picker below). All words are
original/generic English — non-copyrightable facts-only, no ShareAlike, no attribution.

`build_oracle.py`'s `verify()` gains a structural self-check for each of the three
tables: length == 36, all entries non-empty, no duplicates within a column. (No PDF
cross-check — these are authored, not transcribed.) Confirm the existing
`n_tables = len(data["tables"]) + 4` print line and any table-count assertions still
hold after adding three tables (it is a count, not a pinned constant — adjust only if a
test pins an exact number). Regenerate with `python3 build_oracle.py` and copy the
output into `assets/`.

### Engine — `lib/engine/oracle.dart`

The existing `_pick(key)` uses `dice.d10Index()` (10-row tables) and cannot index a
36-row table. Add a small d66 picker and the generator method on `Oracle`:

```dart
/// Picks from a 36-entry d66 table: two d6 → row 11..66 → index 0..35.
/// Returns the picked value plus the "11".."66" face string for display.
(String value, String face) _pickD66(String key) {
  final tens = dice.dN(6);
  final ones = dice.dN(6);
  final idx = (tens - 1) * 6 + (ones - 1); // 0..35
  return (data.table(key)[idx], '$tens$ones');
}

/// d66 word oracle (Action / Descriptor / Subject) — one combined prompt.
GenResult wordOracle() {
  Roll col(String key, String label) {
    final (value, face) = _pickD66(key);
    return Roll(label: label, value: value, detail: 'd66 → $face');
  }
  return GenResult(title: 'Word Oracle', rolls: [
    col('word_action', 'Action'),
    col('word_descriptor', 'Descriptor'),
    col('word_subject', 'Subject'),
  ]);
}
```

`Dice.dN(6)` already exists. The list must be authored in d66 order so
`(tens-1)*6 + (ones-1)` lines up with the intended row.

### Registry — `lib/engine/generator_registry.dart`

One line added to `kGenerators`:

```dart
GeneratorDef('Word Oracle', GenSection.story, (o) => o.wordOracle()),
```

`GenSection.story` ("Story & Scenes") is the right home for an inspiration prompt;
its `sourceTool` is `gen-story`. It is NOT in `_entityLabels`, so it appears in
`flavorGenerators` → the Inspire sheet and the Loop's Inspire step automatically.

### Data flow (unchanged, reused)

GenerateSheet renders a `Word Oracle` `ActionChip` under "Story & Scenes". On tap:
`g.run(oracle)` → `journalProvider.addResult(r.title, r.asText, sourceTool:
'gen-story', payload: r.toPayload())` → sheet closes. The entry body is the three
`label: value (detail)` lines; the source chip is non-tappable like other `gen-*`
provenance tags. Available from the Solo Loop Inspire button with zero extra wiring.

## Testing

- **`build_oracle.py` `verify()`** — the new structural self-check (3 tables × len 36,
  non-empty, unique) runs on every `python3 build_oracle.py`.
- **`test/oracle_word_oracle_test.dart`** — construct an `Oracle` over a small fixture
  `OracleData` (or the loaded asset, following existing oracle tests) and assert:
  `wordOracle()` returns a `GenResult` titled `'Word Oracle'` with exactly 3 rolls
  labelled Action/Descriptor/Subject; each `value` is a member of its source table;
  each roll's `detail` matches `d66 → NN` with N in 1..6; with a seeded `Dice` the
  index math is correct (row 11 → index 0, row 66 → index 35).
- **`_pickD66` boundary** — seed the RNG so both d6 read 1 (→ index 0, face "11") and
  both read 6 (→ index 35, face "66"); assert the right table entries.

Follow the existing oracle-test setup (mock prefs / fixture data per the
rootBundle-hang testing rule); do not call asset `.load()` directly in tests.

## Files touched

**Changed**
- `build_oracle.py` — 3 authored word tables + `verify()` self-check.
- `assets/oracle_data.json` — regenerated (do not hand-edit).
- `lib/engine/oracle.dart` — `_pickD66` helper + `wordOracle()`.
- `lib/engine/generator_registry.dart` — one `GeneratorDef`.

**New**
- `test/oracle_word_oracle_test.dart`.

## Deferred

- Weighted/longer columns (d100), per-column re-roll, a dedicated Ask-verb surface —
  all YAGNI; Custom Tables already cover user-authored single-column lists.
