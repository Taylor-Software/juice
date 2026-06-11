# Mythic Meaning Tables Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** All 47 Mythic 2e Meaning Tables rollable from the Mythic section — two-word prompts (Actions/Descriptions pairs, single-list tables rolled twice).

**Architecture:** Source JSONs are vendored in `data/mythic_meaning/` (47 files, `{id, name, order, entries[100], entries2?[100]}`, CC-BY-NC text, attribution already rendered). `build_oracle.py` loads them, verifies shape, and emits a compact `mythic.meaning` list into the asset. Engine rolls d100 twice: word 1 from `entries`, word 2 from `entries2` when present else `entries` again. UI: table dropdown + Meaning button in the existing Mythic section.

**Tech Stack:** existing only.

---

### Task 1: Pipeline

**Files:**
- Modify: `build_oracle.py` (loader near the top after imports; verify section 9; emit)
- Modify: `assets/oracle_data.json` (regenerated)
- Already staged: `data/mythic_meaning/*.json` (47 vendored files — commit them in this task)

- [ ] **Step 1: Loader** (top of file, after existing imports — `json`, `os` may need importing):

```python
def load_mythic_meaning():
    """Vendored Mythic 2e meaning tables (data/mythic_meaning/*.json)."""
    tables = []
    base = os.path.join(os.path.dirname(__file__), "data", "mythic_meaning")
    for fname in sorted(os.listdir(base)):
        if not fname.endswith(".json"):
            continue
        with open(os.path.join(base, fname)) as f:
            t = json.load(f)
        tables.append({
            "id": t["id"],
            "name": t["name"],
            "entries": t["entries"],
            "entries2": t.get("entries2") or None,
        })
    tables.sort(key=lambda t: t["name"])
    return tables

MYTHIC_MEANING = load_mythic_meaning()
```

- [ ] **Step 2: verify() section 9:**

```python
    # 9. Mythic meaning tables: 47 tables, d100 lists.
    if len(MYTHIC_MEANING) != 47:
        failures.append(f"mythic meaning count {len(MYTHIC_MEANING)} != 47")
    ids = [t["id"] for t in MYTHIC_MEANING]
    if len(set(ids)) != len(ids):
        failures.append("mythic meaning duplicate ids")
    for t in MYTHIC_MEANING:
        if len(t["entries"]) != 100:
            failures.append(f"meaning {t['id']}: entries {len(t['entries'])} != 100")
        if t["entries2"] is not None and len(t["entries2"]) != 100:
            failures.append(f"meaning {t['id']}: entries2 len != 100")
        if any(not isinstance(e, str) or not e for e in t["entries"]):
            failures.append(f"meaning {t['id']}: empty/non-string entry")
    if not any(t["id"] == "actions" and t["entries2"] for t in MYTHIC_MEANING):
        failures.append("actions table must carry entries2 (word pairs)")
```

- [ ] **Step 3: Emit** — inside the existing `"mythic"` dict in `emit_json`, add key:

```python
            "meaning": MYTHIC_MEANING,
```

- [ ] **Step 4:** `python3 build_oracle.py && cp oracle_data.json assets/oracle_data.json` → "All engine verifications passed." Then sanity: `python3 -c "import json; m=json.load(open('assets/oracle_data.json'))['mythic']['meaning']; print(len(m), m[0]['name'])"` → `47 Actions`.

- [ ] **Step 5: Commit**

```bash
git add data/mythic_meaning build_oracle.py assets/oracle_data.json
git commit -m "feat: vendor + emit all 47 Mythic 2e meaning tables"
```

### Task 2: Engine (TDD)

**Files:**
- Modify: `lib/engine/oracle_data.dart`, `lib/engine/oracle.dart`
- Test: `test/mythic_test.dart` (append)

- [ ] **Step 1: Failing test** (append to existing groups; `data`/`Oracle` already set up in the file):

```dart
  group('Mythic meaning tables', () {
    test('47 tables, all d100, pairs where entries2 exists', () {
      expect(data.mythicMeaning.length, 47);
      for (final t in data.mythicMeaning) {
        expect((t['entries'] as List).length, 100);
      }
    });

    test('meaning roll yields two non-empty words', () {
      final oracle = Oracle(data);
      for (var i = 0; i < 500; i++) {
        final r = oracle.mythicMeaning('actions');
        expect(r.title, 'Mythic Meaning');
        final words = r.rolls.where((x) => x.label.startsWith('Word'));
        expect(words.length, 2);
        for (final w in words) {
          expect(w.value, isNotEmpty);
        }
      }
    });
  });
```

- [ ] **Step 2:** observe FAIL.

- [ ] **Step 3: Implement.** `oracle_data.dart` (in the Mythic section):

```dart
  /// 47 meaning tables: {id, name, entries[100], entries2?[100]}.
  List<Map<String, dynamic>> get mythicMeaning =>
      (_mythic['meaning'] as List).cast<Map<String, dynamic>>();
```

`oracle.dart` (in the Mythic section):

```dart
  /// Two-word meaning prompt from the table with [id]; the second word
  /// comes from entries2 when the table has pairs, else entries again.
  GenResult mythicMeaning(String id) {
    final table = data.mythicMeaning.firstWhere((t) => t['id'] == id);
    final entries = (table['entries'] as List).cast<String>();
    final entries2 =
        (table['entries2'] as List?)?.cast<String>() ?? entries;
    final r1 = dice.d100(), r2 = dice.d100();
    return GenResult(title: 'Mythic Meaning', rolls: [
      Roll(label: 'Table', value: table['name'] as String),
      Roll(label: 'Word 1', value: entries[r1 - 1], detail: 'd100 $r1'),
      Roll(label: 'Word 2', value: entries2[r2 - 1], detail: 'd100 $r2'),
    ]);
  }
```

- [ ] **Step 4:** full `flutter test` (57 passing) + analyze (4 infos).

- [ ] **Step 5: Commit**

```bash
git add lib/engine/oracle_data.dart lib/engine/oracle.dart test/mythic_test.dart
git commit -m "feat: mythic meaning rolls in Dart engine"
```

### Task 3: UI + docs

**Files:**
- Modify: `lib/features/fate_screen.dart`
- Modify: `README.md`

- [ ] **Step 1:** In `_FateScreenState` add `String _meaningId = 'actions';`. In the Mythic section (inside the existing `Builder`), after the Scene Test / Event Focus row, add:

```dart
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DropdownMenu<String>(
                      initialSelection: _meaningId,
                      label: const Text('Meaning table'),
                      dropdownMenuEntries: [
                        for (final t in widget.oracle.data.mythicMeaning)
                          DropdownMenuEntry(
                              value: t['id'] as String,
                              label: t['name'] as String),
                      ],
                      onSelected: (v) =>
                          setState(() => _meaningId = v ?? _meaningId),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => setState(() => _mythicLast =
                        widget.oracle.mythicMeaning(_meaningId)),
                    child: const Text('Meaning'),
                  ),
                ],
              ),
```

(If `DropdownMenu` inside `Expanded` complains about unbounded width, give it `expandedInsets: EdgeInsets.zero`.)

- [ ] **Step 2:** `flutter analyze && flutter test` green; `flutter build web` ✓.

- [ ] **Step 3:** README: extend the Mythic sentence with "all 47 Meaning Tables". Commit:

```bash
git add lib/features/fate_screen.dart README.md
git commit -m "feat: Mythic meaning table picker + roll"
```

## Self-review notes
- Roadmap "Mythic GME full support — Meaning Tables (47 in 2e) ... Behavior/Statistic/Detail checks, chaos adjustment at scene end": meaning tables fully delivered; behavior/statistic/detail checks deferred (no clean source for their tables/procedures — neither reference implementation ships them; revisit if sourced); scene-end chaos adjustment already served by the persisted dial.
- Asset growth ~50KB of words — negligible.
- Attribution already on-screen from the spike; tables fall under the same CC-BY-NC notice.
