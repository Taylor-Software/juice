# Funnel Generalization Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the 0-level funnel cover all campaigns — graduate into the **Custom/Homebrew** sheet (template locked at funnel creation) and into the correct **Ironsworn-family** variant (classic / Starforged / Sundered Isles).

**Architecture:** Add a `FunnelSheet.seedVariant` discriminator (custom template id), thread a `seedVariant` param into `FunnelProfile.graduate`, and introduce a pure `funnelPeasantSchema(seedSystem, seedVariant)` so peasant rendering/seeding is uniform while custom derives its stat schema from the chosen template. The `ironsworn` profile gains a `variant` graduation choice (defaulted from the active ruleset); the dead `starforged` profile is removed. A `custom` profile builds a template's blocks and injects peasant stats/HP.

**Tech Stack:** Flutter, flutter_riverpod, Dart. Tests pump `FunnelSheetView` directly via the prefs-seeded `ProviderContainer` harness. Prefix every flutter command with `export PATH="$HOME/development/flutter/bin:$PATH"`. A `dart format` hook runs on `.dart` edits.

---

## File structure

- **Modify** `lib/engine/models.dart` — `FunnelSheet` gains `seedVariant` (field, ctor, premade, copyWith, toJson, maybeFromJson).
- **Modify** `lib/engine/funnel.dart` — `FunnelProfile.graduate` gains a `seedVariant` param; `seedPeasant(seedVariant)`; new top-level `funnelPeasantSchema` + `FunnelPeasantSchema` typedef; modify the `ironsworn` profile + remove `starforged`; add the `custom` profile. Imports `custom_sheet.dart` + `custom_templates.dart`.
- **Modify** `lib/state/providers.dart` — `addFunnel(seedSystem, {seedVariant})`.
- **Modify** `lib/features/funnel_sheet.dart` — render peasant cards from `funnelPeasantSchema`; add-peasant via `seedPeasant(s.seedVariant)`; graduate passes `s.seedVariant`; ironsworn `variant` default from `rulesetsProvider`; pretty variant labels; header shows custom template.
- **Modify** `lib/features/tracker_screen.dart` — `_newFunnel` custom template picker.
- **Modify** `test/funnel_test.dart` — update `seedPeasant`/`graduate` call sites for the new param; drop the `custom` completeness exclusion; well-formed test handles custom; add custom + ironsworn-family + schema tests.
- **Modify** `test/funnel_sheet_ui_test.dart` — custom funnel creation + graduation widget tests.
- **Modify** `CLAUDE.md` — update the funnel bullet.

### Verified anchors (from recon)

- `FunnelProfile.graduate` is currently `Character Function(String id, FunnelPeasant p, Map<String,String> picks)`. `seedPeasant()` takes 0 args. `defaultPicks()` returns first-option-per-choice.
- `kFunnelProfiles` has 12 keys incl. `ironsworn` (lines ~320-342) and a dead `starforged` (~343-365). Both use the 5 shared stats edge/heart/iron/shadow/wits (1-3, hpMin 0 hpMax 5, graduateChoices `const []`).
- `FunnelSheet` ctor: `const FunnelSheet({this.seedSystem = '', this.peasants = const []})`; `premade(String seedSystem, List<FunnelPeasant> seed)`; `copyWith({seedSystem, peasants})`; toJson `{seedSystem, peasants}`; maybeFromJson reads `m['seedSystem']` + peasants.
- `CustomBlockType` enum has `stat`, `hp` (among 11). A `stat` block's `config['stats']` is `List<Map>` of `{'key':String,'label':String}` + `config['min']`/`config['max']` ints. `CustomSheet(blocks, values)`, `values` keyed by `block.id`; hp block value is a plain `int`.
- `CustomTemplate {id, label, blocks}`; `kCustomTemplates` = `blank` (no blocks), `generic-d20` (stat `g-stat` 6 abilities 3-18 + hp `g-hp` + ...), `osr` (stat `o-stat` str/dex/wil 3-18 + hp `o-hp` + ...), `pbta` (stat `p-stat` 5 mods -1..3, **no hp** + ...).
- `Character.forSheet` arms exist for `'custom'`, `'ironsworn'`, `'starforged'`, `'sundered_isles'` (sundered → `StarforgedSheet(assetRuleset:'sundered_isles')`).
- `addFunnel(String seedSystem)` → `profile.seedPeasant()`. `graduateFunnelPeasant(funnelChar, index, Character Function(String id) buildHero)` — UI passes the builder.
- `rulesetsProvider` = `AsyncNotifierProvider<RulesetsNotifier, Set<String>>`; read via `ref.read(rulesetsProvider).valueOrNull ?? const <String>{}`. `resolveSystem(Set systems, Set rulesets)` in `lib/engine/system_primer.dart` returns the family key (`ironsworn`/`starforged`/`sundered_isles`/...).
- `funnel_sheet.dart` `_graduateDialog`: builds `targets` from `kFunnelProfiles.keys ∩ enabled`, `picks = {...funnelProfileFor(target)!.defaultPicks()}`, renders a `variant`-less choice loop, calls `profile.graduate(id, peasant, picks)`.
- `funnel_sheet.dart` `_peasantCard` renders stat steppers from `profile.statKeys`/`statMin`/`statMax`/`statDefault` and an HP stepper from `profile.hpMin`/`hpMax`.
- `tracker_screen._newFunnel`: seed picker (SimpleDialog when >1) → `addFunnel(seed)`.
- The completeness test (`test/funnel_test.dart`) excludes `custom` and calls `seedPeasant()` (0 args) + `graduate('hid', peasant, defaultPicks())` (3 args).

---

## Task 1: `FunnelSheet.seedVariant`

**Files:** Modify `lib/engine/models.dart` (`FunnelSheet`); Test `test/funnel_test.dart`.

- [ ] **Step 1: Add a failing test** — append to the `FunnelSheet` group in `test/funnel_test.dart`:

```dart
    test('seedVariant round-trips and defaults empty', () {
      const s = FunnelSheet(
          seedSystem: 'custom', seedVariant: 'generic-d20', peasants: []);
      final back = FunnelSheet.maybeFromJson(s.toJson())!;
      expect(back.seedVariant, 'generic-d20');
      expect(FunnelSheet.maybeFromJson(const {})!.seedVariant, '');
      expect(s.copyWith(seedVariant: 'osr').seedVariant, 'osr');
    });
```

- [ ] **Step 2: Run** `export PATH="$HOME/development/flutter/bin:$PATH" && flutter test test/funnel_test.dart -n "seedVariant round-trips"` — FAIL (no `seedVariant`).

- [ ] **Step 3: Modify `FunnelSheet` in `lib/engine/models.dart`:**

Constructor + field:
```dart
  const FunnelSheet(
      {this.seedSystem = '', this.seedVariant = '', this.peasants = const []});

  final String seedSystem;

  /// Sub-discriminator within [seedSystem]. For a custom funnel, the chosen
  /// template id (locked at creation); '' for every other system.
  final String seedVariant;
  final List<FunnelPeasant> peasants;
```
`premade`:
```dart
  factory FunnelSheet.premade(String seedSystem, List<FunnelPeasant> seed,
          {String seedVariant = ''}) =>
      FunnelSheet(
          seedSystem: seedSystem, seedVariant: seedVariant, peasants: seed);
```
`copyWith`:
```dart
  FunnelSheet copyWith(
          {String? seedSystem, String? seedVariant, List<FunnelPeasant>? peasants}) =>
      FunnelSheet(
        seedSystem: seedSystem ?? this.seedSystem,
        seedVariant: seedVariant ?? this.seedVariant,
        peasants: peasants ?? this.peasants,
      );
```
`toJson` (add after `'seedSystem'`):
```dart
        if (seedVariant.isNotEmpty) 'seedVariant': seedVariant,
```
`maybeFromJson` (add after `seedSystem:`):
```dart
      seedVariant: m['seedVariant'] as String? ?? '',
```

- [ ] **Step 4: Run** `flutter test test/funnel_test.dart` — PASS. `flutter analyze lib/engine/models.dart` — clean.
- [ ] **Step 5: Commit**

```bash
git add lib/engine/models.dart test/funnel_test.dart
git commit -m "feat(funnel): FunnelSheet.seedVariant discriminator"
```

---

## Task 2: Thread `seedVariant` into `FunnelProfile.graduate` + `seedPeasant`

**Files:** Modify `lib/engine/funnel.dart`; Test `test/funnel_test.dart`.

Pure refactor — add the param to the `graduate` typedef + every closure (all ignore it for now) + make `seedPeasant` take it. No behavior change. The completeness test call sites are updated to compile.

- [ ] **Step 1: Update the completeness test call sites first (will fail to compile until Step 3).** In `test/funnel_test.dart`, the `every profile is well-formed` test: change
```dart
      final peasant = p.seedPeasant().copyWith(name: 'X');
      final hero = p.graduate('hid', peasant, p.defaultPicks());
```
to
```dart
      final peasant = p.seedPeasant('').copyWith(name: 'X');
      final hero = p.graduate('hid', peasant, p.defaultPicks(), '');
```

- [ ] **Step 2: Run** `flutter test test/funnel_test.dart -n "every profile is well-formed"` — FAIL (compile error: too many args).

- [ ] **Step 3: In `lib/engine/funnel.dart`:**
  (a) Change the `graduate` field type to add the param:
```dart
  final Character Function(
          String id, FunnelPeasant p, Map<String, String> picks, String seedVariant)
      graduate;
```
  (b) Change `seedPeasant` to take a variant (kept schema-aware in Task 3; for now use the profile's fixed fields):
```dart
  FunnelPeasant seedPeasant(String seedVariant) => FunnelPeasant(
        hp: hpMin,
        stats: {for (final s in statKeys) s.key: statDefault},
        flavor: {for (final f in flavorFields) f.key: ''},
      );
```
  (c) In EVERY entry of `kFunnelProfiles`, change each `graduate: (id, p, picks) {` to `graduate: (id, p, picks, seedVariant) {` (12 closures: dcc, dnd, shadowdark, argosa, ose, nimble, draw-steel, knave, kal-arath, cairn, ironsworn, starforged). The bodies are unchanged.

- [ ] **Step 4: Run** `flutter test test/funnel_test.dart` — PASS (no behavior change). `flutter analyze lib/engine/funnel.dart` — clean.
- [ ] **Step 5: Commit**

```bash
git add lib/engine/funnel.dart test/funnel_test.dart
git commit -m "refactor(funnel): thread seedVariant param into graduate + seedPeasant"
```

---

## Task 3: `funnelPeasantSchema` helper + schema-driven `seedPeasant`

**Files:** Modify `lib/engine/funnel.dart`; Test `test/funnel_test.dart`.

Introduce the pure schema resolver (custom → template, else → profile) and route `seedPeasant` through it. Non-custom behavior is identical (the helper returns the profile's fixed values).

- [ ] **Step 1: Add failing tests** — append a group to `test/funnel_test.dart`:

```dart
  group('funnelPeasantSchema', () {
    test('non-custom returns the profile fixed schema', () {
      final sc = funnelPeasantSchema('dcc', '');
      final p = funnelProfileFor('dcc')!;
      expect(sc.statKeys.map((s) => s.key), p.statKeys.map((s) => s.key));
      expect(sc.statMin, p.statMin);
      expect(sc.statMax, p.statMax);
      expect(sc.hpMin, p.hpMin);
      expect(sc.hpMax, p.hpMax);
    });
    test('custom derives stat keys from the chosen template', () {
      final g = funnelPeasantSchema('custom', 'generic-d20');
      expect(g.statKeys.map((s) => s.key),
          ['str', 'dex', 'con', 'int', 'wis', 'cha']);
      expect(g.statMin, 3);
      expect(g.statMax, 18);

      final osr = funnelPeasantSchema('custom', 'osr');
      expect(osr.statKeys.map((s) => s.key), ['str', 'dex', 'wil']);

      final pbta = funnelPeasantSchema('custom', 'pbta');
      expect(pbta.statKeys.length, 5);
      expect(pbta.statMin, -1);
      expect(pbta.statMax, 3);

      final blank = funnelPeasantSchema('custom', 'blank');
      expect(blank.statKeys, isEmpty);
      expect(blank.hpMin >= 1, true); // peasants still track death
    });
    test('custom seedPeasant uses the template schema', () {
      final p = funnelProfileFor('custom');
      // custom profile exists after Task 4; until then this sub-test is added in Task 4.
    }, skip: 'custom profile added in Task 4');
  });
```

- [ ] **Step 2: Run** `flutter test test/funnel_test.dart -n "funnelPeasantSchema"` — FAIL (`funnelPeasantSchema` undefined).

- [ ] **Step 3: Add to `lib/engine/funnel.dart`** (top of file add imports; then the typedef + function). Imports:
```dart
import 'custom_sheet.dart';
import 'custom_templates.dart';
import 'models.dart';
```
Typedef + helper (place near `funnelProfileFor`):
```dart
/// The effective peasant schema for a funnel — what stat/HP steppers to render
/// and seed. For custom it derives from the chosen template's stat block; for
/// every other system it is the profile's fixed schema.
typedef FunnelPeasantSchema = ({
  List<({String key, String label})> statKeys,
  int statMin,
  int statMax,
  int statDefault,
  List<({String key, String label})> flavorFields,
  int hpMin,
  int hpMax,
});

FunnelPeasantSchema funnelPeasantSchema(String seedSystem, String seedVariant) {
  if (seedSystem == 'custom') {
    final t = kCustomTemplates.firstWhere((x) => x.id == seedVariant,
        orElse: () => kCustomTemplates.first); // 'blank' is first
    CustomBlock? statBlock;
    for (final b in t.blocks) {
      if (b.type == CustomBlockType.stat) {
        statBlock = b;
        break;
      }
    }
    final rawStats = (statBlock?.config['stats'] as List?) ?? const [];
    final keys = [
      for (final s in rawStats)
        (key: (s as Map)['key'] as String, label: s['label'] as String),
    ];
    final min = (statBlock?.config['min'] as int?) ?? 1;
    final max = (statBlock?.config['max'] as int?) ?? 18;
    return (
      statKeys: keys,
      statMin: min,
      statMax: max,
      statDefault: ((min + max) / 2).round(),
      flavorFields: const [],
      hpMin: 1, // peasants always track death, even if the template has no HP block
      hpMax: 8,
    );
  }
  final p = funnelProfileFor(seedSystem);
  if (p == null) {
    return (
      statKeys: const [],
      statMin: 1,
      statMax: 18,
      statDefault: 10,
      flavorFields: const [],
      hpMin: 0,
      hpMax: 0,
    );
  }
  return (
    statKeys: p.statKeys,
    statMin: p.statMin,
    statMax: p.statMax,
    statDefault: p.statDefault,
    flavorFields: p.flavorFields,
    hpMin: p.hpMin,
    hpMax: p.hpMax,
  );
}
```
Route `seedPeasant` through it (replace the Task-2 body):
```dart
  FunnelPeasant seedPeasant(String seedVariant) {
    final sc = funnelPeasantSchema(system, seedVariant);
    return FunnelPeasant(
      hp: sc.hpMin,
      stats: {for (final s in sc.statKeys) s.key: sc.statDefault},
      flavor: {for (final f in sc.flavorFields) f.key: ''},
    );
  }
```

- [ ] **Step 4: Run** `flutter test test/funnel_test.dart` — PASS (the custom-schema tests pass even before a custom profile exists, since `funnelPeasantSchema('custom',...)` reads templates directly). `flutter analyze lib/engine/funnel.dart` — clean.
- [ ] **Step 5: Commit**

```bash
git add lib/engine/funnel.dart test/funnel_test.dart
git commit -m "feat(funnel): funnelPeasantSchema + schema-driven seedPeasant"
```

---

## Task 4: Ironsworn family — variant graduation choice

**Files:** Modify `lib/engine/funnel.dart`; Test `test/funnel_test.dart`.

Remove the dead `starforged` profile; give `ironsworn` a `variant` choice + a variant-aware graduate.

- [ ] **Step 1: Add failing tests** — append a group to `test/funnel_test.dart`:

```dart
  group('ironsworn family graduation', () {
    const peasant = FunnelPeasant(hp: 3,
        stats: {'edge': 2, 'heart': 1, 'iron': 3, 'shadow': 1, 'wits': 2});
    test('ironsworn profile offers a variant choice', () {
      final p = funnelProfileFor('ironsworn')!;
      final variant = p.graduateChoices.firstWhere((c) => c.key == 'variant');
      expect(variant.options, ['ironsworn', 'starforged', 'sundered_isles']);
    });
    test('graduate builds classic Ironsworn for variant ironsworn', () {
      final h = funnelProfileFor('ironsworn')!
          .graduate('h', peasant, {'variant': 'ironsworn'}, '');
      expect(h.ironsworn, isNotNull);
      expect(h.starforged, isNull);
      expect(h.ironsworn!.iron, 3);
    });
    test('graduate builds Starforged for variant starforged', () {
      final h = funnelProfileFor('ironsworn')!
          .graduate('h', peasant, {'variant': 'starforged'}, '');
      expect(h.starforged, isNotNull);
      expect(h.ironsworn, isNull);
      expect(h.starforged!.isSundered, false);
      expect(h.starforged!.shadow, 1);
    });
    test('graduate builds Sundered Isles for variant sundered_isles', () {
      final h = funnelProfileFor('ironsworn')!
          .graduate('h', peasant, {'variant': 'sundered_isles'}, '');
      expect(h.starforged, isNotNull);
      expect(h.starforged!.isSundered, true);
    });
    test('no standalone starforged/sundered_isles profile', () {
      expect(kFunnelProfiles.containsKey('starforged'), false);
      expect(kFunnelProfiles.containsKey('sundered_isles'), false);
    });
  });
```

- [ ] **Step 2: Run** `flutter test test/funnel_test.dart -n "ironsworn family"` — FAIL.

- [ ] **Step 3: In `lib/engine/funnel.dart`:**
  (a) DELETE the entire `'starforged': FunnelProfile(...)` entry from `kFunnelProfiles`.
  (b) REPLACE the `'ironsworn'` entry with:
```dart
  'ironsworn': FunnelProfile(
    system: 'ironsworn',
    statKeys: const [
      (key: 'edge', label: 'Edge'), (key: 'heart', label: 'Heart'),
      (key: 'iron', label: 'Iron'), (key: 'shadow', label: 'Shadow'),
      (key: 'wits', label: 'Wits'),
    ],
    statMin: 1, statMax: 3, statDefault: 1,
    flavorFields: const [],
    hpMin: 0, hpMax: 5,
    graduateChoices: const [
      FunnelChoice('variant', 'Ruleset',
          ['ironsworn', 'starforged', 'sundered_isles']),
    ],
    graduate: (id, p, picks, seedVariant) {
      final variant = picks['variant'] ?? 'ironsworn';
      final base = Character.forSheet(variant, id);
      if (variant == 'ironsworn') {
        return base.copyWith(
          name: _heroName(p, base),
          ironsworn: base.ironsworn!.copyWith(
            edge: p.stats['edge'], heart: p.stats['heart'],
            iron: p.stats['iron'], shadow: p.stats['shadow'],
            wits: p.stats['wits'],
          ),
        );
      }
      // starforged or sundered_isles → StarforgedSheet (forSheet sets assetRuleset)
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

- [ ] **Step 4: Run** `flutter test test/funnel_test.dart` — PASS. (The `every profile is well-formed` test now also exercises ironsworn's `variant` default pick — `defaultPicks()` yields `{'variant':'ironsworn'}`, graduate builds classic.) `flutter analyze lib/engine/funnel.dart` — clean.
- [ ] **Step 5: Commit**

```bash
git add lib/engine/funnel.dart test/funnel_test.dart
git commit -m "feat(funnel): ironsworn-family variant graduation; drop dead starforged profile"
```

---

## Task 5: `custom` FunnelProfile

**Files:** Modify `lib/engine/funnel.dart`, `test/funnel_test.dart`.

Add the `custom` profile (schema-driven peasants via the helper; graduate builds the locked template + injects). Drop the completeness exclusion; make the well-formed test custom-aware.

- [ ] **Step 1: Add failing tests** — append a group + un-skip the Task-3 placeholder:

```dart
  group('custom funnel profile', () {
    test('custom profile exists with no graduate choices', () {
      final p = funnelProfileFor('custom');
      expect(p, isNotNull);
      expect(p!.graduateChoices, isEmpty);
    });
    test('custom seedPeasant uses the template schema', () {
      final p = funnelProfileFor('custom')!;
      final peasant = p.seedPeasant('osr');
      expect(peasant.stats.keys, containsAll(['str', 'dex', 'wil']));
    });
    test('graduate builds the template blocks + injects stats and hp', () {
      const peasant = FunnelPeasant(name: 'Reaper', hp: 6,
          stats: {'str': 15, 'dex': 13, 'con': 14, 'int': 8, 'wis': 9, 'cha': 11});
      final h = funnelProfileFor('custom')!
          .graduate('h', peasant, const {}, 'generic-d20');
      expect(h.custom, isNotNull);
      expect(h.name, 'Reaper');
      // first stat block id is 'g-stat', hp block id 'g-hp' (generic-d20)
      expect(h.custom!.blocks.any((b) => b.id == 'g-stat'), true);
      expect((h.custom!.values['g-stat'] as Map)['str'], 15);
      expect(h.custom!.values['g-hp'], 6);
    });
    test('graduate into blank template yields an empty custom sheet', () {
      const peasant = FunnelPeasant(name: 'Nobody', hp: 4);
      final h = funnelProfileFor('custom')!
          .graduate('h', peasant, const {}, 'blank');
      expect(h.custom, isNotNull);
      expect(h.custom!.blocks, isEmpty);
      expect(h.name, 'Nobody');
    });
  });
```

- [ ] **Step 2: Run** `flutter test test/funnel_test.dart -n "custom funnel profile"` — FAIL.

- [ ] **Step 3a: Add the `custom` entry to `kFunnelProfiles`** in `lib/engine/funnel.dart` (its fixed stat fields are placeholders — the schema/graduate use the template via `seedVariant`):
```dart
  'custom': FunnelProfile(
    system: 'custom',
    statKeys: const [], // template-driven; see funnelPeasantSchema
    statMin: 1, statMax: 18, statDefault: 10,
    flavorFields: const [],
    hpMin: 1, hpMax: 8,
    graduateChoices: const [], // template locked at creation
    graduate: (id, p, picks, seedVariant) {
      final t = kCustomTemplates.firstWhere((x) => x.id == seedVariant,
          orElse: () => kCustomTemplates.first);
      final values = <String, dynamic>{};
      var didStat = false, didHp = false;
      for (final b in t.blocks) {
        if (!didStat && b.type == CustomBlockType.stat) {
          final rawStats = (b.config['stats'] as List?) ?? const [];
          values[b.id] = {
            for (final s in rawStats)
              (s as Map)['key'] as String: p.stats[s['key']] ?? 0,
          };
          didStat = true;
        } else if (!didHp && b.type == CustomBlockType.hp) {
          values[b.id] = p.hp;
          didHp = true;
        }
      }
      final base = Character.forSheet('custom', id);
      return base.copyWith(
        name: _heroName(p, base),
        custom: CustomSheet(blocks: t.blocks, values: values),
      );
    },
  ),
```

- [ ] **Step 3b: Update the completeness test** in `test/funnel_test.dart`. Remove the `.where((s) => s != 'custom')` exclusion so it reads:
```dart
    test('every kSystemCategory ruleset has a profile', () {
      final rulesets = kSystemCategory.entries
          .where((e) => e.value == SystemCategory.ruleset)
          .map((e) => e.key)
          .toSet();
      for (final sys in rulesets) {
        expect(kFunnelProfiles.containsKey(sys), true,
            reason: 'missing FunnelProfile for ruleset "$sys"');
      }
    });
```
And make `every profile is well-formed` custom-aware (custom's `statKeys` is intentionally empty):
```dart
    test('every profile is well-formed', () {
      kFunnelProfiles.forEach((sys, p) {
        expect(p.system, sys);
        expect(p.statMin < p.statMax, true, reason: '$sys range');
        expect(p.statDefault >= p.statMin && p.statDefault <= p.statMax, true,
            reason: '$sys default in range');
        expect(p.hpMin <= p.hpMax, true, reason: '$sys hp range');
        for (final c in p.graduateChoices) {
          expect(c.options, isNotEmpty, reason: '$sys choice ${c.key}');
        }
        if (sys == 'custom') {
          // template-driven: validate the schema resolves stat keys per template
          expect(funnelPeasantSchema('custom', 'generic-d20').statKeys,
              isNotEmpty);
        } else {
          expect(p.statKeys, isNotEmpty, reason: '$sys statKeys');
        }
        // graduate produces a hero with the right id + carried name.
        final variant = sys == 'custom' ? 'generic-d20' : '';
        final peasant = p.seedPeasant(variant).copyWith(name: 'X');
        final hero = p.graduate('hid', peasant, p.defaultPicks(), variant);
        expect(hero.id, 'hid');
        expect(hero.name, 'X');
      });
    });
```

- [ ] **Step 4: Run** `flutter test test/funnel_test.dart` — PASS (all groups, including completeness). `flutter analyze lib/engine/funnel.dart` — clean.
- [ ] **Step 5: Commit**

```bash
git add lib/engine/funnel.dart test/funnel_test.dart
git commit -m "feat(funnel): custom-sheet FunnelProfile (template-locked graduation)"
```

---

## Task 6: Wire `addFunnel(seedVariant)` + funnel UI

**Files:** Modify `lib/state/providers.dart`, `lib/features/funnel_sheet.dart`; Test `test/funnel_sheet_ui_test.dart`, `test/funnel_test.dart`.

- [ ] **Step 1: Add a failing model test** for `addFunnel` carrying the variant — append to the `CharacterNotifier funnel` group in `test/funnel_test.dart`:

```dart
    test('addFunnel custom seeds from the template variant', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final id = await c
          .read(charactersProvider.notifier)
          .addFunnel('custom', seedVariant: 'osr');
      final f = (await c.read(charactersProvider.future))
          .firstWhere((x) => x.id == id);
      expect(f.funnel!.seedSystem, 'custom');
      expect(f.funnel!.seedVariant, 'osr');
      expect(f.funnel!.peasants.first.stats.keys, containsAll(['str', 'dex', 'wil']));
    });
```

- [ ] **Step 2: Run** `flutter test test/funnel_test.dart -n "addFunnel custom"` — FAIL (`seedVariant` not a param).

- [ ] **Step 3a: `lib/state/providers.dart` — `addFunnel`:**
```dart
  Future<String> addFunnel(String seedSystem, {String seedVariant = ''}) async {
    final id = _newId();
    final profile = funnelProfileFor(seedSystem);
    final seed = profile == null
        ? const <FunnelPeasant>[]
        : [profile.seedPeasant(seedVariant)];
    final ch = Character(
      id: id,
      name: '0-Level Funnel',
      funnel: FunnelSheet(
          seedSystem: seedSystem, seedVariant: seedVariant, peasants: seed),
    );
    await _persist([ch, ...await _ready]);
    return id;
  }
```

- [ ] **Step 3b: `lib/features/funnel_sheet.dart` — render from schema + pass seedVariant + ironsworn default + pretty labels.**

  In `build`, after `final s = _s;`, compute the schema and keep the profile:
```dart
    final profile = funnelProfileFor(s.seedSystem);
    final schema = funnelPeasantSchema(s.seedSystem, s.seedVariant);
```
  Change the header line to show the custom template:
```dart
        Text(
            s.seedSystem == 'custom' && s.seedVariant.isNotEmpty
                ? '0-Level Funnel — Custom (${_templateLabel(s.seedVariant)})'
                : '0-Level Funnel — ${s.seedSystem}',
            style: theme.textTheme.labelSmall),
```
  Change the add-peasant button to seed with the variant:
```dart
            onPressed: s.peasants.length >= kFunnelMaxPeasants
                ? null
                : () => _save(
                    ref,
                    s.copyWith(peasants: [
                      ...s.peasants,
                      profile!.seedPeasant(s.seedVariant),
                    ])),
```
  Change `_peasantCard` to take + use the `schema` for stat/HP rendering. Update its signature to `_peasantCard(BuildContext context, WidgetRef ref, FunnelSheet s, FunnelPeasantSchema schema, int i)` and the call site `_peasantCard(context, ref, s, schema, i)`. Inside, replace `profile.statKeys`→`schema.statKeys`, `profile.statMin/statMax/statDefault`→`schema.statMin/statMax/statDefault`, and the HP stepper bounds `profile.hpMin/hpMax`→`schema.hpMin/hpMax`. (The `profile` is no longer needed inside `_peasantCard`.)

  Add a template-label helper (top of the class):
```dart
  String _templateLabel(String id) {
    for (final t in kCustomTemplates) {
      if (t.id == id) return t.label;
    }
    return id;
  }
```

  In `_graduateDialog`, default the ironsworn `variant` from the active ruleset, pass `seedVariant` to graduate, and prettify variant option labels. Replace the picks-init + the graduate call + the option `Text`:
```dart
    final rulesets = ref.read(rulesetsProvider).valueOrNull ?? const <String>{};
    var target = s.seedSystem;
    Map<String, String> picksFor(String t) {
      final m = {...funnelProfileFor(t)!.defaultPicks()};
      if (t == 'ironsworn') {
        final resolved = resolveSystem(enabled, rulesets);
        if (const {'ironsworn', 'starforged', 'sundered_isles'}
            .contains(resolved)) {
          m['variant'] = resolved;
        }
      }
      return m;
    }
    var picks = picksFor(target);
```
  In the target dropdown `onChanged`: `picks = picksFor(target);` (instead of the inline `{...defaultPicks()}`).
  In the choice loop, prettify the displayed option:
```dart
                items: ch.options
                    .map((o) =>
                        DropdownMenuItem(value: o, child: Text(_prettyOption(o))))
                    .toList(),
```
  The graduate call passes seedVariant:
```dart
    await ref.read(charactersProvider.notifier).graduateFunnelPeasant(
        character, i, (id) => profile.graduate(id, peasant, picks, s.seedVariant));
```
  Add the prettify helper + imports. At the top of `funnel_sheet.dart` add:
```dart
import '../engine/system_primer.dart';
```
  (for `resolveSystem`; `rulesetsProvider` comes from `providers.dart`, already imported). Helper:
```dart
  String _prettyOption(String o) => switch (o) {
        'ironsworn' => 'Ironsworn',
        'starforged' => 'Starforged',
        'sundered_isles' => 'Sundered Isles',
        _ => o,
      };
```

- [ ] **Step 4: Add a custom funnel widget test** to `test/funnel_sheet_ui_test.dart` (mirror the existing `_pump` harness; seed a custom funnel):
```dart
  testWidgets('custom funnel renders template stats + graduates a custom hero',
      (tester) async {
    final sheet = FunnelSheet(seedSystem: 'custom', seedVariant: 'generic-d20',
        peasants: [
          const FunnelPeasant(name: '', hp: 6, stats: {
            'str': 12, 'dex': 10, 'con': 11, 'int': 10, 'wis': 9, 'cha': 8,
          }),
        ]);
    final c = await _pump(tester, sheet);
    // a generic-d20 stat key renders
    expect(find.byKey(const Key('funnel-peasant-0-str-plus')), findsOneWidget);
    await tester.tap(find.byKey(const Key('funnel-peasant-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('funnel-peasant-0-graduate')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('funnel-graduate-confirm')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final hero = (await c.read(charactersProvider.future))
        .firstWhere((x) => x.custom != null);
    expect((hero.custom!.values['g-stat'] as Map)['str'], 12);
    expect(hero.custom!.values['g-hp'], 6);
  });
```

- [ ] **Step 5: Run** the FULL ui file `flutter test test/funnel_sheet_ui_test.dart` AND `flutter test test/funnel_test.dart` — expect all PASS (run the ui file whole to catch teardown). `flutter analyze lib/state/providers.dart lib/features/funnel_sheet.dart` — clean.
- [ ] **Step 6: Commit**

```bash
git add lib/state/providers.dart lib/features/funnel_sheet.dart \
  test/funnel_sheet_ui_test.dart test/funnel_test.dart
git commit -m "feat(funnel): schema-driven peasant cards + seedVariant wiring + ironsworn default"
```

---

## Task 7: Custom template picker at creation + verify + docs

**Files:** Modify `lib/features/tracker_screen.dart`, `CLAUDE.md`; Test `test/funnel_sheet_ui_test.dart` (optional creation test if the harness supports it — otherwise rely on the addFunnel unit test).

- [ ] **Step 1: `tracker_screen._newFunnel` — add the custom template step.** After the seed is chosen (`if (seed == null || !mounted) return;`), before `addFunnel`, insert:
```dart
    var seedVariant = '';
    if (seed == 'custom') {
      seedVariant = await showDialog<String>(
            context: context,
            builder: (ctx) => SimpleDialog(
              title: const Text('Custom funnel template'),
              children: [
                for (final t in kCustomTemplates)
                  SimpleDialogOption(
                    key: Key('funnel-template-${t.id}'),
                    onPressed: () => Navigator.pop(ctx, t.id),
                    child: Text(t.label),
                  ),
              ],
            ),
          ) ??
          '';
      if (!mounted) return;
      if (seedVariant.isEmpty) return; // cancelled the template pick
    }
    final id = await ref
        .read(charactersProvider.notifier)
        .addFunnel(seed, seedVariant: seedVariant);
    if (mounted) setState(() => _editingId = id);
```
Remove the old trailing `final id = await ...addFunnel(seed); if (mounted) ...` lines that this replaces. Add the import at the top of `tracker_screen.dart` if missing:
```dart
import '../engine/custom_templates.dart';
```

- [ ] **Step 2: Run** `flutter analyze lib/features/tracker_screen.dart` — clean. (The creation path is exercised end-to-end by the addFunnel unit test + the custom widget test; a full tracker_screen pump is out of scope per the rootBundle-hang rule.)

- [ ] **Step 3: Full verification** — `flutter analyze` (whole project, expect no issues; if `dart fix --apply` is needed for `prefer_const`/`unnecessary_const` in the new test code, run it then re-analyze) and `flutter test` (whole suite, expect all pass). Report the pass count. Fix any registry/count test that references the removed `starforged` profile or the old custom exclusion.

- [ ] **Step 4: Update `CLAUDE.md`** — in the generalized-funnel bullet, append:
```markdown
  Custom-sheet + Ironsworn-family funnels are supported: a `custom` funnel locks
  a template at creation (`FunnelSheet.seedVariant`) and graduates 1:1 into it
  (peasant stats injected into the template's first stat/hp block); the
  `ironsworn` profile offers a `variant` graduation choice (Ironsworn / Starforged
  / Sundered Isles) defaulted from the active ruleset (the dead standalone
  `starforged` profile was removed). Peasant rendering/seeding goes through the
  pure `funnelPeasantSchema(seedSystem, seedVariant)`. See
  `docs/superpowers/specs/2026-06-27-funnel-generalization-completion-design.md`.
```

- [ ] **Step 5: Commit**

```bash
git add lib/features/tracker_screen.dart CLAUDE.md
git commit -m "feat(funnel): custom template picker at creation; docs"
```

---

## Self-review notes

- **Spec coverage:** seedVariant model (T1), graduate-param + schema helper (T2/T3), Ironsworn family + dead-profile removal (T4), custom profile + completeness un-exclusion (T5), addFunnel + UI rendering/graduate/ironsworn-default (T6), creation template picker + docs (T7). All spec sections covered.
- **Naming consistency:** `FunnelSheet.seedVariant`; `funnelPeasantSchema(seedSystem, seedVariant)` → `FunnelPeasantSchema` record; `graduate(id, p, picks, seedVariant)`; `seedPeasant(seedVariant)`; `addFunnel(seedSystem, {seedVariant})`; widget keys `funnel-template-<id>`, `funnel-graduate-variant` (the variant choice renders via the existing `funnel-graduate-<ch.key>` loop → `funnel-graduate-variant`).
- **Ordering:** T2 adds the graduate param (all closures, no behavior change) BEFORE T4/T5 use it; T3 adds the schema helper BEFORE T5/T6 use it; each task stays green.
- **Custom placeholder fields:** the `custom` profile's `statKeys` is intentionally `const []` (template-driven); the well-formed test special-cases custom (validates via `funnelPeasantSchema`). No other profile relies on custom's fixed fields.
- **HP for meter/no-hp-block:** custom peasants always get an HP stepper (death track, hpMin 1); graduation only injects HP when the template has an `hp` block (pbta/blank → no injection, no crash).
- **Imports:** `funnel.dart` adds `custom_sheet.dart` + `custom_templates.dart` (no cycle — neither imports funnel.dart); `funnel_sheet.dart` adds `system_primer.dart` (resolveSystem); `tracker_screen.dart` adds `custom_templates.dart`.
