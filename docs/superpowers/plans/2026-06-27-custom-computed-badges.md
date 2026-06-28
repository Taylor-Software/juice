# Custom Sheet — Computed Badges Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a read-only `computed` block to the Custom/Homebrew sheet — a two-operand, one-binary-op derived value that renders a number badge (arithmetic) or a conditional chip (comparison), referencing other blocks' values.

**Architecture:** A pure, total `resolveComputed(blocks, values, ComputedConfig)` in `lib/engine/custom_sheet.dart` (alongside `resolveRoll`/`customStatMod`); a `computed` `CustomBlockType` with its formula in `block.config` (no play-state value — derived on render); a play renderer + a config dialog in `lib/features/custom_sheet.dart`. No expression parser; cycle-free (a computed block can't reference another computed block).

**Tech Stack:** Flutter, flutter_riverpod, Dart. Prefix flutter commands with `export PATH="$HOME/development/flutter/bin:$PATH"`. `dart format` hook runs on `.dart` edits. Model tests in `test/custom_sheet_model_test.dart`, widget tests in `test/custom_sheet_ui_test.dart`.

---

## File structure

- **Modify** `lib/engine/custom_sheet.dart` — add `ComputedOp` enum, `ComputedOperand`, `ComputedConfig` (+ tolerant JSON), `resolveComputed` + `_lookup`; add `computed` to `CustomBlockType`.
- **Modify** `lib/features/custom_sheet.dart` — `_playComputed`, `_configComputed` + `_ComputedConfigDialog`; arms in `_playBlock`, `_configBlock`, `_defaultLabel`, `defaultConfigFor`.
- **Modify** `test/custom_sheet_model_test.dart` — `resolveComputed` + JSON tests.
- **Modify** `test/custom_sheet_ui_test.dart` — computed badge/chip + config-dialog tests.
- **Modify** `CLAUDE.md` — note the computed block.

### Verified anchors (from recon)

- `CustomBlockType` enum (engine, lines 43-55): `stat, counter, hp, roll, luck, conditions, dropdown, freeform, timer, togglechips, progress`. `_blockTypeFromName` = `values.where((e)=>e.name==n).firstOrNull`.
- Enum<->name JSON idiom: `Enum.values.firstWhere((e) => e.name == j['k'], orElse: () => Default)`.
- `CustomBlock { id, type, label, config }`; `config` is a `Map<String,dynamic>`; `toJson` writes `config` only when non-empty; `maybeFromJson` drops unknown types (forward-compat).
- `RollConfig` is the config-object precedent (short-key `toJson` + tolerant `fromJson`).
- Features file class: `_CustomSheetViewState extends ConsumerState<CustomSheetView>`; `CustomSheet get _s => widget.character.custom ?? const CustomSheet();`.
- `_playBlock(b)` is an **exhaustive** `switch` expression (adding an enum value breaks compilation until an arm is added). `_defaultLabel(t)` is also an exhaustive switch expression. `defaultConfigFor(t)` has a `_ => const {}` default. `_configBlock(b)` has a `default: _renameBlock(b)`.
- Helpers: `int _valInt(id, fallback)`, `Map<String,dynamic> _valMap(id)`, `void _setVal(id, v)`, `void _save(CustomSheet next)`, `int _intCfg(b, key, fallback)`.
- Add-block picker `_addBlock` iterates `CustomBlockType.values` showing `Text(t.name)` → a new enum value auto-appears (as "computed"); on create it sets `label: _defaultLabel(type)`, `config: defaultConfigFor(type)` then opens `_configBlock`.
- Config-dialog pattern: `_configCounter` does `showDialog<_CounterCfg>` → on result `_save(_s.copyWith(blocks: _s.blocks.map((x)=> x.id==b.id ? x.copyWith(label:.., config:{...}) : x).toList()))`. `_StatConfigDialog` is the StatefulWidget precedent.
- Test harness `_pump(tester, {sheet})` seeds prefs + `UncontrolledProviderScope` + a `Consumer` live-read; `_bigView(tester)` sets a large physical size. Model tests are pure.

---

## Task 1: Engine — computed model + resolver

**Files:** Modify `lib/engine/custom_sheet.dart`; Test `test/custom_sheet_model_test.dart`.

Add the pure types + resolver. Do NOT add `computed` to `CustomBlockType` yet (Task 2) — `resolveComputed` takes a `ComputedConfig`, not a block, so it's testable without the enum value and the features file stays compiling.

- [ ] **Step 1: Write failing tests** — append to `test/custom_sheet_model_test.dart` (inside `main()`):

```dart
  group('resolveComputed', () {
    // a stat block 's1' with con=14, and an hp block 'h1' with cur=4/max=10
    const blocks = [
      CustomBlock(id: 's1', type: CustomBlockType.stat, label: 'Abilities', config: {
        'stats': [
          {'key': 'con', 'label': 'CON'}
        ],
        'min': 3,
        'max': 18,
      }),
      CustomBlock(id: 'h1', type: CustomBlockType.hp, label: 'HP'),
      CustomBlock(id: 'c1', type: CustomBlockType.counter, label: 'AC'),
    ];
    const values = {
      's1': {'con': 14},
      'h1': {'cur': 4, 'max': 10},
      'c1': 15,
    };

    test('10 + CON → number 24', () {
      const cfg = ComputedConfig(
        a: ComputedOperand(constant: 10),
        op: ComputedOp.add,
        b: ComputedOperand(isConst: false, blockId: 's1', subKey: 'con'),
      );
      final r = resolveComputed(blocks, values, cfg);
      expect(r.number, 24);
      expect(r.flag, isNull);
    });
    test('cur*2 <= max → flag (true then false)', () {
      const cfg = ComputedConfig(
        a: ComputedOperand(isConst: false, blockId: 'h1', subKey: 'cur', coeff: 2),
        op: ComputedOp.le,
        b: ComputedOperand(isConst: false, blockId: 'h1', subKey: 'max'),
      );
      expect(resolveComputed(blocks, values, cfg).flag, true); // 8 <= 10
      final hi = {...values, 'h1': {'cur': 6, 'max': 10}};
      expect(resolveComputed(blocks, hi, cfg).flag, false); // 12 <= 10 false
    });
    test('counter ref + arithmetic ops', () {
      ComputedConfig c(ComputedOp op, int k) => ComputedConfig(
          a: const ComputedOperand(isConst: false, blockId: 'c1'),
          op: op,
          b: ComputedOperand(constant: k));
      expect(resolveComputed(blocks, values, c(ComputedOp.sub, 5)).number, 10);
      expect(resolveComputed(blocks, values, c(ComputedOp.mul, 2)).number, 30);
      expect(resolveComputed(blocks, values, c(ComputedOp.divFloor, 4)).number, 3);
      expect(resolveComputed(blocks, values, c(ComputedOp.divFloor, 0)).number, 0);
    });
    test('comparison ops over constants', () {
      ({int? number, bool? flag}) r(ComputedOp op) => resolveComputed(blocks, values,
          ComputedConfig(
              a: const ComputedOperand(constant: 5), op: op, b: const ComputedOperand(constant: 5)));
      expect(r(ComputedOp.eq).flag, true);
      expect(r(ComputedOp.lt).flag, false);
      expect(r(ComputedOp.ge).flag, true);
      expect(r(ComputedOp.gt).flag, false);
    });
    test('graceful: missing block, missing key, non-numeric ref → 0', () {
      const missBlock = ComputedConfig(
          a: ComputedOperand(isConst: false, blockId: 'nope'),
          op: ComputedOp.add,
          b: ComputedOperand(constant: 7));
      expect(resolveComputed(blocks, values, missBlock).number, 7); // 0 + 7
      const missKey = ComputedConfig(
          a: ComputedOperand(isConst: false, blockId: 's1', subKey: 'xyz'),
          op: ComputedOp.add,
          b: ComputedOperand(constant: 7));
      expect(resolveComputed(blocks, values, missKey).number, 7);
    });
    test('ComputedConfig JSON round-trips; fromJson tolerant', () {
      const cfg = ComputedConfig(
        a: ComputedOperand(isConst: false, blockId: 's1', subKey: 'con', coeff: 2),
        op: ComputedOp.ge,
        b: ComputedOperand(constant: 12),
      );
      final back = ComputedConfig.maybeFromJson(cfg.toJson());
      expect(back.op, ComputedOp.ge);
      expect(back.a.blockId, 's1');
      expect(back.a.coeff, 2);
      expect(back.b.constant, 12);
      // garbage → defaults
      final d = ComputedConfig.maybeFromJson('nope');
      expect(d.op, ComputedOp.add);
      expect(d.a.isConst, true);
      expect(d.a.constant, 0);
    });
  });
```

- [ ] **Step 2: Run** `export PATH="$HOME/development/flutter/bin:$PATH" && flutter test test/custom_sheet_model_test.dart -n resolveComputed` — FAIL (undefined `ComputedConfig` etc).

- [ ] **Step 3: Add to `lib/engine/custom_sheet.dart`** (near `resolveRoll` / `customStatMod`):

```dart
/// Operators for a computed block. Arithmetic ops yield a number; comparison
/// ops yield a boolean (a conditional chip).
enum ComputedOp { add, sub, mul, divFloor, le, lt, eq, ge, gt }

bool _isComparison(ComputedOp op) => switch (op) {
      ComputedOp.le || ComputedOp.lt || ComputedOp.eq || ComputedOp.ge ||
      ComputedOp.gt =>
        true,
      _ => false,
    };

/// One operand of a computed formula: a constant, or a reference to another
/// block's value (a stat key, an hp/luck 'cur'/'max' field, or a counter/timer
/// int) scaled by [coeff].
class ComputedOperand {
  const ComputedOperand({
    this.isConst = true,
    this.constant = 0,
    this.blockId = '',
    this.subKey = '',
    this.coeff = 1,
  });

  final bool isConst;
  final int constant;
  final String blockId;
  final String subKey;
  final int coeff;

  Map<String, dynamic> toJson() => {
        'k': isConst ? 'c' : 'r',
        if (isConst) 'v': constant,
        if (!isConst) 'b': blockId,
        if (!isConst) 's': subKey,
        if (!isConst) 'co': coeff,
      };

  factory ComputedOperand.fromJson(dynamic j) {
    if (j is! Map) return const ComputedOperand();
    return ComputedOperand(
      isConst: j['k'] != 'r',
      constant: (j['v'] as num?)?.toInt() ?? 0,
      blockId: j['b'] as String? ?? '',
      subKey: j['s'] as String? ?? '',
      coeff: (j['co'] as num?)?.toInt() ?? 1,
    );
  }

  ComputedOperand copyWith({
    bool? isConst,
    int? constant,
    String? blockId,
    String? subKey,
    int? coeff,
  }) =>
      ComputedOperand(
        isConst: isConst ?? this.isConst,
        constant: constant ?? this.constant,
        blockId: blockId ?? this.blockId,
        subKey: subKey ?? this.subKey,
        coeff: coeff ?? this.coeff,
      );
}

/// A computed block's formula: `a op b`. Stored directly as the block's config.
class ComputedConfig {
  const ComputedConfig({required this.a, required this.op, required this.b});

  final ComputedOperand a, b;
  final ComputedOp op;

  bool get isComparison => _isComparison(op);

  Map<String, dynamic> toJson() => {
        'a': a.toJson(),
        'op': op.name,
        'b': b.toJson(),
      };

  factory ComputedConfig.maybeFromJson(dynamic j) {
    if (j is! Map) {
      return const ComputedConfig(
          a: ComputedOperand(), op: ComputedOp.add, b: ComputedOperand());
    }
    return ComputedConfig(
      a: ComputedOperand.fromJson(j['a']),
      op: ComputedOp.values
          .firstWhere((o) => o.name == j['op'], orElse: () => ComputedOp.add),
      b: ComputedOperand.fromJson(j['b']),
    );
  }
}

int _computedLookup(List<CustomBlock> blocks, Map<String, dynamic> values,
    String blockId, String subKey) {
  CustomBlock? b;
  for (final x in blocks) {
    if (x.id == blockId) {
      b = x;
      break;
    }
  }
  if (b == null) return 0;
  final v = values[blockId];
  switch (b.type) {
    case CustomBlockType.stat:
    case CustomBlockType.hp:
    case CustomBlockType.luck:
      if (v is Map) {
        final n = v[subKey];
        return n is num ? n.toInt() : 0;
      }
      return 0;
    case CustomBlockType.counter:
    case CustomBlockType.timer:
      return v is num ? v.toInt() : 0;
    default:
      return 0; // not referenceable (incl. another computed block)
  }
}

int _operandValue(List<CustomBlock> blocks, Map<String, dynamic> values,
        ComputedOperand o) =>
    o.isConst
        ? o.constant
        : o.coeff * _computedLookup(blocks, values, o.blockId, o.subKey);

/// Pure + total. Arithmetic op → `(number: …, flag: null)`; comparison op →
/// `(number: null, flag: …)`. Missing refs → 0; divFloor by 0 → 0.
({int? number, bool? flag}) resolveComputed(List<CustomBlock> blocks,
    Map<String, dynamic> values, ComputedConfig cfg) {
  final a = _operandValue(blocks, values, cfg.a);
  final b = _operandValue(blocks, values, cfg.b);
  return switch (cfg.op) {
    ComputedOp.add => (number: a + b, flag: null),
    ComputedOp.sub => (number: a - b, flag: null),
    ComputedOp.mul => (number: a * b, flag: null),
    ComputedOp.divFloor => (number: b == 0 ? 0 : (a / b).floor(), flag: null),
    ComputedOp.le => (number: null, flag: a <= b),
    ComputedOp.lt => (number: null, flag: a < b),
    ComputedOp.eq => (number: null, flag: a == b),
    ComputedOp.ge => (number: null, flag: a >= b),
    ComputedOp.gt => (number: null, flag: a > b),
  };
}
```

- [ ] **Step 4: Run** `flutter test test/custom_sheet_model_test.dart` — PASS. `flutter analyze lib/engine/custom_sheet.dart` — clean.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/custom_sheet.dart test/custom_sheet_model_test.dart
git commit -m "feat(custom): computed block model + resolveComputed"
```

---

## Task 2: UI — `computed` block type, play renderer, config dialog

**Files:** Modify `lib/engine/custom_sheet.dart` (enum), `lib/features/custom_sheet.dart`; Test `test/custom_sheet_ui_test.dart` (one smoke test to drive compilation).

Adding `computed` to the enum breaks the exhaustive `_playBlock` + `_defaultLabel` switches, so this task adds the enum value AND all required arms + the play renderer + the config dialog together (the codebase only compiles once they're all present).

- [ ] **Step 1: Write a failing widget test** — append to `test/custom_sheet_ui_test.dart`:

```dart
  testWidgets('computed number badge renders label: n', (tester) async {
    _bigView(tester);
    const sheet = CustomSheet(blocks: [
      CustomBlock(id: 's1', type: CustomBlockType.stat, label: 'Abilities', config: {
        'stats': [
          {'key': 'con', 'label': 'CON'}
        ],
        'min': 3,
        'max': 18,
      }),
      CustomBlock(id: 'cm', type: CustomBlockType.computed, label: 'Slots', config: {
        'a': {'k': 'c', 'v': 10},
        'op': 'add',
        'b': {'k': 'r', 'b': 's1', 's': 'con', 'co': 1},
      }),
    ], values: {
      's1': {'con': 14}
    });
    await _pump(tester, sheet: sheet);
    expect(find.text('Slots: 24'), findsOneWidget);
  });

  testWidgets('computed comparison chip shows when true, hidden when false',
      (tester) async {
    _bigView(tester);
    CustomSheet sheetWith(int cur) => CustomSheet(blocks: const [
          CustomBlock(id: 'h1', type: CustomBlockType.hp, label: 'HP'),
          CustomBlock(id: 'cm', type: CustomBlockType.computed, label: 'Staggered',
              config: {
                'a': {'k': 'r', 'b': 'h1', 's': 'cur', 'co': 2},
                'op': 'le',
                'b': {'k': 'r', 'b': 'h1', 's': 'max', 'co': 1},
              }),
        ], values: {
          'h1': {'cur': cur, 'max': 10}
        });
    await _pump(tester, sheet: sheetWith(4)); // 8 <= 10 → true
    expect(find.widgetWithText(Chip, 'Staggered'), findsOneWidget);
    await _pump(tester, sheet: sheetWith(6)); // 12 <= 10 → false
    expect(find.widgetWithText(Chip, 'Staggered'), findsNothing);
  });
```

- [ ] **Step 2: Run** `flutter test test/custom_sheet_ui_test.dart -n computed` — FAIL (no `CustomBlockType.computed`; won't compile).

- [ ] **Step 3a: Add `computed` to the enum** in `lib/engine/custom_sheet.dart`:
```dart
enum CustomBlockType {
  stat,
  counter,
  hp,
  roll,
  luck,
  conditions,
  dropdown,
  freeform,
  timer,
  togglechips,
  progress,
  computed,
}
```

- [ ] **Step 3b: In `lib/features/custom_sheet.dart`, add the switch arms + renderers.**

`_playBlock` — add an arm:
```dart
      CustomBlockType.computed => _playComputed(b),
```
`_configBlock` — add a case before `default`:
```dart
    case CustomBlockType.computed:
      await _configComputed(b);
```
`_defaultLabel` — add an arm:
```dart
      CustomBlockType.computed => 'Computed',
```
`defaultConfigFor` — add an arm before the `_ =>` default:
```dart
      CustomBlockType.computed => const ComputedConfig(
          a: ComputedOperand(), op: ComputedOp.add, b: ComputedOperand()).toJson(),
```

Add the play renderer:
```dart
  Widget _playComputed(CustomBlock b) {
    final cfg = ComputedConfig.maybeFromJson(b.config);
    final r = resolveComputed(_s.blocks, _s.values, cfg);
    if (r.flag != null) {
      // comparison → conditional chip (hidden when false)
      return r.flag!
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Chip(
                    key: Key('custom-${b.id}-computed-chip'),
                    label: Text(b.label)),
              ),
            )
          : const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text('${b.label}: ${r.number ?? 0}',
          key: Key('custom-${b.id}-computed')),
    );
  }
```

Add the config method + dialog:
```dart
  Future<void> _configComputed(CustomBlock b) async {
    final result = await showDialog<ComputedConfig>(
      context: context,
      builder: (_) => _ComputedConfigDialog(block: b, blocks: _s.blocks),
    );
    if (result == null) return;
    _save(_s.copyWith(
        blocks: _s.blocks
            .map((x) => x.id == b.id
                ? x.copyWith(config: result.toJson())
                : x)
            .toList()));
  }
```

Append the dialog widget at the bottom of the file (with the other `_*ConfigDialog`s):
```dart
class _ComputedConfigDialog extends StatefulWidget {
  const _ComputedConfigDialog({required this.block, required this.blocks});
  final CustomBlock block;
  final List<CustomBlock> blocks;

  @override
  State<_ComputedConfigDialog> createState() => _ComputedConfigDialogState();
}

class _ComputedConfigDialogState extends State<_ComputedConfigDialog> {
  late ComputedConfig _cfg = ComputedConfig.maybeFromJson(widget.block.config);

  // Blocks whose value a computed operand can reference (numeric scalars).
  static const _refTypes = {
    CustomBlockType.stat,
    CustomBlockType.hp,
    CustomBlockType.luck,
    CustomBlockType.counter,
    CustomBlockType.timer,
  };

  List<CustomBlock> get _refBlocks =>
      widget.blocks.where((x) => _refTypes.contains(x.type)).toList();

  List<String> _subKeysFor(String blockId) {
    final b = widget.blocks.where((x) => x.id == blockId).firstOrNull;
    if (b == null) return const [];
    switch (b.type) {
      case CustomBlockType.stat:
        return [
          for (final s in (b.config['stats'] as List?) ?? const [])
            if (s is Map && s['key'] is String) s['key'] as String,
        ];
      case CustomBlockType.hp:
      case CustomBlockType.luck:
        return const ['cur', 'max'];
      default:
        return const []; // counter / timer: no sub-key
    }
  }

  Widget _operandEditor(String title, ComputedOperand o,
      ValueChanged<ComputedOperand> onChange) {
    final refs = _refBlocks;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      Row(children: [
        ChoiceChip(
          label: const Text('Constant'),
          selected: o.isConst,
          onSelected: (_) => onChange(o.copyWith(isConst: true)),
        ),
        const SizedBox(width: 8),
        ChoiceChip(
          label: const Text('Reference'),
          selected: !o.isConst,
          onSelected: refs.isEmpty
              ? null
              : (_) => onChange(o.copyWith(
                  isConst: false,
                  blockId: o.blockId.isEmpty ? refs.first.id : o.blockId)),
        ),
      ]),
      if (o.isConst)
        TextFormField(
          initialValue: '${o.constant}',
          decoration: const InputDecoration(labelText: 'Value'),
          keyboardType: TextInputType.number,
          onChanged: (v) => onChange(o.copyWith(constant: int.tryParse(v) ?? 0)),
        )
      else ...[
        DropdownButton<String>(
          isExpanded: true,
          value: refs.any((x) => x.id == o.blockId) ? o.blockId : null,
          hint: const Text('Block'),
          items: [
            for (final x in refs)
              DropdownMenuItem(value: x.id, child: Text(x.label)),
          ],
          onChanged: (v) {
            if (v == null) return;
            final keys = _subKeysFor(v);
            onChange(o.copyWith(
                blockId: v, subKey: keys.isEmpty ? '' : keys.first));
          },
        ),
        if (_subKeysFor(o.blockId).isNotEmpty)
          DropdownButton<String>(
            isExpanded: true,
            value: _subKeysFor(o.blockId).contains(o.subKey) ? o.subKey : null,
            hint: const Text('Field'),
            items: [
              for (final k in _subKeysFor(o.blockId))
                DropdownMenuItem(value: k, child: Text(k)),
            ],
            onChanged: (v) => onChange(o.copyWith(subKey: v ?? '')),
          ),
        TextFormField(
          initialValue: '${o.coeff}',
          decoration: const InputDecoration(labelText: 'Coefficient (×)'),
          keyboardType: TextInputType.number,
          onChanged: (v) => onChange(o.copyWith(coeff: int.tryParse(v) ?? 1)),
        ),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Edit computed value'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _operandEditor('Operand A', _cfg.a,
                (o) => setState(() => _cfg = ComputedConfig(a: o, op: _cfg.op, b: _cfg.b))),
            const SizedBox(height: 12),
            DropdownButton<ComputedOp>(
              key: const Key('custom-computed-op'),
              isExpanded: true,
              value: _cfg.op,
              items: const [
                DropdownMenuItem(value: ComputedOp.add, child: Text('+ (number)')),
                DropdownMenuItem(value: ComputedOp.sub, child: Text('− (number)')),
                DropdownMenuItem(value: ComputedOp.mul, child: Text('× (number)')),
                DropdownMenuItem(value: ComputedOp.divFloor, child: Text('÷ floor (number)')),
                DropdownMenuItem(value: ComputedOp.le, child: Text('≤ (chip)')),
                DropdownMenuItem(value: ComputedOp.lt, child: Text('< (chip)')),
                DropdownMenuItem(value: ComputedOp.eq, child: Text('= (chip)')),
                DropdownMenuItem(value: ComputedOp.ge, child: Text('≥ (chip)')),
                DropdownMenuItem(value: ComputedOp.gt, child: Text('> (chip)')),
              ],
              onChanged: (v) => setState(
                  () => _cfg = ComputedConfig(a: _cfg.a, op: v ?? _cfg.op, b: _cfg.b)),
            ),
            const SizedBox(height: 12),
            _operandEditor('Operand B', _cfg.b,
                (o) => setState(() => _cfg = ComputedConfig(a: _cfg.a, op: _cfg.op, b: o))),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              key: const Key('custom-computed-save'),
              onPressed: () => Navigator.pop(context, _cfg),
              child: const Text('Save')),
        ],
      );
}
```

Confirm `firstOrNull` is available in this file (the recon shows `_blockTypeFromName` uses `.firstOrNull`, so the `collection` extension is already imported). Confirm `sheetSection`/`fmtSigned` etc are unaffected.

- [ ] **Step 4: Run** `flutter test test/custom_sheet_ui_test.dart` — PASS (the two computed tests + all prior). `flutter analyze lib/features/custom_sheet.dart lib/engine/custom_sheet.dart` — clean.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/custom_sheet.dart lib/features/custom_sheet.dart test/custom_sheet_ui_test.dart
git commit -m "feat(custom): computed block play renderer + config dialog"
```

---

## Task 3: Config-dialog round-trip test + full verify + docs

**Files:** Test `test/custom_sheet_ui_test.dart`; Modify `CLAUDE.md`.

- [ ] **Step 1: Add a config-dialog test** — append to `test/custom_sheet_ui_test.dart`. It drives the dialog: a fresh computed block (default `0 + 0 = 0`) referencing a stat, edited to `10 + CON`. (The sheet starts in Edit mode when blocks are empty; here we seed an existing computed block + a stat block and open its config via the ⚙ affordance. Use the block's config gear key — confirm the edit-mode config-button key in the file, e.g. `custom-<id>-config`; if the key differs, use the real one.)

```dart
  testWidgets('computed config dialog builds 10 + CON', (tester) async {
    _bigView(tester);
    const sheet = CustomSheet(blocks: [
      CustomBlock(id: 's1', type: CustomBlockType.stat, label: 'Abilities', config: {
        'stats': [
          {'key': 'con', 'label': 'CON'}
        ],
        'min': 3,
        'max': 18,
      }),
      CustomBlock(id: 'cm', type: CustomBlockType.computed, label: 'Slots'),
    ], values: {
      's1': {'con': 12}
    });
    final c = await _pump(tester, sheet: sheet);
    // enter edit mode + open the computed block's config (adapt the keys to the
    // real edit-mode toggle + per-block config-button keys in custom_sheet.dart).
    // Then: set op=add, operand A const 10, operand B ref s1/con, Save.
    // Assert the persisted config resolves to 22 on the next render.
    // If driving the dialog via keys is brittle, assert resolveComputed on the
    // saved config instead (model-level) — but prefer the UI path.
    expect(c, isNotNull);
  });
```
NOTE: if exercising the full dialog through the edit-mode UI proves brittle (edit-mode toggle + scattered dropdowns), it is acceptable to replace this with a direct `_ComputedConfigDialog` pump (pump the dialog widget alone in a `MaterialApp`, tap the op dropdown + operand chips, tap `custom-computed-save`, and assert the returned `ComputedConfig`). Keep at least one test that exercises the dialog producing a correct `ComputedConfig`.

- [ ] **Step 2: Run** `flutter test test/custom_sheet_ui_test.dart` — PASS.

- [ ] **Step 3: Full verification** — `export PATH="$HOME/development/flutter/bin:$PATH" && flutter analyze` (whole project; if `prefer_const`/`unnecessary_const` lints appear in the new test code, `dart fix --apply test/custom_sheet_model_test.dart test/custom_sheet_ui_test.dart` then re-analyze) and `flutter test` (whole suite). Expect all pass; report the count.

- [ ] **Step 4: Update `CLAUDE.md`** — in the Custom/Homebrew sheet bullet, note the new block type:
```markdown
  A **computed** block (`CustomBlockType.computed`, P2) adds read-only derived
  values: a two-operand single-binary-op formula (`ComputedConfig` in
  `custom_sheet.dart`: each operand a constant or a block-reference with a
  coefficient; arithmetic op → number badge, comparison op → conditional chip)
  resolved by the pure total `resolveComputed`. Cycle-free — a computed block
  can't reference another computed block. Covers e.g. Knave `10+CON`, Argosa
  `currentHp*2 ≤ maxHp`. See
  `docs/superpowers/specs/2026-06-27-custom-computed-badges-design.md`.
```

- [ ] **Step 5: Commit**

```bash
git add test/custom_sheet_ui_test.dart CLAUDE.md
git commit -m "test(custom): computed config-dialog test; docs"
```

---

## Self-review notes

- **Spec coverage:** model + resolver (T1), block type + play badge/chip + config dialog (T2), config round-trip + verify + docs (T3). All spec sections covered.
- **Naming:** `ComputedOp`/`ComputedOperand`/`ComputedConfig`/`resolveComputed`; `CustomBlockType.computed`; play keys `custom-<id>-computed` (number) / `custom-<id>-computed-chip` (chip); dialog keys `custom-computed-op` / `custom-computed-save`. Config JSON keys: operand `k`(c/r)/`v`/`b`/`s`/`co`; config `a`/`op`/`b`.
- **Compile-order:** Task 1 adds the resolver taking a `ComputedConfig` (not a block), so it does NOT touch the enum — the exhaustive `_playBlock`/`_defaultLabel` switches stay valid. Task 2 adds the enum value together with all switch arms + renderers in one commit, so the project only ever compiles in a complete state.
- **Tolerance:** `ComputedConfig.maybeFromJson` + `ComputedOperand.fromJson` never throw; `resolveComputed` is total (missing refs → 0, div0 → 0); referencing a non-numeric or computed block → 0.
- **Add-block picker:** `_addBlock` iterates `CustomBlockType.values`, so `computed` auto-appears (shown as `t.name` = "computed", consistent with the existing raw-name picker); `_defaultLabel`/`defaultConfigFor` arms give it a sane label + default formula.
