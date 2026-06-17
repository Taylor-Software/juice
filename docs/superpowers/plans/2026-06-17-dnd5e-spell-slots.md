# D&D 5e Spell Slots (Slice C, P2a) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Spell-slot tracking on the D&D sheet for caster classes — authored slot tables (full/half/pact) + derived save-DC/attack/ability + a Spellcasting section shown only for casters.

**Architecture:** Add flat spell fields to `DndSheet` (`spellSlotsUsed`/`pactSlotsUsed`/`preparedSpells`) + authored game-mechanic slot-table constants. All maxes/DCs are derived. No vendored data, no build script, no attribution (the spell-text picker is P2b).

**Tech Stack:** Dart/Flutter, flutter_riverpod, shared_preferences (mock in tests). TDD with `flutter test` + `dart analyze`.

**Spec:** `docs/superpowers/specs/2026-06-17-dnd5e-spell-slots-design.md`

**Anchors (current `lib/engine/models.dart`):** `DndSheet` at :896; constructor ends `this.featuresText = '',` (:928); fields end `final String featuresText;` (:942); derived getters block ends at `passivePerception` (:960); `premade` (:962); copyWith param `String? featuresText,` (:1006) + body `featuresText: featuresText ?? this.featuresText,` (:1048); toJson `if (featuresText.isNotEmpty) 'featuresText': featuresText,` (:1079); maybeFromJson `featuresText: strOr(j['featuresText']),` (:1125). The slot-table consts go just before `class DndSheet {` (after `kDndProfBonusByLevel`, :872-895). **Sheet anchor** (`lib/features/dnd_sheet.dart`): insert the Spellcasting section in the `children:` list immediately before `sheetSection(context, 'Features & Traits')` (:186); `final s = _s;` is at :26.

**Convention:** `dart format` on save; widget tests must avoid rootBundle (P2a reads no asset).

---

## Task 1: spell-slot constants + `DndSheet` spell fields/getters

**Files:**
- Modify: `lib/engine/models.dart`
- Test: `test/character_sheet_test.dart`

- [ ] **Step 1: Write the failing test** (add inside `void main()`):

```dart
  group('DndSheet spell slots', () {
    test('slot tables match the SRD full/half/pact tables', () {
      DndSheet caster(String c, int lvl) => DndSheet(className: c, level: lvl);
      // Full caster (Wizard)
      expect(caster('Wizard', 1).slotMax(1), 2);
      expect(caster('Wizard', 1).slotMax(2), 0);
      expect([for (var l = 1; l <= 9; l++) caster('Wizard', 5).slotMax(l)],
          [4, 3, 2, 0, 0, 0, 0, 0, 0]);
      expect([for (var l = 1; l <= 9; l++) caster('Wizard', 20).slotMax(l)],
          [4, 3, 3, 3, 3, 2, 2, 1, 1]);
      // Half caster (Paladin): none at L1, 5th-level slots at L19+
      expect(caster('Paladin', 1).slotMax(1), 0);
      expect(caster('Paladin', 2).slotMax(1), 2);
      expect(caster('Paladin', 20).slotMax(5), 2);
      expect(caster('Paladin', 20).slotMax(6), 0); // half casters cap at 5th
      // Warlock pact magic
      expect(caster('Warlock', 1).pactSlotCount, 1);
      expect(caster('Warlock', 1).pactSlotLevel, 1);
      expect(caster('Warlock', 11).pactSlotCount, 3);
      expect(caster('Warlock', 20).pactSlotCount, 4);
      expect(caster('Warlock', 20).pactSlotLevel, 5);
      expect(caster('Warlock', 5).slotMax(1), 0); // warlock uses pact, not slotMax
    });

    test('isCaster + derived DC/attack/ability', () {
      const w = DndSheet(
        className: 'Wizard', level: 5,
        abilities: {'str': 8, 'dex': 14, 'con': 12, 'int': 16, 'wis': 10, 'cha': 10},
      );
      expect(w.isCaster, isTrue);
      expect(w.spellcastingAbility, 'int');
      expect(w.spellcastingMod, 3); // int 16 -> +3
      expect(w.proficiencyBonus, 3); // level 5
      expect(w.spellSaveDC, 14); // 8 + 3 + 3
      expect(w.spellAttackBonus, 6); // 3 + 3
      const f = DndSheet(className: 'Fighter', level: 5);
      expect(f.isCaster, isFalse);
      expect(f.spellcastingAbility, isNull);
      expect(f.spellSaveDC, isNull);
    });

    test('round-trips; normalizes spellSlotsUsed to length 9; omits defaults', () {
      const s = DndSheet(
        className: 'Wizard', level: 3,
        spellSlotsUsed: [1, 0, 0, 0, 0, 0, 0, 0, 0],
        pactSlotsUsed: 0,
        preparedSpells: 'Mage Hand, Shield',
      );
      final back = DndSheet.maybeFromJson(s.toJson())!;
      expect(back.spellSlotsUsed.length, 9);
      expect(back.spellSlotsUsed[0], 1);
      expect(back.preparedSpells, 'Mage Hand, Shield');
      // defaults omitted
      expect(DndSheet.premade().toJson().containsKey('spellSlotsUsed'), isFalse);
      expect(DndSheet.premade().toJson().containsKey('preparedSpells'), isFalse);
      // tolerant: short/junk list normalized to length 9, negatives floored to 0
      final j = DndSheet.maybeFromJson({
        'className': 'Wizard',
        'spellSlotsUsed': [-3, 'x', 2],
        'pactSlotsUsed': -1,
      })!;
      expect(j.spellSlotsUsed.length, 9);
      expect(j.spellSlotsUsed[0], 0); // -3 floored
      expect(j.spellSlotsUsed[2], 2);
      expect(j.pactSlotsUsed, 0);
    });
  });
```

- [ ] **Step 2: Run, verify fail**

Run: `flutter test test/character_sheet_test.dart`
Expected: FAIL — `slotMax`/`pactSlotCount`/`isCaster`/`spellSlotsUsed` undefined.

- [ ] **Step 3a: Add slot-table constants** — insert immediately before `class DndSheet {` (after `kDndProfBonusByLevel`, ~line 895):

```dart
/// SRD caster classes → spellcasting ability id. Non-casters (Fighter,
/// Barbarian, Monk, Rogue) are absent.
const kDndSpellcastingAbility = <String, String>{
  'Bard': 'cha', 'Sorcerer': 'cha', 'Warlock': 'cha', 'Paladin': 'cha',
  'Cleric': 'wis', 'Druid': 'wis', 'Ranger': 'wis', 'Wizard': 'int',
};
const kDndFullCasterClasses = <String>{
  'Bard', 'Cleric', 'Druid', 'Sorcerer', 'Wizard',
};
const kDndHalfCasterClasses = <String>{'Paladin', 'Ranger'};

/// Full-caster spell slots: row = character level 1..20, columns = spell
/// levels 1..9.
const kDndFullCasterSlots = <List<int>>[
  [2, 0, 0, 0, 0, 0, 0, 0, 0],
  [3, 0, 0, 0, 0, 0, 0, 0, 0],
  [4, 2, 0, 0, 0, 0, 0, 0, 0],
  [4, 3, 0, 0, 0, 0, 0, 0, 0],
  [4, 3, 2, 0, 0, 0, 0, 0, 0],
  [4, 3, 3, 0, 0, 0, 0, 0, 0],
  [4, 3, 3, 1, 0, 0, 0, 0, 0],
  [4, 3, 3, 2, 0, 0, 0, 0, 0],
  [4, 3, 3, 3, 1, 0, 0, 0, 0],
  [4, 3, 3, 3, 2, 0, 0, 0, 0],
  [4, 3, 3, 3, 2, 1, 0, 0, 0],
  [4, 3, 3, 3, 2, 1, 0, 0, 0],
  [4, 3, 3, 3, 2, 1, 1, 0, 0],
  [4, 3, 3, 3, 2, 1, 1, 0, 0],
  [4, 3, 3, 3, 2, 1, 1, 1, 0],
  [4, 3, 3, 3, 2, 1, 1, 1, 0],
  [4, 3, 3, 3, 2, 1, 1, 1, 1],
  [4, 3, 3, 3, 3, 1, 1, 1, 1],
  [4, 3, 3, 3, 3, 2, 1, 1, 1],
  [4, 3, 3, 3, 3, 2, 2, 1, 1],
];

/// Half-caster spell slots (Paladin/Ranger): row = level 1..20, columns =
/// spell levels 1..5.
const kDndHalfCasterSlots = <List<int>>[
  [0, 0, 0, 0, 0],
  [2, 0, 0, 0, 0],
  [3, 0, 0, 0, 0],
  [3, 0, 0, 0, 0],
  [4, 2, 0, 0, 0],
  [4, 2, 0, 0, 0],
  [4, 3, 0, 0, 0],
  [4, 3, 0, 0, 0],
  [4, 3, 2, 0, 0],
  [4, 3, 2, 0, 0],
  [4, 3, 3, 0, 0],
  [4, 3, 3, 0, 0],
  [4, 3, 3, 1, 0],
  [4, 3, 3, 1, 0],
  [4, 3, 3, 2, 0],
  [4, 3, 3, 2, 0],
  [4, 3, 3, 3, 1],
  [4, 3, 3, 3, 1],
  [4, 3, 3, 3, 2],
  [4, 3, 3, 3, 2],
];

/// Warlock Pact Magic: row = level 1..20 → (slot count, slot spell-level).
const kDndPactSlots = <(int, int)>[
  (1, 1), (2, 1), (2, 2), (2, 2), (2, 3), (2, 3), (2, 4), (2, 4), (2, 5),
  (2, 5), (3, 5), (3, 5), (3, 5), (3, 5), (3, 5), (3, 5), (4, 5), (4, 5),
  (4, 5), (4, 5),
];
```

- [ ] **Step 3b: Add the three fields** — constructor: after `this.featuresText = '',` (line 928) add:
```dart
    this.spellSlotsUsed = const [0, 0, 0, 0, 0, 0, 0, 0, 0],
    this.pactSlotsUsed = 0,
    this.preparedSpells = '',
```
fields: after `final String featuresText;` (line 942) add:
```dart
  final List<int> spellSlotsUsed; // length 9, expended per spell level
  final int pactSlotsUsed; // Warlock Pact Magic
  final String preparedSpells; // freeform
```

- [ ] **Step 3c: Add derived getters** — after `int get passivePerception => 10 + skillBonus('perception');` (line 960) add:
```dart
  bool get isCaster => kDndSpellcastingAbility.containsKey(className);
  String? get spellcastingAbility => kDndSpellcastingAbility[className];
  int? get spellcastingMod =>
      isCaster ? abilityMod(spellcastingAbility!) : null;
  int? get spellSaveDC =>
      isCaster ? 8 + proficiencyBonus + spellcastingMod! : null;
  int? get spellAttackBonus =>
      isCaster ? proficiencyBonus + spellcastingMod! : null;

  /// Max slots at [spellLevel] (1..9) from the class's table; 0 if none.
  /// Warlock uses pact magic instead and returns 0 here.
  int slotMax(int spellLevel) {
    final row = (level - 1).clamp(0, 19);
    if (kDndFullCasterClasses.contains(className)) {
      return (spellLevel >= 1 && spellLevel <= 9)
          ? kDndFullCasterSlots[row][spellLevel - 1]
          : 0;
    }
    if (kDndHalfCasterClasses.contains(className)) {
      return (spellLevel >= 1 && spellLevel <= 5)
          ? kDndHalfCasterSlots[row][spellLevel - 1]
          : 0;
    }
    return 0;
  }

  int get pactSlotCount =>
      className == 'Warlock' ? kDndPactSlots[(level - 1).clamp(0, 19)].$1 : 0;
  int get pactSlotLevel =>
      className == 'Warlock' ? kDndPactSlots[(level - 1).clamp(0, 19)].$2 : 0;
```

- [ ] **Step 3d: Wire copyWith** — add a param after `String? featuresText,` (line 1006):
```dart
    List<int>? spellSlotsUsed,
    int? pactSlotsUsed,
    String? preparedSpells,
```
and in the returned `DndSheet(...)` after `featuresText: featuresText ?? this.featuresText,` (line 1048):
```dart
      spellSlotsUsed: _normSlots(spellSlotsUsed ?? this.spellSlotsUsed),
      pactSlotsUsed: (pactSlotsUsed ?? this.pactSlotsUsed).clamp(0, 1 << 20),
      preparedSpells: preparedSpells ?? this.preparedSpells,
```
Add this private static helper to the class (e.g. right after `maybeFromJson`):
```dart
  /// Normalize an expended-slots list to exactly 9 non-negative ints.
  static List<int> _normSlots(List<int> v) =>
      [for (var i = 0; i < 9; i++) (i < v.length ? v[i] : 0).clamp(0, 1 << 20)];
```

- [ ] **Step 3e: Wire toJson** — after `if (featuresText.isNotEmpty) 'featuresText': featuresText,` (line 1079):
```dart
        if (spellSlotsUsed.any((x) => x != 0)) 'spellSlotsUsed': spellSlotsUsed,
        if (pactSlotsUsed != 0) 'pactSlotsUsed': pactSlotsUsed,
        if (preparedSpells.isNotEmpty) 'preparedSpells': preparedSpells,
```

- [ ] **Step 3f: Wire maybeFromJson** — after `featuresText: strOr(j['featuresText']),` (line 1125):
```dart
      spellSlotsUsed: _normSlots(j['spellSlotsUsed'] is List
          ? [for (final x in j['spellSlotsUsed'] as List) x is int ? x : 0]
          : const []),
      pactSlotsUsed: intOr(j['pactSlotsUsed'], 0).clamp(0, 1 << 20),
      preparedSpells: strOr(j['preparedSpells']),
```

- [ ] **Step 4: Run, verify pass**

Run: `flutter test test/character_sheet_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/models.dart test/character_sheet_test.dart
git commit -m "feat(dnd): spell-slot tables + DndSheet spell fields/getters"
```

---

## Task 2: Spellcasting UI section

**Files:**
- Modify: `lib/features/dnd_sheet.dart`
- Test: `test/character_sheet_ui_test.dart`

- [ ] **Step 1: Write the failing tests** (add inside `void main()`; reuse the `pumpDnd` helper):

```dart
  String _wizardDnd({int level = 5}) =>
      '{"abilities":{"str":8,"dex":14,"con":12,"int":16,"wis":10,"cha":10},'
      '"className":"Wizard","level":$level,"ac":12,"currentHp":20,"maxHp":20,'
      '"hitDiceRemaining":$level,"speed":30}';

  testWidgets('caster sheet shows Spellcasting with derived DC + slot stepper',
      (tester) async {
    final c = await pumpDnd(tester, dnd: _wizardDnd());
    await tester.tap(find.text('Tarin'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.byKey(const Key('dnd-slot-1-plus')), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.text('Spellcasting'), findsOneWidget);
    expect(find.textContaining('DC 14'), findsOneWidget); // 8 + prof3 + int+3
    // Expend a level-1 slot.
    await tester.tap(find.byKey(const Key('dnd-slot-1-plus')));
    await tester.pumpAndSettle();
    expect((await c.read(charactersProvider.future)).single.dnd!
        .spellSlotsUsed[0], 1);
  });

  testWidgets('Warlock shows a Pact Magic row', (tester) async {
    await pumpDnd(tester,
        dnd: '{"abilities":{"str":10,"dex":14,"con":12,"int":10,"wis":10,'
            '"cha":16},"className":"Warlock","level":5,"ac":12,"currentHp":20,'
            '"maxHp":20,"hitDiceRemaining":5,"speed":30}');
    await tester.tap(find.text('Tarin'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.byKey(const Key('dnd-pact-plus')), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Pact'), findsOneWidget);
  });

  testWidgets('non-caster (Fighter) shows no Spellcasting section',
      (tester) async {
    await pumpDnd(tester); // premade Fighter
    await tester.tap(find.text('Tarin'));
    await tester.pumpAndSettle();
    expect(find.text('Spellcasting'), findsNothing);
  });
```

- [ ] **Step 2: Run, verify fail**

Run: `flutter test test/character_sheet_ui_test.dart`
Expected: FAIL — `dnd-slot-1-plus` not found / no 'Spellcasting'.

- [ ] **Step 3: Implement** — in `lib/features/dnd_sheet.dart`, insert the Spellcasting section into the `children:` list immediately **before** `sheetSection(context, 'Features & Traits')` (line 186):

```dart
        if (s.isCaster) ...[
          sheetSection(context, 'Spellcasting'),
          Text(
              'Spell save DC ${s.spellSaveDC}  ·  Attack ${_fmt(s.spellAttackBonus!)}'
              '  ·  ${kDndAbilityLabels[s.spellcastingAbility]}',
              style: theme.textTheme.bodySmall),
          if (s.className == 'Warlock')
            Row(children: [
              SizedBox(
                  width: 120,
                  child: Text('Pact slots (lv ${s.pactSlotLevel})')),
              intStepper(
                  prefix: 'dnd',
                  fieldKey: 'pact',
                  value: s.pactSlotsUsed,
                  onSet: (v) => _save(ref, s.copyWith(pactSlotsUsed: v))),
              Text('${(s.pactSlotCount - s.pactSlotsUsed).clamp(0, s.pactSlotCount)}'
                  ' / ${s.pactSlotCount} left'),
            ])
          else
            for (var lvl = 1; lvl <= 9; lvl++)
              if (s.slotMax(lvl) > 0) _slotRow(ref, s, lvl),
          TextFormField(
            key: const Key('dnd-prepared'),
            initialValue: s.preparedSpells,
            maxLines: null,
            decoration: const InputDecoration(
                labelText: 'Prepared / known', hintText: 'Spell names…'),
            onChanged: (v) => _save(ref, s.copyWith(preparedSpells: v)),
          ),
        ],
```

Add the `_slotRow` method to the class:

```dart
  Widget _slotRow(WidgetRef ref, DndSheet s, int lvl) {
    final max = s.slotMax(lvl);
    final used = lvl - 1 < s.spellSlotsUsed.length ? s.spellSlotsUsed[lvl - 1] : 0;
    return Row(children: [
      SizedBox(width: 64, child: Text('Lv $lvl')),
      intStepper(
        prefix: 'dnd',
        fieldKey: 'slot-$lvl',
        value: used,
        onSet: (v) {
          final next = [...s.spellSlotsUsed];
          while (next.length < 9) {
            next.add(0);
          }
          next[lvl - 1] = v.clamp(0, max);
          _save(ref, s.copyWith(spellSlotsUsed: next));
        },
      ),
      Text('${(max - used).clamp(0, max)} / $max left'),
    ]);
  }
```

(`_fmt` already exists at the top of the file. `theme` is the local `Theme.of(context)` in `build`.)

- [ ] **Step 4: Run, verify pass**

Run: `flutter test test/character_sheet_ui_test.dart`
Expected: PASS (3 new + all existing green). Add a larger `scrollUntilVisible` delta if a control is deep; the helper already scrolls progressively.

- [ ] **Step 5: Analyze + commit**

Run: `dart analyze lib/features/dnd_sheet.dart test/character_sheet_ui_test.dart`
Expected: `No issues found!`

```bash
git add lib/features/dnd_sheet.dart test/character_sheet_ui_test.dart
git commit -m "feat(dnd): spellcasting section (slots, pact magic, prepared)"
```

---

## Task 3: Full verification + docs

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Full analyze + test**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test`
Expected: all pass (no regressions).

- [ ] **Step 2: Update CLAUDE.md** — append to the D&D bullet (after the P2-deferral sentence):

> P2a (spell slots) is shipped: authored slot tables (`kDndFullCasterSlots`/`kDndHalfCasterSlots`/`kDndPactSlots` + `kDndSpellcastingAbility`) drive a Spellcasting section (derived save-DC/attack, slot grid, Warlock pact magic, freeform prepared list) shown only for caster classes — still no vendored data/attribution. The spell-name picker (reproduces SRD text → needs the data rail + CC-BY notice) remains P2b.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: note D&D P2a spell slots shipped; picker still P2b"
```

---

## Self-Review (completed during planning)

**Spec coverage:** spell fields + authored tables + derived DC/attack/ability/slotMax/pact (Task 1); Spellcasting section gated on `isCaster`, slot grid + pact row + prepared text (Task 2); no data rail/attribution (confirmed — no pubspec/asset/build changes); tests incl. slot-table verify + caster/non-caster UI (Tasks 1-2); verify + docs (Task 3). ✓

**Type consistency:** `slotMax(int)`, `pactSlotCount`/`pactSlotLevel`, `isCaster`, `spellSaveDC`/`spellAttackBonus`/`spellcastingMod`/`spellcastingAbility`, `_normSlots` defined Task 1 and used by Task 2's `_slotRow`/section. Keys `dnd-slot-<lvl>`, `dnd-pact`, `dnd-prepared` unique. `spellSlotsUsed` always length-9 (constructor default, `_normSlots` in copyWith + maybeFromJson, and the UI pads before write).

**Placeholder scan:** none — full slot tables + code in every step.

**Out of scope:** spell-name picker + SRD text + data rail + CC-BY attribution (P2b), attacks table, equipment/currency.
