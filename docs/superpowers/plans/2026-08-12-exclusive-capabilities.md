# Single-Select Capabilities (PR 2 of streamline epic) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Where multiple enabled tools do the same job, the player picks ONE: verdant-vs-hexcrawl becomes an exclusive pair, the party subtab shows one chosen paradigm, and the dungeon pane never stacks two generators.

**Architecture:** Pure `kExclusiveGroups` + `normalizeExclusive` over the existing `Set<String> systems` (no model migration); one new per-campaign field `SessionMeta.partyTool`; radio ChoiceChips in the wizard + edit-systems dialog; two one-line UI gates in map_screen.

**Tech Stack:** Flutter + flutter_riverpod (existing rails only). Package name is `loreseer` (imports `package:loreseer/...`).

**Spec:** `docs/superpowers/specs/2026-08-12-streamline-library-exclusive-capabilities-design.md` (Part 2)

## Global Constraints

- Gates stay tolerant: a legacy campaign with BOTH verdant + hexcrawl enabled keeps working; normalization happens only when the edit-systems dialog saves (keep the FIRST group member by group order, drop the rest) and on wizard create (defensive).
- `SessionMeta.partyTool` values: `'emulator' | 'behavior' | 'sidekick'`; default `'emulator'`; JSON key `partyTool`, omitted at default (null); tolerant parse.
- Persisted state of unchosen party panes is untouched — switching back restores it.
- Existing test keys `cat-verdant`, `cat-hexcrawl`, `edit-sys-verdant`, `edit-sys-hexcrawl` stay on the new ChoiceChips (semantics change checkbox→radio; keys don't).
- Format only files you edit (`dart format <file>`), never repo-wide.
- Widget tests must NOT pump HomeShell/JournalScreen without the repo's asset-provider overrides (rootBundle hang); pump dialogs/panes directly and override `emulatorDataProvider`-style asset providers with fixtures where a pane loads assets (copy the setup of that pane's existing test file).

---

### Task 1: Engine + model (exclusive groups, partyTool field/setter/provider)

**Files:**
- Modify: `lib/engine/campaign_surfaces.dart` (append at end)
- Modify: `lib/engine/models/session.dart` (`SessionMeta` ~lines 292–362)
- Modify: `lib/state/providers.dart` (`SessionsNotifier` after `setDndEdition` ~line 2785; provider next to `dndEditionProvider` ~line 3188)
- Test: `test/exclusive_groups_test.dart`, `test/party_tool_test.dart`

**Interfaces:**
- Consumes: `SessionMeta`/`SessionsState` (session.dart), `sessionsProvider`, `_save` (SessionsNotifier private persist — same as `setDndEdition`).
- Produces (used by Tasks 2–4):
  - `const Map<String, List<String>> kExclusiveGroups` = `{'hex-flavor': ['verdant', 'hexcrawl']}`
  - `Set<String> normalizeExclusive(Set<String> systems)`
  - `Set<String> kExclusiveSystemIds` (flattened members, for the dialogs to exclude from checkbox/filter loops)
  - `SessionMeta.partyTool` (`String?` field; `enabledPartyTool` getter → `partyTool ?? 'emulator'`)
  - `SessionsNotifier.setPartyTool(String id, String tool)`
  - `final partyToolProvider = Provider<String>(...)` (active campaign's, default `'emulator'`)

- [ ] **Step 1: Write the failing tests**

```dart
// test/exclusive_groups_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:loreseer/engine/campaign_surfaces.dart';

void main() {
  test('normalizeExclusive keeps the first member by group order', () {
    expect(normalizeExclusive({'juice', 'verdant', 'hexcrawl'}),
        {'juice', 'verdant'});
    expect(normalizeExclusive({'hexcrawl'}), {'hexcrawl'});
    expect(normalizeExclusive({'juice', 'party'}), {'juice', 'party'});
    expect(normalizeExclusive(const {}), isEmpty);
  });

  test('kExclusiveSystemIds flattens group members', () {
    expect(kExclusiveSystemIds, containsAll(['verdant', 'hexcrawl']));
  });
}
```

```dart
// test/party_tool_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loreseer/engine/models.dart';
import 'package:loreseer/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('partyTool round-trips through JSON, omitted at default', () {
    const m = SessionMeta(id: 's1', name: 'A');
    expect(m.toJson().containsKey('partyTool'), isFalse);
    expect(m.enabledPartyTool, 'emulator');
    final m2 = SessionMeta.fromJson(
        {'id': 's1', 'name': 'A', 'partyTool': 'sidekick'});
    expect(m2.enabledPartyTool, 'sidekick');
    expect(m2.toJson()['partyTool'], 'sidekick');
  });

  test('setPartyTool persists and partyToolProvider reflects it', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final sessions = await container.read(sessionsProvider.future);
    expect(container.read(partyToolProvider), 'emulator');
    await container
        .read(sessionsProvider.notifier)
        .setPartyTool(sessions.active, 'behavior');
    expect(container.read(partyToolProvider), 'behavior');
  });
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/exclusive_groups_test.dart test/party_tool_test.dart`
Expected: FAIL — symbols undefined.

- [ ] **Step 3: Implement**

Append to `lib/engine/campaign_surfaces.dart`:

```dart
/// Capability groups where enabling more than one member stacks overlapping
/// UI for the same job. The dialogs render each group as a radio row, and
/// [normalizeExclusive] resolves a both-on legacy set by keeping the FIRST
/// member listed here. Gates elsewhere stay tolerant of both-on sets.
const Map<String, List<String>> kExclusiveGroups = {
  'hex-flavor': ['verdant', 'hexcrawl'],
};

/// Every system id that belongs to some exclusive group — the dialogs skip
/// these in their plain checkbox/filter loops.
final Set<String> kExclusiveSystemIds =
    kExclusiveGroups.values.expand((m) => m).toSet();

/// Keeps at most one member per exclusive group (the first listed), leaving
/// everything else untouched.
Set<String> normalizeExclusive(Set<String> systems) {
  final out = {...systems};
  for (final members in kExclusiveGroups.values) {
    final present = members.where(out.contains).toList();
    for (final id in present.skip(1)) {
      out.remove(id);
    }
    // Order comes from the group list, not the set: keep the first-listed.
    if (present.length > 1) {
      out.removeAll(present);
      out.add(present.first);
    }
  }
  return out;
}
```

(Note the two loops above are redundant as written — implement it as ONE pass: compute `present`; if `present.length > 1`, `out.removeAll(present)` then `out.add(present.first)`. The test pins the behavior.)

`lib/engine/models/session.dart` — `SessionMeta` gains a field mirroring `dndEdition` exactly: constructor param `this.partyTool`, `final String? partyTool;` with doc `/// Which party-tools paradigm the Track subtab shows ('emulator' | 'behavior' | 'sidekick'); null → emulator.`, getter `String get enabledPartyTool => partyTool ?? 'emulator';`, `toJson`: `if (partyTool != null) 'partyTool': partyTool,`, `copyWith` param + pass-through, `fromJson`: `partyTool: j['partyTool'] as String?,`.

`lib/state/providers.dart` — after `setDndEdition` (~line 2785):

```dart
  /// Set which party-tools paradigm session [id] shows
  /// ('emulator' | 'behavior' | 'sidekick').
  Future<void> setPartyTool(String id, String tool) async {
    final s = state.valueOrNull;
    if (s == null) return;
    final updated = [
      for (final m in s.sessions)
        if (m.id == id) m.copyWith(partyTool: tool) else m,
    ];
    await _save(SessionsState(active: s.active, sessions: updated));
  }
```

Next to `dndEditionProvider` (~line 3188):

```dart
/// Active campaign's party-tools paradigm; default 'emulator'.
final partyToolProvider = Provider<String>((ref) =>
    ref.watch(sessionsProvider).valueOrNull?.activeMeta.enabledPartyTool ??
    'emulator');
```

- [ ] **Step 4: Run to verify they pass**

Run: `flutter test test/exclusive_groups_test.dart test/party_tool_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/campaign_surfaces.dart lib/engine/models/session.dart lib/state/providers.dart test/exclusive_groups_test.dart test/party_tool_test.dart
git commit -m "feat(systems): exclusive capability groups + per-campaign partyTool"
```

---

### Task 2: Wizard — exclusive radio row + party-tool row

**Files:**
- Modify: `lib/shared/home_shell.dart` (`NewCampaignResult` typedef ~line 1241; `_NewCampaignDialogState` ~1265–1341; `_buildStep1` addon loop ~1520–1552; `_createSession` ~302) and `lib/features/launcher_screen.dart` (`_new`, the second `NewCampaignDialog` call site ~line 96 — it consumes the same result record; wire `setPartyTool` the same way)
- Test: `test/campaign_wizard_exclusive_test.dart`

**Interfaces:**
- Consumes: `kExclusiveGroups` / `kExclusiveSystemIds` / `normalizeExclusive` (Task 1), `SessionsNotifier.setPartyTool` (Task 1), existing wizard state (`_addons`, `_systems`, `_submit`).
- Produces: `NewCampaignResult` gains `String partyTool`; keys `hexflavor-none`, `party-tool-emulator|behavior|sidekick` (wizard); `cat-verdant`/`cat-hexcrawl` become ChoiceChips (same keys).

- [ ] **Step 1: Write the failing test**

Model the pump on the existing wizard test (find it: `grep -rln "wizard-next\|ruleset-none" test/ | head`, copy its scaffolding — it pumps `NewCampaignDialog` directly and walks steps). Then add:

```dart
// test/campaign_wizard_exclusive_test.dart — scenarios:
// 1. Step 1 shows a 'Hexcrawl flavor' ChoiceChip row: hexflavor-none selected
//    by default; cat-verdant + cat-hexcrawl present as radio chips.
// 2. Tap cat-verdant then cat-hexcrawl → resulting created systems contain
//    'hexcrawl' and NOT 'verdant' (radio, not additive). Assert via the
//    popped NewCampaignResult (pump the dialog with a Navigator and capture
//    the result like the existing wizard test does).
// 3. With the 'party' addon on (default), a 'Party tool' ChoiceChip row shows
//    party-tool-emulator selected; tapping party-tool-sidekick makes the
//    popped result carry partyTool == 'sidekick'. Turning the party addon OFF
//    hides the row and the result carries partyTool == 'emulator'.
```

Write real tests for all three.

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/campaign_wizard_exclusive_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement**

(a) `_NewCampaignDialogState`: add `String _partyTool = 'emulator';`. In `_buildStep1`'s per-category chip Wrap (~line 1539), skip exclusive members in the FilterChip loop:

```dart
            for (final id in addonIds.where((i) =>
                kSystemCategory[i] == cat && !kExclusiveSystemIds.contains(i)))
```

Directly after that Wrap, still inside the `for (final cat ...)` block, render each group whose members live in this category (today: hex-flavor under exploration):

```dart
          if (cat == SystemCategory.exploration) ...[
            const SizedBox(height: 6),
            const Text('Hexcrawl flavor (pick one)',
                style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 6, children: [
              ChoiceChip(
                key: const Key('hexflavor-none'),
                label: const Text('None'),
                selected: !kExclusiveGroups['hex-flavor']!
                    .any(_addons.contains),
                onSelected: (_) => setState(() =>
                    _addons.removeAll(kExclusiveGroups['hex-flavor']!)),
              ),
              for (final id in kExclusiveGroups['hex-flavor']!)
                ChoiceChip(
                  key: Key('cat-$id'),
                  label: Text(kSystemShortName[id] ?? id),
                  selected: _addons.contains(id),
                  onSelected: (_) => setState(() {
                    _addons.removeAll(kExclusiveGroups['hex-flavor']!);
                    _addons.add(id);
                  }),
                ),
            ]),
          ],
          if (cat == SystemCategory.tools && _addons.contains('party')) ...[
            const SizedBox(height: 6),
            const Text('Party tool (pick one)',
                style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final t in const [
                ('emulator', 'Emulator'),
                ('behavior', 'Behavior'),
                ('sidekick', 'Sidekick'),
              ])
                ChoiceChip(
                  key: Key('party-tool-${t.$1}'),
                  label: Text(t.$2),
                  selected: _partyTool == t.$1,
                  onSelected: (_) => setState(() => _partyTool = t.$1),
                ),
            ]),
          ],
```

(b) `NewCampaignResult` gains `String partyTool`; `_submit` wraps systems defensively and carries the tool:

```dart
    Navigator.of(context).pop((
      name: _nameCtrl.text,
      systems: normalizeExclusive(systemsForSubmit),
      ...
      partyTool: _partyTool,
    ));
```

(c) Both create call sites (`home_shell._createSession` after `setDefaultOracle`, `launcher_screen._new` same spot) add:

```dart
    if (result.partyTool != 'emulator') {
      final active = ref.read(sessionsProvider).valueOrNull?.active;
      if (active != null) {
        await ref
            .read(sessionsProvider.notifier)
            .setPartyTool(active, result.partyTool);
      }
    }
```

Add `import` for `campaign_surfaces.dart` where missing.

- [ ] **Step 4: Run tests**

Run: `flutter test test/campaign_wizard_exclusive_test.dart $(grep -rln "wizard-next" test/ | tr '\n' ' ')`
Expected: PASS (new + existing wizard tests).

- [ ] **Step 5: Format + commit**

```bash
dart format lib/shared/home_shell.dart lib/features/launcher_screen.dart
git add -A lib test/campaign_wizard_exclusive_test.dart
git commit -m "feat(wizard): hexcrawl-flavor radio + party-tool choice"
```

---

### Task 3: Edit-systems dialog — radio row, normalization on save, party-tool switcher

**Files:**
- Modify: `lib/shared/home_shell.dart` (`_EditSystemsDialog` ~1855–1930; caller `_editSystems` ~326–334)
- Test: `test/edit_systems_exclusive_test.dart`

**Interfaces:**
- Consumes: Task 1 symbols; `SessionsNotifier.editSystems` + `setPartyTool`.
- Produces: `_EditSystemsDialog` returns `({Set<String> systems, String partyTool})`; takes `initial` + `initialPartyTool`. Keys: `edit-sys-verdant`/`edit-sys-hexcrawl` (now ChoiceChips), `edit-hexflavor-none`, `edit-party-tool-<id>`.

- [ ] **Step 1: Write the failing test**

Model on the existing edit-systems test (find: `grep -rln "edit-sys-" test/ | head`). Scenarios (write real tests):

```dart
// 1. Dialog seeded with {'juice','verdant','hexcrawl'} (legacy both-on):
//    saving without touching anything returns systems containing 'verdant'
//    but NOT 'hexcrawl' (normalizeExclusive keeps first by group order).
// 2. Tapping edit-sys-hexcrawl then Save → 'hexcrawl' in, 'verdant' out.
//    Tapping edit-hexflavor-none then Save → neither.
// 3. Seeded with party enabled + initialPartyTool 'emulator': an
//    edit-party-tool-behavior chip exists; tapping it and saving returns
//    partyTool == 'behavior'. Without 'party' in the picked set, the row is
//    hidden and partyTool returns unchanged.
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/edit_systems_exclusive_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement**

`_EditSystemsDialog`: add `final String initialPartyTool;` (constructor `this.initialPartyTool = 'emulator'`). State: `late String _partyTool = widget.initialPartyTool;`. In the category loop, exclude exclusive members from the checkbox rows:

```dart
              for (final id in kSystemCategory.entries
                  .where((e) =>
                      e.value == cat && !kExclusiveSystemIds.contains(e.key))
                  .map((e) => e.key))
                _row(id, kSystemShortName[id] ?? id),
```

After the exploration category's rows, add the radio row (same chip pattern as the wizard, keys `edit-sys-<id>` + `edit-hexflavor-none`, mutating `_picked`). After the tools category's rows, when `_picked.contains('party')`, add the party-tool row (keys `edit-party-tool-<id>`, mutating `_partyTool`).

Save action pops the record with normalization:

```dart
        FilledButton(
          onPressed: () => Navigator.of(context)
              .pop((systems: normalizeExclusive(_picked), partyTool: _partyTool)),
          child: const Text('Save'),
        ),
```

Caller `_editSystems`:

```dart
    final picked = await showDialog<({Set<String> systems, String partyTool})>(
      context: dialogContext,
      builder: (context) => _EditSystemsDialog(
          initial: meta.enabledSystems,
          initialPartyTool: meta.enabledPartyTool),
    );
    if (picked == null) return;
    await ref
        .read(sessionsProvider.notifier)
        .editSystems(meta.id, picked.systems);
    if (picked.partyTool != meta.enabledPartyTool) {
      await ref
          .read(sessionsProvider.notifier)
          .setPartyTool(meta.id, picked.partyTool);
    }
```

- [ ] **Step 4: Run tests**

Run: `flutter test test/edit_systems_exclusive_test.dart $(grep -rln "edit-sys-" test/ | tr '\n' ' ')`
Expected: PASS.

- [ ] **Step 5: Format + commit**

```bash
dart format lib/shared/home_shell.dart
git add lib/shared/home_shell.dart test/edit_systems_exclusive_test.dart
git commit -m "feat(systems): edit dialog radio groups + normalization + party-tool switcher"
```

---

### Task 4: Party pane renders only the chosen paradigm

**Files:**
- Modify: `lib/features/party_tools_pane.dart` (whole file — it is 60 lines)
- Test: `test/party_tools_pane_test.dart` (new or extend existing — check `grep -rln "party-tools-switch" test/`)

**Interfaces:**
- Consumes: `partyToolProvider` (Task 1).
- Produces: `PartyToolsPane` (ConsumerWidget) rendering exactly one of `PartyEmulatorScreen` / `BehaviorTablesScreen` / `SidekickScreen`; the `party-tools-switch` SegmentedButton and `initial` param are REMOVED (check its call site: `grep -rn "PartyToolsPane(" lib/` — update any `initial:` usage; the subtab host likely constructs it bare).

- [ ] **Step 1: Write the failing test**

Override whatever asset providers the three screens load (copy the setup from the existing party/emulator test file — find via `grep -rln "PartyEmulator\|emulatorData" test/ | head`; repo rule: never let a widget test hit rootBundle). Scenarios:

```dart
// 1. partyTool 'emulator' (default, empty prefs) → PartyEmulatorScreen
//    present; BehaviorTablesScreen + SidekickScreen absent;
//    party-tools-switch key absent.
// 2. prefs seeded with sessions registry carrying partyTool 'sidekick'
//    (or override partyToolProvider directly with Provider((_) => 'sidekick'))
//    → only SidekickScreen present.
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/party_tools_pane_test.dart`
Expected: FAIL (switch still present / wrong child).

- [ ] **Step 3: Implement**

```dart
// lib/features/party_tools_pane.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import 'behavior_tables_screen.dart';
import 'party_emulator_screen.dart';
import 'sidekick_screen.dart';

/// The Track party subtab shows ONE party-tools paradigm — Emulator,
/// Behavior, or Sidekick — chosen per campaign (SessionMeta.partyTool, set
/// in the creation wizard or Campaigns → Edit systems). The old in-pane
/// SegmentedButton stacked all three behind a switch; the paradigms answer
/// the same question, so the choice is campaign config, not pane state.
/// Unchosen paradigms keep their persisted state for a later switch back.
class PartyToolsPane extends ConsumerWidget {
  const PartyToolsPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (ref.watch(partyToolProvider)) {
      'behavior' => const BehaviorTablesScreen(),
      'sidekick' => const SidekickScreen(),
      _ => const PartyEmulatorScreen(),
    };
  }
}
```

Fix any call site passing `initial:` (grep first; adjust or drop the arg).

- [ ] **Step 4: Run tests**

Run: `flutter test test/party_tools_pane_test.dart $(grep -rln "party-tools\|PartyToolsPane" test/ | tr '\n' ' ')`
Expected: PASS.

- [ ] **Step 5: Format + commit**

```bash
dart format lib/features/party_tools_pane.dart
git add -A lib/features test/party_tools_pane_test.dart
git commit -m "feat(party): subtab renders the one chosen party tool"
```

---

### Task 5: Dungeon pane — one generator at a time

**Files:**
- Modify: `lib/features/map_screen.dart` (line ~593: `if (_hexcrawlOn()) _hexcrawlDungeonControls(context)` in the Dungeon pane's `_tools`)
- Test: extend the existing dungeon-pane widget test (find: `grep -rln "classic-enter\|hexcrawl-new-room" test/ | head`)

**Interfaces:**
- Consumes: existing private `_hexcrawlOn()` / `_classicOn()` in the same State.
- Produces: no new symbols — a gate change only.

- [ ] **Step 1: Write the failing test**

In the existing dungeon-pane test file (reuse its pump + provider-override scaffolding; remember tests must tap `map-tools-toggle` before reaching folded tools):

```dart
// classic-dungeon AND hexcrawl both enabled → after opening map-tools-toggle,
// hexcrawl-new-room and hexcrawl-generate-dungeon are ABSENT (classic owns
// dungeon generation); with hexcrawl on and classic OFF, both remain present.
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test <that test file>`
Expected: new case FAILS (controls currently render under classic).

- [ ] **Step 3: Implement**

```dart
        // One dungeon generator at a time: when the classic (Roll 4 Ruin)
        // crawler owns this pane, the hexcrawl toolkit's room/dungeon
        // generation folds away instead of stacking a second generator.
        if (_hexcrawlOn() && !_classicOn()) _hexcrawlDungeonControls(context),
```

- [ ] **Step 4: Run tests**

Run: `flutter test <that test file>`
Expected: PASS (new + existing cases).

- [ ] **Step 5: Format + commit**

```bash
dart format lib/features/map_screen.dart
git add lib/features/map_screen.dart test/
git commit -m "fix(map): classic dungeon hides hexcrawl generation controls"
```

---

### Task 6: Full verify + docs

**Files:**
- Modify: `CLAUDE.md` (one bullet under Project notes)

- [ ] **Step 1: Analyze + full suite**

Run: `flutter analyze && flutter test`
Expected: clean + green. Attribute any failure ONLY from the final "Failing tests:" block (never `+P -F:` lines); treat failures as this branch's until proven otherwise.

- [ ] **Step 2: CLAUDE.md note**

```markdown
- **Single-select capabilities (2026-08-12, PR 2 of the streamline epic)** —
  overlapping tools are radio choices, not stacking toggles. Pure
  `kExclusiveGroups` (`{'hex-flavor': [verdant, hexcrawl]}`) +
  `normalizeExclusive` + `kExclusiveSystemIds` in `campaign_surfaces.dart`;
  the wizard + `_EditSystemsDialog` render group members as ChoiceChips
  (keys unchanged, `hexflavor-none`/`edit-hexflavor-none` for None) and
  normalization runs on wizard create + edit-dialog save ONLY (gates stay
  tolerant of legacy both-on sets). `SessionMeta.partyTool`
  ('emulator'|'behavior'|'sidekick', JSON omitted at default;
  `enabledPartyTool`, `setPartyTool`, `partyToolProvider`) picks the ONE
  party surface `PartyToolsPane` renders (SegmentedButton retired; the
  wizard's `party-tool-<id>` row + the edit dialog's `edit-party-tool-<id>`
  row switch it). The Dungeon pane shows one generator at a time
  (`_hexcrawlDungeonControls` hidden while classic-dungeon is on). See
  `docs/superpowers/specs/2026-08-12-streamline-library-exclusive-capabilities-design.md`.
```

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: single-select capabilities project note"
```
