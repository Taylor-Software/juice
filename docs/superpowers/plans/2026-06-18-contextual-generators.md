# Contextual Generators Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Re-home the 27 content generators — flavor generators move to a journal-composer "inspire" sheet (the standalone `Ask > Generators` tab is removed), and the four entity generators become contextual create-affordances that prefill the existing editable dialogs.

**Architecture:** Extract the generator registry (`GenSection` + the `_Gen` list) out of `generators_screen.dart` into a shared `lib/engine/generator_registry.dart`. A new `GenerateSheet` bottom sheet renders the *flavor* generators and appends rolls to the journal via the existing `addResult` path; the composer gains an "inspire" button to open it. The `Ask > Generators` tab + `gen-*` tool ids are removed. P2 wires the four entity generators (`npc`/`newScene`/`monsterEncounter`/`generateName`) into the roster/Scenes/Encounter create dialogs (prefill-then-edit) + an inline name-roll. No new engine logic — all generators already exist on `Oracle`.

**Tech Stack:** Flutter, `flutter_riverpod`, `package:flutter_test`.

---

## File Structure

**Create:**
- `lib/engine/generator_registry.dart` — `GenSection`, label, `GeneratorDef`, `kGenerators` (27), `flavorGenerators`, `sourceToolFor`.
- `lib/features/generate_sheet.dart` — `GenerateSheet` + `showGenerateSheet`.
- `test/generator_registry_test.dart`, `test/generate_sheet_test.dart`.

**Modify:**
- `lib/features/generators_screen.dart` — use the shared registry (P1), then delete after the tab is removed.
- `lib/features/oracles_tab.dart` — drop the Generators tab.
- `lib/features/journal_screen.dart` — composer "inspire" button.
- `lib/shared/tool_registry.dart`, `lib/shared/destination.dart` — drop `gen-*`.
- `lib/features/tracker_screen.dart` — Generate NPC + `_EditDialog` name-roll (P2).
- `lib/features/scenes_pane.dart`, `lib/features/encounter_screen.dart` — Generate affordances (P2).
- `CLAUDE.md`.

**Delete:**
- `lib/features/generators_screen.dart` (after Task 4).

---

## P1 — flavor home + tab removal

### Task 1: Extract the generator registry

**Files:**
- Create: `lib/engine/generator_registry.dart`
- Modify: `lib/features/generators_screen.dart` (use the shared registry)
- Test: `test/generator_registry_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/generator_registry.dart';

void main() {
  test('registry holds all 27 generators', () {
    expect(kGenerators.length, 27);
  });

  test('flavorGenerators excludes exactly the 4 entity generators', () {
    final flavorLabels = flavorGenerators.map((g) => g.label).toSet();
    for (final entity in ['NPC', 'New Scene', 'Monster Encounter', 'Name']) {
      expect(flavorLabels.contains(entity), isFalse, reason: '$entity excluded');
    }
    expect(flavorGenerators.length, 23);
  });

  test('sourceToolFor maps sections to gen-* ids', () {
    expect(sourceToolFor(GenSection.story), 'gen-story');
    expect(sourceToolFor(GenSection.details), 'gen-details');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/generator_registry_test.dart`
Expected: FAIL — `generator_registry.dart` not found.

- [ ] **Step 3: Create `lib/engine/generator_registry.dart`**

```dart
import 'oracle.dart';

enum GenSection { story, npcs, exploration, encounters, details }

extension GenSectionLabel on GenSection {
  String get label => switch (this) {
        GenSection.story => 'Story & Scenes',
        GenSection.npcs => 'NPCs & Dialog',
        GenSection.exploration => 'Exploration',
        GenSection.encounters => 'Encounters & Combat',
        GenSection.details => 'Names & Details',
      };
}

String sourceToolFor(GenSection s) => switch (s) {
      GenSection.story => 'gen-story',
      GenSection.npcs => 'gen-npcs',
      GenSection.exploration => 'gen-exploration',
      GenSection.encounters => 'gen-encounters',
      GenSection.details => 'gen-details',
    };

class GeneratorDef {
  const GeneratorDef(this.label, this.section, this.run);
  final String label;
  final GenSection section;
  final GenResult Function(Oracle o) run;
}

/// All content generators (the source of truth, moved out of GeneratorsScreen).
final List<GeneratorDef> kGenerators = [
  GeneratorDef('New Quest', GenSection.story, (o) => o.newQuest()),
  GeneratorDef('New Scene', GenSection.story, (o) => o.newScene()),
  GeneratorDef('Random Event', GenSection.story, (o) => o.randomEvent()),
  GeneratorDef('Challenge', GenSection.story, (o) => o.challenge()),
  GeneratorDef('Pay the Price', GenSection.story, (o) => o.payThePrice()),
  GeneratorDef(
      'Major Plot Twist', GenSection.story, (o) => o.payThePrice(critical: true)),
  GeneratorDef('NPC', GenSection.npcs, (o) => o.npc()),
  GeneratorDef('NPC Behavior', GenSection.npcs, (o) => o.npcBehavior()),
  GeneratorDef(
      'NPC Behavior (Active)', GenSection.npcs, (o) => o.npcBehavior(skew: 1)),
  GeneratorDef(
      'NPC Behavior (Passive)', GenSection.npcs, (o) => o.npcBehavior(skew: -1)),
  GeneratorDef('NPC Combat', GenSection.npcs, (o) => o.npcCombat()),
  GeneratorDef('Settlement', GenSection.exploration, (o) => o.settlement()),
  GeneratorDef('Natural Hazard', GenSection.exploration, (o) => o.naturalHazard()),
  GeneratorDef(
      'Monster Encounter', GenSection.encounters, (o) => o.monsterEncounter()),
  GeneratorDef('Creature Tracks', GenSection.encounters, (o) => o.creatureTracks()),
  GeneratorDef('Dungeon Name', GenSection.exploration, (o) => o.dungeonName()),
  GeneratorDef('Dungeon Room', GenSection.exploration, (o) => o.dungeonRoom()),
  GeneratorDef('Treasure', GenSection.details, (o) => o.treasure()),
  GeneratorDef('Name', GenSection.details, (o) => o.generateName()),
  GeneratorDef('Discover Meaning', GenSection.details, (o) => o.discoverMeaning()),
  GeneratorDef('Immersion', GenSection.details, (o) => o.immersion()),
  GeneratorDef('Plot Point', GenSection.story, (o) => o.plotPoint()),
  GeneratorDef('Random Idea', GenSection.details, (o) => o.randomIdea()),
  GeneratorDef('Detail', GenSection.details, (o) => o.detail()),
  GeneratorDef('Property', GenSection.details, (o) => o.property()),
  GeneratorDef('NPC Plot Knowledge', GenSection.npcs, (o) => o.extendedInfo()),
  GeneratorDef('Companion Response', GenSection.npcs, (o) => o.companionResponse()),
  GeneratorDef('NPC Dialog Topic', GenSection.npcs, (o) => o.dialogTopic()),
];

/// The four entity generators that get contextual homes (P2); excluded from the
/// composer's flavor sheet.
const _entityLabels = {'NPC', 'New Scene', 'Monster Encounter', 'Name'};

List<GeneratorDef> get flavorGenerators =>
    kGenerators.where((g) => !_entityLabels.contains(g.label)).toList();
```

(Verify this matches the current `_gens` list in `generators_screen.dart` exactly — it was copied from there; if that file's list has drifted, reconcile to it.)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/generator_registry_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Point `generators_screen.dart` at the shared registry**

In `lib/features/generators_screen.dart`: remove the local `enum GenSection`,
its label extension, the `_Gen` class, and the static `_gens` list; instead
`import '../engine/generator_registry.dart';` and use `kGenerators` /
`GeneratorDef` / `GenSection`. Replace the `_sourceTool` getter body with
`sourceToolFor(widget.section)` (keeping the `null` fallback → `gen-details` if
`widget.section` is nullable). The screen still renders + logs identically.

- [ ] **Step 6: Verify + commit**

Run: `flutter test test/generators_screen_test.dart test/generator_registry_test.dart` (if a generators_screen test exists) and `flutter analyze lib/features/generators_screen.dart lib/engine/generator_registry.dart`
Expected: PASS / No issues.

```bash
git add lib/engine/generator_registry.dart lib/features/generators_screen.dart test/generator_registry_test.dart
git commit -m "refactor(generators): extract shared generator registry"
```

---

### Task 2: GenerateSheet (flavor generators → journal)

**Files:**
- Create: `lib/features/generate_sheet.dart`
- Test: `test/generate_sheet_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/features/generate_sheet.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

Oracle _oracle() => Oracle(OracleData(
    jsonDecode(File('assets/oracle_data.json').readAsStringSync())
        as Map<String, dynamic>));

void main() {
  testWidgets('lists flavor generators (not the entity ones)', (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.journal.v2.default': '[]',
    });
    final c = ProviderContainer(overrides: [
      oracleProvider.overrideWith((ref) async => _oracle()),
    ]);
    addTearDown(c.dispose);
    await c.read(oracleProvider.future);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: GenerateSheet()))));
    await tester.pumpAndSettle();
    expect(find.text('Pay the Price'), findsOneWidget);
    expect(find.text('Random Event'), findsOneWidget);
    // entity generators are NOT in the flavor sheet:
    expect(find.text('New Scene'), findsNothing);
    expect(find.text('Monster Encounter'), findsNothing);
  });

  testWidgets('tapping a generator adds a journal entry', (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.journal.v2.default': '[]',
    });
    final c = ProviderContainer(overrides: [
      oracleProvider.overrideWith((ref) async => _oracle()),
    ]);
    addTearDown(c.dispose);
    await c.read(oracleProvider.future);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: GenerateSheet()))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pay the Price'));
    await tester.pumpAndSettle();
    final entries = await c.read(journalProvider.future);
    expect(entries.length, 1);
    expect(entries.first.sourceTool, 'gen-story');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/generate_sheet_test.dart`
Expected: FAIL — `generate_sheet.dart` not found.

- [ ] **Step 3: Create `lib/features/generate_sheet.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/generator_registry.dart';
import '../state/providers.dart';

/// Opens the flavor-generator sheet from the journal composer.
Future<void> showGenerateSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const GenerateSheet(),
    );

/// The "inspire" sheet: flavor generators grouped by section. Tapping one rolls
/// it and appends the result to the journal.
class GenerateSheet extends ConsumerWidget {
  const GenerateSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final oracle = ref.watch(oracleProvider).valueOrNull;
    if (oracle == null) {
      return const SizedBox(
        height: 120,
        child: Center(child: Text('Generators still loading…')),
      );
    }
    final bySection = <GenSection, List<GeneratorDef>>{};
    for (final g in flavorGenerators) {
      bySection.putIfAbsent(g.section, () => []).add(g);
    }
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final section in GenSection.values)
              if (bySection[section]?.isNotEmpty ?? false) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 6),
                  child: Text(section.label,
                      style: Theme.of(context).textTheme.labelMedium),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final g in bySection[section]!)
                      ActionChip(
                        key: Key('gen-${g.label}'),
                        label: Text(g.label),
                        onPressed: () {
                          final r = g.run(oracle);
                          ref.read(journalProvider.notifier).addResult(
                              r.title, r.asText,
                              sourceTool: sourceToolFor(g.section),
                              payload: r.toPayload());
                          Navigator.of(context).pop();
                        },
                      ),
                  ],
                ),
              ],
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/generate_sheet_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/generate_sheet.dart test/generate_sheet_test.dart
git commit -m "feat(generators): GenerateSheet (flavor generators → journal)"
```

---

### Task 3: Composer "inspire" button

**Files:**
- Modify: `lib/features/journal_screen.dart` (`_composerBar`, lines 908-950)
- Test: covered by Task 4's journal test + manual; add a focused test below.

- [ ] **Step 1: Write the failing test** (new `test/composer_inspire_test.dart`)

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/features/journal_screen.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/interpreter.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_interpreter.dart';

void main() {
  testWidgets('composer inspire button opens the generate sheet',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.journal.v2.default': '[]',
    });
    final oracle = Oracle(OracleData(
        jsonDecode(File('assets/oracle_data.json').readAsStringSync())
            as Map<String, dynamic>));
    final c = ProviderContainer(overrides: [
      oracleProvider.overrideWith((ref) async => oracle),
      interpreterServiceProvider.overrideWith((ref) => FakeInterpreterService()),
    ]);
    addTearDown(c.dispose);
    await c.read(oracleProvider.future);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: JournalScreen()))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('composer-inspire')));
    await tester.pumpAndSettle();
    expect(find.text('Pay the Price'), findsOneWidget); // sheet is open
  });
}
```

(Note: this pumps the full `JournalScreen`. Per the rootBundle-hang rule it needs
`oracleProvider` + `interpreterServiceProvider` overridden, as above, and mock
prefs seeded. If other data providers cause a hang, override them with empty
seeds the way `journal_screen_test.dart` does — match that file's harness.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/composer_inspire_test.dart`
Expected: FAIL — no `composer-inspire` key.

- [ ] **Step 3: Add the inspire button**

In `lib/features/journal_screen.dart` `_composerBar()`, insert between the
`composer-dice` IconButton and the `journal-send` IconButton:

```dart
          IconButton(
            key: const Key('composer-inspire'),
            icon: const Icon(Icons.auto_awesome),
            tooltip: 'Inspire (generators)',
            onPressed: () => showGenerateSheet(context),
          ),
```

Add `import 'generate_sheet.dart';` to `journal_screen.dart`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/composer_inspire_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/journal_screen.dart test/composer_inspire_test.dart
git commit -m "feat(generators): journal composer inspire button"
```

---

### Task 4: Remove the Ask>Generators tab + gen-* tool ids

**Files:**
- Modify: `lib/features/oracles_tab.dart`
- Delete: `lib/features/generators_screen.dart`
- Modify: `lib/shared/tool_registry.dart`, `lib/shared/destination.dart`
- Test: update `test/party_oracles_tab_test.dart`, `test/destination_test.dart`

- [ ] **Step 1: Update the Ask-tab tests first (red)**

In `test/party_oracles_tab_test.dart`, change the assertion to expect NO
Generators tab: `expect(find.widgetWithText(Tab, 'Generators'), findsNothing);`
and keep Oracle/Tables assertions. In `test/destination_test.dart`, add:
`expect(toolLocation.containsKey('gen-npcs'), isFalse);`.

Run: `flutter test test/party_oracles_tab_test.dart test/destination_test.dart`
Expected: FAIL (Generators tab still present; gen-* still in toolLocation).

- [ ] **Step 2: Remove the tab in `oracles_tab.dart`**

Delete the `SubtabDef('generators', 'Generators')` entry and the
`GeneratorsScreen(oracle: oracle)` child; remove the `generators_screen.dart`
import. The `initialTabIndex` math (dnd/shadowdark → `tables`) still works
(`tables` is unconditional). Tabs become Oracle / Tables (/ lonelog).

- [ ] **Step 3: Delete `generators_screen.dart`**

```bash
git rm lib/features/generators_screen.dart
```

(Its registry already moved to `generator_registry.dart` in Task 1; it now has
no references — confirm with `grep -rn GeneratorsScreen lib test`, expect none.)

- [ ] **Step 4: Drop `gen-*` from the tool registry + routing**

In `lib/shared/destination.dart` `toolLocation`, remove the five entries
`'gen-story'|'gen-npcs'|'gen-exploration'|'gen-encounters'|'gen-details'`. In
`lib/shared/tool_registry.dart`, remove the corresponding `ToolDef`s
(`gen-story`, `gen-npcs`, `gen-exploration`, `gen-encounters`, `gen-details`).

- [ ] **Step 5: Run the updated tests + full analyze**

Run: `flutter test test/party_oracles_tab_test.dart test/destination_test.dart test/tool_registry_test.dart`
Expected: PASS.
Run: `flutter analyze`
Expected: No issues found (no dangling `GeneratorsScreen` / `gen-*` refs).
If `tool_registry_test.dart` or `tool_search_sheet_test.dart` assert a count or a
specific gen-* tool, update them to the reduced set.

- [ ] **Step 6: Commit**

```bash
git add lib/features/oracles_tab.dart lib/shared/destination.dart lib/shared/tool_registry.dart test/
git commit -m "refactor(generators): remove Ask>Generators tab + gen-* tool ids"
```

---

## P2 — entity contextual affordances

### Task 5: Generate NPC in the roster + inline name-roll

**Files:**
- Modify: `lib/features/tracker_screen.dart` (CharactersPane + `_EditDialog`)
- Test: `test/character_sheet_ui_test.dart` (append) or a new test file

- [ ] **Step 1: Write the failing test**

```dart
  testWidgets('Generate NPC prefills and creates a character', (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.characters.v1.default': '[]',
    });
    final oracle = Oracle(OracleData(
        jsonDecode(File('assets/oracle_data.json').readAsStringSync())
            as Map<String, dynamic>));
    final c = ProviderContainer(overrides: [
      oracleProvider.overrideWith((ref) async => oracle),
    ]);
    addTearDown(c.dispose);
    await c.read(oracleProvider.future);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CharactersPane()))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('generate-npc')));
    await tester.pumpAndSettle();
    // The edit dialog opens prefilled; Save creates the character.
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final chars = await c.read(charactersProvider.future);
    expect(chars.length, 1);
    expect(chars.first.name.trim(), isNotEmpty);
  });
```

(Add the needed imports — `dart:convert`/`dart:io`, oracle, oracle_data — at the
file top if not present. This test seeds an empty roster, so the FAB shows; the
`generate-npc` affordance is reachable. If the roster's add flow is a dialog/menu,
confirm where the `generate-npc` key lives — see Step 3.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/character_sheet_ui_test.dart -n "Generate NPC"`
Expected: FAIL — no `generate-npc` key.

- [ ] **Step 3: Add Generate NPC + the `_EditDialog` name-roll**

In `tracker_screen.dart`:

(a) Add an `onRollName` hook to `_EditDialog` so the name field gets a dice
suffix. Change the constructor to accept `this.onRollName` (`String Function()?`,
optional), and in the `_a` `TextField` decoration add a suffix when present:

```dart
            decoration: InputDecoration(
              labelText: widget.labelA,
              suffixIcon: widget.onRollName == null
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.casino_outlined),
                      tooltip: 'Roll a name',
                      onPressed: () =>
                          setState(() => _a.text = widget.onRollName!()),
                    ),
            ),
```

(b) Add a "Generate NPC" affordance to the CharactersPane (e.g. a second small
button near the FAB, or an entry in the add flow) keyed `generate-npc`. Its
handler rolls and opens the prefilled dialog:

```dart
  Future<void> _generateNpc(BuildContext context) async {
    final oracle = ref.read(oracleProvider).valueOrNull;
    if (oracle == null) return;
    final npc = oracle.npc();
    final name = oracle.generateName().summary ?? '';
    final result = await showDialog<({String title, String note})>(
      context: context,
      builder: (_) => _EditDialog(
        heading: 'New NPC',
        labelA: 'Name',
        labelB: 'Note',
        initialA: name,
        initialB: npc.asText,
        onRollName: () => oracle.generateName().summary ?? '',
      ),
    );
    if (result == null || result.title.trim().isEmpty) return;
    final notifier = ref.read(charactersProvider.notifier);
    await notifier.add(result.title.trim());
    final added = ref.read(charactersProvider).valueOrNull?.first;
    if (added != null && result.note.trim().isNotEmpty) {
      await notifier.replace(added.copyWith(note: result.note.trim()));
    }
    if (mounted) setState(() => _editingId = added?.id);
  }
```

Wire a `generate-npc`-keyed button to `_generateNpc(context)`. (Place it
alongside the existing add FAB — e.g. a small `FloatingActionButton.small` with
`heroTag` set to avoid hero collisions, or a leading action in the list's empty
state. Pick the existing-pattern-consistent spot; key it `generate-npc`.)

`GenResult.summary` is nullable; `generateName()` always sets it, so `?? ''` is a
safe guard.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/character_sheet_ui_test.dart -n "Generate NPC"`
Expected: PASS.
Run: `flutter analyze lib/features/tracker_screen.dart`
Expected: No issues.

- [ ] **Step 5: Commit**

```bash
git add lib/features/tracker_screen.dart test/character_sheet_ui_test.dart
git commit -m "feat(generators): Generate NPC + inline name-roll in the roster"
```

---

### Task 6: Generate scene in Scenes

**Files:**
- Modify: `lib/features/scenes_pane.dart`
- Test: `test/scenes_pane_test.dart` (append or new)

- [ ] **Step 1: Write the failing test**

```dart
  testWidgets('Generate scene prefills the new-scene dialog', (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.journal.v2.default': '[]',
    });
    final oracle = Oracle(OracleData(
        jsonDecode(File('assets/oracle_data.json').readAsStringSync())
            as Map<String, dynamic>));
    final c = ProviderContainer(overrides: [
      oracleProvider.overrideWith((ref) async => oracle),
    ]);
    addTearDown(c.dispose);
    await c.read(oracleProvider.future);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: ScenesPane()))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('generate-scene')));
    await tester.pumpAndSettle();
    // The new-scene dialog is open with a non-empty prefilled title field.
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text.trim(), isNotEmpty);
  });
```

(Confirm `ScenesPane` pumps cleanly with just `oracleProvider` + seeded prefs;
match the existing `scenes_pane_test.dart` harness if present.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/scenes_pane_test.dart -n "Generate scene"`
Expected: FAIL — no `generate-scene` key.

- [ ] **Step 3: Add the Generate affordance**

In `scenes_pane.dart`, add a `generate-scene`-keyed button beside the existing
"New scene" button. Its handler rolls and opens the new-scene dialog prefilled:

```dart
  Future<void> _generateScene(BuildContext context, WidgetRef ref) async {
    final oracle = ref.read(oracleProvider).valueOrNull;
    if (oracle == null) return;
    final g = oracle.newScene();
    final controller = TextEditingController(text: g.summary ?? g.title);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New scene'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Scene title'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Start scene')),
        ],
      ),
    );
    if (title == null || title.trim().isEmpty) return;
    await ref.read(journalProvider.notifier).addScene(title.trim(),
        chaosFactor: ref.read(crawlProvider).valueOrNull?.chaosFactor);
  }
```

(`newScene().summary` may be null; fall back to `g.title`. This mirrors the
existing `_newScene` dialog exactly, only prefilled. If you prefer DRY, extract
the shared dialog into a helper that takes an initial title and have both
`_newScene` and `_generateScene` call it.)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/scenes_pane_test.dart -n "Generate scene"`
Expected: PASS.
Run: `flutter analyze lib/features/scenes_pane.dart`
Expected: No issues.

- [ ] **Step 5: Commit**

```bash
git add lib/features/scenes_pane.dart test/scenes_pane_test.dart
git commit -m "feat(generators): Generate scene prefills the new-scene dialog"
```

---

### Task 7: Generate monster in Encounter

**Files:**
- Modify: `lib/features/encounter_screen.dart`
- Test: `test/encounter_screen_test.dart` (append or new)

- [ ] **Step 1: Write the failing test**

```dart
  testWidgets('Generate monster prefills the ad-hoc combatant name',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.encounter.v1.default': '{"combatants":[],"round":1}',
    });
    final oracle = Oracle(OracleData(
        jsonDecode(File('assets/oracle_data.json').readAsStringSync())
            as Map<String, dynamic>));
    final c = ProviderContainer(overrides: [
      oracleProvider.overrideWith((ref) async => oracle),
    ]);
    addTearDown(c.dispose);
    await c.read(oracleProvider.future);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: EncounterScreen()))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('generate-monster')));
    await tester.pumpAndSettle();
    final name = tester.widget<TextField>(find.byKey(const Key('adhoc-name')));
    expect(name.controller?.text.trim(), isNotEmpty);
  });
```

(Confirm `EncounterScreen` pumps with `oracleProvider` + seeded encounter prefs;
match `encounter_screen_test.dart` if present. The `adhoc-name` key exists on the
ad-hoc dialog's name field per `_addAdHoc`.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/encounter_screen_test.dart -n "Generate monster"`
Expected: FAIL — no `generate-monster` key.

- [ ] **Step 3: Add the Generate affordance**

In `encounter_screen.dart`, add a `generate-monster`-keyed button near the
existing add affordances. Its handler rolls a monster and opens the ad-hoc
dialog with the name prefilled. Reuse `_addAdHoc`'s dialog by giving it an
optional initial name parameter:

```dart
  Future<void> _generateMonster(BuildContext context, WidgetRef ref) async {
    final oracle = ref.read(oracleProvider).valueOrNull;
    if (oracle == null) return;
    final g = oracle.monsterEncounter();
    await _addAdHoc(context, ref, initialName: g.summary ?? g.title);
  }
```

And add `{String initialName = ''}` to `_addAdHoc`, initializing its name
controller with it: `final name = TextEditingController(text: initialName);`.
Wire a `generate-monster`-keyed button to `_generateMonster`.

(`monsterEncounter().summary` may be null; fall back to `g.title`.)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/encounter_screen_test.dart -n "Generate monster"`
Expected: PASS.
Run: `flutter analyze lib/features/encounter_screen.dart`
Expected: No issues.

- [ ] **Step 5: Commit**

```bash
git add lib/features/encounter_screen.dart test/encounter_screen_test.dart
git commit -m "feat(generators): Generate monster prefills the ad-hoc combatant"
```

---

### Task 8: Full verify + docs

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Full analyze + test**

Run: `flutter analyze` → No issues found.
Run: `flutter test` → All tests pass.

- [ ] **Step 2: CLAUDE.md note**

Add under "## Project notes":

```markdown
- **Generators are re-homed** (no standalone screen). The 27-generator registry
  lives in `lib/engine/generator_registry.dart` (`GenSection`, `GeneratorDef`,
  `kGenerators`, `flavorGenerators`, `sourceToolFor`). The ~23 flavor generators
  open from the journal composer's **inspire** button (`composer-inspire`) →
  `GenerateSheet` (`lib/features/generate_sheet.dart`) → roll → journal
  `addResult`. The four entity generators are contextual prefill-then-edit
  affordances: Generate NPC in the roster (+ inline name-roll on the name
  field), Generate scene in Scenes, Generate monster in Encounter. The
  `Ask > Generators` tab and the `gen-*` tool ids are removed. See
  `docs/superpowers/specs/2026-06-18-contextual-generators-design.md`.
```

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(generators): document the re-homed generators"
```

---

## Self-Review

**1. Spec coverage:**
- GenerateSheet (flavor → journal) → Task 2. ✓
- Registry extraction (`generator_registry.dart`, `flavorGenerators` excludes 4) → Task 1. ✓
- Composer inspire button → Task 3. ✓
- Remove Ask>Generators tab + gen-* ids + delete GeneratorsScreen → Task 4. ✓
- Entity contextual affordances (NPC/scene/monster) prefill-then-edit + inline name-roll → Tasks 5/6/7. ✓
- oracleProvider null-guard on all generate affordances → Tasks 2/5/6/7. ✓
- Tests (registry, sheet, tab removal, destination, entity prefills) → each task. ✓
- Docs → Task 8. ✓

**2. Placeholder scan:** No "TBD"/"implement later". The "confirm/match existing
harness" notes point at concrete sibling test files and named keys
(`adhoc-name`), not vague logic. Button-placement notes give the key + handler;
the exact widget slot is left to match existing layout (a deliberate, bounded UI
choice, not missing logic).

**3. Type consistency:** `GeneratorDef{label,section,run}`, `GenSection`,
`flavorGenerators`, `sourceToolFor(GenSection)→String`, `GenerateSheet` +
`showGenerateSheet(context)`, `_EditDialog.onRollName` (`String Function()?`),
`_generateNpc`/`_generateScene`/`_generateMonster`, `_addAdHoc({initialName})` —
consistent across tasks. `GenResult.summary` treated as nullable (`?? ''` / `??
g.title`) everywhere.

**Ordering note:** Task 1 must precede Task 4 (the registry must move out before
`generators_screen.dart` is deleted). Tasks 5–7 are independent of each other.
P1 (1–4) is shippable on its own; P2 (5–7) layers on top.
