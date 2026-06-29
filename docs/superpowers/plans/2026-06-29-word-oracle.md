# Word Oracle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a 3-column d66 Word Oracle (Action / Descriptor / Subject) that surfaces automatically in the generator sheet + Solo Loop Inspire.

**Architecture:** Three authored word tables added to `build_oracle.py` (source of truth) → regenerated `assets/oracle_data.json`. A `_pickD66` helper + `wordOracle()` method on `Oracle`, and one `GeneratorDef` in the registry. No widget changes — the existing GenerateSheet/registry pipeline renders + logs it.

**Tech Stack:** Python 3 (build script), Dart/Flutter, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-06-29-word-oracle-design.md`

**Environment:** `flutter`/`dart` at `$HOME/development/flutter/bin` — `export PATH="$HOME/development/flutter/bin:$PATH"` first. `python3` is on PATH. Package name `juice_oracle`.

---

## File Structure

**Changed**
- `build_oracle.py` — 3 authored word tables in `TABLES` + a `verify()` self-check.
- `assets/oracle_data.json` — regenerated artifact (never hand-edit).
- `lib/engine/oracle.dart` — top-level `d66Index`, `Oracle._pickD66`, `Oracle.wordOracle()`.
- `lib/engine/generator_registry.dart` — one `GeneratorDef`.

**New**
- `test/oracle_word_oracle_test.dart`.

**Reference (read for signatures, don't change)**
- `build_oracle.py:48` — `TABLES = { ... }` dict (each value a `List[str]`); `:620` `verify()` returns a `failures` list; `:846` `emit_json` packs `"tables": TABLES`.
- `lib/engine/oracle.dart:81` — `Oracle(this.data, [Dice? dice])`; `:196` `_pick` (d10-based, do not reuse for d66).
- `lib/engine/oracle_data.dart:18` — `List<String> table(String key)`.
- `lib/engine/generator_registry.dart:24` — `GeneratorDef(label, section, run)`; `GenSection.story`.
- Test pattern (e.g. `test/ask_anything_test.dart:41`): `final data = OracleData(jsonDecode(File('assets/oracle_data.json').readAsStringSync()) as Map<String,dynamic>); final oracle = Oracle(data, Dice(Random(1)));`

---

## Task 1: Author the word tables + regenerate the asset

**Files:**
- Modify: `build_oracle.py` (`TABLES` dict ~line 48; `verify()` ~line 620)
- Regenerate: `assets/oracle_data.json`

- [ ] **Step 1: Add the three tables to `TABLES`**

In `build_oracle.py`, inside the `TABLES = { ... }` dict (after the existing entries,
before the closing `}`), add these three keys verbatim. Each list is exactly 36 entries
in **d66 order** (row 11,12,…,16,21,…,66 → index 0..35). All words are original/authored.

```python
    # ---- Word Oracle (d66 each): Action / Descriptor / Subject ----
    "word_action": [
        "Abandon", "Ambush", "Betray", "Bind", "Break", "Burn",
        "Capture", "Conceal", "Conquer", "Corrupt", "Deceive", "Defend",
        "Deliver", "Demand", "Destroy", "Discover", "Escape", "Expose",
        "Gather", "Guard", "Haggle", "Hunt", "Ignite", "Imprison",
        "Negotiate", "Offer", "Pursue", "Reveal", "Sabotage", "Scatter",
        "Seize", "Summon", "Surrender", "Threaten", "Transform", "Warn",
    ],
    "word_descriptor": [
        "Ancient", "Bitter", "Blazing", "Broken", "Cold", "Concealed",
        "Corrupt", "Cruel", "Decaying", "Distant", "Fading", "Fertile",
        "Forbidden", "Fragile", "Frozen", "Glittering", "Hidden", "Hollow",
        "Hostile", "Luminous", "Massive", "Noble", "Ominous", "Radiant",
        "Restless", "Ruined", "Sacred", "Savage", "Shifting", "Silent",
        "Tangled", "Twisted", "Vast", "Withered", "Wounded", "Youthful",
    ],
    "word_subject": [
        "Altar", "Beast", "Bridge", "Cage", "Caravan", "Children",
        "Coin", "Crown", "Debt", "Disease", "Door", "Dream",
        "Enemy", "Feast", "Gate", "Grave", "Harvest", "Hideout",
        "Hunger", "Journey", "Letter", "Map", "Mountain", "Oath",
        "Omen", "Prisoner", "Prophecy", "Relic", "Ruin", "Secret",
        "Shelter", "Shrine", "Storm", "Stranger", "Weapon", "Wound",
    ],
```

- [ ] **Step 2: Add a structural self-check to `verify()`**

In `build_oracle.py`, inside `verify()` (which builds a `failures` list and returns it),
add this block before `return failures` (or before whatever the final return is — find
where `failures` is returned):

```python
    # Word Oracle: three authored d66 columns, each exactly 36 unique non-empty.
    for col in ("word_action", "word_descriptor", "word_subject"):
        words = TABLES[col]
        if len(words) != 36:
            failures.append(f"{col}: expected 36 entries, got {len(words)}")
        if any(not w.strip() for w in words):
            failures.append(f"{col}: contains an empty entry")
        if len(set(words)) != len(words):
            failures.append(f"{col}: contains duplicate entries")
```

- [ ] **Step 3: Run the build script (this is the data test)**

Run: `python3 build_oracle.py`
Expected output: `All engine verifications passed.` then `Emitted oracle_data.json: ...`.
If it prints `VERIFICATION FAILED`, fix the table contents and re-run.

This writes `oracle_data.json` in the repo root. Per CLAUDE.md, the generated file must
be copied into `assets/`.

- [ ] **Step 4: Copy the regenerated JSON into assets**

Run: `cp oracle_data.json assets/oracle_data.json`
Then confirm the new tables landed:
Run: `python3 -c "import json; d=json.load(open('assets/oracle_data.json')); print(len(d['tables']['word_action']), len(d['tables']['word_descriptor']), len(d['tables']['word_subject']))"`
Expected: `36 36 36`.

(If `build_oracle.py` already writes directly to `assets/oracle_data.json`, Step 4 is a
no-op — verify the path it wrote and adjust. Do NOT leave a stray root-level
`oracle_data.json` if the repo convention keeps only the asset copy; check
`git status` and match the existing tracked layout.)

- [ ] **Step 5: Commit**

```bash
git add build_oracle.py assets/oracle_data.json
git commit -m "feat(word-oracle): authored d66 Action/Descriptor/Subject tables"
```

---

## Task 2: Engine method + registry + test (TDD)

**Files:**
- Modify: `lib/engine/oracle.dart`
- Modify: `lib/engine/generator_registry.dart`
- Test: `test/oracle_word_oracle_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/oracle_word_oracle_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';

OracleData _loadData() =>
    OracleData(jsonDecode(File('assets/oracle_data.json').readAsStringSync())
        as Map<String, dynamic>);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final data = _loadData();

  group('d66Index', () {
    test('row 11 -> 0, row 66 -> 35, row 34 -> 20', () {
      expect(d66Index(1, 1), 0);
      expect(d66Index(6, 6), 35);
      expect(d66Index(3, 4), 20); // (3-1)*6 + (4-1)
    });
  });

  group('wordOracle', () {
    test('returns Word Oracle with 3 labelled rolls from the tables', () {
      final oracle = Oracle(data, Dice(Random(7)));
      final r = oracle.wordOracle();
      expect(r.title, 'Word Oracle');
      expect(r.rolls.map((e) => e.label).toList(),
          ['Action', 'Descriptor', 'Subject']);
      expect(data.table('word_action'), contains(r.rolls[0].value));
      expect(data.table('word_descriptor'), contains(r.rolls[1].value));
      expect(data.table('word_subject'), contains(r.rolls[2].value));
      for (final roll in r.rolls) {
        expect(roll.detail, matches(RegExp(r'^d66 → [1-6][1-6]$')));
      }
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/oracle_word_oracle_test.dart`
Expected: FAIL — `d66Index`/`wordOracle` are not defined.

- [ ] **Step 3: Implement in `lib/engine/oracle.dart`**

Add this top-level pure function near the top of the file (after the imports, outside the
`Oracle` class):

```dart
/// Maps a two-d6 "d66" roll (tens, ones each 1..6) to a 0..35 list index,
/// reading rows in order 11,12,…,16,21,…,66.
int d66Index(int tens, int ones) => (tens - 1) * 6 + (ones - 1);
```

Inside the `Oracle` class, add the helper + the generator method (place them near the
existing `_pick` at line ~196):

```dart
  /// Picks from a 36-entry d66 table: two d6 → index 0..35 via [d66Index].
  /// Returns the picked value plus the "11".."66" face string for display.
  (String, String) _pickD66(String key) {
    final tens = dice.dN(6);
    final ones = dice.dN(6);
    return (data.table(key)[d66Index(tens, ones)], '$tens$ones');
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

(Confirm `Roll` and `GenResult` are already imported in oracle.dart — they come from
`models.dart`, which oracle.dart already imports.)

- [ ] **Step 4: Register the generator**

In `lib/engine/generator_registry.dart`, add one entry to the `kGenerators` list. Place
it in the `GenSection.story` group, e.g. immediately after the `'Pay the Price'` /
`'Major Plot Twist'` story entries:

```dart
  GeneratorDef('Word Oracle', GenSection.story, (o) => o.wordOracle()),
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/oracle_word_oracle_test.dart`
Expected: PASS (both groups).

- [ ] **Step 6: Analyze**

Run: `flutter analyze lib/engine/oracle.dart lib/engine/generator_registry.dart test/oracle_word_oracle_test.dart`
Expected: No new issues.

- [ ] **Step 7: Commit**

```bash
git add lib/engine/oracle.dart lib/engine/generator_registry.dart test/oracle_word_oracle_test.dart
git commit -m "feat(word-oracle): wordOracle() engine method + registry entry"
```

---

## Task 3: Full verification + bookkeeping + PR

- [ ] **Step 1: Full analyze + test**

Run: `flutter analyze` → expect no new errors.
Run: `flutter test` → expect all pass (suite was 1693; +2 here).

- [ ] **Step 2: Update CLAUDE.md**

Add a short bullet under "Project notes" near the generator notes: the Word Oracle is a
3-column d66 (Action/Descriptor/Subject) authored in `build_oracle.py` (`word_action`/
`word_descriptor`/`word_subject`), surfaced via one `GeneratorDef` in `GenSection.story`
(auto-appears in GenerateSheet + Loop Inspire), original facts-only words (no
attribution). Reference the spec + this plan.

- [ ] **Step 3: Commit + push + PR**

```bash
git add CLAUDE.md
git commit -m "docs: note Word Oracle generator"
git push -u origin feat/word-oracle
gh pr create --title "feat(word-oracle): d66 Action/Descriptor/Subject inspiration oracle" \
  --body "Implements docs/superpowers/specs/2026-06-29-word-oracle-design.md"
```

---

## Self-Review notes

- **Spec coverage:** authored tables + build-script self-check (T1) ✓; `_pickD66` + d66
  index + `wordOracle()` (T2) ✓; registry entry → auto-surfaces in GenerateSheet + Loop
  (T2) ✓; tests incl. d66 boundary + table-membership (T2) ✓; no widget changes, no new
  asset file, one-tap-all-three honored.
- **Type consistency:** `d66Index(int,int)→int`, `_pickD66(String)→(String,String)`,
  `wordOracle()→GenResult`, table keys `word_action`/`word_descriptor`/`word_subject`,
  labels `Action`/`Descriptor`/`Subject`, `GenSection.story` — consistent across tasks.
- **Watch-out:** the d66 lists MUST stay 36 entries in row order, or `d66Index` mis-maps
  and the build `verify()` fails — that's the intended guard.
