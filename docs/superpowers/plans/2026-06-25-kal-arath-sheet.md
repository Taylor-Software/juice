# Kal-Arath Character Sheet Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Add a facts-only Kal-Arath character sheet with 5 stats, per-stat 2d6-roll buttons (2d6 + stat ≥ 8 → Success; two 6s crit success, two 1s crit failure), Fate Points, demonic pact + doom, skill archetype, HP, damage reduction.

**Architecture:** Mirror the OSE/Knave/Cairn pattern: `KalArathSheet` model + `Character.kalArath` field in `models.dart`, `KalArathSheetView` ConsumerWidget, wired into tracker/home-shell/encounter/primer. System ID: `'kal-arath'`. Resolution is **2d6 + stat ≥ 8** (NOT d20). Crit on doubles (two 6s / two 1s). Stat range −1 to +5.

**Licensing:** Kal-Arath © 2023 Castle Grief, "permission granted to copy for personal use" only — NOT an app/redistribution license. This sheet uses ONLY non-copyrightable game-mechanic facts (stat / archetype / pact names). Strictest facts-only posture, identical to Shadowdark: **NO rulebook prose, NO attribution, NO "compatible-with" claim, NO settings note, NO kSystemBlurbs creator credit.** (A richer P2 — pact/skill text + attribution — is deferred pending explicit permission from Castle Grief.)

**Tech Stack:** Dart, Flutter, flutter_riverpod, shared_preferences, flutter_test.

**Working directory:** `.worktrees/kal-arath` (branch `kal-arath`). Paths relative to repo root.

**Do NOT stage:** `macos/Runner.xcodeproj`, `macos/Runner.xcworkspace`, `macos/Podfile.lock`.

---

## Mechanics Reference (facts only)

- **Stats (5):** STR, TOU, AGI, INT, PRE. Range −1 to +5 (start: 4 points, one may be −1, cap +2 at start; +5 max).
- **Resolution:** roll 2d6 + stat. ≥ 8 = Success. Two 6s = Critical Success; two 1s = Critical Failure (regardless of total). Combat uses +STR (melee) / +AGI (missile) / +INT (magic) — the sheet's per-stat buttons cover all.
- **HP:** current/max (d6 + TOU at creation).
- **Fate Points:** 1 per session (re-roll); player-managed counter.
- **Skill archetypes (4):** Warrior, Rogue, Mystic, Explorer (chosen skills are prose → freeform field).
- **Demonic Pact (6):** Blood, Destruction, Corruption, Illumination, Shadow, Domination (+ none). The pact's Doom is freeform.
- **Damage reduction:** from armor (player-managed int).
- **Level:** 1–9; XP freeform.

---

## File Structure

| File | Action |
|------|--------|
| `lib/engine/models.dart` | Add `kKalArathStats`/`kKalArathStatLabels`/`kKalArathArchetypes`/`kKalArathPacts`, `KalArathSheet`; add `Character.kalArath` |
| `lib/state/providers.dart` | Add `CharacterNotifier.addKalArath()` |
| `lib/features/kal_arath_sheet.dart` | Create `KalArathSheetView` |
| `lib/engine/system_primer.dart` | Add `'kal-arath'` primer + branches |
| `lib/engine/models.dart` (kKnownSystems/kSystemCategory) | Add `'kal-arath'` as a ruleset |
| `lib/engine/campaign_surfaces.dart` | Add Kal-Arath sheet surface row |
| `lib/engine/campaign_presets.dart` | Add `solo-kal-arath` preset |
| `lib/features/tracker_screen.dart` | Render branch + `new-kal-arath` + `_newKalArath()` |
| `lib/shared/home_shell.dart` | `kSystemBlurbs` + `kSystemShortName` + `kPresetIcons` entries |
| `lib/features/encounter_screen.dart` | HP branch |
| `CLAUDE.md` | Note the sheet |
| `test/kal_arath_sheet_test.dart` | Model unit tests |
| `test/kal_arath_sheet_ui_test.dart` | Widget tests |

NOTE: Because P1/P2 of the campaign redesign landed, a new ruleset system MUST also be added to `kKnownSystems`, `kSystemCategory` (→ ruleset), `kSystemShortName`, `kSystemBlurbs`, `surfacesFor`'s Sheet table, and optionally a `solo-*` preset. The `campaign_presets_test` (`every preset references only known systems`) and `campaign_surfaces_test` (`every authored system gate is a known system`) completeness tests will FAIL if these drift — that's the safety net.

---

## Task 1: KalArathSheet model + Character.kalArath

**Files:** Modify `lib/engine/models.dart`; Create `test/kal_arath_sheet_test.dart`.

- [ ] **Step 1: Create test file**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';

void main() {
  test('KalArathSheet round-trips toJson/maybeFromJson', () {
    const s = KalArathSheet(
      archetype: 'Mystic',
      level: 2,
      xp: '3',
      stats: {'str': 1, 'tou': 0, 'agi': 2, 'int': 1, 'pre': -1},
      maxHp: 7,
      currentHp: 4,
      fatePoints: 2,
      damageReduction: 1,
      pact: 'Shadow',
      doom: 'no metal',
      skills: 'sneak',
      notes: 'n',
    );
    final back = KalArathSheet.maybeFromJson(s.toJson())!;
    expect(back.archetype, 'Mystic');
    expect(back.stats['agi'], 2);
    expect(back.stats['pre'], -1);
    expect(back.currentHp, 4);
    expect(back.fatePoints, 2);
    expect(back.pact, 'Shadow');
    expect(KalArathSheet.maybeFromJson('nope'), isNull);
  });

  test('KalArathSheet copyWith clamps stats -1..5, hp, level, fate, dr', () {
    const s = KalArathSheet(
      stats: {'str': 0, 'tou': 0, 'agi': 0, 'int': 0, 'pre': 0},
      maxHp: 6,
      currentHp: 3,
    );
    expect(s.copyWith(stats: {...s.stats, 'str': 9}).stats['str'], 5);
    expect(s.copyWith(stats: {...s.stats, 'str': -5}).stats['str'], -1);
    expect(s.copyWith(currentHp: 99).currentHp, 6);
    expect(s.copyWith(currentHp: -1).currentHp, 0);
    expect(s.copyWith(level: 0).level, 1);
    expect(s.copyWith(level: 99).level, 9);
    expect(s.copyWith(fatePoints: -1).fatePoints, 0);
    expect(s.copyWith(damageReduction: -1).damageReduction, 0);
  });

  test('Kal-Arath constants', () {
    expect(kKalArathStats, ['str', 'tou', 'agi', 'int', 'pre']);
    expect(kKalArathArchetypes.length, 4);
    expect(kKalArathPacts.length, 6);
    expect(kKalArathStatLabels['tou'], 'TOU');
  });

  test('Character round-trips kalArath + withHpDelta', () {
    const c = Character(
      id: 'c1',
      name: 'Vorr',
      kalArath: KalArathSheet(maxHp: 8, currentHp: 8),
    );
    final back = Character.fromJson(c.toJson());
    expect(back.kalArath, isNotNull);
    expect(c.withHpDelta(-3).kalArath!.currentHp, 5);
    expect(c.withHpDelta(99).kalArath!.currentHp, 8);
    expect(c.withHpDelta(-99).kalArath!.currentHp, 0);
  });
}
```

- [ ] **Step 2: Verify FAIL** — `cd .worktrees/kal-arath && flutter test test/kal_arath_sheet_test.dart 2>&1 | head -5`

- [ ] **Step 3: Add constants + KalArathSheet to `lib/engine/models.dart`**

Find where `OseSheet.maybeFromJson` ends; insert IMMEDIATELY AFTER its closing `}`:

```dart
// ── Kal-Arath ────────────────────────────────────────────────────────────────

const kKalArathStats = <String>['str', 'tou', 'agi', 'int', 'pre'];

const kKalArathStatLabels = <String, String>{
  'str': 'STR',
  'tou': 'TOU',
  'agi': 'AGI',
  'int': 'INT',
  'pre': 'PRE',
};

const kKalArathArchetypes = <String>['Warrior', 'Rogue', 'Mystic', 'Explorer'];

const kKalArathPacts = <String>[
  'Blood', 'Destruction', 'Corruption', 'Illumination', 'Shadow', 'Domination',
];

/// Facts-only Kal-Arath character sheet. Field names are non-copyrightable
/// game-mechanic facts. No rulebook prose or attribution (Kal-Arath © Castle
/// Grief is personal-use only; richer content deferred pending permission).
class KalArathSheet {
  const KalArathSheet({
    this.archetype = 'Warrior',
    this.level = 1,
    this.xp = '',
    this.stats = const {
      'str': 0, 'tou': 0, 'agi': 0, 'int': 0, 'pre': 0,
    },
    this.maxHp = 4,
    this.currentHp = 4,
    this.fatePoints = 1,
    this.damageReduction = 0,
    this.pact = '',
    this.doom = '',
    this.skills = '',
    this.notes = '',
  });

  final String archetype;
  final int level;
  final String xp;
  final Map<String, int> stats;
  final int maxHp;
  final int currentHp;
  final int fatePoints;
  final int damageReduction;
  final String pact;
  final String doom;
  final String skills;
  final String notes;

  KalArathSheet copyWith({
    String? archetype,
    int? level,
    String? xp,
    Map<String, int>? stats,
    int? maxHp,
    int? currentHp,
    int? fatePoints,
    int? damageReduction,
    String? pact,
    String? doom,
    String? skills,
    String? notes,
  }) {
    final mh = (maxHp ?? this.maxHp).clamp(0, 1 << 20);
    final st = stats ?? this.stats;
    return KalArathSheet(
      archetype: archetype ?? this.archetype,
      level: (level ?? this.level).clamp(1, 9),
      xp: xp ?? this.xp,
      stats: {
        for (final k in kKalArathStats)
          k: ((st[k] ?? 0) as num).round().clamp(-1, 5)
      },
      maxHp: mh,
      currentHp: (currentHp ?? this.currentHp).clamp(0, mh),
      fatePoints: (fatePoints ?? this.fatePoints).clamp(0, 99),
      damageReduction: (damageReduction ?? this.damageReduction).clamp(0, 99),
      pact: pact ?? this.pact,
      doom: doom ?? this.doom,
      skills: skills ?? this.skills,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() => {
        'archetype': archetype,
        'level': level,
        'xp': xp,
        'stats': stats,
        'maxHp': maxHp,
        'currentHp': currentHp,
        'fatePoints': fatePoints,
        'damageReduction': damageReduction,
        'pact': pact,
        'doom': doom,
        'skills': skills,
        'notes': notes,
      };

  static KalArathSheet? maybeFromJson(dynamic j) {
    if (j is! Map<String, dynamic>) return null;
    final st = (j['stats'] as Map?) ?? {};
    return KalArathSheet(
      archetype: j['archetype'] as String? ?? 'Warrior',
      level: ((j['level'] as num?)?.round() ?? 1).clamp(1, 9),
      xp: j['xp'] as String? ?? '',
      stats: {
        for (final k in kKalArathStats)
          k: ((st[k] ?? 0) as num).round().clamp(-1, 5),
      },
      maxHp: (j['maxHp'] as num?)?.round() ?? 4,
      currentHp: (j['currentHp'] as num?)?.round() ?? 4,
      fatePoints: ((j['fatePoints'] as num?)?.round() ?? 1).clamp(0, 99),
      damageReduction:
          ((j['damageReduction'] as num?)?.round() ?? 0).clamp(0, 99),
      pact: j['pact'] as String? ?? '',
      doom: j['doom'] as String? ?? '',
      skills: j['skills'] as String? ?? '',
      notes: j['notes'] as String? ?? '',
    );
  }
}
```

- [ ] **Step 4: Add `Character.kalArath` field** — mirror how `ose` was added (7 points):
  - **4a.** ctor param (after `this.ose,`): `this.kalArath,`
  - **4b.** field (after `final OseSheet? ose;`): `final KalArathSheet? kalArath;`
  - **4c.** copyWith params (after `bool clearOse = false,`):
    ```dart
    KalArathSheet? kalArath,
    bool clearKalArath = false,
    ```
  - **4d.** copyWith body (after `ose:` line): `kalArath: clearKalArath ? null : (kalArath ?? this.kalArath),`
  - **4e.** withHpDelta (after `ose != null` branch):
    ```dart
    if (kalArath != null) {
      return copyWith(
          kalArath: kalArath!.copyWith(
              currentHp:
                  (kalArath!.currentHp + delta).clamp(0, kalArath!.maxHp)));
    }
    ```
  - **4f.** toJson (after `ose` entry): `if (kalArath != null) 'kalArath': kalArath!.toJson(),`
  - **4g.** fromJson (after `ose:` line): `kalArath: KalArathSheet.maybeFromJson(j['kalArath']),`

- [ ] **Step 5: Run tests** — `flutter test test/kal_arath_sheet_test.dart` (4 pass) + `flutter analyze`.

- [ ] **Step 6: Commit**

```bash
git add lib/engine/models.dart test/kal_arath_sheet_test.dart
git commit -m "$(cat <<'EOF'
feat(kal-arath): KalArathSheet model + Character.kalArath field

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: addKalArath() + register the system

**Files:** Modify `lib/state/providers.dart`, `lib/engine/models.dart` (kKnownSystems/kSystemCategory).

- [ ] **Step 1: addKalArath()** — find `addOse()` in providers.dart, add after:

```dart
  Future<String> addKalArath() async {
    final id = _newId();
    await _persist([
      Character(id: id, name: 'New Wanderer', kalArath: const KalArathSheet()),
      ...await _ready,
    ]);
    return id;
  }
```

- [ ] **Step 2: Register `'kal-arath'` as a known ruleset system.**

In `lib/engine/models.dart`:
- Add `'kal-arath'` to `kKnownSystems` (the set).
- Add `'kal-arath': SystemCategory.ruleset,` to `kSystemCategory`.

- [ ] **Step 3: Update the completeness test** in `test/campaign_presets_test.dart` (the "kKnownSystems has the 16 ids" test) → make it 17 ids including `'kal-arath'`, and the "9 ruleset systems" test → 10, adding `'kal-arath'`. Run `flutter test test/campaign_presets_test.dart` — should pass.

- [ ] **Step 4: Verify + commit**

```bash
flutter analyze && flutter test test/kal_arath_sheet_test.dart test/campaign_presets_test.dart
git add lib/state/providers.dart lib/engine/models.dart test/campaign_presets_test.dart
git commit -m "$(cat <<'EOF'
feat(kal-arath): addKalArath() + register kal-arath ruleset system

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: KalArathSheetView + widget tests

**Files:** Create `lib/features/kal_arath_sheet.dart`, `test/kal_arath_sheet_ui_test.dart`.

**Keys:** root `kal-arath-sheet`; back `sheet-back`; `kal-arath-archetype` dropdown; `kal-arath-pact` dropdown; `kal-arath-stat-<k>-minus/plus` (range −1..5); `kal-arath-roll-<k>` roll buttons; `kal-arath-level-minus/plus` (1..9); `kal-arath-hp-minus/plus`, `kal-arath-maxhp-minus/plus`; `kal-arath-fate-minus/plus`; `kal-arath-dr-minus/plus`; `kal-arath-xp`, `kal-arath-doom`, `kal-arath-skills`, `kal-arath-notes` text fields.

**System label text:** `'Kal-Arath'`.

**Roll logic (2d6 + stat):**
```dart
void _roll(BuildContext context, String statKey) {
  final score = _s.stats[statKey] ?? 0;
  final d1 = Random().nextInt(6) + 1;
  final d2 = Random().nextInt(6) + 1;
  final total = d1 + d2 + score;
  final String result;
  if (d1 == 6 && d2 == 6) {
    result = 'Critical Success';
  } else if (d1 == 1 && d2 == 1) {
    result = 'Critical Failure';
  } else {
    result = total >= 8 ? 'Success' : 'Failure';
  }
  final label = kKalArathStatLabels[statKey] ?? statKey.toUpperCase();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('$label: $total — $result'),
      duration: const Duration(seconds: 3),
    ),
  );
}
```

CRITICAL: use the em-dash `—` ONLY in the snackbar (the widget test asserts exactly one `find.textContaining('—')`). No `—` in static text. Stat steppers allow min −1, max 5 (so `value > -1` / `value < 5` for enable). Pact dropdown includes a leading "None" (`value: ''`).

- [ ] **Step 1: Write failing tests** `test/kal_arath_sheet_ui_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/features/kal_arath_sheet.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _pump(WidgetTester tester) async {
  const sheet = KalArathSheet(
    archetype: 'Warrior',
    stats: {'str': 2, 'tou': 1, 'agi': 0, 'int': -1, 'pre': 1},
    maxHp: 8,
    currentHp: 6,
    fatePoints: 1,
  );
  SharedPreferences.setMockInitialValues({
    'juice.sessions.v1':
        '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    'juice.characters.v1.default': jsonEncode([
      {
        'id': 'c1',
        'name': 'Vorr',
        'stats': [],
        'tracks': [],
        'tags': [],
        'kalArath': sheet.toJson(),
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
            return KalArathSheetView(character: live, onBack: () {});
          })))));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('kal-arath-sheet renders with name + label', (tester) async {
    tester.view.physicalSize = const Size(1200, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pump(tester);
    expect(find.byKey(const Key('kal-arath-sheet')), findsOneWidget);
    expect(find.text('Vorr'), findsOneWidget);
    expect(find.text('Kal-Arath'), findsOneWidget);
  });

  testWidgets('HP stepper persists', (tester) async {
    tester.view.physicalSize = const Size(1200, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = await _pump(tester);
    await tester.tap(find.byKey(const Key('kal-arath-hp-minus')));
    await tester.pumpAndSettle();
    final chars = await c.read(charactersProvider.future);
    expect(chars.single.kalArath!.currentHp, 5);
  });

  testWidgets('roll button shows snackbar with em-dash', (tester) async {
    tester.view.physicalSize = const Size(1200, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pump(tester);
    await tester.tap(find.byKey(const Key('kal-arath-roll-str')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('—'), findsOneWidget);
  });

  testWidgets('fate point stepper persists', (tester) async {
    tester.view.physicalSize = const Size(1200, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = await _pump(tester);
    await tester.tap(find.byKey(const Key('kal-arath-fate-minus')));
    await tester.pumpAndSettle();
    final chars = await c.read(charactersProvider.future);
    expect(chars.single.kalArath!.fatePoints, 0);
  });

  testWidgets('sheet-back fires onBack', (tester) async {
    tester.view.physicalSize = const Size(1200, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var back = false;
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.characters.v1.default': jsonEncode([
        {
          'id': 'c1',
          'name': 'Vorr',
          'stats': [],
          'tracks': [],
          'tags': [],
          'kalArath': const KalArathSheet().toJson(),
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
            home: Scaffold(
                body: KalArathSheetView(
                    character: char, onBack: () => back = true)))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sheet-back')));
    await tester.pumpAndSettle();
    expect(back, isTrue);
  });
}
```

- [ ] **Step 2: Verify FAIL.**

- [ ] **Step 3: Create `lib/features/kal_arath_sheet.dart`** — `KalArathSheetView extends ConsumerWidget`. Use the OSE sheet (`lib/features/ose_sheet.dart`) as the structural template: a `_save(ref, next)` that calls `charactersProvider.notifier.replace(character.copyWith(kalArath: next))`; a `_stepper(key,label,value,{onSet,min,max})` helper; per-stat blocks with a `kal-arath-roll-<k>` casino icon button calling `_roll`; the dropdowns for archetype + pact; HP/maxHp/fate/dr steppers; `conditionsSection(context, ref, character, 'kal-arath')`; freeform xp/doom/skills/notes `TextFormField`s. System label `Text('Kal-Arath', style: theme.textTheme.labelSmall)`. Stat stepper min −1, max 5.

  Pact dropdown:
  ```dart
  DropdownButtonFormField<String>(
    key: const Key('kal-arath-pact'),
    value: kKalArathPacts.contains(s.pact) ? s.pact : '',
    decoration: const InputDecoration(labelText: 'Demonic pact'),
    items: [
      const DropdownMenuItem(value: '', child: Text('None')),
      for (final p in kKalArathPacts)
        DropdownMenuItem(value: p, child: Text(p)),
    ],
    onChanged: (v) => _save(ref, s.copyWith(pact: v ?? '')),
  ),
  ```

- [ ] **Step 4: Run tests** (`flutter test test/kal_arath_sheet_ui_test.dart`, 5 pass) + `flutter analyze`.

- [ ] **Step 5: Commit**

```bash
git add lib/features/kal_arath_sheet.dart test/kal_arath_sheet_ui_test.dart
git commit -m "$(cat <<'EOF'
feat(kal-arath): KalArathSheetView with 2d6 roll buttons, pact, fate points

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: System wiring (primer, tracker, home-shell, encounter, surfaces, preset)

- [ ] **system_primer.dart** — after the `'ose'` entry in `kSystemPrimers`:
```dart
  'kal-arath':
      'Kal-Arath: sword & sorcery OSR. Resolution: roll 2d6 + stat, 8+ to succeed; double 6s crit, double 1s fumble. Five stats; demonic pacts; Fate Points.',
```
Verify ≤ 220 chars. Add `kal-arath` branches in `resolveSystemPrimer`/`resolveSystem` (after ose).

- [ ] **tracker_screen.dart** — import `kal_arath_sheet.dart`; render branch before ose: `if (c.kalArath != null) return KalArathSheetView(character: c, onBack: onBack);`; `new-kal-arath` option; `_newKalArath()` (→ `addKalArath()`); dispatch entry; short-circuit guard `&& !systems.contains('kal-arath')`; hint text.

- [ ] **home_shell.dart**:
  - `kSystemBlurbs['kal-arath']` — facts-only, NO creator credit:
    ```dart
      'kal-arath':
          'Kal-Arath: sword & sorcery OSR. 2d6 + stat >= 8; five stats, '
          'demonic pacts, Fate Points. Facts-only mechanics.',
    ```
  - `kSystemShortName['kal-arath'] = 'Kal-Arath'`
  - `kPresetIcons['solo-kal-arath'] = Icons.whatshot` (any material icon)

- [ ] **campaign_presets.dart** — add a `solo-kal-arath` preset (party mode, `{'kal-arath','juice','party'}`):
```dart
  CampaignPreset(
      id: 'solo-kal-arath',
      label: 'Kal-Arath',
      mode: CampaignMode.party,
      systems: {'kal-arath', 'juice', 'party'}),
```
Place it among the `solo-*` ruleset presets. The `campaign_presets_test` "ruleset presets" test counts `solo-*` presets — update the expected count from 9 to 10.

- [ ] **campaign_surfaces.dart** — add a Sheet surface row:
```dart
    SurfaceRow('Kal-Arath sheet', requiresSystem: 'kal-arath'),
```
(in the `'Sheet'` list). The no-drift test validates it.

- [ ] **encounter_screen.dart** — before the ose branch:
```dart
        } else if (linked.kalArath != null) {
          curHp = linked.kalArath!.currentHp;
          maxHp = linked.kalArath!.maxHp;
```

- [ ] **character_sheet_ui_test.dart** — if the "omit hint" test enumerates sheet systems, add `'kal-arath'` + a `new-kal-arath` key assertion.

- [ ] **Verify + commit**

```bash
flutter analyze
flutter test
git add lib/engine/system_primer.dart lib/features/tracker_screen.dart \
        lib/shared/home_shell.dart lib/features/encounter_screen.dart \
        lib/engine/campaign_presets.dart lib/engine/campaign_surfaces.dart
git add test/character_sheet_ui_test.dart test/campaign_presets_test.dart 2>/dev/null || true
git commit -m "$(cat <<'EOF'
feat(kal-arath): system wiring — primer, tracker, home-shell, encounter, presets, surfaces

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: CLAUDE.md + full verify + PR

- [ ] **CLAUDE.md** — after the OSE bullet:
```
- A facts-only **Kal-Arath** sheet (`lib/features/kal_arath_sheet.dart`, rendered
  when `Character.kalArath` is set; opt-in `kal-arath` system, NOT in `kAllSystems`).
  Authored constants: `kKalArathStats` / `kKalArathStatLabels` (5: STR/TOU/AGI/INT/PRE,
  range -1..+5) / `kKalArathArchetypes` (Warrior/Rogue/Mystic/Explorer) / `kKalArathPacts`
  (6: Blood/Destruction/Corruption/Illumination/Shadow/Domination). Per-stat **roll**
  buttons (2d6 + stat >= 8 -> Success; double 6s Critical Success, double 1s Critical
  Failure; snackbar "STR: 10 — Success"; ephemeral). **Fate Points** stepper (1/session).
  Demonic-pact dropdown + freeform Doom. Skill archetype dropdown; skills/notes freeform.
  Damage-reduction + level (1-9) steppers. **Licensing:** Kal-Arath © 2023 Castle Grief
  is personal-use-only (not an app license); strictest facts-only posture like Shadowdark
  — NO rulebook prose, NO attribution, NO compatible-with claim. A richer P2 (pact/skill
  text + attribution) is deferred pending explicit permission from Castle Grief. Registered
  as a ruleset in `kKnownSystems`/`kSystemCategory`, with a `solo-kal-arath` preset +
  `surfacesFor` row. See `docs/superpowers/plans/2026-06-25-kal-arath-sheet.md`.
```

- [ ] **Full verify:** `flutter analyze` clean; `flutter test` all pass.

- [ ] **Commit + PR** (title `feat(kal-arath): Kal-Arath character sheet (facts-only)`, against `main`).

---

## Self-Review

**Spec coverage:** stats(-1..5)+labels, archetypes, pacts, KalArathSheet, Character.kalArath (7 pts) → T1 ✓; addKalArath + system registration (kKnownSystems/kSystemCategory) → T2 ✓; view w/ 2d6 roll (double-6/double-1 crit), fate, pact, archetype → T3 ✓; primer/tracker/home-shell/encounter/preset/surfaces wiring → T4 ✓; CLAUDE.md + facts-only licensing posture (no prose/attribution) → T5 ✓.

**Placeholder scan:** none.

**Type consistency:** `KalArathSheet.currentHp/maxHp` in withHpDelta (T1) + encounter (T4) ✓; `kal-arath` system id consistent across kKnownSystems/kSystemCategory/primer/blurb/preset/surfaces ✓; completeness tests (`campaign_presets_test` 16→17 ids, 9→10 ruleset/solo-presets; `campaign_surfaces_test` no-drift) updated in T2+T4 — these are the safety net that forces every registration point to be filled ✓.
