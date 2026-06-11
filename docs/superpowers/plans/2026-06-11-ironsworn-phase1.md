# Ironsworn Family Phase 1–2 Implementation Plan (Pipeline + Starforged Slice)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Datasworn ingestion pipeline emitting verified per-ruleset assets for all four rulesets, Ironsworn dice mechanics in the engine, and a Starforged vertical slice: a Rulesets toggle, a Moves tab (moves + oracles) that appears only when enabled.

**Architecture:** Vendored official Datasworn JSON (`data/datasworn/*.json`, CC-BY-4.0 for Starforged — license URL embedded per package) → `build_datasworn.py` transforms to compact `assets/ruleset_<id>.json` (move categories with text/triggers/outcomes; oracle collections flattened, rows as `[min,max,text]`) with self-verification. Engine adds the three Ironsworn roll types (pure mechanics, no per-ruleset data). A global (not session-scoped) `rulesetsProvider` persists enabled rulesets; HomeShell inserts a Moves destination when Starforged is on. Phase 3 (other rulesets + exclusivity rules) builds on the same assets, already emitted here.

**Tech Stack:** existing only (Python 3 stdlib, Flutter/riverpod/shared_preferences).

---

**Source files (already downloaded, controller will stage them):**
`data/datasworn/starforged.json`, `classic.json`, `delve.json`, `sundered_isles.json` — from npm `@datasworn/*` 0.0.10 / 0.1.0-0.

**Datasworn shape (verified):** ruleset JSON has `moves` (map of categories → `contents` map of moves with `name`, `roll_type` ∈ {no_roll, action_roll, progress_roll, special_track}, `trigger.text`, `text` (markdown), `outcomes.{strong_hit,weak_hit,miss}.text`), and `oracles` (map of collections → `contents` map of tables with `name`, `dice` (e.g. "1d100"), `rows` of `{min, max, text}`; some collections nest further via `collections`). Top-level `title`, `license`, `authors`, `url`.

**Mechanics (per the published SRD rules):** Action roll = 1d6 (action die) + stat + adds vs two d10 challenge dice; strictly beat both = strong hit, one = weak hit, none = miss; equal challenge dice = match. Progress roll = progress score (0–10) vs two d10, same ladder. Oracle roll = d100 against row ranges.

### Task 1: Pipeline emitting four ruleset assets

**Files:**
- Create: `build_datasworn.py`
- Create: `assets/ruleset_starforged.json` + `ruleset_classic.json` + `ruleset_delve.json` + `ruleset_sundered_isles.json` (generated)
- Modify: `pubspec.yaml` (register the four assets)
- Commit also: `data/datasworn/*.json` (staged by controller)

- [ ] **Step 1: Write `build_datasworn.py`**

```python
#!/usr/bin/env python3
"""Transform vendored Datasworn JSON into compact per-ruleset assets.

Self-verifies: known roll types only, every oracle row well-formed
(min <= max within the dice range), no empty move/oracle sets.
Run: python3 build_datasworn.py   (writes assets/ruleset_<id>.json)
"""
import json
import os
import sys

SRC = {
    "starforged": "data/datasworn/starforged.json",
    "classic": "data/datasworn/classic.json",
    "delve": "data/datasworn/delve.json",
    "sundered_isles": "data/datasworn/sundered_isles.json",
}
ROLL_TYPES = {"no_roll", "action_roll", "progress_roll", "special_track"}


def transform_moves(moves):
    cats = []
    for cat in moves.values():
        entries = []
        for mv in (cat.get("contents") or {}).values():
            outcomes = mv.get("outcomes") or {}
            entries.append({
                "name": mv["name"],
                "rollType": mv["roll_type"],
                "trigger": (mv.get("trigger") or {}).get("text", ""),
                "text": mv.get("text", ""),
                "outcomes": {
                    k: (outcomes.get(k) or {}).get("text", "")
                    for k in ("strong_hit", "weak_hit", "miss")
                    if outcomes.get(k)
                },
            })
        if entries:
            cats.append({"name": cat["name"], "moves": entries})
    return cats


def flatten_oracles(collections, prefix=""):
    out = []
    for coll in collections.values():
        name = f"{prefix}{coll['name']}"
        tables = []
        for table in (coll.get("contents") or {}).values():
            rows = [
                [r["min"], r["max"], r.get("text") or ""]
                for r in (table.get("rows") or [])
                if r.get("min") is not None and r.get("max") is not None
            ]
            if rows:
                tables.append({
                    "name": table["name"],
                    "dice": table.get("dice", "1d100"),
                    "rows": rows,
                })
        if tables:
            out.append({"name": name, "tables": tables})
        if coll.get("collections"):
            out.extend(flatten_oracles(coll["collections"], prefix=f"{name} / "))
    return out


def verify(ruleset_id, data):
    failures = []
    if not data["move_categories"]:
        failures.append(f"{ruleset_id}: no move categories")
    for cat in data["move_categories"]:
        for mv in cat["moves"]:
            if mv["rollType"] not in ROLL_TYPES:
                failures.append(f"{ruleset_id}: unknown roll type {mv['rollType']}")
            if not mv["name"]:
                failures.append(f"{ruleset_id}: unnamed move")
    if not data["oracle_collections"]:
        failures.append(f"{ruleset_id}: no oracle collections")
    for coll in data["oracle_collections"]:
        for table in coll["tables"]:
            sides = int(table["dice"].split("d")[-1])
            for mn, mx, _text in table["rows"]:
                if not (1 <= mn <= mx <= sides):
                    failures.append(
                        f"{ruleset_id}: bad row [{mn},{mx}] in {table['name']}")
    return failures


def main():
    all_failures = []
    for rid, path in SRC.items():
        with open(path) as f:
            src = json.load(f)
        data = {
            "meta": {
                "id": rid,
                "title": src.get("title", rid),
                "license": src.get("license", ""),
                "authors": [a.get("name", "") for a in src.get("authors", [])],
                "url": src.get("url", ""),
            },
            "move_categories": transform_moves(src.get("moves") or {}),
            "oracle_collections": flatten_oracles(src.get("oracles") or {}),
        }
        all_failures += verify(rid, data)
        out = f"assets/ruleset_{rid}.json"
        with open(out, "w") as f:
            json.dump(data, f, ensure_ascii=False)
        n_moves = sum(len(c["moves"]) for c in data["move_categories"])
        n_tables = sum(len(c["tables"]) for c in data["oracle_collections"])
        print(f"{out}: {n_moves} moves, {n_tables} oracle tables")
    if all_failures:
        print("VERIFICATION FAILED:")
        for f_ in all_failures:
            print("  -", f_)
        sys.exit(1)
    print("All datasworn verifications passed.")


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Run it**

`python3 build_datasworn.py` → four asset lines + "All datasworn verifications passed." Starforged should report ~56 moves. If a source file violates an assumption (e.g. delve has no oracles), report it rather than silently relaxing — adjust `verify` ONLY for structures the source genuinely lacks, and say so in the commit body.

- [ ] **Step 3: Register assets** — `pubspec.yaml` `assets:` section gains the four `assets/ruleset_*.json` lines.

- [ ] **Step 4:** `flutter analyze && flutter test` (no Dart changes — must stay green: 57 passing, 4 infos).

- [ ] **Step 5: Commit**

```bash
git add data/datasworn build_datasworn.py assets/ruleset_*.json pubspec.yaml
git commit -m "feat: Datasworn pipeline — verified compact assets for four rulesets"
```

### Task 2: Engine — Ironsworn rolls (TDD)

**Files:**
- Modify: `lib/engine/oracle.dart` (append an Ironsworn section)
- Test: `test/ironsworn_test.dart` (create; no asset needed — pure mechanics, use `Oracle`? No: mechanics don't need OracleData. Put them on a small pure class.)
- Create: `lib/engine/ironsworn.dart`

- [ ] **Step 1: Failing test** — `test/ironsworn_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/ironsworn.dart';

void main() {
  group('Action roll', () {
    test('outcome ladder and match flag behave statistically', () {
      final iron = Ironsworn(Dice());
      var strong = 0, weak = 0, miss = 0, matches = 0;
      const n = 30000;
      for (var i = 0; i < n; i++) {
        final r = iron.actionRoll(stat: 2, adds: 1);
        switch (r.outcome) {
          case 'Strong Hit':
            strong++;
          case 'Weak Hit':
            weak++;
          default:
            miss++;
        }
        if (r.match) matches++;
        expect(r.total, r.actionDie + 3);
        expect(r.actionDie, inInclusiveRange(1, 6));
      }
      // Exact probabilities for 1d6+3 vs 2d10: strong 0.2517, weak 0.3683,
      // miss 0.3800 (computed by enumeration); match = 1/10.
      expect(strong / n, closeTo(0.2517, 0.02));
      expect(weak / n, closeTo(0.3683, 0.02));
      expect(matches / n, closeTo(0.10, 0.01));
    });

    test('progress roll uses the score directly', () {
      final iron = Ironsworn(Dice());
      var strong = 0;
      const n = 20000;
      for (var i = 0; i < n; i++) {
        if (iron.progressRoll(score: 10).outcome == 'Strong Hit') strong++;
      }
      // 10 beats any challenge die except a 10: P(both < 10) = 0.81
      expect(strong / n, closeTo(0.81, 0.02));
    });

    test('oracle roll picks the matching row', () {
      final iron = Ironsworn(Dice());
      const rows = [
        [1, 50, 'low'],
        [51, 100, 'high'],
      ];
      for (var i = 0; i < 500; i++) {
        final r = iron.oracleRoll(rows);
        expect(r.text, r.roll <= 50 ? 'low' : 'high');
      }
    });
  });
}
```

- [ ] **Step 2:** observe FAIL (file missing).

- [ ] **Step 3: Implement** — `lib/engine/ironsworn.dart`:

```dart
import 'dice.dart';

/// Ironsworn/Starforged dice mechanics (rules CC-BY-4.0, Shawn Tomkin).
/// Pure mechanics — ruleset content comes from the Datasworn assets.
class Ironsworn {
  Ironsworn(this.dice);
  final Dice dice;

  IronswornRoll actionRoll({required int stat, int adds = 0}) {
    final action = dice.dN(6);
    return _resolve(action + stat + adds, actionDie: action);
  }

  IronswornRoll progressRoll({required int score}) =>
      _resolve(score, actionDie: null);

  IronswornRoll _resolve(int total, {int? actionDie}) {
    final c1 = dice.dN(10), c2 = dice.dN(10);
    final beats = (total > c1 ? 1 : 0) + (total > c2 ? 1 : 0);
    return IronswornRoll(
      total: total,
      actionDie: actionDie ?? 0,
      challenge1: c1,
      challenge2: c2,
      outcome: beats == 2
          ? 'Strong Hit'
          : beats == 1
              ? 'Weak Hit'
              : 'Miss',
      match: c1 == c2,
    );
  }

  /// d100 oracle against [rows] of [min, max, text].
  ({int roll, String text}) oracleRoll(List<dynamic> rows) {
    final roll = dice.d100();
    final row = rows.firstWhere(
        (r) => roll >= (r[0] as int) && roll <= (r[1] as int),
        orElse: () => rows.last);
    return (roll: roll, text: row[2] as String);
  }
}

class IronswornRoll {
  const IronswornRoll({
    required this.total,
    required this.actionDie,
    required this.challenge1,
    required this.challenge2,
    required this.outcome,
    required this.match,
  });
  final int total;
  final int actionDie;
  final int challenge1;
  final int challenge2;
  final String outcome; // Strong Hit | Weak Hit | Miss
  final bool match;
}
```

- [ ] **Step 4:** full suite → 60 passing, analyze 4 infos.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/ironsworn.dart test/ironsworn_test.dart
git commit -m "feat: Ironsworn action/progress/oracle roll mechanics"
```

### Task 3: Rulesets state + loader (TDD)

**Files:**
- Modify: `lib/state/providers.dart` (append)
- Test: `test/ironsworn_test.dart` (append)

- [ ] **Step 1: Failing test** (append; add imports flutter_riverpod, shared_preferences, providers; `TestWidgetsFlutterBinding.ensureInitialized()` at top of main):

```dart
  group('Rulesets provider', () {
    test('defaults empty, toggle persists globally (key juice.rulesets.v1)', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(await container.read(rulesetsProvider.future), isEmpty);
      await container.read(rulesetsProvider.notifier).toggle('starforged');
      expect(await container.read(rulesetsProvider.future), {'starforged'});
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('juice.rulesets.v1'), contains('starforged'));
      await container.read(rulesetsProvider.notifier).toggle('starforged');
      expect(await container.read(rulesetsProvider.future), isEmpty);
    });
  });
```

- [ ] **Step 2:** FAIL. **Step 3: Implement** in providers.dart:

```dart
// -- Enabled rulesets (global, not session-scoped) ---------------------------
class RulesetsNotifier extends AsyncNotifier<Set<String>> {
  static const _key = 'juice.rulesets.v1';

  @override
  Future<Set<String>> build() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return <String>{};
    return (jsonDecode(raw) as List).cast<String>().toSet();
  }

  Future<void> toggle(String id) async {
    final current = {...(state.valueOrNull ?? await future)};
    if (!current.remove(id)) current.add(id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(current.toList()));
    state = AsyncData(current);
  }
}

final rulesetsProvider =
    AsyncNotifierProvider<RulesetsNotifier, Set<String>>(RulesetsNotifier.new);

/// Lazy per-ruleset asset, loaded only when its toggle is on.
final rulesetDataProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, id) async {
  final raw = await rootBundle.loadString('assets/ruleset_$id.json');
  return jsonDecode(raw) as Map<String, dynamic>;
});
```

(`rootBundle` needs `import 'package:flutter/services.dart' show rootBundle;` in providers.dart.)

- [ ] **Step 4:** suite green (61). **Step 5: Commit**

```bash
git add lib/state/providers.dart test/ironsworn_test.dart
git commit -m "feat: global rulesets toggle + lazy ruleset asset loading"
```

### Task 4: Moves screen + settings toggle + shell wiring

**Files:**
- Create: `lib/features/moves_screen.dart`
- Modify: `lib/shared/home_shell.dart`

- [ ] **Step 1: `lib/features/moves_screen.dart`** — full file:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/dice.dart';
import '../engine/ironsworn.dart';
import '../engine/models.dart';
import '../shared/result_card.dart';
import '../state/providers.dart';

class MovesScreen extends ConsumerStatefulWidget {
  const MovesScreen({super.key, required this.rulesetId});
  final String rulesetId;

  @override
  ConsumerState<MovesScreen> createState() => _MovesScreenState();
}

class _MovesScreenState extends ConsumerState<MovesScreen> {
  final _iron = Ironsworn(Dice());
  GenResult? _last;

  @override
  Widget build(BuildContext context) {
    final asyncData = ref.watch(rulesetDataProvider(widget.rulesetId));
    return asyncData.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (data) {
        final meta = data['meta'] as Map<String, dynamic>;
        return DefaultTabController(
          length: 2,
          child: Column(
            children: [
              const Material(
                child: TabBar(tabs: [Tab(text: 'Moves'), Tab(text: 'Oracles')]),
              ),
              if (_last != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: ResultCard(
                    result: _last!,
                    onLog: () {
                      ref
                          .read(logProvider.notifier)
                          .add(_last!.title, _last!.asText);
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Logged')));
                    },
                  ),
                ),
              Expanded(
                child: TabBarView(children: [
                  _MovesList(
                      data: data,
                      onRoll: (g) => setState(() => _last = g),
                      iron: _iron),
                  _OraclesList(
                      data: data,
                      onRoll: (g) => setState(() => _last = g),
                      iron: _iron),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.all(4),
                child: Text(
                  '${meta['title']} © ${(meta['authors'] as List).join(', ')} — CC-BY 4.0',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MovesList extends StatelessWidget {
  const _MovesList({required this.data, required this.onRoll, required this.iron});
  final Map<String, dynamic> data;
  final void Function(GenResult) onRoll;
  final Ironsworn iron;

  @override
  Widget build(BuildContext context) {
    final cats = (data['move_categories'] as List).cast<Map<String, dynamic>>();
    return ListView(
      children: [
        for (final cat in cats)
          ExpansionTile(
            title: Text(cat['name'] as String),
            children: [
              for (final mv in (cat['moves'] as List).cast<Map<String, dynamic>>())
                ListTile(
                  title: Text(mv['name'] as String),
                  subtitle: Text(
                    mv['trigger'] as String,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: mv['rollType'] == 'action_roll' ||
                          mv['rollType'] == 'progress_roll'
                      ? const Icon(Icons.casino_outlined)
                      : null,
                  onTap: () => _showMove(context, mv),
                ),
            ],
          ),
      ],
    );
  }

  void _showMove(BuildContext context, Map<String, dynamic> mv) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        var stat = 2, adds = 0, score = 5;
        return StatefulBuilder(builder: (context, setSheet) {
          final rollType = mv['rollType'] as String;
          return Padding(
            padding: const EdgeInsets.all(16),
            child: ListView(
              shrinkWrap: true,
              children: [
                Text(mv['name'] as String,
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(mv['text'] as String),
                const SizedBox(height: 12),
                if (rollType == 'action_roll') ...[
                  _Stepper(
                      label: 'Stat',
                      value: stat,
                      min: 0,
                      max: 5,
                      onChanged: (v) => setSheet(() => stat = v)),
                  _Stepper(
                      label: 'Adds',
                      value: adds,
                      min: 0,
                      max: 5,
                      onChanged: (v) => setSheet(() => adds = v)),
                ],
                if (rollType == 'progress_roll')
                  _Stepper(
                      label: 'Progress',
                      value: score,
                      min: 0,
                      max: 10,
                      onChanged: (v) => setSheet(() => score = v)),
                if (rollType == 'action_roll' || rollType == 'progress_roll')
                  FilledButton(
                    onPressed: () {
                      final r = rollType == 'action_roll'
                          ? iron.actionRoll(stat: stat, adds: adds)
                          : iron.progressRoll(score: score);
                      final outcomeText = (mv['outcomes']
                              as Map<String, dynamic>?)?[
                          switch (r.outcome) {
                        'Strong Hit' => 'strong_hit',
                        'Weak Hit' => 'weak_hit',
                        _ => 'miss',
                      }] as String?;
                      onRoll(GenResult(title: mv['name'] as String, rolls: [
                        Roll(
                            label: 'Outcome',
                            value: r.outcome + (r.match ? ' (match)' : ''),
                            detail: rollType == 'action_roll'
                                ? '${r.actionDie}+${r.total - r.actionDie} vs ${r.challenge1} & ${r.challenge2}'
                                : '${r.total} vs ${r.challenge1} & ${r.challenge2}'),
                        if (outcomeText != null && outcomeText.isNotEmpty)
                          Roll(label: 'Result', value: outcomeText),
                      ]));
                      Navigator.of(sheetContext).pop();
                    },
                    child: const Text('Roll'),
                  ),
              ],
            ),
          );
        });
      },
    );
  }
}

class _OraclesList extends StatelessWidget {
  const _OraclesList({required this.data, required this.onRoll, required this.iron});
  final Map<String, dynamic> data;
  final void Function(GenResult) onRoll;
  final Ironsworn iron;

  @override
  Widget build(BuildContext context) {
    final colls =
        (data['oracle_collections'] as List).cast<Map<String, dynamic>>();
    return ListView(
      children: [
        for (final coll in colls)
          ExpansionTile(
            title: Text(coll['name'] as String),
            children: [
              for (final table
                  in (coll['tables'] as List).cast<Map<String, dynamic>>())
                ListTile(
                  title: Text(table['name'] as String),
                  trailing: const Icon(Icons.casino_outlined),
                  onTap: () {
                    final r = iron.oracleRoll(table['rows'] as List);
                    onRoll(GenResult(
                      title: '${coll['name']}: ${table['name']}',
                      rolls: [
                        Roll(
                            label: 'Result',
                            value: r.text,
                            detail: '${table['dice']} ${r.roll}'),
                      ],
                    ));
                  },
                ),
            ],
          ),
      ],
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text('$label: $value')),
        IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: value > min ? () => onChanged(value - 1) : null),
        IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: value < max ? () => onChanged(value + 1) : null),
      ],
    );
  }
}
```

Note: oracle dice strings other than 1d100 exist (e.g. 1d6 in some tables); `oracleRoll` uses d100 — for non-d100 tables roll within the right range instead: change `_OraclesList` onTap to parse sides from `table['dice']` and call a generalized roll. Implement `oracleRoll` in Task 2 as written (d100), then HERE extend the call site: if dice != '1d100', use `Dice().dN(sides)` and find the row the same way — factor a tiny helper in this file:

```dart
({int roll, String text}) rollTable(Ironsworn iron, Map<String, dynamic> table) {
  final sides = int.parse((table['dice'] as String).split('d').last);
  final rows = table['rows'] as List;
  if (sides == 100) return iron.oracleRoll(rows);
  final roll = iron.dice.dN(sides);
  final row = rows.firstWhere(
      (r) => roll >= (r[0] as int) && roll <= (r[1] as int),
      orElse: () => rows.last);
  return (roll: roll, text: row[2] as String);
}
```

and use `rollTable(iron, table)` in the onTap. (`Dice dice` must be accessible: make `Ironsworn.dice` public — it is, per Task 2.)

- [ ] **Step 2: `home_shell.dart` wiring**

In `_HomeShellState.build`, watch rulesets and build dynamic pages:

```dart
    final rulesets = ref.watch(rulesetsProvider).valueOrNull ?? const <String>{};
    final hasStarforged = rulesets.contains('starforged');
    final pages = [
      FateScreen(oracle: widget.oracle),
      GeneratorsScreen(oracle: widget.oracle),
      TablesScreen(oracle: widget.oracle),
      if (hasStarforged) const MovesScreen(rulesetId: 'starforged'),
      const TrackerScreen(),
    ];
    final index = _index.clamp(0, pages.length - 1);
```

Use `index` for IndexedStack + NavigationBar selectedIndex. Destinations list mirrors pages (`if (hasStarforged) NavigationDestination(icon: Icon(Icons.flash_on_outlined), label: 'Moves'),` between Tables and Tracker). Import moves_screen.dart.

Add a settings action to the AppBar (before the campaigns icon):

```dart
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Rulesets',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => Consumer(builder: (context, ref, _) {
                final enabled =
                    ref.watch(rulesetsProvider).valueOrNull ?? const <String>{};
                return SimpleDialog(
                  title: const Text('Rulesets'),
                  children: [
                    SwitchListTile(
                      title: const Text('Ironsworn: Starforged'),
                      subtitle: const Text(
                          'Moves + oracles © Shawn Tomkin, CC-BY 4.0'),
                      value: enabled.contains('starforged'),
                      onChanged: (_) => ref
                          .read(rulesetsProvider.notifier)
                          .toggle('starforged'),
                    ),
                  ],
                );
              }),
            ),
          ),
```

- [ ] **Step 3:** `flutter analyze && flutter test` green (61 tests, 4 infos); `flutter build web` ✓.

- [ ] **Step 4: Commit**

```bash
git add lib/features/moves_screen.dart lib/shared/home_shell.dart
git commit -m "feat: Starforged slice — rulesets toggle, Moves tab with moves + oracles"
```

### Task 5: Docs

README: feature line for optional Starforged ruleset (moves + oracles from official Datasworn data, CC-BY 4.0, toggle in app bar; other Ironsworn rulesets to follow). CLAUDE.md: note `build_datasworn.py` as second pipeline (regenerate + verify like build_oracle.py). Commit `docs: Starforged ruleset slice`.

## Self-review notes
- Spec coverage (docs/specs/ironsworn-family.md P0 subset): pipeline all four rulesets ✓ (toggles/exclusivity for the other three = phase 3), engine rolls ✓, Moves tab ✓, oracles rollable ✓ (in Moves tab per the lean call rather than Tables — note in PR), attribution ✓, Juice-only unchanged when toggles off ✓ (pages identical, no asset loads).
- `special_track` moves render with text but no roll button (no_roll path) — correct minimal handling; full special-track support is phase-3+/P1.
- Type consistency: `IronswornRoll` fields used by moves_screen; `rulesetDataProvider.family` keyed by id string used in shell + screen.
