# Generalized 0-Level Funnel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generalize the DCC 0-level funnel into a system-agnostic feature: a standalone `Character.funnel` roster entity whose survivors graduate into full hero Characters of any enabled sheet system, via per-system `FunnelProfile`s. Replaces DCC's bespoke funnel.

**Architecture:** A pure engine module (`lib/engine/funnel.dart`) holds `FunnelPeasant`, `FunnelChoice`, `FunnelProfile`, and a `kFunnelProfiles` registry (one profile per sheet system). `FunnelSheet` is a new typed sheet field on `Character` (like `.dcc`). A generic `FunnelSheetView` renders peasant cards driven by the seed system's profile; graduating spawns a new hero Character built by the target profile's `graduate` closure (each closure reuses the target sheet's own `copyWith` for clamping/defaults). DCC's funnel is then ripped out of `DccSheet` (leveled-only). Finally an opt-in `funnel` system (tools category) wires the roster Add action, sheet dispatch, surfaces, blurb, and campaign-creation presets.

**Tech Stack:** Flutter, flutter_riverpod, Dart. Tests use `flutter_test`; widget tests pump `FunnelSheetView` directly via the prefs-seeded `ProviderContainer` harness (never `HomeShell`/`JournalScreen` — avoids the rootBundle hang). Roll/graduation use no randomness in mappers (deterministic).

**Run note:** `flutter` may not be on PATH in a fresh shell — prefix every flutter command with `export PATH="$HOME/development/flutter/bin:$PATH"`. A `dart format` hook runs on `.dart` edits (expected reformat).

---

## File structure

- **Create** `lib/engine/funnel.dart` — `FunnelPeasant`, `FunnelChoice`, `FunnelProfile`, `kFunnelProfiles` registry, `funnelProfileFor`, `kFunnelMaxPeasants`, and the per-system mapper closures.
- **Create** `lib/engine/funnel_sheet.dart` — wait: `FunnelSheet` lives in `models.dart` alongside the other sheet classes (so `Character` can reference it without a cycle). Put `FunnelSheet` in `models.dart`; put `FunnelPeasant`/`FunnelProfile`/registry in `funnel.dart` (imported by models.dart). **Correction:** to avoid an import cycle (`funnel.dart` profiles call `Character.forSheet`, which is in `models.dart`), put `FunnelSheet` + `FunnelPeasant` in `models.dart`, and put `FunnelProfile`/`FunnelChoice`/`kFunnelProfiles`/`funnelProfileFor` in `funnel.dart` (which imports models.dart). `models.dart` does NOT import `funnel.dart`.
- **Modify** `lib/engine/models.dart` — `FunnelSheet`/`FunnelPeasant` classes; `Character.funnel` field wiring; DCC refactor (remove funnel from `DccSheet`, delete `DccPeasant`); `kKnownSystems`/`kSystemCategory`.
- **Create** `lib/features/funnel_sheet.dart` — `FunnelSheetView` (the funnel UI; replaces DCC's funnel UI).
- **Modify** `lib/features/dcc_sheet.dart` — drop the funnel branch (leveled-only).
- **Modify** `lib/state/providers.dart` — `addFunnel(seedSystem)` + `graduateFunnelPeasant`.
- **Modify** `lib/features/tracker_screen.dart` — roster Add menu (`new-funnel`), dispatch, `_newFunnel`.
- **Modify** `lib/shared/home_shell.dart` — `kSystemBlurbs['funnel']`.
- **Modify** `lib/engine/campaign_presets.dart` — `solo-dcc` gains `funnel`; new `solo-funnel` preset + icon.
- **Modify** `lib/engine/campaign_surfaces.dart` — `_table['Sheet']` funnel row.
- **Create** `test/funnel_test.dart` — model + profile + registration unit tests.
- **Create** `test/funnel_sheet_ui_test.dart` — `FunnelSheetView` widget tests.
- **Modify** `test/dcc_sheet_test.dart` / `test/dcc_sheet_ui_test.dart` — drop funnel coverage (moved to funnel tests), keep leveled.

### Key verified anchors (from recon, all real)

- **Character wiring (models.dart):** constructor params end `…this.kalArath, this.dcc, this.starred=…`; fields `final DccSheet? dcc;`; `forSheet` switch (arms per system, `_ => throw StateError`); `copyWith` has `DccSheet? dcc, bool clearDcc=false,` + body `dcc: clearDcc ? null : (dcc ?? this.dcc),`; toJson `if (dcc != null) 'dcc': dcc!.toJson(),`; fromJson `dcc: DccSheet.maybeFromJson(j['dcc']),`; `withHpDelta` has `if (dcc != null && dcc!.mode == 'leveled') {…}`.
- **DccSheet currently still has** `mode`, `peasants`, `graduate(i, className, alignment)`, `isFunnel`, and the `DccPeasant` class — all to be removed in P1b.
- **Registration:** `kKnownSystems` (models.dart, a `<String>{}` set); `kSystemCategory` (tools examples `'party'`/`'lonelog'`); `kSystemBlurbs` (home_shell.dart); `CampaignPreset{id,label,kind,blurb,mode,systems}` + `kPresetIcons` (campaign_presets.dart); `_table['Sheet']` (campaign_surfaces.dart) — DCC row `SurfaceRow('Dungeon Crawl Classics sheet', requiresSystem: 'dcc')`; tracker_screen `_onAdd` guard / options records `(key,value,label,blurb)` / `choice` dispatch chain / `_newOse` helper / sheet-dispatch `if (c.ose != null) return OseSheetView(...)`; providers `addPreMadeSheet(systemKey)` + `addDcc()`.
- **UI bricks (sheet_widgets.dart):** `sheetSection(context, title)`; `sheetNameHeader(context, ref, character, onBack:, nameKey:)`; `conditionsSection(context, ref, c, prefix)`; `intStepper(prefix:, fieldKey:, value:, onSet:)`. `OseSheetView` pattern: `ConsumerWidget`, `OseSheet get _s => character.ose!;`, `_save(ref, next) => ref.read(charactersProvider.notifier).replace(character.copyWith(ose: next));`, a local `_stepper(key,label,value,{onSet,min,max})` whose buttons key `$key-minus`/`$key-plus`.
- **Widget-test harness:** `SharedPreferences.setMockInitialValues({'juice.sessions.v1': '{"active":"default","sessions":[{"id":"default","name":"C1"}]}', 'juice.characters.v1.default': jsonEncode([{...,'<field>': sheet.toJson()}])})` → `ProviderContainer()` → read `charactersProvider.future` → `UncontrolledProviderScope` + `Consumer` live-read + `tester.view.physicalSize = const Size(1200, 6000)`.

### Per-system profile facts (verified)

| system | sheetField | stat storage | stat keys | range | HP pool | graduate choices (optionsConst) |
|---|---|---|---|---|---|---|
| dcc | dcc | `Map stats` | str,agi,sta,per,int,lck | 3..18 | currentHp/maxHp | className `kDccClasses`, alignment `kDccAlignments` |
| dnd | dnd | `Map abilities` | str,dex,con,int,wis,cha | 1..30 | currentHp/maxHp | className `kDndClasses` |
| shadowdark | shadowdark | `Map abilities` | str,dex,con,int,wis,cha | 1..20 | currentHp/maxHp | className `kShadowdarkClasses`, ancestry `kShadowdarkAncestries`, alignment `kShadowdarkAlignments` |
| nimble | nimble | `Map stats` (mods) | str,dex,int,wis | -9..9 | currentHp/maxHp | className `kNimbleClasses` |
| draw-steel | drawSteel | `Map characteristics` (mods) | might,agility,reason,intuition,presence | -5..5 | currentStamina/maxStamina | className `kDrawSteelClasses` |
| argosa | argosa | `Map stats` | str,dex,con,int,per,wil,cha | 3..18 | currentHp/maxHp | className `kArgosaClasses` |
| cairn | cairn | **individual** str,dex,wil | str,dex,wil | 3..18 | currentHp/maxHp | background `kCairnBackgrounds` |
| knave | knave | `Map stats` (mods) | str,dex,con,int,wis,cha | 0..10 | currentHp/maxHp | (none — career freeform) |
| ose | ose | `Map stats` | str,int,wis,dex,con,cha | 3..18 | currentHp/maxHp | className `kOseClasses`, alignment `kOseAlignments` |
| kal-arath | kalArath | `Map stats` (mods) | str,tou,agi,int,pre | -1..5 | currentHp/maxHp | archetype `kKalArathArchetypes`, pact `kKalArathPacts` |
| ironsworn | ironsworn | **individual** edge,heart,iron,shadow,wits | edge,heart,iron,shadow,wits | 1..3 | **none** (meters) | (none) |
| starforged | starforged | **individual** edge,heart,iron,shadow,wits | edge,heart,iron,shadow,wits | 1..3 | **none** (meters) | (none) |

**HP rule for meter systems (ironsworn/starforged):** they have no `currentHp/maxHp` pool — the mapper does NOT map peasant HP (the premade meters stay full). This supersedes the spec's loose "HP maps to health meter" line (mapping a d8 HP into a 0–5 condition meter would mis-set a fresh hero). Documented deviation.

**Stat mapping:** each mapper passes `peasant.stats` (or per-key picks) into the target sheet's `copyWith`; the sheet's own `copyWith` clamps to its range and defaults missing keys. Same-system graduation is 1:1; cross-system is best-effort by key (lossy across score↔modifier semantics — accepted).

---

## Task 1: `FunnelPeasant` value class

**Files:** Modify `lib/engine/models.dart` (add near the DCC classes); Test `test/funnel_test.dart` (create).

- [ ] **Step 1: Write the failing test** — create `test/funnel_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';

void main() {
  group('FunnelPeasant', () {
    test('defaults: alive, not graduated, empty maps', () {
      const p = FunnelPeasant();
      expect(p.alive, true);
      expect(p.graduated, false);
      expect(p.hp, 0);
      expect(p.stats, isEmpty);
      expect(p.flavor, isEmpty);
    });
    test('copyWith replaces fields', () {
      const p = FunnelPeasant();
      final p2 = p.copyWith(
          name: 'Bob', hp: 4, alive: false, graduated: true,
          stats: {'str': 12}, flavor: {'occupation': 'Farmer'});
      expect(p2.name, 'Bob');
      expect(p2.hp, 4);
      expect(p2.alive, false);
      expect(p2.graduated, true);
      expect(p2.stats['str'], 12);
      expect(p2.flavor['occupation'], 'Farmer');
    });
    test('round-trips through json', () {
      const p = FunnelPeasant(
          name: 'Ada', hp: 3, stats: {'str': 9}, flavor: {'weapon': 'Sling'});
      final back = FunnelPeasant.fromJson(p.toJson());
      expect(back.name, 'Ada');
      expect(back.hp, 3);
      expect(back.stats['str'], 9);
      expect(back.flavor['weapon'], 'Sling');
      expect(back.alive, true);
      expect(back.graduated, false);
    });
    test('fromJson tolerates missing fields', () {
      final p = FunnelPeasant.fromJson(const {});
      expect(p.name, '');
      expect(p.hp, 0);
      expect(p.stats, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run** `export PATH="$HOME/development/flutter/bin:$PATH" && flutter test test/funnel_test.dart` — FAIL (`FunnelPeasant` undefined).

- [ ] **Step 3: Add to `lib/engine/models.dart`** (place just above the `Character` class, after the DCC section):

```dart
/// One 0-level funnel character. Stats/flavor are keyed by the seed
/// FunnelProfile (see lib/engine/funnel.dart); both are free-shaped maps so the
/// funnel is system-agnostic. All descriptive content is user-entered.
class FunnelPeasant {
  const FunnelPeasant({
    this.name = '',
    this.hp = 0,
    this.alive = true,
    this.graduated = false,
    this.stats = const {},
    this.flavor = const {},
  });

  final String name;
  final int hp;
  final bool alive;
  final bool graduated;       // already promoted → not graduable again
  final Map<String, int> stats;
  final Map<String, String> flavor;

  FunnelPeasant copyWith({
    String? name,
    int? hp,
    bool? alive,
    bool? graduated,
    Map<String, int>? stats,
    Map<String, String>? flavor,
  }) =>
      FunnelPeasant(
        name: name ?? this.name,
        hp: (hp ?? this.hp).clamp(0, 1 << 20),
        alive: alive ?? this.alive,
        graduated: graduated ?? this.graduated,
        stats: stats ?? this.stats,
        flavor: flavor ?? this.flavor,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'hp': hp,
        'alive': alive,
        'graduated': graduated,
        'stats': stats,
        'flavor': flavor,
      };

  factory FunnelPeasant.fromJson(Map<String, dynamic> j) => FunnelPeasant(
        name: j['name'] as String? ?? '',
        hp: ((j['hp'] as num?)?.round() ?? 0).clamp(0, 1 << 20),
        alive: j['alive'] as bool? ?? true,
        graduated: j['graduated'] as bool? ?? false,
        stats: ((j['stats'] as Map?) ?? const {}).map(
            (k, v) => MapEntry(k as String, (v as num).round())),
        flavor: ((j['flavor'] as Map?) ?? const {}).map(
            (k, v) => MapEntry(k as String, v as String)),
      );
}
```

- [ ] **Step 4: Run** `flutter test test/funnel_test.dart` — PASS.
- [ ] **Step 5: Commit**

```bash
git add lib/engine/models.dart test/funnel_test.dart
git commit -m "feat(funnel): FunnelPeasant value class"
```

---

## Task 2: `FunnelSheet` value class

**Files:** Modify `lib/engine/models.dart`; Test `test/funnel_test.dart`.

- [ ] **Step 1: Write the failing test** — append to `test/funnel_test.dart` `main()`:

```dart
  group('FunnelSheet', () {
    test('premade has the seed system + one empty peasant', () {
      final s = FunnelSheet.premade('dcc', const [FunnelPeasant(hp: 1)]);
      expect(s.seedSystem, 'dcc');
      expect(s.peasants.length, 1);
      expect(s.peasants.first.hp, 1);
    });
    test('markGraduated flips one peasant', () {
      final s = FunnelSheet(seedSystem: 'dcc', peasants: const [
        FunnelPeasant(name: 'A'),
        FunnelPeasant(name: 'B'),
      ]);
      final s2 = s.markGraduated(1);
      expect(s2.peasants[0].graduated, false);
      expect(s2.peasants[1].graduated, true);
    });
    test('round-trips through json', () {
      final s = FunnelSheet(seedSystem: 'ose', peasants: const [
        FunnelPeasant(name: 'A', hp: 4, stats: {'str': 12}),
      ]);
      final back = FunnelSheet.maybeFromJson(s.toJson())!;
      expect(back.seedSystem, 'ose');
      expect(back.peasants.single.name, 'A');
      expect(back.peasants.single.stats['str'], 12);
    });
    test('maybeFromJson returns null for non-map', () {
      expect(FunnelSheet.maybeFromJson(null), isNull);
      expect(FunnelSheet.maybeFromJson('x'), isNull);
    });
    test('maybeFromJson defaults a missing seedSystem to empty + tolerates no peasants', () {
      final s = FunnelSheet.maybeFromJson(const {})!;
      expect(s.seedSystem, '');
      expect(s.peasants, isEmpty);
    });
  });
```

- [ ] **Step 2: Run** `flutter test test/funnel_test.dart` — FAIL (`FunnelSheet` undefined).

- [ ] **Step 3: Add to `lib/engine/models.dart`** (directly after `FunnelPeasant`):

```dart
/// A standalone 0-level funnel roster entity. `seedSystem` is the sheet system
/// whose FunnelProfile shaped the peasants' stat/flavor keys (see
/// lib/engine/funnel.dart). Graduating a survivor spawns a *separate* hero
/// Character; the funnel persists (the promoted peasant is marked graduated).
class FunnelSheet {
  const FunnelSheet({this.seedSystem = '', this.peasants = const []});

  final String seedSystem;
  final List<FunnelPeasant> peasants;

  factory FunnelSheet.premade(String seedSystem, List<FunnelPeasant> seed) =>
      FunnelSheet(seedSystem: seedSystem, peasants: seed);

  FunnelSheet copyWith({String? seedSystem, List<FunnelPeasant>? peasants}) =>
      FunnelSheet(
        seedSystem: seedSystem ?? this.seedSystem,
        peasants: peasants ?? this.peasants,
      );

  /// Returns a copy with peasant [i] flagged graduated.
  FunnelSheet markGraduated(int i) {
    final list = [...peasants];
    list[i] = list[i].copyWith(graduated: true);
    return copyWith(peasants: list);
  }

  int get aliveCount => peasants.where((p) => p.alive && !p.graduated).length;
  int get graduatedCount => peasants.where((p) => p.graduated).length;

  Map<String, dynamic> toJson() => {
        'seedSystem': seedSystem,
        'peasants': peasants.map((p) => p.toJson()).toList(),
      };

  static FunnelSheet? maybeFromJson(dynamic j) {
    if (j is! Map<String, dynamic>) return null;
    return FunnelSheet(
      seedSystem: j['seedSystem'] as String? ?? '',
      peasants: ((j['peasants'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => FunnelPeasant.fromJson(m.cast<String, dynamic>()))
          .toList(),
    );
  }
}
```

- [ ] **Step 4: Run** `flutter test test/funnel_test.dart` — PASS.
- [ ] **Step 5: Commit**

```bash
git add lib/engine/models.dart test/funnel_test.dart
git commit -m "feat(funnel): FunnelSheet value class"
```

---

## Task 3: Wire `Character.funnel`

**Files:** Modify `lib/engine/models.dart` (`Character`); Test `test/funnel_test.dart`.

NOTE: `Character.forSheet` gets **no** `funnel` arm — a funnel needs a `seedSystem` that `forSheet(systemKey, id)` can't supply; creation goes through `addFunnel(seedSystem)` (Task 11). `withHpDelta` ignores funnel Characters (peasant HP is edited in the funnel UI).

- [ ] **Step 1: Write the failing test** — append to `test/funnel_test.dart`:

```dart
  group('Character funnel wiring', () {
    test('round-trips a funnel character through json', () {
      final c = Character(
        id: 'f1',
        name: 'Funnel',
        funnel: FunnelSheet(seedSystem: 'dcc', peasants: const [
          FunnelPeasant(name: 'A', hp: 3, stats: {'str': 12}),
        ]),
      );
      final back = Character.fromJson(c.toJson());
      expect(back.funnel, isNotNull);
      expect(back.funnel!.seedSystem, 'dcc');
      expect(back.funnel!.peasants.single.name, 'A');
    });
    test('clearFunnel drops the sheet', () {
      final c = Character(
          id: 'f1', name: 'F', funnel: const FunnelSheet(seedSystem: 'dcc'));
      expect(c.copyWith(clearFunnel: true).funnel, isNull);
    });
    test('withHpDelta leaves a funnel character unchanged', () {
      final c = Character(
          id: 'f1', name: 'F', funnel: const FunnelSheet(seedSystem: 'dcc'));
      expect(identical(c.withHpDelta(-5), c), true);
    });
  });
```

- [ ] **Step 2: Run** `flutter test test/funnel_test.dart` — FAIL (`funnel`/`clearFunnel` undefined).

- [ ] **Step 3: Wire `Character`** — 6 edits, each next to the `dcc` equivalent:
  1. Constructor param (after `this.dcc,`): `    this.funnel,`
  2. Field (after `final DccSheet? dcc;` block): 
     ```dart
       /// Standalone 0-level funnel; null unless this roster entry is a funnel.
       final FunnelSheet? funnel;
     ```
  3. `copyWith` params (after `DccSheet? dcc, bool clearDcc = false,`):
     ```dart
         FunnelSheet? funnel,
         bool clearFunnel = false,
     ```
  4. `copyWith` body (after `dcc: clearDcc ? null : (dcc ?? this.dcc),`):
     ```dart
             funnel: clearFunnel ? null : (funnel ?? this.funnel),
     ```
  5. `toJson` (after `if (dcc != null) 'dcc': dcc!.toJson(),`):
     ```dart
             if (funnel != null) 'funnel': funnel!.toJson(),
     ```
  6. `fromJson` (after `dcc: DccSheet.maybeFromJson(j['dcc']),`):
     ```dart
             funnel: FunnelSheet.maybeFromJson(j['funnel']),
     ```
  `withHpDelta` — **no change** (funnel is not an HP-bearing sheet; the existing branches already skip it and the final fallback `return this;` covers a funnel Character with empty `tracks`).

- [ ] **Step 4: Run** `flutter test test/funnel_test.dart && flutter test test/character_sheet_test.dart` — PASS (no regression). `flutter analyze lib/engine/models.dart` — clean.
- [ ] **Step 5: Commit**

```bash
git add lib/engine/models.dart test/funnel_test.dart
git commit -m "feat(funnel): wire Character.funnel"
```

---

## Task 4: `FunnelProfile` types + registry skeleton + DCC profile

**Files:** Create `lib/engine/funnel.dart`; Test `test/funnel_test.dart`.

This establishes the extension point and the **first** profile (DCC). DccSheet still has its leveled fields (mode/peasants removed in P1b/Task 9); the DCC mapper builds a leveled DccSheet via `copyWith`, which works now and after the refactor.

- [ ] **Step 1: Write the failing test** — append to `test/funnel_test.dart` (add `import 'package:juice_oracle/engine/funnel.dart';` at top):

```dart
  group('FunnelProfile registry', () {
    test('funnelProfileFor returns null for unknown', () {
      expect(funnelProfileFor('nope'), isNull);
    });
    test('dcc profile shape', () {
      final p = funnelProfileFor('dcc')!;
      expect(p.system, 'dcc');
      expect(p.statKeys.map((s) => s.key),
          containsAll(['str', 'agi', 'sta', 'per', 'int', 'lck']));
      expect(p.flavorFields.map((f) => f.key),
          containsAll(['occupation', 'weapon', 'tradeGoods']));
      expect(p.graduateChoices.map((c) => c.key),
          containsAll(['className', 'alignment']));
    });
    test('dcc seedPeasant has mid-range stats + hpMin hp', () {
      final p = funnelProfileFor('dcc')!;
      final peasant = p.seedPeasant();
      expect(peasant.stats['str'], p.statDefault);
      expect(peasant.hp, p.hpMin);
      expect(peasant.alive, true);
    });
    test('dcc graduate builds a leveled DCC hero copying stats + hp', () {
      final p = funnelProfileFor('dcc')!;
      const peasant = FunnelPeasant(
        name: 'Survivor',
        hp: 5,
        stats: {'str': 16, 'agi': 12, 'sta': 14, 'per': 9, 'int': 8, 'lck': 11},
        flavor: {'occupation': 'Blacksmith'},
      );
      final hero = p.graduate('h1', peasant, {'className': 'Warrior', 'alignment': 'Lawful'});
      expect(hero.id, 'h1');
      expect(hero.name, 'Survivor');
      expect(hero.dcc, isNotNull);
      expect(hero.dcc!.className, 'Warrior');
      expect(hero.dcc!.alignment, 'Lawful');
      expect(hero.dcc!.stats['str'], 16);
      expect(hero.dcc!.stats['lck'], 11);
      expect(hero.dcc!.lckMax, 11);
      expect(hero.dcc!.currentHp, 5);
      expect(hero.dcc!.maxHp, 5);
      expect(hero.dcc!.occupation, 'Blacksmith');
    });
  });
```

- [ ] **Step 2: Run** `flutter test test/funnel_test.dart` — FAIL (`funnel.dart` / `funnelProfileFor` undefined).

- [ ] **Step 3: Create `lib/engine/funnel.dart`**:

```dart
import 'models.dart';

/// Max 0-level peasants a funnel tracks at once.
const int kFunnelMaxPeasants = 6;

/// A graduation dropdown a target system needs (class/ancestry/alignment/…).
class FunnelChoice {
  const FunnelChoice(this.key, this.label, this.options);
  final String key, label;
  final List<String> options;
}

/// Per-system funnel contract: what its peasants look like + how to build one of
/// its heroes from a survivor. Pure; registered in [kFunnelProfiles].
class FunnelProfile {
  const FunnelProfile({
    required this.system,
    required this.statKeys,
    required this.statMin,
    required this.statMax,
    required this.statDefault,
    required this.flavorFields,
    required this.hpMin,
    required this.hpMax,
    required this.graduateChoices,
    required this.graduate,
  });

  final String system;
  final List<({String key, String label})> statKeys;
  final int statMin, statMax, statDefault;
  final List<({String key, String label})> flavorFields;
  final int hpMin, hpMax;
  final List<FunnelChoice> graduateChoices;

  /// Builds a hero Character of [system] from [p], applying graduation [picks]
  /// (keyed by [graduateChoices] key). Maps stats by key into the target sheet
  /// (the sheet's own copyWith clamps/defaults); HP into the sheet's pool.
  final Character Function(String id, FunnelPeasant p, Map<String, String> picks)
      graduate;

  /// A fresh empty peasant seeded from this profile (mid-range stats, hpMin).
  FunnelPeasant seedPeasant() => FunnelPeasant(
        hp: hpMin,
        stats: {for (final s in statKeys) s.key: statDefault},
        flavor: {for (final f in flavorFields) f.key: ''},
      );

  /// The default pick for each choice (its first option), for the graduate dialog.
  Map<String, String> defaultPicks() =>
      {for (final c in graduateChoices) c.key: c.options.first};
}

FunnelProfile? funnelProfileFor(String system) => kFunnelProfiles[system];

/// Helper: hero name from the peasant, falling back to the forSheet default.
String _heroName(FunnelPeasant p, Character base) =>
    p.name.trim().isEmpty ? base.name : p.name.trim();

final Map<String, FunnelProfile> kFunnelProfiles = {
  'dcc': FunnelProfile(
    system: 'dcc',
    statKeys: const [
      (key: 'str', label: 'STR'),
      (key: 'agi', label: 'AGI'),
      (key: 'sta', label: 'STA'),
      (key: 'per', label: 'PER'),
      (key: 'int', label: 'INT'),
      (key: 'lck', label: 'LCK'),
    ],
    statMin: 3,
    statMax: 18,
    statDefault: 10,
    flavorFields: const [
      (key: 'occupation', label: 'Occupation'),
      (key: 'weapon', label: 'Weapon'),
      (key: 'tradeGoods', label: 'Trade goods'),
    ],
    hpMin: 1,
    hpMax: 8,
    graduateChoices: [
      FunnelChoice('className', 'Class', kDccClasses),
      FunnelChoice('alignment', 'Alignment', kDccAlignments),
    ],
    graduate: (id, p, picks) {
      final base = Character.forSheet('dcc', id);
      return base.copyWith(
        name: _heroName(p, base),
        dcc: base.dcc!.copyWith(
          stats: p.stats,
          lckMax: p.stats['lck'] ?? 10,
          currentHp: p.hp,
          maxHp: p.hp,
          occupation: p.flavor['occupation'] ?? '',
          className: picks['className'] ?? 'Warrior',
          alignment: picks['alignment'] ?? 'Neutral',
        ),
      );
    },
  ),
};
```

NOTE on the DCC mapper: it sets `mode` implicitly — after P1b `DccSheet` is leveled-only so there is no `mode`. **Until P1b lands, `DccSheet.copyWith` still defaults `mode: 'funnel'`.** So in THIS task add `mode: 'leveled'` to the DCC mapper's `copyWith` (it is a valid param now); Task 9 removes `mode` entirely and you delete that one argument. The test above does not assert `mode`, so it passes both before and after. Add `mode: 'leveled',` to the `dcc: base.dcc!.copyWith(...)` call now.

- [ ] **Step 4: Run** `flutter test test/funnel_test.dart` — PASS. `flutter analyze lib/engine/funnel.dart` — clean.
- [ ] **Step 5: Commit**

```bash
git add lib/engine/funnel.dart test/funnel_test.dart
git commit -m "feat(funnel): FunnelProfile registry + DCC profile"
```

---

## Task 5: Notifier — `addFunnel` + `graduateFunnelPeasant`

**Files:** Modify `lib/state/providers.dart`; Test `test/funnel_test.dart`.

- [ ] **Step 1: Write the failing test** — append to `test/funnel_test.dart` (add imports `package:flutter_riverpod/flutter_riverpod.dart`, `package:juice_oracle/state/providers.dart`, `package:shared_preferences/shared_preferences.dart`):

```dart
  group('CharacterNotifier funnel', () {
    setUp(() => SharedPreferences.setMockInitialValues({
          'juice.sessions.v1':
              '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
        }));

    test('addFunnel creates a funnel seeded from the system profile', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final id = await c.read(charactersProvider.notifier).addFunnel('dcc');
      final list = await c.read(charactersProvider.future);
      final f = list.firstWhere((x) => x.id == id);
      expect(f.funnel, isNotNull);
      expect(f.funnel!.seedSystem, 'dcc');
      expect(f.funnel!.peasants.length, 1);
      expect(f.funnel!.peasants.first.stats['str'], 10); // dcc statDefault
    });

    test('graduateFunnelPeasant spawns a hero + marks the peasant graduated', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final notifier = c.read(charactersProvider.notifier);
      final fid = await notifier.addFunnel('dcc');
      final funnelChar = (await c.read(charactersProvider.future))
          .firstWhere((x) => x.id == fid);
      // set the peasant's stats so we can assert mapping
      final seeded = funnelChar.copyWith(
          funnel: funnelChar.funnel!.copyWith(peasants: [
        funnelChar.funnel!.peasants.first
            .copyWith(name: 'Reaper', hp: 6, stats: {...funnelChar.funnel!.peasants.first.stats, 'str': 15}),
      ]));
      await notifier.replace(seeded);
      final profile = funnelProfileFor('dcc')!;
      final heroId = await notifier.graduateFunnelPeasant(
          seeded, 0, (id) => profile.graduate(id, seeded.funnel!.peasants[0],
              {'className': 'Warrior', 'alignment': 'Lawful'}));
      final list = await c.read(charactersProvider.future);
      final hero = list.firstWhere((x) => x.id == heroId);
      expect(hero.dcc, isNotNull);
      expect(hero.dcc!.stats['str'], 15);
      expect(hero.name, 'Reaper');
      final funnel = list.firstWhere((x) => x.id == fid);
      expect(funnel.funnel!.peasants[0].graduated, true);   // funnel persists
    });
  });
```

- [ ] **Step 2: Run** `flutter test test/funnel_test.dart -n "CharacterNotifier funnel"` — FAIL (`addFunnel`/`graduateFunnelPeasant` undefined).

- [ ] **Step 3: Add to `lib/state/providers.dart`** (in `CharacterNotifier`, next to `addDcc`). Add `import '../engine/funnel.dart';` at the top if not present:

```dart
  /// Creates a standalone funnel seeded from [seedSystem]'s FunnelProfile (one
  /// empty peasant) at the top of the roster and returns its id.
  Future<String> addFunnel(String seedSystem) async {
    final id = _newId();
    final profile = funnelProfileFor(seedSystem);
    final seed = profile == null ? const <FunnelPeasant>[] : [profile.seedPeasant()];
    final ch = Character(
      id: id,
      name: '0-Level Funnel',
      funnel: FunnelSheet(seedSystem: seedSystem, peasants: seed),
    );
    await _persist([ch, ...await _ready]);
    return id;
  }

  /// Spawns a hero Character built by [buildHero] (top of roster) and marks
  /// peasant [index] of [funnelChar] graduated — in one persist. Returns the
  /// hero's id.
  Future<String> graduateFunnelPeasant(
      Character funnelChar, int index, Character Function(String id) buildHero) async {
    final id = _newId();
    final hero = buildHero(id);
    final updated =
        funnelChar.copyWith(funnel: funnelChar.funnel!.markGraduated(index));
    await _persist([
      hero,
      for (final c in await _ready) if (c.id == funnelChar.id) updated else c,
    ]);
    return id;
  }
```

- [ ] **Step 4: Run** `flutter test test/funnel_test.dart` — PASS. `flutter analyze lib/state/providers.dart` — clean.
- [ ] **Step 5: Commit**

```bash
git add lib/state/providers.dart test/funnel_test.dart
git commit -m "feat(funnel): addFunnel + graduateFunnelPeasant notifier methods"
```

---

## Task 6: `FunnelSheetView` UI

**Files:** Create `lib/features/funnel_sheet.dart`; Test `test/funnel_sheet_ui_test.dart` (create).

The view reads `character.funnel!` directly (parent rebuilds it, like `OseSheetView`). The seed profile drives which stat/flavor fields render.

- [ ] **Step 1: Write the failing test** — create `test/funnel_sheet_ui_test.dart`:

```dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/features/funnel_sheet.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _pump(WidgetTester tester, FunnelSheet sheet) async {
  tester.view.physicalSize = const Size(1200, 6000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({
    'juice.sessions.v1':
        '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    'juice.characters.v1.default': jsonEncode([
      {
        'id': 'f1',
        'name': '0-Level Funnel',
        'stats': [],
        'tracks': [],
        'tags': [],
        'funnel': sheet.toJson(),
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
        body: Consumer(builder: (_, ref, __) {
          final live =
              ref.watch(charactersProvider).valueOrNull?.firstOrNull ?? char;
          return FunnelSheetView(character: live, onBack: () {});
        }),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return container;
}

// A dcc-seeded funnel with one peasant.
FunnelSheet _dccFunnel() => FunnelSheet(seedSystem: 'dcc', peasants: const [
      FunnelPeasant(
          name: '', hp: 1,
          stats: {'str': 10, 'agi': 10, 'sta': 10, 'per': 10, 'int': 10, 'lck': 10},
          flavor: {'occupation': '', 'weapon': '', 'tradeGoods': ''}),
    ]);

void main() {
  testWidgets('renders the funnel header + add button', (tester) async {
    await _pump(tester, _dccFunnel());
    expect(find.byKey(const Key('funnel-sheet')), findsOneWidget);
    expect(find.textContaining('1 / 1 alive'), findsOneWidget);
    expect(find.byKey(const Key('funnel-add-peasant')), findsOneWidget);
  });

  testWidgets('add peasant raises count + caps at kFunnelMaxPeasants',
      (tester) async {
    final c = await _pump(tester, _dccFunnel());
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.byKey(const Key('funnel-add-peasant')));
      await tester.pumpAndSettle();
    }
    expect((await c.read(charactersProvider.future)).single.funnel!.peasants.length, 6);
    final btn = tester.widget<FilledButton>(
        find.byKey(const Key('funnel-add-peasant')));
    expect(btn.onPressed, isNull); // capped at 6
  });

  testWidgets('graduate spawns a hero + funnel persists', (tester) async {
    final c = await _pump(tester, _dccFunnel());
    await tester.tap(find.byKey(const Key('funnel-peasant-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('funnel-peasant-0-graduate')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('funnel-graduate-confirm')));
    await tester.pumpAndSettle();
    final list = await c.read(charactersProvider.future);
    expect(list.length, 2);                       // hero spawned
    expect(list.any((x) => x.dcc != null), true); // a DCC hero exists
    expect(list.firstWhere((x) => x.funnel != null)
        .funnel!.peasants[0].graduated, true);    // funnel persists
  });
}
```

- [ ] **Step 2: Run** `export PATH="$HOME/development/flutter/bin:$PATH" && flutter test test/funnel_sheet_ui_test.dart` — FAIL (`funnel_sheet.dart`/`FunnelSheetView` undefined).

- [ ] **Step 3: Create `lib/features/funnel_sheet.dart`**:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/funnel.dart';
import '../engine/models.dart';
import '../state/providers.dart';
import 'sheet_widgets.dart';

class FunnelSheetView extends ConsumerWidget {
  const FunnelSheetView(
      {super.key, required this.character, required this.onBack});
  final Character character;
  final VoidCallback onBack;

  FunnelSheet get _s => character.funnel!;

  void _save(WidgetRef ref, FunnelSheet next) => ref
      .read(charactersProvider.notifier)
      .replace(character.copyWith(funnel: next));

  Widget _stepper(String key, String label, int value,
          {required ValueChanged<int> onSet, int min = 0, int max = 9999}) =>
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final s = _s;
    final profile = funnelProfileFor(s.seedSystem);
    return ListView(
      key: const Key('funnel-sheet'),
      padding: const EdgeInsets.all(12),
      children: [
        sheetNameHeader(context, ref, character,
            onBack: onBack, nameKey: 'funnel-name'),
        Text('0-Level Funnel — ${s.seedSystem}',
            style: theme.textTheme.labelSmall),
        Text('${s.aliveCount} / ${s.peasants.length} alive · '
            '${s.graduatedCount} graduated',
            style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (profile == null)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text('No funnel profile for this system.'),
          )
        else ...[
          for (var i = 0; i < s.peasants.length; i++)
            _peasantCard(context, ref, s, profile, i),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              key: const Key('funnel-add-peasant'),
              onPressed: s.peasants.length >= kFunnelMaxPeasants
                  ? null
                  : () => _save(ref,
                      s.copyWith(peasants: [...s.peasants, profile.seedPeasant()])),
              icon: const Icon(Icons.person_add),
              label: const Text('Add peasant'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _peasantCard(BuildContext context, WidgetRef ref, FunnelSheet s,
      FunnelProfile profile, int i) {
    final p = s.peasants[i];
    void setP(FunnelPeasant np) {
      final list = [...s.peasants];
      list[i] = np;
      _save(ref, s.copyWith(peasants: list));
    }

    final dead = !p.alive;
    final titleStyle = p.graduated
        ? const TextStyle(color: Colors.grey)
        : dead
            ? const TextStyle(
                decoration: TextDecoration.lineThrough, color: Colors.grey)
            : null;
    final statusText = p.graduated
        ? 'graduated'
        : (p.alive ? 'alive' : 'dead');

    return Card(
      child: ExpansionTile(
        key: Key('funnel-peasant-$i'),
        title: Text(p.name.isEmpty ? 'Peasant ${i + 1}' : p.name,
            style: titleStyle),
        subtitle: Text('HP ${p.hp}  •  $statusText'),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          TextFormField(
            key: Key('funnel-peasant-$i-name'),
            initialValue: p.name,
            enabled: !p.graduated,
            decoration: const InputDecoration(labelText: 'Name'),
            onChanged: (v) => setP(p.copyWith(name: v)),
          ),
          for (final f in profile.flavorFields)
            TextFormField(
              key: Key('funnel-peasant-$i-flavor-${f.key}'),
              initialValue: p.flavor[f.key] ?? '',
              enabled: !p.graduated,
              decoration: InputDecoration(labelText: f.label),
              onChanged: (v) =>
                  setP(p.copyWith(flavor: {...p.flavor, f.key: v})),
            ),
          const SizedBox(height: 8),
          _stepper('funnel-peasant-$i-hp', 'HP', p.hp,
              min: profile.hpMin,
              max: profile.hpMax,
              onSet: p.graduated ? (_) {} : (v) => setP(p.copyWith(hp: v))),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final st in profile.statKeys)
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text(st.label,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                _stepper('funnel-peasant-$i-${st.key}',
                    '', p.stats[st.key] ?? profile.statDefault,
                    min: profile.statMin,
                    max: profile.statMax,
                    onSet: p.graduated
                        ? (_) {}
                        : (v) => setP(
                            p.copyWith(stats: {...p.stats, st.key: v}))),
              ]),
          ]),
          const SizedBox(height: 8),
          if (!p.graduated)
            Wrap(alignment: WrapAlignment.spaceBetween, children: [
              TextButton(
                key: Key('funnel-peasant-$i-${p.alive ? "kill" : "revive"}'),
                onPressed: () => setP(p.copyWith(alive: !p.alive)),
                child: Text(p.alive ? 'Mark dead' : 'Mark alive'),
              ),
              if (p.alive)
                FilledButton(
                  key: Key('funnel-peasant-$i-graduate'),
                  onPressed: () => _graduateDialog(context, ref, s, i),
                  child: const Text('Graduate →'),
                ),
            ]),
        ],
      ),
    );
  }

  Future<void> _graduateDialog(
      BuildContext context, WidgetRef ref, FunnelSheet s, int i) async {
    // target systems = enabled sheet systems that have a profile; default = seed.
    final enabled =
        ref.read(sessionsProvider).valueOrNull?.activeMeta.enabledSystems ??
            const <String>{};
    final targets = kFunnelProfiles.keys
        .where((sys) => sys == s.seedSystem || enabled.contains(sys))
        .toList();
    if (!targets.contains(s.seedSystem) && funnelProfileFor(s.seedSystem) != null) {
      targets.insert(0, s.seedSystem);
    }
    var target = s.seedSystem;
    var picks = {...funnelProfileFor(target)!.defaultPicks()};

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final profile = funnelProfileFor(target)!;
          return AlertDialog(
            title: const Text('Graduate survivor'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButton<String>(
                key: const Key('funnel-graduate-target'),
                value: target,
                isExpanded: true,
                items: targets
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) => setState(() {
                  target = v ?? target;
                  picks = {...funnelProfileFor(target)!.defaultPicks()};
                }),
              ),
              for (final ch in profile.graduateChoices)
                DropdownButton<String>(
                  key: Key('funnel-graduate-${ch.key}'),
                  value: picks[ch.key],
                  isExpanded: true,
                  items: ch.options
                      .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => picks[ch.key] = v ?? picks[ch.key]!),
                ),
            ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              FilledButton(
                  key: const Key('funnel-graduate-confirm'),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Graduate')),
            ],
          );
        },
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final profile = funnelProfileFor(target)!;
    final peasant = s.peasants[i];
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(charactersProvider.notifier).graduateFunnelPeasant(
        character, i, (id) => profile.graduate(id, peasant, picks));
    final cls = picks['className'] ?? picks.values.firstOrNull ?? '';
    messenger.showSnackBar(SnackBar(
      content: Text(
          '${peasant.name.isEmpty ? "Peasant" : peasant.name} graduated as a '
          '$target${cls.isEmpty ? "" : " $cls"}'),
      duration: const Duration(seconds: 3),
    ));
  }
}
```

- [ ] **Step 4: Run** `flutter test test/funnel_sheet_ui_test.dart` — PASS. `flutter analyze lib/features/funnel_sheet.dart` — clean.
- [ ] **Step 5: Commit**

```bash
git add lib/features/funnel_sheet.dart test/funnel_sheet_ui_test.dart
git commit -m "feat(funnel): FunnelSheetView (peasants + graduation)"
```

---

## Task 7: Register `funnel` system + roster wiring + creation

**Files:** Modify `lib/engine/models.dart`, `lib/shared/home_shell.dart`, `lib/engine/campaign_surfaces.dart`, `lib/state/providers.dart` (done), `lib/features/tracker_screen.dart`, `lib/engine/campaign_presets.dart`; Test `test/funnel_test.dart`.

- [ ] **Step 1: Write the failing test** — append to `test/funnel_test.dart` (add `import 'package:juice_oracle/engine/campaign_presets.dart';` and `import 'package:juice_oracle/shared/home_shell.dart';`):

```dart
  group('funnel system registration', () {
    test('funnel is a known tools system', () {
      expect(kKnownSystems, contains('funnel'));
      expect(kSystemCategory['funnel'], SystemCategory.tools);
    });
    test('blurb exists', () {
      expect(kSystemBlurbs['funnel'], isNotNull);
    });
    test('solo-dcc preset includes funnel', () {
      final p = kCampaignPresets.firstWhere((x) => x.id == 'solo-dcc');
      expect(p.systems, contains('funnel'));
    });
    test('solo-funnel preset resolves', () {
      final p = kCampaignPresets.firstWhere((x) => x.id == 'solo-funnel');
      final (mode, systems) = presetConfig(p);
      expect(systems, contains('funnel'));
      expect(mode, CampaignMode.party);
    });
  });
```

- [ ] **Step 2: Run** `flutter test test/funnel_test.dart -n "funnel system registration"` — FAIL.

- [ ] **Step 3: Make the edits.**
  - **models.dart `kKnownSystems`:** add `'funnel',` (after `'dcc',`).
  - **models.dart `kSystemCategory`:** add `'funnel': SystemCategory.tools,` (after `'lonelog': …`).
  - **home_shell.dart `kSystemBlurbs`:** add
    ```dart
      'funnel':
          '0-Level Funnel: run a pack of doomed peasants, then graduate '
              'survivors into full characters of any enabled system.',
    ```
  - **campaign_surfaces.dart `_table['Sheet']`:** after the DCC row:
    ```dart
        SurfaceRow('0-Level Funnel', requiresSystem: 'funnel'),
    ```
  - **campaign_presets.dart:** add `'funnel'` to the `solo-dcc` entry's `systems` set → `{'dcc', 'juice', 'party', 'funnel'}`. Add a new preset after `solo-dcc`:
    ```dart
      CampaignPreset(
          id: 'solo-funnel',
          label: 'Character Funnel',
          kind: 'Session-zero gauntlet',
          blurb: 'Doomed peasants → survivors',
          mode: CampaignMode.party,
          systems: {'funnel', 'juice', 'party'}),
    ```
    Add to `kPresetIcons`: `'solo-funnel': Icons.groups,`.
  - **tracker_screen.dart:**
    - `_onAdd` guard: add ` && !systems.contains('funnel')` to the chain.
    - options list (after `new-dcc` record):
      ```dart
            if (systems.contains('funnel'))
              (
                key: 'new-funnel',
                value: 'funnel',
                label: '0-Level Funnel',
                blurb: 'Doomed peasants → graduate survivors into any system.'
              ),
      ```
    - choice dispatch (after the `dcc` arm): the funnel needs a **seed-system pick** before creating. Add:
      ```dart
          } else if (choice == 'funnel') {
            await _newFunnel(context);
      ```
    - helper (next to `_newDcc`):
      ```dart
        Future<void> _newFunnel(BuildContext context) async {
          final enabled = ref
                  .read(sessionsProvider)
                  .valueOrNull
                  ?.activeMeta
                  .enabledSystems ??
              const <String>{};
          final seeds = kFunnelProfiles.keys
              .where((s) => enabled.contains(s))
              .toList();
          if (seeds.isEmpty) {
            // No profiled sheet system enabled — default to dcc so the funnel works.
            final id =
                await ref.read(charactersProvider.notifier).addFunnel('dcc');
            if (mounted) setState(() => _editingId = id);
            return;
          }
          final seed = seeds.length == 1
              ? seeds.first
              : await showDialog<String>(
                  context: context,
                  builder: (ctx) => SimpleDialog(
                    title: const Text('Funnel for which system?'),
                    children: [
                      for (final s in seeds)
                        SimpleDialogOption(
                          key: Key('funnel-seed-$s'),
                          onPressed: () => Navigator.pop(ctx, s),
                          child: Text(s),
                        ),
                    ],
                  ),
                );
          if (seed == null || !mounted) return;
          final id = await ref.read(charactersProvider.notifier).addFunnel(seed);
          if (mounted) setState(() => _editingId = id);
        }
      ```
    - sheet-dispatch (after the `c.dcc != null` block):
      ```dart
                    if (c.funnel != null) {
                      return FunnelSheetView(
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
    - imports at the top: `import 'funnel_sheet.dart';` and `import '../engine/funnel.dart';`.

- [ ] **Step 4: Run** `flutter test test/funnel_test.dart` then the FULL suite `flutter test`. Fix any registry-count tests (e.g. `campaign_presets_test.dart` exact id/preset counts — bump them to include `funnel` + `solo-funnel`; a surfaces test that checks `requiresSystem ⊆ kKnownSystems`). Report which existing tests you updated and why. `flutter analyze` — clean.
- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(funnel): register funnel system (roster, dispatch, surfaces, presets)"
```
(Stage only your files; leave the pre-existing macos/* + docs/ working-tree noise unstaged.)

---

## Task 8: Profiles for the currentHp/maxHp Map-stat systems (dnd, shadowdark, argosa, ose)

**Files:** Modify `lib/engine/funnel.dart`; Test `test/funnel_test.dart`.

These four store stats in a `Map` and have a `currentHp`/`maxHp` pool; their `copyWith` clamps + defaults. Each mapper is uniform.

- [ ] **Step 1: Write the failing test** — append to `test/funnel_test.dart`:

```dart
  group('profiles: map-stat hp systems', () {
    const peasant = FunnelPeasant(
      name: 'Hero', hp: 7,
      stats: {'str': 15, 'dex': 13, 'con': 14, 'int': 8, 'wis': 9, 'cha': 11},
    );
    test('dnd', () {
      final h = funnelProfileFor('dnd')!
          .graduate('h', peasant, {'className': 'Wizard'});
      expect(h.dnd, isNotNull);
      expect(h.dnd!.abilities['str'], 15);
      expect(h.dnd!.currentHp, 7);
      expect(h.dnd!.maxHp, 7);
      expect(h.dnd!.className, 'Wizard');
      expect(h.name, 'Hero');
    });
    test('shadowdark', () {
      final h = funnelProfileFor('shadowdark')!.graduate('h', peasant,
          {'className': 'Wizard', 'ancestry': 'Human', 'alignment': 'Neutral'});
      expect(h.shadowdark!.abilities['str'], 15);
      expect(h.shadowdark!.currentHp, 7);
      expect(h.shadowdark!.className, 'Wizard');
    });
    test('argosa', () {
      final h = funnelProfileFor('argosa')!
          .graduate('h', peasant, {'className': funnelProfileFor('argosa')!.graduateChoices.first.options.first});
      expect(h.argosa!.stats['str'], 15);
      expect(h.argosa!.currentHp, 7);
    });
    test('ose', () {
      final h = funnelProfileFor('ose')!.graduate('h', peasant,
          {'className': 'Fighter', 'alignment': 'Neutral'});
      expect(h.ose!.stats['str'], 15);
      expect(h.ose!.currentHp, 7);
      expect(h.ose!.className, 'Fighter');
    });
  });
```

- [ ] **Step 2: Run** `flutter test test/funnel_test.dart -n "map-stat hp systems"` — FAIL.

- [ ] **Step 3: Add these four entries to `kFunnelProfiles`** in `lib/engine/funnel.dart`. (Stat keys/ranges/choices per the verified table; the sheet's `copyWith` clamps.)

```dart
  'dnd': FunnelProfile(
    system: 'dnd',
    statKeys: const [
      (key: 'str', label: 'STR'), (key: 'dex', label: 'DEX'),
      (key: 'con', label: 'CON'), (key: 'int', label: 'INT'),
      (key: 'wis', label: 'WIS'), (key: 'cha', label: 'CHA'),
    ],
    statMin: 3, statMax: 18, statDefault: 10,
    flavorFields: const [(key: 'background', label: 'Background')],
    hpMin: 1, hpMax: 10,
    graduateChoices: [FunnelChoice('className', 'Class', kDndClasses)],
    graduate: (id, p, picks) {
      final base = Character.forSheet('dnd', id);
      return base.copyWith(
        name: _heroName(p, base),
        dnd: base.dnd!.copyWith(
          abilities: p.stats,
          currentHp: p.hp, maxHp: p.hp,
          className: picks['className'] ?? 'Fighter',
        ),
      );
    },
  ),
  'shadowdark': FunnelProfile(
    system: 'shadowdark',
    statKeys: const [
      (key: 'str', label: 'STR'), (key: 'dex', label: 'DEX'),
      (key: 'con', label: 'CON'), (key: 'int', label: 'INT'),
      (key: 'wis', label: 'WIS'), (key: 'cha', label: 'CHA'),
    ],
    statMin: 3, statMax: 18, statDefault: 10,
    flavorFields: const [(key: 'background', label: 'Background')],
    hpMin: 1, hpMax: 8,
    graduateChoices: [
      FunnelChoice('className', 'Class', kShadowdarkClasses),
      FunnelChoice('ancestry', 'Ancestry', kShadowdarkAncestries),
      FunnelChoice('alignment', 'Alignment', kShadowdarkAlignments),
    ],
    graduate: (id, p, picks) {
      final base = Character.forSheet('shadowdark', id);
      return base.copyWith(
        name: _heroName(p, base),
        shadowdark: base.shadowdark!.copyWith(
          abilities: p.stats,
          currentHp: p.hp, maxHp: p.hp,
          className: picks['className'] ?? 'Fighter',
          ancestry: picks['ancestry'] ?? 'Human',
          alignment: picks['alignment'] ?? 'Neutral',
        ),
      );
    },
  ),
  'argosa': FunnelProfile(
    system: 'argosa',
    statKeys: const [
      (key: 'str', label: 'STR'), (key: 'dex', label: 'DEX'),
      (key: 'con', label: 'CON'), (key: 'int', label: 'INT'),
      (key: 'per', label: 'PER'), (key: 'wil', label: 'WIL'),
      (key: 'cha', label: 'CHA'),
    ],
    statMin: 3, statMax: 18, statDefault: 10,
    flavorFields: const [(key: 'occupation', label: 'Occupation')],
    hpMin: 1, hpMax: 10,
    graduateChoices: [FunnelChoice('className', 'Class', kArgosaClasses)],
    graduate: (id, p, picks) {
      final base = Character.forSheet('argosa', id);
      return base.copyWith(
        name: _heroName(p, base),
        argosa: base.argosa!.copyWith(
          stats: p.stats,
          currentHp: p.hp, maxHp: p.hp,
          className: picks['className'] ?? kArgosaClasses.first,
        ),
      );
    },
  ),
  'ose': FunnelProfile(
    system: 'ose',
    statKeys: const [
      (key: 'str', label: 'STR'), (key: 'int', label: 'INT'),
      (key: 'wis', label: 'WIS'), (key: 'dex', label: 'DEX'),
      (key: 'con', label: 'CON'), (key: 'cha', label: 'CHA'),
    ],
    statMin: 3, statMax: 18, statDefault: 10,
    flavorFields: const [(key: 'occupation', label: 'Occupation')],
    hpMin: 1, hpMax: 8,
    graduateChoices: [
      FunnelChoice('className', 'Class', kOseClasses),
      FunnelChoice('alignment', 'Alignment', kOseAlignments),
    ],
    graduate: (id, p, picks) {
      final base = Character.forSheet('ose', id);
      return base.copyWith(
        name: _heroName(p, base),
        ose: base.ose!.copyWith(
          stats: p.stats,
          currentHp: p.hp, maxHp: p.hp,
          className: picks['className'] ?? 'Fighter',
          alignment: picks['alignment'] ?? 'Neutral',
        ),
      );
    },
  ),
```

Verify the exact `copyWith` param names against `models.dart` (`abilities` for dnd/shadowdark, `stats` for argosa/ose) before running. If any sheet's `copyWith` lacks a named param used here, adapt to the real signature (do not change the sheet).

- [ ] **Step 4: Run** `flutter test test/funnel_test.dart` — PASS. `flutter analyze lib/engine/funnel.dart` — clean.
- [ ] **Step 5: Commit**

```bash
git add lib/engine/funnel.dart test/funnel_test.dart
git commit -m "feat(funnel): dnd/shadowdark/argosa/ose profiles"
```

---

## Task 9: Profiles for the modifier-stat systems (nimble, draw-steel, knave, kal-arath)

**Files:** Modify `lib/engine/funnel.dart`; Test `test/funnel_test.dart`.

These store stats as modifiers (different ranges) and have an HP pool (Draw Steel uses `currentStamina/maxStamina`). Seed peasants use a modifier-appropriate default (0). Knave has no class choice.

- [ ] **Step 1: Write the failing test** — append:

```dart
  group('profiles: modifier-stat systems', () {
    test('nimble', () {
      const peasant = FunnelPeasant(hp: 12, stats: {'str': 2, 'dex': 1, 'int': 0, 'wis': -1});
      final h = funnelProfileFor('nimble')!
          .graduate('h', peasant, {'className': kNimbleClasses.first});
      expect(h.nimble!.stats['str'], 2);
      expect(h.nimble!.currentHp, 12);
      expect(funnelProfileFor('nimble')!.statDefault, 0);
    });
    test('draw-steel maps stamina', () {
      const peasant = FunnelPeasant(hp: 20,
          stats: {'might': 2, 'agility': 1, 'reason': 0, 'intuition': 0, 'presence': -1});
      final h = funnelProfileFor('draw-steel')!
          .graduate('h', peasant, {'className': kDrawSteelClasses.first});
      expect(h.drawSteel!.characteristics['might'], 2);
      expect(h.drawSteel!.currentStamina, 20);
      expect(h.drawSteel!.maxStamina, 20);
    });
    test('knave has no class choice', () {
      expect(funnelProfileFor('knave')!.graduateChoices, isEmpty);
      const peasant = FunnelPeasant(hp: 6, stats: {'str': 3, 'dex': 2});
      final h = funnelProfileFor('knave')!.graduate('h', peasant, const {});
      expect(h.knave!.stats['str'], 3);
      expect(h.knave!.currentHp, 6);
    });
    test('kal-arath', () {
      const peasant = FunnelPeasant(hp: 8, stats: {'str': 3, 'tou': 2, 'agi': 1, 'int': 0, 'pre': -1});
      final h = funnelProfileFor('kal-arath')!.graduate('h', peasant,
          {'archetype': kKalArathArchetypes.first, 'pact': kKalArathPacts.first});
      expect(h.kalArath!.stats['str'], 3);
      expect(h.kalArath!.currentHp, 8);
    });
  });
```

- [ ] **Step 2: Run** `flutter test test/funnel_test.dart -n "modifier-stat systems"` — FAIL.

- [ ] **Step 3: Add these entries to `kFunnelProfiles`:**

```dart
  'nimble': FunnelProfile(
    system: 'nimble',
    statKeys: const [
      (key: 'str', label: 'STR'), (key: 'dex', label: 'DEX'),
      (key: 'int', label: 'INT'), (key: 'wis', label: 'WIS'),
    ],
    statMin: -9, statMax: 9, statDefault: 0,
    flavorFields: const [(key: 'ancestry', label: 'Ancestry')],
    hpMin: 1, hpMax: 20,
    graduateChoices: [FunnelChoice('className', 'Class', kNimbleClasses)],
    graduate: (id, p, picks) {
      final base = Character.forSheet('nimble', id);
      return base.copyWith(
        name: _heroName(p, base),
        nimble: base.nimble!.copyWith(
          stats: p.stats,
          currentHp: p.hp, maxHp: p.hp,
          className: picks['className'] ?? kNimbleClasses.first,
        ),
      );
    },
  ),
  'draw-steel': FunnelProfile(
    system: 'draw-steel',
    statKeys: const [
      (key: 'might', label: 'Might'), (key: 'agility', label: 'Agility'),
      (key: 'reason', label: 'Reason'), (key: 'intuition', label: 'Intuition'),
      (key: 'presence', label: 'Presence'),
    ],
    statMin: -5, statMax: 5, statDefault: 0,
    flavorFields: const [(key: 'ancestry', label: 'Ancestry')],
    hpMin: 1, hpMax: 24,
    graduateChoices: [FunnelChoice('className', 'Class', kDrawSteelClasses)],
    graduate: (id, p, picks) {
      final base = Character.forSheet('draw-steel', id);
      return base.copyWith(
        name: _heroName(p, base),
        drawSteel: base.drawSteel!.copyWith(
          characteristics: p.stats,
          currentStamina: p.hp, maxStamina: p.hp,
          className: picks['className'] ?? kDrawSteelClasses.first,
        ),
      );
    },
  ),
  'knave': FunnelProfile(
    system: 'knave',
    statKeys: const [
      (key: 'str', label: 'STR'), (key: 'dex', label: 'DEX'),
      (key: 'con', label: 'CON'), (key: 'int', label: 'INT'),
      (key: 'wis', label: 'WIS'), (key: 'cha', label: 'CHA'),
    ],
    statMin: 0, statMax: 10, statDefault: 0,
    flavorFields: const [(key: 'career', label: 'Career')],
    hpMin: 1, hpMax: 8,
    graduateChoices: const [],
    graduate: (id, p, picks) {
      final base = Character.forSheet('knave', id);
      return base.copyWith(
        name: _heroName(p, base),
        knave: base.knave!.copyWith(
          stats: p.stats,
          currentHp: p.hp, maxHp: p.hp,
        ),
      );
    },
  ),
  'kal-arath': FunnelProfile(
    system: 'kal-arath',
    statKeys: const [
      (key: 'str', label: 'STR'), (key: 'tou', label: 'TOU'),
      (key: 'agi', label: 'AGI'), (key: 'int', label: 'INT'),
      (key: 'pre', label: 'PRE'),
    ],
    statMin: -1, statMax: 5, statDefault: 0,
    flavorFields: const [(key: 'doom', label: 'Doom')],
    hpMin: 1, hpMax: 10,
    graduateChoices: [
      FunnelChoice('archetype', 'Archetype', kKalArathArchetypes),
      FunnelChoice('pact', 'Demonic Pact', kKalArathPacts),
    ],
    graduate: (id, p, picks) {
      final base = Character.forSheet('kal-arath', id);
      return base.copyWith(
        name: _heroName(p, base),
        kalArath: base.kalArath!.copyWith(
          stats: p.stats,
          currentHp: p.hp, maxHp: p.hp,
          archetype: picks['archetype'] ?? kKalArathArchetypes.first,
          pact: picks['pact'] ?? kKalArathPacts.first,
        ),
      );
    },
  ),
```

Verify each `copyWith` param name against `models.dart` (`characteristics` for draw-steel; `archetype`/`pact` for kal-arath; KalArathSheet `currentHp`/`maxHp`). Adapt to the real signature if any differ.

- [ ] **Step 4: Run** `flutter test test/funnel_test.dart` — PASS. Analyze clean.
- [ ] **Step 5: Commit**

```bash
git add lib/engine/funnel.dart test/funnel_test.dart
git commit -m "feat(funnel): nimble/draw-steel/knave/kal-arath profiles"
```

---

## Task 10: Profiles for individual-field + meter systems (cairn, ironsworn, starforged)

**Files:** Modify `lib/engine/funnel.dart`; Test `test/funnel_test.dart`.

Cairn stores stats as individual int fields + has an HP pool. Ironsworn/Starforged store stats as individual fields + have **no HP pool** (the mapper does NOT map peasant HP; meters stay at premade defaults).

- [ ] **Step 1: Write the failing test** — append:

```dart
  group('profiles: individual-field + meter systems', () {
    test('cairn maps individual stats + hp + background', () {
      const peasant = FunnelPeasant(hp: 5, stats: {'str': 12, 'dex': 9, 'wil': 14});
      final h = funnelProfileFor('cairn')!.graduate('h', peasant,
          {'background': kCairnBackgrounds.first});
      expect(h.cairn!.str, 12);
      expect(h.cairn!.dex, 9);
      expect(h.cairn!.wil, 14);
      expect(h.cairn!.currentHp, 5);
      expect(h.cairn!.background, kCairnBackgrounds.first);
    });
    test('ironsworn maps individual stats, ignores hp (no pool)', () {
      const peasant = FunnelPeasant(hp: 4,
          stats: {'edge': 2, 'heart': 1, 'iron': 3, 'shadow': 1, 'wits': 2});
      final h = funnelProfileFor('ironsworn')!.graduate('h', peasant, const {});
      expect(h.ironsworn!.edge, 2);
      expect(h.ironsworn!.iron, 3);
      expect(funnelProfileFor('ironsworn')!.graduateChoices, isEmpty);
    });
    test('starforged maps individual stats', () {
      const peasant = FunnelPeasant(hp: 4,
          stats: {'edge': 1, 'heart': 2, 'iron': 1, 'shadow': 3, 'wits': 2});
      final h = funnelProfileFor('starforged')!.graduate('h', peasant, const {});
      expect(h.starforged!.shadow, 3);
    });
  });
```

- [ ] **Step 2: Run** `flutter test test/funnel_test.dart -n "individual-field"` — FAIL.

- [ ] **Step 3: Add these entries.** Stats map by reading individual keys from `p.stats` (null → keep sheet default). Meter systems map no HP.

```dart
  'cairn': FunnelProfile(
    system: 'cairn',
    statKeys: const [
      (key: 'str', label: 'STR'), (key: 'dex', label: 'DEX'),
      (key: 'wil', label: 'WIL'),
    ],
    statMin: 3, statMax: 18, statDefault: 10,
    flavorFields: const [],
    hpMin: 1, hpMax: 8,
    graduateChoices: [FunnelChoice('background', 'Background', kCairnBackgrounds)],
    graduate: (id, p, picks) {
      final base = Character.forSheet('cairn', id);
      return base.copyWith(
        name: _heroName(p, base),
        cairn: base.cairn!.copyWith(
          str: p.stats['str'], dex: p.stats['dex'], wil: p.stats['wil'],
          currentHp: p.hp, maxHp: p.hp,
          background: picks['background'] ?? kCairnBackgrounds.first,
        ),
      );
    },
  ),
  'ironsworn': FunnelProfile(
    system: 'ironsworn',
    statKeys: const [
      (key: 'edge', label: 'Edge'), (key: 'heart', label: 'Heart'),
      (key: 'iron', label: 'Iron'), (key: 'shadow', label: 'Shadow'),
      (key: 'wits', label: 'Wits'),
    ],
    statMin: 1, statMax: 3, statDefault: 1,
    flavorFields: const [],
    hpMin: 0, hpMax: 5,   // peasant HP not mapped (no pool); shown for tracking
    graduateChoices: const [],
    graduate: (id, p, picks) {
      final base = Character.forSheet('ironsworn', id);
      return base.copyWith(
        name: _heroName(p, base),
        ironsworn: base.ironsworn!.copyWith(
          edge: p.stats['edge'], heart: p.stats['heart'],
          iron: p.stats['iron'], shadow: p.stats['shadow'],
          wits: p.stats['wits'],
        ),
      );
    },
  ),
  'starforged': FunnelProfile(
    system: 'starforged',
    statKeys: const [
      (key: 'edge', label: 'Edge'), (key: 'heart', label: 'Heart'),
      (key: 'iron', label: 'Iron'), (key: 'shadow', label: 'Shadow'),
      (key: 'wits', label: 'Wits'),
    ],
    statMin: 1, statMax: 3, statDefault: 1,
    flavorFields: const [],
    hpMin: 0, hpMax: 5,
    graduateChoices: const [],
    graduate: (id, p, picks) {
      final base = Character.forSheet('starforged', id);
      return base.copyWith(
        name: _heroName(p, base),
        starforged: base.starforged!.copyWith(
          edge: p.stats['edge'], heart: p.stats['heart'],
          iron: p.stats['iron'], shadow: p.stats['shadow'],
          wits: p.stats['wits'],
        ),
      );
    },
  ),
```

Verify CairnSheet/IronswornSheet/StarforgedSheet `copyWith` accept these individual `int?` params (per recon they do). Adapt if a name differs.

- [ ] **Step 4: Run** `flutter test test/funnel_test.dart` — PASS. Analyze clean.
- [ ] **Step 5: Commit**

```bash
git add lib/engine/funnel.dart test/funnel_test.dart
git commit -m "feat(funnel): cairn/ironsworn/starforged profiles"
```

---

## Task 11: Profile registry completeness test

**Files:** Test `test/funnel_test.dart`.

A parameterized guard so no profile drifts + every ruleset is covered.

- [ ] **Step 1: Write the test** — append:

```dart
  group('profile registry completeness', () {
    test('every kSystemCategory ruleset (except sundered_isles alias) has a profile', () {
      final rulesets = kSystemCategory.entries
          .where((e) => e.value == SystemCategory.ruleset)
          .map((e) => e.key)
          .toSet();
      for (final sys in rulesets) {
        expect(kFunnelProfiles.containsKey(sys), true,
            reason: 'missing FunnelProfile for ruleset "$sys"');
      }
    });
    test('every profile is well-formed', () {
      kFunnelProfiles.forEach((sys, p) {
        expect(p.system, sys);
        expect(p.statKeys, isNotEmpty, reason: '$sys statKeys');
        expect(p.statMin < p.statMax, true, reason: '$sys range');
        expect(p.statDefault >= p.statMin && p.statDefault <= p.statMax, true,
            reason: '$sys default in range');
        expect(p.hpMin <= p.hpMax, true, reason: '$sys hp range');
        for (final c in p.graduateChoices) {
          expect(c.options, isNotEmpty, reason: '$sys choice ${c.key}');
        }
        // graduate() produces the target sheet field, name carried.
        final peasant = p.seedPeasant().copyWith(name: 'X');
        final hero = p.graduate('hid', peasant, p.defaultPicks());
        expect(hero.id, 'hid');
        expect(hero.name, 'X');
      });
    });
  });
```

- [ ] **Step 2: Run** `flutter test test/funnel_test.dart -n "registry completeness"`.
  - If it FAILS because a ruleset has no profile (e.g. `sundered_isles` is categorized as a ruleset), decide: `sundered_isles` reuses the Starforged sheet — either add a `sundered_isles` profile entry (a copy of starforged's whose `graduate` calls `Character.forSheet('sundered_isles', id)` so the StarforgedSheet gets `assetRuleset: 'sundered_isles'`), OR exclude it explicitly in the test if it is not in `kSystemCategory` as a standalone ruleset. Check `kSystemCategory` first; if `sundered_isles` is present, add the profile (preferred). Document the choice.
- [ ] **Step 3:** Make it pass (add the missing profile if needed).
- [ ] **Step 4: Run** `flutter test test/funnel_test.dart` — PASS.
- [ ] **Step 5: Commit**

```bash
git add lib/engine/funnel.dart test/funnel_test.dart
git commit -m "test(funnel): profile registry completeness guard"
```

---

## Task 12: DCC refactor — strip the funnel from DccSheet (leveled-only)

**Files:** Modify `lib/engine/models.dart`, `lib/features/dcc_sheet.dart`, `lib/engine/funnel.dart`; Test `test/dcc_sheet_test.dart`, `test/dcc_sheet_ui_test.dart`.

Now that the generic funnel + DCC profile work, remove DCC's bespoke funnel so there is one codebase.

- [ ] **Step 1: Update DCC tests first (red).** In `test/dcc_sheet_test.dart`: delete the `DccPeasant` group and the `DccSheet` tests that reference `mode`/`peasants`/`graduate`/`isFunnel` (the funnel/graduate behavior is now covered by `test/funnel_test.dart`'s DCC profile tests). Keep the leveled round-trip + `dccAbilityMod` + constants + the `maybeFromJson sanitizes corrupted dice tokens` test + the registration/blurb tests. Update the `premade` test to expect a leveled sheet:

```dart
    test('premade is a leveled level-1 hero', () {
      final s = DccSheet.premade();
      expect(s.className, 'Warrior');
      expect(s.level, 1);
    });
```

In `test/dcc_sheet_ui_test.dart`: delete the `DccSheetView funnel` group entirely (funnel UI is gone); keep the `DccSheetView leveled` group, but its `leveledWarrior()`/`leveledCleric()` builders currently call `.graduate(...)` — rewrite them to build a leveled DccSheet directly:

```dart
    DccSheet leveledWarrior() => const DccSheet(
          className: 'Warrior', alignment: 'Lawful',
          stats: {'str': 16, 'agi': 12, 'sta': 13, 'per': 9, 'int': 8, 'lck': 11},
          lckMax: 11, currentHp: 8, maxHp: 8,
        );
    DccSheet leveledCleric() => const DccSheet(
          className: 'Cleric', alignment: 'Lawful',
          stats: {'str': 10, 'agi': 10, 'sta': 10, 'per': 14, 'int': 9, 'lck': 10},
          lckMax: 10, currentHp: 6, maxHp: 6,
        );
```
(`luckTokensSection` test expecting `11 / 11` still holds with lckMax 11.)

- [ ] **Step 2: Run** `flutter test test/dcc_sheet_test.dart test/dcc_sheet_ui_test.dart` — FAIL (still references removed members OR compiles against the old DccSheet). Confirm the failures are about the funnel members.

- [ ] **Step 3: Strip DccSheet** in `lib/engine/models.dart`:
  - Delete the `DccPeasant` class entirely.
  - In `DccSheet`: remove the `mode` and `peasants` constructor params + fields; remove `isFunnel`; remove the `graduate(int i, …)` method. Change the constructor default so a premade is leveled (drop `mode`/`peasants` defaults). `premade()` stays `const DccSheet()` (now leveled).
  - In `copyWith`: remove `mode`/`peasants` params + their body lines.
  - In `toJson`/`maybeFromJson`: remove the `mode`/`peasants` keys.
  - In `Character.forSheet`, change the `'dcc'` arm name to `'New DCC character'`.
  - In `Character.withHpDelta`, change `if (dcc != null && dcc!.mode == 'leveled')` → `if (dcc != null)`.

- [ ] **Step 4: Strip the funnel branch from `lib/features/dcc_sheet.dart`:** delete `_buildFunnel`, `_peasantCard`, `_graduateDialog`, and the funnel `_stepper` usages tied to peasants; the `build` method becomes just the leveled render (remove the `isFunnel ? _buildFunnel : _buildLeveled` switch — call the leveled body directly). Remove now-unused helpers/imports.

- [ ] **Step 5: Fix the DCC profile in `lib/engine/funnel.dart`:** remove the `mode: 'leveled',` argument from the DCC mapper's `copyWith` (the param no longer exists).

- [ ] **Step 6: Run** `flutter test test/dcc_sheet_test.dart test/dcc_sheet_ui_test.dart test/funnel_test.dart test/funnel_sheet_ui_test.dart` — PASS. `flutter analyze lib/engine/models.dart lib/features/dcc_sheet.dart lib/engine/funnel.dart` — clean (no dangling references to `DccPeasant`/`mode`/`peasants`/`graduate`).

- [ ] **Step 7: Commit**

```bash
git add lib/engine/models.dart lib/features/dcc_sheet.dart lib/engine/funnel.dart \
  test/dcc_sheet_test.dart test/dcc_sheet_ui_test.dart
git commit -m "refactor(dcc): remove bespoke funnel; DccSheet is leveled-only"
```

---

## Task 13: Full verification + docs

**Files:** Modify `CLAUDE.md`; verify whole suite + analyzer.

- [ ] **Step 1: Run the analyzer** — `export PATH="$HOME/development/flutter/bin:$PATH" && flutter analyze`. Expected: no new issues. Fix any funnel-introduced warnings (unused imports, etc.).

- [ ] **Step 2: Run the full suite** — `flutter test`. Expected: all pass. If a registry/count test fails (presets count, surfaces coverage, kKnownSystems enumeration), update its expected values to include `funnel`/`solo-funnel`. Report which tests changed.

- [ ] **Step 3: Add a CLAUDE.md note** after the DCC bullet:

```markdown
- The **0-Level Funnel** is generalized & system-agnostic
  (`lib/engine/funnel.dart` + `FunnelSheet`/`FunnelPeasant` in `models.dart`,
  rendered by `lib/features/funnel_sheet.dart` when `Character.funnel` is set;
  opt-in `funnel` system, `SystemCategory.tools`, NOT in `kAllSystems`). A funnel
  is a standalone roster entity holding up to `kFunnelMaxPeasants` (6) peasants;
  graduating a survivor **spawns a new hero Character** (the funnel persists; the
  peasant is flagged `graduated`) via `CharacterNotifier.graduateFunnelPeasant`.
  Each sheet system registers a `FunnelProfile` in `kFunnelProfiles` (peasant
  stat keys + flavor fields + HP rule + a `graduate` closure that builds that
  system's hero, reusing the sheet's own `copyWith` for clamping; meter systems
  ironsworn/starforged map no HP). Same-system graduation is 1:1; cross-system is
  best-effort by key. This **replaced DCC's bespoke funnel** — `DccSheet` is now
  leveled-only (no `mode`/`peasants`/`DccPeasant`); "Add DCC" makes a leveled hero
  and DCC funnels go through the generic path (the `solo-dcc` preset enables
  `funnel`). A `solo-funnel` preset + the `cat-funnel` creation chip surface it.
  See `docs/superpowers/specs/2026-06-27-generalized-funnel-design.md` and the
  plan `docs/superpowers/plans/2026-06-27-generalized-funnel.md`.
```

Also update the existing DCC bullet's funnel description (it currently describes DccSheet's `mode`/funnel — change to note the funnel moved to the generic feature).

- [ ] **Step 4: Final run** — `flutter analyze && flutter test`. Expected: clean + green.
- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(funnel): CLAUDE.md note for the generalized funnel"
```

---

## Self-review notes

- **Spec coverage:** data model (T1–T3), per-system profiles + registry (T4, T8–T11), `graduate` mappers for all 12 (T4 dcc, T8 ×4, T9 ×4, T10 ×3, T11 covers sundered alias), notifier spawn-new (T5), funnel UI + graduation flow (T6), registration + creation + presets (T7), DCC refactor (T12), testing + docs (T11/T13). All covered.
- **Naming consistency:** `Character.funnel` / `clearFunnel`; `FunnelSheet`/`FunnelPeasant`/`FunnelProfile`/`FunnelChoice`; `funnelProfileFor`/`kFunnelProfiles`/`kFunnelMaxPeasants`; notifier `addFunnel`/`graduateFunnelPeasant`; view `FunnelSheetView`; widget keys `funnel-sheet`/`funnel-add-peasant`/`funnel-peasant-<i>`(`-name`/`-flavor-<k>`/`-hp`/`-<statKey>`/`-kill`/`-revive`/`-graduate`)/`funnel-graduate-target`/`funnel-graduate-<choiceKey>`/`funnel-graduate-confirm`/`funnel-seed-<sys>`; stepper buttons append `-minus`/`-plus`.
- **copyWith param names** are asserted per-task against `models.dart` (abilities vs stats vs characteristics vs individual fields) — Step 3 of T8/T9/T10 says to verify before running; the recon table is the source.
- **Import cycle avoided:** `FunnelSheet`/`FunnelPeasant` in `models.dart`; `FunnelProfile`/registry in `funnel.dart` (imports models.dart, not vice versa). `funnel_sheet.dart` (UI) imports both.
- **Ordering:** the DCC mapper carries a transitional `mode: 'leveled'` arg (T4) removed in T12 — both states compile and the tests don't assert `mode`.
- **No randomness** in mappers → deterministic graduation tests.
