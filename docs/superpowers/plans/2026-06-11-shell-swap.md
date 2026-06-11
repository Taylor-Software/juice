# Shell Swap (Redesign Phase 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Journal becomes the home screen; every existing tool moves behind an activity-grouped, searchable launcher that opens over the journal (side panel ≥840dp, full-width sheet below), with tool state surviving close/reopen.

**Architecture:** A declarative tool registry (`ToolDef` list) feeds a single `ToolHost` widget that owns an always-mounted `Offstage`+`IndexedStack` of instantiated tools — one keep-alive mechanism for desktop and mobile, no `Scaffold.endDrawer`/`showModalBottomSheet` (those unmount content and lose state). `HomeShell` drops the `NavigationBar`; `JournalScreen` fills the body; the Tracker's Journal tab is removed (its home now). `FateScreen` gains a section anchor; `GeneratorsScreen` gains an activity-section filter so one screen serves five launcher groups.

**Tech Stack:** Flutter + flutter_riverpod + shared_preferences (existing rails only). Spec: `docs/superpowers/specs/2026-06-11-journal-redesign-design.md` (Phase 2 section). Baseline: 83 tests green; `flutter analyze --no-fatal-infos` = 4 pre-existing infos (models.dart doc comment + 3 tracker const lints; removing the tracker ones by rewriting those lines is acceptable, adding new infos is not).

---

### Task 1: Screen params — Fate anchor, Generators sections, Tracker two tabs

**Files:**
- Modify: `lib/features/fate_screen.dart`
- Modify: `lib/features/generators_screen.dart`
- Modify: `lib/features/tracker_screen.dart` (tab list at top)
- Test: `test/screen_params_test.dart` (new)

- [ ] **Step 1: Write failing tests** (`test/screen_params_test.dart`):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/features/generators_screen.dart';

void main() {
  test('every generator belongs to exactly one section', () {
    final seen = <String>{};
    for (final s in GenSection.values) {
      for (final label in GeneratorsScreen.labelsFor(s)) {
        expect(seen.add(label), isTrue, reason: '$label in two sections');
      }
    }
    expect(seen.length, greaterThanOrEqualTo(28));
  });

  test('section labels cover the activity taxonomy', () {
    expect(GenSection.values.map((s) => s.label), containsAll([
      'Story & Scenes',
      'NPCs & Dialog',
      'Exploration',
      'Encounters & Combat',
      'Names & Details',
    ]));
  });
}
```

- [ ] **Step 2: Run** `flutter test test/screen_params_test.dart` — FAIL (GenSection undefined).

- [ ] **Step 3: Implement.**

`lib/features/generators_screen.dart`:
- Add at top level:

```dart
/// Activity grouping for the launcher; each generator lives in exactly one.
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
```

- Tag `_Gen` with a section: `const _Gen(this.label, this.section, this.run);`. Partition (every existing generator, no additions):
  - story: New Quest, New Scene, Random Event, Challenge, Pay the Price, Major Plot Twist, Plot Point, Random Idea, Immersion
  - npcs: NPC, NPC Behavior, NPC Behavior (Active), NPC Behavior (Passive), NPC Combat, NPC Plot Knowledge, Companion Response, NPC Dialog Topic
  - exploration: Settlement, Natural Hazard, Dungeon Name, Dungeon Room
  - encounters: Monster Encounter, Creature Tracks
  - details: Treasure, Name, Discover Meaning, Detail, Property
- Constructor: `const GeneratorsScreen({super.key, required this.oracle, this.section});` with `final GenSection? section;` — null shows everything (today's behavior, keeps existing tests valid).
- Static helper for tests/registry: `static List<String> labelsFor(GenSection s) => _gens.where((g) => g.section == s).map((g) => g.label).toList();` (make `_gens` static const-compatible as it already is).
- In `build`: filter `_gens` by `widget.section` when non-null. Crawl chips placement: the Crawl block (Wilderness Travel / Dungeon Linger / Reset Crawl chips + env line) renders only when `section == null || section == GenSection.exploration`; the NPC Dialog chip moves rendering to `section == null || section == GenSection.npcs`; the Abstract Icon chip renders under `section == null || section == GenSection.details`. Keep one shared `_last`/`_lastIcon` per screen instance (each launcher entry gets its own instance, so no cross-talk).
- Screen heading: `Text(widget.section?.label ?? 'Generators', ...)`.

`lib/features/fate_screen.dart`:
- Add `enum FateSection { fateCheck, rollHigh, mythic }` (top level) and `final FateSection? initialSection;` constructor param.
- Give the three section headers `GlobalKey`s (`_fateKey`, `_rollHighKey`, `_mythicKey`) attached to the existing header `Text` widgets. In `initState`, when `initialSection` is non-null, post-frame: `Scrollable.ensureVisible(key.currentContext!, duration: ...)` — guard `currentContext != null`.

`lib/features/tracker_screen.dart`:
- `DefaultTabController length: 2`; tabs Threads | Characters; remove the Journal tab and the `journal_screen.dart` import (JournalScreen is the home surface after Task 4 — tracker keeps zero journal responsibility).

- [ ] **Step 4: Run** `flutter test` — all green (existing journal_screen tests pump JournalScreen directly, unaffected).

- [ ] **Step 5: Commit** `git add -A lib test && git commit -m "feat: section params for fate/generators, tracker drops journal tab"`

### Task 2: Tool registry

**Files:**
- Create: `lib/shared/tool_registry.dart`
- Test: `test/tool_registry_test.dart`

- [ ] **Step 1: Failing tests** (`test/tool_registry_test.dart`):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/shared/tool_registry.dart';

void main() {
  test('ids unique, groups ordered, every tool in a known group', () {
    final tools = buildToolRegistry(family: ['classic', 'delve']);
    final ids = tools.map((t) => t.id).toList();
    expect(ids.toSet().length, ids.length);
    for (final t in tools) {
      expect(toolGroups, contains(t.group));
    }
  });

  test('moves tool present only when a family is enabled', () {
    expect(
        buildToolRegistry(family: []).any((t) => t.id == 'moves'), isFalse);
    expect(buildToolRegistry(family: ['starforged']).any((t) => t.id == 'moves'),
        isTrue);
  });

  test('expected entry count and core ids', () {
    final tools = buildToolRegistry(family: []);
    expect(tools.map((t) => t.id), containsAll([
      'fate-check', 'roll-high', 'mythic',
      'gen-story', 'gen-npcs', 'gen-exploration', 'gen-encounters',
      'gen-details', 'threads-characters', 'tables',
    ]));
  });
}
```

- [ ] **Step 2: Run** — FAIL (file missing).

- [ ] **Step 3: Implement** `lib/shared/tool_registry.dart`:

```dart
import 'package:flutter/material.dart';

import '../engine/oracle.dart';
import '../features/fate_screen.dart';
import '../features/generators_screen.dart';
import '../features/moves_screen.dart';
import '../features/tables_screen.dart';
import '../features/tracker_screen.dart';

/// A tool the launcher can summon over the journal.
class ToolDef {
  const ToolDef({
    required this.id,
    required this.label,
    required this.icon,
    required this.group,
    this.badge,
    required this.builder,
  });
  final String id;
  final String label;
  final IconData icon;
  final String group;
  /// Source-system badge shown in the launcher ('Juice', 'Mythic', …).
  final String? badge;
  /// Oracle is nullable so tests can inject self-contained fake tools;
  /// real builders use `o!`.
  final Widget Function(Oracle? oracle) builder;
}

/// Launcher group order (activity-based; see redesign spec phase 2).
const toolGroups = [
  'Ask the Oracle',
  'Story & Scenes',
  'NPCs & Dialog',
  'Exploration',
  'Encounters & Combat',
  'Names & Details',
  'Characters & Threads',
  'Reference',
];

/// Build the registry. [family] is the enabled Ironsworn family chain
/// (e.g. ['classic','delve']); empty = no Moves tool.
List<ToolDef> buildToolRegistry({required List<String> family}) => [
      ToolDef(
        id: 'fate-check',
        label: 'Fate Check',
        icon: Icons.help_outline,
        group: 'Ask the Oracle',
        badge: 'Juice',
        builder: (o) =>
            FateScreen(oracle: o!, initialSection: FateSection.fateCheck),
      ),
      ToolDef(
        id: 'roll-high',
        label: 'Roll High Oracle',
        icon: Icons.trending_up,
        group: 'Ask the Oracle',
        builder: (o) =>
            FateScreen(oracle: o, initialSection: FateSection.rollHigh),
      ),
      ToolDef(
        id: 'mythic',
        label: 'Mythic GME',
        icon: Icons.theater_comedy_outlined,
        group: 'Ask the Oracle',
        badge: 'Mythic',
        builder: (o) =>
            FateScreen(oracle: o, initialSection: FateSection.mythic),
      ),
      ToolDef(
        id: 'gen-story',
        label: 'Story & Scenes',
        icon: Icons.auto_stories_outlined,
        group: 'Story & Scenes',
        badge: 'Juice',
        builder: (o) =>
            GeneratorsScreen(oracle: o, section: GenSection.story),
      ),
      ToolDef(
        id: 'gen-npcs',
        label: 'NPCs & Dialog',
        icon: Icons.people_outline,
        group: 'NPCs & Dialog',
        badge: 'Juice',
        builder: (o) => GeneratorsScreen(oracle: o, section: GenSection.npcs),
      ),
      ToolDef(
        id: 'gen-exploration',
        label: 'Exploration & Crawl',
        icon: Icons.explore_outlined,
        group: 'Exploration',
        badge: 'Juice',
        builder: (o) =>
            GeneratorsScreen(oracle: o, section: GenSection.exploration),
      ),
      ToolDef(
        id: 'gen-encounters',
        label: 'Monsters & Tracks',
        icon: Icons.pets_outlined,
        group: 'Encounters & Combat',
        badge: 'Juice',
        builder: (o) =>
            GeneratorsScreen(oracle: o, section: GenSection.encounters),
      ),
      ToolDef(
        id: 'gen-details',
        label: 'Names & Details',
        icon: Icons.style_outlined,
        group: 'Names & Details',
        badge: 'Juice',
        builder: (o) =>
            GeneratorsScreen(oracle: o, section: GenSection.details),
      ),
      const ToolDef(
        id: 'threads-characters',
        label: 'Threads & Characters',
        icon: Icons.bookmarks_outlined,
        group: 'Characters & Threads',
        builder: _trackerBuilder,
      ),
      ToolDef(
        id: 'tables',
        label: 'Table Browser',
        icon: Icons.grid_view_outlined,
        group: 'Reference',
        badge: 'Juice',
        builder: (o) => TablesScreen(oracle: o),
      ),
      if (family.isNotEmpty)
        ToolDef(
          id: 'moves',
          label: family.contains('starforged')
              ? 'Starforged Moves & Oracles'
              : 'Ironsworn Moves & Oracles',
          icon: Icons.flash_on_outlined,
          group: 'Reference',
          badge: 'Ironsworn',
          builder: (_) => MovesScreen(rulesetIds: family),
        ),
    ];

Widget _trackerBuilder(Oracle _) => const TrackerScreen();
```

(If `const ToolDef` with a top-level function tear-off fights the analyzer, drop the `const` — not load-bearing.)

- [ ] **Step 4: Run** `flutter test` — green.
- [ ] **Step 5: Commit** `git commit -am "feat: declarative tool registry (activity groups, system badges)"`

### Task 3: ToolHost (panel + launcher + keep-alive) and MRU provider

**Files:**
- Create: `lib/shared/tool_host.dart`
- Modify: `lib/state/providers.dart` (append MRU notifier)
- Test: `test/tool_host_test.dart`

- [ ] **Step 1: Failing tests** (`test/tool_host_test.dart`) — uses an injected fake registry; the counter tool proves keep-alive:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/shared/tool_host.dart';
import 'package:juice_oracle/shared/tool_registry.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Counter extends StatefulWidget {
  const _Counter();
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int n = 0;
  @override
  Widget build(BuildContext context) => TextButton(
      onPressed: () => setState(() => n++), child: Text('count $n'));
}

void main() {
  final tools = [
    ToolDef(
        id: 'counter',
        label: 'Counter',
        icon: Icons.add,
        group: 'Reference',
        builder: (_) => const _Counter()),
    ToolDef(
        id: 'other',
        label: 'Other Tool',
        icon: Icons.circle,
        group: 'Reference',
        builder: (_) => const Text('other tool body')),
  ];

  Future<void> pump(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: Scaffold(
                body: ToolHost(
                    tools: tools, child: const Text('journal home'))))));
    await tester.pumpAndSettle();
  }

  testWidgets('launcher opens, search filters, tool opens', (tester) async {
    await pump(tester);
    expect(find.text('journal home'), findsOneWidget);
    ToolHost.openLauncher(tester.element(find.text('journal home')));
    await tester.pumpAndSettle();
    expect(find.text('Counter'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('tool-search')), 'other');
    await tester.pumpAndSettle();
    expect(find.text('Counter'), findsNothing);
    await tester.tap(find.text('Other Tool'));
    await tester.pumpAndSettle();
    expect(find.text('other tool body'), findsOneWidget);
  });

  testWidgets('tool state survives close and reopen', (tester) async {
    await pump(tester);
    ToolHost.openLauncher(tester.element(find.text('journal home')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Counter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('count 0'));
    await tester.pump();
    expect(find.text('count 1'), findsOneWidget);
    await tester.tap(find.byKey(const Key('tool-close')));
    await tester.pumpAndSettle();
    expect(find.text('journal home'), findsOneWidget);
    ToolHost.openLauncher(tester.element(find.text('journal home')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Counter'));
    await tester.pumpAndSettle();
    expect(find.text('count 1'), findsOneWidget); // state kept
  });

  testWidgets('opening a tool records it as most recently used',
      (tester) async {
    await pump(tester);
    ToolHost.openLauncher(tester.element(find.text('journal home')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Other Tool'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('juice.tools.mru.v1'), contains('other'));
  });
}
```

- [ ] **Step 2: Run** — FAIL (tool_host.dart missing).

- [ ] **Step 3: Implement.**

`lib/state/providers.dart` — append:

```dart
// -- Tool MRU (global, not session-scoped) ----------------------------------
class ToolMruNotifier extends AsyncNotifier<List<String>> {
  static const _key = 'juice.tools.mru.v1';
  static const _cap = 6;

  @override
  Future<List<String>> build() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    return (jsonDecode(raw) as List).cast<String>();
  }

  Future<void> record(String toolId) async {
    final current = [...(state.valueOrNull ?? const <String>[])];
    current.remove(toolId);
    current.insert(0, toolId);
    final capped = current.take(_cap).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(capped));
    state = AsyncData(capped);
  }
}

final toolMruProvider =
    AsyncNotifierProvider<ToolMruNotifier, List<String>>(ToolMruNotifier.new);
```

`lib/shared/tool_host.dart` — structure (implementer fleshes out styling; behavior is binding):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/oracle.dart';
import '../state/providers.dart';
import 'tool_registry.dart';

/// Hosts the journal [child] full-screen with a tool panel that opens over
/// it. Instantiated tools live in an always-mounted IndexedStack inside an
/// Offstage, so their state survives close/reopen within the session.
class ToolHost extends ConsumerStatefulWidget {
  const ToolHost({super.key, required this.tools, this.oracle, required this.child});
  final List<ToolDef> tools;
  final Oracle? oracle; // null only in tests with self-contained builders
  final Widget child;

  /// Open the launcher from anywhere below a ToolHost.
  static void openLauncher(BuildContext context) =>
      context.findAncestorStateOfType<_ToolHostState>()!._openLauncher();

  @override
  ConsumerState<ToolHost> createState() => _ToolHostState();
}

class _ToolHostState extends ConsumerState<ToolHost> {
  final List<String> _instantiated = []; // insertion-ordered tool ids
  String? _activeId; // tool showing; null = launcher view
  bool _open = false; // panel visible
  String _query = '';

  void _openLauncher() => setState(() {
        _open = true;
        _activeId = null;
        _query = '';
      });

  void _openTool(String id) {
    if (!_instantiated.contains(id)) _instantiated.add(id);
    ref.read(toolMruProvider.notifier).record(id);
    setState(() {
      _open = true;
      _activeId = id;
    });
  }

  void _close() => setState(() => _open = false);

  @override
  Widget build(BuildContext context) {
    // Stack: [ journal child, barrier+panel (Offstage when closed) ].
    // Panel geometry via LayoutBuilder: width >= 840 -> right-aligned,
    // width 400, full height; else bottom-aligned, full width, 85% height.
    // Panel content: header row [
    //   if (_activeId != null) IconButton(back -> setState _activeId = null),
    //   Expanded(Text(title)),
    //   IconButton(key: Key('tool-close'), Icons.close, onPressed: _close)
    // ] + Expanded(body).
    // Body when _activeId == null: _LauncherView (search field
    // key: Key('tool-search'), MRU row from toolMruProvider filtered to
    // known ids, grouped ListTiles in toolGroups order, badge chips,
    // filtered by _query case-insensitively on label+group).
    // Body when _activeId != null: IndexedStack(
    //   index: _instantiated.indexOf(_activeId!),
    //   children: [for (final id in _instantiated)
    //     widget.tools.firstWhere((t) => t.id == id).builder(widget.oracle!)],
    // )
    // CRITICAL: the IndexedStack must be in the tree even when _open is
    // false (wrap panel in Offstage(offstage: !_open)) so tool state
    // survives close. The builder runs once per id thanks to the stable
    // _instantiated order — builders are invoked on each build but the
    // Element tree is keyed by position+type, preserving State. To make
    // identity explicit, give each child a ValueKey(id).
    ...
  }
}
```

Note on `oracle`: `ToolDef.builder` is `Widget Function(Oracle? oracle)` (defined that way in Task 2); real registry builders use `o!` (e.g. `(o) => FateScreen(oracle: o!, ...)`); test builders ignore the param. Make the State class public from the start: `class ToolHostState extends ConsumerState<ToolHost>` with public `openLauncher()` and `openTool(String id)` methods, so Task 4 can drive it via `GlobalKey<ToolHostState>`; the static `ToolHost.openLauncher(context)` helper (findAncestorStateOfType) stays for tests.

A barrier GestureDetector behind the panel calls `_close()` on tap (desktop side-panel mode and sheet mode both).

- [ ] **Step 4: Run** `flutter test` — green.
- [ ] **Step 5: Commit** `git commit -am "feat: ToolHost panel with keep-alive tools, searchable launcher, MRU"`

### Task 4: HomeShell swap

**Files:**
- Modify: `lib/shared/home_shell.dart`
- Test: `test/home_shell_test.dart` (new)

- [ ] **Step 1: Failing test** (`test/home_shell_test.dart`):

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/shared/home_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('journal is home; launcher opens grouped tools',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final data = OracleData(jsonDecode(
            File('assets/oracle_data.json').readAsStringSync())
        as Map<String, dynamic>);
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(home: HomeShell(oracle: Oracle(data)))));
    await tester.pumpAndSettle();
    // Journal home: composer visible, no NavigationBar.
    expect(find.byKey(const Key('journal-composer')), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    // Launcher.
    await tester.tap(find.byTooltip('Tools'));
    await tester.pumpAndSettle();
    expect(find.text('Ask the Oracle'), findsOneWidget);
    expect(find.text('Fate Check'), findsOneWidget);
    // Open a tool.
    await tester.tap(find.text('Fate Check'));
    await tester.pumpAndSettle();
    expect(find.text('Roll Fate Check'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run** — FAIL (no Tools button; NavigationBar present).

- [ ] **Step 3: Implement** in `home_shell.dart`:
- Delete `_index`, `pages`, `IndexedStack`, `NavigationBar`, and the now-unused feature-screen imports except what the registry needs (registry imports the screens itself).
- `body: SafeArea(child: ToolHost(tools: buildToolRegistry(family: family), oracle: widget.oracle, child: const JournalScreen()))`.
- Keep `family` computation where it is (rulesets watch) so the registry rebuilds when rulesets change. ToolHost must tolerate a changed `tools` list across rebuilds: when an instantiated id no longer exists in `tools` (moves toggled off), drop it from `_instantiated` (and clear `_activeId` if it pointed there) — add this reconciliation in `didUpdateWidget` in Task 3's file if not already handled; cover with a registry-swap widget test if trivial, else note it.
- App-bar actions: prepend `IconButton(icon: Icon(Icons.handyman_outlined), tooltip: 'Tools', onPressed: ...)` that calls `ToolHost.openLauncher` — needs a context below the ToolHost; simplest is giving ToolHost a `GlobalKey<State>` exposed via a `toolHostKey` or making openLauncher take the state: use a `final _hostKey = GlobalKey();` on the shell, pass `key: _hostKey` to ToolHost, and have the button call `(_hostKey.currentState as dynamic)._openLauncher()` — NO. Cleaner (binding): add to ToolHost a public `static ToolHostController? maybeOf(BuildContext)`? Simplest robust approach: expose `class ToolHostState` (make the state class public, `ToolHost.createState() => ToolHostState()`), give the shell `final _hostKey = GlobalKey<ToolHostState>();`, button calls `_hostKey.currentState?.openLauncher()` (make `openLauncher`/`openTool` public methods on the state). Adjust Task 3 visibility accordingly (public state class with public `openLauncher`; the static `ToolHost.openLauncher(context)` helper stays for tests).
- Rulesets and Campaigns app-bar buttons unchanged.

- [ ] **Step 4: Run** `flutter test` — green; `flutter analyze --no-fatal-infos` — no new infos.
- [ ] **Step 5: Commit** `git commit -am "feat: journal-first shell — NavigationBar out, tool launcher in"`

### Task 5: Verify, docs, ship (controller-run)

- [ ] Full gates: `flutter analyze --no-fatal-infos` (no new infos), `flutter test`, `python3 build_oracle.py`, `flutter build web`.
- [ ] Browser verify on built web: journal home renders; Tools button → launcher groups; open Fate Check → roll → Add to journal → entry lands in home journal; close panel; reopen → result card still shown (keep-alive); narrow viewport (preview_resize mobile) → sheet layout. Composer typing headless-impossible — covered by widget tests; disclose in PR.
- [ ] Docs: README architecture line (`shared/ theme, result card, home shell (journal + tool launcher)`, drop "NavigationBar + IndexedStack"); CLAUDE.md lean-stack line "no router (4-tab IndexedStack)" → "no router (journal shell + tool panel)". ROADMAP phase 2 row → Done.
- [ ] PR `feat/shell-swap`, wait CI green, squash-merge, verify deploy + live smoke.
