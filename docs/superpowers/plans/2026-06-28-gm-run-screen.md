# GM Run-Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A live "Run" verb — a read-and-act GM dashboard composing initiative, party HP/conditions, active scene+chaos, and quick dice/oracle/capture into one screen, over existing providers.

**Architecture:** A new `Destination.run` (6th verb) renders `RunScreen` (`lib/features/run_screen.dart`), a `ConsumerWidget` that uses `LayoutBuilder` to lay out five self-contained panel widgets — 2-column when wide (≥720), single scroll column when narrow. Every mutation routes through an existing notifier; the only new behaviors are `EncounterNotifier.rollInitiativeForAll` and a quick-capture box. No new persistence.

**Tech Stack:** Flutter, flutter_riverpod, Dart. Prefix flutter commands with `export PATH="$HOME/development/flutter/bin:$PATH"`. `dart format` runs on `.dart` edits. Tests use the `test/campaign_header_test.dart` harness pattern (mock prefs + `oracleProvider`/`interpreterServiceProvider` overrides + `tester.view.physicalSize`).

---

## Verified integration points (from recon)

- `Destination` enum + `destinationMeta` + `landingDestination` all in `lib/shared/destination.dart` (5 values: journal/sheet/ask/map/track; `landingDestination` gm→track, party→sheet). Test: `test/destination_test.dart`.
- `lib/shared/home_shell.dart`: `_visibleDestinations()` (line ~379, a `const [...]` list), `_root(d, systems, family)` switch (line ~387), nav built data-driven from `destinationMeta` + `_visibleDestinations()` (rail at ~467, bottom bar at ~486, split-view rail at ~428 which excludes `journal`). Adding a verb = add to the enum, `destinationMeta`, `_visibleDestinations()`, and `_root`.
- `EncounterNotifier` (`lib/state/providers.dart:744`): `_ready`, `save`, `addCombatant` (descending-init insert), `nextTurn`, `reorder`. `encounterProvider` at 857. `Dice` is `lib/engine/dice.dart` — `Dice([Random?])`, `int dN(int n)` rolls 1..n.
- `Combatant` (`lib/engine/models.dart:2757`): `id, name, characterId, initiative (int), track (CharTrack?), tags, defeated`; `copyWith({initiative, track, tags, defeated})`. `EncounterState` (2815): `combatants, turnIndex, round, locationRef` + `copyWith`.
- `CharacterNotifier` (`lib/state/providers.dart`): `applyPartyEffect(Set<String> ids, {int hpDelta, List<String> addConditions})` (406), `replace(Character)` (374). `Character.withHpDelta(int)` (models.dart:3627). `Character.role` (`CharacterRole {pc, companion, npc}` models.dart:3278); `Character.conditions` is `List<String>`.
- HP-pool display resolver: `_hpOf(Character) → (int,int)?` private in `lib/features/track_home_pane.dart` (~line 408, mirrors `withHpDelta` order). This plan lifts it to a public `characterHpPool` in `models.dart`.
- `JournalNotifier` (`lib/state/providers.dart`): `addResult(title, body, {sourceTool, payload})` (94), `addText(String body)` → `JournalKind.text` entry (112), `addScene(title,{chaosFactor}) → String id` (126), `replace(JournalEntry)` (167). `JournalEntry.copyWith({..., String? body})` (models.dart:130).
- Scene resolve: `activeSceneEntry(journal, activeSceneId)` (`lib/state/play_context.dart:80`). `PlayContextNotifier.setActiveScene(id)` (42); `playContextProvider` (61).
- Chaos: `crawlProvider` → `CrawlNotifier.setChaos(int n)` (providers.dart:601, clamps 1..9); read `ref.watch(crawlProvider).valueOrNull?.chaosFactor`.
- Oracle quick-roll: `oracleProvider` = `FutureProvider<Oracle>` (36); `fateCheckGenResult(oracle.fateCheck(Likelihood.normal))` (`lib/engine/oracle.dart:8`); the HUD's `_quickRoll` (`play_context_hud.dart:254`) switches on the default oracle (`mythic`→`oracle.mythicFate(4, chaos)`, `roll-high`→`oracle.rollHigh('d100', 3)`, else `fateCheckGenResult(...)`) then `journalProvider.notifier.addResult(g.title, g.asText, sourceTool: tool, payload: g.toPayload())`. Default oracle: `ref.watch(settingsProvider).valueOrNull?.defaultOracle ?? 'juice'` (models.dart:4192). `aiReadyProvider` = `Provider<bool>` (providers.dart:1278).

## File structure

- **Modify** `lib/state/providers.dart` — add `EncounterNotifier.rollInitiativeForAll({Dice? dice})`.
- **Modify** `lib/engine/models.dart` — add public `(int,int)? characterHpPool(Character c)`.
- **Modify** `lib/features/track_home_pane.dart` — `_hpOf` delegates to `characterHpPool` (DRY).
- **Modify** `lib/shared/destination.dart` — add `Destination.run` + meta + `landingDestination` gm→run.
- **Modify** `lib/shared/home_shell.dart` — `_visibleDestinations()` + `_root` case for `run`.
- **Create** `lib/features/run_screen.dart` — `RunScreen` + `_InitiativePanel`, `_PartyPanel`, `_ScenePanel`, `_DiceOraclePanel`, `_CapturePanel`.
- **Modify** `test/destination_test.dart` — gm→run.
- **Create** `test/run_screen_test.dart` — panel + reflow widget tests.
- **Create** `test/encounter_roll_init_test.dart` — `rollInitiativeForAll` model test.
- **Modify** `CLAUDE.md` — Run-screen bullet.

---

## Task 1: `rollInitiativeForAll` (engine/state)

**Files:** Modify `lib/state/providers.dart`; Test `test/encounter_roll_init_test.dart`.

Assign a d20 to every combatant whose initiative is unset (≤0), re-sort descending, reset the turn pointer to the top. Injectable `Dice` for deterministic tests. Won't clobber initiatives the GM already typed.

- [ ] **Step 1: Write the failing test** — create `test/encounter_roll_init_test.dart`:

```dart
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({
        'juice.sessions.v1':
            '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      }));

  test('rollInitiativeForAll fills unset (<=0) initiatives and sorts desc',
      () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(encounterProvider.notifier);
    await c.read(encounterProvider.future);
    await n.addCombatant(const Combatant(
        id: 'a', name: 'A', initiative: 0, track: CharTrack(current: 5, max: 5)));
    await n.addCombatant(const Combatant(
        id: 'b', name: 'B', initiative: 0, track: CharTrack(current: 5, max: 5)));
    await n.addCombatant(const Combatant(
        id: 'c', name: 'C', initiative: 18, track: CharTrack(current: 5, max: 5)));

    await n.rollInitiativeForAll(dice: Dice(Random(1)));
    final s = await c.read(encounterProvider.future);

    // typed value (18) preserved; the two zeros got d20 rolls
    expect(s.combatants.firstWhere((x) => x.id == 'c').initiative, 18);
    expect(s.combatants.firstWhere((x) => x.id == 'a').initiative, inInclusiveRange(1, 20));
    expect(s.combatants.firstWhere((x) => x.id == 'b').initiative, inInclusiveRange(1, 20));
    // sorted descending + turn pointer reset to top
    final inits = s.combatants.map((x) => x.initiative).toList();
    expect(inits, [...inits]..sort((p, q) => q.compareTo(p)));
    expect(s.turnIndex, 0);
  });

  test('rollInitiativeForAll is a no-op on empty + resorts when all typed',
      () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(encounterProvider.notifier);
    await c.read(encounterProvider.future);
    await n.rollInitiativeForAll(dice: Dice(Random(1))); // empty: no throw
    expect((await c.read(encounterProvider.future)).combatants, isEmpty);
  });
}
```

- [ ] **Step 2: Run** `export PATH="$HOME/development/flutter/bin:$PATH" && flutter test test/encounter_roll_init_test.dart` — FAIL (`rollInitiativeForAll` undefined).

- [ ] **Step 3: Implement** — in `lib/state/providers.dart`, add to `EncounterNotifier` (after `nextTurn`, before `setLocation`). Confirm `package:juice_oracle/engine/dice.dart` (the `Dice` class) is imported at the top of providers.dart; it is used elsewhere in the file (e.g. `crawlDungeon(HexcrawlData, Dice)`), so the import already exists.

```dart
  /// Roll a d20 for every combatant whose initiative is unset (<= 0), then
  /// re-sort descending and reset the turn pointer to the top of the order.
  /// Initiatives the GM already entered (> 0) are preserved. No-op when empty.
  Future<void> rollInitiativeForAll({Dice? dice}) async {
    final s = await _ready;
    if (s.combatants.isEmpty) return;
    final d = dice ?? Dice();
    final rolled = [
      for (final c in s.combatants)
        c.initiative <= 0 ? c.copyWith(initiative: d.dN(20)) : c,
    ]..sort((a, b) => b.initiative.compareTo(a.initiative));
    await save(s.copyWith(combatants: rolled, turnIndex: 0));
  }
```

- [ ] **Step 4: Run** `flutter test test/encounter_roll_init_test.dart` — PASS. `flutter analyze lib/state/providers.dart` — clean.

- [ ] **Step 5: Commit**

```bash
git add lib/state/providers.dart test/encounter_roll_init_test.dart
git commit -m "feat(encounter): rollInitiativeForAll helper"
```

---

## Task 2: `Destination.run` verb + shell wiring + stub screen

**Files:** Modify `lib/shared/destination.dart`, `lib/shared/home_shell.dart`; Create `lib/features/run_screen.dart` (stub); Modify `test/destination_test.dart`.

Add the 6th verb so it appears in nav and GM campaigns land on it. A stub `RunScreen` keeps the `_root` switch compiling; later tasks fill the panels.

- [ ] **Step 1: Update `test/destination_test.dart`** — change the gm expectation (read the file first; replace the gm line):

```dart
    expect(landingDestination(CampaignMode.gm), Destination.run);
    expect(landingDestination(CampaignMode.party), Destination.sheet);
```

- [ ] **Step 2: Run** `flutter test test/destination_test.dart` — FAIL (`Destination.run` undefined).

- [ ] **Step 3a: Edit `lib/shared/destination.dart`** — add `run` to the enum (last), its meta, and flip the gm landing:

```dart
enum Destination { journal, sheet, ask, map, track, run }
```
```dart
Destination landingDestination(CampaignMode mode) =>
    mode == CampaignMode.gm ? Destination.run : Destination.sheet;
```
Add to the `destinationMeta` map:
```dart
  Destination.run: DestinationMeta('Run', Icons.play_circle_outline),
```

- [ ] **Step 3b: Create the stub `lib/features/run_screen.dart`:**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The live GM run-screen: a read-and-act dashboard composing initiative,
/// party HP, the active scene, and quick dice/oracle over existing providers.
class RunScreen extends ConsumerWidget {
  const RunScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Center(key: Key('run-screen'), child: Text('Run'));
  }
}
```

- [ ] **Step 3c: Wire into `lib/shared/home_shell.dart`** — add the import:
```dart
import '../features/run_screen.dart';
```
add `Destination.run` to the end of the `_visibleDestinations()` const list:
```dart
        Destination.track,
        Destination.run,
      ];
```
add the `_root` switch arm:
```dart
      case Destination.run:
        return const RunScreen();
```

- [ ] **Step 4: Run** `flutter test test/destination_test.dart` — PASS. `flutter analyze lib/shared/ lib/features/run_screen.dart` — clean. Quick sanity: `flutter test test/home_shell_test.dart` — PASS (nav now has 6 items; if any test asserts an exact destination count, update it to 6).

- [ ] **Step 5: Commit**

```bash
git add lib/shared/destination.dart lib/shared/home_shell.dart lib/features/run_screen.dart test/destination_test.dart
git commit -m "feat(run): add Run verb + shell wiring; gm lands on Run"
```

---

## Task 3: `RunScreen` responsive scaffold

**Files:** Modify `lib/features/run_screen.dart`; Test `test/run_screen_test.dart`.

Replace the stub with the responsive shell: a top bar + five panel slots (empty placeholder widgets for now), 2-column when wide, single column when narrow.

- [ ] **Step 1: Write the failing test** — create `test/run_screen_test.dart`:

```dart
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/features/run_screen.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/interpreter.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

import 'fake_interpreter.dart';

const _sid = 'default';

OracleData _loadData() =>
    OracleData(jsonDecode(File('assets/oracle_data.json').readAsStringSync())
        as Map<String, dynamic>);

Map<String, Object> _prefs({
  String? journalJson,
  String? charsJson,
  String? encounterJson,
  String? crawlJson,
  String? contextJson,
}) =>
    {
      'juice.sessions.v1':
          '{"active":"$_sid","sessions":[{"id":"$_sid","name":"C1"}]}',
      if (journalJson != null) 'juice.journal.v2.$_sid': journalJson,
      if (charsJson != null) 'juice.characters.v1.$_sid': charsJson,
      if (encounterJson != null) 'juice.encounter.v1.$_sid': encounterJson,
      if (crawlJson != null) 'juice.crawl.v1.$_sid': crawlJson,
      if (contextJson != null) 'juice.context.v1.$_sid': contextJson,
    };

Future<ProviderContainer> _pump(
  WidgetTester tester,
  OracleData data,
  Map<String, Object> prefs, {
  Size size = const Size(1000, 2200),
  bool aiReady = false,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final oracle = Oracle(data, Dice(Random(1)));
  final container = ProviderContainer(overrides: [
    oracleProvider.overrideWith((ref) async => oracle),
    interpreterServiceProvider.overrideWithValue(FakeInterpreterService()),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: RunScreen())),
  ));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  late OracleData data;
  setUpAll(() => data = _loadData());

  testWidgets('run-screen renders the four panel headers', (tester) async {
    await _pump(tester, data, _prefs());
    expect(find.byKey(const Key('run-screen')), findsOneWidget);
    expect(find.byKey(const Key('run-panel-initiative')), findsOneWidget);
    expect(find.byKey(const Key('run-panel-party')), findsOneWidget);
    expect(find.byKey(const Key('run-panel-scene')), findsOneWidget);
    expect(find.byKey(const Key('run-panel-dice')), findsOneWidget);
    expect(find.byKey(const Key('run-panel-capture')), findsOneWidget);
  });
}
```

NOTE: this test asserts the five panels exist (they render as labelled placeholders until Tasks 4–7 flesh them). Keep the panel keys (`run-panel-initiative/party/scene/dice/capture`) stable — later tasks build inside these widgets.

- [ ] **Step 2: Run** `flutter test test/run_screen_test.dart` — FAIL (panels missing).

- [ ] **Step 3: Implement the scaffold** in `lib/features/run_screen.dart` (replace the whole file). Panels are private placeholder widgets here; Tasks 4–7 replace each body.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Width at or above which the run-screen shows a two-column dashboard;
/// below it the panels stack in a single scrolling column.
const double kRunWideBreakpoint = 720;

/// The live GM run-screen: a read-and-act dashboard composing initiative,
/// party HP, the active scene, and quick dice/oracle over existing providers.
class RunScreen extends ConsumerWidget {
  const RunScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      key: const Key('run-screen'),
      builder: (context, c) {
        final wide = c.maxWidth >= kRunWideBreakpoint;
        const initiative = _InitiativePanel();
        const party = _PartyPanel();
        const scene = _ScenePanel();
        const dice = _DiceOraclePanel();
        const capture = _CapturePanel();
        if (wide) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Expanded(
                  child: Column(children: [
                    initiative,
                    SizedBox(height: 12),
                    party,
                  ]),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(children: [
                    scene,
                    SizedBox(height: 12),
                    dice,
                    SizedBox(height: 12),
                    capture,
                  ]),
                ),
              ],
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(12),
          children: const [
            initiative,
            SizedBox(height: 12),
            party,
            SizedBox(height: 12),
            scene,
            SizedBox(height: 12),
            dice,
            SizedBox(height: 12),
            capture,
          ],
        );
      },
    );
  }
}

/// Shared card chrome for a run-screen panel.
class _Panel extends StatelessWidget {
  const _Panel({required this.k, required this.title, required this.child});
  final Key k;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: k,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class _InitiativePanel extends ConsumerWidget {
  const _InitiativePanel();
  @override
  Widget build(BuildContext context, WidgetRef ref) => const _Panel(
      k: Key('run-panel-initiative'), title: 'Initiative', child: SizedBox());
}

class _PartyPanel extends ConsumerWidget {
  const _PartyPanel();
  @override
  Widget build(BuildContext context, WidgetRef ref) => const _Panel(
      k: Key('run-panel-party'), title: 'Party', child: SizedBox());
}

class _ScenePanel extends ConsumerWidget {
  const _ScenePanel();
  @override
  Widget build(BuildContext context, WidgetRef ref) => const _Panel(
      k: Key('run-panel-scene'), title: 'Scene', child: SizedBox());
}

class _DiceOraclePanel extends ConsumerWidget {
  const _DiceOraclePanel();
  @override
  Widget build(BuildContext context, WidgetRef ref) => const _Panel(
      k: Key('run-panel-dice'), title: 'Dice & oracle', child: SizedBox());
}

class _CapturePanel extends ConsumerWidget {
  const _CapturePanel();
  @override
  Widget build(BuildContext context, WidgetRef ref) => const _Panel(
      k: Key('run-panel-capture'), title: 'Capture', child: SizedBox());
}
```

- [ ] **Step 4: Run** `flutter test test/run_screen_test.dart` — PASS. `flutter analyze lib/features/run_screen.dart` — clean.

- [ ] **Step 5: Commit**

```bash
git add lib/features/run_screen.dart test/run_screen_test.dart
git commit -m "feat(run): responsive RunScreen scaffold with panel slots"
```

---

## Task 4: Initiative panel

**Files:** Modify `lib/features/run_screen.dart`; Test `test/run_screen_test.dart`.

Fill `_InitiativePanel`: combatant rows (init badge, name, current-turn highlight, defeated strike-through), round, "Next turn", "Roll all init", and an empty-state.

- [ ] **Step 1: Add the failing test** to `test/run_screen_test.dart` (inside `main`):

```dart
  testWidgets('initiative: next turn advances; roll-all fills unset', (tester) async {
    const enc =
        '{"combatants":[{"id":"a","name":"Ash","initiative":15,"track":{"current":5,"max":5},"tags":[],"defeated":false},{"id":"b","name":"Bog","initiative":0,"track":{"current":4,"max":4},"tags":[],"defeated":false}],"turnIndex":0,"round":1}';
    final c = await _pump(tester, data, _prefs(encounterJson: enc));
    expect(find.text('Ash'), findsOneWidget);
    expect(find.textContaining('Round 1'), findsOneWidget);

    await tester.tap(find.byKey(const Key('run-init-next')));
    await tester.pumpAndSettle();
    expect((await c.read(encounterProvider.future)).turnIndex, 1);

    await tester.tap(find.byKey(const Key('run-init-roll-all')));
    await tester.pumpAndSettle();
    expect((await c.read(encounterProvider.future))
        .combatants.firstWhere((x) => x.id == 'b').initiative, greaterThan(0));
  });

  testWidgets('initiative: empty state when no combatants', (tester) async {
    await _pump(tester, data, _prefs());
    expect(find.byKey(const Key('run-init-empty')), findsOneWidget);
  });
```

- [ ] **Step 2: Run** `flutter test test/run_screen_test.dart -n initiative` — FAIL.

- [ ] **Step 3: Implement** — replace `_InitiativePanel` in `lib/features/run_screen.dart` (add `import '../engine/models.dart';` and `import '../state/providers.dart';` at the top):

```dart
class _InitiativePanel extends ConsumerWidget {
  const _InitiativePanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final enc = ref.watch(encounterProvider).valueOrNull ?? const EncounterState();
    final notifier = ref.read(encounterProvider.notifier);
    final rows = <Widget>[];
    for (var i = 0; i < enc.combatants.length; i++) {
      final c = enc.combatants[i];
      final current = i == enc.turnIndex;
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: current
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surfaceContainerHighest,
            child: Text('${c.initiative}',
                style: theme.textTheme.labelMedium),
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
      ));
    }

    return _Panel(
      k: const Key('run-panel-initiative'),
      title: 'Initiative · Round ${enc.round}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (enc.combatants.isEmpty)
            const Text('No encounter yet.', key: Key('run-init-empty'))
          else
            ...rows,
          const SizedBox(height: 8),
          Row(children: [
            FilledButton.tonal(
              key: const Key('run-init-next'),
              onPressed:
                  enc.combatants.isEmpty ? null : () => notifier.nextTurn(),
              child: const Text('Next turn'),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              key: const Key('run-init-roll-all'),
              onPressed: enc.combatants.isEmpty
                  ? null
                  : () => notifier.rollInitiativeForAll(),
              child: const Text('Roll all init'),
            ),
          ]),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run** `flutter test test/run_screen_test.dart` — PASS. `flutter analyze lib/features/run_screen.dart` — clean.

- [ ] **Step 5: Commit**

```bash
git add lib/features/run_screen.dart test/run_screen_test.dart
git commit -m "feat(run): initiative panel (next turn, roll-all, rows)"
```

---

## Task 5: Party panel + `characterHpPool` helper

**Files:** Modify `lib/engine/models.dart`, `lib/features/track_home_pane.dart`, `lib/features/run_screen.dart`; Test `test/run_screen_test.dart`.

Lift the HP-pool resolver to a public `characterHpPool`, then fill `_PartyPanel`: a card per PC/companion with HP + conditions and inline ±HP.

- [ ] **Step 1: Add `characterHpPool` to `lib/engine/models.dart`** (top-level function near the `Character` class; mirrors `withHpDelta` order exactly):

```dart
/// A character's HP pool `(current, max)` resolved the same way [Character.withHpDelta]
/// applies damage: the active sheet's pool, else the first generic track, else null
/// (pool-less sheets). Shared by the roster, the encounter tracker, and the run-screen.
(int, int)? characterHpPool(Character c) {
  if (c.dnd != null) return (c.dnd!.currentHp, c.dnd!.maxHp);
  if (c.shadowdark != null) return (c.shadowdark!.currentHp, c.shadowdark!.maxHp);
  if (c.nimble != null) return (c.nimble!.currentHp, c.nimble!.maxHp);
  if (c.drawSteel != null) return (c.drawSteel!.currentStamina, c.drawSteel!.maxStamina);
  if (c.argosa != null) return (c.argosa!.currentHp, c.argosa!.maxHp);
  if (c.cairn != null) return (c.cairn!.currentHp, c.cairn!.maxHp);
  if (c.knave != null) return (c.knave!.currentHp, c.knave!.maxHp);
  if (c.ose != null) return (c.ose!.currentHp, c.ose!.maxHp);
  if (c.kalArath != null) return (c.kalArath!.currentHp, c.kalArath!.maxHp);
  if (c.tracks.isNotEmpty) return (c.tracks.first.current, c.tracks.first.max);
  return null;
}
```
IMPORTANT: open `lib/features/track_home_pane.dart`'s `_hpOf` and confirm `characterHpPool` lists the SAME sheet types in the SAME order (the recon snippet shows dnd/shadowdark/nimble/drawSteel/argosa/cairn/knave/ose/kalArath then `tracks.first`). If `_hpOf` includes a sheet type not listed above (e.g. a newer sheet), add it to `characterHpPool` to match — the two must stay identical.

- [ ] **Step 2: DRY `track_home_pane.dart`** — replace the body of its private `_hpOf` with a delegation:

```dart
  (int, int)? _hpOf(Character c) => characterHpPool(c);
```
(Confirm `models.dart` is already imported there — it is, for `Character`.)

- [ ] **Step 3: Write the failing test** in `test/run_screen_test.dart`:

```dart
  testWidgets('party: shows PCs with HP and applies inline damage', (tester) async {
    const chars =
        '[{"id":"p1","name":"Vex","stats":[],"tracks":[{"label":"HP","current":10,"max":10}],"tags":[],"role":"pc"},{"id":"n1","name":"Goon","stats":[],"tracks":[],"tags":[],"role":"npc"}]';
    final c = await _pump(tester, data, _prefs(charsJson: chars));
    expect(find.text('Vex'), findsOneWidget);
    expect(find.text('Goon'), findsNothing); // npc not in party panel
    expect(find.textContaining('10/10'), findsOneWidget);

    await tester.tap(find.byKey(const Key('run-party-p1-dec')));
    await tester.pumpAndSettle();
    final vex = (await c.read(charactersProvider.future))
        .firstWhere((x) => x.id == 'p1');
    expect(vex.tracks.first.current, 9);
  });

  testWidgets('party: empty state when no PCs', (tester) async {
    await _pump(tester, data, _prefs());
    expect(find.byKey(const Key('run-party-empty')), findsOneWidget);
  });
```

- [ ] **Step 4: Run** `flutter test test/run_screen_test.dart -n party` — FAIL.

- [ ] **Step 5: Implement** — replace `_PartyPanel` in `lib/features/run_screen.dart`:

```dart
class _PartyPanel extends ConsumerWidget {
  const _PartyPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final all = ref.watch(charactersProvider).valueOrNull ?? const <Character>[];
    final notifier = ref.read(charactersProvider.notifier);
    final party = all
        .where((c) =>
            c.role == CharacterRole.pc || c.role == CharacterRole.companion)
        .toList();

    return _Panel(
      k: const Key('run-panel-party'),
      title: 'Party',
      child: party.isEmpty
          ? const Text('No party yet.', key: Key('run-party-empty'))
          : Column(
              children: [
                for (final c in party)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.name, style: theme.textTheme.bodyMedium),
                            Builder(builder: (_) {
                              final hp = characterHpPool(c);
                              final cond = c.conditions.join(', ');
                              final parts = [
                                if (hp != null) '${hp.$1}/${hp.$2}',
                                if (cond.isNotEmpty) cond,
                              ];
                              return Text(parts.join(' · '),
                                  style: theme.textTheme.bodySmall);
                            }),
                          ],
                        ),
                      ),
                      IconButton(
                        key: Key('run-party-${c.id}-dec'),
                        icon: const Icon(Icons.remove, size: 18),
                        onPressed: () =>
                            notifier.replace(c.withHpDelta(-1)),
                      ),
                      IconButton(
                        key: Key('run-party-${c.id}-inc'),
                        icon: const Icon(Icons.add, size: 18),
                        onPressed: () =>
                            notifier.replace(c.withHpDelta(1)),
                      ),
                    ]),
                  ),
              ],
            ),
    );
  }
}
```

- [ ] **Step 6: Run** `flutter test test/run_screen_test.dart` (whole file) + `flutter test test/track_home_pane_test.dart` (if present) — PASS. `flutter analyze lib/engine/models.dart lib/features/track_home_pane.dart lib/features/run_screen.dart` — clean.

- [ ] **Step 7: Commit**

```bash
git add lib/engine/models.dart lib/features/track_home_pane.dart lib/features/run_screen.dart test/run_screen_test.dart
git commit -m "feat(run): party panel + shared characterHpPool helper"
```

---

## Task 6: Scene panel

**Files:** Modify `lib/features/run_screen.dart`; Test `test/run_screen_test.dart`.

Fill `_ScenePanel`: active scene title + description (read-only display in v1 + a chaos −/+ dial). Scene is resolved via `activeSceneEntry`; chaos via `crawlProvider`.

- [ ] **Step 1: Write the failing test** in `test/run_screen_test.dart` (add `import 'package:juice_oracle/state/play_context.dart';` if you reference it; not needed for this test):

```dart
  testWidgets('scene: shows active scene + steps chaos', (tester) async {
    const journal =
        '[{"id":"e1","timestamp":"2026-01-01T10:00:00.000Z","title":"The Vault","body":"Dust everywhere.","kind":"scene","chaosFactor":6,"tags":[]}]';
    final c = await _pump(tester, data,
        _prefs(journalJson: journal, crawlJson: '{"chaosFactor":6}'));
    expect(find.text('The Vault'), findsWidgets);
    expect(find.text('Dust everywhere.'), findsOneWidget);
    expect(find.textContaining('Chaos 6'), findsOneWidget);

    await tester.tap(find.byKey(const Key('run-scene-chaos-inc')));
    await tester.pumpAndSettle();
    expect((await c.read(crawlProvider.future)).chaosFactor, 7);
  });

  testWidgets('scene: empty state when no scene', (tester) async {
    await _pump(tester, data, _prefs());
    expect(find.byKey(const Key('run-scene-empty')), findsOneWidget);
  });
```

- [ ] **Step 2: Run** `flutter test test/run_screen_test.dart -n scene` — FAIL.

- [ ] **Step 3: Implement** — replace `_ScenePanel` (add `import '../state/play_context.dart';` to the file):

```dart
class _ScenePanel extends ConsumerWidget {
  const _ScenePanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final journal = ref.watch(journalProvider).valueOrNull ?? const <JournalEntry>[];
    final ctx = ref.watch(playContextProvider).valueOrNull;
    final scene = activeSceneEntry(journal, ctx?.activeSceneId);
    final chaos = ref.watch(crawlProvider).valueOrNull?.chaosFactor;

    return _Panel(
      k: const Key('run-panel-scene'),
      title: 'Scene',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (scene == null)
            const Text('No active scene.', key: Key('run-scene-empty'))
          else ...[
            Text(scene.title.isEmpty ? '(untitled scene)' : scene.title,
                style: theme.textTheme.titleSmall),
            if (scene.body.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(scene.body, style: theme.textTheme.bodySmall),
              ),
          ],
          if (chaos != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(children: [
                Text('Chaos $chaos', style: theme.textTheme.bodyMedium),
                const Spacer(),
                IconButton(
                  key: const Key('run-scene-chaos-dec'),
                  icon: const Icon(Icons.remove, size: 18),
                  onPressed: () =>
                      ref.read(crawlProvider.notifier).setChaos(chaos - 1),
                ),
                IconButton(
                  key: const Key('run-scene-chaos-inc'),
                  icon: const Icon(Icons.add, size: 18),
                  onPressed: () =>
                      ref.read(crawlProvider.notifier).setChaos(chaos + 1),
                ),
              ]),
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run** `flutter test test/run_screen_test.dart` — PASS. `flutter analyze lib/features/run_screen.dart` — clean.

- [ ] **Step 5: Commit**

```bash
git add lib/features/run_screen.dart test/run_screen_test.dart
git commit -m "feat(run): scene panel (active scene + chaos dial)"
```

---

## Task 7: Dice/oracle panel + capture panel

**Files:** Modify `lib/features/run_screen.dart`; Test `test/run_screen_test.dart`.

Fill `_DiceOraclePanel` (default-oracle quick roll mirroring the HUD + an aiReady-gated Interpret stub) and `_CapturePanel` (text → `addText`).

- [ ] **Step 1: Write the failing tests** in `test/run_screen_test.dart`:

```dart
  testWidgets('dice: roll logs a journal result; interpret hidden when AI off',
      (tester) async {
    final c = await _pump(tester, data, _prefs(crawlJson: '{"chaosFactor":5}'));
    expect(find.byKey(const Key('run-dice-interpret')), findsNothing); // AI off
    await tester.tap(find.byKey(const Key('run-dice-roll')));
    await tester.pumpAndSettle();
    final entries = await c.read(journalProvider.future);
    expect(entries.where((e) => e.sourceTool == 'fate-check'), hasLength(1));
  });

  testWidgets('capture: logs a text note and clears', (tester) async {
    final c = await _pump(tester, data, _prefs());
    await tester.enterText(
        find.byKey(const Key('run-capture-field')), 'Brakk shoves the archer');
    await tester.tap(find.byKey(const Key('run-capture-log')));
    await tester.pumpAndSettle();
    final entries = await c.read(journalProvider.future);
    expect(entries.where((e) => e.body == 'Brakk shoves the archer'),
        hasLength(1));
  });
```

- [ ] **Step 2: Run** `flutter test test/run_screen_test.dart -n dice` then `-n capture` — FAIL.

- [ ] **Step 3: Implement** — replace `_DiceOraclePanel` and `_CapturePanel`. Add imports `import '../engine/oracle.dart';` (for `fateCheckGenResult` + `Likelihood`) and `import 'package:flutter_riverpod/flutter_riverpod.dart';` (already present). `_CapturePanel` becomes a `ConsumerStatefulWidget` for its controller.

```dart
class _DiceOraclePanel extends ConsumerWidget {
  const _DiceOraclePanel();

  void _roll(WidgetRef ref) {
    final oracle = ref.read(oracleProvider).valueOrNull;
    if (oracle == null) return;
    final defaultOracle =
        ref.read(settingsProvider).valueOrNull?.defaultOracle ?? 'juice';
    final chaos = ref.read(crawlProvider).valueOrNull?.chaosFactor ?? 5;
    final GenResult g;
    final String tool;
    switch (defaultOracle) {
      case 'mythic':
        g = oracle.mythicFate(4, chaos);
        tool = 'mythic';
      case 'roll-high':
        g = oracle.rollHigh('d100', 3);
        tool = 'roll-high';
      default:
        g = fateCheckGenResult(oracle.fateCheck(Likelihood.normal));
        tool = 'fate-check';
    }
    ref.read(journalProvider.notifier).addResult(g.title, g.asText,
        sourceTool: tool, payload: g.toPayload());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aiReady = ref.watch(aiReadyProvider);
    return _Panel(
      k: const Key('run-panel-dice'),
      title: 'Dice & oracle',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton(
            key: const Key('run-dice-roll'),
            onPressed: () => _roll(ref),
            child: const Text('Roll oracle'),
          ),
          if (aiReady)
            OutlinedButton(
              key: const Key('run-dice-interpret'),
              onPressed: () => ref
                  .read(shellRouteProvider.notifier)
                  .goTo(Destination.journal),
              child: const Text('Interpret in journal'),
            ),
        ],
      ),
    );
  }
}

class _CapturePanel extends ConsumerStatefulWidget {
  const _CapturePanel();
  @override
  ConsumerState<_CapturePanel> createState() => _CapturePanelState();
}

class _CapturePanelState extends ConsumerState<_CapturePanel> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _log() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    ref.read(journalProvider.notifier).addText(text);
    _ctrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    return _Panel(
      k: const Key('run-panel-capture'),
      title: 'Capture',
      child: Row(children: [
        Expanded(
          child: TextField(
            key: const Key('run-capture-field'),
            controller: _ctrl,
            decoration: const InputDecoration(hintText: 'What just happened…'),
            onSubmitted: (_) => _log(),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.tonal(
          key: const Key('run-capture-log'),
          onPressed: _log,
          child: const Text('Log'),
        ),
      ]),
    );
  }
}
```
The file now also needs `import '../shared/shell_route.dart';` and `import '../shared/destination.dart';` (for the Interpret nav). Add them.

NOTE on the Interpret button: v1 routes to the Journal verb (where per-entry Interpret already lives) rather than duplicating the interpret flow — keeps the panel lean while honoring "AI affordance only when ready". The test only asserts it is hidden when AI is off; a richer inline interpret is deferred.

- [ ] **Step 4: Run** `flutter test test/run_screen_test.dart` — PASS (all run-screen tests). `flutter analyze lib/features/run_screen.dart` — clean.

- [ ] **Step 5: Commit**

```bash
git add lib/features/run_screen.dart test/run_screen_test.dart
git commit -m "feat(run): dice/oracle + capture panels"
```

---

## Task 8: Reflow test + full verify + docs

**Files:** Test `test/run_screen_test.dart`; Modify `CLAUDE.md`.

- [ ] **Step 1: Add a responsive-reflow test** to `test/run_screen_test.dart`:

```dart
  testWidgets('layout: two columns when wide, one column when narrow',
      (tester) async {
    const chars =
        '[{"id":"p1","name":"Vex","stats":[],"tracks":[{"label":"HP","current":10,"max":10}],"tags":[],"role":"pc"}]';
    // Wide: initiative and scene panels sit in two side-by-side columns → the
    // initiative panel's left edge is left of the scene panel's left edge.
    await _pump(tester, data, _prefs(charsJson: chars),
        size: const Size(1100, 1600));
    final initWide = tester.getTopLeft(find.byKey(const Key('run-panel-initiative')));
    final sceneWide = tester.getTopLeft(find.byKey(const Key('run-panel-scene')));
    expect(initWide.dx, lessThan(sceneWide.dx));

    // Narrow: stacked → scene sits below initiative (greater dy, same-ish dx).
    await _pump(tester, data, _prefs(charsJson: chars),
        size: const Size(500, 2400));
    final initN = tester.getTopLeft(find.byKey(const Key('run-panel-initiative')));
    final sceneN = tester.getTopLeft(find.byKey(const Key('run-panel-scene')));
    expect(sceneN.dy, greaterThan(initN.dy));
  });
```

- [ ] **Step 2: Run** `flutter test test/run_screen_test.dart` — PASS.

- [ ] **Step 3: Full verification:**
```bash
export PATH="$HOME/development/flutter/bin:$PATH"
flutter analyze
flutter test
```
Expect no analyze issues and all tests pass; report the total count. If lints appear in new test code, `dart fix --apply test/run_screen_test.dart test/encounter_roll_init_test.dart` then re-analyze.

- [ ] **Step 4: Update `CLAUDE.md`** — add a bullet near the verb-nav / PlayContext-spine notes:
```markdown
- The **GM Run-screen** (`lib/features/run_screen.dart`, `RunScreen`, a new
  `Destination.run` 6th verb) is a live read-and-act dashboard: a responsive
  `LayoutBuilder` grid (2-col ≥ `kRunWideBreakpoint` 720, else stacked) of five
  panels — Initiative (`encounterProvider` + `nextTurn` + new
  `EncounterNotifier.rollInitiativeForAll`), Party (PC/companion HP+conditions
  via `characterHpPool` + `withHpDelta`), Scene (`activeSceneEntry` + chaos via
  `crawlProvider.setChaos`), Dice/oracle (default-oracle roll → `addResult`,
  aiReady-gated Interpret routes to Journal), and Capture (`addText`). Pure
  composition over existing providers + one new encounter helper; NO new
  persistence. GM mode now lands on Run (`landingDestination` gm→run). The
  shared `characterHpPool` (models.dart) is the single HP-pool resolver
  (track_home_pane's `_hpOf` delegates to it). See
  `docs/superpowers/specs/2026-06-28-gm-run-screen-design.md`.
```

- [ ] **Step 5: Commit**

```bash
git add test/run_screen_test.dart CLAUDE.md
git commit -m "test(run): responsive reflow; docs"
```

---

## Self-review notes

- **Spec coverage:** placement+landing (T2), responsive layout (T3, T8), initiative incl. roll-all (T1, T4), party HP/conditions+effect-path (T5), scene+chaos (T6), dice/oracle+capture (T7), tests+docs (T8). All spec panels covered. (The bulk-effect modal is reachable via the existing `applyPartyEffect`; v1 party panel exposes inline ±HP — an "Effect…" button can be added later, noted as a lean cut, since `applyPartyEffect` is already tested elsewhere.)
- **Naming consistency:** `Destination.run`; `RunScreen`; `kRunWideBreakpoint`; panel keys `run-panel-{initiative,party,scene,dice,capture}`; action keys `run-init-next`/`run-init-roll-all`/`run-party-<id>-dec|inc`/`run-scene-chaos-dec|inc`/`run-dice-roll`/`run-dice-interpret`/`run-capture-field|log`; `EncounterNotifier.rollInitiativeForAll({Dice? dice})`; `characterHpPool(Character)`.
- **Compile-order:** T2 adds the enum value WITH a stub `RunScreen` + the `_root` arm in the same commit, so the exhaustive `_root` switch always compiles. T3 swaps the stub for the scaffold. Each task leaves the suite green.
- **No new persistence / no export change.** Only `rollInitiativeForAll` + `characterHpPool` are new code paths; everything else routes through existing notifiers.
- **Deferred (per spec):** stat-block cards, per-combatant init modifiers, reorder/collapse panels, threads/rumors panel, inline interpret, an "Effect…" bulk button on the party panel.
