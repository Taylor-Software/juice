# Custom Oracle Tables — Implementation Plan (Epic Phase 1)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task.
> Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user author their own random tables in-app, roll one, and log the
result to the journal — closing the #1 solo-player creator gap (all tables are
currently baked into assets).

**Architecture:** A pure model + roll function in a new engine leaf
(`lib/engine/custom_table.dart`), persisted by an app-global notifier that mirrors
the existing `BestiaryNotifier` (reusable across campaigns, not exported), surfaced
as a "My Tables" section in the existing `GenerateSheet` that reuses the proven
`oracle roll → journalProvider.addResult` pipeline.

**Tech Stack:** Dart, Flutter, `flutter_riverpod`, `shared_preferences`,
`package:test` / `flutter_test`.

**Scope (lean / P1):** Flat list of row strings; a roll uniformly picks one row
(`dN` where N = row count). No weights, no min-max ranges, no dice-notation field —
deferred. Ships zero vendored content (the user authors every row), consistent with
the repo's facts-only posture.

---

## File structure

- Create `lib/engine/custom_table.dart` — pure `CustomTable` model + `rollCustomTable`.
- Create `test/custom_table_test.dart` — model JSON round-trip + roll behavior.
- Modify `lib/state/providers.dart` — add `CustomTablesNotifier` + `customTablesProvider`
  (mirror `BestiaryNotifier`, ~`providers.dart:1256`); register key in the app-global
  (NOT session-scoped) group.
- Create `test/custom_tables_provider_test.dart` — persistence round-trip with mock prefs.
- Modify `lib/features/generate_sheet.dart` — add a "My Tables" section: roll chips +
  a "New table" button + per-table edit/delete via a `_CustomTableDialog`.
- Modify `test/generate_sheet_test.dart` — a light widget test that the section renders
  and a roll logs (only if the existing harness already overrides the data providers;
  otherwise cover via the provider/engine tests and device-verify the UI).

---

## Task 1: Pure `CustomTable` model

**Files:**
- Create: `lib/engine/custom_table.dart`
- Test: `test/custom_table_test.dart`

- [ ] **Step 1: Write failing tests**

```dart
// test/custom_table_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/custom_table.dart';

void main() {
  group('CustomTable JSON', () {
    test('round-trips id/name/rows', () {
      const t = CustomTable(
          id: 't1', name: 'Tavern Names', rows: ['The Rusty Flagon', 'The Sly Fox']);
      final back = CustomTable.fromJson(t.toJson());
      expect(back.id, 't1');
      expect(back.name, 'Tavern Names');
      expect(back.rows, ['The Rusty Flagon', 'The Sly Fox']);
    });

    test('maybeFromJson returns null on malformed input', () {
      expect(CustomTable.maybeFromJson('not a map'), isNull);
      expect(CustomTable.maybeFromJson({'name': 'x'}), isNull); // missing id
    });

    test('maybeFromJson drops non-string rows tolerantly', () {
      final t = CustomTable.maybeFromJson(
          {'id': 'a', 'name': 'n', 'rows': ['ok', 3, null, 'fine']});
      expect(t, isNotNull);
      expect(t!.rows, ['ok', 'fine']);
    });
  });
}
```

- [ ] **Step 2: Run, verify it fails** — `flutter test test/custom_table_test.dart`
  Expected: FAIL (`custom_table.dart` / `CustomTable` not found).

- [ ] **Step 3: Implement the model**

```dart
// lib/engine/custom_table.dart
/// Pure model + roll logic for user-authored random tables.
/// No Flutter imports — unit-tested without a widget harness.
library;

import 'dice.dart';
import 'models.dart';

/// A user-authored random table: a flat list of row strings rolled uniformly.
class CustomTable {
  const CustomTable({required this.id, required this.name, required this.rows});

  final String id;
  final String name;
  final List<String> rows;

  CustomTable copyWith({String? name, List<String>? rows}) => CustomTable(
        id: id,
        name: name ?? this.name,
        rows: rows ?? this.rows,
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'rows': rows};

  factory CustomTable.fromJson(Map<String, dynamic> j) => CustomTable(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        rows: [
          for (final r in (j['rows'] as List? ?? const []))
            if (r is String) r
        ],
      );

  /// Tolerant decode for persistence: returns null when [raw] is not a map or
  /// lacks an id.
  static CustomTable? maybeFromJson(Object? raw) {
    if (raw is! Map) return null;
    final map = raw.cast<String, dynamic>();
    if (map['id'] is! String) return null;
    return CustomTable.fromJson(map);
  }
}
```

- [ ] **Step 4: Run, verify pass** — `flutter test test/custom_table_test.dart` → PASS.

- [ ] **Step 5: Commit** — `git add lib/engine/custom_table.dart test/custom_table_test.dart && git commit -m "feat(tables): pure CustomTable model"`

---

## Task 2: `rollCustomTable` roll function

**Files:**
- Modify: `lib/engine/custom_table.dart`
- Test: `test/custom_table_test.dart`

- [ ] **Step 1: Add failing tests**

```dart
// append inside test/custom_table_test.dart main()
  group('rollCustomTable', () {
    test('picks a row and returns a GenResult titled by the table name', () {
      const t = CustomTable(id: 't', name: 'Weather', rows: ['Rain', 'Sun', 'Fog']);
      final g = rollCustomTable(t, Dice(_SeqRandom([0]))); // dN(3) -> 1 -> idx 0
      expect(g.title, 'Weather');
      expect(g.rolls, hasLength(1));
      expect(g.rolls.first.value, 'Rain');
      expect(g.rolls.first.detail, 'd3 → 1');
    });

    test('empty table yields a single placeholder roll, no crash', () {
      const t = CustomTable(id: 't', name: 'Empty', rows: []);
      final g = rollCustomTable(t, Dice());
      expect(g.rolls, hasLength(1));
      expect(g.rolls.first.value, isNotEmpty);
    });
  });
```

Add this helper at the bottom of the test file (a `Random` that returns a fixed
sequence so `dN` is deterministic — `dN(n)` calls `nextInt(n)`):

```dart
class _SeqRandom implements Random {
  _SeqRandom(this._values);
  final List<int> _values;
  int _i = 0;
  @override
  int nextInt(int max) => _values[_i++ % _values.length] % max;
  @override
  bool nextBool() => false;
  @override
  double nextDouble() => 0;
}
```

Add `import 'dart:math';` and `import 'package:juice_oracle/engine/dice.dart';`
(plus `models.dart` for `GenResult`) to the test imports.

- [ ] **Step 2: Run, verify fail** — `flutter test test/custom_table_test.dart` →
  FAIL (`rollCustomTable` undefined).

- [ ] **Step 3: Implement**

```dart
// append to lib/engine/custom_table.dart
/// Roll [table]: uniformly pick one row and return it as a one-roll [GenResult].
/// An empty table yields a placeholder roll so the UI never has to special-case.
GenResult rollCustomTable(CustomTable table, Dice dice) {
  if (table.rows.isEmpty) {
    return GenResult(
        title: table.name.isEmpty ? 'Table' : table.name,
        rolls: const [Roll(label: 'Result', value: '(empty table)')]);
  }
  final n = table.rows.length;
  final idx = dice.dN(n); // 1..n
  return GenResult(
    title: table.name.isEmpty ? 'Table' : table.name,
    rolls: [Roll(label: 'Result', value: table.rows[idx - 1], detail: 'd$n → $idx')],
  );
}
```

- [ ] **Step 4: Run, verify pass** — `flutter test test/custom_table_test.dart` → PASS.

- [ ] **Step 5: Commit** — `git commit -am "feat(tables): rollCustomTable -> GenResult"`

---

## Task 3: App-global `customTablesProvider`

**Files:**
- Modify: `lib/state/providers.dart` (add next to `BestiaryNotifier`, ~line 1290)
- Test: `test/custom_tables_provider_test.dart`

- [ ] **Step 1: Write failing persistence test**

```dart
// test/custom_tables_provider_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice_oracle/engine/custom_table.dart';
import 'package:juice_oracle/state/providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('adds, persists, and reloads custom tables', () async {
    SharedPreferences.setMockInitialValues({});
    final c1 = ProviderContainer();
    await c1.read(customTablesProvider.future);
    await c1.read(customTablesProvider.notifier).add(
        const CustomTable(id: 'a', name: 'Names', rows: ['X', 'Y']));
    expect(c1.read(customTablesProvider).value, hasLength(1));
    c1.dispose();

    // New container reads the same mock store -> persisted.
    final c2 = ProviderContainer();
    final loaded = await c2.read(customTablesProvider.future);
    expect(loaded.single.name, 'Names');
    expect(loaded.single.rows, ['X', 'Y']);
    c2.dispose();
  });

  test('replace and remove', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    final n = c.read(customTablesProvider.notifier);
    await c.read(customTablesProvider.future);
    await n.add(const CustomTable(id: 'a', name: 'A', rows: ['1']));
    await n.replace(const CustomTable(id: 'a', name: 'A2', rows: ['1', '2']));
    expect(c.read(customTablesProvider).value!.single.name, 'A2');
    await n.remove('a');
    expect(c.read(customTablesProvider).value, isEmpty);
    c.dispose();
  });
}
```

- [ ] **Step 2: Run, verify fail** — `flutter test test/custom_tables_provider_test.dart`
  → FAIL (`customTablesProvider` undefined).

- [ ] **Step 3: Implement (mirror `BestiaryNotifier`)**

Add after the `bestiaryProvider` definition in `lib/state/providers.dart`. Ensure
`custom_table.dart` is imported at the top of the file (check existing engine imports).

```dart
/// App-global store of user-authored random tables. Like [bestiaryProvider],
/// this is NOT session-scoped and NOT exported — tables are reusable across
/// campaigns and live per-device.
class CustomTablesNotifier extends AsyncNotifier<List<CustomTable>> {
  static const _key = 'juice.custom_tables.v1';

  @override
  Future<List<CustomTable>> build() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    return (jsonDecode(raw) as List)
        .map(CustomTable.maybeFromJson)
        .whereType<CustomTable>()
        .toList();
  }

  Future<List<CustomTable>> get _ready async => state.valueOrNull ?? await future;

  Future<void> _save(List<CustomTable> list) async {
    await (await SharedPreferences.getInstance())
        .setString(_key, jsonEncode(list.map((t) => t.toJson()).toList()));
    state = AsyncData(list);
  }

  Future<void> add(CustomTable t) async => _save([...await _ready, t]);
  Future<void> remove(String id) async =>
      _save((await _ready).where((t) => t.id != id).toList());
  Future<void> replace(CustomTable t) async =>
      _save((await _ready).map((e) => e.id == t.id ? t : e).toList());
}

final customTablesProvider =
    AsyncNotifierProvider<CustomTablesNotifier, List<CustomTable>>(
        CustomTablesNotifier.new);
```

- [ ] **Step 4: Run, verify pass** — `flutter test test/custom_tables_provider_test.dart`
  → PASS.

- [ ] **Step 5: Commit** — `git commit -am "feat(tables): app-global customTablesProvider"`

---

## Task 4: "My Tables" UI in `GenerateSheet`

**Files:**
- Modify: `lib/features/generate_sheet.dart`

This is UI work; verify by `flutter analyze` + device/preview, plus a light widget
test only if the existing `test/generate_sheet_test.dart` harness already overrides
the data providers (see the rootBundle-hang memory — do not add a test that pumps the
sheet without the oracle/verdant/emulator/ruleset overrides).

- [ ] **Step 1: Add a "My Tables" section** above the built-in generator sections in
  the sheet's scroll body (near `generate_sheet.dart:166`). Watch the provider:

```dart
final tables = ref.watch(customTablesProvider).valueOrNull ?? const <CustomTable>[];
```

Render a labeled section:
- A `Wrap` of `ActionChip`s, one per table (`key: Key('table-roll-${t.id}')`), whose
  `onPressed` rolls and logs, mirroring the existing generator chip handler:

```dart
onPressed: () {
  final r = rollCustomTable(t, Dice());
  ref.read(journalProvider.notifier).addResult(r.title, r.asText,
      sourceTool: 'custom-table', payload: r.toPayload());
  Navigator.of(context).pop();
},
```

- A trailing `ActionChip(key: Key('table-new'), label: Text('New table'))` →
  `_showTableDialog(context, ref, null)`.
- Long-press / a small edit affordance per chip is optional; simplest is to make the
  "New table" dialog also list existing tables for edit/delete. To stay lean, give
  each table chip a trailing edit on long-press: `onLongPress: () =>
  _showTableDialog(context, ref, t)`.

- [ ] **Step 2: Add the editor dialog** (top-level in the same file):

```dart
Future<void> _showTableDialog(
    BuildContext context, WidgetRef ref, CustomTable? existing) async {
  final nameCtl = TextEditingController(text: existing?.name ?? '');
  final rowsCtl =
      TextEditingController(text: (existing?.rows ?? const []).join('\n'));
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(existing == null ? 'New table' : 'Edit table'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              key: const Key('table-name'),
              controller: nameCtl,
              decoration: const InputDecoration(labelText: 'Name')),
          TextField(
              key: const Key('table-rows'),
              controller: rowsCtl,
              minLines: 4,
              maxLines: 12,
              decoration: const InputDecoration(
                  labelText: 'Rows (one per line)', alignLabelWithHint: true)),
        ]),
      ),
      actions: [
        if (existing != null)
          TextButton(
            key: const Key('table-delete'),
            onPressed: () async {
              await ref.read(customTablesProvider.notifier).remove(existing.id);
              if (ctx.mounted) Navigator.of(ctx).pop(false);
            },
            child: const Text('Delete'),
          ),
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel')),
        FilledButton(
            key: const Key('table-save'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Save')),
      ],
    ),
  );
  if (result != true) return;
  final rows = rowsCtl.text
      .split('\n')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  final name = nameCtl.text.trim();
  if (name.isEmpty && rows.isEmpty) return;
  final notifier = ref.read(customTablesProvider.notifier);
  if (existing == null) {
    await notifier.add(CustomTable(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: name,
        rows: rows));
  } else {
    await notifier.replace(existing.copyWith(name: name, rows: rows));
  }
}
```

(Use whatever id scheme the file/codebase already uses for fresh ids if there is a
shared `_newId()`/uuid helper — match it; otherwise the timestamp id above is fine.)

- [ ] **Step 3: Ensure imports** — `custom_table.dart`, `dice.dart`, and the
  `customTablesProvider` are imported in `generate_sheet.dart`.

- [ ] **Step 4: Static analysis** — `flutter analyze` → no new errors/warnings.

- [ ] **Step 5: Commit** — `git commit -am "feat(tables): My Tables editor + roll in GenerateSheet"`

---

## Task 5: Verify, document, ship

- [ ] **Step 1: Full suite** — `flutter test` → all green. `flutter analyze` → clean.
- [ ] **Step 2: Device/preview verify** (the play loop): open the journal composer →
  inspire → New table → add ~3 rows → Save → table chip appears → tap it → a `result`
  entry is logged with the rolled row. Edit via long-press; delete works.
- [ ] **Step 3: Update `CLAUDE.md`** — add a "Custom random tables" bullet under
  Project notes (app-global `juice.custom_tables.v1`, pure `lib/engine/custom_table.dart`,
  surfaced in `GenerateSheet`, facts-only/user-authored, P1 = flat uniform list;
  deferred: weights/ranges, Ask-verb surfacing, per-campaign scope).
- [ ] **Step 4: Update the epic doc** — tick Phase 1 in
  `docs/superpowers/plans/2026-06-29-streamline-epic.md`.
- [ ] **Step 5: PR + merge** — branch `feat/custom-oracle-tables`, push, open PR
  titled "feat(tables): user-authored custom oracle tables (Phase 1)", review, merge,
  delete branch. (Use the repo's `/ship-pr` flow.)

---

## Self-review notes

- **Spec coverage:** model (T1) + roll (T2) + persistence (T3) + UI (T4) + verify/ship
  (T5) cover the goal end-to-end.
- **Type consistency:** `CustomTable` fields `id/name/rows`, `copyWith(name,rows)`,
  `rollCustomTable(CustomTable, Dice) -> GenResult`, provider name
  `customTablesProvider` / notifier `CustomTablesNotifier`, key
  `juice.custom_tables.v1`, sourceTool `'custom-table'` — used consistently across tasks.
- **Deferred (YAGNI):** weighted rows, min-max ranges, dice-notation field, Ask-verb
  surfacing, per-campaign/exported scope, import/export of table packs.
