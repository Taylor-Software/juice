# Ironsworn Family Phase 3 Implementation Plan (All Rulesets + Exclusivity)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** All four rulesets toggleable with the spec's logical exclusivity (expansions require their base; base games mutually exclusive), expansions merged into their base's Moves tab.

**Architecture:** Exclusivity lives in `RulesetsNotifier.setRuleset(id, on)` (pure, testable); the UI confirm dialog fires only for the destructive base-game swap. `MovesScreen` takes the enabled family (base + optional expansion) and concatenates categories/collections, expansion sections suffixed with the expansion title.

**Tech Stack:** existing only. Assets for all four rulesets already shipped in phase 1.

---

**Rules (docs/specs/ironsworn-family.md):**
- `classic` (Ironsworn) and `starforged` are base games, mutually exclusive.
- `delve` requires `classic`; `sundered_isles` requires `starforged`; expansions auto-off with their base.
- Enabling an expansion with its base off enables the base too (single action).
- Enabling a base while the other family is on swaps families (UI confirms first).

### Task 1: Notifier rules (TDD)

**Files:**
- Modify: `lib/state/providers.dart` (RulesetsNotifier)
- Test: `test/ironsworn_test.dart` (append)

- [ ] **Step 1: Failing test** (append):

```dart
  group('Ruleset exclusivity rules', () {
    Future<RulesetsNotifier> boot(ProviderContainer c) async {
      await c.read(rulesetsProvider.future);
      return c.read(rulesetsProvider.notifier);
    }

    test('enabling an expansion brings its base; disabling base drops expansion',
        () async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = await boot(c);
      await n.setRuleset('delve', true);
      expect(await c.read(rulesetsProvider.future), {'classic', 'delve'});
      await n.setRuleset('classic', false);
      expect(await c.read(rulesetsProvider.future), isEmpty);
    });

    test('base games are mutually exclusive (family swap)', () async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = await boot(c);
      await n.setRuleset('sundered_isles', true);
      expect(await c.read(rulesetsProvider.future),
          {'starforged', 'sundered_isles'});
      await n.setRuleset('classic', true);
      expect(await c.read(rulesetsProvider.future), {'classic'});
    });
  });
```

- [ ] **Step 2:** FAIL (setRuleset undefined).

- [ ] **Step 3: Implement** in `RulesetsNotifier` (keep `toggle` for compatibility or replace its call sites — REPLACE: delete `toggle`, update the one UI call site in Task 2; if tests elsewhere use toggle, update them to setRuleset):

```dart
  static const _bases = {'classic', 'starforged'};
  static const _expansionOf = {'delve': 'classic', 'sundered_isles': 'starforged'};

  /// Apply the family rules: expansions require their base; the two base
  /// games are mutually exclusive (enabling one drops the other family).
  Future<void> setRuleset(String id, bool on) async {
    final current = {...(state.valueOrNull ?? await future)};
    if (on) {
      final base = _expansionOf[id] ?? id;
      if (_bases.contains(base)) {
        final otherBase = base == 'classic' ? 'starforged' : 'classic';
        current.remove(otherBase);
        current.removeWhere((r) => _expansionOf[r] == otherBase);
      }
      current.add(base);
      if (_expansionOf.containsKey(id)) current.add(id);
    } else {
      current.remove(id);
      current.removeWhere((r) => _expansionOf[r] == id);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(current.toList()));
    state = AsyncData(current);
  }
```

(`_key` already exists. Existing `toggle` test in ironsworn_test.dart: update it to call `setRuleset('starforged', true/false)` and keep its persistence assertions.)

- [ ] **Step 4:** suite green (63 tests: 61 + 2, with the toggle test updated in place). **Step 5: Commit**

```bash
git add lib/state/providers.dart test/ironsworn_test.dart
git commit -m "feat: ruleset family rules — expansions require base, bases exclusive"
```

### Task 2: UI — four switches + family merge

**Files:**
- Modify: `lib/shared/home_shell.dart`
- Modify: `lib/features/moves_screen.dart`

- [ ] **Step 1: Rulesets dialog** — replace the single SwitchListTile with four, driven by a small list; confirm dialog only when enabling a base/expansion would drop the other ACTIVE family:

```dart
    const rulesetNames = {
      'classic': 'Ironsworn',
      'delve': 'Ironsworn: Delve',
      'starforged': 'Ironsworn: Starforged',
      'sundered_isles': 'Starforged: Sundered Isles',
    };
```

Dialog children (inside the existing Consumer):

```dart
                  for (final id in const [
                    'classic',
                    'delve',
                    'starforged',
                    'sundered_isles'
                  ])
                    SwitchListTile(
                      title: Text(rulesetNames[id]!),
                      subtitle: id == 'classic'
                          ? const Text('Rules © Shawn Tomkin, CC-BY 4.0')
                          : null,
                      value: enabled.contains(id),
                      onChanged: (on) async {
                        final otherFamily = (id == 'classic' || id == 'delve')
                            ? const {'starforged', 'sundered_isles'}
                            : const {'classic', 'delve'};
                        if (on && enabled.any(otherFamily.contains)) {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Switch family?'),
                              content: const Text(
                                  'Ironsworn and Starforged are separate games — enabling this turns the other family off.'),
                              actions: [
                                TextButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(false),
                                    child: const Text('Cancel')),
                                FilledButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(true),
                                    child: const Text('Switch')),
                              ],
                            ),
                          );
                          if (ok != true) return;
                        }
                        await ref
                            .read(rulesetsProvider.notifier)
                            .setRuleset(id, on);
                      },
                    ),
```

- [ ] **Step 2: Family pages** — in `_HomeShellState.build`:

```dart
    final rulesets = ref.watch(rulesetsProvider).valueOrNull ?? const <String>{};
    final family = [
      if (rulesets.contains('classic')) 'classic',
      if (rulesets.contains('delve')) 'delve',
      if (rulesets.contains('starforged')) 'starforged',
      if (rulesets.contains('sundered_isles')) 'sundered_isles',
    ];
    final hasMoves = family.isNotEmpty;
```

Pages: `if (hasMoves) MovesScreen(rulesetIds: family),` (replaces the starforged-only line); destination unchanged label 'Moves'.

- [ ] **Step 3: MovesScreen merge** — change to `final List<String> rulesetIds;` (`required this.rulesetIds`). In build, load all and merge:

```dart
    final asyncs = widget.rulesetIds
        .map((id) => ref.watch(rulesetDataProvider(id)))
        .toList();
    if (asyncs.any((a) => a.isLoading)) {
      return const Center(child: CircularProgressIndicator());
    }
    final err = asyncs.where((a) => a.hasError).firstOrNull;
    if (err != null) return Center(child: Text('Error: ${err.error}'));
    final datas = asyncs.map((a) => a.value!).toList();
    final base = datas.first;
    final categories = <Map<String, dynamic>>[
      for (var i = 0; i < datas.length; i++)
        for (final cat
            in (datas[i]['move_categories'] as List).cast<Map<String, dynamic>>())
          i == 0
              ? cat
              : {...cat, 'name': '${cat['name']} (${(datas[i]['meta'] as Map)['title']})'},
    ];
    final collections = <Map<String, dynamic>>[
      for (var i = 0; i < datas.length; i++)
        for (final coll in (datas[i]['oracle_collections'] as List)
            .cast<Map<String, dynamic>>())
          i == 0
              ? coll
              : {...coll, 'name': '${coll['name']} (${(datas[i]['meta'] as Map)['title']})'},
    ];
```

Pass `categories`/`collections` into `_MovesList`/`_OraclesList` (change their constructors from `data` to the lists), and build the attribution footer from all metas: `datas.map((d) => (d['meta'] as Map)['title']).join(' + ')` © joined authors, CC-BY 4.0.

- [ ] **Step 4:** `flutter analyze && flutter test` green (63, 4 infos); `flutter build web` ✓.

- [ ] **Step 5: Commit**

```bash
git add lib/shared/home_shell.dart lib/features/moves_screen.dart
git commit -m "feat: all four rulesets with family exclusivity and merged Moves tab"
```

### Task 3: Docs

README: update the Starforged paragraph to the full family (Ironsworn, Delve, Starforged, Sundered Isles; expansions fold into their base's Moves tab; families mutually exclusive). Commit `docs: full Ironsworn family`.

## Self-review notes
- Spec P0 remaining clauses: four toggles + exclusivity ✓, Delve/Sundered merge into base lists ✓ (suffix-labelled sections), attribution covers all enabled ✓, Juice-only unchanged ✓.
- Delve sundered classic licensing: classic/delve are CC-BY-4.0 per their package `license` fields emitted into each asset's meta (verify at runtime nothing prints NC wrongly — footer says CC-BY 4.0; if any meta.license differs, render meta.license instead: implementer must check the four assets' meta.license values and use the per-asset value in the footer if they differ).
- `toggle` removed → no dead API.
