# Draw Steel Character Sheet Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a facts-only Draw Steel (MCDM) character sheet with per-characteristic power-roll buttons (2d10 + score → tier snackbar), gated on an opt-in `draw-steel` system.

**Architecture:** Mirror the `NimbleSheet` pattern throughout — `DrawSteelSheet` model + `Character.drawSteel` field in `models.dart`, a `DrawSteelSheetView` ConsumerWidget in its own file, wired into tracker/home-shell/encounter by the same hooks as nimble/shadowdark. Power roll is an ephemeral snackbar (no journal log) computed inline from `dart:math`.

**Tech Stack:** Dart, Flutter, flutter_riverpod, shared_preferences, flutter_test.

---

## File Structure

| File | Action |
|------|--------|
| `lib/engine/models.dart` | Add `kDrawSteelCharacteristics`, `kDrawSteelClasses`, `kDrawSteelHeroicResource`, `DrawSteelSheet` class, `Character.drawSteel` field, `withHpDelta` branch |
| `lib/state/providers.dart` | Add `CharacterNotifier.addDrawSteel()` |
| `lib/features/draw_steel_sheet.dart` | Create `DrawSteelSheetView` |
| `lib/engine/system_primer.dart` | Add `draw-steel` primer + `resolveSystemPrimer`/`resolveSystem` branch |
| `lib/features/tracker_screen.dart` | Render branch + `new-draw-steel` create option + `_newDrawSteel()` |
| `lib/shared/home_shell.dart` | `sys-draw-steel` toggle in both dialogs + `kSystemBlurbs` entry |
| `lib/features/encounter_screen.dart` | HP read-through branch for `drawSteel` |
| `lib/features/settings_sheet.dart` | MCDM non-affiliation disclaimer section |
| `test/draw_steel_sheet_test.dart` | Create — model unit tests |
| `test/draw_steel_sheet_ui_test.dart` | Create — widget tests |
| `CLAUDE.md` | Note the Draw Steel sheet |

---

## Task 1: Verify constants + DrawSteelSheet model

**Files:**
- Modify: `lib/engine/models.dart` (after the `NimbleSheet` block, ~line 1491)
- Create: `test/draw_steel_sheet_test.dart`

- [ ] **Step 1: Verify class names and heroic resource names from MCDM**

  Search the web for `"draw steel MCDM classes list" site:mcdmproductions.com OR site:shop.mcdmproductions.com` and check [MCDM Draw Steel Resources](https://www.mcdmproductions.com/draw-steel-resources).

  You need: the **full released class list** from *Draw Steel: Heroes* and the **heroic resource name** for each class. Confirmed characteristics: Might, Agility, Reason, Intuition, Presence (all sources agree). Resource names and the full class list need verification — the backer-packet classes (Fury, Conduit, Tactician, Elementalist, Shadow) are confirmed; check whether the released book adds more (Null, Troubadour, Talent, Censor have been mentioned as candidates). Update the constants in Step 3 with what you find.

- [ ] **Step 2: Write failing tests**

  Create `test/draw_steel_sheet_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';

void main() {
  // ── Model unit tests ──────────────────────────────────────────────────────

  test('DrawSteelSheet round-trips toJson/maybeFromJson', () {
    const s = DrawSteelSheet(
      className: 'Fury',
      ancestry: 'Human',
      level: 3,
      characteristics: {'might': 2, 'agility': 1, 'reason': 0, 'intuition': -1, 'presence': 1},
      maxStamina: 30,
      currentStamina: 22,
      recoveries: 3,
      maxRecoveries: 8,
      stability: 1,
      heroicResource: 2,
      skills: 'Climb',
      notes: 'n',
    );
    final back = DrawSteelSheet.maybeFromJson(s.toJson())!;
    expect(back.className, 'Fury');
    expect(back.characteristics['might'], 2);
    expect(back.currentStamina, 22);
    expect(back.stability, 1);
    expect(back.heroicResource, 2);
    expect(back.skills, 'Climb');
  });

  test('DrawSteelSheet copyWith clamps level and stamina', () {
    const s = DrawSteelSheet(maxStamina: 20, currentStamina: 10);
    final over = s.copyWith(level: 99, currentStamina: 999);
    expect(over.level, 10);
    expect(over.currentStamina, 20); // clamped to maxStamina
    final under = s.copyWith(level: 0, currentStamina: -5);
    expect(under.level, 1);
    expect(under.currentStamina, 0);
  });

  test('DrawSteelSheet unknown class falls back to first class', () {
    final s = DrawSteelSheet.maybeFromJson({'className': 'Bogus'})!;
    expect(s.className, kDrawSteelClasses.first);
    expect(DrawSteelSheet.maybeFromJson('nope'), isNull);
  });

  test('DrawSteelSheet.resourceLabel returns known resource or "Resource"', () {
    // Each class in kDrawSteelClasses must appear in kDrawSteelHeroicResource.
    for (final cls in kDrawSteelClasses) {
      expect(DrawSteelSheet(className: cls).resourceLabel, isNotEmpty);
    }
    // Unknown class (shouldn't happen after copyWith) → fallback.
    expect(
      const DrawSteelSheet(className: '_bogus').resourceLabel,
      'Resource',
    );
  });

  test('Character round-trips drawSteel + withHpDelta adjusts stamina', () {
    const c = Character(
        id: 'c1',
        name: 'Kael',
        drawSteel: DrawSteelSheet(currentStamina: 20, maxStamina: 30));
    final back = Character.fromJson(c.toJson());
    expect(back.drawSteel, isNotNull);
    expect(back.drawSteel!.currentStamina, 20);

    final hurt = c.withHpDelta(-5);
    expect(hurt.drawSteel!.currentStamina, 15);

    final overheal = c.withHpDelta(99);
    expect(overheal.drawSteel!.currentStamina, 30); // clamped to maxStamina

    final overkill = c.withHpDelta(-999);
    expect(overkill.drawSteel!.currentStamina, 0); // clamped to 0
  });

  test('kSystemBlurbs draw-steel contains MCDM non-affiliation text', () {
    // License requirement: non-affiliation statement must appear in promotional
    // materials; kSystemBlurbs shows in the new-campaign / edit-systems dialogs.
    expect(kSystemBlurbs['draw-steel'], isNotNull);
    final blurb = kSystemBlurbs['draw-steel']!;
    expect(blurb.toLowerCase(), contains('mcdm'));
    expect(blurb.toLowerCase(), contains('not affiliated'));
  });
}
```

- [ ] **Step 3: Run to confirm tests fail**

  Run: `flutter test test/draw_steel_sheet_test.dart`
  Expected: FAIL — `DrawSteelSheet` undefined.

- [ ] **Step 4: Implement constants + DrawSteelSheet in `lib/engine/models.dart`**

  Add immediately after the closing `}` of `NimbleSheet.maybeFromJson` (~line 1491), before the `// --- Shadowdark` comment block:

```dart
// --- Draw Steel (facts-only: class/characteristic NAMES only; published under
// the Draw Steel Creator License — not affiliated with MCDM Productions, LLC)

/// Characteristic keys for Draw Steel power rolls (non-copyrightable names).
const kDrawSteelCharacteristics = <String>[
  'might',
  'agility',
  'reason',
  'intuition',
  'presence',
];

/// Published hero classes from Draw Steel: Heroes (MCDM Productions).
/// VERIFY against https://www.mcdmproductions.com/draw-steel-resources
/// if the released book adds classes beyond the confirmed five.
const kDrawSteelClasses = <String>[
  'Conduit',
  'Elementalist',
  'Fury',
  'Null',     // VERIFY: present in released Heroes book?
  'Shadow',
  'Tactician',
  'Troubadour', // VERIFY: present in released Heroes book?
];

/// Heroic resource name per class (the class-specific pool spent on abilities).
/// VERIFY names against published Draw Steel: Heroes.
const kDrawSteelHeroicResource = <String, String>{
  'Conduit': 'Piety',
  'Elementalist': 'Essence',
  'Fury': 'Fury',
  'Null': 'Null Points', // VERIFY
  'Shadow': 'Shadow',
  'Tactician': 'Momentum',
  'Troubadour': 'Drama', // VERIFY
};

/// Facts-only Draw Steel sheet. Class/characteristic NAMES are authored
/// constants; all values are player-editable. Published under the Draw Steel
/// Creator License; not affiliated with MCDM Productions, LLC.
class DrawSteelSheet {
  const DrawSteelSheet({
    this.className = 'Conduit',
    this.ancestry = '',
    this.level = 1,
    this.characteristics = const {
      'might': 0,
      'agility': 0,
      'reason': 0,
      'intuition': 0,
      'presence': 0,
    },
    this.maxStamina = 1,
    this.currentStamina = 1,
    this.recoveries = 0,
    this.maxRecoveries = 0,
    this.stability = 0,
    this.heroicResource = 0,
    this.skills = '',
    this.notes = '',
  });

  final String className;
  final String ancestry;
  final int level;
  final Map<String, int> characteristics; // keys = kDrawSteelCharacteristics, −5..+5
  final int maxStamina;
  final int currentStamina;
  final int recoveries;
  final int maxRecoveries;
  final int stability;
  final int heroicResource;
  final String skills;
  final String notes;

  /// The display name of this class's heroic resource pool.
  String get resourceLabel =>
      kDrawSteelHeroicResource[className] ?? 'Resource';

  DrawSteelSheet copyWith({
    String? className,
    String? ancestry,
    int? level,
    Map<String, int>? characteristics,
    int? maxStamina,
    int? currentStamina,
    int? recoveries,
    int? maxRecoveries,
    int? stability,
    int? heroicResource,
    String? skills,
    String? notes,
  }) {
    final cls = className ?? this.className;
    final ms = (maxStamina ?? this.maxStamina).clamp(0, 1 << 20);
    final ch = characteristics ?? this.characteristics;
    return DrawSteelSheet(
      className: kDrawSteelClasses.contains(cls) ? cls : kDrawSteelClasses.first,
      ancestry: ancestry ?? this.ancestry,
      level: (level ?? this.level).clamp(1, 10),
      characteristics: {
        for (final k in kDrawSteelCharacteristics)
          k: (ch[k] ?? 0).clamp(-5, 5),
      },
      maxStamina: ms,
      currentStamina: (currentStamina ?? this.currentStamina).clamp(0, ms),
      recoveries: (recoveries ?? this.recoveries).clamp(0, 1 << 20),
      maxRecoveries: (maxRecoveries ?? this.maxRecoveries).clamp(0, 1 << 20),
      stability: (stability ?? this.stability).clamp(0, 99),
      heroicResource: (heroicResource ?? this.heroicResource).clamp(0, 1 << 20),
      skills: skills ?? this.skills,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() => {
        'className': className,
        'ancestry': ancestry,
        'level': level,
        'characteristics': characteristics,
        'maxStamina': maxStamina,
        'currentStamina': currentStamina,
        'recoveries': recoveries,
        'maxRecoveries': maxRecoveries,
        'stability': stability,
        'heroicResource': heroicResource,
        if (skills.isNotEmpty) 'skills': skills,
        if (notes.isNotEmpty) 'notes': notes,
      };

  static DrawSteelSheet? maybeFromJson(Object? j) {
    if (j is! Map) return null;
    int i(String k, int d) => (j[k] as num?)?.toInt() ?? d;
    Map<String, int> intMap(String k) => {
          for (final e in ((j[k] as Map?) ?? const {}).entries)
            '${e.key}': (e.value as num?)?.toInt() ?? 0,
        };
    return const DrawSteelSheet().copyWith(
      className: j['className'] as String?,
      ancestry: j['ancestry'] as String?,
      level: i('level', 1),
      characteristics: intMap('characteristics'),
      maxStamina: i('maxStamina', 1),
      currentStamina: i('currentStamina', 1),
      recoveries: i('recoveries', 0),
      maxRecoveries: i('maxRecoveries', 0),
      stability: i('stability', 0),
      heroicResource: i('heroicResource', 0),
      skills: j['skills'] as String?,
      notes: j['notes'] as String?,
    );
  }
}
```

- [ ] **Step 5: Add `Character.drawSteel` field**

  In `lib/engine/models.dart`, find the `Character` class. Follow the exact pattern used for `nimble`:

  **5a.** In the constructor, add `this.drawSteel` after `this.nimble`:
  ```dart
  this.drawSteel,
  ```

  **5b.** Add the field declaration after `final NimbleSheet? nimble;`:
  ```dart
  /// Bespoke Draw Steel sheet; null unless this is a Draw Steel hero.
  final DrawSteelSheet? drawSteel;
  ```

  **5c.** In `copyWith`, add the parameter after `clearNimble`:
  ```dart
  DrawSteelSheet? drawSteel,
  bool clearDrawSteel = false,
  ```

  **5d.** In the `copyWith` return `Character(...)`, add after `nimble: clearNimble ? null : (nimble ?? this.nimble),`:
  ```dart
  drawSteel: clearDrawSteel ? null : (drawSteel ?? this.drawSteel),
  ```

  **5e.** In `withHpDelta`, add before the `if (tracks.isNotEmpty)` block:
  ```dart
    if (drawSteel != null) {
      return copyWith(
          drawSteel: drawSteel!.copyWith(
              currentStamina:
                  (drawSteel!.currentStamina + delta).clamp(0, drawSteel!.maxStamina)));
    }
  ```

  **5f.** In `toJson()`, add after the nimble line:
  ```dart
        if (drawSteel != null) 'drawSteel': drawSteel!.toJson(),
  ```

  **5g.** In `Character.fromJson`, add after the nimble line:
  ```dart
        drawSteel: DrawSteelSheet.maybeFromJson(j['drawSteel']),
  ```

- [ ] **Step 6: Run tests — expect PASS**

  Run: `flutter test test/draw_steel_sheet_test.dart`

  The blurb test will fail until Task 4 (home_shell). Skip it for now with `skip: 'needs kSystemBlurbs entry'` by temporarily commenting it out. All other tests must pass.

  Run: `flutter analyze` → expect `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add lib/engine/models.dart test/draw_steel_sheet_test.dart
git commit -m "feat(draw-steel): DrawSteelSheet model + Character.drawSteel field

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 2: `addDrawSteel()` in CharacterNotifier

**Files:**
- Modify: `lib/state/providers.dart` (~after `addNimble`, line ~318)

- [ ] **Step 1: Implement `addDrawSteel()`**

  In `lib/state/providers.dart`, add after the `addNimble()` method:

```dart
  /// Creates a pre-made Draw Steel hero at the top and returns its id.
  Future<String> addDrawSteel() async {
    final id = _newId();
    await _persist([
      Character(
          id: id,
          name: 'New Draw Steel hero',
          drawSteel: const DrawSteelSheet()),
      ...await _ready,
    ]);
    return id;
  }
```

- [ ] **Step 2: Run tests**

  Run: `flutter test test/draw_steel_sheet_test.dart`
  Run: `flutter analyze`
  Both must pass.

- [ ] **Step 3: Commit**

```bash
git add lib/state/providers.dart
git commit -m "feat(draw-steel): addDrawSteel() in CharacterNotifier

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 3: DrawSteelSheetView

**Files:**
- Create: `lib/features/draw_steel_sheet.dart`
- Create: `test/draw_steel_sheet_ui_test.dart`

- [ ] **Step 1: Write failing widget tests**

  Create `test/draw_steel_sheet_ui_test.dart`:

```dart
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/features/draw_steel_sheet.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _pumpSheet(WidgetTester tester,
    {Character? character}) async {
  final sheet = DrawSteelSheet(
    className: kDrawSteelClasses.first,
    maxStamina: 30,
    currentStamina: 20,
    maxRecoveries: 8,
    recoveries: 8,
  );
  final charJson = character != null
      ? jsonEncode([character.toJson()])
      : jsonEncode([
          {
            'id': 'c1',
            'name': 'Kael',
            'stats': [],
            'tracks': [],
            'tags': [],
            'drawSteel': sheet.toJson(),
          }
        ]);
  SharedPreferences.setMockInitialValues({
    'juice.sessions.v1':
        '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    'juice.characters.v1.default': charJson,
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
                ref.watch(charactersProvider).valueOrNull?.firstOrNull ??
                    char;
            return DrawSteelSheetView(character: live, onBack: () {});
          })))));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  setUp(() {});

  testWidgets('draw-steel-sheet key renders', (tester) async {
    tester.view.physicalSize = const Size(1200, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpSheet(tester);
    expect(find.byKey(const Key('draw-steel-sheet')), findsOneWidget);
    expect(find.text('Kael'), findsOneWidget);
    expect(find.text('Draw Steel'), findsOneWidget);
  });

  testWidgets('stamina stepper persists', (tester) async {
    tester.view.physicalSize = const Size(1200, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final c = await _pumpSheet(tester);

    await tester.tap(find.byKey(const Key('draw-steel-stamina-minus')));
    await tester.pumpAndSettle();

    final chars = await c.read(charactersProvider.future);
    expect(chars.single.drawSteel!.currentStamina, 19);
  });

  testWidgets('roll button shows snackbar with tier', (tester) async {
    tester.view.physicalSize = const Size(1200, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpSheet(tester);

    // Tap any roll button — might is the first characteristic.
    await tester.tap(find.byKey(const Key('draw-steel-roll-might')));
    await tester.pump(); // trigger snackbar animation
    await tester.pump(const Duration(milliseconds: 300));

    // A snackbar should appear containing "Tier" (1, 2, or 3).
    expect(find.textContaining('Tier'), findsOneWidget);
  });

  testWidgets('class dropdown changes class', (tester) async {
    tester.view.physicalSize = const Size(1200, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final c = await _pumpSheet(tester);

    // Pick the second class in the list.
    final second = kDrawSteelClasses[1];
    await tester.tap(find.byKey(const Key('draw-steel-class')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(second).last);
    await tester.pumpAndSettle();

    final chars = await c.read(charactersProvider.future);
    expect(chars.single.drawSteel!.className, second);
  });

  testWidgets('sheet-back fires onBack', (tester) async {
    tester.view.physicalSize = const Size(1200, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var backCalled = false;
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.characters.v1.default': jsonEncode([
        {
          'id': 'c1',
          'name': 'Kael',
          'stats': [],
          'tracks': [],
          'tags': [],
          'drawSteel': const DrawSteelSheet().toJson(),
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
                body: DrawSteelSheetView(
                    character: char,
                    onBack: () => backCalled = true)))));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sheet-back')));
    await tester.pumpAndSettle();
    expect(backCalled, isTrue);
  });
}
```

- [ ] **Step 2: Run to confirm tests fail**

  Run: `flutter test test/draw_steel_sheet_ui_test.dart`
  Expected: FAIL — `DrawSteelSheetView` undefined.

- [ ] **Step 3: Create `lib/features/draw_steel_sheet.dart`**

```dart
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../state/providers.dart';
import 'sheet_widgets.dart';

/// Facts-only Draw Steel sheet. Class/characteristic NAMES are authored
/// constants (non-copyrightable game-mechanic facts); all values are
/// player-editable. Published under the Draw Steel Creator License;
/// not affiliated with MCDM Productions, LLC.
class DrawSteelSheetView extends ConsumerWidget {
  const DrawSteelSheetView(
      {super.key, required this.character, required this.onBack});
  final Character character;
  final VoidCallback onBack;

  DrawSteelSheet get _s => character.drawSteel!;

  void _save(WidgetRef ref, DrawSteelSheet next) => ref
      .read(charactersProvider.notifier)
      .replace(character.copyWith(drawSteel: next));

  Widget _stepper(
    String key,
    String label,
    int value, {
    required ValueChanged<int> onSet,
    int min = 0,
    int max = 9999,
  }) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        if (label.isNotEmpty) Text('$label '),
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

  void _roll(BuildContext context, String charKey) {
    final score = _s.characteristics[charKey] ?? 0;
    final rng = Random();
    final total = rng.nextInt(10) + 1 + rng.nextInt(10) + 1 + score;
    final tier = total <= 11 ? 'Tier 1' : total <= 16 ? 'Tier 2' : 'Tier 3';
    final label = charKey[0].toUpperCase() + charKey.substring(1);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label: $total — $tier'),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final s = _s;
    return ListView(
      key: const Key('draw-steel-sheet'),
      padding: const EdgeInsets.all(12),
      children: [
        // ── Header ──────────────────────────────────────────────────────────
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
        Text('Draw Steel', style: theme.textTheme.labelSmall),
        const SizedBox(height: 8),

        // ── Class + Ancestry + Level ─────────────────────────────────────────
        DropdownButton<String>(
          key: const Key('draw-steel-class'),
          isExpanded: true,
          value: kDrawSteelClasses.contains(s.className)
              ? s.className
              : kDrawSteelClasses.first,
          items: [
            for (final c in kDrawSteelClasses)
              DropdownMenuItem(value: c, child: Text(c)),
          ],
          onChanged: (v) =>
              v == null ? null : _save(ref, s.copyWith(className: v)),
        ),
        TextFormField(
          key: const Key('draw-steel-ancestry'),
          initialValue: s.ancestry,
          decoration: const InputDecoration(labelText: 'Ancestry'),
          onChanged: (v) => _save(ref, s.copyWith(ancestry: v)),
        ),
        const SizedBox(height: 8),
        _stepper('draw-steel-level', 'Level', s.level,
            min: 1, max: 10, onSet: (v) => _save(ref, s.copyWith(level: v))),

        // ── Characteristics + Power Roll ────────────────────────────────────
        const SizedBox(height: 12),
        Text('Characteristics', style: theme.textTheme.titleMedium),
        const Text(
          'Power roll: 2d10 + characteristic → Tier 1 (≤11) / Tier 2 (12–16) / Tier 3 (≥17)',
          style: TextStyle(fontSize: 11),
        ),
        const SizedBox(height: 4),
        for (final k in kDrawSteelCharacteristics)
          Row(children: [
            SizedBox(
              width: 80,
              child: Text(k[0].toUpperCase() + k.substring(1)),
            ),
            _stepper(
              'draw-steel-char-$k',
              '',
              s.characteristics[k] ?? 0,
              min: -5,
              max: 5,
              onSet: (v) =>
                  _save(ref, s.copyWith(characteristics: {...s.characteristics, k: v})),
            ),
            const Spacer(),
            IconButton(
              key: Key('draw-steel-roll-$k'),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.casino_outlined, size: 18),
              tooltip: 'Roll 2d10 + $k',
              onPressed: () => _roll(context, k),
            ),
          ]),

        // ── Stamina ──────────────────────────────────────────────────────────
        const SizedBox(height: 12),
        Text('Stamina', style: theme.textTheme.titleMedium),
        Wrap(spacing: 16, runSpacing: 8, children: [
          _stepper('draw-steel-stamina', 'Current', s.currentStamina,
              max: s.maxStamina,
              onSet: (v) => _save(ref, s.copyWith(currentStamina: v))),
          _stepper('draw-steel-max-stamina', 'Max', s.maxStamina,
              onSet: (v) => _save(ref, s.copyWith(maxStamina: v))),
        ]),

        // ── Recoveries ───────────────────────────────────────────────────────
        const SizedBox(height: 12),
        Text('Recoveries', style: theme.textTheme.titleMedium),
        Wrap(spacing: 16, runSpacing: 8, children: [
          _stepper('draw-steel-recoveries', 'Used', s.recoveries,
              onSet: (v) => _save(ref, s.copyWith(recoveries: v))),
          _stepper('draw-steel-max-recoveries', 'Max', s.maxRecoveries,
              onSet: (v) => _save(ref, s.copyWith(maxRecoveries: v))),
        ]),

        // ── Stability ────────────────────────────────────────────────────────
        const SizedBox(height: 12),
        _stepper('draw-steel-stability', 'Stability', s.stability,
            onSet: (v) => _save(ref, s.copyWith(stability: v))),

        // ── Heroic Resource ──────────────────────────────────────────────────
        const SizedBox(height: 12),
        Text(s.resourceLabel, style: theme.textTheme.titleMedium),
        _stepper('draw-steel-resource', '', s.heroicResource,
            onSet: (v) => _save(ref, s.copyWith(heroicResource: v))),

        // ── Conditions ───────────────────────────────────────────────────────
        const SizedBox(height: 12),
        conditionsSection(context, ref, character, 'draw-steel'),

        // ── Skills + Notes ───────────────────────────────────────────────────
        const SizedBox(height: 12),
        TextFormField(
          key: const Key('draw-steel-skills'),
          initialValue: s.skills,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Skills'),
          onChanged: (v) => _save(ref, s.copyWith(skills: v)),
        ),
        TextFormField(
          key: const Key('draw-steel-notes'),
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

- [ ] **Step 4: Run tests — expect PASS**

  Run: `flutter test test/draw_steel_sheet_ui_test.dart`
  Run: `flutter analyze` → expect `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/features/draw_steel_sheet.dart test/draw_steel_sheet_ui_test.dart
git commit -m "feat(draw-steel): DrawSteelSheetView with per-characteristic power-roll buttons

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 4: System wiring

**Files:**
- Modify: `lib/engine/system_primer.dart`
- Modify: `lib/features/tracker_screen.dart`
- Modify: `lib/shared/home_shell.dart`
- Modify: `lib/features/encounter_screen.dart`

All four edits are small additions following existing patterns; commit once at the end of this task.

- [ ] **Step 1: Add primer in `lib/engine/system_primer.dart`**

  In `kSystemPrimers`, add after the `'nimble'` entry:
  ```dart
    'draw-steel':
        'Draw Steel: cinematic tactical fantasy. Resolution: power roll 2d10+characteristic → Tier 1 (≤11), Tier 2 (12-16), Tier 3 (≥17); heroic resources; stamina and recoveries.',
  ```

  In `resolveSystemPrimer`, add after the `nimble` check:
  ```dart
    if (systems.contains('draw-steel')) return kSystemPrimers['draw-steel']!;
  ```

  In `resolveSystem`, add after the `nimble` check:
  ```dart
    if (systems.contains('draw-steel')) return 'draw-steel';
  ```

  Verify the primer stays under `kSystemPrimerMaxChars` (220 chars): count the 'draw-steel' string.

- [ ] **Step 2: Add render branch in `lib/features/tracker_screen.dart`**

  **2a.** At the top of the file, add the import after `nimble_sheet.dart`:
  ```dart
  import 'draw_steel_sheet.dart';
  ```

  **2b.** In `_CharacterSheetTabState.build`, find the block:
  ```dart
              if (c.nimble != null) {
                return NimbleSheetView(
  ```
  Add a new block immediately BEFORE it:
  ```dart
              if (c.drawSteel != null) {
                return DrawSteelSheetView(
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

  **2c.** In `_onAdd`, find:
  ```dart
        !systems.contains('nimble')) {
  ```
  Change to:
  ```dart
        !systems.contains('nimble') &&
        !systems.contains('draw-steel')) {
  ```

  **2d.** In the `options` list, add after the `nimble` entry:
  ```dart
      if (systems.contains('draw-steel'))
        (
          key: 'new-draw-steel',
          value: 'draw-steel',
          label: 'Draw Steel',
          blurb: 'Characteristics, stamina, heroic resource, power rolls.'
        ),
  ```

  **2e.** In the picker-hint condition (the `if (!systems.contains('dnd') || ...` text block), add `draw-steel`:
  ```dart
                  if (!systems.contains('dnd') ||
                      !systems.contains('shadowdark') ||
                      !systems.contains('nimble') ||
                      !systems.contains('draw-steel'))
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                      child: Text(
                        'Enable D&D 5e, Shadowdark, Nimble, or Draw Steel in '
                        'Campaigns → Edit systems to add those sheets.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
  ```

  **2f.** In the `choice` dispatch (the `if (choice == 'generic')` chain), add:
  ```dart
    } else if (choice == 'draw-steel') {
      await _newDrawSteel();
    }
  ```

  **2g.** Add the `_newDrawSteel` method after `_newNimble`:
  ```dart
    Future<void> _newDrawSteel() async {
      final id = await ref.read(charactersProvider.notifier).addDrawSteel();
      if (mounted) setState(() => _editingId = id);
    }
  ```

- [ ] **Step 3: Add toggle + blurb in `lib/shared/home_shell.dart`**

  **3a.** In `kSystemBlurbs`, add after the `'nimble'` entry:
  ```dart
    'draw-steel':
        'Draw Steel hero sheet: characteristics, stamina, heroic resource, power rolls. '
        'Independent product; not affiliated with MCDM Productions, LLC.',
  ```

  **3b.** In `NewCampaignDialog`, find `bool _nimble = false;` and add after it:
  ```dart
  bool _drawSteel = false;
  ```

  **3c.** In `NewCampaignDialog`'s system list builder, find `if (_nimble) 'nimble',` and add:
  ```dart
  if (_drawSteel) 'draw-steel',
  ```

  **3d.** In `NewCampaignDialog`'s UI, find the `sys-nimble` SwitchListTile block and add after it:
  ```dart
              SwitchListTile(
                key: const Key('sys-draw-steel'),
                title: const Text('Draw Steel'),
                subtitle: Text(kSystemBlurbs['draw-steel']!),
                value: _drawSteel,
                onChanged: (v) => setState(() => _drawSteel = v ?? false),
              ),
  ```

  **3e.** In `_EditSystemsDialog`, find `_row('nimble', 'Nimble'),` and add:
  ```dart
              _row('draw-steel', 'Draw Steel'),
  ```

- [ ] **Step 4: Add HP read-through in `lib/features/encounter_screen.dart`**

  Find the block:
  ```dart
          } else if (linked.nimble != null) {
            curHp = linked.nimble!.currentHp;
            maxHp = linked.nimble!.maxHp;
  ```
  Add immediately after it (before the `} else if (linked.tracks.isNotEmpty)` block):
  ```dart
          } else if (linked.drawSteel != null) {
            curHp = linked.drawSteel!.currentStamina;
            maxHp = linked.drawSteel!.maxStamina;
  ```

- [ ] **Step 5: Run full suite**

  Run: `flutter analyze` → expect `No issues found!`
  Run: `flutter test` → all tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/engine/system_primer.dart lib/features/tracker_screen.dart \
        lib/shared/home_shell.dart lib/features/encounter_screen.dart
git commit -m "feat(draw-steel): system wiring — primer, tracker, home-shell, encounter

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 5: MCDM disclaimer + enable blurb test + CLAUDE.md

**Files:**
- Modify: `lib/features/settings_sheet.dart`
- Modify: `test/draw_steel_sheet_test.dart` (re-enable the kSystemBlurbs test)
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add MCDM disclaimer in `lib/features/settings_sheet.dart`**

  At the end of `_SettingsSheet.build`'s `Column` children list, after the AI section, add:

```dart
            const SizedBox(height: 16),
            Text('Third-party content', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            const Text(
              'Draw Steel content is an independent product published under '
              'the Draw Steel Creator License and is not affiliated with '
              'MCDM Productions, LLC.',
              style: TextStyle(fontSize: 12),
            ),
```

- [ ] **Step 2: Re-enable the blurb test**

  In `test/draw_steel_sheet_test.dart`, remove the `skip:` comment from the `kSystemBlurbs` test.

  Run: `flutter test test/draw_steel_sheet_test.dart` → all pass.

- [ ] **Step 3: Update CLAUDE.md**

  In `CLAUDE.md`, find the bullet that describes the Nimble sheet (starts "A facts-only **Nimble** sheet"). Add a new bullet after it:

```
- A facts-only **Draw Steel** sheet (`lib/features/draw_steel_sheet.dart`, rendered when
  `Character.drawSteel` is set; opt-in `draw-steel` system, NOT in `kAllSystems`) follows
  the Nimble facts-only approach: authored mechanic constants only
  (`kDrawSteelCharacteristics` / `kDrawSteelClasses` / `kDrawSteelHeroicResource`) with
  ancestry/skills/notes freeform. Per-characteristic **power roll** buttons (2d10 + score
  → snackbar: "Might: 14 — Tier 2"; tiers ≤11/12-16/≥17; ephemeral, no journal log).
  **Licensing:** Draw Steel Creator License (MCDM) permits apps + commercial use; required
  non-affiliation statement appears in `kSystemBlurbs['draw-steel']` + settings sheet. See
  `docs/superpowers/specs/2026-06-24-draw-steel-sheet-design.md`.
```

- [ ] **Step 4: Full verification**

  Run: `flutter analyze` → expect `No issues found!`
  Run: `flutter test` → all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/features/settings_sheet.dart test/draw_steel_sheet_test.dart CLAUDE.md
git commit -m "feat(draw-steel): MCDM disclaimer in settings + CLAUDE.md note

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:**
- Constants (kDrawSteelCharacteristics / kDrawSteelClasses / kDrawSteelHeroicResource) → Task 1 ✓
- DrawSteelSheet model (copyWith clamps, toJson, maybeFromJson, resourceLabel) → Task 1 ✓
- Character.drawSteel field (ctor/copyWith/toJson/fromJson/withHpDelta) → Task 1 ✓
- addDrawSteel() → Task 2 ✓
- DrawSteelSheetView (all sections, roll buttons, snackbar) → Task 3 ✓
- system_primer draw-steel entry → Task 4 ✓
- tracker_screen render branch + new-draw-steel → Task 4 ✓
- home_shell sys-draw-steel toggle + kSystemBlurbs → Task 4 ✓
- encounter_screen HP branch (currentStamina/maxStamina) → Task 4 ✓
- MCDM non-affiliation in kSystemBlurbs + settings → Task 4 + Task 5 ✓
- CLAUDE.md → Task 5 ✓

**Placeholder scan:** Constants include `// VERIFY` comments with instructions; these are actionable research steps (Task 1, Step 1), not vague "TBD" placeholders. All code blocks are complete.

**Type consistency:**
- `DrawSteelSheet.currentStamina` / `maxStamina` used in `withHpDelta` (Task 1), encounter_screen (Task 4), and tests ✓
- `kDrawSteelClasses` referenced in `DrawSteelSheet.copyWith` (Task 1) and `DrawSteelSheetView` (Task 3) ✓
- `character.drawSteel` accessed as non-null (`character.drawSteel!`) inside branches that check `c.drawSteel != null` ✓
- `addDrawSteel()` in `providers.dart` (Task 2) called from `tracker_screen._newDrawSteel()` (Task 4) ✓
- `draw-steel` system key consistent across all files ✓
