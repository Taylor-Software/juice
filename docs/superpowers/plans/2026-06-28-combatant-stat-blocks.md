# Combatant Stat Blocks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give each encounter combatant an optional, user-authored stat block (AC, attacks, saves, speed, notes) — edited on the Encounter screen, glanced at on the Run-screen.

**Architecture:** A lean `StatBlock` + `Attack` value class on a nullable `Combatant.statBlock`; a shared read-only `StatBlockView` widget; a `_StatBlockDialog` editor on the Encounter screen; a tap-to-glance dialog on the Run-screen initiative panel. Facts-only — the GM types everything; no parser, no vendored content, no new persistence key.

**Tech Stack:** Flutter, flutter_riverpod, Dart. Prefix flutter with `export PATH="$HOME/development/flutter/bin:$PATH"`. `dart format` runs on `.dart` edits.

---

## Verified anchors (recon)

- `Combatant` (`lib/engine/models.dart:2757`): `{id, name, characterId?, initiative, track CharTrack?, tags, defeated}`; `copyWith({initiative, track, tags, defeated})` (uses `x ?? this.x`); `toJson`; `fromJson`. `EncounterNotifier.updateCombatant(Combatant)` replaces by id (`providers.dart`).
- `EncounterState.copyWith` uses a `clearLocationRef` bool to null-out a field — the precedent for a nullable copyWith param.
- Encounter row `_row` (`lib/features/encounter_screen.dart:100`): a `Card(key: ValueKey(c.id)) > ListTile` with `trailing: Row([defeat IconButton key 'enc-defeat-$i', delete IconButton])`. Subtitle has HP row + a `Wrap` of condition/tag chips. The add flow (`_addAdHoc`/`_addFromCharacters`) is separate; leave it unchanged.
- Encounter widget-test harness (`test/encounter_screen_test.dart`): `pump(tester, {encounterJson, charactersJson})`, `_c(id, name, init, {track, tags, ...})` JSON builder, `_enc([...])`, `tileOf(tester, id)`. Combatant JSON keys: `id/name/characterId/initiative/track/tags/defeated`.
- Run-screen `_InitiativePanel` (`lib/features/run_screen.dart`): builds a row per combatant (init avatar + name + `c.track` HP). Test harness `test/run_screen_test.dart`: `_pump(tester, data, _prefs(encounterJson: ...))`.
- Shared widgets live in `lib/features/sheet_widgets.dart` (imports `models.dart`).

## File structure

- **Modify** `lib/engine/models.dart` — add `Attack`, `StatBlock`; add `statBlock` to `Combatant`.
- **Create** `test/stat_block_test.dart` — model tests.
- **Modify** `lib/features/sheet_widgets.dart` — add read-only `StatBlockView`.
- **Modify** `lib/features/encounter_screen.dart` — row stat-block button + `_StatBlockDialog` + inline summary.
- **Modify** `test/encounter_screen_test.dart` — editor widget test.
- **Modify** `lib/features/run_screen.dart` — tap-to-glance on the initiative panel.
- **Modify** `test/run_screen_test.dart` — glance widget test.
- **Modify** `CLAUDE.md` — stat-block note.

---

## Task 1: Model — `Attack`, `StatBlock`, `Combatant.statBlock`

**Files:** Modify `lib/engine/models.dart`; Create `test/stat_block_test.dart`; Modify `test/encounter_test.dart` (round-trip).

- [ ] **Step 1: Write failing tests** — create `test/stat_block_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';

void main() {
  group('StatBlock / Attack', () {
    test('round-trips through JSON', () {
      const sb = StatBlock(
        ac: 14,
        attacks: [
          Attack(name: 'Shortbow', detail: '+4, 1d6+2'),
          Attack(name: 'Bite'),
        ],
        saves: 'Dex +2',
        speed: '30 ft',
        notes: 'Nimble Escape',
      );
      final back = StatBlock.maybeFromJson(sb.toJson())!;
      expect(back.ac, 14);
      expect(back.attacks.length, 2);
      expect(back.attacks.first.name, 'Shortbow');
      expect(back.attacks.first.detail, '+4, 1d6+2');
      expect(back.attacks[1].detail, ''); // omitted detail round-trips to ''
      expect(back.saves, 'Dex +2');
      expect(back.speed, '30 ft');
      expect(back.notes, 'Nimble Escape');
    });

    test('isEmpty true only when everything blank', () {
      expect(const StatBlock().isEmpty, true);
      expect(const StatBlock(ac: 12).isEmpty, false);
      expect(const StatBlock(attacks: [Attack(name: 'x')]).isEmpty, false);
      expect(const StatBlock(notes: 'x').isEmpty, false);
    });

    test('maybeFromJson tolerant: non-map -> null; bad attacks dropped', () {
      expect(StatBlock.maybeFromJson('nope'), isNull);
      final sb = StatBlock.maybeFromJson({
        'ac': 10,
        'attacks': [
          {'name': 'Claw'},
          {'detail': 'no name -> dropped'},
          'garbage',
        ],
      })!;
      expect(sb.ac, 10);
      expect(sb.attacks.length, 1);
      expect(sb.attacks.single.name, 'Claw');
    });

    test('toJson omits empty fields', () {
      expect(const StatBlock(ac: 12).toJson(), {'ac': 12});
      expect(const StatBlock().toJson(), <String, dynamic>{});
    });

    test('Combatant carries a statBlock through JSON', () {
      const c = Combatant(
        id: 'g', name: 'Goblin', initiative: 12,
        statBlock: StatBlock(ac: 13, attacks: [Attack(name: 'Scimitar')]),
      );
      final back = Combatant.fromJson(c.toJson());
      expect(back.statBlock, isNotNull);
      expect(back.statBlock!.ac, 13);
      expect(back.statBlock!.attacks.single.name, 'Scimitar');
    });

    test('Combatant without a statBlock round-trips to null (legacy)', () {
      const c = Combatant(id: 'g', name: 'Goblin', initiative: 12);
      expect(Combatant.fromJson(c.toJson()).statBlock, isNull);
      // legacy JSON with no statBlock key:
      final legacy = Combatant.fromJson({
        'id': 'g', 'name': 'Goblin', 'initiative': 12,
        'track': null, 'tags': const [], 'defeated': false,
      });
      expect(legacy.statBlock, isNull);
    });

    test('copyWith sets and clears statBlock', () {
      const c = Combatant(id: 'g', name: 'G', initiative: 1);
      final withSb = c.copyWith(statBlock: const StatBlock(ac: 12));
      expect(withSb.statBlock!.ac, 12);
      expect(withSb.copyWith(clearStatBlock: true).statBlock, isNull);
      // a plain copyWith preserves it:
      expect(withSb.copyWith(defeated: true).statBlock!.ac, 12);
    });
  });
}
```

- [ ] **Step 2: Run** `export PATH="$HOME/development/flutter/bin:$PATH" && flutter test test/stat_block_test.dart` — FAIL (undefined `Attack`/`StatBlock`/`statBlock`).

- [ ] **Step 3: Add `Attack` + `StatBlock`** to `lib/engine/models.dart` (immediately above `class Combatant {`):

```dart
/// One attack line on a combatant stat block: a name plus freeform [detail]
/// (e.g. "+4, 1d6+2 slashing"). Display-only — no expression parsing.
class Attack {
  const Attack({required this.name, this.detail = ''});
  final String name;
  final String detail;

  Attack copyWith({String? name, String? detail}) =>
      Attack(name: name ?? this.name, detail: detail ?? this.detail);

  Map<String, dynamic> toJson() =>
      {'name': name, if (detail.isNotEmpty) 'detail': detail};

  factory Attack.fromJson(dynamic j) => j is Map
      ? Attack(
          name: (j['name'] as String?) ?? '',
          detail: (j['detail'] as String?) ?? '')
      : const Attack(name: '');
}

/// A combatant's user-authored stat block. Facts-only; the GM types everything.
/// HP is NOT here — it lives on the combatant's track / linked character.
class StatBlock {
  const StatBlock({
    this.ac = 0,
    this.attacks = const [],
    this.saves = '',
    this.speed = '',
    this.notes = '',
  });
  final int ac;
  final List<Attack> attacks;
  final String saves, speed, notes;

  bool get isEmpty =>
      ac == 0 &&
      attacks.isEmpty &&
      saves.isEmpty &&
      speed.isEmpty &&
      notes.isEmpty;

  StatBlock copyWith({
    int? ac,
    List<Attack>? attacks,
    String? saves,
    String? speed,
    String? notes,
  }) =>
      StatBlock(
        ac: ac ?? this.ac,
        attacks: attacks ?? this.attacks,
        saves: saves ?? this.saves,
        speed: speed ?? this.speed,
        notes: notes ?? this.notes,
      );

  Map<String, dynamic> toJson() => {
        if (ac != 0) 'ac': ac,
        if (attacks.isNotEmpty)
          'attacks': attacks.map((a) => a.toJson()).toList(),
        if (saves.isNotEmpty) 'saves': saves,
        if (speed.isNotEmpty) 'speed': speed,
        if (notes.isNotEmpty) 'notes': notes,
      };

  /// Tolerant: non-map -> null; attack entries without a name are dropped.
  static StatBlock? maybeFromJson(dynamic j) {
    if (j is! Map) return null;
    return StatBlock(
      ac: (j['ac'] as num?)?.toInt() ?? 0,
      attacks: ((j['attacks'] as List?) ?? const [])
          .map(Attack.fromJson)
          .where((a) => a.name.isNotEmpty)
          .toList(),
      saves: (j['saves'] as String?) ?? '',
      speed: (j['speed'] as String?) ?? '',
      notes: (j['notes'] as String?) ?? '',
    );
  }
}
```

- [ ] **Step 4: Thread `statBlock` into `Combatant`** (`lib/engine/models.dart`, the class at ~2757). Add the field + constructor param:
```dart
    this.tags = const [],
    this.defeated = false,
    this.statBlock,
  });
```
```dart
  final bool defeated;
  final StatBlock? statBlock;
```
Update `copyWith` (add the param + a clear flag, mirroring `EncounterState.clearLocationRef`):
```dart
  Combatant copyWith({
    int? initiative,
    CharTrack? track,
    List<String>? tags,
    bool? defeated,
    StatBlock? statBlock,
    bool clearStatBlock = false,
  }) =>
      Combatant(
        id: id,
        name: name,
        characterId: characterId,
        initiative: initiative ?? this.initiative,
        track: track ?? this.track,
        tags: tags ?? this.tags,
        defeated: defeated ?? this.defeated,
        statBlock: clearStatBlock ? null : (statBlock ?? this.statBlock),
      );
```
Update `toJson` (add, only when present + non-empty):
```dart
        'defeated': defeated,
        if (statBlock != null && !statBlock!.isEmpty)
          'statBlock': statBlock!.toJson(),
      };
```
Update `fromJson` (add, tolerant):
```dart
        defeated: (j['defeated'] as bool?) ?? false,
        statBlock: StatBlock.maybeFromJson(j['statBlock']),
      );
```

- [ ] **Step 5: Add a Combatant round-trip assertion** to `test/encounter_test.dart` — find an existing combatant round-trip / persistence test and confirm it still passes; no new test needed there (covered by stat_block_test). If `encounter_test.dart` has a "round-trips" model test, leave as-is.

- [ ] **Step 6: Run** `flutter test test/stat_block_test.dart test/encounter_test.dart` — PASS. `flutter analyze lib/engine/models.dart` — clean.

- [ ] **Step 7: Commit**
```bash
git add lib/engine/models.dart test/stat_block_test.dart
git commit -m "feat(encounter): StatBlock/Attack model on Combatant"
```

---

## Task 2: Shared read-only `StatBlockView`

**Files:** Modify `lib/features/sheet_widgets.dart`; Test `test/stat_block_test.dart` (widget pump).

- [ ] **Step 1: Add a failing widget test** to `test/stat_block_test.dart` (add imports `package:flutter/material.dart` + `package:flutter_test/flutter_test.dart` (already) + `package:juice_oracle/features/sheet_widgets.dart`; wrap in `MaterialApp`):

```dart
  testWidgets('StatBlockView renders AC, attacks, saves/speed/notes', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: StatBlockView(
          block: StatBlock(
            ac: 14,
            attacks: [Attack(name: 'Scimitar', detail: '+4, 1d6+2')],
            saves: 'Dex +2',
            speed: '30 ft',
            notes: 'Nimble Escape',
          ),
          curHp: 7,
          maxHp: 7,
        ),
      ),
    ));
    expect(find.textContaining('AC 14'), findsOneWidget);
    expect(find.textContaining('7/7'), findsOneWidget);
    expect(find.textContaining('30 ft'), findsOneWidget);
    expect(find.text('Scimitar'), findsOneWidget);
    expect(find.textContaining('+4, 1d6+2'), findsOneWidget);
    expect(find.textContaining('Dex +2'), findsOneWidget);
    expect(find.textContaining('Nimble Escape'), findsOneWidget);
  });

  testWidgets('StatBlockView omits empty sections', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: StatBlockView(block: StatBlock(ac: 12))),
    ));
    expect(find.textContaining('AC 12'), findsOneWidget);
    expect(find.text('SAVES'), findsNothing);
    expect(find.text('ATTACKS'), findsNothing);
  });
```
Put these two `testWidgets` inside a new `group('StatBlockView', () { ... })` in `main()`.

- [ ] **Step 2: Run** `flutter test test/stat_block_test.dart -n StatBlockView` — FAIL (undefined `StatBlockView`).

- [ ] **Step 3: Add `StatBlockView`** to `lib/features/sheet_widgets.dart` (append; it already imports `../engine/models.dart` — confirm and add if missing):

```dart
/// Read-only render of a combatant [StatBlock]: AC / HP / speed chips, an
/// attacks list, and saves / notes lines. Empty sections are omitted. Shared by
/// the encounter screen (inline) and the run-screen (glance dialog).
class StatBlockView extends StatelessWidget {
  const StatBlockView({super.key, required this.block, this.curHp, this.maxHp});
  final StatBlock block;
  final int? curHp;
  final int? maxHp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget chip(String text) => Chip(
          label: Text(text),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        );
    Widget labeled(String label, String value) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 56,
              child: Text(label,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.outline)),
            ),
            Expanded(child: Text(value, style: theme.textTheme.bodySmall)),
          ]),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(spacing: 6, runSpacing: 6, children: [
          if (block.ac != 0) chip('AC ${block.ac}'),
          if (curHp != null) chip('$curHp/$maxHp'),
          if (block.speed.isNotEmpty) chip(block.speed),
        ]),
        if (block.attacks.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('ATTACKS',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.outline)),
          for (final a in block.attacks)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text.rich(TextSpan(children: [
                TextSpan(
                    text: a.name,
                    style: const TextStyle(fontWeight: FontWeight.w500)),
                if (a.detail.isNotEmpty)
                  TextSpan(
                      text: ' — ${a.detail}',
                      style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
              ])),
            ),
        ],
        if (block.saves.isNotEmpty) labeled('SAVES', block.saves),
        if (block.notes.isNotEmpty) labeled('NOTES', block.notes),
      ],
    );
  }
}
```

- [ ] **Step 4: Run** `flutter test test/stat_block_test.dart` — PASS. `flutter analyze lib/features/sheet_widgets.dart` — clean.

- [ ] **Step 5: Commit**
```bash
git add lib/features/sheet_widgets.dart test/stat_block_test.dart
git commit -m "feat(encounter): shared read-only StatBlockView"
```

---

## Task 3: Encounter screen — editor + row affordance

**Files:** Modify `lib/features/encounter_screen.dart`; Test `test/encounter_screen_test.dart`.

- [ ] **Step 1: Add a failing widget test** to `test/encounter_screen_test.dart` (uses the file's `pump`/`_c`/`_enc`):

```dart
  testWidgets('stat-block dialog sets AC + an attack and persists', (tester) async {
    final c = await pump(tester,
        encounterJson: _enc([
          _c('g', 'Goblin', 12, track: {'label': 'HP', 'current': 7, 'max': 7}),
        ]));
    await tester.tap(find.byKey(const Key('enc-statblock-g')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('statblock-ac')), '13');
    await tester.tap(find.byKey(const Key('statblock-add-attack')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('statblock-attack-name-0')), 'Scimitar');
    await tester.enterText(
        find.byKey(const Key('statblock-attack-detail-0')), '+4, 1d6+2');
    await tester.tap(find.byKey(const Key('statblock-save')));
    await tester.pumpAndSettle();

    final sb = (await c.read(encounterProvider.future))
        .combatants.single.statBlock!;
    expect(sb.ac, 13);
    expect(sb.attacks.single.name, 'Scimitar');
    expect(sb.attacks.single.detail, '+4, 1d6+2');
  });

  testWidgets('saving an empty stat block clears it to null', (tester) async {
    final c = await pump(tester,
        encounterJson: _enc([
          _c('g', 'Goblin', 12, track: {'label': 'HP', 'current': 7, 'max': 7}),
        ]));
    await tester.tap(find.byKey(const Key('enc-statblock-g')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('statblock-save')));
    await tester.pumpAndSettle();
    expect((await c.read(encounterProvider.future)).combatants.single.statBlock,
        isNull);
  });
```

- [ ] **Step 2: Run** `flutter test test/encounter_screen_test.dart -n stat-block` — FAIL (no `enc-statblock-g`).

- [ ] **Step 3: Add the row button** in `_row`'s `trailing: Row(...)` (before the `enc-defeat-$i` button), in `lib/features/encounter_screen.dart`:
```dart
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: Key('enc-statblock-${c.id}'),
              icon: Icon(
                Icons.shield_outlined,
                color: (c.statBlock != null && !c.statBlock!.isEmpty)
                    ? theme.colorScheme.primary
                    : null,
              ),
              tooltip: 'Stat block',
              onPressed: () => _editStatBlock(context, ref, c),
            ),
            IconButton(
              key: Key('enc-defeat-$i'),
```
(Leave the rest of the trailing Row as-is.)

- [ ] **Step 4: Add `_editStatBlock` + `_StatBlockDialog`** to `encounter_screen.dart`. Add the import `import 'sheet_widgets.dart';` only if `StatBlockView` is used here (the inline summary — optional; the dialog editor doesn't need it, so skip the import unless you add the summary). Method:
```dart
  Future<void> _editStatBlock(
      BuildContext context, WidgetRef ref, Combatant c) async {
    final result = await showDialog<StatBlock>(
      context: context,
      builder: (_) => _StatBlockDialog(initial: c.statBlock),
    );
    if (result == null) return; // dialog cancelled
    final notifier = ref.read(encounterProvider.notifier);
    if (result.isEmpty) {
      await notifier.updateCombatant(c.copyWith(clearStatBlock: true));
    } else {
      await notifier.updateCombatant(c.copyWith(statBlock: result));
    }
  }
```
Append the dialog widget at the end of the file:
```dart
class _StatBlockDialog extends StatefulWidget {
  const _StatBlockDialog({this.initial});
  final StatBlock? initial;
  @override
  State<_StatBlockDialog> createState() => _StatBlockDialogState();
}

class _StatBlockDialogState extends State<_StatBlockDialog> {
  late final TextEditingController _ac =
      TextEditingController(text: (widget.initial?.ac ?? 0) == 0 ? '' : '${widget.initial!.ac}');
  late final TextEditingController _saves =
      TextEditingController(text: widget.initial?.saves ?? '');
  late final TextEditingController _speed =
      TextEditingController(text: widget.initial?.speed ?? '');
  late final TextEditingController _notes =
      TextEditingController(text: widget.initial?.notes ?? '');
  // Each attack = a (name, detail) controller pair.
  late final List<(TextEditingController, TextEditingController)> _attacks = [
    for (final a in widget.initial?.attacks ?? const <Attack>[])
      (TextEditingController(text: a.name), TextEditingController(text: a.detail)),
  ];

  @override
  void dispose() {
    _ac.dispose();
    _saves.dispose();
    _speed.dispose();
    _notes.dispose();
    for (final (n, d) in _attacks) {
      n.dispose();
      d.dispose();
    }
    super.dispose();
  }

  StatBlock _build() => StatBlock(
        ac: int.tryParse(_ac.text.trim()) ?? 0,
        attacks: [
          for (final (n, d) in _attacks)
            if (n.text.trim().isNotEmpty)
              Attack(name: n.text.trim(), detail: d.text.trim()),
        ],
        saves: _saves.text.trim(),
        speed: _speed.text.trim(),
        notes: _notes.text.trim(),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Stat block'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            key: const Key('statblock-ac'),
            controller: _ac,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'AC'),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Attacks', style: Theme.of(context).textTheme.labelLarge),
          ),
          for (var i = 0; i < _attacks.length; i++)
            Row(children: [
              Expanded(
                child: TextField(
                  key: Key('statblock-attack-name-$i'),
                  controller: _attacks[i].$1,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 2,
                child: TextField(
                  key: Key('statblock-attack-detail-$i'),
                  controller: _attacks[i].$2,
                  decoration: const InputDecoration(labelText: 'Detail'),
                ),
              ),
              IconButton(
                key: Key('statblock-attack-remove-$i'),
                icon: const Icon(Icons.close),
                onPressed: () {
                  setState(() {
                    final (n, d) = _attacks.removeAt(i);
                    n.dispose();
                    d.dispose();
                  });
                },
              ),
            ]),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('statblock-add-attack'),
              icon: const Icon(Icons.add),
              label: const Text('Add attack'),
              onPressed: () => setState(() => _attacks
                  .add((TextEditingController(), TextEditingController()))),
            ),
          ),
          TextField(
            key: const Key('statblock-saves'),
            controller: _saves,
            decoration: const InputDecoration(labelText: 'Saves'),
          ),
          TextField(
            key: const Key('statblock-speed'),
            controller: _speed,
            decoration: const InputDecoration(labelText: 'Speed'),
          ),
          TextField(
            key: const Key('statblock-notes'),
            controller: _notes,
            decoration: const InputDecoration(labelText: 'Notes'),
            maxLines: 3,
          ),
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('statblock-save'),
          onPressed: () => Navigator.pop(context, _build()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
```
NOTE: the test taps `statblock-attack-remove-$i` is not exercised, but it's wired. Cancel returns `null` (no change); Save returns the built block (empty → `_editStatBlock` clears).

- [ ] **Step 5: Run** the WHOLE file `flutter test test/encounter_screen_test.dart` — PASS. `flutter analyze lib/features/encounter_screen.dart` — clean.

- [ ] **Step 6: Commit**
```bash
git add lib/features/encounter_screen.dart test/encounter_screen_test.dart
git commit -m "feat(encounter): per-combatant stat-block editor"
```

---

## Task 4: Run-screen glance

**Files:** Modify `lib/features/run_screen.dart`; Test `test/run_screen_test.dart`.

- [ ] **Step 1: Add a failing test** to `test/run_screen_test.dart`:

```dart
  testWidgets('initiative: tapping a combatant with a stat block shows it',
      (tester) async {
    const enc =
        '{"combatants":[{"id":"g","name":"Goblin","initiative":12,"track":{"label":"HP","current":7,"max":7},"tags":[],"defeated":false,"statBlock":{"ac":13,"attacks":[{"name":"Scimitar","detail":"+4"}]}}],"turnIndex":0,"round":1}';
    await _pump(tester, data, _prefs(encounterJson: enc));
    await tester.tap(find.byKey(const Key('run-init-row-g')));
    await tester.pumpAndSettle();
    expect(find.textContaining('AC 13'), findsOneWidget);
    expect(find.text('Scimitar'), findsOneWidget);
  });

  testWidgets('initiative: a combatant without a stat block does not open one',
      (tester) async {
    const enc =
        '{"combatants":[{"id":"g","name":"Goblin","initiative":12,"track":{"label":"HP","current":7,"max":7},"tags":[],"defeated":false}],"turnIndex":0,"round":1}';
    await _pump(tester, data, _prefs(encounterJson: enc));
    await tester.tap(find.byKey(const Key('run-init-row-g')));
    await tester.pumpAndSettle();
    expect(find.textContaining('AC '), findsNothing); // no glance dialog
  });
```

- [ ] **Step 2: Run** `flutter test test/run_screen_test.dart -n "stat block"` — FAIL.

- [ ] **Step 3: Implement** — in `lib/features/run_screen.dart`, add `import 'sheet_widgets.dart';` (for `StatBlockView`). In `_InitiativePanel.build`, find where each combatant row widget is built (the `Padding > Row([...])` per combatant) and wrap that row in an `InkWell` with a key + tap that opens the glance when a block exists:
```dart
      rows.add(InkWell(
        key: Key('run-init-row-${c.id}'),
        onTap: (c.statBlock != null && !c.statBlock!.isEmpty)
            ? () => _showStatBlock(context, c)
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [ /* existing row children unchanged */ ]),
        ),
      ));
```
(Adapt to the exact existing row structure — wrap the existing per-combatant child, don't rebuild it.) Add the helper method to `_InitiativePanel`:
```dart
  void _showStatBlock(BuildContext context, Combatant c) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(c.name),
        content: SingleChildScrollView(
          child: StatBlockView(
            block: c.statBlock!,
            curHp: c.track?.current,
            maxHp: c.track?.max,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
```
(`_InitiativePanel` is a `ConsumerWidget`; `_showStatBlock` can be a method on it taking `context` + `c`. `Combatant` is already imported via `../engine/models.dart`.)

- [ ] **Step 4: Run** the whole `flutter test test/run_screen_test.dart` — PASS. `flutter analyze lib/features/run_screen.dart` — clean.

- [ ] **Step 5: Commit**
```bash
git add lib/features/run_screen.dart test/run_screen_test.dart
git commit -m "feat(run): tap a combatant to glance its stat block"
```

---

## Task 5: Full verify + docs

**Files:** Modify `CLAUDE.md`.

- [ ] **Step 1: Full verification:**
```bash
export PATH="$HOME/development/flutter/bin:$PATH"
flutter analyze
flutter test
```
Expect no analyze issues and all tests pass; report the count. If new test code trips `prefer_const` lints, `dart fix --apply test/stat_block_test.dart` then re-analyze.

- [ ] **Step 2: Update `CLAUDE.md`** — append to the GM Run-screen bullet (or add a sibling bullet near the encounter/run notes):
```markdown
- **Combatant stat blocks** (`StatBlock`/`Attack` in `models.dart`, a nullable
  `Combatant.statBlock`): user-authored AC + attacks (name + freeform detail) +
  saves/speed/notes (all freeform, facts-only, no parser — attacks are display
  text). Edited on the Encounter screen (`enc-statblock-<id>` →
  `_StatBlockDialog`), glanced read-only on the Run-screen initiative panel (tap
  `run-init-row-<id>` → `StatBlockView` dialog). Shared read-only render is
  `StatBlockView` (`sheet_widgets.dart`). Ephemeral on the combatant (gone on
  encounter reset); persisted inside the existing `juice.encounter.v1` key, no
  new key. Deferred: rollable attacks (needs a parser), reusable bestiary
  library (Tier-2.5). See
  `docs/superpowers/specs/2026-06-28-combatant-stat-blocks-design.md`.
```

- [ ] **Step 3: Commit**
```bash
git add CLAUDE.md
git commit -m "docs(encounter): note combatant stat blocks"
```

---

## Self-review notes

- **Spec coverage:** model + Combatant field (T1), shared view (T2), encounter editor + row affordance (T3), run-screen glance (T4), verify + docs (T5). All spec sections covered.
- **Naming:** `Attack {name, detail}`; `StatBlock {ac, attacks, saves, speed, notes}` + `isEmpty` + `maybeFromJson`; `Combatant.statBlock` + `copyWith({statBlock, clearStatBlock})`; `StatBlockView({block, curHp, maxHp})`; keys `enc-statblock-<id>` / `statblock-ac` / `statblock-add-attack` / `statblock-attack-name-$i` / `statblock-attack-detail-$i` / `statblock-attack-remove-$i` / `statblock-saves` / `statblock-speed` / `statblock-notes` / `statblock-save` / `run-init-row-<id>`.
- **Compile-order:** each task is independently green. T1 model is standalone; T2 adds a widget; T3/T4 consume them. The `Combatant` copyWith change is additive (new optional params) — existing `copyWith` callers are unaffected.
- **No new persistence / export:** `statBlock` rides the existing combatant JSON in `juice.encounter.v1`.
- **DRY:** one `StatBlockView` serves both surfaces. The encounter row's existing per-sheet HP chain is left untouched (out of scope; not my mess).
- **Deferred:** rollable attacks (parser), bestiary library, structured saves, templates/vendored content.
