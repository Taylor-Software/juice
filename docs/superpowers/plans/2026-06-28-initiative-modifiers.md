# Initiative Modifiers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use `- [ ]` checkboxes.

**Goal:** Per-combatant initiative modifier — `Roll all init` rolls `d20 + mod`, ties break by mod, edited by tapping the encounter row's init avatar.

**Architecture:** Add `int initMod` to `Combatant`; make `rollInitiativeForAll` mod-aware + tie-breaking; tap the init `CircleAvatar` → `_InitDialog`. No new persistence (rides `juice.encounter.v1`).

**Tech Stack:** Flutter, flutter_riverpod, Dart. Prefix flutter with `export PATH="$HOME/development/flutter/bin:$PATH"`. `dart format` runs on edits.

---

## Verified anchors

- `Combatant` (`models.dart:2757`): const ctor, `copyWith({initiative, track, tags, defeated, statBlock, clearStatBlock})`, `toJson`, `fromJson`. `initiative` is `int`.
- `rollInitiativeForAll({Dice? dice})` (`providers.dart:846`): rolls `d.dN(20)` for `initiative <= 0`, sorts desc, turnIndex 0. `Dice` from `engine/dice.dart` (`dN(int)`).
- Encounter row leading avatar (`encounter_screen.dart:176`): `CircleAvatar(child: Text('${c.initiative}'))`. Subtitle is a `Column` (HP row + tag `Wrap`). `updateCombatant(Combatant)` persists.
- Model test harness: `test/encounter_roll_init_test.dart` (ProviderContainer + mock prefs + `Dice(Random(1))`). Widget harness: `test/encounter_screen_test.dart` (`pump`/`_c`/`_enc`/`tileOf`).
- `fmtSigned(int)` exists in `lib/features/sheet_widgets.dart` (`+3`/`0`/`-1`).

---

## Task 1: Model + mod-aware roll

**Files:** Modify `lib/engine/models.dart`, `lib/state/providers.dart`; Test `test/encounter_roll_init_test.dart`.

- [ ] **Step 1: Add failing tests** to `test/encounter_roll_init_test.dart` (inside `main`):

```dart
  test('initMod round-trips and toJson omits zero', () {
    const c = Combatant(id: 'a', name: 'A', initiative: 5, initMod: 3);
    final j = c.toJson();
    expect(j['initMod'], 3);
    expect(Combatant.fromJson(j).initMod, 3);
    expect(const Combatant(id: 'b', name: 'B', initiative: 1).toJson()
        .containsKey('initMod'), false);
    expect(Combatant.fromJson({
      'id': 'b', 'name': 'B', 'initiative': 1,
      'track': null, 'tags': const [], 'defeated': false,
    }).initMod, 0);
  });

  test('rollInitiativeForAll adds initMod to unset rolls + breaks ties by mod',
      () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(encounterProvider.notifier);
    await c.read(encounterProvider.future);
    // 'hi' has mod +10 so its d20+10 beats 'lo' (d20+0); also verifies add.
    await n.addCombatant(const Combatant(
        id: 'lo', name: 'Lo', initiative: 0, initMod: 0,
        track: CharTrack(label: 'HP', current: 5, max: 5)));
    await n.addCombatant(const Combatant(
        id: 'hi', name: 'Hi', initiative: 0, initMod: 10,
        track: CharTrack(label: 'HP', current: 5, max: 5)));
    await n.rollInitiativeForAll(dice: Dice(Random(1)));
    final s = await c.read(encounterProvider.future);
    expect(s.combatants.first.id, 'hi'); // +10 mod wins
    // 'hi' final initiative >= 11 (1..20 + 10)
    expect(s.combatants.firstWhere((x) => x.id == 'hi').initiative,
        greaterThanOrEqualTo(11));
  });

  test('rollInitiativeForAll tie-break: equal final initiative, higher mod first',
      () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(encounterProvider.notifier);
    await c.read(encounterProvider.future);
    // Both typed to the same initiative (>0 so not rolled); higher mod sorts first.
    await n.addCombatant(const Combatant(id: 'x', name: 'X', initiative: 12, initMod: 1));
    await n.addCombatant(const Combatant(id: 'y', name: 'Y', initiative: 12, initMod: 5));
    await n.rollInitiativeForAll(dice: Dice(Random(1)));
    final s = await c.read(encounterProvider.future);
    expect(s.combatants.first.id, 'y');
  });
```

- [ ] **Step 2: Run** `export PATH="$HOME/development/flutter/bin:$PATH" && flutter test test/encounter_roll_init_test.dart` — FAIL (no `initMod`).

- [ ] **Step 3: Add `initMod` to `Combatant`** (`lib/engine/models.dart`):
  - constructor: after `this.statBlock,` add `this.initMod = 0,`
  - field: after `final StatBlock? statBlock;` add `final int initMod;`
  - copyWith: add param `int? initMod,` and in the body `initMod: initMod ?? this.initMod,`
  - toJson: after the `statBlock` line add `if (initMod != 0) 'initMod': initMod,`
  - fromJson: after the `statBlock:` line add `initMod: (j['initMod'] as int?) ?? 0,`

- [ ] **Step 4: Make `rollInitiativeForAll` mod-aware** (`lib/state/providers.dart:846`), replace the `rolled` build + sort:
```dart
    final rolled = [
      for (final c in s.combatants)
        c.initiative <= 0
            ? c.copyWith(initiative: d.dN(20) + c.initMod)
            : c,
    ]..sort((a, b) {
        final byInit = b.initiative.compareTo(a.initiative);
        return byInit != 0 ? byInit : b.initMod.compareTo(a.initMod);
      });
```

- [ ] **Step 5: Run** `flutter test test/encounter_roll_init_test.dart` — PASS. `flutter analyze lib/engine/models.dart lib/state/providers.dart` — clean.

- [ ] **Step 6: Commit**
```bash
git add lib/engine/models.dart lib/state/providers.dart test/encounter_roll_init_test.dart
git commit -m "feat(encounter): per-combatant initMod + mod-aware roll-init"
```

---

## Task 2: Encounter edit dialog + row display

**Files:** Modify `lib/features/encounter_screen.dart`; Test `test/encounter_screen_test.dart`.

- [ ] **Step 1: Add a failing widget test** to `test/encounter_screen_test.dart`:

```dart
  testWidgets('tap init avatar edits initiative + mod; mod shows on row',
      (tester) async {
    final c = await pump(tester,
        encounterJson: _enc([
          _c('g', 'Goblin', 12, track: {'label': 'HP', 'current': 7, 'max': 7}),
        ]));
    expect(find.byKey(const Key('enc-initmod-g')), findsNothing); // mod 0
    await tester.tap(find.byKey(const Key('enc-init-g')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('init-dialog-value')), '18');
    await tester.enterText(find.byKey(const Key('init-dialog-mod')), '2');
    await tester.tap(find.byKey(const Key('init-dialog-save')));
    await tester.pumpAndSettle();
    final cm = (await c.read(encounterProvider.future)).combatants.single;
    expect(cm.initiative, 18);
    expect(cm.initMod, 2);
    expect(find.byKey(const Key('enc-initmod-g')), findsOneWidget);
  });
```

- [ ] **Step 2: Run** `flutter test test/encounter_screen_test.dart -n "init avatar"` — FAIL.

- [ ] **Step 3: Make the avatar tappable** — in `_row`, wrap the `leading: CircleAvatar(...)` in an `InkWell` (CircleAvatar already shows `Text('${c.initiative}')`):
```dart
        leading: InkWell(
          key: Key('enc-init-${c.id}'),
          onTap: () => _editInit(context, ref, c),
          child: CircleAvatar(
            backgroundColor: c.defeated
                ? theme.colorScheme.surfaceContainerHighest
                : (isTurn ? theme.colorScheme.primaryContainer : null),
            foregroundColor: c.defeated
                ? theme.colorScheme.onSurfaceVariant
                : (isTurn ? theme.colorScheme.onPrimaryContainer : null),
            child: Text('${c.initiative}'),
          ),
        ),
```

- [ ] **Step 4: Add the mod marker** to the subtitle `Column` (`_row`). At the top of the subtitle `children: [...]` (before the HP row), add:
```dart
            if (c.initMod != 0)
              Text('init ${c.initMod >= 0 ? '+' : ''}${c.initMod}',
                  key: Key('enc-initmod-${c.id}'),
                  style: theme.textTheme.bodySmall),
```

- [ ] **Step 5: Add `_editInit` + `_InitDialog`** to `encounter_screen.dart`. Method on `EncounterScreen`:
```dart
  Future<void> _editInit(
      BuildContext context, WidgetRef ref, Combatant c) async {
    final result = await showDialog<({int initiative, int mod})>(
      context: context,
      builder: (_) => _InitDialog(initiative: c.initiative, mod: c.initMod),
    );
    if (result == null) return;
    await ref.read(encounterProvider.notifier).updateCombatant(
        c.copyWith(initiative: result.initiative, initMod: result.mod));
  }
```
Append the dialog at the end of the file:
```dart
class _InitDialog extends StatefulWidget {
  const _InitDialog({required this.initiative, required this.mod});
  final int initiative;
  final int mod;
  @override
  State<_InitDialog> createState() => _InitDialogState();
}

class _InitDialogState extends State<_InitDialog> {
  late final TextEditingController _v =
      TextEditingController(text: '${widget.initiative}');
  late final TextEditingController _m =
      TextEditingController(text: widget.mod == 0 ? '' : '${widget.mod}');

  @override
  void dispose() {
    _v.dispose();
    _m.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Initiative'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          key: const Key('init-dialog-value'),
          controller: _v,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Initiative'),
        ),
        TextField(
          key: const Key('init-dialog-mod'),
          controller: _m,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Modifier'),
        ),
      ]),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('init-dialog-save'),
          onPressed: () => Navigator.pop(context, (
            initiative: int.tryParse(_v.text.trim()) ?? widget.initiative,
            mod: int.tryParse(_m.text.trim()) ?? 0,
          )),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
```

- [ ] **Step 6: Run** the whole file `flutter test test/encounter_screen_test.dart` — PASS. `flutter analyze lib/features/encounter_screen.dart` — clean.

- [ ] **Step 7: Commit**
```bash
git add lib/features/encounter_screen.dart test/encounter_screen_test.dart
git commit -m "feat(encounter): tap init avatar to edit initiative + mod"
```

---

## Task 3: Full verify + docs

**Files:** Modify `CLAUDE.md`.

- [ ] **Step 1: Full verify** — `export PATH="$HOME/development/flutter/bin:$PATH" && flutter analyze && flutter test`. Expect clean + all pass; report count. `dart fix --apply` any new-test lints.

- [ ] **Step 2: Update `CLAUDE.md`** — append to the combatant stat-blocks bullet:
```markdown
  Per-combatant **initiative modifiers** (`Combatant.initMod`): tap the encounter
  row's init avatar (`enc-init-<id>`) → `_InitDialog` sets initiative + mod;
  `rollInitiativeForAll` rolls `d20 + initMod` for unset combatants and tie-breaks
  by mod. See `docs/superpowers/specs/2026-06-28-initiative-modifiers-design.md`.
```

- [ ] **Step 3: Commit**
```bash
git add CLAUDE.md
git commit -m "docs(encounter): note initiative modifiers"
```

---

## Self-review notes

- **Spec coverage:** model+roll (T1), edit dialog + row marker (T2), verify+docs (T3). Covered.
- **Naming:** `Combatant.initMod`; keys `enc-init-<id>` / `enc-initmod-<id>` / `init-dialog-value` / `init-dialog-mod` / `init-dialog-save`.
- **Additive:** `initMod` is a new optional ctor param (default 0) — existing `Combatant(...)` + `copyWith` callers unaffected. No new persistence.
- **Loose-constraints:** `_InitDialog` uses plain TextFields in a `Column` (bounded by AlertDialog) + AlertDialog actions — no Wrap, no Material button beside a flex sibling. Safe.
