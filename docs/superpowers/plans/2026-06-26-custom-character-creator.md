# Custom / Homebrew Character Sheet — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a user-defined "Custom / Homebrew" character sheet that exposes the superset of configurable mechanics across the existing pre-made sheets, so a player can build a sheet for an unsupported game without code.

**Architecture:** A custom sheet is a typed `Character.custom` field holding `CustomSheet { List<CustomBlock> blocks; Map<String,dynamic> values }` — `blocks` is the user-authored schema (ordered), `values` is live play state keyed by `block.id`. One `CustomSheetView` renders two ways: **Play** (each block's widget) and **Edit** (reorder / configure / delete + add-block). Creation offers starter templates that pre-seed `blocks`. All pure logic (model, modifier formulas, roll resolution) lives in `lib/engine/custom_sheet.dart` and is unit-tested without Flutter.

**Tech Stack:** Flutter, flutter_riverpod, shared_preferences. No new dependencies. Reuses `lib/features/sheet_widgets.dart` bricks.

**Spec:** `docs/superpowers/specs/2026-06-26-custom-character-creator-design.md`

---

## File Structure

**Create:**
- `lib/engine/custom_sheet.dart` — pure model + logic: `CustomBlockType`, `StatModFormula`, `customStatMod`, `CustomBlock`, `CustomSheet`, and the roll model (`RollConfig`, `RollDirection`, `RollTargetKind`, `RollCrit`, `RollBand`, `RollOutcome`, `resolveRoll`).
- `lib/engine/custom_templates.dart` — pure `kCustomTemplates` (`CustomTemplate { id, label, blocks }`).
- `lib/features/custom_sheet.dart` — `CustomSheetView` (play/edit scaffolding + per-block play renderers + per-block config dialogs).
- `test/custom_sheet_model_test.dart` — model + customStatMod + resolveRoll + templates.
- `test/custom_sheet_ui_test.dart` — widget tests pumping `CustomSheetView`.

**Modify:**
- `lib/engine/models.dart` — `Character` (field, ctor, copyWith, toJson, fromJson, `forSheet`), `kKnownSystems`, `kSystemCategory`.
- `lib/state/providers.dart` — `CharacterNotifier.addCustom`.
- `lib/features/tracker_screen.dart` — sheet render dispatch, roster `new-custom` option + handler + `_newCustom`.
- `lib/shared/home_shell.dart` — `kSystemBlurbs['custom']`, `kSystemShortName['custom']`.
- `lib/engine/campaign_presets.dart` — `solo-custom` preset.
- `lib/engine/campaign_surfaces.dart` — `Sheet` surface row.
- `lib/features/sheet_widgets.dart` — new `luckTokensSection` + `rollTrackRow` bricks.

**Phases:** P1a Foundation (Tasks 1–6) → P1b Full block set (Tasks 7–11) → P1c Templates + registration (Tasks 12–14).

---

# Phase P1a — Foundation

## Task 1: Engine model — blocks, sheet, stat-modifier formulas

**Files:**
- Create: `lib/engine/custom_sheet.dart`
- Test: `test/custom_sheet_model_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/custom_sheet_model_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/custom_sheet.dart';

void main() {
  group('customStatMod', () {
    test('fived: 5e curve', () {
      expect(customStatMod(StatModFormula.fived, 10), 0);
      expect(customStatMod(StatModFormula.fived, 18), 4);
      expect(customStatMod(StatModFormula.fived, 3), -4);
    });
    test('dccTight: capped +/-3 table', () {
      expect(customStatMod(StatModFormula.dccTight, 3), -3);
      expect(customStatMod(StatModFormula.dccTight, 8), -1);
      expect(customStatMod(StatModFormula.dccTight, 9), 0);
      expect(customStatMod(StatModFormula.dccTight, 12), 0);
      expect(customStatMod(StatModFormula.dccTight, 13), 1);
      expect(customStatMod(StatModFormula.dccTight, 18), 3);
    });
    test('scoreIsMod: identity', () {
      expect(customStatMod(StatModFormula.scoreIsMod, 4), 4);
      expect(customStatMod(StatModFormula.scoreIsMod, -2), -2);
    });
    test('halfFloor', () {
      expect(customStatMod(StatModFormula.halfFloor, 7), 3);
      expect(customStatMod(StatModFormula.halfFloor, 4), 2);
    });
  });

  group('CustomSheet JSON', () {
    test('round-trips blocks + values', () {
      const sheet = CustomSheet(blocks: [
        CustomBlock(
            id: 'b1',
            type: CustomBlockType.counter,
            label: 'AC',
            config: {'min': 0, 'max': 30}),
        CustomBlock(id: 'b2', type: CustomBlockType.freeform, label: 'Notes'),
      ], values: {
        'b1': 15,
        'b2': 'hello',
      });
      final back = CustomSheet.maybeFromJson(sheet.toJson())!;
      expect(back.blocks.length, 2);
      expect(back.blocks[0].id, 'b1');
      expect(back.blocks[0].type, CustomBlockType.counter);
      expect(back.blocks[0].label, 'AC');
      expect(back.blocks[0].config['max'], 30);
      expect(back.values['b1'], 15);
      expect(back.values['b2'], 'hello');
    });
    test('drops a block with an unknown type', () {
      final back = CustomSheet.maybeFromJson({
        'blocks': [
          {'id': 'x', 'type': 'counter', 'label': 'A'},
          {'id': 'y', 'type': 'bogus', 'label': 'B'},
        ],
      })!;
      expect(back.blocks.map((b) => b.id), ['x']);
    });
    test('maybeFromJson tolerates non-map / null', () {
      expect(CustomSheet.maybeFromJson(null), isNull);
      expect(CustomSheet.maybeFromJson(42), isNull);
      final empty = CustomSheet.maybeFromJson({})!;
      expect(empty.blocks, isEmpty);
      expect(empty.values, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/custom_sheet_model_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'juice_oracle' ... custom_sheet.dart` / undefined `CustomSheet`.

- [ ] **Step 3: Write minimal implementation**

Create `lib/engine/custom_sheet.dart`:

```dart
/// Pure model + logic for the user-defined "Custom / Homebrew" sheet.
/// No Flutter imports — unit-tested without a widget harness.
library;

// ---------------------------------------------------------------------------
// Stat-modifier formulas (the only "math" a stat block needs).
// ---------------------------------------------------------------------------

/// How a stat block derives a modifier from a score.
/// [raw] shows no modifier; the renderer hides the modifier line for it.
enum StatModFormula { raw, fived, dccTight, scoreIsMod, halfFloor }

/// The derived modifier for [score] under [formula]. For [StatModFormula.raw]
/// this is 0 and unused (the renderer shows the score only).
int customStatMod(StatModFormula formula, int score) => switch (formula) {
      StatModFormula.raw => 0,
      StatModFormula.fived => ((score - 10) / 2).floor(),
      StatModFormula.dccTight => _dccTight(score),
      StatModFormula.scoreIsMod => score,
      StatModFormula.halfFloor => (score / 2).floor(),
    };

/// DCC's tightened ability table, capped at +/-3 (also adopted by the DCC
/// sheet when built). Defined over the 3..18 stepper range.
int _dccTight(int s) {
  if (s <= 3) return -3;
  if (s <= 5) return -2;
  if (s <= 8) return -1;
  if (s <= 12) return 0;
  if (s <= 15) return 1;
  if (s <= 17) return 2;
  return 3;
}

StatModFormula statModFormulaFromName(String? n) => StatModFormula.values
    .firstWhere((f) => f.name == n, orElse: () => StatModFormula.raw);

// ---------------------------------------------------------------------------
// Blocks + sheet.
// ---------------------------------------------------------------------------

/// The kinds of block a custom sheet can contain.
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
}

CustomBlockType? _blockTypeFromName(String? n) =>
    CustomBlockType.values.where((e) => e.name == n).firstOrNull;

/// One configurable block in a custom sheet's schema.
class CustomBlock {
  const CustomBlock({
    required this.id,
    required this.type,
    required this.label,
    this.config = const {},
  });

  /// Stable id, generated once at creation; keys into [CustomSheet.values].
  final String id;
  final CustomBlockType type;
  final String label;

  /// Per-type configuration (e.g. stat keys, dropdown options, roll config).
  final Map<String, dynamic> config;

  CustomBlock copyWith({String? label, Map<String, dynamic>? config}) =>
      CustomBlock(
        id: id,
        type: type,
        label: label ?? this.label,
        config: config ?? this.config,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'label': label,
        if (config.isNotEmpty) 'config': config,
      };

  static CustomBlock? maybeFromJson(dynamic j) {
    if (j is! Map) return null;
    final type = _blockTypeFromName(j['type'] as String?);
    if (type == null) return null; // forward-compat: drop unknown types
    return CustomBlock(
      id: (j['id'] as String?) ?? '',
      type: type,
      label: (j['label'] as String?) ?? '',
      config: (j['config'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }
}

/// A user-authored sheet: an ordered list of [blocks] (the schema) plus a
/// [values] map of live play state keyed by block id.
class CustomSheet {
  const CustomSheet({this.blocks = const [], this.values = const {}});

  final List<CustomBlock> blocks;
  final Map<String, dynamic> values;

  CustomSheet copyWith({
    List<CustomBlock>? blocks,
    Map<String, dynamic>? values,
  }) =>
      CustomSheet(
        blocks: blocks ?? this.blocks,
        values: values ?? this.values,
      );

  Map<String, dynamic> toJson() => {
        'blocks': blocks.map((b) => b.toJson()).toList(),
        if (values.isNotEmpty) 'values': values,
      };

  static CustomSheet? maybeFromJson(dynamic j) {
    if (j is! Map) return null;
    return CustomSheet(
      blocks: ((j['blocks'] as List?) ?? const [])
          .map(CustomBlock.maybeFromJson)
          .whereType<CustomBlock>()
          .toList(),
      values: (j['values'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/custom_sheet_model_test.dart`
Expected: PASS (all groups).

- [ ] **Step 5: Commit**

```bash
git add lib/engine/custom_sheet.dart test/custom_sheet_model_test.dart
git commit -m "feat(custom): custom-sheet model + stat-modifier formulas"
```

---

## Task 2: Character integration + system registration constants

**Files:**
- Modify: `lib/engine/models.dart` (Character ctor/fields/copyWith/toJson/fromJson/forSheet; `kKnownSystems`; `kSystemCategory`)
- Test: `test/custom_sheet_model_test.dart` (append)

- [ ] **Step 1: Write the failing test** — append to `test/custom_sheet_model_test.dart`:

```dart
// add this import at the top of the file:
// import 'package:juice_oracle/engine/models.dart';

  group('Character.custom integration', () {
    test('round-trips through Character JSON', () {
      const sheet = CustomSheet(blocks: [
        CustomBlock(id: 'b1', type: CustomBlockType.freeform, label: 'Notes'),
      ], values: {
        'b1': 'hi'
      });
      final c = Character(id: 'c1', name: 'Homebrew', custom: sheet);
      final back = Character.fromJson(c.toJson());
      expect(back.custom, isNotNull);
      expect(back.custom!.blocks.single.label, 'Notes');
      expect(back.custom!.values['b1'], 'hi');
    });
    test('forSheet seeds a blank custom sheet', () {
      final c = Character.forSheet('custom', 'c9');
      expect(c.custom, isNotNull);
      expect(c.custom!.blocks, isEmpty);
    });
    test('copyWith clearCustom drops the sheet', () {
      final c = Character(
          id: 'c1', name: 'X', custom: const CustomSheet(blocks: []));
      expect(c.copyWith(clearCustom: true).custom, isNull);
    });
    test('custom is a known, categorized ruleset system', () {
      expect(kKnownSystems.contains('custom'), isTrue);
      expect(kSystemCategory['custom'], SystemCategory.ruleset);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/custom_sheet_model_test.dart`
Expected: FAIL — `The named parameter 'custom' isn't defined` (Character ctor) / `clearCustom` undefined.

- [ ] **Step 3: Write minimal implementation** — in `lib/engine/models.dart`:

Add the import at the top (with the other engine imports if models.dart imports siblings; if models.dart has no imports of engine files, add):
```dart
import 'custom_sheet.dart';
```

In the `Character` constructor parameter list, after `this.kalArath,`:
```dart
    this.custom,
```

In the field declarations, after the `kalArath` field:
```dart
  /// User-defined custom/homebrew sheet; null unless this is a custom PC.
  final CustomSheet? custom;
```

In `forSheet`'s switch, before the `_ =>` default case:
```dart
      'custom' => Character(
          id: id, name: 'New custom character', custom: const CustomSheet()),
```

In `copyWith`, after the `KalArathSheet? kalArath, bool clearKalArath = false,` params:
```dart
    CustomSheet? custom,
    bool clearCustom = false,
```
and in the returned `Character(...)`, after the `kalArath:` line:
```dart
        custom: clearCustom ? null : (custom ?? this.custom),
```

In `toJson()`, after the `if (kalArath != null) ...` line:
```dart
        if (custom != null) 'custom': custom!.toJson(),
```

In `fromJson`, after the `kalArath:` line:
```dart
        custom: CustomSheet.maybeFromJson(j['custom']),
```

In `kKnownSystems`, add `'custom',` (after `'cards',` is fine).

In `kSystemCategory`, add:
```dart
  'custom': SystemCategory.ruleset,
```

> Note: `withHpDelta` is intentionally NOT extended for custom sheets — a custom sheet's HP lives in its `values` map keyed by an arbitrary block id, so the party-wide HP broadcast skips it (it returns the character unchanged, like Ironsworn/Starforged). Documented as out-of-scope in the spec.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/custom_sheet_model_test.dart`
Expected: PASS.

- [ ] **Step 5: Run the model/registration suites to confirm no completeness regressions**

Run: `flutter test test/campaign_presets_test.dart test/models_test.dart`
Expected: PASS (the `kSystemCategory.keys == kKnownSystems` assertion now holds because both got `custom`).

- [ ] **Step 6: Commit**

```bash
git add lib/engine/models.dart test/custom_sheet_model_test.dart
git commit -m "feat(custom): wire Character.custom + register custom system"
```

---

## Task 3: `addCustom` notifier

**Files:**
- Modify: `lib/state/providers.dart` (`CharacterNotifier`)
- Test: `test/custom_sheet_ui_test.dart` (create)

- [ ] **Step 1: Write the failing test** — create `test/custom_sheet_ui_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/custom_sheet.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('addCustom seeds a character with the given blocks', () async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.characters.v1.default': '[]',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(charactersProvider.future);

    const blocks = [
      CustomBlock(id: 'b1', type: CustomBlockType.counter, label: 'AC'),
    ];
    final id =
        await container.read(charactersProvider.notifier).addCustom(blocks);

    final chars = await container.read(charactersProvider.future);
    final c = chars.firstWhere((e) => e.id == id);
    expect(c.custom, isNotNull);
    expect(c.custom!.blocks.single.label, 'AC');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/custom_sheet_ui_test.dart`
Expected: FAIL — `The method 'addCustom' isn't defined`.

- [ ] **Step 3: Write minimal implementation** — in `lib/state/providers.dart`, in `CharacterNotifier`, next to the other `addXxx` methods (after `addKalArath`), add:

```dart
  /// Creates a custom/homebrew PC seeded with [blocks] at the top and returns
  /// its id. Unlike the fixed sheets, the schema is supplied by the caller
  /// (a chosen template, or empty for Blank).
  Future<String> addCustom(List<CustomBlock> blocks) async {
    final id = _newId();
    final c = Character(
        id: id, name: 'New custom character', custom: CustomSheet(blocks: blocks));
    await _persist([c, ...await _ready]);
    return id;
  }
```

Add the import at the top of `providers.dart` if not already importing the engine model:
```dart
import '../engine/custom_sheet.dart';
```

> `Character` and `_newId`/`_persist`/`_ready` are already in scope (used by the existing `addPreMadeSheet`). Mirror its exact persistence call.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/custom_sheet_ui_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/state/providers.dart test/custom_sheet_ui_test.dart
git commit -m "feat(custom): CharacterNotifier.addCustom"
```

---

## Task 4: `CustomSheetView` scaffold — play/edit toggle, add/reorder/delete

**Files:**
- Create: `lib/features/custom_sheet.dart`
- Modify: `lib/features/tracker_screen.dart` (render dispatch)
- Test: `test/custom_sheet_ui_test.dart` (append)

This task builds the editor shell with a single placeholder block renderer (`freeform`) so add/reorder/delete/toggle are testable. Real per-block renderers land in Task 5+.

- [ ] **Step 1: Write the failing test** — append to `test/custom_sheet_ui_test.dart`. Add these imports at the top:

```dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/features/custom_sheet.dart';
import 'package:juice_oracle/shared/theme.dart';
```

Add this pump helper + tests:

```dart
Future<ProviderContainer> _pump(WidgetTester tester,
    {CustomSheet sheet = const CustomSheet()}) async {
  SharedPreferences.setMockInitialValues({
    'juice.sessions.v1':
        '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    'juice.characters.v1.default': jsonEncode([
      {
        'id': 'c1',
        'name': 'Homebrew',
        'stats': [],
        'tracks': [],
        'tags': [],
        'custom': sheet.toJson(),
      }
    ]),
  });
  final container = ProviderContainer();
  addTearDown(container.dispose);
  final char = (await container.read(charactersProvider.future)).single;
  await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: Consumer(builder: (_, ref, __) {
            final live =
                ref.watch(charactersProvider).valueOrNull?.firstOrNull ?? char;
            return CustomSheetView(character: live, onBack: () {});
          })))));
  await tester.pumpAndSettle();
  return container;
}

void _bigView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 5000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

  testWidgets('empty sheet starts in edit mode with add-block', (tester) async {
    _bigView(tester);
    await _pump(tester);
    expect(find.byKey(const Key('custom-add-block')), findsOneWidget);
  });

  testWidgets('delete removes a block and persists', (tester) async {
    _bigView(tester);
    const sheet = CustomSheet(blocks: [
      CustomBlock(id: 'b1', type: CustomBlockType.freeform, label: 'Notes'),
    ]);
    final c = await _pump(tester, sheet: sheet);
    // ensure edit mode
    if (find.byKey(const Key('custom-block-b1-delete')).evaluate().isEmpty) {
      await tester.tap(find.byKey(const Key('custom-mode-toggle')));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const Key('custom-block-b1-delete')));
    await tester.pumpAndSettle();
    final chars = await c.read(charactersProvider.future);
    expect(chars.single.custom!.blocks, isEmpty);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/custom_sheet_ui_test.dart`
Expected: FAIL — `CustomSheetView` undefined.

- [ ] **Step 3: Write minimal implementation** — create `lib/features/custom_sheet.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/custom_sheet.dart';
import '../engine/models.dart';
import '../state/providers.dart';
import 'sheet_widgets.dart';

/// The user-defined custom/homebrew sheet. Renders for characters whose
/// [Character.custom] is non-null. Two modes: Play (use the sheet) and Edit
/// (author the schema). Edits persist via charactersProvider.
class CustomSheetView extends ConsumerStatefulWidget {
  const CustomSheetView(
      {super.key, required this.character, required this.onBack});
  final Character character;
  final VoidCallback onBack;

  @override
  ConsumerState<CustomSheetView> createState() => _CustomSheetViewState();
}

class _CustomSheetViewState extends ConsumerState<CustomSheetView> {
  late bool _editing = (widget.character.custom?.blocks.isEmpty ?? true);

  CustomSheet get _s => widget.character.custom ?? const CustomSheet();

  void _save(CustomSheet next) => ref
      .read(charactersProvider.notifier)
      .replace(widget.character.copyWith(custom: next));

  /// Reads a block's live value, or [fallback] when unset.
  dynamic _val(String id, dynamic fallback) => _s.values[id] ?? fallback;

  void _setVal(String id, dynamic value) =>
      _save(_s.copyWith(values: {..._s.values, id: value}));

  String _newBlockId() =>
      'blk-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = _s;
    return ListView(
      key: const Key('custom-sheet'),
      padding: const EdgeInsets.all(12),
      children: [
        Row(children: [
          IconButton(
            key: const Key('sheet-back'),
            icon: const Icon(Icons.arrow_back),
            onPressed: widget.onBack,
          ),
          Expanded(
            child: Text(widget.character.name,
                style: theme.textTheme.titleLarge,
                overflow: TextOverflow.ellipsis),
          ),
          IconButton(
            key: const Key('custom-mode-toggle'),
            icon: Icon(_editing ? Icons.visibility : Icons.edit_outlined),
            tooltip: _editing ? 'Play' : 'Edit layout',
            onPressed: () => setState(() => _editing = !_editing),
          ),
        ]),
        Text('Custom / Homebrew', style: theme.textTheme.labelSmall),
        const SizedBox(height: 8),
        if (_editing)
          _editList(s)
        else
          for (final b in s.blocks) _playBlock(b),
        if (_editing)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: OutlinedButton.icon(
              key: const Key('custom-add-block'),
              icon: const Icon(Icons.add),
              label: const Text('Add block'),
              onPressed: _addBlock,
            ),
          ),
      ],
    );
  }

  Widget _editList(CustomSheet s) => ReorderableListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        onReorder: (oldI, newI) {
          final list = [...s.blocks];
          if (newI > oldI) newI -= 1;
          final moved = list.removeAt(oldI);
          list.insert(newI, moved);
          _save(s.copyWith(blocks: list));
        },
        children: [
          for (final b in s.blocks)
            Card(
              key: ValueKey(b.id),
              child: ListTile(
                title: Text(b.label.isEmpty ? b.type.name : b.label),
                subtitle: Text(b.type.name),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    key: Key('custom-block-${b.id}-config'),
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: () => _configBlock(b),
                  ),
                  IconButton(
                    key: Key('custom-block-${b.id}-delete'),
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _save(s.copyWith(
                        blocks: s.blocks.where((x) => x.id != b.id).toList())),
                  ),
                ]),
              ),
            ),
        ],
      );

  Future<void> _addBlock() async {
    final type = await showDialog<CustomBlockType>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Add block'),
        children: [
          for (final t in CustomBlockType.values)
            SimpleDialogOption(
              key: Key('custom-add-type-${t.name}'),
              child: Text(t.name),
              onPressed: () => Navigator.pop(context, t),
            ),
        ],
      ),
    );
    if (type == null) return;
    final block = CustomBlock(
        id: _newBlockId(), type: type, label: _defaultLabel(type),
        config: defaultConfigFor(type));
    _save(_s.copyWith(blocks: [..._s.blocks, block]));
    if (mounted) _configBlock(block);
  }

  String _defaultLabel(CustomBlockType t) => switch (t) {
        CustomBlockType.stat => 'Abilities',
        CustomBlockType.counter => 'Counter',
        CustomBlockType.hp => 'HP',
        CustomBlockType.roll => 'Checks',
        CustomBlockType.luck => 'Luck',
        CustomBlockType.conditions => 'Conditions',
        CustomBlockType.dropdown => 'Class',
        CustomBlockType.freeform => 'Notes',
        CustomBlockType.timer => 'Timer',
        CustomBlockType.togglechips => 'Flags',
        CustomBlockType.progress => 'Tracks',
      };

  // --- play + config dispatch (filled in by later tasks) ---------------------

  Widget _playBlock(CustomBlock b) => switch (b.type) {
        CustomBlockType.freeform => _playFreeform(b),
        _ => const SizedBox.shrink(),
      };

  Future<void> _configBlock(CustomBlock b) async {
    switch (b.type) {
      default:
        await _renameBlock(b);
    }
  }

  Future<void> _renameBlock(CustomBlock b) async {
    final name = await renameDialog(context,
        nameKey: 'custom-block-${b.id}-label', current: b.label);
    if (name == null) return;
    _save(_s.copyWith(
        blocks:
            _s.blocks.map((x) => x.id == b.id ? x.copyWith(label: name) : x).toList()));
  }

  // --- freeform (placeholder real block) -------------------------------------

  Widget _playFreeform(CustomBlock b) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: TextFormField(
          key: Key('custom-${b.id}-freeform'),
          initialValue: _val(b.id, '') as String,
          maxLines: (b.config['multiline'] == true) ? 4 : 1,
          decoration: InputDecoration(labelText: b.label),
          onChanged: (v) => _setVal(b.id, v),
        ),
      );
}

/// Default config for a freshly added block of [type].
Map<String, dynamic> defaultConfigFor(CustomBlockType type) => switch (type) {
      CustomBlockType.stat => {
          'stats': [
            {'key': 'str', 'label': 'STR'},
          ],
          'min': 3,
          'max': 18,
          'modFormula': StatModFormula.raw.name,
        },
      CustomBlockType.counter => {'min': 0, 'max': 999, 'step': 1},
      CustomBlockType.hp => {'allowTemp': false},
      CustomBlockType.dropdown => {'options': <String>[]},
      CustomBlockType.freeform => {'multiline': true},
      CustomBlockType.timer => {'start': 0},
      CustomBlockType.togglechips => {'options': <String>[]},
      _ => const {},
    };
```

Now wire the render dispatch. In `lib/features/tracker_screen.dart`, add the import:
```dart
import 'custom_sheet.dart';
```
and in the sheet-render conditional chain (the block that returns `StarforgedSheetView` / `ShadowdarkSheetView` / etc.), add — placing it first so a custom sheet always wins:
```dart
              if (c.custom != null) {
                return CustomSheetView(
                  character: c,
                  onBack: () {
                    ref
                        .read(playContextProvider.notifier)
                        .setActiveCharacter(null);
                    setState(() => _editingId = null);
                  },
                );
              }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/custom_sheet_ui_test.dart`
Expected: PASS.

- [ ] **Step 5: Confirm the app still compiles**

Run: `flutter analyze lib/features/tracker_screen.dart lib/features/custom_sheet.dart`
Expected: No errors (warnings about unused `defaultConfigFor` branches are fine; later tasks use them).

- [ ] **Step 6: Commit**

```bash
git add lib/features/custom_sheet.dart lib/features/tracker_screen.dart test/custom_sheet_ui_test.dart
git commit -m "feat(custom): CustomSheetView scaffold + render dispatch"
```

---

## Task 5: Core block renderers — stat, counter, conditions (freeform already done)

**Files:**
- Modify: `lib/features/custom_sheet.dart`
- Test: `test/custom_sheet_ui_test.dart` (append)

- [ ] **Step 1: Write the failing test** — append:

```dart
  testWidgets('counter block steps and persists', (tester) async {
    _bigView(tester);
    const sheet = CustomSheet(blocks: [
      CustomBlock(
          id: 'b1',
          type: CustomBlockType.counter,
          label: 'AC',
          config: {'min': 0, 'max': 30, 'step': 1}),
    ], values: {
      'b1': 12
    });
    final c = await _pump(tester, sheet: sheet);
    // play mode (non-empty sheet starts in play)
    await tester.tap(find.byKey(const Key('custom-b1-counter-plus')));
    await tester.pumpAndSettle();
    final chars = await c.read(charactersProvider.future);
    expect(chars.single.custom!.values['b1'], 13);
  });

  testWidgets('stat block shows derived modifier and steps', (tester) async {
    _bigView(tester);
    const sheet = CustomSheet(blocks: [
      CustomBlock(id: 'b1', type: CustomBlockType.stat, label: 'Abilities', config: {
        'stats': [
          {'key': 'str', 'label': 'STR'}
        ],
        'min': 3,
        'max': 18,
        'modFormula': 'fived',
      }),
    ], values: {
      'b1': {'str': 14}
    });
    final c = await _pump(tester, sheet: sheet);
    expect(find.text('+2'), findsOneWidget); // fived(14) = +2
    await tester.tap(find.byKey(const Key('custom-b1-stat-str-plus')));
    await tester.pumpAndSettle();
    final chars = await c.read(charactersProvider.future);
    expect((chars.single.custom!.values['b1'] as Map)['str'], 15);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/custom_sheet_ui_test.dart -n "counter block"`
Expected: FAIL — no `custom-b1-counter-plus` widget (counter renders `SizedBox.shrink`).

- [ ] **Step 3: Write minimal implementation** — in `lib/features/custom_sheet.dart`:

Extend `_playBlock`'s switch:
```dart
  Widget _playBlock(CustomBlock b) => switch (b.type) {
        CustomBlockType.freeform => _playFreeform(b),
        CustomBlockType.counter => _playCounter(b),
        CustomBlockType.stat => _playStat(b),
        CustomBlockType.conditions => _playConditions(b),
        _ => const SizedBox.shrink(),
      };
```

Add the renderers:
```dart
  int _intCfg(CustomBlock b, String key, int fallback) =>
      (b.config[key] as num?)?.toInt() ?? fallback;

  Widget _playCounter(CustomBlock b) {
    final min = _intCfg(b, 'min', 0);
    final max = _intCfg(b, 'max', 999);
    final step = _intCfg(b, 'step', 1);
    final v = (_val(b.id, min) as num).toInt();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(child: Text(b.label)),
        IconButton(
          key: Key('custom-${b.id}-counter-minus'),
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: v > min ? () => _setVal(b.id, v - step) : null,
        ),
        Text('$v'),
        IconButton(
          key: Key('custom-${b.id}-counter-plus'),
          icon: const Icon(Icons.add_circle_outline),
          onPressed: v < max ? () => _setVal(b.id, v + step) : null,
        ),
      ]),
    );
  }

  Widget _playStat(CustomBlock b) {
    final min = _intCfg(b, 'min', 3);
    final max = _intCfg(b, 'max', 18);
    final formula = statModFormulaFromName(b.config['modFormula'] as String?);
    final stats = ((b.config['stats'] as List?) ?? const [])
        .whereType<Map>()
        .toList();
    final cur = (_val(b.id, const {}) as Map).cast<String, dynamic>();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      sheetSection(context, b.label),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final st in stats)
          () {
            final key = st['key'] as String;
            final label = (st['label'] as String?) ?? key.toUpperCase();
            final score = (cur[key] as num?)?.toInt() ?? ((min + max) ~/ 2);
            final modText = formula == StatModFormula.raw
                ? ''
                : fmtSigned(customStatMod(formula, score));
            return SizedBox(
              width: 96,
              child: Column(children: [
                Text(label, style: const TextStyle(fontSize: 11)),
                if (modText.isNotEmpty)
                  Text(modText,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold)),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  IconButton(
                    key: Key('custom-${b.id}-stat-$key-minus'),
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.remove, size: 16),
                    onPressed: score > min
                        ? () => _setVal(
                            b.id, {...cur, key: score - 1})
                        : null,
                  ),
                  Text('$score'),
                  IconButton(
                    key: Key('custom-${b.id}-stat-$key-plus'),
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.add, size: 16),
                    onPressed: score < max
                        ? () => _setVal(
                            b.id, {...cur, key: score + 1})
                        : null,
                  ),
                ]),
              ]),
            );
          }(),
      ]),
    ]);
  }

  Widget _playConditions(CustomBlock b) =>
      conditionsSection(context, ref, widget.character, 'custom-${b.id}');
```

> The `conditions` block reuses the shared `conditionsSection`, which edits `Character.conditions` directly — it does not use the block's `values` entry (matches the spec). `sheetSection`, `fmtSigned`, and `conditionsSection` come from `sheet_widgets.dart` (already imported).

Also extend `_configBlock` so stat/counter blocks get a real config dialog (Step 1's tests don't require it, but the config buttons exist):
```dart
  Future<void> _configBlock(CustomBlock b) async {
    switch (b.type) {
      case CustomBlockType.counter:
        await _configCounter(b);
      case CustomBlockType.stat:
        await _configStat(b);
      default:
        await _renameBlock(b);
    }
  }
```
Add minimal config dialogs (label + the numeric/formula knobs). Use a `StatefulBuilder` `AlertDialog` with `TextFormField`s for min/max/step (counter) and a label field + `DropdownButton<StatModFormula>` + an editable stat-key list (stat). Persist via `_save(_s.copyWith(blocks: _s.blocks.map((x) => x.id == b.id ? x.copyWith(label: .., config: ..) : x).toList()))`. (Full dialog code follows the same `_RenameDialog`/`StatefulBuilder` pattern in `sheet_widgets.dart`; keep each dialog self-contained and dispose controllers in a `finally`.)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/custom_sheet_ui_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/custom_sheet.dart test/custom_sheet_ui_test.dart
git commit -m "feat(custom): stat/counter/conditions block renderers + config"
```

---

## Task 6: Roster wiring + blurb/short-name (Blank creation path)

**Files:**
- Modify: `lib/features/tracker_screen.dart` (roster option + handler + `_newCustom`)
- Modify: `lib/shared/home_shell.dart` (`kSystemBlurbs`, `kSystemShortName`)
- Test: `test/custom_sheet_model_test.dart` (append — blurb assertion); `test/custom_sheet_ui_test.dart` (append — handler smoke if practical)

- [ ] **Step 1: Write the failing test** — append to `test/custom_sheet_model_test.dart`:

```dart
// requires: import 'package:juice_oracle/shared/home_shell.dart';
  test('kSystemBlurbs covers custom (new_campaign_dialog completeness)', () {
    expect(kSystemBlurbs['custom'], isNotNull);
    expect(kSystemBlurbs['custom']!.toLowerCase(), contains('custom'));
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/custom_sheet_model_test.dart -n "kSystemBlurbs covers custom"`
Expected: FAIL — `kSystemBlurbs['custom']` is null.

- [ ] **Step 3: Write minimal implementation**

In `lib/shared/home_shell.dart`, in `kSystemBlurbs`, add:
```dart
  'custom':
      'Custom / Homebrew sheet: build your own from configurable blocks — '
          'stats, HP, rolls, luck, timers, conditions. Facts-only; you author all content.',
```
In `kSystemShortName`, add:
```dart
  'custom': 'Custom',
```

In `lib/features/tracker_screen.dart`, add the roster option (in the gated options list, alongside `new-kal-arath`):
```dart
      if (systems.contains('custom'))
        (
          key: 'new-custom',
          value: 'custom',
          label: 'Custom / Homebrew',
          blurb: 'Build your own sheet from blocks.'
        ),
```
Add the choice-handler branch (alongside the other `else if (choice == ...)`):
```dart
    } else if (choice == 'custom') {
      await _newCustom();
```
Add the `_newCustom` method (mirror `_newDnd`; Blank-only for now — Task 13 adds the template picker):
```dart
  Future<void> _newCustom() async {
    final id =
        await ref.read(charactersProvider.notifier).addCustom(const []);
    if (mounted) setState(() => _editingId = id);
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/custom_sheet_model_test.dart`
Expected: PASS.

- [ ] **Step 5: Run the dialog completeness suite**

Run: `flutter test test/new_campaign_dialog_test.dart`
Expected: PASS (blurb completeness over `kKnownSystems` now includes `custom`).

- [ ] **Step 6: Commit**

```bash
git add lib/features/tracker_screen.dart lib/shared/home_shell.dart test/custom_sheet_model_test.dart
git commit -m "feat(custom): roster create + blurb/short-name (blank path)"
```

---

# Phase P1b — Full block set

## Task 7: Roll model — `RollConfig` + `resolveRoll`

**Files:**
- Modify: `lib/engine/custom_sheet.dart`
- Test: `test/custom_sheet_model_test.dart` (append)

- [ ] **Step 1: Write the failing test** — append:

```dart
  group('resolveRoll', () {
    // dice are passed explicitly so the tests are deterministic.
    test('Cairn-style roll-under own value: pass/fail', () {
      const cfg = RollConfig(
          direction: RollDirection.low,
          addBonus: false,
          targetKind: RollTargetKind.rowValue);
      expect(resolveRoll(cfg, 14, [10]).label, 'Pass');
      expect(resolveRoll(cfg, 14, [18]).label, 'Fail');
    });
    test('Argosa-style low with great-on-half ladder', () {
      const cfg = RollConfig(
        direction: RollDirection.low,
        addBonus: false,
        targetKind: RollTargetKind.rowValue,
        bands: [
          RollBand(threshold: 0.5, label: 'Great Success'),
          RollBand(threshold: 1.0, label: 'Success'),
        ],
      );
      expect(resolveRoll(cfg, 16, [4]).label, 'Great Success'); // 4 <= 8
      expect(resolveRoll(cfg, 16, [12]).label, 'Success'); // 12 <= 16
      expect(resolveRoll(cfg, 16, [18]).label, 'Fail');
    });
    test('D&D/DCC high + bonus vs prompted DC', () {
      const cfg = RollConfig(
          direction: RollDirection.high,
          addBonus: true,
          targetKind: RollTargetKind.prompt);
      expect(resolveRoll(cfg, 3, [11], promptTarget: 11).total, 14);
      expect(resolveRoll(cfg, 3, [11], promptTarget: 11).label, 'Pass');
      expect(resolveRoll(cfg, 3, [5], promptTarget: 11).label, 'Fail');
    });
    test('Knave high + bonus vs fixed target', () {
      const cfg = RollConfig(
          direction: RollDirection.high,
          addBonus: true,
          targetKind: RollTargetKind.fixed,
          fixedTarget: 11);
      expect(resolveRoll(cfg, 4, [7]).label, 'Pass'); // 7+4=11 >= 11
      expect(resolveRoll(cfg, 4, [6]).label, 'Fail');
    });
    test('PbtA 2d6 ladder', () {
      const cfg = RollConfig(
        diceCount: 2,
        diceSides: 6,
        direction: RollDirection.high,
        addBonus: true,
        bands: [
          RollBand(threshold: 10, label: 'Strong hit'),
          RollBand(threshold: 7, label: 'Weak hit'),
          RollBand(threshold: 0, label: 'Miss'),
        ],
      );
      expect(resolveRoll(cfg, 2, [5, 4]).label, 'Strong hit'); // 11
      expect(resolveRoll(cfg, 1, [4, 3]).label, 'Weak hit'); // 8
      expect(resolveRoll(cfg, 0, [1, 2]).label, 'Miss'); // 3
    });
    test('Kal-Arath crit on matching dice', () {
      const cfg = RollConfig(
          diceCount: 2,
          diceSides: 6,
          direction: RollDirection.high,
          addBonus: true,
          targetKind: RollTargetKind.fixed,
          fixedTarget: 8,
          crit: RollCrit.matchingDice);
      expect(resolveRoll(cfg, 0, [6, 6]).label, 'Critical Success');
      expect(resolveRoll(cfg, 0, [1, 1]).label, 'Critical Failure');
      expect(resolveRoll(cfg, 2, [4, 2]).label, 'Pass'); // 6+2=8 >= 8
    });
    test('Draw Steel 2d10 tiers', () {
      const cfg = RollConfig(
        diceCount: 2,
        diceSides: 10,
        direction: RollDirection.high,
        addBonus: true,
        bands: [
          RollBand(threshold: 17, label: 'Tier 3'),
          RollBand(threshold: 12, label: 'Tier 2'),
          RollBand(threshold: 0, label: 'Tier 1'),
        ],
      );
      expect(resolveRoll(cfg, 2, [9, 8]).label, 'Tier 3'); // 19
      expect(resolveRoll(cfg, 1, [7, 5]).label, 'Tier 2'); // 13
      expect(resolveRoll(cfg, 0, [2, 3]).label, 'Tier 1'); // 5
    });
    test('RollConfig JSON round-trips', () {
      const cfg = RollConfig(
          diceCount: 2,
          diceSides: 6,
          bands: [RollBand(threshold: 10, label: 'Hit')],
          crit: RollCrit.matchingDice);
      final back = RollConfig.fromJson(cfg.toJson());
      expect(back.diceSides, 6);
      expect(back.bands.single.label, 'Hit');
      expect(back.crit, RollCrit.matchingDice);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/custom_sheet_model_test.dart -n "resolveRoll"`
Expected: FAIL — `RollConfig` / `resolveRoll` undefined.

- [ ] **Step 3: Write minimal implementation** — append to `lib/engine/custom_sheet.dart`:

```dart
// ---------------------------------------------------------------------------
// Roll model. A roll block holds rows (label + own bonus value) and one
// shared RollConfig. resolveRoll is pure: the widget rolls dice and passes
// them in, so outcomes are deterministic in tests.
// ---------------------------------------------------------------------------

enum RollDirection { high, low }

enum RollTargetKind { fixed, prompt, rowValue }

enum RollCrit { none, matchingDice, natural }

/// One degree-of-success band. For [RollDirection.high] [threshold] is a
/// minimum total (integer-valued). For [RollDirection.low] it is a fraction of
/// the target (e.g. 0.5 = "great on half", 1.0 = "success at target").
class RollBand {
  const RollBand({required this.threshold, required this.label});
  final double threshold;
  final String label;
  Map<String, dynamic> toJson() => {'t': threshold, 'l': label};
  static RollBand? fromJson(dynamic j) {
    if (j is! Map) return null;
    return RollBand(
        threshold: (j['t'] as num?)?.toDouble() ?? 0,
        label: (j['l'] as String?) ?? '');
  }
}

class RollConfig {
  const RollConfig({
    this.diceCount = 1,
    this.diceSides = 20,
    this.addBonus = true,
    this.direction = RollDirection.high,
    this.targetKind = RollTargetKind.prompt,
    this.fixedTarget = 10,
    this.bands = const [],
    this.crit = RollCrit.none,
  });

  final int diceCount, diceSides, fixedTarget;
  final bool addBonus;
  final RollDirection direction;
  final RollTargetKind targetKind;
  final List<RollBand> bands;
  final RollCrit crit;

  Map<String, dynamic> toJson() => {
        'dc': diceCount,
        'ds': diceSides,
        'ab': addBonus,
        'dir': direction.name,
        'tk': targetKind.name,
        'ft': fixedTarget,
        if (bands.isNotEmpty) 'bands': bands.map((b) => b.toJson()).toList(),
        'crit': crit.name,
      };

  factory RollConfig.fromJson(dynamic j) {
    if (j is! Map) return const RollConfig();
    return RollConfig(
      diceCount: (j['dc'] as num?)?.toInt() ?? 1,
      diceSides: (j['ds'] as num?)?.toInt() ?? 20,
      addBonus: j['ab'] != false,
      direction: RollDirection.values
          .firstWhere((d) => d.name == j['dir'], orElse: () => RollDirection.high),
      targetKind: RollTargetKind.values.firstWhere((t) => t.name == j['tk'],
          orElse: () => RollTargetKind.prompt),
      fixedTarget: (j['ft'] as num?)?.toInt() ?? 10,
      bands: ((j['bands'] as List?) ?? const [])
          .map(RollBand.fromJson)
          .whereType<RollBand>()
          .toList(),
      crit: RollCrit.values
          .firstWhere((c) => c.name == j['crit'], orElse: () => RollCrit.none),
    );
  }
}

class RollOutcome {
  const RollOutcome(this.total, this.label);
  final int total;
  final String label;
}

/// Resolves a roll. [rowValue] is the row's own bonus/target number, [dice]
/// the already-rolled face values, [promptTarget] the entered DC when
/// [RollTargetKind.prompt].
RollOutcome resolveRoll(RollConfig cfg, int rowValue, List<int> dice,
    {int? promptTarget}) {
  final sum = dice.fold<int>(0, (a, b) => a + b);

  // Natural / matching-dice crits override everything.
  if (cfg.crit == RollCrit.matchingDice &&
      dice.length > 1 &&
      dice.toSet().length == 1) {
    if (dice.first == cfg.diceSides) {
      return RollOutcome(sum + (cfg.addBonus ? rowValue : 0), 'Critical Success');
    }
    if (dice.first == 1) {
      return RollOutcome(sum + (cfg.addBonus ? rowValue : 0), 'Critical Failure');
    }
  }
  if (cfg.crit == RollCrit.natural && dice.length == 1) {
    if (dice.first == cfg.diceSides) {
      return RollOutcome(sum + (cfg.addBonus ? rowValue : 0), 'Critical Success');
    }
    if (dice.first == 1) {
      return RollOutcome(sum + (cfg.addBonus ? rowValue : 0), 'Critical Failure');
    }
  }

  int target() => switch (cfg.targetKind) {
        RollTargetKind.fixed => cfg.fixedTarget,
        RollTargetKind.prompt => promptTarget ?? cfg.fixedTarget,
        RollTargetKind.rowValue => rowValue,
      };

  if (cfg.direction == RollDirection.low) {
    final raw = sum; // roll-under compares the raw dice
    final tgt = target();
    if (cfg.bands.isNotEmpty) {
      final sorted = [...cfg.bands]
        ..sort((a, b) => a.threshold.compareTo(b.threshold)); // low -> high
      for (final band in sorted) {
        if (raw <= (band.threshold * tgt).floor()) {
          return RollOutcome(raw, band.label);
        }
      }
      return RollOutcome(raw, 'Fail');
    }
    return RollOutcome(raw, raw <= tgt ? 'Pass' : 'Fail');
  }

  final total = sum + (cfg.addBonus ? rowValue : 0);
  if (cfg.bands.isNotEmpty) {
    final sorted = [...cfg.bands]
      ..sort((a, b) => b.threshold.compareTo(a.threshold)); // high -> low
    for (final band in sorted) {
      if (total >= band.threshold) return RollOutcome(total, band.label);
    }
    return RollOutcome(total, sorted.last.label);
  }
  final tgt = target();
  return RollOutcome(total, total >= tgt ? 'Pass' : 'Fail');
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/custom_sheet_model_test.dart`
Expected: PASS (every coverage-table row).

- [ ] **Step 5: Commit**

```bash
git add lib/engine/custom_sheet.dart test/custom_sheet_model_test.dart
git commit -m "feat(custom): roll model + resolveRoll with degrees/crit"
```

---

## Task 8: Roll block renderer + `rollTrackRow` brick

**Files:**
- Modify: `lib/features/sheet_widgets.dart` (add `rollTrackRow`)
- Modify: `lib/features/custom_sheet.dart` (roll play + config)
- Test: `test/custom_sheet_ui_test.dart` (append)

- [ ] **Step 1: Write the failing test** — append:

```dart
  testWidgets('roll block shows a snackbar with the row label', (tester) async {
    _bigView(tester);
    const sheet = CustomSheet(blocks: [
      CustomBlock(id: 'b1', type: CustomBlockType.roll, label: 'Saves', config: {
        'rows': ['Fort', 'Ref'],
        'roll': {
          'dc': 1,
          'ds': 20,
          'ab': true,
          'dir': 'high',
          'tk': 'fixed',
          'ft': 1, // always passes (d20 + bonus >= 1)
          'crit': 'none',
        },
      }),
    ], values: {
      'b1': [3, 1]
    });
    await _pump(tester, sheet: sheet);
    await tester.tap(find.byKey(const Key('custom-b1-roll-0')));
    await tester.pump(); // show snackbar
    expect(find.textContaining('Fort:'), findsOneWidget);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/custom_sheet_ui_test.dart -n "roll block"`
Expected: FAIL — no `custom-b1-roll-0` widget.

- [ ] **Step 3: Write minimal implementation**

In `lib/features/sheet_widgets.dart`, add a reusable roll row (a label + own bonus stepper + roll button):
```dart
/// A roll-track row: a label, a +/- bonus stepper, and a roll button. [prefix]
/// + [index] key the controls (e.g. 'custom-b1' -> 'custom-b1-roll-0'). The
/// caller owns rolling + the snackbar via [onRoll].
Widget rollTrackRow({
  required String prefix,
  required int index,
  required String label,
  required int bonus,
  required ValueChanged<int> onBonus,
  required VoidCallback onRoll,
}) =>
    Row(children: [
      Expanded(child: Text(label)),
      IconButton(
        key: Key('$prefix-roll-$index-bonus-minus'),
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.remove, size: 16),
        onPressed: () => onBonus(bonus - 1),
      ),
      Text(bonus >= 0 ? '+$bonus' : '$bonus'),
      IconButton(
        key: Key('$prefix-roll-$index-bonus-plus'),
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.add, size: 16),
        onPressed: () => onBonus(bonus + 1),
      ),
      IconButton(
        key: Key('$prefix-roll-$index'),
        icon: const Icon(Icons.casino_outlined, size: 18),
        tooltip: 'Roll',
        onPressed: onRoll,
      ),
    ]);
```

In `lib/features/custom_sheet.dart`, add `import 'dart:math';` at the top, extend `_playBlock` with `CustomBlockType.roll => _playRoll(b),`, and add:
```dart
  Widget _playRoll(CustomBlock b) {
    final rows =
        ((b.config['rows'] as List?) ?? const []).whereType<String>().toList();
    final cfg = RollConfig.fromJson(b.config['roll']);
    final raw = (_val(b.id, const []) as List);
    final bonuses = [
      for (var i = 0; i < rows.length; i++)
        (i < raw.length ? (raw[i] as num).toInt() : 0)
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      sheetSection(context, b.label),
      for (var i = 0; i < rows.length; i++)
        rollTrackRow(
          prefix: 'custom-${b.id}',
          index: i,
          label: rows[i],
          bonus: bonuses[i],
          onBonus: (v) {
            final next = [...bonuses]..[i] = v;
            _setVal(b.id, next);
          },
          onRoll: () => _doRoll(b, cfg, rows[i], bonuses[i]),
        ),
    ]);
  }

  Future<void> _doRoll(
      CustomBlock b, RollConfig cfg, String label, int bonus) async {
    int? promptTarget;
    if (cfg.targetKind == RollTargetKind.prompt) {
      promptTarget = await _promptInt(context, 'Target / DC');
      if (promptTarget == null) return;
    }
    final rng = Random();
    final dice = [for (var i = 0; i < cfg.diceCount; i++) rng.nextInt(cfg.diceSides) + 1];
    final out = resolveRoll(cfg, bonus, dice, promptTarget: promptTarget);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$label: ${out.total} — ${out.label}'),
      duration: const Duration(seconds: 3),
    ));
  }

  Future<int?> _promptInt(BuildContext context, String label) async {
    final ctrl = TextEditingController();
    try {
      return await showDialog<int>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(label),
          content: TextField(
            key: const Key('custom-roll-target'),
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: label),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () =>
                    Navigator.pop(context, int.tryParse(ctrl.text) ?? 0),
                child: const Text('Roll')),
          ],
        ),
      );
    } finally {
      ctrl.dispose();
    }
  }
```

Extend `_configBlock` with `case CustomBlockType.roll: await _configRoll(b);` — a dialog editing the row labels (one `TextFormField` each + add/remove) and the `RollConfig` knobs (dice count/sides, direction, addBonus switch, target kind + fixed value, crit dropdown, and an editable bands list). Persist as `config: {'rows': [...], 'roll': cfg.toJson()}`. Keep it self-contained; dispose controllers in `finally`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/custom_sheet_ui_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/sheet_widgets.dart lib/features/custom_sheet.dart test/custom_sheet_ui_test.dart
git commit -m "feat(custom): roll block + rollTrackRow brick"
```

---

## Task 9: Luck block + `luckTokensSection` brick

**Files:**
- Modify: `lib/features/sheet_widgets.dart` (add `luckTokensSection`)
- Modify: `lib/features/custom_sheet.dart` (luck play + config)
- Test: `test/custom_sheet_ui_test.dart` (append)

- [ ] **Step 1: Write the failing test** — append:

```dart
  testWidgets('luck block spends and resets', (tester) async {
    _bigView(tester);
    const sheet = CustomSheet(blocks: [
      CustomBlock(id: 'b1', type: CustomBlockType.luck, label: 'Luck'),
    ], values: {
      'b1': {'cur': 3, 'max': 5}
    });
    final c = await _pump(tester, sheet: sheet);
    await tester.tap(find.byKey(const Key('custom-b1-luck-spend')));
    await tester.pumpAndSettle();
    expect((((await c.read(charactersProvider.future)).single.custom!
        .values['b1']) as Map)['cur'], 2);
    await tester.tap(find.byKey(const Key('custom-b1-luck-reset')));
    await tester.pumpAndSettle();
    expect((((await c.read(charactersProvider.future)).single.custom!
        .values['b1']) as Map)['cur'], 5);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/custom_sheet_ui_test.dart -n "luck block"`
Expected: FAIL — no `custom-b1-luck-spend` widget.

- [ ] **Step 3: Write minimal implementation**

In `lib/features/sheet_widgets.dart`, add (the brick the DCC spec promised):
```dart
/// Spendable luck/fate token pool: a label, current/max readout, a spend (−1)
/// button, and a reset-to-max button. [prefix] keys the buttons (e.g.
/// 'custom-b1' -> 'custom-b1-luck-spend'). Adopted by the custom luck block;
/// the DCC sheet will adopt it too.
Widget luckTokensSection({
  required String prefix,
  required String label,
  required int current,
  required int max,
  required VoidCallback onDecrement,
  required VoidCallback onReset,
}) =>
    Row(children: [
      Expanded(child: Text(label)),
      IconButton(
        key: Key('$prefix-luck-spend'),
        icon: const Icon(Icons.remove_circle_outline),
        tooltip: 'Spend',
        onPressed: current > 0 ? onDecrement : null,
      ),
      Text('$current / $max'),
      const SizedBox(width: 8),
      TextButton(
        key: Key('$prefix-luck-reset'),
        onPressed: onReset,
        child: const Text('Reset'),
      ),
    ]);
```

In `lib/features/custom_sheet.dart`, extend `_playBlock` with `CustomBlockType.luck => _playLuck(b),` and add:
```dart
  Widget _playLuck(CustomBlock b) {
    final v = (_val(b.id, const {}) as Map).cast<String, dynamic>();
    final cur = (v['cur'] as num?)?.toInt() ?? 0;
    final max = (v['max'] as num?)?.toInt() ?? 0;
    return luckTokensSection(
      prefix: 'custom-${b.id}',
      label: b.label,
      current: cur,
      max: max,
      onDecrement: () => _setVal(b.id, {'cur': cur - 1, 'max': max}),
      onReset: () => _setVal(b.id, {'cur': max, 'max': max}),
    );
  }
```

Extend `_configBlock` with `case CustomBlockType.luck: await _configLuck(b);` — a dialog with the label + a "max tokens" stepper that writes `{'cur': max, 'max': max}` into the value. (Follow the same `StatefulBuilder` dialog pattern.)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/custom_sheet_ui_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/sheet_widgets.dart lib/features/custom_sheet.dart test/custom_sheet_ui_test.dart
git commit -m "feat(custom): luck block + shared luckTokensSection brick"
```

---

## Task 10: HP + dropdown blocks

**Files:**
- Modify: `lib/features/custom_sheet.dart`
- Test: `test/custom_sheet_ui_test.dart` (append)

- [ ] **Step 1: Write the failing test** — append:

```dart
  testWidgets('hp block steps current and persists', (tester) async {
    _bigView(tester);
    const sheet = CustomSheet(blocks: [
      CustomBlock(id: 'b1', type: CustomBlockType.hp, label: 'HP'),
    ], values: {
      'b1': {'cur': 8, 'max': 10}
    });
    final c = await _pump(tester, sheet: sheet);
    await tester.tap(find.byKey(const Key('custom-b1-hp-cur-minus')));
    await tester.pumpAndSettle();
    expect((((await c.read(charactersProvider.future)).single.custom!
        .values['b1']) as Map)['cur'], 7);
  });

  testWidgets('dropdown block selects and persists', (tester) async {
    _bigView(tester);
    const sheet = CustomSheet(blocks: [
      CustomBlock(id: 'b1', type: CustomBlockType.dropdown, label: 'Class', config: {
        'options': ['Fighter', 'Mage']
      }),
    ], values: {
      'b1': 'Fighter'
    });
    final c = await _pump(tester, sheet: sheet);
    await tester.tap(find.byKey(const Key('custom-b1-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mage').last);
    await tester.pumpAndSettle();
    expect((await c.read(charactersProvider.future)).single.custom!.values['b1'],
        'Mage');
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/custom_sheet_ui_test.dart -n "hp block"`
Expected: FAIL — no `custom-b1-hp-cur-minus` widget.

- [ ] **Step 3: Write minimal implementation** — in `lib/features/custom_sheet.dart`, extend `_playBlock` with `CustomBlockType.hp => _playHp(b),` and `CustomBlockType.dropdown => _playDropdown(b),`, and add:

```dart
  Widget _playHp(CustomBlock b) {
    final v = (_val(b.id, const {}) as Map).cast<String, dynamic>();
    final cur = (v['cur'] as num?)?.toInt() ?? 0;
    final max = (v['max'] as num?)?.toInt() ?? 0;
    final temp = (v['temp'] as num?)?.toInt() ?? 0;
    final allowTemp = b.config['allowTemp'] == true;
    void set(Map<String, dynamic> next) => _setVal(b.id, {...v, ...next});
    return Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
      SizedBox(width: 64, child: Text(b.label)),
      IconButton(
          key: Key('custom-${b.id}-hp-cur-minus'),
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: () => set({'cur': cur - 1})),
      Text('$cur / $max'),
      IconButton(
          key: Key('custom-${b.id}-hp-cur-plus'),
          icon: const Icon(Icons.add_circle_outline),
          onPressed: () => set({'cur': cur + 1})),
      const SizedBox(width: 8),
      const Text('Max'),
      IconButton(
          key: Key('custom-${b.id}-hp-max-minus'),
          icon: const Icon(Icons.remove, size: 16),
          onPressed: () => set({'max': max - 1})),
      IconButton(
          key: Key('custom-${b.id}-hp-max-plus'),
          icon: const Icon(Icons.add, size: 16),
          onPressed: () => set({'max': max + 1})),
      if (allowTemp) ...[
        const SizedBox(width: 8),
        const Text('Temp'),
        IconButton(
            key: Key('custom-${b.id}-hp-temp-minus'),
            icon: const Icon(Icons.remove, size: 16),
            onPressed: () => set({'temp': temp - 1})),
        Text('$temp'),
        IconButton(
            key: Key('custom-${b.id}-hp-temp-plus'),
            icon: const Icon(Icons.add, size: 16),
            onPressed: () => set({'temp': temp + 1})),
      ],
    ]);
  }

  Widget _playDropdown(CustomBlock b) {
    final options =
        ((b.config['options'] as List?) ?? const []).whereType<String>().toList();
    final value = _val(b.id, options.isEmpty ? '' : options.first) as String;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        SizedBox(width: 96, child: Text(b.label)),
        Expanded(
          child: DropdownButton<String>(
            key: Key('custom-${b.id}-dropdown'),
            isExpanded: true,
            value: options.contains(value) ? value : (options.isEmpty ? null : options.first),
            items: [
              for (final o in options) DropdownMenuItem(value: o, child: Text(o)),
            ],
            onChanged: (v) => v == null ? null : _setVal(b.id, v),
          ),
        ),
      ]),
    );
  }
```

Extend `_configBlock`: `case CustomBlockType.hp:` (label + allowTemp switch) and `case CustomBlockType.dropdown:` (label + editable options list — one `TextFormField` per option + add/remove). Persist via `config:`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/custom_sheet_ui_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/custom_sheet.dart test/custom_sheet_ui_test.dart
git commit -m "feat(custom): hp + dropdown blocks"
```

---

## Task 11: Timer + toggle-chips + progress blocks

**Files:**
- Modify: `lib/features/custom_sheet.dart`
- Test: `test/custom_sheet_ui_test.dart` (append)

- [ ] **Step 1: Write the failing test** — append:

```dart
  testWidgets('timer block ticks down and shows lit/out', (tester) async {
    _bigView(tester);
    const sheet = CustomSheet(blocks: [
      CustomBlock(id: 'b1', type: CustomBlockType.timer, label: 'Torch'),
    ], values: {
      'b1': 1
    });
    final c = await _pump(tester, sheet: sheet);
    expect(find.text('lit'), findsOneWidget);
    await tester.tap(find.byKey(const Key('custom-b1-timer-dec')));
    await tester.pumpAndSettle();
    expect((await c.read(charactersProvider.future)).single.custom!.values['b1'],
        0);
    expect(find.text('out'), findsOneWidget);
  });

  testWidgets('toggle-chips select and persist', (tester) async {
    _bigView(tester);
    const sheet = CustomSheet(blocks: [
      CustomBlock(id: 'b1', type: CustomBlockType.togglechips, label: 'Flags', config: {
        'options': ['Wounded', 'Shaken']
      }),
    ]);
    final c = await _pump(tester, sheet: sheet);
    await tester.tap(find.text('Wounded'));
    await tester.pumpAndSettle();
    expect(
        ((await c.read(charactersProvider.future)).single.custom!.values['b1']
            as List),
        contains('Wounded'));
  });

  testWidgets('progress block adds a track', (tester) async {
    _bigView(tester);
    const sheet = CustomSheet(blocks: [
      CustomBlock(id: 'b1', type: CustomBlockType.progress, label: 'Tracks'),
    ]);
    final c = await _pump(tester, sheet: sheet);
    await tester.tap(find.byKey(const Key('custom-b1-progress-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('custom-b1-track-name')), 'Vow');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(
        ((await c.read(charactersProvider.future)).single.custom!.values['b1']
            as List),
        isNotEmpty);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/custom_sheet_ui_test.dart -n "timer block"`
Expected: FAIL — no `custom-b1-timer-dec` widget.

- [ ] **Step 3: Write minimal implementation** — in `lib/features/custom_sheet.dart`, extend `_playBlock` with the three cases and add:

```dart
  Widget _playTimer(CustomBlock b) {
    final v = (_val(b.id, _intCfg(b, 'start', 0)) as num).toInt();
    return Row(children: [
      Expanded(child: Text(b.label)),
      IconButton(
          key: Key('custom-${b.id}-timer-dec'),
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: v > 0 ? () => _setVal(b.id, v - 1) : null),
      Text('$v'),
      IconButton(
          key: Key('custom-${b.id}-timer-inc'),
          icon: const Icon(Icons.add_circle_outline),
          onPressed: () => _setVal(b.id, v + 1)),
      const SizedBox(width: 8),
      Text(v > 0 ? 'lit' : 'out',
          style: TextStyle(
              color: v > 0
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.error)),
    ]);
  }

  Widget _playToggleChips(CustomBlock b) {
    final options =
        ((b.config['options'] as List?) ?? const []).whereType<String>().toList();
    final selected =
        ((_val(b.id, const []) as List).whereType<String>().toSet());
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      sheetSection(context, b.label),
      Wrap(spacing: 6, runSpacing: 4, children: [
        for (final o in options)
          FilterChip(
            key: Key('custom-${b.id}-chip-$o'),
            label: Text(o),
            selected: selected.contains(o),
            onSelected: (on) {
              final next = {...selected};
              on ? next.add(o) : next.remove(o);
              _setVal(b.id, next.toList());
            },
          ),
      ]),
    ]);
  }

  Widget _playProgress(CustomBlock b) {
    final tracks = ((_val(b.id, const []) as List))
        .map(ProgressTrack.maybeFromJson)
        .whereType<ProgressTrack>()
        .toList();
    void persist(List<ProgressTrack> next) =>
        _setVal(b.id, next.map((t) => t.toJson()).toList());
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: sheetSection(context, b.label)),
        IconButton(
          key: Key('custom-${b.id}-progress-add'),
          icon: const Icon(Icons.add_circle_outline),
          onPressed: () async {
            final t = await addProgressTrackDialog(context,
                nameKey: 'custom-${b.id}-track-name', label: 'Track');
            if (t != null) persist([...tracks, t]);
          },
        ),
      ]),
      for (var i = 0; i < tracks.length; i++)
        progressTrackRow(
          context: context,
          prefix: 'custom-${b.id}-trk',
          index: i,
          track: tracks[i],
          onChanged: (t) {
            final next = [...tracks]..[i] = t;
            persist(next);
          },
          onDelete: () {
            final next = [...tracks]..removeAt(i);
            persist(next);
          },
        ),
    ]);
  }
```

Add the three switch arms to `_playBlock`:
```dart
        CustomBlockType.timer => _playTimer(b),
        CustomBlockType.togglechips => _playToggleChips(b),
        CustomBlockType.progress => _playProgress(b),
```
`ProgressTrack`, `addProgressTrackDialog`, and `progressTrackRow` are already available via the `models.dart` + `sheet_widgets.dart` imports.

Extend `_configBlock`: `case CustomBlockType.timer:` (label + start stepper), `case CustomBlockType.togglechips:` (label + options list). `progress` needs only rename (`default`).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/custom_sheet_ui_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/custom_sheet.dart test/custom_sheet_ui_test.dart
git commit -m "feat(custom): timer + toggle-chips + progress blocks"
```

---

# Phase P1c — Templates + registration

## Task 12: `kCustomTemplates`

**Files:**
- Create: `lib/engine/custom_templates.dart`
- Test: `test/custom_sheet_model_test.dart` (append)

- [ ] **Step 1: Write the failing test** — append (add `import 'package:juice_oracle/engine/custom_templates.dart';`):

```dart
  group('kCustomTemplates', () {
    test('has the four authored starters incl. Blank', () {
      final ids = kCustomTemplates.map((t) => t.id).toList();
      expect(ids, containsAll(['blank', 'generic-d20', 'osr', 'pbta']));
    });
    test('blank has no blocks; others have blocks with unique ids', () {
      for (final t in kCustomTemplates) {
        if (t.id == 'blank') {
          expect(t.blocks, isEmpty);
          continue;
        }
        expect(t.blocks, isNotEmpty, reason: t.id);
        final ids = t.blocks.map((b) => b.id).toList();
        expect(ids.toSet().length, ids.length, reason: '${t.id} dup ids');
      }
    });
    test('every block type/formula referenced is valid (round-trips)', () {
      for (final t in kCustomTemplates) {
        final back = CustomSheet.maybeFromJson(
            CustomSheet(blocks: t.blocks).toJson())!;
        expect(back.blocks.length, t.blocks.length, reason: t.id);
      }
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/custom_sheet_model_test.dart -n "kCustomTemplates"`
Expected: FAIL — `kCustomTemplates` undefined.

- [ ] **Step 3: Write minimal implementation** — create `lib/engine/custom_templates.dart`:

```dart
import 'custom_sheet.dart';

/// A named starter schema (a pre-seeded block list). Generic mechanics only —
/// no game names, prose, or setting (facts-only).
class CustomTemplate {
  const CustomTemplate(
      {required this.id, required this.label, required this.blocks});
  final String id;
  final String label;
  final List<CustomBlock> blocks;
}

const kCustomTemplates = <CustomTemplate>[
  CustomTemplate(id: 'blank', label: 'Blank', blocks: []),
  CustomTemplate(id: 'generic-d20', label: 'Generic d20', blocks: [
    CustomBlock(id: 'g-stat', type: CustomBlockType.stat, label: 'Abilities', config: {
      'stats': [
        {'key': 'str', 'label': 'STR'},
        {'key': 'dex', 'label': 'DEX'},
        {'key': 'con', 'label': 'CON'},
        {'key': 'int', 'label': 'INT'},
        {'key': 'wis', 'label': 'WIS'},
        {'key': 'cha', 'label': 'CHA'},
      ],
      'min': 3,
      'max': 18,
      'modFormula': 'fived',
    }),
    CustomBlock(id: 'g-hp', type: CustomBlockType.hp, label: 'HP', config: {'allowTemp': false}),
    CustomBlock(id: 'g-ac', type: CustomBlockType.counter, label: 'AC', config: {'min': 0, 'max': 30, 'step': 1}),
    CustomBlock(id: 'g-saves', type: CustomBlockType.roll, label: 'Saves', config: {
      'rows': ['Fortitude', 'Reflex', 'Will'],
      'roll': {'dc': 1, 'ds': 20, 'ab': true, 'dir': 'high', 'tk': 'prompt', 'crit': 'none'},
    }),
    CustomBlock(id: 'g-cond', type: CustomBlockType.conditions, label: 'Conditions'),
    CustomBlock(id: 'g-notes', type: CustomBlockType.freeform, label: 'Notes', config: {'multiline': true}),
  ]),
  CustomTemplate(id: 'osr', label: 'OSR roll-under', blocks: [
    CustomBlock(id: 'o-stat', type: CustomBlockType.stat, label: 'Abilities', config: {
      'stats': [
        {'key': 'str', 'label': 'STR'},
        {'key': 'dex', 'label': 'DEX'},
        {'key': 'wil', 'label': 'WIL'},
      ],
      'min': 3,
      'max': 18,
      'modFormula': 'raw',
    }),
    CustomBlock(id: 'o-saves', type: CustomBlockType.roll, label: 'Saves', config: {
      'rows': ['STR', 'DEX', 'WIL'],
      'roll': {'dc': 1, 'ds': 20, 'ab': false, 'dir': 'low', 'tk': 'rowValue', 'crit': 'none'},
    }),
    CustomBlock(id: 'o-hp', type: CustomBlockType.hp, label: 'HP', config: {'allowTemp': false}),
    CustomBlock(id: 'o-cond', type: CustomBlockType.conditions, label: 'Conditions'),
    CustomBlock(id: 'o-notes', type: CustomBlockType.freeform, label: 'Notes', config: {'multiline': true}),
  ]),
  CustomTemplate(id: 'pbta', label: '2d6 PbtA', blocks: [
    CustomBlock(id: 'p-stat', type: CustomBlockType.stat, label: 'Stats', config: {
      'stats': [
        {'key': 'cool', 'label': 'COOL'},
        {'key': 'hard', 'label': 'HARD'},
        {'key': 'hot', 'label': 'HOT'},
        {'key': 'sharp', 'label': 'SHARP'},
        {'key': 'weird', 'label': 'WEIRD'},
      ],
      'min': -1,
      'max': 3,
      'modFormula': 'scoreIsMod',
    }),
    CustomBlock(id: 'p-moves', type: CustomBlockType.roll, label: 'Moves', config: {
      'rows': ['Act under fire', 'Go aggro'],
      'roll': {
        'dc': 2,
        'ds': 6,
        'ab': true,
        'dir': 'high',
        'tk': 'fixed',
        'ft': 0,
        'bands': [
          {'t': 10, 'l': 'Strong hit'},
          {'t': 7, 'l': 'Weak hit'},
          {'t': 0, 'l': 'Miss'},
        ],
        'crit': 'none',
      },
    }),
    CustomBlock(id: 'p-cond', type: CustomBlockType.conditions, label: 'Conditions'),
    CustomBlock(id: 'p-notes', type: CustomBlockType.freeform, label: 'Notes', config: {'multiline': true}),
  ]),
];
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/custom_sheet_model_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/custom_templates.dart test/custom_sheet_model_test.dart
git commit -m "feat(custom): starter templates (blank/d20/osr/pbta)"
```

---

## Task 13: Template picker on create + preset + surface row

**Files:**
- Modify: `lib/features/tracker_screen.dart` (`_newCustom` → template picker)
- Modify: `lib/engine/campaign_presets.dart` (`solo-custom`)
- Modify: `lib/engine/campaign_surfaces.dart` (Sheet row)
- Test: `test/campaign_presets_test.dart` runs clean; `test/custom_sheet_model_test.dart` (append preset/surface assertions)

- [ ] **Step 1: Write the failing test** — append to `test/custom_sheet_model_test.dart` (add `import 'package:juice_oracle/engine/campaign_presets.dart';` and `import 'package:juice_oracle/engine/campaign_surfaces.dart';`):

```dart
  test('solo-custom preset resolves to the custom ruleset', () {
    final p = kCampaignPresets.firstWhere((p) => p.id == 'solo-custom');
    final (mode, systems) = presetConfig(p);
    expect(systems.contains('custom'), isTrue);
    expect(mode, CampaignMode.party);
  });
  test('custom lights up a Sheet surface', () {
    final sheet = surfacesFor(CampaignMode.party, {'custom'})
        .firstWhere((v) => v.verb == 'Sheet');
    expect(sheet.rows.any((r) => r.on && r.requiresSystem == 'custom'), isTrue);
  });
```
> Confirm the `VerbSurfaces` field name for the verb (it may be `.verb` or `.name`); adjust the `.firstWhere` accessor to match `campaign_surfaces.dart`.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/custom_sheet_model_test.dart -n "solo-custom"`
Expected: FAIL — no `solo-custom` preset.

- [ ] **Step 3: Write minimal implementation**

In `lib/engine/campaign_presets.dart`, add to `kCampaignPresets` (next to `solo-cairn`):
```dart
  CampaignPreset(
      id: 'solo-custom',
      label: 'Custom / Homebrew',
      kind: 'Build your own sheet',
      blurb: 'Any game, your blocks',
      mode: CampaignMode.party,
      systems: {'custom', 'juice', 'party'}),
```

In `lib/engine/campaign_surfaces.dart`, add to the `'Sheet'` list (after the `Kal-Arath sheet` row):
```dart
    SurfaceRow('Custom / Homebrew sheet', requiresSystem: 'custom'),
```

In `lib/features/tracker_screen.dart`, replace `_newCustom` with a template-picker flow:
```dart
  Future<void> _newCustom() async {
    final template = await showDialog<CustomTemplate>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Start from…'),
        children: [
          for (final t in kCustomTemplates)
            SimpleDialogOption(
              key: Key('custom-template-${t.id}'),
              child: Text(t.label),
              onPressed: () => Navigator.pop(context, t),
            ),
        ],
      ),
    );
    if (template == null) return;
    final id = await ref
        .read(charactersProvider.notifier)
        .addCustom(template.blocks);
    if (mounted) setState(() => _editingId = id);
  }
```
Add the import: `import '../engine/custom_templates.dart';` (and `custom_sheet.dart` if not already imported for the dispatch).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/custom_sheet_model_test.dart test/campaign_presets_test.dart test/campaign_surfaces_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/tracker_screen.dart lib/engine/campaign_presets.dart lib/engine/campaign_surfaces.dart test/custom_sheet_model_test.dart
git commit -m "feat(custom): template picker on create + preset + surface row"
```

---

## Task 14: Full-suite verification + analyze + live smoke

**Files:** none (verification only)

- [ ] **Step 1: Static analysis**

Run: `flutter analyze`
Expected: No errors. Fix any analyzer issues introduced (unused imports, missing `mounted` guards) and re-run.

- [ ] **Step 2: Full test suite**

Run: `flutter test`
Expected: All tests PASS, including the completeness suites (`campaign_presets_test`, `new_campaign_dialog_test`, `system_primer_test`).

- [ ] **Step 3: Live smoke on macOS (per the rootBundle-hang note, do NOT add a HomeShell widget test — verify by running the app)**

Run: `flutter run -d macos`
Verify by hand: create a campaign with the **Custom / Homebrew** preset → roster → New → **Custom / Homebrew** → pick **Generic d20** → sheet renders in Play; toggle to Edit, add a **luck** block, configure it, toggle to Play, spend/reset; add a **roll** block with a prompted DC and confirm the snackbar. Back out and re-enter to confirm persistence. Export the campaign and confirm the `custom` payload is in the JSON.

- [ ] **Step 4: Commit (if any analyzer fixes were needed)**

```bash
git add -A
git commit -m "chore(custom): analyzer cleanup + full-suite green"
```

---

## Notes for the executor

- **rootBundle-hang rule:** never pump `JournalScreen`/`HomeShell` or call any asset `.load()` in tests. All custom-sheet widget tests pump `CustomSheetView` directly (no data-provider overrides needed — it reads only `charactersProvider` + theme).
- **Config dialogs (do these test-first — they ARE the builder UX):** Tasks 5/8/9/10/11 describe config dialogs in prose rather than full code because they all follow one pattern — a `StatefulBuilder` `AlertDialog` editing the block's `label` + type-specific `config`, persisting via `_save(_s.copyWith(blocks: ...map... copyWith(label:, config:)))`, disposing any `TextEditingController` in a `finally`. Mirror `_RenameDialog`/`addProgressTrackDialog` in `sheet_widgets.dart`. **The block-play tests in those tasks seed `config` directly, so they do NOT exercise the config dialogs.** To avoid shipping an untested authoring path, in **Task 5** write the counter config dialog FULLY and add a gating test as the exemplar: tap `custom-block-<id>-config` in Edit mode → change the "max" field → Save → assert the persisted `block.config['max']` changed. Every later config dialog (stat/roll/luck/hp/dropdown/timer/togglechips) copies that exemplar and gets the same one-line open-edit-save test in its own task. Keep dialogs minimal but real.
- **`VerbSurfaces` accessor:** verify the verb field name in `campaign_surfaces.dart` before writing the Task 13 test assertion.
- **Facts-only:** no block, template, label, or blurb may ship vendored game prose or names beyond generic mechanics.
