# Combat Merge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One `EncounterPane` widget renders combat everywhere — full manager on Track → Encounter, compact glance on the Run dashboard; the duplicate `_InitiativePanel` is deleted.

**Architecture:** Pure widget-level merge, no model or persistence change. Task 1 extracts today's `EncounterScreen` body into `EncounterPane` (full mode, zero behavior change). Task 2 adds the compact branch (glance rows + next-turn/roll-all + open-full link, `run-init-*` keys). Task 3 deletes `_InitiativePanel` and mounts `EncounterPane(compact: true)` in the Run dashboard slot.

**Tech Stack:** Flutter + flutter_riverpod. Tests: `flutter test`, `flutter analyze`.

**Spec:** `docs/superpowers/specs/2026-08-22-combat-merge-design.md`

## Global Constraints

- No model or persistence change anywhere in the diff.
- Full mode is a pure extraction: every existing `enc-*`, `add-*`, `next-turn`, `end-encounter` key and behavior unchanged; existing encounter tests must pass untouched.
- Compact mode emits keys `run-init-row-<id>`, `run-init-next`, `run-init-roll-all`, `run-init-empty`, plus new `run-init-open-full`; it shows NO manager affordances (no HP steppers, condition/tag editors, attack chips, stat-block/init editors, add flows, end-encounter).
- Colors from existing token usage; no new `Theme.of(context).colorScheme` references (design ratchet).
- The pane brings no `Card` surface in compact mode — Run's `_Panel` supplies chrome.
- Package prefix in tests: `package:loreseer/...`. A hook auto-runs `dart format` on every `.dart` edit. Format only files you edit.
- Each task ends with the named tests green + `flutter analyze` clean on touched files, then a commit.

---

### Task 1: Extract `EncounterPane` (full mode, pure move)

**Files:**
- Modify: `lib/features/encounter_screen.dart:16-40`
- Test: existing `test/encounter_attack_test.dart` (no edits — it must stay green)

**Interfaces:**
- Produces: `class EncounterPane extends ConsumerWidget` with `const EncounterPane({super.key, this.compact = false}); final bool compact;`. Full mode renders exactly what `EncounterScreen.build` renders today (`Column[_header, list/_empty, _addButtons]` under the same `async.when`). `EncounterScreen` becomes `class EncounterScreen extends StatelessWidget { build => const EncounterPane(); }`.
- Consumes: nothing new.

- [ ] **Step 1: Restructure the widget**

In `lib/features/encounter_screen.dart`:

1. Rename the existing `class EncounterScreen extends ConsumerWidget` to `class EncounterPane extends ConsumerWidget` — its `build` and ALL its helper methods (`_header`, `_empty`, `_list`, `_attack`, `_addButtons`, `_addFromBestiary`, `_endEncounter`, `_addTag`, `_addFromCharacters`, `_generateMonster`, `_addAdHoc`, `_editStatBlock`, `_saveToBestiary`, `_editInit`, `_addFromFoes`, `_addFromSystemCreatures`, `_addFromReference`) move with it verbatim. Private dialog classes in the file are untouched.
2. Give it the constructor and field:

```dart
/// The one combat surface. Full mode (default) is the Track → Encounter
/// manager; [compact] renders the Run dashboard glance (Task 2).
class EncounterPane extends ConsumerWidget {
  const EncounterPane({super.key, this.compact = false});

  /// Compact = read-and-act glance: rows + next turn + roll-all only.
  final bool compact;
```

3. Add a new thin Track mount at the top of the file:

```dart
/// Track → Encounter mount. All rendering lives in [EncounterPane].
class EncounterScreen extends StatelessWidget {
  const EncounterScreen({super.key});

  @override
  Widget build(BuildContext context) => const EncounterPane();
}
```

No other line changes — this is a rename plus a wrapper. `compact` is declared but not yet read (that is Task 2); if the analyzer flags the unused field, reference it trivially only if required — it will not, fields are not flagged.

- [ ] **Step 2: Verify pure extraction**

Run: `flutter test test/encounter_attack_test.dart && flutter analyze lib/features/encounter_screen.dart`
Expected: PASS with zero test edits, analyzer clean. Then run the wider encounter coverage: `flutter test test/encounter_screen_test.dart` if that file exists (`ls test | grep encounter` first); every existing encounter test file must pass unedited.

- [ ] **Step 3: Commit**

```bash
git add lib/features/encounter_screen.dart
git commit -m "refactor(encounter): extract EncounterPane; EncounterScreen is a thin mount"
```

---

### Task 2: Compact mode

**Files:**
- Modify: `lib/features/encounter_screen.dart` (the `EncounterPane.build` + one new private helper)
- Test: `test/encounter_pane_compact_test.dart` (create)

**Interfaces:**
- Consumes: `EncounterPane.compact` from Task 1; `encounterProvider`, `EncounterNotifier.nextTurn()/rollInitiativeForAll()`, `StatBlockView` (from `sheet_widgets.dart`, already imported), `shellRouteProvider` + `Destination` (import `../shared/shell_route.dart` / `../shared/destination.dart` as the file's existing imports allow — check what `run_screen.dart` imports for `shellRouteProvider` and mirror it).
- Produces: compact rendering under keys `run-init-row-<id>`, `run-init-next`, `run-init-roll-all`, `run-init-empty`, `run-init-open-full`. Task 3 mounts it.

- [ ] **Step 1: Write the failing test**

Create `test/encounter_pane_compact_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loreseer/engine/models.dart';
import 'package:loreseer/features/encounter_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  void seed(List<Map<String, dynamic>> combatants) {
    SharedPreferences.setMockInitialValues({
      'loreseer.encounter.v1.default': jsonEncode({
        'round': 2,
        'turnIndex': 0,
        'combatants': combatants,
      }),
      'loreseer.sessions.v1': jsonEncode({
        'active': 'default',
        'sessions': [
          {'id': 'default', 'name': 'Campaign 1'}
        ],
      }),
    });
  }

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(
            home: Scaffold(body: EncounterPane(compact: true)))));
    await tester.pumpAndSettle();
  }

  testWidgets('compact renders glance rows and actions, no manager UI',
      (tester) async {
    seed([
      {
        'id': 'g1',
        'name': 'Goblin',
        'initiative': 12,
        'track': {'current': 4, 'max': 7},
      },
    ]);
    await pump(tester);

    expect(find.byKey(const Key('run-init-row-g1')), findsOneWidget);
    expect(find.text('Goblin'), findsOneWidget);
    expect(find.text('4/7'), findsOneWidget);
    expect(find.byKey(const Key('run-init-next')), findsOneWidget);
    expect(find.byKey(const Key('run-init-roll-all')), findsOneWidget);
    expect(find.byKey(const Key('run-init-open-full')), findsOneWidget);

    // Manager affordances absent in compact mode.
    expect(find.byKey(const Key('enc-attack-g1')), findsNothing);
    expect(find.byKey(const Key('enc-minus-0')), findsNothing);
    expect(find.byKey(const Key('enc-statblock-g1')), findsNothing);
    expect(find.byKey(const Key('add-adhoc')), findsNothing);
    expect(find.byKey(const Key('end-encounter')), findsNothing);
  });

  testWidgets('compact empty state', (tester) async {
    seed([]);
    await pump(tester);
    expect(find.byKey(const Key('run-init-empty')), findsOneWidget);
  });
}
```

Adjust the seeded combatant JSON to `Combatant.fromJson`'s real field names first — read `Combatant.toJson`/`fromJson` in `lib/engine/models.dart` (or its part files) and use those exact keys; if hand-writing JSON is brittle, build `Combatant` objects and `jsonEncode(EncounterState(...).toJson())` instead.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/encounter_pane_compact_test.dart`
Expected: FAIL — compact flag ignored, full manager renders (`enc-*` keys found / `run-init-*` missing).

- [ ] **Step 3: Implement the compact branch**

In `EncounterPane.build`, inside the `data:` case, branch first:

```dart
      data: (s) => compact
          ? _compact(context, ref, s)
          : Column(
              children: [
                _header(context, ref, s),
                ...
```

Add the helper (adapted from the deleted-in-Task-3 `_InitiativePanel`, so Run behavior is preserved):

```dart
  /// Run-dashboard glance: rows + next-turn/roll-all + open-full link.
  /// Emits the historical run-init-* keys so Run tests and muscle memory
  /// survive the merge. No Card surface — the host panel supplies chrome.
  Widget _compact(BuildContext context, WidgetRef ref, EncounterState s) {
    final theme = Theme.of(context);
    final notifier = ref.read(encounterProvider.notifier);
    final rows = <Widget>[];
    for (var i = 0; i < s.combatants.length; i++) {
      final c = s.combatants[i];
      final current = i == s.turnIndex;
      rows.add(InkWell(
        key: Key('run-init-row-${c.id}'),
        onTap: (c.statBlock != null && !c.statBlock!.isEmpty)
            ? () => _showCompactStatBlock(context, c)
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: current
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.surfaceContainerHighest,
              child:
                  Text('${c.initiative}', style: theme.textTheme.labelMedium),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(c.name,
                  style: c.defeated
                      ? const TextStyle(decoration: TextDecoration.lineThrough)
                      : (current
                          ? TextStyle(color: theme.colorScheme.primary)
                          : null)),
            ),
            if (c.track != null)
              Text('${c.track!.current}/${c.track!.max}',
                  style: theme.textTheme.bodySmall),
          ]),
        ),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (s.combatants.isEmpty)
          Text('No encounter yet.',
              key: const Key('run-init-empty'),
              style: TextStyle(color: Theme.of(context).colorScheme.outline))
        else
          ...rows,
        const SizedBox(height: 8),
        Row(children: [
          Flexible(
            child: FilledButton.tonal(
              key: const Key('run-init-next'),
              onPressed:
                  s.combatants.isEmpty ? null : () => notifier.nextTurn(),
              child: const Text('Next turn'),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: OutlinedButton(
              key: const Key('run-init-roll-all'),
              onPressed: s.combatants.isEmpty
                  ? null
                  : () => notifier.rollInitiativeForAll(),
              child: const Text('Roll all init'),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: TextButton(
              key: const Key('run-init-open-full'),
              onPressed: () => ref
                  .read(shellRouteProvider.notifier)
                  .goTo(Destination.track, subtab: 'encounter'),
              child: const Text('Open encounter'),
            ),
          ),
        ]),
      ],
    );
  }

  void _showCompactStatBlock(BuildContext context, Combatant c) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(c.name),
        content: SingleChildScrollView(
          child: StatBlockView(
            block: c.statBlock!,
            curHp: c.track?.current,
            maxHp: c.track?.max,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
```

Notes:
- The `theme.colorScheme.*` references above are MOVED from the old `_InitiativePanel`, not new design-language choices; the design-ratchet test counts files, and `encounter_screen.dart` already uses `colorScheme` (verify with `grep -c colorScheme lib/features/encounter_screen.dart` — nonzero today). If the ratchet test still fails, STOP and report DONE_WITH_CONCERNS rather than restyling.
- Add the imports the helper needs (`shellRouteProvider`, `Destination`) by mirroring `run_screen.dart`'s import lines for those symbols.
- The `Flexible`-wrapped buttons follow the repo's loose-constraints gotcha — keep them `Flexible`, never bare.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/encounter_pane_compact_test.dart test/encounter_attack_test.dart && flutter analyze lib/features/encounter_screen.dart`
Expected: PASS; full-mode tests still untouched and green.

- [ ] **Step 5: Commit**

```bash
git add lib/features/encounter_screen.dart test/encounter_pane_compact_test.dart
git commit -m "feat(encounter): compact glance mode on EncounterPane"
```

---

### Task 3: Run wiring — delete `_InitiativePanel`

**Files:**
- Modify: `lib/features/run_screen.dart:43` (construction) and `:169-273` (delete `_InitiativePanel`)
- Test: `test/run_screen_test.dart` (should need no or minimal edits — verify)

**Interfaces:**
- Consumes: `EncounterPane(compact: true)` from Task 2 (import `encounter_screen.dart`).
- Produces: the Run dashboard's initiative slot backed by the shared pane; `run-panel-initiative` key + "Initiative · Round N" title preserved.

- [ ] **Step 1: Rewire the dashboard slot**

In `lib/features/run_screen.dart`:

1. Replace `const initiative = _InitiativePanel();` (line ~43) with `const initiative = _InitiativeSlot();`.
2. Delete `class _InitiativePanel` (lines 169-273) entirely, including its `_showStatBlock` (now lives in the pane).
3. Add the slot wrapper next to the other panels:

```dart
/// Initiative slot: Run-side chrome around the shared [EncounterPane]
/// glance. The pane owns rendering; this owns the panel card + title.
class _InitiativeSlot extends ConsumerWidget {
  const _InitiativeSlot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enc =
        ref.watch(encounterProvider).valueOrNull ?? const EncounterState();
    return _Panel(
      k: const Key('run-panel-initiative'),
      title: 'Initiative · Round ${enc.round}',
      child: const EncounterPane(compact: true),
    );
  }
}
```

4. Add `import 'encounter_screen.dart';`. Remove imports that only `_InitiativePanel` used if the analyzer flags them (`StatBlockView` import stays only if another panel uses it — `run-init-row` stat-block glance moved to the pane, but `_PartyPanel`/reference panels may still use `sheet_widgets.dart`; keep what the analyzer needs).

- [ ] **Step 2: Run the Run tests**

Run: `flutter test test/run_screen_test.dart && flutter analyze lib/features/run_screen.dart lib/features/encounter_screen.dart`
Expected: PASS with no or minimal test edits — the compact pane emits identical `run-init-*` keys and identical behaviors. If a case fails, fix the CODE to honor the old contract unless the assertion covers a deliberately removed detail; brief allows editing the test only for such removed details, and the report must name each edited assertion and why.

- [ ] **Step 3: Full suite**

Run: `flutter test`
Expected: green. Attribute any failure via the final "Failing tests:" block only.

- [ ] **Step 4: Update CLAUDE.md**

Add one Project-notes bullet (top of the list, normal prose, existing style):

> **Combat merge (2026-08-22, consolidation epic sub-project 2)** — ONE combat widget: `EncounterPane({compact})` in `encounter_screen.dart` renders both the full Track → Encounter manager (`EncounterScreen` is now a thin mount) and the Run dashboard glance (`_InitiativeSlot` wraps `EncounterPane(compact: true)`; the old `_InitiativePanel` is deleted). Compact keeps the historical `run-init-*` keys + a `run-init-open-full` jump to Track → Encounter and shows no manager affordances. Pure widget merge — no model/persistence change. See `docs/superpowers/specs/2026-08-22-combat-merge-design.md`.

- [ ] **Step 5: Commit**

```bash
git add lib/features/run_screen.dart CLAUDE.md
git commit -m "feat(run): initiative slot mounts shared EncounterPane; _InitiativePanel deleted"
```

---

## Post-plan verification (before PR)

- Full suite + analyze green (Task 3 proves).
- Manual smoke on macOS: Run dashboard shows the glance; row tap opens stat block; Open encounter jumps to Track → Encounter; full manager unchanged.
- Branch is stacked on `feat/tracking-merge`; after PR #333 squash-merges, rebase with `git rebase --onto origin/main feat/tracking-merge feat/combat-merge` before opening the PR (or open the PR with base `feat/tracking-merge` if #333 is still open).
