# Nimble Character Sheet Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A facts-only pre-made **Nimble** character sheet — `NimbleSheet` model + `NimbleSheetView` — gated by an opt-in `nimble` system, mirroring the Shadowdark sheet.

**Architecture:** Authored mechanic-fact constants (`kNimbleStats`, `kNimbleClasses`) + a `NimbleSheet` data class on `Character.nimble`; a `NimbleSheetView` rendered when `Character.nimble` is set; registered as an opt-in system with a `system_primer` line and HP read-through.

**Tech Stack:** Dart, Flutter, flutter_riverpod, flutter_test. Mirrors `ShadowdarkSheet`/`ShadowdarkSheetView` (#75).

---

## Task 1: NimbleSheet model + Character.nimble + withHpDelta

**Files:** Modify `lib/engine/models.dart`; Test `test/nimble_sheet_test.dart` (new).

- [ ] **Step 1: Write the failing test** — create `test/nimble_sheet_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';

void main() {
  test('NimbleSheet round-trips + applies defaults/clamps', () {
    const s = NimbleSheet(
      stats: {'str': 2, 'dex': 1, 'int': 0, 'wis': -1},
      saveAdv: {'dex': 1},
      className: 'Hunter',
      ancestry: 'Elf',
      level: 3,
      hitDieSize: 8,
      maxHp: 20,
      currentHp: 14,
      wounds: 2,
      maxWounds: 6,
      speed: 6,
      gearSlotsUsed: 5,
      talents: 'Keen eye',
      notes: 'n',
    );
    final back = NimbleSheet.maybeFromJson(s.toJson())!;
    expect(back.className, 'Hunter');
    expect(back.stats['str'], 2);
    expect(back.saveAdv['dex'], 1);
    expect(back.currentHp, 14);
    expect(back.wounds, 2);
    expect(back.slotCap, 12); // 10 + str(2)
  });

  test('NimbleSheet tolerates junk + unknown class', () {
    final s = NimbleSheet.maybeFromJson({'className': 'Bogus', 'level': 99})!;
    expect(s.className, 'The Cheat'); // unknown -> default
    expect(s.level, 10); // clamped
    expect(NimbleSheet.maybeFromJson('nope'), isNull);
  });

  test('Character round-trips nimble + withHpDelta adjusts its pool', () {
    final c = Character(id: 'c1', name: 'Ari', nimble: const NimbleSheet(currentHp: 10, maxHp: 12));
    final back = Character.fromJson(c.toJson());
    expect(back.nimble, isNotNull);
    final hurt = c.withHpDelta(-4);
    expect(hurt.nimble!.currentHp, 6);
    final overheal = c.withHpDelta(99);
    expect(overheal.nimble!.currentHp, 12); // clamped to maxHp
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/nimble_sheet_test.dart`
Expected: FAIL — `NimbleSheet` undefined.

- [ ] **Step 3a: Add the constants** — in `lib/engine/models.dart`, near `kShadowdarkClasses`:

```dart
const kNimbleStats = <String>['str', 'dex', 'int', 'wis'];
const kNimbleClasses = <String>[
  'The Cheat', 'Commander', 'Hunter', 'Mage', 'Oathsworn',
  'Shadowmancer', 'Shepherd', 'Songweaver', 'Stormshifter', 'Zephyr',
];
```

- [ ] **Step 3b: Add the `NimbleSheet` class** — in `lib/engine/models.dart` (beside `ShadowdarkSheet`):

```dart
/// Facts-only Nimble sheet. Authored class/stat NAMES only (non-copyrightable);
/// all values are player-editable. Stats are MODIFIERS (small ± numbers).
class NimbleSheet {
  const NimbleSheet({
    this.stats = const {'str': 0, 'dex': 0, 'int': 0, 'wis': 0},
    this.saveAdv = const {},
    this.className = 'The Cheat',
    this.ancestry = '',
    this.level = 1,
    this.hitDieSize = 6,
    this.maxHp = 1,
    this.currentHp = 1,
    this.wounds = 0,
    this.maxWounds = 6,
    this.speed = 6,
    this.gearSlotsUsed = 0,
    this.talents = '',
    this.notes = '',
  });

  final Map<String, int> stats; // keys = kNimbleStats; values are modifiers
  final Map<String, int> saveAdv; // per stat: 1 adv / -1 dis / 0 none
  final String className, ancestry;
  final int level, hitDieSize, maxHp, currentHp, wounds, maxWounds, speed,
      gearSlotsUsed;
  final String talents, notes;

  int get slotCap => 10 + (stats['str'] ?? 0);

  NimbleSheet copyWith({
    Map<String, int>? stats,
    Map<String, int>? saveAdv,
    String? className,
    String? ancestry,
    int? level,
    int? hitDieSize,
    int? maxHp,
    int? currentHp,
    int? wounds,
    int? maxWounds,
    int? speed,
    int? gearSlotsUsed,
    String? talents,
    String? notes,
  }) {
    final st = stats ?? this.stats;
    final sv = saveAdv ?? this.saveAdv;
    final cls = className ?? this.className;
    return NimbleSheet(
      stats: {for (final k in kNimbleStats) k: (st[k] ?? 0).clamp(-9, 9)},
      saveAdv: {
        for (final k in kNimbleStats)
          if ((sv[k] ?? 0) != 0) k: (sv[k] ?? 0).clamp(-1, 1),
      },
      className: kNimbleClasses.contains(cls) ? cls : 'The Cheat',
      ancestry: ancestry ?? this.ancestry,
      level: (level ?? this.level).clamp(1, 10),
      hitDieSize: (hitDieSize ?? this.hitDieSize).clamp(1, 100),
      maxHp: (maxHp ?? this.maxHp).clamp(0, 1 << 20),
      currentHp: (currentHp ?? this.currentHp).clamp(0, 1 << 20),
      wounds: (wounds ?? this.wounds).clamp(0, 99),
      maxWounds: (maxWounds ?? this.maxWounds).clamp(1, 99),
      speed: (speed ?? this.speed).clamp(0, 99),
      gearSlotsUsed: (gearSlotsUsed ?? this.gearSlotsUsed).clamp(0, 999),
      talents: talents ?? this.talents,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() => {
        'stats': stats,
        if (saveAdv.isNotEmpty) 'saveAdv': saveAdv,
        'className': className,
        'ancestry': ancestry,
        'level': level,
        'hitDieSize': hitDieSize,
        'maxHp': maxHp,
        'currentHp': currentHp,
        'wounds': wounds,
        'maxWounds': maxWounds,
        'speed': speed,
        'gearSlotsUsed': gearSlotsUsed,
        'talents': talents,
        'notes': notes,
      };

  static NimbleSheet? maybeFromJson(Object? j) {
    if (j is! Map) return null;
    int i(String k, int d) => (j[k] as num?)?.toInt() ?? d;
    Map<String, int> intMap(String k) => {
          for (final e in ((j[k] as Map?) ?? const {}).entries)
            '${e.key}': (e.value as num?)?.toInt() ?? 0,
        };
    return const NimbleSheet().copyWith(
      stats: intMap('stats'),
      saveAdv: intMap('saveAdv'),
      className: j['className'] as String?,
      ancestry: j['ancestry'] as String?,
      level: i('level', 1),
      hitDieSize: i('hitDieSize', 6),
      maxHp: i('maxHp', 1),
      currentHp: i('currentHp', 1),
      wounds: i('wounds', 0),
      maxWounds: i('maxWounds', 6),
      speed: i('speed', 6),
      gearSlotsUsed: i('gearSlotsUsed', 0),
      talents: j['talents'] as String?,
      notes: j['notes'] as String?,
    );
  }
}
```

- [ ] **Step 3c: Wire `Character.nimble`** — in `class Character`:
  - ctor param `this.nimble,` + field `final NimbleSheet? nimble;` (beside `shadowdark`).
  - `copyWith`: add `NimbleSheet? nimble, bool clearNimble = false,` and `nimble: clearNimble ? null : (nimble ?? this.nimble),`.
  - `toJson`: `if (nimble != null) 'nimble': nimble!.toJson(),` (beside the shadowdark line).
  - `fromJson`: `nimble: NimbleSheet.maybeFromJson(j['nimble']),` (beside shadowdark).

- [ ] **Step 3d: `withHpDelta`** — in `Character.withHpDelta`, add BEFORE the `if (tracks.isNotEmpty)` fallback (after the shadowdark branch):

```dart
    if (nimble != null) {
      return copyWith(
          nimble: nimble!.copyWith(
              currentHp: (nimble!.currentHp + delta).clamp(0, nimble!.maxHp)));
    }
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/nimble_sheet_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/models.dart test/nimble_sheet_test.dart
git commit -m "feat(nimble): NimbleSheet model + Character.nimble + withHpDelta (facts-only)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 2: System registration + primer

**Files:** Modify `lib/engine/models.dart`, `lib/engine/system_primer.dart`, `lib/features/home_shell.dart`.

- [ ] **Step 1: Register the system label** — in `lib/engine/models.dart`, add to `kSystemLabels`: `'nimble': 'Nimble',`. Then find EVERY list that enumerates the opt-in sheet systems alongside `'shadowdark'` (e.g. the `formatSystems` `order` list and any known-systems / sheet-systems validation list) and add `'nimble'` beside `'shadowdark'`. Grep `'shadowdark'` in `models.dart` to find them all; `nimble` is NOT added to `kAllSystems`.

- [ ] **Step 2: System primer** — in `lib/engine/system_primer.dart`:
  - add to `kSystemPrimers`: 
    ```dart
    'nimble':
        'Nimble: fast, tactical 5e-compatible fantasy. Resolution: d20 + stat vs DC or armor; advantage/disadvantage; a wounds dying-track; slot inventory.',
    ```
  - in `resolveSystemPrimer`, add after the shadowdark line: `if (systems.contains('nimble')) return kSystemPrimers['nimble']!;`
  - in `resolveSystem`, add the matching `nimble` branch in the same priority slot.

- [ ] **Step 3: Opt-in toggle** — in `lib/features/home_shell.dart`, find the `sys-shadowdark` `CheckboxListTile`/toggle (in BOTH the new-campaign dialog AND the edit-systems dialog if separate) and add a sibling:

```dart
              CheckboxListTile(
                key: const Key('sys-nimble'),
                title: const Text('Nimble'),
                value: selected.contains('nimble'),
                onChanged: (v) => setState(() =>
                    v == true ? selected.add('nimble') : selected.remove('nimble')),
              ),
```

(Match the real surrounding toggle's shape — the state variable + add/remove pattern may differ; mirror `sys-shadowdark` exactly.)

- [ ] **Step 4: Verify**

Run: `flutter analyze` → expect no issues.
Run: `flutter test test/home_shell_test.dart` → expect PASS (extend later if it enumerates add-ons).

- [ ] **Step 5: Commit**

```bash
git add lib/engine/models.dart lib/engine/system_primer.dart lib/features/home_shell.dart
git commit -m "feat(nimble): register the nimble opt-in system + primer + toggle

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 3: NimbleSheetView + render + creation

**Files:** Create `lib/features/nimble_sheet.dart`; Modify `lib/features/tracker_screen.dart`; Test `test/nimble_sheet_ui_test.dart` (new).

- [ ] **Step 1: Write the failing widget test** — create `test/nimble_sheet_ui_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/features/nimble_sheet.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({
    'juice.sessions.v1':
        '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    'juice.characters.v1.default':
        '[{"id":"c1","name":"Ari","stats":[],"tracks":[],"tags":[],"nimble":{"className":"The Cheat","maxHp":10,"currentHp":10}}]',
  });
  final c = ProviderContainer();
  addTearDown(c.dispose);
  await c.read(charactersProvider.future);
  final ch = c.read(charactersProvider).value!.single;
  await tester.pumpWidget(ProviderScope(
    parent: c,
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: NimbleSheetView(character: ch, onBack: () {})),
    ),
  ));
  await tester.pumpAndSettle();
  return c;
}

void main() {
  testWidgets('renders + a stat stepper persists', (tester) async {
    final c = await _pump(tester);
    expect(find.byKey(const Key('nimble-sheet')), findsOneWidget);
    expect(find.text('The Cheat'), findsWidgets);
    await tester.tap(find.byKey(const Key('nimble-stat-str-plus')));
    await tester.pumpAndSettle();
    final s = c.read(charactersProvider).value!.single.nimble!;
    expect(s.stats['str'], 1);
  });

  testWidgets('wounds stepper persists', (tester) async {
    final c = await _pump(tester);
    await tester.tap(find.byKey(const Key('nimble-wounds-plus')));
    await tester.pumpAndSettle();
    expect(c.read(charactersProvider).value!.single.nimble!.wounds, 1);
  });
}
```

> NOTE: use the SAME `ProviderScope(parent:)` / pump shape the Shadowdark sheet
> test (`test/character_sheet_ui_test.dart` or the shadowdark test) uses — adapt
> if `parent:` isn't how those tests inject the container. The keys
> `nimble-stat-str-plus` / `nimble-wounds-plus` come from the `_stepper` below.

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/nimble_sheet_ui_test.dart`
Expected: FAIL — `NimbleSheetView` undefined.

- [ ] **Step 3: Create `lib/features/nimble_sheet.dart`** (mirrors `shadowdark_sheet.dart`):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../state/providers.dart';
import 'sheet_widgets.dart';

/// Facts-only Nimble sheet. Class/stat NAMES are authored; values are editable.
class NimbleSheetView extends ConsumerWidget {
  const NimbleSheetView(
      {super.key, required this.character, required this.onBack});
  final Character character;
  final VoidCallback onBack;

  NimbleSheet get _s => character.nimble!;
  void _save(WidgetRef ref, NimbleSheet next) => ref
      .read(charactersProvider.notifier)
      .replace(character.copyWith(nimble: next));

  Widget _stepper(String key, String label, int value,
          {required ValueChanged<int> onSet, int min = -9, int max = 999}) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$label '),
        IconButton(
          key: Key('$key-minus'),
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.remove),
          onPressed: value > min ? () => onSet(value - 1) : null,
        ),
        Text('$value'),
        IconButton(
          key: Key('$key-plus'),
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.add),
          onPressed: value < max ? () => onSet(value + 1) : null,
        ),
      ]);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final s = _s;
    return ListView(
      key: const Key('nimble-sheet'),
      padding: const EdgeInsets.all(12),
      children: [
        Row(children: [
          IconButton(
              key: const Key('sheet-back'),
              icon: const Icon(Icons.arrow_back),
              onPressed: onBack),
          Expanded(
              child: Text(character.name,
                  style: theme.textTheme.titleLarge,
                  overflow: TextOverflow.ellipsis)),
        ]),
        Text('Nimble', style: theme.textTheme.labelSmall),
        const SizedBox(height: 8),
        DropdownButton<String>(
          key: const Key('nimble-class'),
          isExpanded: true,
          value: kNimbleClasses.contains(s.className) ? s.className : kNimbleClasses.first,
          items: [
            for (final c in kNimbleClasses)
              DropdownMenuItem(value: c, child: Text(c)),
          ],
          onChanged: (v) => v == null ? null : _save(ref, s.copyWith(className: v)),
        ),
        TextFormField(
          key: const Key('nimble-ancestry'),
          initialValue: s.ancestry,
          decoration: const InputDecoration(labelText: 'Ancestry'),
          onChanged: (v) => _save(ref, s.copyWith(ancestry: v)),
        ),
        const SizedBox(height: 12),
        Text('Stats (modifiers) + saves', style: theme.textTheme.titleMedium),
        for (final k in kNimbleStats)
          Row(children: [
            SizedBox(width: 48, child: Text(k.toUpperCase())),
            _stepper('nimble-stat-$k', '', s.stats[k] ?? 0,
                min: -9, max: 9,
                onSet: (v) =>
                    _save(ref, s.copyWith(stats: {...s.stats, k: v}))),
            const Spacer(),
            // Save advantage: tap to cycle none -> adv(+) -> dis(-) -> none.
            TextButton(
              key: Key('nimble-save-$k'),
              onPressed: () {
                final cur = s.saveAdv[k] ?? 0;
                final next = cur == 0 ? 1 : (cur == 1 ? -1 : 0);
                _save(ref, s.copyWith(saveAdv: {...s.saveAdv, k: next}));
              },
              child: Text((s.saveAdv[k] ?? 0) == 0
                  ? 'save —'
                  : ((s.saveAdv[k] ?? 0) > 0 ? 'save +' : 'save –')),
            ),
          ]),
        const SizedBox(height: 12),
        Wrap(spacing: 16, runSpacing: 8, children: [
          _stepper('nimble-hp', 'HP', s.currentHp,
              min: 0, max: s.maxHp, onSet: (v) => _save(ref, s.copyWith(currentHp: v))),
          _stepper('nimble-maxhp', 'Max HP', s.maxHp,
              min: 0, onSet: (v) => _save(ref, s.copyWith(maxHp: v))),
          _stepper('nimble-wounds', 'Wounds', s.wounds,
              min: 0, max: s.maxWounds, onSet: (v) => _save(ref, s.copyWith(wounds: v))),
          _stepper('nimble-level', 'Level', s.level,
              min: 1, max: 10, onSet: (v) => _save(ref, s.copyWith(level: v))),
          _stepper('nimble-speed', 'Speed', s.speed,
              min: 0, onSet: (v) => _save(ref, s.copyWith(speed: v))),
          _stepper('nimble-hitdie', 'Hit Die d', s.hitDieSize,
              min: 1, onSet: (v) => _save(ref, s.copyWith(hitDieSize: v))),
        ]),
        const SizedBox(height: 8),
        _stepper('nimble-slots', 'Slots used (cap ${s.slotCap})',
            s.gearSlotsUsed,
            min: 0, onSet: (v) => _save(ref, s.copyWith(gearSlotsUsed: v))),
        const SizedBox(height: 12),
        conditionsSection(context, ref, character, 'nimble'),
        const SizedBox(height: 12),
        TextFormField(
          key: const Key('nimble-talents'),
          initialValue: s.talents,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Talents'),
          onChanged: (v) => _save(ref, s.copyWith(talents: v)),
        ),
        TextFormField(
          key: const Key('nimble-notes'),
          initialValue: s.notes,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Notes'),
          onChanged: (v) => _save(ref, s.copyWith(notes: v)),
        ),
      ],
    );
  }
}
```

> Confirm `conditionsSection(context, ref, character, String prefix)`'s real
> signature in `sheet_widgets.dart` (the Shadowdark sheet calls it with `'sd'`)
> and match it. If `NimbleSheetView`'s constructor needs a different shape than
> `{character, onBack}` to match how `tracker_screen` invokes the other sheets,
> match the Shadowdark/D&D view constructors exactly.

- [ ] **Step 4: Render branch** — in `lib/features/tracker_screen.dart`, beside `if (c.shadowdark != null) return ShadowdarkSheetView(...)` / the `c.dnd` branch, add:

```dart
              if (c.nimble != null) {
                return NimbleSheetView(character: c, onBack: <same onBack as the others>);
              }
```

(Match the exact `onBack`/argument shape the sibling `ShadowdarkSheetView(...)` call uses; add the import.)

- [ ] **Step 5: Sheet creation** — add a "New Nimble sheet" affordance gated on the `nimble` system, mirroring how a Shadowdark sheet is created (grep `ShadowdarkSheet.premade` / `shadowdark:` assignment in `tracker_screen.dart`). It sets `character.copyWith(nimble: const NimbleSheet())` (or a `NimbleSheet.premade()` factory if you add one). Gate its visibility on the active campaign's systems containing `'nimble'` (mirror the shadowdark-create gate).

- [ ] **Step 6: Run to verify**

Run: `flutter test test/nimble_sheet_ui_test.dart` → expect PASS.
Run: `flutter analyze` → expect `No issues found!`
Run: `flutter test` → expect All tests passed.

- [ ] **Step 7: Commit**

```bash
git add lib/features/nimble_sheet.dart lib/features/tracker_screen.dart test/nimble_sheet_ui_test.dart
git commit -m "feat(nimble): NimbleSheetView + roster render/creation

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 4: Encounter HP read-through + doc

**Files:** Modify `lib/features/encounter_screen.dart`, `CLAUDE.md`.

- [ ] **Step 1: Nimble HP read-through** — in `lib/features/encounter_screen.dart` (~line 122, where a linked combatant's HP resolves `dnd`/`shadowdark` pools), add a `nimble` branch mirroring the `shadowdark` one (read `linked.nimble!.currentHp`/`maxHp`). The party-effect/steppers already route through `Character.withHpDelta` (Task 1), so HP edits resolve the nimble pool automatically.

- [ ] **Step 2: Verify**

Run: `flutter analyze` → no issues.
Run: `flutter test test/encounter_screen_test.dart` → PASS.

- [ ] **Step 3: CLAUDE.md** — add a Nimble bullet near the Shadowdark sheet note:

```
- A facts-only **Nimble** sheet (`lib/features/nimble_sheet.dart`, rendered when
  `Character.nimble` is set; opt-in `nimble` system, NOT in `kAllSystems`)
  follows the Shadowdark facts-only approach: authored mechanic constants only
  (`kNimbleStats` = str/dex/int/wis modifiers, `kNimbleClasses` = the 10 classes),
  class freeform/editable values, with a signature **Wounds** dying-track stepper.
  **Licensing:** Nimble's 3rd-party license is OPEN + app-friendly (unlike
  Shadowdark), so a P2 with class-feature/spell text + pickers (under the Nimble
  3rd-Party Creator License + SRD-5.1/WotC attribution) is genuinely allowed
  later; P1 stays facts-only for consistency + speed. See
  `docs/superpowers/specs/2026-06-24-nimble-sheet-design.md`.
```

- [ ] **Step 4: Commit**

```bash
git add lib/features/encounter_screen.dart CLAUDE.md
git commit -m "feat(nimble): encounter HP read-through + CLAUDE.md note

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:**
- §1 model + constants (`kNimbleStats`/`kNimbleClasses`/`NimbleSheet`) → Task 1; `Character.nimble` + `withHpDelta` → Task 1. ✓
- §3 system registration (labels/lists/toggle) + §4 primer → Task 2. ✓
- §5 `NimbleSheetView` + §6 render/creation → Task 3. ✓
- §7 HP read-through → Task 4; doc → Task 4. ✓
- Testing: model round-trip + withHpDelta (Task 1), sheet widget (Task 3). ✓

**Type consistency:**
- `NimbleSheet{stats,saveAdv,className,ancestry,level,hitDieSize,maxHp,currentHp,wounds,maxWounds,speed,gearSlotsUsed,talents,notes}` + `slotCap` (Task 1) used by `NimbleSheetView` (Task 3) + `withHpDelta` (Task 1). ✓
- `Character.nimble` (Task 1) read in `NimbleSheetView._s`/render (Task 3) + encounter (Task 4). ✓
- Keys `nimble-sheet`/`nimble-class`/`nimble-stat-<k>-plus`/`nimble-wounds-plus`/etc. consistent between view (Task 3) + tests (Tasks 1/3). ✓
- `kNimbleClasses` first = `'The Cheat'` = the model default (Task 1) — the unknown-class fallback test + the dropdown default agree. ✓

**Placeholder scan:** No TBD/TODO. The NOTE callouts (match the real `conditionsSection` signature / sibling-view constructor / sheet-creation gate) are grounding guidance for sites that vary — each names the exact template to mirror.

**Risk note:** the widget-test pump shape (`ProviderScope(parent:)`) must match how the Shadowdark/character sheet tests inject the container — the implementer verifies against `test/character_sheet_ui_test.dart` and adapts. The `conditionsSection` + sibling-view-constructor signatures are confirmed against `shadowdark_sheet.dart` before use.
