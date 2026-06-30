# Custom Random Tables P2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend user-authored custom oracle tables beyond a flat uniform list to support **weighted rows**, **dice-range rows** (e.g. `01-05`), and a **dice-notation field** (e.g. `2d6`, `d100`).

**Architecture:** The pure engine `lib/engine/custom_table.dart` gains a `CustomRow` model (text + weight + optional min/max span), a `TableRoll` mode enum on `CustomTable`, a `dice` notation string, a tiny dice-notation parser, and three roll branches. All parsing of the editor textarea lives in pure helper functions (`parseRows` / `rowsToText`) so the widget stays thin. The `GenerateSheet` "My Tables" editor adds a mode selector + conditional dice field; the roll chip is unchanged (same `rollCustomTable(t, Dice())` call, new behavior). JSON stays back-compatible: legacy `rows: [String]` still loads.

**Tech Stack:** Dart, Flutter, `flutter_riverpod`, `package:flutter_test`. No new dependencies. No vendored content (user authors every row — facts-only).

---

## Design summary

P1 model: `CustomTable { id, name, rows: List<String> }`, rolled with `dice.dN(rows.length)`.

P2 model:

```dart
enum TableRoll { uniform, weighted, ranges }

class CustomRow {            // one row
  final String text;
  final int weight;          // weighted mode (default 1, min 1)
  final int? min, max;       // ranges mode inclusive span (null = no span)
}

class CustomTable {
  final String id, name;
  final TableRoll mode;      // default uniform (legacy)
  final String dice;         // ranges mode die, e.g. "d100"/"2d6"; "" => d100
  final List<CustomRow> rows;
}
```

Three roll behaviors:
- **uniform** (legacy): `dN(n)` over rows, ignores weight/span. Detail `dN → i`.
- **weighted**: cumulative pick over `sum(weight)`. Detail `dW → k`. Empty-text row = a gap → `(no result)`.
- **ranges**: parse `dice` (fallback `d100`), roll its total, find the row whose `[min,max]` contains it. No match → `(no result)`. Detail `<dice> → v`.

Editor textarea micro-syntax (parsed by pure helpers, not the widget):
- uniform: `text` (one per line)
- weighted: `text | weight` (e.g. `Rain | 3`; missing weight = 1)
- ranges: `min[-max] text` (e.g. `01-05 The Rusty Flagon`, `6 The Sly Fox`)

**Back-compat:** new saves write rows as objects `{t,w,min,max}`; `CustomRow.fromJson` also lifts a bare `String` → `CustomRow(text)`, so persisted P1 tables (`rows:[String]`) still load. `mode` absent → uniform.

---

## File Structure

- `lib/engine/custom_table.dart` — **modify**: add `TableRoll`, `CustomRow`, `DiceNotation`, `parseDiceNotation`, `rollNotation`, extend `CustomTable`, rewrite `rollCustomTable`, add `parseRows`/`rowsToText`. (One pure file, no Flutter.)
- `lib/features/generate_sheet.dart` — **modify**: `_showTableDialog` gains a mode selector + conditional dice field; rows seeded/parsed via the pure helpers. Roll chip call site updated only for the `CustomRow` type.
- `test/custom_table_test.dart` — **modify**: update existing cases for `CustomRow`; add parser/roll/helper cases.
- `test/custom_tables_provider_test.dart` — **modify**: update `rows` assertions for `CustomRow`; add a ranges round-trip case.
- `test/generate_sheet_test.dart` — **modify**: add a widget test creating + rolling a ranges table.
- `CLAUDE.md` — **modify**: flip the custom-tables bullet from "P1 = flat uniform list; deferred: weighted/min-max-range rows, a dice-notation field" to shipped.

---

## Task 1: Dice-notation parser (pure)

**Files:**
- Modify: `lib/engine/custom_table.dart`
- Test: `test/custom_table_test.dart`

- [ ] **Step 1: Write the failing tests**

Add to `test/custom_table_test.dart` inside `void main() { ... }`:

```dart
  group('parseDiceNotation', () {
    test('parses d-only, count d, case/space tolerant', () {
      expect(parseDiceNotation('d6')!.count, 1);
      expect(parseDiceNotation('d6')!.sides, 6);
      expect(parseDiceNotation('2d6')!.count, 2);
      expect(parseDiceNotation(' D100 ')!.sides, 100);
      expect(parseDiceNotation('1 d 20')!.sides, 20);
    });
    test('rejects garbage and out-of-range', () {
      expect(parseDiceNotation(''), isNull);
      expect(parseDiceNotation('d'), isNull);
      expect(parseDiceNotation('hello'), isNull);
      expect(parseDiceNotation('d1'), isNull); // sides < 2
      expect(parseDiceNotation('0d6'), isNull); // count < 1
    });
    test('rollNotation sums count dice', () {
      // _SeqRandom yields nextInt -> values; dN(sides)=value%sides+1
      final d = Dice(_SeqRandom([0, 2])); // d6 -> 1, then 3
      expect(rollNotation(const DiceNotation(2, 6), d), 1 + 3);
    });
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/custom_table_test.dart`
Expected: FAIL — `parseDiceNotation`, `DiceNotation`, `rollNotation` undefined.

- [ ] **Step 3: Implement in `lib/engine/custom_table.dart`**

Add below the imports (before `CustomTable`):

```dart
/// A parsed `NdM` dice expression (count·dSides). [count]>=1, [sides]>=2.
class DiceNotation {
  const DiceNotation(this.count, this.sides);
  final int count;
  final int sides;
}

final _diceRe = RegExp(r'^(\d*)d(\d+)$');

/// Parse `d6`/`2d6`/`d100` (whitespace + case tolerant). Returns null on garbage
/// or out-of-range (count 1..100, sides 2..1000).
DiceNotation? parseDiceNotation(String raw) {
  final s = raw.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  final m = _diceRe.firstMatch(s);
  if (m == null) return null;
  final count = m.group(1)!.isEmpty ? 1 : int.parse(m.group(1)!);
  final sides = int.parse(m.group(2)!);
  if (count < 1 || count > 100 || sides < 2 || sides > 1000) return null;
  return DiceNotation(count, sides);
}

/// Sum [n.count] rolls of d[n.sides].
int rollNotation(DiceNotation n, Dice dice) {
  var total = 0;
  for (var i = 0; i < n.count; i++) {
    total += dice.dN(n.sides);
  }
  return total;
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/custom_table_test.dart`
Expected: PASS (the parser group; pre-existing roll tests may still fail until Task 2 — that's expected, ignore them for now).

- [ ] **Step 5: Commit**

```bash
git add lib/engine/custom_table.dart test/custom_table_test.dart
git commit -m "feat(custom-table): dice-notation parser + roller"
```

---

## Task 2: CustomRow model + extend CustomTable (back-compat JSON)

**Files:**
- Modify: `lib/engine/custom_table.dart`
- Test: `test/custom_table_test.dart`

- [ ] **Step 1: Write the failing tests**

Replace the existing `group('CustomTable JSON', ...)` block in `test/custom_table_test.dart` with:

```dart
  group('CustomTable JSON', () {
    test('round-trips id/name/mode/dice/rows', () {
      const t = CustomTable(
        id: 't1',
        name: 'Tavern Names',
        mode: TableRoll.ranges,
        dice: 'd100',
        rows: [
          CustomRow('The Rusty Flagon', min: 1, max: 50),
          CustomRow('The Sly Fox', min: 51, max: 100),
        ],
      );
      final back = CustomTable.fromJson(t.toJson());
      expect(back.id, 't1');
      expect(back.name, 'Tavern Names');
      expect(back.mode, TableRoll.ranges);
      expect(back.dice, 'd100');
      expect(back.rows.map((r) => r.text).toList(),
          ['The Rusty Flagon', 'The Sly Fox']);
      expect(back.rows.first.min, 1);
      expect(back.rows.first.max, 50);
    });

    test('weighted row round-trips weight', () {
      const t = CustomTable(
          id: 'w', name: 'W', mode: TableRoll.weighted,
          rows: [CustomRow('Rain', weight: 3), CustomRow('Sun')]);
      final back = CustomTable.fromJson(t.toJson());
      expect(back.rows.first.weight, 3);
      expect(back.rows[1].weight, 1);
    });

    test('legacy string rows still load (back-compat)', () {
      final t = CustomTable.maybeFromJson(
          {'id': 'a', 'name': 'n', 'rows': ['Rain', 'Sun']});
      expect(t, isNotNull);
      expect(t!.mode, TableRoll.uniform);
      expect(t.rows.map((r) => r.text).toList(), ['Rain', 'Sun']);
      expect(t.rows.first.weight, 1);
    });

    test('maybeFromJson returns null on malformed input', () {
      expect(CustomTable.maybeFromJson('not a map'), isNull);
      expect(CustomTable.maybeFromJson({'name': 'x'}), isNull); // missing id
    });

    test('maybeFromJson drops non-string/non-map rows tolerantly', () {
      final t = CustomTable.maybeFromJson({
        'id': 'a',
        'name': 'n',
        'rows': ['ok', 3, null, {'t': 'fine', 'w': 2}],
      });
      expect(t, isNotNull);
      expect(t!.rows.map((r) => r.text).toList(), ['ok', 'fine']);
      expect(t.rows[1].weight, 2);
    });
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/custom_table_test.dart`
Expected: FAIL — `TableRoll`, `CustomRow` undefined; `CustomTable` has no `mode`/`dice`.

- [ ] **Step 3: Implement in `lib/engine/custom_table.dart`**

Add the enum + `CustomRow` above `CustomTable`:

```dart
/// How a [CustomTable] resolves a roll.
enum TableRoll { uniform, weighted, ranges }

TableRoll _tableRollFromName(String? s) => switch (s) {
      'weighted' => TableRoll.weighted,
      'ranges' => TableRoll.ranges,
      _ => TableRoll.uniform,
    };

/// One row of a [CustomTable]. [weight] biases weighted picks (min 1).
/// [min]/[max] give the inclusive span this row covers in ranges mode.
class CustomRow {
  const CustomRow(this.text, {this.weight = 1, this.min, this.max});
  final String text;
  final int weight;
  final int? min;
  final int? max;

  Map<String, dynamic> toJson() => {
        't': text,
        if (weight != 1) 'w': weight,
        if (min != null) 'min': min,
        if (max != null) 'max': max,
      };

  /// Lifts a bare String (legacy) or an object map into a [CustomRow].
  static CustomRow fromJson(Object? raw) {
    if (raw is String) return CustomRow(raw);
    if (raw is Map) {
      final m = raw.cast<String, dynamic>();
      return CustomRow(
        (m['t'] as String?) ?? '',
        weight: (m['w'] as num?)?.toInt() ?? 1,
        min: (m['min'] as num?)?.toInt(),
        max: (m['max'] as num?)?.toInt(),
      );
    }
    return const CustomRow('');
  }
}
```

Replace the entire `class CustomTable { ... }` body with:

```dart
/// A user-authored random table.
class CustomTable {
  const CustomTable({
    required this.id,
    required this.name,
    this.mode = TableRoll.uniform,
    this.dice = '',
    this.rows = const [],
  });

  final String id;
  final String name;
  final TableRoll mode;
  final String dice;
  final List<CustomRow> rows;

  CustomTable copyWith({
    String? name,
    TableRoll? mode,
    String? dice,
    List<CustomRow>? rows,
  }) =>
      CustomTable(
        id: id,
        name: name ?? this.name,
        mode: mode ?? this.mode,
        dice: dice ?? this.dice,
        rows: rows ?? this.rows,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (mode != TableRoll.uniform) 'mode': mode.name,
        if (dice.isNotEmpty) 'dice': dice,
        'rows': rows.map((r) => r.toJson()).toList(),
      };

  factory CustomTable.fromJson(Map<String, dynamic> j) => CustomTable(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        mode: _tableRollFromName(j['mode'] as String?),
        dice: (j['dice'] as String?) ?? '',
        rows: [
          for (final r in (j['rows'] as List? ?? const []))
            if (r is String || r is Map) CustomRow.fromJson(r),
        ],
      );

  /// Tolerant decode for persistence: null when [raw] is not a map or lacks id.
  static CustomTable? maybeFromJson(Object? raw) {
    if (raw is! Map) return null;
    final map = raw.cast<String, dynamic>();
    if (map['id'] is! String) return null;
    return CustomTable.fromJson(map);
  }
}
```

- [ ] **Step 4: Run to verify the JSON group passes**

Run: `flutter test test/custom_table_test.dart -p vm --plain-name 'CustomTable JSON'`
Expected: PASS for the JSON group. (The `rollCustomTable` group will FAIL to COMPILE because its old cases use `rows: ['Rain', ...]` — fixed in Task 3.)

- [ ] **Step 5: Commit**

```bash
git add lib/engine/custom_table.dart test/custom_table_test.dart
git commit -m "feat(custom-table): CustomRow model + mode/dice fields, back-compat JSON"
```

---

## Task 3: rollCustomTable — weighted + ranges branches

**Files:**
- Modify: `lib/engine/custom_table.dart`
- Test: `test/custom_table_test.dart`

- [ ] **Step 1: Write the failing tests**

Replace the existing `group('rollCustomTable', ...)` block with:

```dart
  group('rollCustomTable', () {
    test('uniform: picks a row, GenResult titled by the table name', () {
      const t = CustomTable(
          id: 't',
          name: 'Weather',
          rows: [CustomRow('Rain'), CustomRow('Sun'), CustomRow('Fog')]);
      final g = rollCustomTable(t, Dice(_SeqRandom([0]))); // dN(3) -> 1
      expect(g.title, 'Weather');
      expect(g.rolls.single.value, 'Rain');
      expect(g.rolls.single.detail, 'd3 → 1');
    });

    test('empty table yields a single placeholder roll, no crash', () {
      const t = CustomTable(id: 't', name: 'Empty', rows: []);
      final g = rollCustomTable(t, Dice());
      expect(g.rolls.single.value, isNotEmpty);
    });

    test('weighted: cumulative pick lands in the heavy row', () {
      const t = CustomTable(
          id: 't', name: 'W', mode: TableRoll.weighted,
          rows: [CustomRow('Rare', weight: 1), CustomRow('Common', weight: 9)]);
      // total = 10; dN(10): nextInt(10) -> value, +1. value 4 -> hit 5 -> Common.
      final g = rollCustomTable(t, Dice(_SeqRandom([4])));
      expect(g.rolls.single.value, 'Common');
      expect(g.rolls.single.detail, 'd10 → 5');
    });

    test('weighted: empty-text row reads as (no result)', () {
      const t = CustomTable(
          id: 't', name: 'W', mode: TableRoll.weighted,
          rows: [CustomRow('', weight: 1)]);
      final g = rollCustomTable(t, Dice(_SeqRandom([0]))); // hit 1
      expect(g.rolls.single.value, '(no result)');
    });

    test('ranges: matches the row whose span contains the roll', () {
      const t = CustomTable(
        id: 't', name: 'R', mode: TableRoll.ranges, dice: 'd100',
        rows: [
          CustomRow('Low', min: 1, max: 50),
          CustomRow('High', min: 51, max: 100),
        ],
      );
      // d100: nextInt(100) -> 74, +1 -> 75 -> High.
      final g = rollCustomTable(t, Dice(_SeqRandom([74])));
      expect(g.rolls.single.value, 'High');
      expect(g.rolls.single.detail, 'd100 → 75');
    });

    test('ranges: gap (no covering span) yields (no result)', () {
      const t = CustomTable(
        id: 't', name: 'R', mode: TableRoll.ranges, dice: 'd100',
        rows: [CustomRow('Only', min: 1, max: 10)],
      );
      final g = rollCustomTable(t, Dice(_SeqRandom([74]))); // -> 75, no match
      expect(g.rolls.single.value, '(no result)');
      expect(g.rolls.single.detail, 'd100 → 75');
    });

    test('ranges: blank/garbage dice falls back to d100', () {
      const t = CustomTable(
        id: 't', name: 'R', mode: TableRoll.ranges, dice: '',
        rows: [CustomRow('Hit', min: 1, max: 100)],
      );
      final g = rollCustomTable(t, Dice(_SeqRandom([0]))); // -> 1
      expect(g.rolls.single.value, 'Hit');
      expect(g.rolls.single.detail, 'd100 → 1');
    });
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/custom_table_test.dart`
Expected: FAIL — weighted/ranges produce wrong values (still uniform `dN(n)`).

- [ ] **Step 3: Implement in `lib/engine/custom_table.dart`**

Replace the entire `rollCustomTable` function with:

```dart
/// Roll [table] per its [CustomTable.mode]. An empty table yields a placeholder
/// so the UI never has to special-case.
GenResult rollCustomTable(CustomTable table, Dice dice) {
  final title = table.name.isEmpty ? 'Table' : table.name;
  if (table.rows.isEmpty) {
    return GenResult(
        title: title,
        rolls: const [Roll(label: 'Result', value: '(empty table)')]);
  }
  switch (table.mode) {
    case TableRoll.ranges:
      return _rollRanges(table, dice, title);
    case TableRoll.weighted:
      return _rollWeighted(table, dice, title);
    case TableRoll.uniform:
      final n = table.rows.length;
      final idx = dice.dN(n); // 1..n
      return GenResult(title: title, rolls: [
        Roll(
            label: 'Result',
            value: table.rows[idx - 1].text,
            detail: 'd$n → $idx'),
      ]);
  }
}

String _value(String text) => text.isEmpty ? '(no result)' : text;

GenResult _rollWeighted(CustomTable table, Dice dice, String title) {
  final weights = [for (final r in table.rows) r.weight < 1 ? 1 : r.weight];
  final total = weights.fold<int>(0, (a, b) => a + b);
  final hit = dice.dN(total); // 1..total
  var acc = 0;
  for (var i = 0; i < table.rows.length; i++) {
    acc += weights[i];
    if (hit <= acc) {
      return GenResult(title: title, rolls: [
        Roll(
            label: 'Result',
            value: _value(table.rows[i].text),
            detail: 'd$total → $hit'),
      ]);
    }
  }
  // Unreachable (hit <= total), but keep total-safe.
  return GenResult(title: title, rolls: [
    Roll(
        label: 'Result',
        value: _value(table.rows.last.text),
        detail: 'd$total → $hit'),
  ]);
}

GenResult _rollRanges(CustomTable table, Dice dice, String title) {
  final n = parseDiceNotation(table.dice) ?? const DiceNotation(1, 100);
  final v = rollNotation(n, dice);
  final label = parseDiceNotation(table.dice) == null
      ? 'd100'
      : table.dice.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  for (final r in table.rows) {
    final lo = r.min;
    final hi = r.max ?? r.min;
    if (lo != null && hi != null && v >= lo && v <= hi) {
      return GenResult(title: title, rolls: [
        Roll(label: 'Result', value: _value(r.text), detail: '$label → $v'),
      ]);
    }
  }
  return GenResult(title: title, rolls: [
    Roll(label: 'Result', value: '(no result)', detail: '$label → $v'),
  ]);
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/custom_table_test.dart`
Expected: PASS (all groups).

- [ ] **Step 5: Commit**

```bash
git add lib/engine/custom_table.dart test/custom_table_test.dart
git commit -m "feat(custom-table): weighted + dice-range roll modes"
```

---

## Task 4: Textarea parse/serialize helpers (pure)

**Files:**
- Modify: `lib/engine/custom_table.dart`
- Test: `test/custom_table_test.dart`

- [ ] **Step 1: Write the failing tests**

Add a new group to `test/custom_table_test.dart`:

```dart
  group('parseRows / rowsToText', () {
    test('uniform: line per row, round-trips', () {
      final rows = parseRows('Rain\n  Sun  \n\nFog', TableRoll.uniform);
      expect(rows.map((r) => r.text).toList(), ['Rain', 'Sun', 'Fog']);
      expect(rowsToText(rows, TableRoll.uniform), 'Rain\nSun\nFog');
    });

    test('weighted: "text | weight", default 1, round-trips', () {
      final rows = parseRows('Rain | 3\nSun\nFog | x', TableRoll.weighted);
      expect(rows[0].text, 'Rain');
      expect(rows[0].weight, 3);
      expect(rows[1].weight, 1);
      expect(rows[2].text, 'Fog'); // unparseable weight -> 1
      expect(rows[2].weight, 1);
      expect(rowsToText(rows, TableRoll.weighted), 'Rain | 3\nSun\nFog');
    });

    test('ranges: "min[-max] text", round-trips', () {
      final rows =
          parseRows('01-05 Rusty Flagon\n6 Sly Fox', TableRoll.ranges);
      expect(rows[0].text, 'Rusty Flagon');
      expect(rows[0].min, 1);
      expect(rows[0].max, 5);
      expect(rows[1].min, 6);
      expect(rows[1].max, 6);
      expect(rowsToText(rows, TableRoll.ranges), '1-5 Rusty Flagon\n6 Sly Fox');
    });

    test('ranges: a line with no leading number keeps text, no span', () {
      final rows = parseRows('Plain line', TableRoll.ranges);
      expect(rows.single.text, 'Plain line');
      expect(rows.single.min, isNull);
    });
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/custom_table_test.dart`
Expected: FAIL — `parseRows`, `rowsToText` undefined.

- [ ] **Step 3: Implement in `lib/engine/custom_table.dart`**

Append at the end of the file:

```dart
/// Parse the editor textarea into rows for [mode].
List<CustomRow> parseRows(String text, TableRoll mode) {
  final lines =
      text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty);
  return switch (mode) {
    TableRoll.uniform => [for (final l in lines) CustomRow(l)],
    TableRoll.weighted => [for (final l in lines) _parseWeightedLine(l)],
    TableRoll.ranges => [for (final l in lines) _parseRangeLine(l)],
  };
}

CustomRow _parseWeightedLine(String line) {
  final i = line.lastIndexOf('|');
  if (i < 0) return CustomRow(line);
  final text = line.substring(0, i).trim();
  final w = int.tryParse(line.substring(i + 1).trim()) ?? 1;
  return CustomRow(text.isEmpty ? line : text, weight: w < 1 ? 1 : w);
}

final _rangeLineRe = RegExp(r'^(\d+)(?:\s*-\s*(\d+))?\s+(.*)$');

CustomRow _parseRangeLine(String line) {
  final m = _rangeLineRe.firstMatch(line);
  if (m == null) return CustomRow(line);
  final lo = int.parse(m.group(1)!);
  final hi = m.group(2) != null ? int.parse(m.group(2)!) : lo;
  return CustomRow(m.group(3)!.trim(), min: lo, max: hi);
}

/// Serialize [rows] back to the editor textarea syntax for [mode].
String rowsToText(List<CustomRow> rows, TableRoll mode) => switch (mode) {
      TableRoll.uniform => rows.map((r) => r.text).join('\n'),
      TableRoll.weighted => rows
          .map((r) => r.weight == 1 ? r.text : '${r.text} | ${r.weight}')
          .join('\n'),
      TableRoll.ranges => rows.map((r) {
          final lo = r.min;
          final hi = r.max;
          if (lo == null) return r.text;
          final span = (hi == null || hi == lo) ? '$lo' : '$lo-$hi';
          return '$span ${r.text}';
        }).join('\n'),
    };
```

Note in `_parseWeightedLine`: a line like `| 3` (empty text before the bar) keeps the raw `line` as text rather than producing an empty row — defensive against accidental leading bars.

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/custom_table_test.dart`
Expected: PASS (all groups).

- [ ] **Step 5: Commit**

```bash
git add lib/engine/custom_table.dart test/custom_table_test.dart
git commit -m "feat(custom-table): pure textarea parse/serialize helpers"
```

---

## Task 5: GenerateSheet editor — mode selector + dice field

**Files:**
- Modify: `lib/features/generate_sheet.dart`
- Test: `test/generate_sheet_test.dart`

- [ ] **Step 1: Write the failing widget test**

Add to `test/generate_sheet_test.dart` inside `void main()` (after the existing table-related tests, or at the end):

```dart
  testWidgets('creates a ranges table and rolls it to a journal entry',
      (tester) async {
    final c = await _makeContainer();
    await _pumpSheet(tester, c);

    // Open the new-table dialog.
    await tester.tap(find.byKey(const Key('table-new')));
    await tester.pumpAndSettle();

    // Name it.
    await tester.enterText(find.byKey(const Key('table-name')), 'Loot');

    // Switch to Ranges mode -> dice field appears.
    await tester.tap(find.text('Ranges'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('table-dice')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('table-dice')), 'd100');
    await tester.enterText(find.byKey(const Key('table-rows')),
        '1-50 Copper\n51-100 Gold');
    await tester.tap(find.byKey(const Key('table-save')));
    await tester.pumpAndSettle();

    // The table persisted with ranges mode.
    final tables = await c.read(customTablesProvider.future);
    expect(tables.single.name, 'Loot');
    expect(tables.single.mode, TableRoll.ranges);
    expect(tables.single.dice, 'd100');
    expect(tables.single.rows, hasLength(2));

    // Roll it -> a journal entry with the custom-table source tool.
    await tester.tap(find.byKey(Key('table-roll-${tables.single.id}')));
    await tester.pumpAndSettle();
    final entries = await c.read(journalProvider.future);
    expect(entries.single.sourceTool, 'custom-table');
  });
```

Add the import at the top of `test/generate_sheet_test.dart` if not present:

```dart
import 'package:juice_oracle/engine/custom_table.dart';
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/generate_sheet_test.dart --plain-name 'creates a ranges table'`
Expected: FAIL — no `table-mode`/`table-dice` widgets; mode not persisted.

- [ ] **Step 3: Implement — replace `_showTableDialog`**

In `lib/features/generate_sheet.dart`, replace the entire `_showTableDialog` function with:

```dart
/// New/edit/delete editor for a user-authored [CustomTable]. The rows textarea
/// syntax depends on the selected [TableRoll] mode (see [parseRows]/[rowsToText]).
Future<void> _showTableDialog(
    BuildContext context, WidgetRef ref, CustomTable? existing) async {
  final nameCtl = TextEditingController(text: existing?.name ?? '');
  final diceCtl = TextEditingController(text: existing?.dice ?? '');
  var mode = existing?.mode ?? TableRoll.uniform;
  final rowsCtl =
      TextEditingController(text: rowsToText(existing?.rows ?? const [], mode));

  String hintFor(TableRoll m) => switch (m) {
        TableRoll.uniform => 'One result per line',
        TableRoll.weighted => 'One per line: text | weight   (e.g. Rain | 3)',
        TableRoll.ranges =>
          'One per line: range then text   (e.g. 01-05 Rusty Flagon)',
      };

  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(existing == null ? 'New table' : 'Edit table'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                key: const Key('table-name'),
                controller: nameCtl,
                decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 12),
            SegmentedButton<TableRoll>(
              key: const Key('table-mode'),
              segments: const [
                ButtonSegment(
                    value: TableRoll.uniform, label: Text('Uniform')),
                ButtonSegment(
                    value: TableRoll.weighted, label: Text('Weighted')),
                ButtonSegment(value: TableRoll.ranges, label: Text('Ranges')),
              ],
              selected: {mode},
              showSelectedIcon: false,
              onSelectionChanged: (s) {
                // Re-serialize the current rows into the new mode's syntax so
                // the textarea stays consistent across mode switches.
                final rows = parseRows(rowsCtl.text, mode);
                setState(() {
                  mode = s.first;
                  rowsCtl.text = rowsToText(rows, mode);
                });
              },
            ),
            if (mode == TableRoll.ranges) ...[
              const SizedBox(height: 8),
              TextField(
                  key: const Key('table-dice'),
                  controller: diceCtl,
                  decoration: const InputDecoration(
                      labelText: 'Dice', hintText: 'd100, 2d6, …')),
            ],
            const SizedBox(height: 8),
            TextField(
                key: const Key('table-rows'),
                controller: rowsCtl,
                minLines: 4,
                maxLines: 12,
                decoration: InputDecoration(
                    labelText: 'Rows',
                    helperText: hintFor(mode),
                    helperMaxLines: 2,
                    alignLabelWithHint: true)),
          ]),
        ),
        actions: [
          if (existing != null)
            TextButton(
              key: const Key('table-delete'),
              onPressed: () async {
                await ref
                    .read(customTablesProvider.notifier)
                    .remove(existing.id);
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
    ),
  );
  if (result != true) return;
  final rows = parseRows(rowsCtl.text, mode);
  final name = nameCtl.text.trim();
  if (name.isEmpty && rows.isEmpty) return;
  final dice = mode == TableRoll.ranges ? diceCtl.text.trim() : '';
  final notifier = ref.read(customTablesProvider.notifier);
  if (existing == null) {
    await notifier.add(CustomTable(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: name,
        mode: mode,
        dice: dice,
        rows: rows));
  } else {
    await notifier.replace(
        existing.copyWith(name: name, mode: mode, dice: dice, rows: rows));
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/generate_sheet_test.dart`
Expected: PASS (new test + all existing GenerateSheet tests).

- [ ] **Step 5: Run the full suite + analyzer**

Run: `flutter analyze && flutter test`
Expected: No analyzer issues; all tests pass. (Fix any call-site breakage in `generate_sheet.dart` where the roll chip referenced `t.rows` as strings — the chip uses `rollCustomTable(t, Dice())` and `t.name` only, so no change is expected, but confirm.)

- [ ] **Step 6: Commit**

```bash
git add lib/features/generate_sheet.dart test/generate_sheet_test.dart
git commit -m "feat(custom-table): editor mode selector + dice field"
```

---

## Task 6: Provider round-trip test + docs

**Files:**
- Modify: `test/custom_tables_provider_test.dart`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update the existing provider tests for `CustomRow` + add a ranges round-trip**

In `test/custom_tables_provider_test.dart`, update the two existing assertions that compare `rows` to `List<String>` and add a new test. Replace the file body's `main()` with:

```dart
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('adds, persists, and reloads custom tables', () async {
    SharedPreferences.setMockInitialValues({});
    final c1 = ProviderContainer();
    await c1.read(customTablesProvider.future);
    await c1.read(customTablesProvider.notifier).add(const CustomTable(
        id: 'a', name: 'Names', rows: [CustomRow('X'), CustomRow('Y')]));
    expect(c1.read(customTablesProvider).value, hasLength(1));
    c1.dispose();

    final c2 = ProviderContainer();
    final loaded = await c2.read(customTablesProvider.future);
    expect(loaded.single.name, 'Names');
    expect(loaded.single.rows.map((r) => r.text).toList(), ['X', 'Y']);
    c2.dispose();
  });

  test('persists ranges mode + dice + spans', () async {
    SharedPreferences.setMockInitialValues({});
    final c1 = ProviderContainer();
    await c1.read(customTablesProvider.future);
    await c1.read(customTablesProvider.notifier).add(const CustomTable(
          id: 'r',
          name: 'Loot',
          mode: TableRoll.ranges,
          dice: 'd100',
          rows: [CustomRow('Gold', min: 1, max: 100)],
        ));
    c1.dispose();

    final c2 = ProviderContainer();
    final loaded = await c2.read(customTablesProvider.future);
    expect(loaded.single.mode, TableRoll.ranges);
    expect(loaded.single.dice, 'd100');
    expect(loaded.single.rows.single.max, 100);
    c2.dispose();
  });

  test('loads legacy string-row tables from prefs', () async {
    SharedPreferences.setMockInitialValues({
      'juice.custom_tables.v1':
          '[{"id":"old","name":"Legacy","rows":["A","B"]}]',
    });
    final c = ProviderContainer();
    final loaded = await c.read(customTablesProvider.future);
    expect(loaded.single.mode, TableRoll.uniform);
    expect(loaded.single.rows.map((r) => r.text).toList(), ['A', 'B']);
    c.dispose();
  });

  test('replace and remove', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    final n = c.read(customTablesProvider.notifier);
    await c.read(customTablesProvider.future);
    await n.add(const CustomTable(id: 'a', name: 'A', rows: [CustomRow('1')]));
    await n.replace(const CustomTable(
        id: 'a', name: 'A2', rows: [CustomRow('1'), CustomRow('2')]));
    expect(c.read(customTablesProvider).value!.single.name, 'A2');
    await n.remove('a');
    expect(c.read(customTablesProvider).value, isEmpty);
    c.dispose();
  });
}
```

- [ ] **Step 2: Run to verify it passes**

Run: `flutter test test/custom_tables_provider_test.dart`
Expected: PASS.

- [ ] **Step 3: Update `CLAUDE.md`**

Find the custom-tables bullet (search for `**Custom random tables** (Streamline epic Phase 1)`). Replace its trailing scope sentence:

> **Facts-only:** ships zero vendored content — the user authors every row. P1 = flat uniform list; deferred: weighted/min-max-range rows, a dice-notation field, Ask-verb surfacing, per-campaign/exported scope, import/export of table packs.

with:

> **Facts-only:** ships zero vendored content — the user authors every row. P2 added `TableRoll` modes (uniform / **weighted** / **ranges**): each `CustomRow` carries a `weight` + optional `min`/`max` span, and `CustomTable` carries a `mode` + `dice` notation (`parseDiceNotation`/`rollNotation`); the editor exposes a mode selector + a dice field, with pure `parseRows`/`rowsToText` driving the textarea micro-syntax (`text | weight`, `min-max text`). Legacy `rows:[String]` JSON still loads (uniform). Deferred: Ask-verb surfacing, per-campaign/exported scope, import/export of table packs. See `docs/superpowers/plans/2026-06-30-custom-tables-p2.md`.

- [ ] **Step 4: Final verification**

Run: `flutter analyze && flutter test`
Expected: No issues; all tests pass.

- [ ] **Step 5: Commit**

```bash
git add test/custom_tables_provider_test.dart CLAUDE.md
git commit -m "test(custom-table): provider round-trip + legacy load; docs"
```

---

## Self-Review

**Spec coverage:**
- Weighted rows → Task 2 (`CustomRow.weight`) + Task 3 (`_rollWeighted`). ✅
- Min/max range rows → Task 2 (`min`/`max`) + Task 3 (`_rollRanges`). ✅
- Dice-notation field → Task 1 (`parseDiceNotation`) + Task 2 (`CustomTable.dice`) + Task 5 (`table-dice` field). ✅
- Editor support → Task 4 (parse/serialize) + Task 5 (mode selector). ✅
- Back-compat (don't lose user tables) → Task 2 (`CustomRow.fromJson` lifts strings) + Task 6 (legacy-load test). ✅

**Placeholder scan:** No TBD/TODO; every code step has full code. ✅

**Type consistency:** `TableRoll` / `CustomRow` / `CustomTable.mode` / `CustomTable.dice` / `parseDiceNotation` / `rollNotation` / `parseRows` / `rowsToText` used identically across tasks. `rollCustomTable(CustomTable, Dice)` signature unchanged. The roll-chip call site (`rollCustomTable(t, Dice())`, uses `t.name` only) needs no change. ✅

**Notes for the implementer:**
- Widget tests pumping screens that load asset data hang without the `_makeContainer` override harness — Task 5 reuses the existing `generate_sheet_test.dart` harness, which already overrides `oracleProvider` + builds `sessionsProvider`. Do not add `*.load()` calls.
- `SegmentedButton` is Material; `generate_sheet.dart` already imports `flutter/material.dart`.
- The `switch` expressions are exhaustive over `TableRoll` — adding a 4th mode later forces a compile error here (intentional).
