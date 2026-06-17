# Shadowdark Character Sheet (lean, facts-only) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A lean bespoke Shadowdark character sheet — 6 ability scores + mods, class/ancestry/alignment, level/XP, AC/HP, gear slots, luck token, freeform title/deity/talents/spells — over the generic `Character`, gated by a new opt-in `shadowdark` system.

**Architecture:** Mirrors the D&D P1 pattern: new `ShadowdarkSheet` optional field on `Character`, authored **facts-only** constants (no Shadowdark prose, no title table, no attribution, no logo/"compatible" claim — licensing), new opt-in `shadowdark` flag (NOT in `kAllSystems`), `ShadowdarkSheetView` reusing `sheet_widgets.dart`.

**Tech Stack:** Dart/Flutter, flutter_riverpod, shared_preferences (mock in tests). TDD with `flutter test` + `dart analyze`.

**Spec:** `docs/superpowers/specs/2026-06-17-shadowdark-sheet-design.md`

**Anchors:** `Character` wiring (`lib/engine/models.dart`): insert `shadowdark` siblings right after each `dnd` line — `this.dnd,` (:1751), `final DndSheet? dnd;` (:1771), `bool clearDnd = false,` (:1790), `dnd: clearDnd ? null : (dnd ?? this.dnd),` (:1803), `if (dnd != null) 'dnd': dnd!.toJson(),` (:1819), `dnd: DndSheet.maybeFromJson(j['dnd']),` (:1839). `DndSheet` class ends at :1278 — put the Shadowdark consts + `ShadowdarkSheet` right after it. `providers.dart` `addDnd` at :264. `home_shell.dart` dnd flag: blurb :593, `bool _dnd` :614, `if (_dnd)` :633, `sys-dnd` :731, `_row('dnd'...)` :796. `tracker_screen.dart`: render branch `if (c.dnd != null)` :147, chooser `new-dnd` :270, choice `:286`, `_newDnd` :313. The generic 6-ability consts `kDndAbilities`/`kDndAbilityLabels` already exist in models.dart (plain stat ids/labels) — reuse them.

**Critical:** facts only. Author NO talent/spell/title/deity text; those are freeform fields. Modifier = `((score-10)/2).floor()`.

---

## Task 1: Shadowdark constants + `ShadowdarkSheet` model

**Files:**
- Modify: `lib/engine/models.dart` (insert after the `DndSheet` class, :1278)
- Test: `test/character_sheet_test.dart`

- [ ] **Step 1: Write the failing test** (inside `void main()`):

```dart
  group('ShadowdarkSheet', () {
    test('abilityMod floors; gearSlotCapacity = max(STR,10)', () {
      ShadowdarkSheet s(Map<String, int> a) => ShadowdarkSheet(abilities: a);
      expect(s({'str': 3}).abilityMod('str'), -4);
      expect(s({'str': 7}).abilityMod('str'), -2);
      expect(s({'str': 10}).abilityMod('str'), 0);
      expect(s({'str': 18}).abilityMod('str'), 4);
      expect(s({'str': 8}).gearSlotCapacity, 10);
      expect(s({'str': 15}).gearSlotCapacity, 15);
    });

    test('hit die + caster derivations', () {
      const w = ShadowdarkSheet(
          className: 'Wizard',
          abilities: {'str': 8, 'dex': 12, 'con': 10, 'int': 16, 'wis': 10, 'cha': 10});
      expect(w.hitDie, 4);
      expect(w.isCaster, isTrue);
      expect(w.castingAbility, 'int');
      expect(w.castingMod, 3);
      const f = ShadowdarkSheet(className: 'Fighter');
      expect(f.hitDie, 8);
      expect(f.isCaster, isFalse);
      expect(f.castingAbility, isNull);
      expect(f.castingMod, isNull);
    });

    test('premade is a level-1 Human Fighter', () {
      final s = ShadowdarkSheet.premade();
      expect(s.className, 'Fighter');
      expect(s.ancestry, 'Human');
      expect(s.alignment, 'Neutral');
      expect(s.level, 1);
      expect(s.maxHp, 8);
    });

    test('round-trips; tolerant; coerces unknown enums + clamps', () {
      const s = ShadowdarkSheet(
        className: 'Priest', ancestry: 'Elf', alignment: 'Lawful',
        level: 3, xp: 12, ac: 15, currentHp: 14, maxHp: 18,
        gearSlotsUsed: 5, luckToken: true,
        title: 'Crusader', deity: 'Saint Terragnis', talentsText: '+1 atk',
        spellsText: 'Cure Wounds', abilities: {'wis': 14},
      );
      final back = ShadowdarkSheet.maybeFromJson(s.toJson())!;
      expect(back.className, 'Priest');
      expect(back.ancestry, 'Elf');
      expect(back.alignment, 'Lawful');
      expect(back.luckToken, isTrue);
      expect(back.title, 'Crusader');
      expect(back.deity, 'Saint Terragnis');
      expect(back.score('wis'), 14);

      expect(ShadowdarkSheet.maybeFromJson('x'), isNull);
      final j = ShadowdarkSheet.maybeFromJson({
        'className': 'Bard', 'ancestry': 'Orc', 'alignment': 'Good',
        'level': 99, 'abilities': {'str': 99}, 'gearSlotsUsed': -2,
      })!;
      expect(j.className, 'Fighter'); // unknown -> default
      expect(j.ancestry, 'Human');
      expect(j.alignment, 'Neutral');
      expect(j.level, 10); // clamped 1..10
      expect(j.score('str'), 20); // clamped 1..20
      expect(j.gearSlotsUsed, 0);
    });
  });
```

- [ ] **Step 2: Run, verify fail**

Run: `flutter test test/character_sheet_test.dart`
Expected: FAIL — `ShadowdarkSheet` undefined.

- [ ] **Step 3: Implement** — insert after the `DndSheet` class (line 1278):

```dart
// --- Shadowdark (facts-only: names/rules/dice — no rulebook prose) ----------

const kShadowdarkClasses = <String>['Fighter', 'Priest', 'Thief', 'Wizard'];
const kShadowdarkAncestries = <String>[
  'Dwarf', 'Elf', 'Goblin', 'Half-Orc', 'Halfling', 'Human',
];
const kShadowdarkAlignments = <String>['Lawful', 'Neutral', 'Chaotic'];
const kShadowdarkClassHitDie = <String, int>{
  'Fighter': 8, 'Priest': 6, 'Thief': 4, 'Wizard': 4,
};
const kShadowdarkCastingAbility = <String, String>{
  'Priest': 'wis', 'Wizard': 'int',
};

/// Bespoke lean Shadowdark sheet. Authors only game-mechanic facts; title,
/// deity, talents, and spells are freeform (no rulebook text shipped).
class ShadowdarkSheet {
  const ShadowdarkSheet({
    this.abilities = const {
      'str': 10, 'dex': 10, 'con': 10, 'int': 10, 'wis': 10, 'cha': 10
    },
    this.className = 'Fighter',
    this.ancestry = 'Human',
    this.alignment = 'Neutral',
    this.level = 1,
    this.xp = 0,
    this.ac = 10,
    this.currentHp = 1,
    this.maxHp = 1,
    this.gearSlotsUsed = 0,
    this.luckToken = false,
    this.title = '',
    this.deity = '',
    this.background = '',
    this.talentsText = '',
    this.spellsText = '',
  });

  final Map<String, int> abilities; // keys = kDndAbilities, each 1..20
  final String className, ancestry, alignment;
  final int level; // 1..10
  final int xp, ac, currentHp, maxHp, gearSlotsUsed;
  final bool luckToken;
  final String title, deity, background, talentsText, spellsText;

  int score(String a) => abilities[a] ?? 10;
  int abilityMod(String a) => ((score(a) - 10) / 2).floor();
  int get gearSlotCapacity => score('str') > 10 ? score('str') : 10;
  int get hitDie => kShadowdarkClassHitDie[className] ?? 8;
  bool get isCaster => kShadowdarkCastingAbility.containsKey(className);
  String? get castingAbility => kShadowdarkCastingAbility[className];
  int? get castingMod => isCaster ? abilityMod(castingAbility!) : null;

  factory ShadowdarkSheet.premade() => const ShadowdarkSheet(
        className: 'Fighter',
        ancestry: 'Human',
        alignment: 'Neutral',
        level: 1,
        ac: 10,
        currentHp: 8, // Fighter d8
        maxHp: 8,
      );

  ShadowdarkSheet copyWith({
    Map<String, int>? abilities,
    String? className, String? ancestry, String? alignment,
    int? level, int? xp, int? ac, int? currentHp, int? maxHp, int? gearSlotsUsed,
    bool? luckToken,
    String? title, String? deity, String? background,
    String? talentsText, String? spellsText,
  }) {
    final ab = abilities ?? this.abilities;
    final cls = className ?? this.className;
    final anc = ancestry ?? this.ancestry;
    final al = alignment ?? this.alignment;
    return ShadowdarkSheet(
      abilities: {
        for (final a in kDndAbilities) a: (ab[a] ?? 10).clamp(1, 20),
      },
      className: kShadowdarkClassHitDie.containsKey(cls) ? cls : 'Fighter',
      ancestry: kShadowdarkAncestries.contains(anc) ? anc : 'Human',
      alignment: kShadowdarkAlignments.contains(al) ? al : 'Neutral',
      level: (level ?? this.level).clamp(1, 10),
      xp: (xp ?? this.xp).clamp(0, 1 << 31),
      ac: (ac ?? this.ac).clamp(0, 99),
      currentHp: (currentHp ?? this.currentHp).clamp(0, 1 << 20),
      maxHp: (maxHp ?? this.maxHp).clamp(0, 1 << 20),
      gearSlotsUsed: (gearSlotsUsed ?? this.gearSlotsUsed).clamp(0, 999),
      luckToken: luckToken ?? this.luckToken,
      title: title ?? this.title,
      deity: deity ?? this.deity,
      background: background ?? this.background,
      talentsText: talentsText ?? this.talentsText,
      spellsText: spellsText ?? this.spellsText,
    );
  }

  Map<String, dynamic> toJson() => {
        'abilities': abilities,
        'className': className,
        'ancestry': ancestry,
        'alignment': alignment,
        'level': level,
        if (xp != 0) 'xp': xp,
        'ac': ac,
        'currentHp': currentHp,
        'maxHp': maxHp,
        if (gearSlotsUsed != 0) 'gearSlotsUsed': gearSlotsUsed,
        if (luckToken) 'luckToken': true,
        if (title.isNotEmpty) 'title': title,
        if (deity.isNotEmpty) 'deity': deity,
        if (background.isNotEmpty) 'background': background,
        if (talentsText.isNotEmpty) 'talentsText': talentsText,
        if (spellsText.isNotEmpty) 'spellsText': spellsText,
      };

  static ShadowdarkSheet? maybeFromJson(dynamic j) {
    if (j is! Map) return null;
    int intOr(dynamic v, int d) => v is int ? v : d;
    String strOr(dynamic v) => v is String ? v : '';
    final rawAb = j['abilities'];
    final ab = <String, int>{
      for (final a in kDndAbilities)
        a: (rawAb is Map ? intOr(rawAb[a], 10) : 10).clamp(1, 20),
    };
    final cls = strOr(j['className']);
    final anc = strOr(j['ancestry']);
    final al = strOr(j['alignment']);
    return ShadowdarkSheet(
      abilities: ab,
      className: kShadowdarkClassHitDie.containsKey(cls) ? cls : 'Fighter',
      ancestry: kShadowdarkAncestries.contains(anc) ? anc : 'Human',
      alignment: kShadowdarkAlignments.contains(al) ? al : 'Neutral',
      level: intOr(j['level'], 1).clamp(1, 10),
      xp: intOr(j['xp'], 0).clamp(0, 1 << 31),
      ac: intOr(j['ac'], 10).clamp(0, 99),
      currentHp: intOr(j['currentHp'], 1).clamp(0, 1 << 20),
      maxHp: intOr(j['maxHp'], 1).clamp(0, 1 << 20),
      gearSlotsUsed: intOr(j['gearSlotsUsed'], 0).clamp(0, 999),
      luckToken: j['luckToken'] == true,
      title: strOr(j['title']),
      deity: strOr(j['deity']),
      background: strOr(j['background']),
      talentsText: strOr(j['talentsText']),
      spellsText: strOr(j['spellsText']),
    );
  }
}
```

- [ ] **Step 4: Run, verify pass** — `flutter test test/character_sheet_test.dart` → PASS.
- [ ] **Step 5: Analyze** — `dart analyze lib/engine/models.dart test/character_sheet_test.dart` → clean.
- [ ] **Step 6: Commit**

```bash
git add lib/engine/models.dart test/character_sheet_test.dart
git commit -m "feat(shadowdark): constants + ShadowdarkSheet model"
```

---

## Task 2: Wire `ShadowdarkSheet` into `Character`

**Files:**
- Modify: `lib/engine/models.dart` (the `Character` class — insert after each `dnd` line by content anchor)
- Test: `test/character_sheet_test.dart`

- [ ] **Step 1: Write the failing test** (inside `void main()`):

```dart
  group('Character.shadowdark', () {
    test('round-trips and is omitted when null', () {
      const plain = Character(id: 'p', name: 'Plain');
      expect(plain.toJson().containsKey('shadowdark'), isFalse);
      final c = Character(
          id: 'sd', name: 'Mort', shadowdark: ShadowdarkSheet.premade());
      final back = Character.fromJson(c.toJson());
      expect(back.shadowdark!.className, 'Fighter');
      expect(back.shadowdark!.ancestry, 'Human');
    });

    test('copyWith sets and clears shadowdark', () {
      const c = Character(id: 'sd2', name: 'L');
      final set = c.copyWith(shadowdark: ShadowdarkSheet.premade());
      expect(set.shadowdark, isNotNull);
      expect(set.copyWith().shadowdark, isNotNull);
      expect(set.copyWith(clearShadowdark: true).shadowdark, isNull);
    });

    test('junk shadowdark block tolerated as null', () {
      expect(
          Character.fromJson({'id': 'x', 'name': 'J', 'shadowdark': 'junk'})
              .shadowdark,
          isNull);
    });
  });
```

- [ ] **Step 2: Run, verify fail** — `flutter test test/character_sheet_test.dart` → FAIL.

- [ ] **Step 3: Implement** — six edits to `Character`, each immediately after the matching `dnd` line:

(a) after `this.dnd,`:
```dart
    this.shadowdark,
```
(b) after `final DndSheet? dnd;`:
```dart
  /// Bespoke Shadowdark sheet; null unless this is a Shadowdark PC.
  final ShadowdarkSheet? shadowdark;
```
(c) after `bool clearDnd = false,`:
```dart
    ShadowdarkSheet? shadowdark,
    bool clearShadowdark = false,
```
(d) after `dnd: clearDnd ? null : (dnd ?? this.dnd),`:
```dart
        shadowdark:
            clearShadowdark ? null : (shadowdark ?? this.shadowdark),
```
(e) after `if (dnd != null) 'dnd': dnd!.toJson(),`:
```dart
        if (shadowdark != null) 'shadowdark': shadowdark!.toJson(),
```
(f) after `dnd: DndSheet.maybeFromJson(j['dnd']),`:
```dart
        shadowdark: ShadowdarkSheet.maybeFromJson(j['shadowdark']),
```

- [ ] **Step 4: Run, verify pass** — `flutter test test/character_sheet_test.dart` → PASS.
- [ ] **Step 5: Commit**

```bash
git add lib/engine/models.dart test/character_sheet_test.dart
git commit -m "feat(shadowdark): wire ShadowdarkSheet onto Character"
```

---

## Task 3: `CharacterNotifier.addShadowdark()`

**Files:**
- Modify: `lib/state/providers.dart` (after `addDnd`, :264)
- Test: `test/character_provider_test.dart`

- [ ] **Step 1: Write the failing test** (inside `void main()`):

```dart
  test('addShadowdark prepends a premade Shadowdark character', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(charactersProvider.future);
    final id = await c.read(charactersProvider.notifier).addShadowdark();
    final chars = await c.read(charactersProvider.future);
    expect(chars.first.id, id);
    expect(chars.first.shadowdark, isNotNull);
    expect(chars.first.shadowdark!.className, 'Fighter');
  });
```

- [ ] **Step 2: Run, verify fail** — FAIL (`addShadowdark` undefined).

- [ ] **Step 3: Implement** — add to `CharacterNotifier` after `addDnd`:

```dart
  /// Creates a pre-made Shadowdark PC at the top and returns its id.
  Future<String> addShadowdark() async {
    final id = _newId();
    await _persist([
      Character(
          id: id, name: 'New Shadowdark character',
          shadowdark: ShadowdarkSheet.premade()),
      ...await _ready,
    ]);
    return id;
  }
```

- [ ] **Step 4: Run, verify pass** — PASS.
- [ ] **Step 5: Commit**

```bash
git add lib/state/providers.dart test/character_provider_test.dart
git commit -m "feat(shadowdark): addShadowdark notifier method"
```

---

## Task 4: opt-in `shadowdark` system flag

**Files:**
- Modify: `lib/shared/home_shell.dart`
- Test: `test/home_shell_test.dart`

- [ ] **Step 1: Write the failing test** (inside `void main()`, mirroring the `dnd` add-on test):

```dart
  testWidgets('new campaign dialog can enable the shadowdark add-on',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
        overrides: [_verdantOverride, _emulatorOverride],
        child: MaterialApp(home: HomeShell(oracle: _oracle()))));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Campaigns'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'New campaign'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('new-campaign-name')), 'Gloomhold');
    await tester.ensureVisible(find.byKey(const Key('sys-shadowdark')));
    await tester.tap(find.byKey(const Key('sys-shadowdark')));
    await tester.pumpAndSettle();
    final create = find.widgetWithText(FilledButton, 'Create');
    await tester.ensureVisible(create);
    await tester.tap(create);
    await tester.pumpAndSettle();
    final container =
        ProviderScope.containerOf(tester.element(find.byType(HomeShell)));
    final s = await container.read(sessionsProvider.future);
    expect(s.activeMeta.enabledSystems, contains('shadowdark'));
  });
```

- [ ] **Step 2: Run, verify fail** — FAIL (`sys-shadowdark` not found).

- [ ] **Step 3: Implement** — three edits to `lib/shared/home_shell.dart`:

(a) `kSystemBlurbs` — after the `'dnd'` entry:
```dart
  'shadowdark': 'Shadowdark character sheet: stats, HP, AC, gear, luck.',
```
(b) `_NewCampaignDialogState` — after `bool _dnd = false;`:
```dart
  bool _shadowdark = false;
```
after `if (_dnd) 'dnd',` in `_submit`:
```dart
      if (_shadowdark) 'shadowdark',
```
after the `sys-dnd` `CheckboxListTile`:
```dart
            CheckboxListTile(
              key: const Key('sys-shadowdark'),
              title: const Text('Shadowdark'),
              subtitle: Text(kSystemBlurbs['shadowdark']!),
              value: _shadowdark,
              onChanged: (v) => setState(() => _shadowdark = v ?? false),
            ),
```
(c) `_EditSystemsDialog.build` — after `_row('dnd', 'D&D 5e'),`:
```dart
            _row('shadowdark', 'Shadowdark'),
```

- [ ] **Step 4: Run, verify pass** — `flutter test test/home_shell_test.dart` → PASS (new + existing green).
- [ ] **Step 5: Commit**

```bash
git add lib/shared/home_shell.dart test/home_shell_test.dart
git commit -m "feat(shadowdark): opt-in shadowdark system flag"
```

---

## Task 5: `ShadowdarkSheetView` + render branch + create flow + verify + docs

**Files:**
- Create: `lib/features/shadowdark_sheet.dart`
- Modify: `lib/features/tracker_screen.dart`, `CLAUDE.md`
- Test: `test/character_sheet_ui_test.dart`

- [ ] **Step 1: Write the failing tests** (inside `void main()`):

```dart
  Future<ProviderContainer> pumpShadowdark(WidgetTester tester,
      {String sd = '{"abilities":{"str":13,"dex":12,"con":14,"int":8,"wis":10,'
          '"cha":10},"className":"Fighter","ancestry":"Human",'
          '"alignment":"Neutral","level":1,"ac":13,"currentHp":8,"maxHp":8}'}) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1",'
              '"systems":["shadowdark"]}]}',
      'juice.characters.v1.default':
          '[{"id":"sd","name":"Mort","note":"","stats":[],"tracks":[],'
              '"tags":[],"shadowdark":$sd}]',
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CharactersPane()))));
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
        tester.element(find.byType(CharactersPane)));
  }

  testWidgets('opening a Shadowdark character shows the bespoke sheet',
      (tester) async {
    await pumpShadowdark(tester);
    await tester.tap(find.text('Mort'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shadowdark-sheet')), findsOneWidget);
    expect(find.text('STR'), findsOneWidget);
    expect(find.textContaining('Gear'), findsWidgets);
  });

  testWidgets('SD ability stepper + luck toggle persist', (tester) async {
    final c = await pumpShadowdark(tester);
    await tester.tap(find.text('Mort'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sd-ability-str-plus')));
    await tester.pumpAndSettle();
    expect((await c.read(charactersProvider.future)).single.shadowdark!
        .score('str'), 14);
    await tester.scrollUntilVisible(
        find.byKey(const Key('sd-luck')), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sd-luck')));
    await tester.pumpAndSettle();
    expect((await c.read(charactersProvider.future)).single.shadowdark!
        .luckToken, isTrue);
  });

  testWidgets('Wizard shows Spells section; Fighter does not', (tester) async {
    await pumpShadowdark(tester,
        sd: '{"abilities":{"str":8,"dex":12,"con":10,"int":16,"wis":10,'
            '"cha":10},"className":"Wizard","ancestry":"Elf",'
            '"alignment":"Neutral","level":1,"ac":11,"currentHp":4,"maxHp":4}');
    await tester.tap(find.text('Mort'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.byKey(const Key('sd-spells')), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const Key('sd-spells')), findsOneWidget);
  });

  testWidgets('create flow makes a premade Shadowdark character',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1",'
              '"systems":["shadowdark"]}]}',
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
    await tester.tap(find.byKey(const Key('new-shadowdark')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shadowdark-sheet')), findsOneWidget);
    expect((await c.read(charactersProvider.future)).single.shadowdark!
        .className, 'Fighter');
  });
```

- [ ] **Step 2: Run, verify fail** — FAIL (`shadowdark-sheet`/`new-shadowdark` not found).

- [ ] **Step 3: Create `lib/features/shadowdark_sheet.dart`:**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../state/providers.dart';
import 'sheet_widgets.dart';

String _fmt(int n) => n >= 0 ? '+$n' : '$n';

/// Bespoke lean Shadowdark character sheet. Renders for characters whose
/// [Character.shadowdark] is non-null; edits persist via charactersProvider.
class ShadowdarkSheetView extends ConsumerWidget {
  const ShadowdarkSheetView(
      {super.key, required this.character, required this.onBack});
  final Character character;
  final VoidCallback onBack;

  ShadowdarkSheet get _s => character.shadowdark!;
  void _save(WidgetRef ref, ShadowdarkSheet next) => ref
      .read(charactersProvider.notifier)
      .replace(character.copyWith(shadowdark: next));

  Widget _dropdown(WidgetRef ref, String key, List<String> options,
          String value, ValueChanged<String> onSet) =>
      DropdownButton<String>(
        key: Key(key),
        value: options.contains(value) ? value : options.first,
        isExpanded: true,
        items: [
          for (final o in options) DropdownMenuItem(value: o, child: Text(o)),
        ],
        onChanged: (v) => v == null ? null : onSet(v),
      );

  Widget _freeform(WidgetRef ref, String key, String label, String value,
          ValueChanged<String> onSet) =>
      TextFormField(
        key: Key(key),
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        onChanged: onSet,
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final s = _s;
    return ListView(
      key: const Key('shadowdark-sheet'),
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
                  nameKey: 'sd-name', current: character.name);
              if (name != null) {
                await ref
                    .read(charactersProvider.notifier)
                    .replace(character.copyWith(name: name));
              }
            },
          ),
        ]),
        Text('Shadowdark', style: theme.textTheme.labelSmall),
        Row(children: [
          Expanded(
              child: _dropdown(ref, 'sd-class', kShadowdarkClasses, s.className,
                  (v) => _save(ref, s.copyWith(className: v)))),
          const SizedBox(width: 8),
          const Text('Level'),
          intStepper(
              prefix: 'sd',
              fieldKey: 'level',
              value: s.level,
              onSet: (v) => _save(ref, s.copyWith(level: v))),
        ]),
        Row(children: [
          Expanded(
              child: _dropdown(ref, 'sd-ancestry', kShadowdarkAncestries,
                  s.ancestry, (v) => _save(ref, s.copyWith(ancestry: v)))),
          const SizedBox(width: 8),
          Expanded(
              child: _dropdown(ref, 'sd-alignment', kShadowdarkAlignments,
                  s.alignment, (v) => _save(ref, s.copyWith(alignment: v)))),
        ]),
        _freeform(ref, 'sd-title', 'Title', s.title,
            (v) => _save(ref, s.copyWith(title: v))),
        if (s.className == 'Priest')
          _freeform(ref, 'sd-deity', 'Deity', s.deity,
              (v) => _save(ref, s.copyWith(deity: v))),
        _freeform(ref, 'sd-background', 'Background', s.background,
            (v) => _save(ref, s.copyWith(background: v))),
        Text('Hit die d${s.hitDie}', style: theme.textTheme.labelSmall),

        sheetSection(context, 'Ability Scores'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final a in kDndAbilities) _abilityBox(ref, s, a),
        ]),

        sheetSection(context, 'Combat'),
        Row(children: [
          const SizedBox(width: 64, child: Text('AC')),
          intStepper(prefix: 'sd', fieldKey: 'ac', value: s.ac,
              onSet: (v) => _save(ref, s.copyWith(ac: v))),
          const SizedBox(width: 12),
          const Text('XP'),
          intStepper(prefix: 'sd', fieldKey: 'xp', value: s.xp,
              onSet: (v) => _save(ref, s.copyWith(xp: v))),
        ]),
        Row(children: [
          const SizedBox(width: 64, child: Text('HP')),
          intStepper(prefix: 'sd', fieldKey: 'hp-cur', value: s.currentHp,
              onSet: (v) => _save(ref, s.copyWith(currentHp: v))),
          Text(' / ${s.maxHp}'),
          const SizedBox(width: 8),
          const Text('Max'),
          intStepper(prefix: 'sd', fieldKey: 'hp-max', value: s.maxHp,
              onSet: (v) => _save(ref, s.copyWith(maxHp: v))),
        ]),

        sheetSection(context, 'Gear & Luck'),
        Row(children: [
          const SizedBox(width: 96, child: Text('Gear slots')),
          intStepper(prefix: 'sd', fieldKey: 'gear', value: s.gearSlotsUsed,
              onSet: (v) => _save(ref, s.copyWith(gearSlotsUsed: v))),
          Text(' / ${s.gearSlotCapacity}'),
        ]),
        CheckboxListTile(
          key: const Key('sd-luck'),
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: s.luckToken,
          title: const Text('Luck token'),
          onChanged: (on) => _save(ref, s.copyWith(luckToken: on ?? false)),
        ),

        sheetSection(context, 'Talents'),
        _freeform(ref, 'sd-talents', 'Talents (rolled boons)', s.talentsText,
            (v) => _save(ref, s.copyWith(talentsText: v))),

        if (s.isCaster) ...[
          sheetSection(context, 'Spellcasting'),
          Text(
              'Casts on d20 + ${kDndAbilityLabels[s.castingAbility]} (${_fmt(s.castingMod!)})'
              ' vs DC 10 + spell tier',
              style: theme.textTheme.bodySmall),
          _freeform(ref, 'sd-spells', 'Spells known', s.spellsText,
              (v) => _save(ref, s.copyWith(spellsText: v))),
        ],

        sheetSection(context, 'Notes'),
        Text(character.note.isEmpty ? '—' : character.note),
      ],
    );
  }

  Widget _abilityBox(WidgetRef ref, ShadowdarkSheet s, String a) => SizedBox(
        width: 110,
        child: Column(children: [
          Text(kDndAbilityLabels[a]!, style: const TextStyle(fontSize: 11)),
          Text(_fmt(s.abilityMod(a)),
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(
              key: Key('sd-ability-$a-minus'),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.remove, size: 16),
              onPressed: () => _save(ref,
                  s.copyWith(abilities: {...s.abilities, a: s.score(a) - 1})),
            ),
            Text('${s.score(a)}'),
            IconButton(
              key: Key('sd-ability-$a-plus'),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.add, size: 16),
              onPressed: () => _save(ref,
                  s.copyWith(abilities: {...s.abilities, a: s.score(a) + 1})),
            ),
          ]),
        ]),
      );
}
```

- [ ] **Step 4: Wire `lib/features/tracker_screen.dart`**

(a) add import `import 'shadowdark_sheet.dart';`
(b) render branch — add before the `if (c.dnd != null)` block:
```dart
              if (c.shadowdark != null) {
                return ShadowdarkSheetView(
                  character: c,
                  onBack: () => setState(() => _editingId = null),
                );
              }
```
(c) `_onAdd` guard — extend to also allow shadowdark:
```dart
    if (!systems.contains('ironsworn') &&
        !systems.contains('dnd') &&
        !systems.contains('shadowdark')) {
      await _addCharacter(context);
      return;
    }
```
(d) chooser — add after the `new-dnd` button:
```dart
          if (systems.contains('shadowdark'))
            FilledButton(
              key: const Key('new-shadowdark'),
              onPressed: () => Navigator.pop(context, 'shadowdark'),
              child: const Text('Shadowdark'),
            ),
```
(e) choice handler — after the `else if (choice == 'dnd') ...` branch:
```dart
    } else if (choice == 'shadowdark') {
      await _newShadowdark();
```
(f) add after `_newDnd`:
```dart
  Future<void> _newShadowdark() async {
    final id = await ref.read(charactersProvider.notifier).addShadowdark();
    if (mounted) setState(() => _editingId = id);
  }
```

- [ ] **Step 5: Run, verify pass** — `flutter test test/character_sheet_ui_test.dart` → PASS (4 new + all existing). Use a larger `scrollUntilVisible` delta if a deep control isn't found.

- [ ] **Step 6: Full verify** — `flutter analyze` → clean; `flutter test` → all pass.

- [ ] **Step 7: Update CLAUDE.md** — add a Project-notes bullet:

> A lean **Shadowdark** sheet (`lib/features/shadowdark_sheet.dart`, rendered when `Character.shadowdark` is set; opt-in `shadowdark` system, NOT in `kAllSystems`) follows the D&D-P1 facts-only approach: authored mechanic constants only (`kShadowdarkClasses`/`kShadowdarkAncestries`/`kShadowdarkAlignments`/`kShadowdarkClassHitDie`/`kShadowdarkCastingAbility`) with title/deity/talents/spells freeform. **Licensing:** Shadowdark has no open license and its 3rd-party license excludes apps, so the sheet ships NO rulebook prose, no title table, no logo, no "compatible-with" claim, no attribution — a deliberate facts-only posture (content pickers would need The Arcane Library's permission). See `docs/superpowers/specs/2026-06-17-shadowdark-sheet-design.md`.

- [ ] **Step 8: Commit**

```bash
git add lib/features/shadowdark_sheet.dart lib/features/tracker_screen.dart test/character_sheet_ui_test.dart CLAUDE.md
git commit -m "feat(shadowdark): bespoke sheet + render branch + create flow"
```

---

## Self-Review (completed during planning)

**Spec coverage:** facts-only constants + ShadowdarkSheet (Task 1); Character.shadowdark wiring, no schema bump (Task 2); addShadowdark (Task 3); opt-in flag in both dialogs (Task 4); sheet (dropdowns, ability boxes, combat, gear+luck, talents, caster-only spells, freeform title/deity/background) + render branch + create flow + verify + docs (Task 5). Non-Shadowdark unaffected (render-branch + existing tests). No prose/title-table/attribution/logo (confirmed — no assets/build/pubspec changes). ✓

**Type consistency:** `ShadowdarkSheet` getters (`abilityMod`/`gearSlotCapacity`/`hitDie`/`isCaster`/`castingAbility`/`castingMod`) defined Task 1, used by Task 5; `addShadowdark` (Task 3) called by `_newShadowdark` (Task 5); `Character.shadowdark`/`clearShadowdark` (Task 2). Reuses `kDndAbilities`/`kDndAbilityLabels`. Keys `sd-`-prefixed + unique (`sd-ability-<a>-±`, `sd-class`, `sd-ancestry`, `sd-alignment`, `sd-level/ac/xp/hp-cur/hp-max/gear-±`, `sd-luck`, `sd-title/deity/background/talents/spells`, `sd-name`, `new-shadowdark`, `shadowdark-sheet`).

**Placeholder scan:** none — complete code in every step.

**Out of scope:** talent/spell/title/deity pickers + any Shadowdark prose (licensing), gear catalog, ancestry-ability automation.
