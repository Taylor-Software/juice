# Sundered Isles Sheet Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a character created as "Sundered Isles" reuse the Starforged sheet but pull the 60 Sundered Isles datasworn assets and label itself accordingly — via a single `assetRuleset` discriminator on `StarforgedSheet`.

**Architecture:** SI is mechanically identical to Starforged (same stats/meters/impacts/legacy tracks); only the asset set differs. Add `String assetRuleset` to `StarforgedSheet` (default `'starforged'`), have `StarforgedSheetView` read it for the asset picker + header label, and add a 4th create-chooser option. No new sheet/model class, no schema bump, no build-script change.

**Tech Stack:** Dart/Flutter, flutter_riverpod, shared_preferences (mock in tests). TDD with `flutter test` + `dart analyze`.

**Spec:** `docs/superpowers/specs/2026-06-17-sundered-isles-sheet-design.md`

**Conventions:** `dart format` runs on every `.dart` save (hook). Widget tests MUST override `rulesetDataProvider(...)` (never rootBundle). `StarforgedSheet` lives at `lib/engine/models.dart:585`; `StarforgedSheetView` at `lib/features/starforged_sheet.dart`; create flow at `lib/features/tracker_screen.dart:228-289`.

---

## Task 1: `assetRuleset` field on `StarforgedSheet`

**Files:**
- Modify: `lib/engine/models.dart` (the `StarforgedSheet` class, 585-737)
- Test: `test/character_sheet_test.dart`

- [ ] **Step 1: Write the failing test** (add inside `void main()`):

```dart
  group('StarforgedSheet.assetRuleset', () {
    test('defaults to starforged; premade can set sundered_isles', () {
      expect(const StarforgedSheet().assetRuleset, 'starforged');
      expect(StarforgedSheet.premade().assetRuleset, 'starforged');
      expect(StarforgedSheet.premade().isSundered, isFalse);
      final si = StarforgedSheet.premade(assetRuleset: 'sundered_isles');
      expect(si.assetRuleset, 'sundered_isles');
      expect(si.isSundered, isTrue);
    });

    test('round-trips; omitted from toJson when default', () {
      expect(StarforgedSheet.premade().toJson().containsKey('assetRuleset'),
          isFalse);
      final si = StarforgedSheet.premade(assetRuleset: 'sundered_isles');
      expect(si.toJson()['assetRuleset'], 'sundered_isles');
      expect(StarforgedSheet.maybeFromJson(si.toJson())!.assetRuleset,
          'sundered_isles');
    });

    test('legacy JSON and junk values resolve to starforged', () {
      // No key (existing Starforged characters).
      final legacy = StarforgedSheet.maybeFromJson({'edge': 2})!;
      expect(legacy.assetRuleset, 'starforged');
      // Junk / unknown.
      expect(StarforgedSheet.maybeFromJson({'assetRuleset': 'bogus'})!.assetRuleset,
          'starforged');
      expect(StarforgedSheet.maybeFromJson({'assetRuleset': 42})!.assetRuleset,
          'starforged');
    });

    test('copyWith passes through and sanitizes', () {
      final si = const StarforgedSheet().copyWith(assetRuleset: 'sundered_isles');
      expect(si.assetRuleset, 'sundered_isles');
      expect(si.copyWith().assetRuleset, 'sundered_isles');
      expect(si.copyWith(assetRuleset: 'nope').assetRuleset, 'starforged');
    });
  });
```

- [ ] **Step 2: Run, verify fail**

Run: `flutter test test/character_sheet_test.dart`
Expected: FAIL — `assetRuleset`/`isSundered`/`premade(assetRuleset:)` undefined.

- [ ] **Step 3: Implement** — five edits to `StarforgedSheet` in `lib/engine/models.dart`:

(a) Constructor — add after `this.assets = const [],` (line 604):
```dart
    this.assetRuleset = 'starforged',
```
(b) Field + getter — add after the `final List<AssetState> assets;` line (line 615):
```dart
  final String assetRuleset; // 'starforged' | 'sundered_isles'

  bool get isSundered => assetRuleset == 'sundered_isles';

  static String _validRuleset(String s) =>
      s == 'sundered_isles' ? 'sundered_isles' : 'starforged';
```
(c) `premade` — replace the whole factory (lines 620-630) with a parameterized, non-const version:
```dart
  factory StarforgedSheet.premade({String assetRuleset = 'starforged'}) =>
      StarforgedSheet(
        edge: 3,
        heart: 2,
        iron: 2,
        shadow: 1,
        wits: 1,
        health: 5,
        spirit: 5,
        supply: 5,
        momentum: 2,
        assetRuleset: assetRuleset,
      );
```
(d) `copyWith` — add a param after `List<AssetState>? assets,` (line 650):
```dart
    String? assetRuleset,
```
and add to the returned `StarforgedSheet(...)` after the `assets:` line (line 673):
```dart
      assetRuleset: _validRuleset(assetRuleset ?? this.assetRuleset),
```
(e) `toJson` — add after the `assets` line (line 696, inside the map literal):
```dart
        if (assetRuleset != 'starforged') 'assetRuleset': assetRuleset,
```
(f) `maybeFromJson` — add after the `assets:` block (after line 735, before the closing `);`):
```dart
      assetRuleset: _validRuleset(
          j['assetRuleset'] is String ? j['assetRuleset'] as String : 'starforged'),
```

- [ ] **Step 4: Run, verify pass**

Run: `flutter test test/character_sheet_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/models.dart test/character_sheet_test.dart
git commit -m "feat(sundered): assetRuleset discriminator on StarforgedSheet"
```

---

## Task 2: Sundered Isles create flow + picker/label wiring

**Files:**
- Modify: `lib/state/providers.dart` (`addStarforged`)
- Modify: `lib/features/starforged_sheet.dart` (label + asset picker ruleset)
- Modify: `lib/features/tracker_screen.dart` (chooser + `_newSundered`)
- Test: `test/character_sheet_ui_test.dart`

- [ ] **Step 1: Write the failing tests** (add inside `void main()`; reuse existing imports + the `pumpStarforged` helper):

```dart
  testWidgets('create flow makes a Sundered Isles character with SI label',
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
    await tester.tap(find.byKey(const Key('new-sundered')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('starforged-sheet')), findsOneWidget);
    expect(find.text('Sundered Isles'), findsOneWidget);
    final chars = await c.read(charactersProvider.future);
    expect(chars.single.starforged!.assetRuleset, 'sundered_isles');
  });

  testWidgets('Sundered Isles picker lists SI assets', (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1",'
              '"systems":["ironsworn"]}]}',
      'juice.rulesets.v1': '["starforged","sundered_isles"]',
      'juice.characters.v1.default':
          '[{"id":"si","name":"Mara","note":"","stats":[],"tracks":[],'
              '"tags":[],"starforged":{"edge":3,"heart":2,"iron":2,"shadow":1,'
              '"wits":1,"health":5,"spirit":5,"supply":5,"momentum":2,'
              '"xpEarned":0,"xpSpent":0,"questsLegacy":0,"bondsLegacy":0,'
              '"discoveriesLegacy":0,"assetRuleset":"sundered_isles"}}]',
    });
    final fixture = {
      'asset_collections': [
        {
          'name': 'Path',
          'assets': [
            {
              'id': 'asset:sundered_isles/path/corsair',
              'name': 'Corsair',
              'category': 'Path',
              'abilities': [
                {'text': 'Sail hard', 'enabled': true},
              ],
            },
          ],
        },
      ],
    };
    final c = ProviderContainer(overrides: [
      rulesetDataProvider('sundered_isles').overrideWith((ref) async => fixture),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CharactersPane()))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mara'));
    await tester.pumpAndSettle();
    expect(find.text('Sundered Isles'), findsOneWidget);
    await tester.drag(
        find.byKey(const Key('starforged-sheet')), const Offset(0, -1200));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('sf-add-asset')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sf-add-asset')));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const Key('pick-asset-asset:sundered_isles/path/corsair')),
        findsOneWidget);
  });
```

- [ ] **Step 2: Run, verify fail**

Run: `flutter test test/character_sheet_ui_test.dart`
Expected: FAIL — `new-sundered` not found.

- [ ] **Step 3a: `addStarforged` gains the ruleset arg** — in `lib/state/providers.dart`, replace the `addStarforged` method (lines 248-258) with:

```dart
  /// Creates a pre-made Starforged (or Sundered Isles) PC and returns its id.
  Future<String> addStarforged({String assetRuleset = 'starforged'}) async {
    final id = _newId();
    final name = assetRuleset == 'sundered_isles'
        ? 'New Sundered Isles character'
        : 'New Starforged character';
    await _persist([
      Character(
          id: id,
          name: name,
          starforged: StarforgedSheet.premade(assetRuleset: assetRuleset)),
      ...await _ready,
    ]);
    return id;
  }
```

- [ ] **Step 3b: Sheet label + picker ruleset** — in `lib/features/starforged_sheet.dart`:

Replace the label line (line 62):
```dart
        Text(s.isSundered ? 'Sundered Isles' : 'Starforged',
            style: theme.textTheme.labelSmall),
```
Replace the asset-picker call (line 214) inside the `sf-add-asset` button's `onPressed`:
```dart
            final def = await addAssetDialog(context, ref, _s.assetRuleset);
```

- [ ] **Step 3c: Chooser + `_newSundered`** — in `lib/features/tracker_screen.dart`:

Add a fourth button after the `new-starforged` `FilledButton` (after line 255), inside the `actions:` list:
```dart
          FilledButton(
            key: const Key('new-sundered'),
            onPressed: () => Navigator.pop(context, 'sundered'),
            child: const Text('Sundered Isles'),
          ),
```
Add a choice branch after the `else if (choice == 'starforged') { … }` (after line 266):
```dart
    } else if (choice == 'sundered') {
      await _newSundered();
```
Add the method after `_newStarforged` (after line 289):
```dart
  Future<void> _newSundered() async {
    // Enabling sundered_isles pulls in base starforged per the family rules.
    final rs = ref.read(rulesetsProvider).valueOrNull ?? const <String>{};
    if (!rs.contains('sundered_isles')) {
      await ref
          .read(rulesetsProvider.notifier)
          .setRuleset('sundered_isles', true);
    }
    final id = await ref
        .read(charactersProvider.notifier)
        .addStarforged(assetRuleset: 'sundered_isles');
    if (mounted) setState(() => _editingId = id);
  }
```

- [ ] **Step 4: Run, verify pass**

Run: `flutter test test/character_sheet_ui_test.dart`
Expected: PASS (new SI tests + all existing tests green; the existing Starforged tests still show the 'Starforged' label and use the 'starforged' picker).

- [ ] **Step 5: Analyze**

Run: `dart analyze lib/state/providers.dart lib/features/starforged_sheet.dart lib/features/tracker_screen.dart test/character_sheet_ui_test.dart`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/state/providers.dart lib/features/starforged_sheet.dart lib/features/tracker_screen.dart test/character_sheet_ui_test.dart
git commit -m "feat(sundered): create flow + SI asset picker + label"
```

---

## Task 3: Real-data test + full verification + docs

**Files:**
- Modify: `test/ruleset_assets_test.dart`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Write the real-data test** — add to the existing `void main()` in `test/ruleset_assets_test.dart`:

```dart
  test('real ruleset_sundered_isles.json parses into 60 well-formed asset defs',
      () {
    final raw = File('assets/ruleset_sundered_isles.json').readAsStringSync();
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final defs = IronswornAssetDef.listFromRuleset(data);
    expect(defs.length, 60,
        reason: 'sundered isles has 60 assets across 6 categories');
    for (final d in defs) {
      expect(d.id, isNotEmpty);
      expect(d.name, isNotEmpty);
      expect(d.abilityEnabled.length, d.abilities.length);
    }
    final cats = defs.map((d) => d.category).toSet();
    expect(cats, containsAll(<String>['Path', 'Module', 'Companion']));
  });
```

- [ ] **Step 2: Run real-data + full suites**

Run: `flutter test test/ruleset_assets_test.dart`
Expected: PASS (60 SI assets parse).

Run: `flutter test`
Expected: all pass (no regressions).

- [ ] **Step 3: Analyze**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 4: Update CLAUDE.md** — the `build_datasworn.py` bullet currently ends with the sentence about each sheet pinning its own asset ruleset. Append:

> Sundered Isles reuses the Starforged sheet via a `StarforgedSheet.assetRuleset` discriminator (`starforged` | `sundered_isles`) that selects the asset set; see `docs/superpowers/specs/2026-06-17-sundered-isles-sheet-design.md`.

- [ ] **Step 5: Commit**

```bash
git add test/ruleset_assets_test.dart CLAUDE.md
git commit -m "test(sundered): real ruleset_sundered_isles.json parse + docs"
```

---

## Self-Review (completed during planning)

**Spec coverage:**
- `assetRuleset` field (default/validate/round-trip/omit/isSundered) → Task 1. ✓
- `addStarforged(assetRuleset:)` + SI name → Task 2 Step 3a. ✓
- Picker reads `_s.assetRuleset`; header label → Task 2 Step 3b. ✓
- 4th create option + `_newSundered` (enables sundered_isles ruleset) → Task 2 Step 3c. ✓
- Real-data 60-asset parse → Task 3. ✓
- No new class, no schema bump → only StarforgedSheet field added (Task 1). ✓
- No build-script change → confirmed (SI assets already emitted). ✓

**Type consistency:** `assetRuleset`/`isSundered`/`_validRuleset`/`premade({assetRuleset})` defined Task 1, used by Task 2 (`addStarforged`, sheet label/picker). `new-sundered` → `'sundered'` choice → `_newSundered` → `addStarforged(assetRuleset:'sundered_isles')`. Picker uses `_s.assetRuleset` (fresh getter).

**Placeholder scan:** none — every step has complete code.

**Out of scope:** new sheet/model class, impact/track changes, build-script changes, asset meters/inputs, D&D/Shadowdark, LLM-rules.
