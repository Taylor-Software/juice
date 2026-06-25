# Campaign Creation Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the flat 16-checkbox campaign-creation dialog with a presets-first flow backed by a system-category model (P1, this plan). P2 (grouped wizard + live preview) is a separate follow-up plan.

**Architecture:** Add a pure authored category constant (`kSystemCategory`) and a canonical system set (`kKnownSystems`) in the engine, plus a pure `CampaignPreset` list. Rework `NewCampaignDialog` to a presets grid + a "Custom" grouped category picker, and regroup `_EditSystemsDialog` by the same categories. `kAllSystems` is deliberately left untouched (it is the legacy-null fallback, not the creation seed). The dialog's return contract `(name, systems, mode, genre, tone)` is preserved so callers don't change.

**Tech Stack:** Dart, Flutter, flutter_riverpod, shared_preferences, flutter_test.

**Working directory:** `.worktrees/campaign-redesign` (branch `campaign-redesign`). Paths relative to repo root.

**Do NOT stage:** `macos/Runner.xcodeproj`, `macos/Runner.xcworkspace`, `macos/Podfile.lock`.

**Spec:** `docs/superpowers/specs/2026-06-24-campaign-creation-redesign-design.md`.

---

## Key facts from the codebase (verified)

- `kAllSystems = {'juice','mythic','ironsworn','party','verdant'}` lives at `lib/engine/models.dart:3190`. It has ~17 consumers as a **fallback** (returned by `SessionMeta.enabledSystems` when `systems == null`, and as a default param in many widgets). `test/system_profiles_test.dart:8` hard-asserts its exact value. **DO NOT change `kAllSystems`.**
- There is **no** canonical full-system-id list today. The complete set of 16 ids is implied by `kSystemBlurbs` keys (`lib/shared/home_shell.dart:681-707`), the `NewCampaignDialog` bool fields, and the `_EditSystemsDialog` rows — three hand-synced copies.
- The 16 ids: `juice, mythic, ironsworn, party, verdant, lonelog, hexcrawl, dnd, shadowdark, nimble, draw-steel, argosa, cairn, knave, ose, cards`.
- `NewCampaignDialog` (`lib/shared/home_shell.dart`): State fields 717-736, `dispose` 738-744, `_submit()` 746-772, `build()` 774-965. It pops a record `({name, systems, mode, genre, tone})`.
- `_EditSystemsDialog` (`lib/shared/home_shell.dart:969-1033`): `_row(id,label)` helper 980-992, rows 1002-1017, pops `Set<String>`.
- `SessionsNotifier.create(name, {systems, mode, genre, tone})` (`lib/state/providers.dart:1320-1336`) — unchanged by this plan.
- `models.dart` already defines `CampaignMode` and is pure Dart (no `flutter/material`). Category constants go there. `IconData` is UI-only, so presets stay pure (no icon field); the UI maps preset id → icon.

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `lib/engine/models.dart` | Modify | Add `kKnownSystems`, `SystemCategory` enum, `kSystemCategory` map |
| `lib/engine/campaign_presets.dart` | Create | `CampaignPreset` (pure), `kCampaignPresets`, `presetConfig` |
| `lib/shared/home_shell.dart` | Modify | Rework `NewCampaignDialog`; regroup `_EditSystemsDialog`; add `kPresetIcons` |
| `test/campaign_presets_test.dart` | Create | Category completeness, blurb coverage, preset resolution |
| `test/new_campaign_dialog_test.dart` | Modify | New presets-grid behavior |
| `test/system_profiles_test.dart` | Untouched | (kAllSystems unchanged — must stay green) |

---

## P1 — presets-first (this plan, shippable)

### Task 1: Category model + canonical system set

**Files:**
- Modify: `lib/engine/models.dart`
- Create: `test/campaign_presets_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/campaign_presets_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';

void main() {
  group('kKnownSystems + kSystemCategory', () {
    test('kKnownSystems has the 16 ids', () {
      expect(kKnownSystems, {
        'juice', 'mythic', 'ironsworn', 'party', 'verdant', 'lonelog',
        'hexcrawl', 'dnd', 'shadowdark', 'nimble', 'draw-steel', 'argosa',
        'cairn', 'knave', 'ose', 'cards',
      });
    });

    test('kAllSystems is a subset of kKnownSystems (and unchanged)', () {
      expect(kAllSystems, {'juice', 'mythic', 'ironsworn', 'party', 'verdant'});
      expect(kKnownSystems.containsAll(kAllSystems), isTrue);
    });

    test('every known system is categorized exactly once', () {
      expect(kSystemCategory.keys.toSet(), kKnownSystems);
    });

    test('ruleset category holds the 10 sheet systems', () {
      final rulesets = kSystemCategory.entries
          .where((e) => e.value == SystemCategory.ruleset)
          .map((e) => e.key)
          .toSet();
      expect(rulesets, {
        'ironsworn', 'dnd', 'shadowdark', 'nimble', 'draw-steel', 'argosa',
        'cairn', 'knave', 'ose',
      });
    });

    test('oracle/exploration/tools categories', () {
      Set<String> of(SystemCategory c) => kSystemCategory.entries
          .where((e) => e.value == c)
          .map((e) => e.key)
          .toSet();
      expect(of(SystemCategory.oracle), {'juice', 'mythic', 'cards'});
      expect(of(SystemCategory.exploration), {'verdant', 'hexcrawl'});
      expect(of(SystemCategory.tools), {'party', 'lonelog'});
    });
  });
}
```

Note: the "ruleset category holds the 10 sheet systems" test name says 10 but lists 9 — Ironsworn is one `ruleset` system that fronts the Ironsworn/Starforged/Sundered family. Fix the test name to "9 ruleset systems" when writing it.

- [ ] **Step 2: Run to verify it fails**

Run: `cd .worktrees/campaign-redesign && flutter test test/campaign_presets_test.dart`
Expected: FAIL — `kKnownSystems`, `SystemCategory`, `kSystemCategory` undefined.

- [ ] **Step 3: Add the constants to `lib/engine/models.dart`**

Immediately after the `kAllSystems` declaration (line ~3190), add:

```dart
/// Canonical set of every campaign system id. The single source of truth that
/// kSystemCategory, kSystemBlurbs, and the creation/edit dialogs are checked
/// against. kAllSystems (the 5 legacy-default ids) is a SUBSET of this.
const kKnownSystems = <String>{
  'juice', 'mythic', 'ironsworn', 'party', 'verdant', 'lonelog', 'hexcrawl',
  'dnd', 'shadowdark', 'nimble', 'draw-steel', 'argosa', 'cairn', 'knave',
  'ose', 'cards',
};

/// The four buckets a system belongs to for grouped campaign setup.
enum SystemCategory { ruleset, oracle, exploration, tools }

/// Every system's category. Ruleset is single-select at creation (a campaign
/// runs one game); the model still permits multiple. A completeness test keeps
/// this in lockstep with kKnownSystems.
const kSystemCategory = <String, SystemCategory>{
  'ironsworn': SystemCategory.ruleset,
  'dnd': SystemCategory.ruleset,
  'shadowdark': SystemCategory.ruleset,
  'nimble': SystemCategory.ruleset,
  'draw-steel': SystemCategory.ruleset,
  'argosa': SystemCategory.ruleset,
  'cairn': SystemCategory.ruleset,
  'knave': SystemCategory.ruleset,
  'ose': SystemCategory.ruleset,
  'juice': SystemCategory.oracle,
  'mythic': SystemCategory.oracle,
  'cards': SystemCategory.oracle,
  'verdant': SystemCategory.exploration,
  'hexcrawl': SystemCategory.exploration,
  'party': SystemCategory.tools,
  'lonelog': SystemCategory.tools,
};
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/campaign_presets_test.dart`
Expected: PASS (5 tests). Then `flutter analyze` — clean.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/models.dart test/campaign_presets_test.dart
git commit -m "$(cat <<'EOF'
feat(campaign): kKnownSystems + SystemCategory model

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: CampaignPreset + presetConfig

**Files:**
- Create: `lib/engine/campaign_presets.dart`
- Modify: `test/campaign_presets_test.dart`

- [ ] **Step 1: Add failing tests**

Append to `test/campaign_presets_test.dart` (add the import at top:
`import 'package:juice_oracle/engine/campaign_presets.dart';`):

```dart
  group('kCampaignPresets', () {
    test('every preset references only known systems', () {
      for (final p in kCampaignPresets) {
        for (final s in p.systems) {
          expect(kKnownSystems.contains(s), isTrue, reason: '${p.id}: $s');
        }
      }
    });

    test('ruleset presets are party mode with juice + party + one ruleset', () {
      final rulesetPresets =
          kCampaignPresets.where((p) => p.id.startsWith('solo-'));
      expect(rulesetPresets.length, 9);
      for (final p in rulesetPresets) {
        expect(p.mode, CampaignMode.party, reason: p.id);
        expect(p.systems.contains('juice'), isTrue, reason: p.id);
        expect(p.systems.contains('party'), isTrue, reason: p.id);
        final rulesets = p.systems
            .where((s) => kSystemCategory[s] == SystemCategory.ruleset);
        expect(rulesets.length, 1, reason: p.id);
      }
    });

    test('shape presets: oracle (party) and gm-toolkit (gm)', () {
      final oracle = kCampaignPresets.firstWhere((p) => p.id == 'oracle');
      expect(oracle.mode, CampaignMode.party);
      expect(oracle.systems, {'juice', 'mythic', 'cards', 'party'});
      final gm = kCampaignPresets.firstWhere((p) => p.id == 'gm-toolkit');
      expect(gm.mode, CampaignMode.gm);
      expect(gm.systems, {'juice', 'mythic'});
    });

    test('preset ids are unique', () {
      final ids = kCampaignPresets.map((p) => p.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('presetConfig returns the preset mode + systems', () {
      final p = kCampaignPresets.firstWhere((p) => p.id == 'solo-cairn');
      final (mode, systems) = presetConfig(p);
      expect(mode, CampaignMode.party);
      expect(systems, {'cairn', 'juice', 'party'});
    });
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/campaign_presets_test.dart`
Expected: FAIL — `campaign_presets.dart` missing.

- [ ] **Step 3: Create `lib/engine/campaign_presets.dart`**

```dart
import 'models.dart';

/// A one-tap campaign starting point: a mode + a curated lean system set.
/// Pure data — no Flutter dependency (icons are resolved in the UI layer).
class CampaignPreset {
  const CampaignPreset({
    required this.id,
    required this.label,
    required this.mode,
    required this.systems,
  });

  final String id;
  final String label;
  final CampaignMode mode;
  final Set<String> systems;
}

/// Resolves a preset to the (mode, systems) a new campaign is created with.
(CampaignMode, Set<String>) presetConfig(CampaignPreset p) =>
    (p.mode, p.systems);

/// Ruleset presets (party mode, juice oracle + party tools + the ruleset) +
/// two shape presets. "Custom" is a UI affordance, not a preset entry.
const kCampaignPresets = <CampaignPreset>[
  CampaignPreset(
      id: 'solo-ironsworn',
      label: 'Ironsworn / Starforged',
      mode: CampaignMode.party,
      systems: {'ironsworn', 'juice', 'party'}),
  CampaignPreset(
      id: 'solo-dnd',
      label: 'D&D 5e',
      mode: CampaignMode.party,
      systems: {'dnd', 'juice', 'party'}),
  CampaignPreset(
      id: 'solo-shadowdark',
      label: 'Shadowdark',
      mode: CampaignMode.party,
      systems: {'shadowdark', 'juice', 'party'}),
  CampaignPreset(
      id: 'solo-nimble',
      label: 'Nimble',
      mode: CampaignMode.party,
      systems: {'nimble', 'juice', 'party'}),
  CampaignPreset(
      id: 'solo-draw-steel',
      label: 'Draw Steel',
      mode: CampaignMode.party,
      systems: {'draw-steel', 'juice', 'party'}),
  CampaignPreset(
      id: 'solo-argosa',
      label: 'Tales of Argosa',
      mode: CampaignMode.party,
      systems: {'argosa', 'juice', 'party'}),
  CampaignPreset(
      id: 'solo-cairn',
      label: 'Cairn',
      mode: CampaignMode.party,
      systems: {'cairn', 'juice', 'party'}),
  CampaignPreset(
      id: 'solo-knave',
      label: 'Knave 2e',
      mode: CampaignMode.party,
      systems: {'knave', 'juice', 'party'}),
  CampaignPreset(
      id: 'solo-ose',
      label: 'OSE / B/X',
      mode: CampaignMode.party,
      systems: {'ose', 'juice', 'party'}),
  CampaignPreset(
      id: 'oracle',
      label: 'System-agnostic oracle',
      mode: CampaignMode.party,
      systems: {'juice', 'mythic', 'cards', 'party'}),
  CampaignPreset(
      id: 'gm-toolkit',
      label: 'GM toolkit',
      mode: CampaignMode.gm,
      systems: {'juice', 'mythic'}),
];
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/campaign_presets_test.dart`
Expected: PASS (all groups). `flutter analyze` clean.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/campaign_presets.dart test/campaign_presets_test.dart
git commit -m "$(cat <<'EOF'
feat(campaign): CampaignPreset list + presetConfig

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Rework NewCampaignDialog to presets-first

**Files:**
- Modify: `lib/shared/home_shell.dart`
- Modify: `test/new_campaign_dialog_test.dart`

The dialog keeps its return contract `({name, systems, mode, genre, tone})` and these keys: `new-campaign-name`, `new-campaign-genre`, `new-campaign-tone`, `new-campaign-mode` (now only shown in Custom). New keys: `preset-<id>` per preset card, `preset-custom` for the Custom toggle, `cat-<system>` checkboxes, `ruleset-<system>` radio entries.

- [ ] **Step 1: Rewrite the creation tests first**

Replace `test/new_campaign_dialog_test.dart` entirely:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/shared/home_shell.dart';

typedef NewCampaignResult = ({
  String name,
  Set<String> systems,
  CampaignMode mode,
  String genre,
  String tone,
});

Future<NewCampaignResult?> _open(WidgetTester tester) async {
  NewCampaignResult? result;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () async {
            result = await showDialog<NewCampaignResult>(
              context: context,
              builder: (_) => const NewCampaignDialog(),
            );
          },
          child: const Text('open'),
        );
      }),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('kSystemBlurbs covers every known system', (tester) async {
    for (final id in kKnownSystems) {
      expect(kSystemBlurbs[id], isNotNull, reason: id);
    }
  });

  testWidgets('default preset (Ironsworn) → name + party + juice', (tester) async {
    await _open(tester);
    await tester.enterText(
        find.byKey(const Key('new-campaign-name')), 'My Saga');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    // result captured by closure — re-open pattern: assert via a second pump
  });

  testWidgets('tapping a ruleset preset selects its systems + mode',
      (tester) async {
    NewCampaignResult? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () async {
            result = await showDialog<NewCampaignResult>(
              context: context,
              builder: (_) => const NewCampaignDialog(),
            );
          },
          child: const Text('open'),
        );
      })),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('new-campaign-name')), 'Cairn Run');
    await tester.tap(find.byKey(const Key('preset-solo-cairn')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(result!.name, 'Cairn Run');
    expect(result!.mode, CampaignMode.party);
    expect(result!.systems, {'cairn', 'juice', 'party'});
  });

  testWidgets('GM toolkit preset returns gm mode', (tester) async {
    NewCampaignResult? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () async {
            result = await showDialog<NewCampaignResult>(
              context: context,
              builder: (_) => const NewCampaignDialog(),
            );
          },
          child: const Text('open'),
        );
      })),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('new-campaign-name')), 'Table');
    await tester.tap(find.byKey(const Key('preset-gm-toolkit')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(result!.mode, CampaignMode.gm);
    expect(result!.systems, {'juice', 'mythic'});
  });

  testWidgets('Custom reveals grouped picker; ruleset is single-select',
      (tester) async {
    NewCampaignResult? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () async {
            result = await showDialog<NewCampaignResult>(
              context: context,
              builder: (_) => const NewCampaignDialog(),
            );
          },
          child: const Text('open'),
        );
      })),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('new-campaign-name')), 'Custom');
    await tester.tap(find.byKey(const Key('preset-custom')));
    await tester.pumpAndSettle();
    // grouped picker is now visible
    expect(find.byKey(const Key('ruleset-dnd')), findsOneWidget);
    expect(find.byKey(const Key('cat-cards')), findsOneWidget);
    // pick a ruleset + an oracle add-on
    await tester.tap(find.byKey(const Key('ruleset-dnd')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cat-cards')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(result!.systems.contains('dnd'), isTrue);
    expect(result!.systems.contains('cards'), isTrue);
  });
}
```

Delete the placeholder second test ("default preset … re-open pattern") — it was a stub; the third test covers selection. (Keep tests 1, 3, 4, 5.)

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/new_campaign_dialog_test.dart`
Expected: FAIL — `preset-*`, `ruleset-*`, `cat-*` keys not found; `kKnownSystems` may be unreferenced in the dialog file.

- [ ] **Step 3: Add the preset-icon map + rework the dialog**

In `lib/shared/home_shell.dart`, add an import:
`import '../engine/campaign_presets.dart';`

Add a UI-side icon map near `kSystemBlurbs`:

```dart
const kPresetIcons = <String, IconData>{
  'solo-ironsworn': Icons.bolt,
  'solo-dnd': Icons.castle,
  'solo-shadowdark': Icons.dark_mode,
  'solo-nimble': Icons.flash_on,
  'solo-draw-steel': Icons.shield,
  'solo-argosa': Icons.fort,
  'solo-cairn': Icons.terrain,
  'solo-knave': Icons.content_cut,
  'solo-ose': Icons.auto_stories,
  'oracle': Icons.casino,
  'gm-toolkit': Icons.book,
};
```

Replace the `_NewCampaignDialogState` body. Drop the 16 `bool _<sys>` fields and the `sys-*` CheckboxListTiles. New state:

```dart
class _NewCampaignDialogState extends State<NewCampaignDialog> {
  final _controller = TextEditingController();
  final _genre = TextEditingController();
  final _tone = TextEditingController();

  String? _presetId = 'solo-ironsworn'; // default selection
  bool _custom = false;
  // Custom-mode working set:
  String? _ruleset; // single-select ruleset id, or null
  final Set<String> _addons = {'juice', 'party'}; // non-ruleset picks
  CampaignMode _mode = CampaignMode.party;

  @override
  void dispose() {
    _controller.dispose();
    _genre.dispose();
    _tone.dispose();
    super.dispose();
  }

  /// The (mode, systems) the Create button will submit.
  (CampaignMode, Set<String>) _resolved() {
    if (_custom) {
      return (_mode, {if (_ruleset != null) _ruleset!, ..._addons});
    }
    final p = kCampaignPresets.firstWhere((p) => p.id == _presetId);
    return presetConfig(p);
  }

  void _submit() {
    final (mode, systems) = _resolved();
    Navigator.of(context).pop((
      name: _controller.text,
      systems: systems,
      mode: mode,
      genre: _genre.text.trim(),
      tone: _tone.text.trim(),
    ));
  }
  // build() below
}
```

`build()` body (an `AlertDialog` with a scrolling content column):

```dart
  @override
  Widget build(BuildContext context) {
    final rulesetIds = kSystemCategory.entries
        .where((e) => e.value == SystemCategory.ruleset)
        .map((e) => e.key)
        .toList();
    final addonIds = kSystemCategory.entries
        .where((e) => e.value != SystemCategory.ruleset)
        .map((e) => e.key)
        .toList();

    return AlertDialog(
      title: const Text('New campaign'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              key: const Key('new-campaign-name'),
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Campaign name'),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('new-campaign-genre'),
              controller: _genre,
              decoration: const InputDecoration(
                  labelText: 'Genre (optional)',
                  hintText: 'e.g. grimdark fantasy'),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('new-campaign-tone'),
              controller: _tone,
              decoration: const InputDecoration(
                  labelText: 'Tone (optional)',
                  hintText: 'e.g. tense and dangerous'),
            ),
            const SizedBox(height: 16),
            const Align(
                alignment: Alignment.centerLeft,
                child: Text('Choose a starting point')),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final p in kCampaignPresets)
                ChoiceChip(
                  key: Key('preset-${p.id}'),
                  avatar: Icon(kPresetIcons[p.id], size: 18),
                  label: Text(p.label),
                  selected: !_custom && _presetId == p.id,
                  onSelected: (_) => setState(() {
                    _custom = false;
                    _presetId = p.id;
                  }),
                ),
              ChoiceChip(
                key: const Key('preset-custom'),
                avatar: const Icon(Icons.tune, size: 18),
                label: const Text('Custom'),
                selected: _custom,
                onSelected: (_) => setState(() => _custom = true),
              ),
            ]),
            if (_custom) ...[
              const SizedBox(height: 16),
              const Divider(),
              _customPicker(rulesetIds, addonIds),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Create')),
      ],
    );
  }

  Widget _customPicker(List<String> rulesetIds, List<String> addonIds) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SegmentedButton<CampaignMode>(
        key: const Key('new-campaign-mode'),
        segments: const [
          ButtonSegment(value: CampaignMode.party, label: Text('Party')),
          ButtonSegment(value: CampaignMode.gm, label: Text('GM')),
        ],
        selected: {_mode},
        onSelectionChanged: (s) => setState(() => _mode = s.first),
      ),
      if (_mode == CampaignMode.gm)
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text('GM mode hides party tools & shows Rumors',
              style: TextStyle(fontSize: 11)),
        ),
      const SizedBox(height: 12),
      const Text('Ruleset (pick one)'),
      RadioListTile<String?>(
        key: const Key('ruleset-none'),
        title: const Text('None (system-agnostic)'),
        value: null,
        groupValue: _ruleset,
        onChanged: (v) => setState(() => _ruleset = v),
      ),
      for (final id in rulesetIds)
        RadioListTile<String?>(
          key: Key('ruleset-$id'),
          title: Text(kSystemBlurbs[id]!),
          value: id,
          groupValue: _ruleset,
          onChanged: (v) => setState(() => _ruleset = v),
        ),
      const SizedBox(height: 12),
      for (final cat in const [
        SystemCategory.oracle,
        SystemCategory.exploration,
        SystemCategory.tools
      ]) ...[
        Text(_categoryLabel(cat)),
        for (final id in addonIds.where((i) => kSystemCategory[i] == cat))
          CheckboxListTile(
            key: Key('cat-$id'),
            title: Text(kSystemBlurbs[id]!),
            value: _addons.contains(id),
            onChanged: (v) => setState(() {
              if (v ?? false) {
                _addons.add(id);
              } else {
                _addons.remove(id);
              }
            }),
          ),
      ],
    ]);
  }

  String _categoryLabel(SystemCategory c) {
    switch (c) {
      case SystemCategory.oracle:
        return 'Oracles';
      case SystemCategory.exploration:
        return 'Exploration & maps';
      case SystemCategory.tools:
        return 'Tools';
      case SystemCategory.ruleset:
        return 'Ruleset';
    }
  }
```

Note: `kSystemBlurbs[id]!` is used as the ruleset/addon row title for brevity; if the blurb is long, swap to a short label map later. For P1 the blurb text is acceptable.

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/new_campaign_dialog_test.dart`
Expected: PASS (tests 1, 3, 4, 5). `flutter analyze` clean.

- [ ] **Step 5: Run the full suite (catch caller breakage)**

Run: `flutter test`
Expected: all pass. The dialog's return record is unchanged, so `_HomeShellState` callers and `SessionsNotifier.create` need no edits. If `test/system_profiles_test.dart` fails, STOP — `kAllSystems` was changed by mistake.

- [ ] **Step 6: Commit**

```bash
git add lib/shared/home_shell.dart test/new_campaign_dialog_test.dart
git commit -m "$(cat <<'EOF'
feat(campaign): presets-first NewCampaignDialog + Custom grouped picker

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Regroup _EditSystemsDialog by category

**Files:**
- Modify: `lib/shared/home_shell.dart`

Keep `edit-sys-<id>` keys and the `Set<String>` pop contract (callers + persistence unchanged). Only insert category headers and order rows by category so Edit matches creation's grouping. Edit stays multi-toggle everywhere (advanced).

- [ ] **Step 1: Replace the flat row list with grouped sections**

In `_EditSystemsDialog`'s build, replace the 16 hand-listed `_row(...)` calls (lines ~1002-1017) with a category-driven loop. Keep the existing `_row(id, label)` helper as-is. Insert:

```dart
        for (final cat in SystemCategory.values) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(_editCategoryLabel(cat),
                style: Theme.of(context).textTheme.labelLarge),
          ),
          for (final id in kSystemCategory.entries
              .where((e) => e.value == cat)
              .map((e) => e.key))
            _row(id, kSystemBlurbs[id]!.split('.').first),
        ],
```

Add the helper inside the State class:

```dart
  String _editCategoryLabel(SystemCategory c) {
    switch (c) {
      case SystemCategory.ruleset:
        return 'Ruleset';
      case SystemCategory.oracle:
        return 'Oracles';
      case SystemCategory.exploration:
        return 'Exploration & maps';
      case SystemCategory.tools:
        return 'Tools';
    }
  }
```

Note: `kSystemBlurbs[id]!.split('.').first` gives a short label from the first sentence; if `_row` already took a hardcoded label before, this keeps it terse. If any blurb has no period, `.split('.').first` returns the whole string — acceptable.

- [ ] **Step 2: Run the edit-dialog test (if present) + analyze**

Run: `flutter test test/ 2>&1 | tail -5` and `flutter analyze`
Expected: all pass, clean. There is no dedicated `_EditSystemsDialog` widget test today; the change is render-only and keyed identically (`edit-sys-<id>`), so existing flows stay green. Manually confirm all 16 `edit-sys-*` keys still render by reading the grouped loop (every `kSystemCategory` key is covered).

- [ ] **Step 3: Commit**

```bash
git add lib/shared/home_shell.dart
git commit -m "$(cat <<'EOF'
feat(campaign): group Edit Systems dialog by category

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Full-suite verification + PR

- [ ] **Step 1: Run everything**

```bash
cd .worktrees/campaign-redesign
flutter analyze
flutter test
```
Expected: analyzer clean; all tests pass (including untouched `system_profiles_test.dart`).

- [ ] **Step 2: Update CLAUDE.md**

Add a bullet after the GM/Party mode bullet describing the redesign:

```
- **Campaign creation is presets-first** (`NewCampaignDialog` in
  `lib/shared/home_shell.dart`). The 16 systems are categorized by
  `kSystemCategory` (`SystemCategory {ruleset, oracle, exploration, tools}`,
  models.dart) against the canonical `kKnownSystems`; `kAllSystems` (5 ids)
  is UNCHANGED — it remains the legacy-null fallback, not the creation seed.
  Creation offers `kCampaignPresets` (`lib/engine/campaign_presets.dart`,
  pure: 9 ruleset presets `solo-*` + `oracle` + `gm-toolkit`; `presetConfig`
  resolves a preset to (mode, systems)); a `Custom` chip reveals a grouped
  picker (ruleset = single-select radio, others multi). `_EditSystemsDialog`
  is grouped by the same categories (multi-toggle, advanced). The dialog's
  return record `(name, systems, mode, genre, tone)` is preserved. P2
  (grouped wizard + live preview) is a separate plan. See
  `docs/superpowers/specs/2026-06-24-campaign-creation-redesign-design.md`.
```

Commit:
```bash
git add CLAUDE.md
git commit -m "$(cat <<'EOF'
docs(campaign): note presets-first creation in CLAUDE.md

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 3: Open the PR** (via github-steward or `gh`), title
`feat(campaign): presets-first campaign creation (P1)`, against `main`. Include a
test-plan checklist (full suite green; manual: create via each preset, Custom picker
single-select ruleset, GM toolkit lands on Track, edit-systems grouped).

---

## P2 — grouped wizard + live preview (separate follow-up plan)

**Do not implement in this plan.** After P1 merges, write a second plan
(`docs/superpowers/plans/2026-06-25-campaign-wizard.md`) covering:

- `lib/features/campaign_setup/` — a stepped wizard widget that reuses
  `kCampaignPresets` + `kSystemCategory`: step 1 name + ruleset cards, step 2
  add-ons by category with an embedded live-preview pane, step 3 mode
  (auto-suggested from ruleset, with the dead-combo hint) → Create.
- **Live preview** must reuse the real gating predicates. Before P2, extract a
  shared pure helper (e.g. `surfacesFor(mode, systems)` in `lib/engine/`) that
  both the wizard preview and a test can call, derived from the same logic the
  shell/`role_tags`/tool registry use — so the preview cannot drift from runtime.
- Presets remain the step-0 fast path; `Custom`/the wizard share the grouped
  picker from P1.
- Mode auto-suggest: ruleset chosen → Party; GM toolkit → GM; surfaced as a
  default the user can override.

P2 is deferred because its exact widget shape depends on P1 landing, and the
live-preview helper extraction is a meaningful sub-task of its own.

---

## Self-Review

**Spec coverage:**
- Category model (`kSystemCategory`, completeness test) → Task 1 ✓
- `CampaignPreset` + `presetConfig` + lean preset set → Task 2 ✓
- Presets-first `NewCampaignDialog` + Custom grouped picker (ruleset radio, others multi) → Task 3 ✓
- Mode auto-suggest (preset sets mode; Custom shows mode + dead-combo hint) → Task 3 ✓
- Grouped `_EditSystemsDialog` → Task 4 ✓
- `kAllSystems` consumer audit → resolved: leave `kAllSystems` untouched (it is the fallback, not the seed); `system_profiles_test` stays green (Task 3 Step 5, Task 5 Step 1) ✓
- P2 wizard + live preview → deferred to separate plan, with the preview-drift risk addressed by the shared-helper note ✓

**Placeholder scan:** Task 3 Step 1 contains one intentional stub test ("default preset … re-open pattern") that Step 1's prose explicitly says to delete — keep tests 1, 3, 4, 5. No other placeholders.

**Type consistency:**
- `presetConfig` returns `(CampaignMode, Set<String>)` — used identically in Task 2 test, Task 3 `_resolved()`. ✓
- `SystemCategory` enum values `{ruleset, oracle, exploration, tools}` consistent across Tasks 1, 3, 4. ✓
- Dialog return record `({name, systems, mode, genre, tone})` matches the existing contract (no caller change). ✓
- `kKnownSystems` (16) vs `kAllSystems` (5) kept distinct everywhere. ✓
- New keys (`preset-<id>`, `preset-custom`, `ruleset-<id>`, `ruleset-none`, `cat-<id>`) used consistently between Task 3 tests and implementation. ✓
