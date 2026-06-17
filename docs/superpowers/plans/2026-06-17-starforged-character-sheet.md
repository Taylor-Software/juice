# Starforged Character Sheet Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a bespoke Starforged player-character sheet (impacts, three legacy tracks, connections, Starforged assets) as a separate `StarforgedSheet` over the generic `Character`, reusing slice A's widgets via an extracted shared-widget module.

**Architecture:** Extract slice A's sheet widgets into `lib/features/sheet_widgets.dart` (parameterized by a `prefix` for widget keys), refactor `IronswornSheetView` to consume them (behavior + keys preserved), then build `StarforgedSheetView` from the same widgets. New optional `Character.starforged` field mirrors `Character.ironsworn`. No campaign-schema bump.

**Tech Stack:** Dart/Flutter, flutter_riverpod, shared_preferences (mock in tests). TDD with `flutter test` + `dart analyze`.

**Spec:** `docs/superpowers/specs/2026-06-17-starforged-character-sheet-design.md`

**Conventions (verified in-repo):**
- `IronswornSheet`/`Character` patterns: `lib/engine/models.dart`. Optional typed field mirrors `emulation`/`ironsworn` (param → field → conditional `toJson` → tolerant `maybeFromJson` → `copyWith` + `clearX`).
- Current sheet UI: `lib/features/ironsworn_sheet.dart` (methods `_stat`/`_meter`/`_intStepper`/`_vowRow`/`_addVow`/`_assetCard`/`_addAsset`, momentum row with `SizedBox(width:72)`-bounded Burn).
- Create flow + render branch: `lib/features/tracker_screen.dart:138-263`.
- `dart format` runs on every `.dart` save (hook). Widget tests MUST override `rulesetDataProvider(...)` (never rootBundle).
- Slice-A widget keys that MUST be preserved by the refactor: `ironsworn-sheet`, `iw-stat-<stat>-minus/plus`, `iw-<meter>-minus/plus`, `iw-mom-minus/plus`, `iw-burn`, `iw-deb-<id>`, `iw-xpEarned-minus/plus`, `iw-xpSpent-…`, `iw-bonds-…`, `iw-vow-<i>-rank/mark/unmark`, `iw-add-vow`, `vow-name`, `iw-asset-<i>-ability-<k>`, `iw-add-asset`, `pick-asset-<id>`, `sheet-back`, `iw-name`.

---

## Task 1: Extract shared sheet widgets; refactor IronswornSheetView

Pure refactor verified by the existing slice-A tests (no new tests, no behavior change). Also folds in the spec's correctness fix: `IronswornSheetView` pins its asset ruleset to `classic` instead of reading the global toggle.

**Files:**
- Create: `lib/features/sheet_widgets.dart`
- Modify: `lib/features/ironsworn_sheet.dart`
- Verify with: `test/character_sheet_ui_test.dart`, `test/character_sheet_test.dart`

- [ ] **Step 1: Create `lib/features/sheet_widgets.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../state/providers.dart';

/// Shared building blocks for the bespoke system sheets (Ironsworn, Starforged).
/// Each widget takes a [prefix] so the two sheets get distinct, stable widget
/// keys (e.g. 'iw' -> 'iw-mom-minus', 'sf' -> 'sf-mom-minus').

Widget sheetSection(BuildContext context, String title) => Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 6),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );

Widget statStepper({
  required String prefix,
  required String label,
  required int value,
  required ValueChanged<int> onSet,
}) =>
    Expanded(
      child: Column(children: [
        Text('$value',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(fontSize: 10)),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(
            key: Key('$prefix-stat-${label.toLowerCase()}-minus'),
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.remove, size: 16),
            onPressed: () => onSet(value - 1),
          ),
          IconButton(
            key: Key('$prefix-stat-${label.toLowerCase()}-plus'),
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add, size: 16),
            onPressed: () => onSet(value + 1),
          ),
        ]),
      ]),
    );

Widget meterStepper({
  required String prefix,
  required String label,
  required String meterKey,
  required int value,
  required ValueChanged<int> onSet,
}) =>
    Row(children: [
      SizedBox(width: 64, child: Text(label)),
      IconButton(
        key: Key('$prefix-$meterKey-minus'),
        icon: const Icon(Icons.remove_circle_outline),
        onPressed: () => onSet(value - 1),
      ),
      Text('$value / 5'),
      IconButton(
        key: Key('$prefix-$meterKey-plus'),
        icon: const Icon(Icons.add_circle_outline),
        onPressed: () => onSet(value + 1),
      ),
    ]);

Widget intStepper({
  required String prefix,
  required String fieldKey,
  required int value,
  required ValueChanged<int> onSet,
}) =>
    Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(
        key: Key('$prefix-$fieldKey-minus'),
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.remove_circle_outline),
        onPressed: () => onSet(value - 1),
      ),
      Text('$value'),
      IconButton(
        key: Key('$prefix-$fieldKey-plus'),
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.add_circle_outline),
        onPressed: () => onSet(value + 1),
      ),
    ]);

Widget momentumRow({
  required BuildContext context,
  required String prefix,
  required int momentum,
  required int momentumMax,
  required int momentumReset,
  required ValueChanged<int> onSet,
}) {
  final theme = Theme.of(context);
  return Row(children: [
    IconButton(
      key: Key('$prefix-mom-minus'),
      icon: const Icon(Icons.remove_circle_outline),
      onPressed: () => onSet(momentum - 1),
    ),
    Text(momentum >= 0 ? '+$momentum' : '$momentum',
        style: theme.textTheme.titleLarge),
    IconButton(
      key: Key('$prefix-mom-plus'),
      icon: const Icon(Icons.add_circle_outline),
      onPressed: () => onSet(momentum + 1),
    ),
    const Spacer(),
    Flexible(
      child: Text('max +$momentumMax · reset +$momentumReset',
          style: theme.textTheme.bodySmall),
    ),
    const SizedBox(width: 8),
    SizedBox(
      width: 72,
      child: FilledButton(
        key: Key('$prefix-burn'),
        onPressed: () => onSet(momentumReset),
        child: const Text('Burn'),
      ),
    ),
  ]);
}

/// Flat chip Wrap for debilities/impacts. [chipPrefix] is the full key stem,
/// e.g. 'iw-deb' -> 'iw-deb-shaken', 'sf-imp' -> 'sf-imp-shaken'.
Widget toggleChips({
  required String chipPrefix,
  required Map<String, String> labels,
  required Set<String> selected,
  required ValueChanged<Set<String>> onChanged,
}) =>
    Wrap(spacing: 6, runSpacing: 4, children: [
      for (final e in labels.entries)
        FilterChip(
          key: Key('$chipPrefix-${e.key}'),
          label: Text(e.value),
          selected: selected.contains(e.key),
          onSelected: (on) {
            final next = {...selected};
            if (on) {
              next.add(e.key);
            } else {
              next.remove(e.key);
            }
            onChanged(next);
          },
        ),
    ]);

/// A vow/connection row (a [ProgressTrack]). [prefix] e.g. 'iw-vow', 'sf-conn'.
Widget progressTrackRow({
  required BuildContext context,
  required String prefix,
  required int index,
  required ProgressTrack track,
  required ValueChanged<ProgressTrack> onChanged,
  required VoidCallback onDelete,
}) =>
    Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(track.name,
                    style: const TextStyle(fontWeight: FontWeight.bold))),
            DropdownButton<ProgressRank>(
              key: Key('$prefix-$index-rank'),
              value: track.rank,
              underline: const SizedBox.shrink(),
              items: [
                for (final r in ProgressRank.values)
                  DropdownMenuItem(value: r, child: Text(r.label)),
              ],
              onChanged: (r) => onChanged(track.copyWith(rank: r)),
            ),
            IconButton(
              key: Key('$prefix-$index-unmark'),
              icon: const Icon(Icons.remove_circle_outline),
              tooltip: 'Un-mark',
              onPressed: () => onChanged(track.marked(-1)),
            ),
            IconButton(
              key: Key('$prefix-$index-mark'),
              icon: const Icon(Icons.add_circle_outline),
              tooltip: 'Mark progress',
              onPressed: () => onChanged(track.marked(1)),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: onDelete,
            ),
          ]),
          Text('${track.boxes}/10 boxes · ${track.rank.label}',
              style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
    );

/// "Add progress track" dialog; returns the new track or null if cancelled.
/// [nameKey] keys the name field (e.g. 'vow-name', 'conn-name').
Future<ProgressTrack?> addProgressTrackDialog(
  BuildContext context, {
  required String nameKey,
  required String label,
}) async {
  final ctrl = TextEditingController();
  var rank = ProgressRank.dangerous;
  final name = await showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setLocal) => AlertDialog(
        title: Text('Add $label'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            key: Key(nameKey),
            controller: ctrl,
            autofocus: true,
            decoration: InputDecoration(labelText: label),
          ),
          const SizedBox(height: 12),
          DropdownButton<ProgressRank>(
            value: rank,
            isExpanded: true,
            items: [
              for (final r in ProgressRank.values)
                DropdownMenuItem(value: r, child: Text(r.label)),
            ],
            onChanged: (r) => setLocal(() => rank = r ?? rank),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, ctrl.text),
              child: const Text('Add')),
        ],
      ),
    ),
  );
  if (name == null || name.trim().isEmpty) return null;
  return ProgressTrack(name: name.trim(), rank: rank);
}

Widget assetCard({
  required String prefix,
  required int index,
  required AssetState asset,
  required ValueChanged<List<bool>> onAbilitiesChanged,
  required VoidCallback onDelete,
}) =>
    Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('${asset.name}  ·  ${asset.category}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: onDelete,
            ),
          ]),
          for (var k = 0; k < asset.enabledAbilities.length; k++)
            CheckboxListTile(
              key: Key('$prefix-asset-$index-ability-$k'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: asset.enabledAbilities[k],
              title: Text('Ability ${k + 1}'),
              onChanged: (on) {
                final flags = [...asset.enabledAbilities]..[k] = on ?? false;
                onAbilitiesChanged(flags);
              },
            ),
        ]),
      ),
    );

/// Loads [rulesetId] assets and shows the picker; returns the chosen def or null.
Future<IronswornAssetDef?> addAssetDialog(
    BuildContext context, WidgetRef ref, String rulesetId) async {
  final data = await ref.read(rulesetDataProvider(rulesetId).future);
  final defs = IronswornAssetDef.listFromRuleset(data);
  if (!context.mounted) return null;
  return showDialog<IronswornAssetDef>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Add asset'),
      children: [
        SizedBox(
          width: 320,
          height: 420,
          child: ListView(children: [
            for (final d in defs)
              ListTile(
                key: Key('pick-asset-${d.id}'),
                title: Text(d.name),
                subtitle: Text(d.category),
                onTap: () => Navigator.pop(context, d),
              ),
          ]),
        ),
      ],
    ),
  );
}

/// Rename dialog; returns the trimmed new name or null. [nameKey] keys the field.
Future<String?> renameDialog(BuildContext context,
    {required String nameKey, required String current}) async {
  final ctrl = TextEditingController(text: current);
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Rename'),
      content: TextField(
        key: Key(nameKey),
        controller: ctrl,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Name'),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text),
            child: const Text('Save')),
      ],
    ),
  );
  if (name == null || name.trim().isEmpty) return null;
  return name.trim();
}
```

- [ ] **Step 2: Replace `lib/features/ironsworn_sheet.dart` with the refactored version** (consumes shared widgets; keys + behavior identical; asset ruleset pinned to `classic`):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../state/providers.dart';
import 'sheet_widgets.dart';

/// Bespoke Classic Ironsworn character sheet. Renders for characters whose
/// [Character.ironsworn] is non-null; edits persist via charactersProvider.
class IronswornSheetView extends ConsumerWidget {
  const IronswornSheetView(
      {super.key, required this.character, required this.onBack});
  final Character character;
  final VoidCallback onBack;

  IronswornSheet get _s => character.ironsworn!;

  void _save(WidgetRef ref, IronswornSheet next) => ref
      .read(charactersProvider.notifier)
      .replace(character.copyWith(ironsworn: next));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final s = _s;
    return ListView(
      key: const Key('ironsworn-sheet'),
      padding: const EdgeInsets.all(12),
      children: [
        Row(children: [
          IconButton(
            key: const Key('sheet-back'),
            icon: const Icon(Icons.arrow_back),
            onPressed: onBack,
          ),
          Expanded(
            child: Text(character.name,
                style: theme.textTheme.titleLarge,
                overflow: TextOverflow.ellipsis),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Rename',
            onPressed: () async {
              final name = await renameDialog(context,
                  nameKey: 'iw-name', current: character.name);
              if (name != null) {
                await ref
                    .read(charactersProvider.notifier)
                    .replace(character.copyWith(name: name));
              }
            },
          ),
        ]),
        Text('Ironsworn · Classic', style: theme.textTheme.labelSmall),
        sheetSection(context, 'Stats'),
        Row(children: [
          statStepper(prefix: 'iw', label: 'EDGE', value: s.edge, onSet: (v) => _save(ref, s.copyWith(edge: v))),
          statStepper(prefix: 'iw', label: 'HEART', value: s.heart, onSet: (v) => _save(ref, s.copyWith(heart: v))),
          statStepper(prefix: 'iw', label: 'IRON', value: s.iron, onSet: (v) => _save(ref, s.copyWith(iron: v))),
          statStepper(prefix: 'iw', label: 'SHADOW', value: s.shadow, onSet: (v) => _save(ref, s.copyWith(shadow: v))),
          statStepper(prefix: 'iw', label: 'WITS', value: s.wits, onSet: (v) => _save(ref, s.copyWith(wits: v))),
        ]),
        sheetSection(context, 'Condition Meters'),
        meterStepper(prefix: 'iw', label: 'Health', meterKey: 'health', value: s.health, onSet: (v) => _save(ref, s.copyWith(health: v))),
        meterStepper(prefix: 'iw', label: 'Spirit', meterKey: 'spirit', value: s.spirit, onSet: (v) => _save(ref, s.copyWith(spirit: v))),
        meterStepper(prefix: 'iw', label: 'Supply', meterKey: 'supply', value: s.supply, onSet: (v) => _save(ref, s.copyWith(supply: v))),
        sheetSection(context, 'Momentum'),
        momentumRow(
          context: context,
          prefix: 'iw',
          momentum: s.momentum,
          momentumMax: s.momentumMax,
          momentumReset: s.momentumReset,
          onSet: (v) => _save(ref, s.copyWith(momentum: v)),
        ),
        sheetSection(context, 'Debilities'),
        toggleChips(
          chipPrefix: 'iw-deb',
          labels: kIronswornDebilities,
          selected: s.debilities,
          onChanged: (d) => _save(ref, s.copyWith(debilities: d)),
        ),
        sheetSection(context, 'Experience & Bonds'),
        Row(children: [
          const Text('XP earned'),
          intStepper(prefix: 'iw', fieldKey: 'xpEarned', value: s.xpEarned, onSet: (v) => _save(ref, s.copyWith(xpEarned: v))),
          const SizedBox(width: 16),
          const Text('spent'),
          intStepper(prefix: 'iw', fieldKey: 'xpSpent', value: s.xpSpent, onSet: (v) => _save(ref, s.copyWith(xpSpent: v))),
        ]),
        Row(children: [
          const Text('Bonds'),
          intStepper(prefix: 'iw', fieldKey: 'bonds', value: s.bonds, onSet: (v) => _save(ref, s.copyWith(bonds: v))),
          Text('/ 10', style: theme.textTheme.bodySmall),
        ]),
        sheetSection(context, 'Vows'),
        for (var i = 0; i < s.vows.length; i++)
          progressTrackRow(
            context: context,
            prefix: 'iw-vow',
            index: i,
            track: s.vows[i],
            onChanged: (t) => _save(ref, s.copyWith(vows: [...s.vows]..[i] = t)),
            onDelete: () => _save(ref, s.copyWith(vows: [...s.vows]..removeAt(i))),
          ),
        OutlinedButton.icon(
          key: const Key('iw-add-vow'),
          icon: const Icon(Icons.add),
          label: const Text('Add vow'),
          onPressed: () async {
            final t = await addProgressTrackDialog(context, nameKey: 'vow-name', label: 'Vow');
            if (t != null) _save(ref, _s.copyWith(vows: [..._s.vows, t]));
          },
        ),
        sheetSection(context, 'Assets'),
        for (var i = 0; i < s.assets.length; i++)
          assetCard(
            prefix: 'iw',
            index: i,
            asset: s.assets[i],
            onAbilitiesChanged: (flags) => _save(ref,
                s.copyWith(assets: [...s.assets]..[i] = s.assets[i].copyWith(enabledAbilities: flags))),
            onDelete: () => _save(ref, s.copyWith(assets: [...s.assets]..removeAt(i))),
          ),
        OutlinedButton.icon(
          key: const Key('iw-add-asset'),
          icon: const Icon(Icons.add),
          label: const Text('Add asset'),
          onPressed: () async {
            final def = await addAssetDialog(context, ref, 'classic');
            if (def != null) _save(ref, _s.copyWith(assets: [..._s.assets, def.toState()]));
          },
        ),
        sheetSection(context, 'Notes'),
        Text(character.note.isEmpty ? '—' : character.note),
      ],
    );
  }
}
```

- [ ] **Step 3: Run the slice-A suites — must stay green**

Run: `flutter test test/character_sheet_ui_test.dart test/character_sheet_test.dart`
Expected: all pass (the refactor preserves keys + behavior; `iw-` keys unchanged).

- [ ] **Step 4: Analyze**

Run: `dart analyze lib/features/sheet_widgets.dart lib/features/ironsworn_sheet.dart`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/features/sheet_widgets.dart lib/features/ironsworn_sheet.dart
git commit -m "refactor(sheets): extract shared sheet widgets; pin Ironsworn assets to classic"
```

---

## Task 2: `StarforgedSheet` model + `kStarforgedImpacts`

**Files:**
- Modify: `lib/engine/models.dart` (add after the `IronswornAssetDef` class — locate by content; it's the last sheet-related class)
- Test: `test/character_sheet_test.dart`

- [ ] **Step 1: Write the failing test** (add inside `void main()`):

```dart
  group('StarforgedSheet', () {
    test('premade defaults match the standard starting sheet', () {
      final s = StarforgedSheet.premade();
      expect([s.edge, s.heart, s.iron, s.shadow, s.wits], [3, 2, 2, 1, 1]);
      expect([s.health, s.spirit, s.supply], [5, 5, 5]);
      expect(s.momentum, 2);
      expect(s.momentumMax, 10);
      expect(s.momentumReset, 2);
      expect([s.questsLegacy, s.bondsLegacy, s.discoveriesLegacy], [0, 0, 0]);
    });

    test('impacts lower max + reset and re-clamp momentum via copyWith', () {
      final s = const StarforgedSheet(momentum: 10)
          .copyWith(impacts: {'wounded', 'doomed'});
      expect(s.momentumMax, 8);
      expect(s.momentumReset, 0);
      expect(s.momentum, 8);
    });

    test('values are clamped to legal ranges', () {
      final s = const StarforgedSheet().copyWith(
        edge: 9, health: 99, supply: -2, momentum: 99,
        questsLegacy: 50, discoveriesLegacy: -3, xpSpent: -1,
      );
      expect(s.edge, 3);
      expect(s.health, 5);
      expect(s.supply, 0);
      expect(s.momentum, 10);
      expect(s.questsLegacy, 10);
      expect(s.discoveriesLegacy, 0);
      expect(s.xpSpent, 0);
    });

    test('round-trips with legacy, impacts, vows, connections, assets', () {
      const s = StarforgedSheet(
        edge: 3, heart: 2, iron: 2, shadow: 1, wits: 1,
        health: 4, spirit: 3, supply: 5, momentum: -2,
        xpEarned: 6, xpSpent: 4,
        questsLegacy: 3, bondsLegacy: 1, discoveriesLegacy: 2,
        impacts: {'shaken'},
        vows: [ProgressTrack(name: 'Reach the Forge', rank: ProgressRank.formidable, ticks: 4)],
        connections: [ProgressTrack(name: 'Lara', rank: ProgressRank.dangerous, ticks: 8)],
        assets: [AssetState(assetId: 'starforged/assets/path/ace', name: 'Ace')],
      );
      final back = StarforgedSheet.maybeFromJson(s.toJson())!;
      expect(back.health, 4);
      expect(back.momentum, -2);
      expect(back.questsLegacy, 3);
      expect(back.impacts, {'shaken'});
      expect(back.vows.single.ticks, 4);
      expect(back.connections.single.name, 'Lara');
      expect(back.assets.single.name, 'Ace');
      expect(back.momentumMax, 9);
    });

    test('tolerates junk and unknown impact ids', () {
      expect(StarforgedSheet.maybeFromJson('x'), isNull);
      final s = StarforgedSheet.maybeFromJson({
        'edge': 'three',
        'momentum': 'fast',
        'impacts': ['wounded', 'bogus', 7],
        'connections': ['junk'],
        'assets': 'nope',
      })!;
      expect(s.edge, 1);
      expect(s.momentum, 2);
      expect(s.impacts, {'wounded'});
      expect(s.connections, isEmpty);
      expect(s.assets, isEmpty);
    });
  });
```

- [ ] **Step 2: Run, verify fail**

Run: `flutter test test/character_sheet_test.dart`
Expected: FAIL — `StarforgedSheet`/`kStarforgedImpacts` undefined.

- [ ] **Step 3: Implement** (add after `IronswornAssetDef` in `models.dart`):

```dart
/// Starforged impacts (replace Classic debilities). Each marked impact lowers
/// max momentum and the burn-reset value by 1. Ordered by datasworn category:
/// misfortunes, vehicle troubles, burdens, lasting effects.
const kStarforgedImpacts = <String, String>{
  'wounded': 'Wounded',
  'shaken': 'Shaken',
  'unprepared': 'Unprepared',
  'battered': 'Battered',
  'cursed': 'Cursed',
  'doomed': 'Doomed',
  'tormented': 'Tormented',
  'indebted': 'Indebted',
  'permanently_harmed': 'Permanently Harmed',
  'traumatized': 'Traumatized',
};

/// Bespoke Starforged sheet. Additive on [Character] like [IronswornSheet]:
/// null until "New Starforged character" writes it.
class StarforgedSheet {
  const StarforgedSheet({
    this.edge = 1,
    this.heart = 1,
    this.iron = 1,
    this.shadow = 1,
    this.wits = 1,
    this.health = 5,
    this.spirit = 5,
    this.supply = 5,
    this.momentum = 2,
    this.xpEarned = 0,
    this.xpSpent = 0,
    this.questsLegacy = 0,
    this.bondsLegacy = 0,
    this.discoveriesLegacy = 0,
    this.impacts = const {},
    this.vows = const [],
    this.connections = const [],
    this.assets = const [],
  });

  final int edge, heart, iron, shadow, wits; // 1..3
  final int health, spirit, supply; // 0..5
  final int momentum; // -6..momentumMax
  final int xpEarned, xpSpent; // >=0
  final int questsLegacy, bondsLegacy, discoveriesLegacy; // 0..10 boxes
  final Set<String> impacts; // ids from kStarforgedImpacts
  final List<ProgressTrack> vows;
  final List<ProgressTrack> connections;
  final List<AssetState> assets;

  int get momentumMax => 10 - impacts.length;
  int get momentumReset => (2 - impacts.length).clamp(0, 2);

  factory StarforgedSheet.premade() => const StarforgedSheet(
        edge: 3, heart: 2, iron: 2, shadow: 1, wits: 1,
        health: 5, spirit: 5, supply: 5, momentum: 2,
      );

  StarforgedSheet copyWith({
    int? edge, int? heart, int? iron, int? shadow, int? wits,
    int? health, int? spirit, int? supply,
    int? momentum, int? xpEarned, int? xpSpent,
    int? questsLegacy, int? bondsLegacy, int? discoveriesLegacy,
    Set<String>? impacts,
    List<ProgressTrack>? vows,
    List<ProgressTrack>? connections,
    List<AssetState>? assets,
  }) {
    final imp = impacts ?? this.impacts;
    final maxM = 10 - imp.length;
    return StarforgedSheet(
      edge: (edge ?? this.edge).clamp(1, 3),
      heart: (heart ?? this.heart).clamp(1, 3),
      iron: (iron ?? this.iron).clamp(1, 3),
      shadow: (shadow ?? this.shadow).clamp(1, 3),
      wits: (wits ?? this.wits).clamp(1, 3),
      health: (health ?? this.health).clamp(0, 5),
      spirit: (spirit ?? this.spirit).clamp(0, 5),
      supply: (supply ?? this.supply).clamp(0, 5),
      momentum: (momentum ?? this.momentum).clamp(-6, maxM),
      xpEarned: (xpEarned ?? this.xpEarned).clamp(0, 1 << 31),
      xpSpent: (xpSpent ?? this.xpSpent).clamp(0, 1 << 31),
      questsLegacy: (questsLegacy ?? this.questsLegacy).clamp(0, 10),
      bondsLegacy: (bondsLegacy ?? this.bondsLegacy).clamp(0, 10),
      discoveriesLegacy: (discoveriesLegacy ?? this.discoveriesLegacy).clamp(0, 10),
      impacts: imp,
      vows: vows ?? this.vows,
      connections: connections ?? this.connections,
      assets: assets ?? this.assets,
    );
  }

  Map<String, dynamic> toJson() => {
        'edge': edge, 'heart': heart, 'iron': iron, 'shadow': shadow,
        'wits': wits, 'health': health, 'spirit': spirit, 'supply': supply,
        'momentum': momentum, 'xpEarned': xpEarned, 'xpSpent': xpSpent,
        'questsLegacy': questsLegacy, 'bondsLegacy': bondsLegacy,
        'discoveriesLegacy': discoveriesLegacy,
        if (impacts.isNotEmpty) 'impacts': impacts.toList(),
        if (vows.isNotEmpty) 'vows': vows.map((v) => v.toJson()).toList(),
        if (connections.isNotEmpty)
          'connections': connections.map((c) => c.toJson()).toList(),
        if (assets.isNotEmpty) 'assets': assets.map((a) => a.toJson()).toList(),
      };

  static StarforgedSheet? maybeFromJson(dynamic j) {
    if (j is! Map) return null;
    int intOr(dynamic v, int d) => v is int ? v : d;
    List<ProgressTrack> tracks(dynamic v) => v is List
        ? v.map(ProgressTrack.maybeFromJson).whereType<ProgressTrack>().toList()
        : const [];
    final imp = j['impacts'] is List
        ? (j['impacts'] as List)
            .whereType<String>()
            .where(kStarforgedImpacts.containsKey)
            .toSet()
        : <String>{};
    final maxM = 10 - imp.length;
    return StarforgedSheet(
      edge: intOr(j['edge'], 1).clamp(1, 3),
      heart: intOr(j['heart'], 1).clamp(1, 3),
      iron: intOr(j['iron'], 1).clamp(1, 3),
      shadow: intOr(j['shadow'], 1).clamp(1, 3),
      wits: intOr(j['wits'], 1).clamp(1, 3),
      health: intOr(j['health'], 5).clamp(0, 5),
      spirit: intOr(j['spirit'], 5).clamp(0, 5),
      supply: intOr(j['supply'], 5).clamp(0, 5),
      momentum: intOr(j['momentum'], 2).clamp(-6, maxM),
      xpEarned: intOr(j['xpEarned'], 0).clamp(0, 1 << 31),
      xpSpent: intOr(j['xpSpent'], 0).clamp(0, 1 << 31),
      questsLegacy: intOr(j['questsLegacy'], 0).clamp(0, 10),
      bondsLegacy: intOr(j['bondsLegacy'], 0).clamp(0, 10),
      discoveriesLegacy: intOr(j['discoveriesLegacy'], 0).clamp(0, 10),
      impacts: imp,
      vows: tracks(j['vows']),
      connections: tracks(j['connections']),
      assets: j['assets'] is List
          ? (j['assets'] as List)
              .map(AssetState.maybeFromJson)
              .whereType<AssetState>()
              .toList()
          : const [],
    );
  }
}
```

- [ ] **Step 4: Run, verify pass**

Run: `flutter test test/character_sheet_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/models.dart test/character_sheet_test.dart
git commit -m "feat(starforged): StarforgedSheet model + impacts"
```

---

## Task 3: Wire `StarforgedSheet` into `Character`

**Files:**
- Modify: `lib/engine/models.dart` (the `Character` class — locate the `ironsworn` wiring by content; line numbers are stale)
- Test: `test/character_sheet_test.dart`

- [ ] **Step 1: Write the failing test** (add inside `void main()`):

```dart
  group('Character.starforged', () {
    test('round-trips and is omitted when null', () {
      const plain = Character(id: 'p', name: 'Plain');
      expect(plain.toJson().containsKey('starforged'), isFalse);
      final c = Character(
          id: 's', name: 'Nova', starforged: StarforgedSheet.premade());
      final back = Character.fromJson(c.toJson());
      expect(back.starforged!.edge, 3);
      expect(back.starforged!.momentum, 2);
    });

    test('copyWith sets and clears starforged', () {
      const c = Character(id: 's2', name: 'L');
      final set = c.copyWith(starforged: StarforgedSheet.premade());
      expect(set.starforged, isNotNull);
      expect(set.copyWith().starforged, isNotNull);
      expect(set.copyWith(clearStarforged: true).starforged, isNull);
    });

    test('junk starforged block is tolerated as null', () {
      final c = Character.fromJson(
          {'id': 's3', 'name': 'J', 'starforged': 'junk'});
      expect(c.starforged, isNull);
    });
  });
```

- [ ] **Step 2: Run, verify fail**

Run: `flutter test test/character_sheet_test.dart`
Expected: FAIL — `Character` has no `starforged`.

- [ ] **Step 3: Implement** — five edits to the `Character` class, each placed immediately after the matching `ironsworn` line (locate by content):

(a) Constructor — after `this.ironsworn,`:
```dart
    this.starforged,
```
(b) Field — after `final IronswornSheet? ironsworn;` (and its doc comment):
```dart
  /// Bespoke Starforged sheet; null unless this is a Starforged PC.
  final StarforgedSheet? starforged;
```
(c) `copyWith` params — after `bool clearIronsworn = false,`:
```dart
    StarforgedSheet? starforged,
    bool clearStarforged = false,
```
(d) `copyWith` body — after the `ironsworn:` line:
```dart
        starforged: clearStarforged ? null : (starforged ?? this.starforged),
```
(e) `toJson` — after the `if (ironsworn != null) …` line:
```dart
        if (starforged != null) 'starforged': starforged!.toJson(),
```
(f) `fromJson` — after the `ironsworn: …` line:
```dart
        starforged: StarforgedSheet.maybeFromJson(j['starforged']),
```

- [ ] **Step 4: Run, verify pass**

Run: `flutter test test/character_sheet_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/models.dart test/character_sheet_test.dart
git commit -m "feat(starforged): wire StarforgedSheet onto Character"
```

---

## Task 4: `CharacterNotifier.addStarforged()`

**Files:**
- Modify: `lib/state/providers.dart` (`CharacterNotifier`, after `addIronsworn` — locate by content)
- Test: `test/character_provider_test.dart`

- [ ] **Step 1: Write the failing test** (add inside the existing `void main()` of `test/character_provider_test.dart`):

```dart
  test('addStarforged prepends a premade Starforged character', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(charactersProvider.future);
    final id = await c.read(charactersProvider.notifier).addStarforged();
    final chars = await c.read(charactersProvider.future);
    expect(chars.first.id, id);
    expect(chars.first.starforged, isNotNull);
    expect(chars.first.starforged!.edge, 3);
  });
```

- [ ] **Step 2: Run, verify fail**

Run: `flutter test test/character_provider_test.dart`
Expected: FAIL — `addStarforged` undefined.

- [ ] **Step 3: Implement** — add to `CharacterNotifier` after `addIronsworn`:

```dart
  /// Creates a pre-made Starforged PC at the top and returns its id.
  Future<String> addStarforged() async {
    final id = _newId();
    await _persist([
      Character(
          id: id,
          name: 'New Starforged character',
          starforged: StarforgedSheet.premade()),
      ...await _ready,
    ]);
    return id;
  }
```

- [ ] **Step 4: Run, verify pass**

Run: `flutter test test/character_provider_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/state/providers.dart test/character_provider_test.dart
git commit -m "feat(starforged): addStarforged notifier method"
```

---

## Task 5: `StarforgedSheetView` core + render branch + create flow

**Files:**
- Create: `lib/features/starforged_sheet.dart`
- Modify: `lib/features/tracker_screen.dart`
- Test: `test/character_sheet_ui_test.dart`

- [ ] **Step 1: Write the failing tests** (add inside `void main()`; reuse existing imports):

```dart
  Future<ProviderContainer> pumpStarforged(WidgetTester tester,
      {String sf = '{"edge":3,"heart":2,"iron":2,"shadow":1,"wits":1,'
          '"health":5,"spirit":5,"supply":5,"momentum":2,"xpEarned":0,'
          '"xpSpent":0,"questsLegacy":0,"bondsLegacy":0,"discoveriesLegacy":0}'}) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1",'
              '"systems":["ironsworn"]}]}',
      'juice.characters.v1.default':
          '[{"id":"sf","name":"Nova","note":"","stats":[],"tracks":[],'
              '"tags":[],"starforged":$sf}]',
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CharactersPane()))));
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
        tester.element(find.byType(CharactersPane)));
  }

  testWidgets('opening a Starforged character shows the bespoke sheet',
      (tester) async {
    await pumpStarforged(tester);
    await tester.tap(find.text('Nova'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('starforged-sheet')), findsOneWidget);
    expect(find.text('EDGE'), findsOneWidget);
    expect(find.text('Quests'), findsOneWidget);
  });

  testWidgets('SF meter/momentum/legacy steppers persist', (tester) async {
    final c = await pumpStarforged(tester);
    await tester.tap(find.text('Nova'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sf-health-minus')));
    await tester.pumpAndSettle();
    expect((await c.read(charactersProvider.future)).single.starforged!.health, 4);
    await tester.tap(find.byKey(const Key('sf-mom-minus')));
    await tester.pumpAndSettle();
    expect((await c.read(charactersProvider.future)).single.starforged!.momentum, 1);
    await tester.tap(find.byKey(const Key('sf-quests-plus')));
    await tester.pumpAndSettle();
    expect((await c.read(charactersProvider.future)).single.starforged!.questsLegacy, 1);
  });

  testWidgets('SF Burn resets; impact lowers max', (tester) async {
    final c = await pumpStarforged(tester,
        sf: '{"edge":3,"heart":2,"iron":2,"shadow":1,"wits":1,"health":5,'
            '"spirit":5,"supply":5,"momentum":9,"xpEarned":0,"xpSpent":0,'
            '"questsLegacy":0,"bondsLegacy":0,"discoveriesLegacy":0}');
    await tester.tap(find.text('Nova'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sf-burn')));
    await tester.pumpAndSettle();
    expect((await c.read(charactersProvider.future)).single.starforged!.momentum, 2);
    await tester.tap(find.byKey(const Key('sf-imp-doomed')));
    await tester.pumpAndSettle();
    final s = (await c.read(charactersProvider.future)).single.starforged!;
    expect(s.impacts, {'doomed'});
    expect(s.momentumMax, 9);
  });

  testWidgets('create flow offers Starforged and makes a premade SF character',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1",'
              '"systems":["ironsworn"]}]}',
      'juice.characters.v1.default': '[]',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CharactersPane()))));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new-starforged')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('starforged-sheet')), findsOneWidget);
    final chars = await c.read(charactersProvider.future);
    expect(chars.single.starforged!.edge, 3);
  });
```

- [ ] **Step 2: Run, verify fail**

Run: `flutter test test/character_sheet_ui_test.dart`
Expected: FAIL — `starforged-sheet` / `new-starforged` not found.

- [ ] **Step 3: Create `lib/features/starforged_sheet.dart`** (core sheet; vows/connections added in Task 6, assets in Task 7):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../state/providers.dart';
import 'sheet_widgets.dart';

/// Bespoke Starforged character sheet. Renders for characters whose
/// [Character.starforged] is non-null; edits persist via charactersProvider.
class StarforgedSheetView extends ConsumerWidget {
  const StarforgedSheetView(
      {super.key, required this.character, required this.onBack});
  final Character character;
  final VoidCallback onBack;

  StarforgedSheet get _s => character.starforged!;

  void _save(WidgetRef ref, StarforgedSheet next) => ref
      .read(charactersProvider.notifier)
      .replace(character.copyWith(starforged: next));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final s = _s;
    Widget legacy(String label, String key, int value, ValueChanged<int> onSet) =>
        Row(children: [
          SizedBox(width: 96, child: Text(label)),
          intStepper(prefix: 'sf', fieldKey: key, value: value, onSet: onSet),
          Text('/ 10', style: theme.textTheme.bodySmall),
        ]);
    return ListView(
      key: const Key('starforged-sheet'),
      padding: const EdgeInsets.all(12),
      children: [
        Row(children: [
          IconButton(
            key: const Key('sheet-back'),
            icon: const Icon(Icons.arrow_back),
            onPressed: onBack,
          ),
          Expanded(
            child: Text(character.name,
                style: theme.textTheme.titleLarge,
                overflow: TextOverflow.ellipsis),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Rename',
            onPressed: () async {
              final name = await renameDialog(context,
                  nameKey: 'sf-name', current: character.name);
              if (name != null) {
                await ref
                    .read(charactersProvider.notifier)
                    .replace(character.copyWith(name: name));
              }
            },
          ),
        ]),
        Text('Starforged', style: theme.textTheme.labelSmall),
        sheetSection(context, 'Stats'),
        Row(children: [
          statStepper(prefix: 'sf', label: 'EDGE', value: s.edge, onSet: (v) => _save(ref, s.copyWith(edge: v))),
          statStepper(prefix: 'sf', label: 'HEART', value: s.heart, onSet: (v) => _save(ref, s.copyWith(heart: v))),
          statStepper(prefix: 'sf', label: 'IRON', value: s.iron, onSet: (v) => _save(ref, s.copyWith(iron: v))),
          statStepper(prefix: 'sf', label: 'SHADOW', value: s.shadow, onSet: (v) => _save(ref, s.copyWith(shadow: v))),
          statStepper(prefix: 'sf', label: 'WITS', value: s.wits, onSet: (v) => _save(ref, s.copyWith(wits: v))),
        ]),
        sheetSection(context, 'Condition Meters'),
        meterStepper(prefix: 'sf', label: 'Health', meterKey: 'health', value: s.health, onSet: (v) => _save(ref, s.copyWith(health: v))),
        meterStepper(prefix: 'sf', label: 'Spirit', meterKey: 'spirit', value: s.spirit, onSet: (v) => _save(ref, s.copyWith(spirit: v))),
        meterStepper(prefix: 'sf', label: 'Supply', meterKey: 'supply', value: s.supply, onSet: (v) => _save(ref, s.copyWith(supply: v))),
        sheetSection(context, 'Momentum'),
        momentumRow(
          context: context,
          prefix: 'sf',
          momentum: s.momentum,
          momentumMax: s.momentumMax,
          momentumReset: s.momentumReset,
          onSet: (v) => _save(ref, s.copyWith(momentum: v)),
        ),
        sheetSection(context, 'Impacts'),
        toggleChips(
          chipPrefix: 'sf-imp',
          labels: kStarforgedImpacts,
          selected: s.impacts,
          onChanged: (i) => _save(ref, s.copyWith(impacts: i)),
        ),
        sheetSection(context, 'Legacy Tracks'),
        legacy('Quests', 'quests', s.questsLegacy, (v) => _save(ref, s.copyWith(questsLegacy: v))),
        legacy('Bonds', 'bonds', s.bondsLegacy, (v) => _save(ref, s.copyWith(bondsLegacy: v))),
        legacy('Discoveries', 'discoveries', s.discoveriesLegacy, (v) => _save(ref, s.copyWith(discoveriesLegacy: v))),
        sheetSection(context, 'Experience'),
        Row(children: [
          const Text('XP earned'),
          intStepper(prefix: 'sf', fieldKey: 'xpEarned', value: s.xpEarned, onSet: (v) => _save(ref, s.copyWith(xpEarned: v))),
          const SizedBox(width: 16),
          const Text('spent'),
          intStepper(prefix: 'sf', fieldKey: 'xpSpent', value: s.xpSpent, onSet: (v) => _save(ref, s.copyWith(xpSpent: v))),
        ]),
        sheetSection(context, 'Notes'),
        Text(character.note.isEmpty ? '—' : character.note),
      ],
    );
  }
}
```

- [ ] **Step 4: Wire render branch + create flow in `lib/features/tracker_screen.dart`**

(a) Add import with the other relative imports:
```dart
import 'starforged_sheet.dart';
```
(b) Render branch — replace the `if (c.ironsworn != null) { … }` block (locate by content) so Starforged is checked first:
```dart
              final c = match.first;
              if (c.starforged != null) {
                return StarforgedSheetView(
                  character: c,
                  onBack: () => setState(() => _editingId = null),
                );
              }
              if (c.ironsworn != null) {
                return IronswornSheetView(
                  character: c,
                  onBack: () => setState(() => _editingId = null),
                );
              }
              return _buildSheet(context, c);
```
(c) Add a Starforged button to the chooser in `_onAdd` — add after the `new-ironsworn` `FilledButton`:
```dart
          FilledButton(
            key: const Key('new-starforged'),
            onPressed: () => Navigator.pop(context, 'starforged'),
            child: const Text('Starforged'),
          ),
```
(d) Handle the choice — add after the `else if (choice == 'ironsworn') { … }` branch in `_onAdd`:
```dart
    } else if (choice == 'starforged') {
      await _newStarforged();
```
(e) Add the `_newStarforged` method next to `_newIronsworn`:
```dart
  Future<void> _newStarforged() async {
    // Enable the Starforged ruleset for Moves-tool parity (asset picker reads
    // the bundled JSON regardless). This drops the classic toggle; existing
    // Classic sheets are unaffected (each sheet pins its own asset ruleset).
    final rs = ref.read(rulesetsProvider).valueOrNull ?? const <String>{};
    if (!rs.contains('starforged')) {
      await ref.read(rulesetsProvider.notifier).setRuleset('starforged', true);
    }
    final id = await ref.read(charactersProvider.notifier).addStarforged();
    if (mounted) setState(() => _editingId = id);
  }
```

- [ ] **Step 5: Run, verify pass**

Run: `flutter test test/character_sheet_ui_test.dart`
Expected: PASS (new SF tests + all existing tests green).

- [ ] **Step 6: Analyze**

Run: `dart analyze lib/features/starforged_sheet.dart lib/features/tracker_screen.dart`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add lib/features/starforged_sheet.dart lib/features/tracker_screen.dart test/character_sheet_ui_test.dart
git commit -m "feat(starforged): bespoke sheet core + render branch + create flow"
```

---

## Task 6: Vows + Connections sections

**Files:**
- Modify: `lib/features/starforged_sheet.dart`
- Test: `test/character_sheet_ui_test.dart`

- [ ] **Step 1: Write the failing test** (add inside `void main()`):

```dart
  testWidgets('SF add a vow and a connection, then mark progress',
      (tester) async {
    final c = await pumpStarforged(tester);
    await tester.tap(find.text('Nova'));
    await tester.pumpAndSettle();
    // Vow
    await tester.ensureVisible(find.byKey(const Key('sf-add-vow')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sf-add-vow')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('vow-name')), 'Reach the Forge');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('sf-vow-0-mark')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sf-vow-0-mark')));
    await tester.pumpAndSettle();
    expect((await c.read(charactersProvider.future)).single.starforged!.vows.single.ticks, 8);
    // Connection
    await tester.ensureVisible(find.byKey(const Key('sf-add-conn')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sf-add-conn')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('conn-name')), 'Lara');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    final sf = (await c.read(charactersProvider.future)).single.starforged!;
    expect(sf.connections.single.name, 'Lara');
  });
```

- [ ] **Step 2: Run, verify fail**

Run: `flutter test test/character_sheet_ui_test.dart`
Expected: FAIL — `sf-add-vow` not found.

- [ ] **Step 3: Implement** — in `starforged_sheet.dart`, insert two sections into the `children:` list immediately **before** `sheetSection(context, 'Notes')`:

```dart
        sheetSection(context, 'Vows'),
        for (var i = 0; i < s.vows.length; i++)
          progressTrackRow(
            context: context,
            prefix: 'sf-vow',
            index: i,
            track: s.vows[i],
            onChanged: (t) => _save(ref, s.copyWith(vows: [...s.vows]..[i] = t)),
            onDelete: () => _save(ref, s.copyWith(vows: [...s.vows]..removeAt(i))),
          ),
        OutlinedButton.icon(
          key: const Key('sf-add-vow'),
          icon: const Icon(Icons.add),
          label: const Text('Add vow'),
          onPressed: () async {
            final t = await addProgressTrackDialog(context, nameKey: 'vow-name', label: 'Vow');
            if (t != null) _save(ref, _s.copyWith(vows: [..._s.vows, t]));
          },
        ),
        sheetSection(context, 'Connections'),
        for (var i = 0; i < s.connections.length; i++)
          progressTrackRow(
            context: context,
            prefix: 'sf-conn',
            index: i,
            track: s.connections[i],
            onChanged: (t) => _save(ref, s.copyWith(connections: [...s.connections]..[i] = t)),
            onDelete: () => _save(ref, s.copyWith(connections: [...s.connections]..removeAt(i))),
          ),
        OutlinedButton.icon(
          key: const Key('sf-add-conn'),
          icon: const Icon(Icons.add),
          label: const Text('Add connection'),
          onPressed: () async {
            final t = await addProgressTrackDialog(context, nameKey: 'conn-name', label: 'Connection');
            if (t != null) _save(ref, _s.copyWith(connections: [..._s.connections, t]));
          },
        ),
```

- [ ] **Step 4: Run, verify pass**

Run: `flutter test test/character_sheet_ui_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/starforged_sheet.dart test/character_sheet_ui_test.dart
git commit -m "feat(starforged): vows + connections sections"
```

---

## Task 7: Assets section (Starforged datasworn picker)

**Files:**
- Modify: `lib/features/starforged_sheet.dart`
- Test: `test/character_sheet_ui_test.dart`

- [ ] **Step 1: Write the failing test** (add inside `void main()`; overrides `rulesetDataProvider('starforged')`):

```dart
  testWidgets('SF pick an asset and toggle an ability', (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1",'
              '"systems":["ironsworn"]}]}',
      'juice.rulesets.v1': '["starforged"]',
      'juice.characters.v1.default':
          '[{"id":"sf","name":"Nova","note":"","stats":[],"tracks":[],'
              '"tags":[],"starforged":{"edge":3,"heart":2,"iron":2,"shadow":1,'
              '"wits":1,"health":5,"spirit":5,"supply":5,"momentum":2,'
              '"xpEarned":0,"xpSpent":0,"questsLegacy":0,"bondsLegacy":0,'
              '"discoveriesLegacy":0}}]',
    });
    final fixture = {
      'asset_collections': [
        {
          'name': 'Path',
          'assets': [
            {
              'id': 'starforged/assets/path/ace',
              'name': 'Ace',
              'category': 'Path',
              'abilities': [
                {'text': 'Reroll a die', 'enabled': true},
                {'text': 'Push your luck', 'enabled': false},
              ],
            },
          ],
        },
      ],
    };
    final c = ProviderContainer(overrides: [
      rulesetDataProvider('starforged').overrideWith((ref) async => fixture),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CharactersPane()))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nova'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('sf-add-asset')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sf-add-asset')));
    await tester.pumpAndSettle();
    await tester.tap(
        find.byKey(const Key('pick-asset-starforged/assets/path/ace')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ace'), findsOneWidget);
    var asset = (await c.read(charactersProvider.future)).single.starforged!.assets.single;
    expect(asset.enabledAbilities, [true, false]);
    await tester.ensureVisible(find.byKey(const Key('sf-asset-0-ability-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sf-asset-0-ability-1')));
    await tester.pumpAndSettle();
    asset = (await c.read(charactersProvider.future)).single.starforged!.assets.single;
    expect(asset.enabledAbilities, [true, true]);
  });
```

- [ ] **Step 2: Run, verify fail**

Run: `flutter test test/character_sheet_ui_test.dart`
Expected: FAIL — `sf-add-asset` not found.

- [ ] **Step 3: Implement** — in `starforged_sheet.dart`, insert an Assets section into the `children:` list immediately **before** `sheetSection(context, 'Notes')`:

```dart
        sheetSection(context, 'Assets'),
        for (var i = 0; i < s.assets.length; i++)
          assetCard(
            prefix: 'sf',
            index: i,
            asset: s.assets[i],
            onAbilitiesChanged: (flags) => _save(ref,
                s.copyWith(assets: [...s.assets]..[i] = s.assets[i].copyWith(enabledAbilities: flags))),
            onDelete: () => _save(ref, s.copyWith(assets: [...s.assets]..removeAt(i))),
          ),
        OutlinedButton.icon(
          key: const Key('sf-add-asset'),
          icon: const Icon(Icons.add),
          label: const Text('Add asset'),
          onPressed: () async {
            final def = await addAssetDialog(context, ref, 'starforged');
            if (def != null) _save(ref, _s.copyWith(assets: [..._s.assets, def.toState()]));
          },
        ),
```

- [ ] **Step 4: Run, verify pass**

Run: `flutter test test/character_sheet_ui_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/starforged_sheet.dart test/character_sheet_ui_test.dart
git commit -m "feat(starforged): assets section (picker + ability toggles)"
```

---

## Task 8: Real-data test + full verification + docs

**Files:**
- Modify: `test/ruleset_assets_test.dart`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Write the real-data test** — add to the existing `void main()` in `test/ruleset_assets_test.dart`:

```dart
  test('real ruleset_starforged.json parses into 87 well-formed asset defs', () {
    final raw = File('assets/ruleset_starforged.json').readAsStringSync();
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final defs = IronswornAssetDef.listFromRuleset(data);
    expect(defs.length, 87, reason: 'starforged has 87 assets across 6 categories');
    for (final d in defs) {
      expect(d.id, isNotEmpty);
      expect(d.name, isNotEmpty);
      expect(d.abilityEnabled.length, d.abilities.length);
    }
    final cats = defs.map((d) => d.category).toSet();
    expect(cats, containsAll(<String>['Path', 'Module', 'Companion', 'Deed']));
  });
```

- [ ] **Step 2: Run the real-data + full suites**

Run: `flutter test test/ruleset_assets_test.dart`
Expected: PASS (87 SF assets parse).

Run: `flutter test`
Expected: all pass (no regressions; slice-A + Starforged tests green).

- [ ] **Step 3: Analyze**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 4: Update CLAUDE.md** — the `build_datasworn.py` bullet currently ends with the Ironsworn-sheet sentence. Append after it:

> The same shared sheet widgets (`lib/features/sheet_widgets.dart`) back a bespoke Starforged sheet (`lib/features/starforged_sheet.dart`, rendered when `Character.starforged` is set); see `docs/superpowers/specs/2026-06-17-starforged-character-sheet-design.md`. Each sheet pins its own asset ruleset (Ironsworn→classic, Starforged→starforged).

- [ ] **Step 5: Commit**

```bash
git add test/ruleset_assets_test.dart CLAUDE.md
git commit -m "test(starforged): real ruleset_starforged.json parse + docs"
```

---

## Self-Review (completed during planning)

**Spec coverage:**
- Separate `StarforgedSheet` + `Character.starforged` → Tasks 2, 3. ✓
- Shared widgets extracted + Ironsworn refactored + assetRid fix → Task 1. ✓
- Impacts (kStarforgedImpacts) + momentum-from-impacts → Tasks 2, 5. ✓
- 3 legacy tracks → Tasks 2, 5. ✓
- Vows + Connections → Task 6. ✓
- Assets from SF datasworn (pinned 'starforged') → Task 7. ✓
- 3-way create chooser + addStarforged + render branch (starforged-first) → Tasks 4, 5. ✓
- No schema bump → Character.toJson additive (Task 3); export rides existing path. ✓
- Testing incl. real-data 87-asset parse + rootBundle-free widget tests → Tasks 5-8. ✓
- Sundered Isles deferred (seam only). ✓

**Type consistency:** `StarforgedSheet.copyWith`/`maybeFromJson` clamp identically; shared widgets (`statStepper`/`meterStepper`/`intStepper`/`momentumRow`/`toggleChips`/`progressTrackRow`/`addProgressTrackDialog`/`assetCard`/`addAssetDialog`/`renameDialog`/`sheetSection`) defined in Task 1 and consumed by Tasks 1, 5-7 with matching signatures. `addStarforged` defined Task 4, called Task 5. `Character.starforged`/`clearStarforged` defined Task 3, used Tasks 4-5. Keys: `sf-` prefix for Starforged, `iw-` preserved for Ironsworn; `vow-name`/`conn-name`/`pick-asset-<id>` shared across dialogs (one dialog on screen at a time).

**Placeholder scan:** none — every code step has complete code.

**Out of scope (unchanged):** Sundered Isles, auto-XP-from-legacy, beyond-10 legacy, asset/companion meters + inputs, guided wizard, D&D/Shadowdark, LLM-rules.
