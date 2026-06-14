# Home Tabbed Shell Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the slide-over tool launcher with a persistent five-section tabbed shell (Journal · Maps · Party · Tracking · Oracles & Tables), promote the dice roller onto the journal entry line, and add two new Tracking features (Rumors, progress Tracks).

**Architecture:** A `HomeShell` Scaffold drives an adaptive `NavigationBar`(mobile)/`NavigationRail`(wide) over a keep-alive `IndexedStack` of five destination roots. A reusable `SubtabHost` (TabBar + `IndexedStack`, never `TabBarView`) renders each destination's subtabs and honours deep-link subtab requests. A Riverpod `shellRouteProvider` holds the selected `(Destination, subtabKey)` and exposes `openTool(id)`, replacing `ToolHost.openToolIfKnown`. New `Rumor`/`Track` models follow the existing `_PersistedList<T>` + session-scoped SharedPreferences pattern; campaign export bumps to schema v3.

**Tech Stack:** Flutter, `flutter_riverpod`, `shared_preferences`. No new dependencies.

---

## Reference: spec

Design: `docs/superpowers/specs/2026-06-13-home-tabbed-shell-design.md`. Read it before starting.

## Conventions (apply to every task)

- Run the single test with `flutter test test/<file>.dart` (add `-p` plain name where noted). Full suite: `flutter test`. Analyze: `flutter analyze` (must end "No issues found!").
- `dart format` runs on save via the repo hook; commit formatted code.
- Commit message trailer (last line of every commit body):
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`
- This work happens on a feature branch (created in Task 0), never on `main`.
- Freeze rule: subtab bodies use `IndexedStack`, never `TabBarView`; never put a bare Material text/segmented button as a non-flex `Row` child beside a flex sibling (wrap in `Flexible`). See `juice-toolhost-loose-constraints` memory.

## File structure

**New files**
- `lib/shared/destination.dart` — `Destination` enum, per-destination metadata, `toolLocation` map (id → `(Destination, String subtabKey)`).
- `lib/shared/shell_route.dart` — `ShellRoute` value + `ShellRouteNotifier` + `shellRouteProvider` (holds selection, `goTo`, `openTool`).
- `lib/shared/subtab_host.dart` — generic `SubtabHost` widget (filtered subtabs + deep-link selection).
- `lib/shared/dice_sheet.dart` — `showDiceSheet(context, dice)` modal bottom sheet wrapping `DiceRollerScreen`.
- `lib/features/maps_tab.dart` — Maps destination root (World/Dungeon/Journey).
- `lib/features/party_tab.dart` — Party destination root (Emulator/Sidekick/Behavior).
- `lib/features/oracles_tab.dart` — Oracles & Tables destination root (Oracle/Generators/Tables/Moves).
- `lib/features/tracking_tab.dart` — Tracking destination root (Scenes/NPCs/Threads/Rumors/Tracks/Encounter).
- `lib/features/scenes_pane.dart` — Tracking → Scenes (derived from journal).
- `lib/features/rumors_pane.dart` — Tracking → Rumors (new feature UI).
- `lib/features/tracks_pane.dart` — Tracking → Tracks (new feature UI).
- `lib/shared/tool_search_sheet.dart` — global "jump to tool" sheet (extracted launcher list).

**Modified files**
- `lib/engine/models.dart` — add `Rumor`, `Track`.
- `lib/state/providers.dart` — add `RumorNotifier`/`rumorsProvider`, `TrackNotifier`/`tracksProvider`; add their keys to `sessionScopedKeys`.
- `lib/state/campaign_io.dart` — schema v3 + validation branches for the two keys.
- `lib/shared/tool_registry.dart` — keep `ToolDef`/builders/`toolSystem`; `toolGroups`/`group` retained only for the search sheet grouping.
- `lib/features/map_screen.dart` — promote `_HexTab`→`HexMapPane`, `_DungeonTab`→`DungeonMapPane` (public); `MapScreen` itself becomes thin/removed (superseded by `maps_tab.dart`).
- `lib/features/tracker_screen.dart` — promote `_ThreadsTab`→`ThreadsPane`, `_CharactersTab`→`CharactersPane` (public); `TrackerScreen` removed (superseded by `tracking_tab.dart`).
- `lib/features/journal_screen.dart` — rewire 7 deep-links to `shellRouteProvider.openTool`/`openHelp`; composer scene button → dice sheet.
- `lib/shared/home_shell.dart` — replace `ToolHost` body with adaptive nav + IndexedStack; add Search AppBar action.
- Delete `lib/shared/tool_host.dart` (after extracting the search sheet).
- Tests: `test/tool_host_test.dart` (replace), `test/home_shell_test.dart` (rewrite nav), `test/journal_payload_ui_test.dart` (open-in-tool now navigates).

---

# Phase 1 — Shell scaffold

Goal: adaptive nav + five destination roots in a keep-alive IndexedStack, Journal unchanged, deep-link plumbing in place. Overlay still present but unused by new nav.

### Task 0: Branch

- [ ] **Step 1: Create the feature branch**

```bash
git checkout main && git pull --ff-only
git checkout -b feat/tabbed-shell
```

- [ ] **Step 2: Commit the spec (currently uncommitted on main → bring onto branch)**

```bash
git add docs/superpowers/specs/2026-06-13-home-tabbed-shell-design.md docs/superpowers/plans/2026-06-13-home-tabbed-shell.md
git commit -m "docs: home tabbed shell spec + plan"
```

### Task 1: Destination model

**Files:**
- Create: `lib/shared/destination.dart`
- Test: `test/destination_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice/shared/destination.dart';

void main() {
  test('toolLocation maps tools to destination + subtab key', () {
    expect(toolLocation['verdant'], (Destination.maps, 'journey'));
    expect(toolLocation['encounter'], (Destination.tracking, 'encounter'));
    expect(toolLocation['tables'], (Destination.oracles, 'tables'));
    expect(toolLocation['gen-npcs'], (Destination.oracles, 'generators'));
    // dice has no tab home (entry line + modal)
    expect(toolLocation.containsKey('dice'), isFalse);
  });

  test('every destination has display metadata', () {
    for (final d in Destination.values) {
      expect(destinationMeta[d], isNotNull);
    }
  });
}
```

- [ ] **Step 2: Run, expect FAIL** — `flutter test test/destination_test.dart` → "Target of URI doesn't exist".

- [ ] **Step 3: Implement**

```dart
import 'package:flutter/material.dart';

/// Top-level sections of the home shell.
enum Destination { journal, maps, party, tracking, oracles }

class DestinationMeta {
  const DestinationMeta(this.label, this.icon);
  final String label;
  final IconData icon;
}

const destinationMeta = <Destination, DestinationMeta>{
  Destination.journal: DestinationMeta('Journal', Icons.book_outlined),
  Destination.maps: DestinationMeta('Maps', Icons.map_outlined),
  Destination.party: DestinationMeta('Party', Icons.groups_outlined),
  Destination.tracking: DestinationMeta('Tracking', Icons.checklist_outlined),
  Destination.oracles: DestinationMeta('Oracles', Icons.casino_outlined),
};

/// Registry tool id -> (destination, subtab key). Tools absent here have no
/// tab home (e.g. 'dice' lives on the entry line; 'help' opens as a route).
const toolLocation = <String, (Destination, String)>{
  'maps': (Destination.maps, 'world'),
  'verdant': (Destination.maps, 'journey'),
  'party-emulator': (Destination.party, 'emulator'),
  'sidekick-dialogue': (Destination.party, 'sidekick'),
  'behavior-tables': (Destination.party, 'behavior'),
  'threads-characters': (Destination.tracking, 'npcs'),
  'encounter': (Destination.tracking, 'encounter'),
  'fate-check': (Destination.oracles, 'oracle'),
  'roll-high': (Destination.oracles, 'oracle'),
  'mythic': (Destination.oracles, 'oracle'),
  'gen-story': (Destination.oracles, 'generators'),
  'gen-npcs': (Destination.oracles, 'generators'),
  'gen-exploration': (Destination.oracles, 'generators'),
  'gen-encounters': (Destination.oracles, 'generators'),
  'gen-details': (Destination.oracles, 'generators'),
  'tables': (Destination.oracles, 'tables'),
  'moves': (Destination.oracles, 'moves'),
};
```

- [ ] **Step 4: Run, expect PASS.**

- [ ] **Step 5: Commit** — `feat: destination model + tool location map`.

### Task 2: Shell route provider

**Files:**
- Create: `lib/shared/shell_route.dart`
- Test: `test/shell_route_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:juice/shared/destination.dart';
import 'package:juice/shared/shell_route.dart';

void main() {
  test('default route is journal', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(shellRouteProvider).destination, Destination.journal);
  });

  test('openTool resolves a mapped id to destination + subtab', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final handled = c.read(shellRouteProvider.notifier).openTool('verdant');
    expect(handled, isTrue);
    expect(c.read(shellRouteProvider).destination, Destination.maps);
    expect(c.read(shellRouteProvider).subtab, 'journey');
  });

  test('openTool returns false for an unmapped id', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(shellRouteProvider.notifier).openTool('dice'), isFalse);
    expect(c.read(shellRouteProvider).destination, Destination.journal);
  });

  test('goTo sets destination and subtab', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(shellRouteProvider.notifier).goTo(Destination.tracking, subtab: 'rumors');
    expect(c.read(shellRouteProvider).destination, Destination.tracking);
    expect(c.read(shellRouteProvider).subtab, 'rumors');
  });
}
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'destination.dart';

class ShellRoute {
  const ShellRoute(this.destination, this.subtab);
  final Destination destination;
  /// Requested subtab key (empty = the destination's first/default subtab).
  final String subtab;
}

class ShellRouteNotifier extends Notifier<ShellRoute> {
  @override
  ShellRoute build() => const ShellRoute(Destination.journal, '');

  void goTo(Destination destination, {String subtab = ''}) {
    state = ShellRoute(destination, subtab);
  }

  /// Navigates to the tool's home. Returns false (no-op) for ids with no tab
  /// home, so callers can fall back (e.g. dice sheet, snackbar).
  bool openTool(String id) {
    final loc = toolLocation[id];
    if (loc == null) return false;
    state = ShellRoute(loc.$1, loc.$2);
    return true;
  }
}

final shellRouteProvider =
    NotifierProvider<ShellRouteNotifier, ShellRoute>(ShellRouteNotifier.new);
```

- [ ] **Step 4: Run, expect PASS.**

- [ ] **Step 5: Commit** — `feat: shell route provider with openTool`.

### Task 3: SubtabHost widget

**Files:**
- Create: `lib/shared/subtab_host.dart`
- Test: `test/subtab_host_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:juice/shared/destination.dart';
import 'package:juice/shared/shell_route.dart';
import 'package:juice/shared/subtab_host.dart';

Widget _host() => ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: SubtabHost(
            destination: Destination.tracking,
            tabs: const [
              SubtabDef('a', 'Alpha'),
              SubtabDef('b', 'Beta'),
            ],
            children: const [Text('PANE A'), Text('PANE B')],
          ),
        ),
      ),
    );

void main() {
  testWidgets('renders first subtab by default', (t) async {
    await t.pumpWidget(_host());
    expect(find.text('PANE A'), findsOneWidget);
  });

  testWidgets('switching tab shows the other pane (IndexedStack keep-alive)',
      (t) async {
    await t.pumpWidget(_host());
    await t.tap(find.text('Beta'));
    await t.pumpAndSettle();
    expect(find.text('PANE B'), findsOneWidget);
  });

  testWidgets('a shellRoute request selects the matching subtab', (t) async {
    late WidgetRef capturedRef;
    await t.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(builder: (context, ref, _) {
            capturedRef = ref;
            return const SubtabHost(
              destination: Destination.tracking,
              tabs: [SubtabDef('a', 'Alpha'), SubtabDef('b', 'Beta')],
              children: [Text('PANE A'), Text('PANE B')],
            );
          }),
        ),
      ),
    ));
    capturedRef.read(shellRouteProvider.notifier).goTo(Destination.tracking, subtab: 'b');
    await t.pumpAndSettle();
    expect(find.text('PANE B'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'destination.dart';
import 'shell_route.dart';

class SubtabDef {
  const SubtabDef(this.key, this.label);
  final String key;
  final String label;
}

/// A destination root: a [TabBar] over an [IndexedStack] body (never a
/// TabBarView — see the loose-constraint freeze rule). Honours
/// [shellRouteProvider] subtab requests aimed at [destination].
class SubtabHost extends ConsumerStatefulWidget {
  const SubtabHost({
    super.key,
    required this.destination,
    required this.tabs,
    required this.children,
    this.scrollable = false,
  });

  final Destination destination;
  final List<SubtabDef> tabs;
  final List<Widget> children;
  final bool scrollable;

  @override
  ConsumerState<SubtabHost> createState() => _SubtabHostState();
}

class _SubtabHostState extends ConsumerState<SubtabHost>
    with TickerProviderStateMixin {
  late TabController _controller =
      TabController(length: widget.tabs.length, vsync: this);

  @override
  void didUpdateWidget(SubtabHost old) {
    super.didUpdateWidget(old);
    if (old.tabs.length != widget.tabs.length) {
      _controller.dispose();
      _controller = TabController(length: widget.tabs.length, vsync: this);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _applyRoute(ShellRoute route) {
    if (route.destination != widget.destination || route.subtab.isEmpty) return;
    final i = widget.tabs.indexWhere((t) => t.key == route.subtab);
    if (i >= 0 && i != _controller.index) _controller.index = i;
  }

  @override
  Widget build(BuildContext context) {
    // Apply a request that arrived while this host was offstage.
    _applyRoute(ref.read(shellRouteProvider));
    ref.listen(shellRouteProvider, (_, next) => _applyRoute(next));
    final theme = Theme.of(context);
    return Column(
      children: [
        Material(
          color: theme.colorScheme.surface,
          child: TabBar(
            controller: _controller,
            isScrollable: widget.scrollable,
            tabs: [for (final t in widget.tabs) Tab(text: t.label)],
          ),
        ),
        Expanded(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => IndexedStack(
              index: _controller.index,
              children: widget.children,
            ),
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run, expect PASS.**

- [ ] **Step 5: Commit** — `feat: SubtabHost (TabBar + IndexedStack + deep-link subtab)`.

### Task 4: Adaptive shell body (Journal-only roots placeholder)

**Files:**
- Modify: `lib/shared/home_shell.dart`
- Test: `test/home_shell_test.dart` (rewrite — see Step 1)

- [ ] **Step 1: Write the failing test** (replace the file's body with shell-nav tests)

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:juice/shared/home_shell.dart';
import 'package:juice/engine/oracle.dart';
import 'package:juice/engine/oracle_data.dart';

void main() {
  testWidgets('shell shows five nav destinations and opens on Journal',
      (t) async {
    final oracle = Oracle(await OracleData.load());
    await t.pumpWidget(ProviderScope(
      child: MaterialApp(home: HomeShell(oracle: oracle)),
    ));
    await t.pumpAndSettle();
    for (final label in ['Journal', 'Maps', 'Party', 'Tracking', 'Oracles']) {
      expect(find.text(label), findsWidgets);
    }
    // Journal composer is visible by default.
    expect(find.byKey(const Key('journal-composer')), findsOneWidget);
  });

  testWidgets('tapping Maps switches the body', (t) async {
    final oracle = Oracle(await OracleData.load());
    await t.pumpWidget(ProviderScope(
      child: MaterialApp(home: HomeShell(oracle: oracle)),
    ));
    await t.pumpAndSettle();
    await t.tap(find.text('Maps').first);
    await t.pumpAndSettle();
    // World subtab tab label present once Maps root is shown.
    expect(find.text('World'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run, expect FAIL** (HomeShell still renders ToolHost/journal only).

- [ ] **Step 3: Implement** — in `home_shell.dart`, replace the `body: SafeArea(child: ToolHost(...))` with the adaptive nav. Add imports for `destination.dart`, `shell_route.dart`, the four destination-root widgets (created in Phase 2 — for Phase 1 use placeholders), and `flutter/material`. Replace the build's `body:` and keep the AppBar.

Add this helper inside `_HomeShellState` and use it as the Scaffold body:

```dart
Widget _shellBody(BuildContext context, List<String> family, Set<String> systems) {
  final route = ref.watch(shellRouteProvider);
  final destinations = _visibleDestinations(systems, family);
  final index = destinations.indexOf(route.destination).clamp(0, destinations.length - 1);
  final roots = [
    for (final d in destinations) _root(d, systems, family),
  ];
  final body = IndexedStack(index: index, children: roots);
  return LayoutBuilder(builder: (context, c) {
    final wide = c.maxWidth >= 840;
    final navDestinations = [
      for (final d in destinations)
        (icon: destinationMeta[d]!.icon, label: destinationMeta[d]!.label),
    ];
    if (wide) {
      return Row(children: [
        NavigationRail(
          selectedIndex: index,
          onDestinationSelected: (i) =>
              ref.read(shellRouteProvider.notifier).goTo(destinations[i]),
          labelType: NavigationRailLabelType.all,
          destinations: [
            for (final n in navDestinations)
              NavigationRailDestination(icon: Icon(n.icon), label: Text(n.label)),
          ],
        ),
        const VerticalDivider(width: 1),
        Expanded(child: body),
      ]);
    }
    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) =>
            ref.read(shellRouteProvider.notifier).goTo(destinations[i]),
        destinations: [
          for (final n in navDestinations)
            NavigationDestination(icon: Icon(n.icon), label: n.label),
        ],
      ),
    );
  });
}

List<Destination> _visibleDestinations(Set<String> systems, List<String> family) =>
    Destination.values; // Phase 1: all five. Phase 2 filters by systems.

Widget _root(Destination d, Set<String> systems, List<String> family) {
  switch (d) {
    case Destination.journal:
      return const JournalScreen();
    case Destination.maps:
      return MapsTab(oracle: widget.oracle); // Phase 2
    case Destination.party:
      return const PartyTab(); // Phase 2
    case Destination.tracking:
      return const TrackingTab(); // Phase 2
    case Destination.oracles:
      return OraclesTab(oracle: widget.oracle, family: family); // Phase 2
  }
}
```

For Phase 1, stub the four `*Tab` widgets minimally so the shell compiles and the Maps test passes. Create them now as real files but with just their `SubtabHost` skeleton + one placeholder pane each; Phase 2 fills the panes. Example `lib/features/maps_tab.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../engine/oracle.dart';
import '../shared/destination.dart';
import '../shared/subtab_host.dart';

class MapsTab extends ConsumerWidget {
  const MapsTab({super.key, required this.oracle});
  final Oracle oracle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const SubtabHost(
      destination: Destination.maps,
      tabs: [
        SubtabDef('world', 'World'),
        SubtabDef('dungeon', 'Dungeon'),
        SubtabDef('journey', 'Journey'),
      ],
      children: [
        Center(child: Text('World')),
        Center(child: Text('Dungeon')),
        Center(child: Text('Journey')),
      ],
    );
  }
}
```

Create equivalent skeletons for `party_tab.dart` (PartyTab: emulator/sidekick/behavior), `oracles_tab.dart` (OraclesTab: oracle/generators/tables/moves), `tracking_tab.dart` (TrackingTab: scenes/npcs/threads/rumors/tracks/encounter, `scrollable: true`). Wire `_shellBody` into the Scaffold `body:` in `build()`.

Keep the existing AppBar and its actions unchanged in this task. Leave `ToolHost` import + `_hostKey` in place but unused (removed in Task 9); the Tools AppBar button stays for now.

- [ ] **Step 4: Run** — `flutter test test/home_shell_test.dart`, expect PASS. Then `flutter analyze`.

- [ ] **Step 5: Commit** — `feat: adaptive tabbed shell scaffold (Journal live, tabs stubbed)`.

---

# Phase 2 — Relocate tools + retire launcher

Goal: real panes in every destination; deep-links navigate; global search sheet; overlay deleted.

### Task 5: Promote Maps panes + fill Maps tab (add Journey)

**Files:**
- Modify: `lib/features/map_screen.dart` (promote panes)
- Modify: `lib/features/maps_tab.dart`
- Test: `test/maps_tab_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:juice/features/maps_tab.dart';
import 'package:juice/engine/oracle.dart';
import 'package:juice/engine/oracle_data.dart';

void main() {
  testWidgets('Maps tab shows World/Dungeon/Journey and a real hex pane',
      (t) async {
    final oracle = Oracle(await OracleData.load());
    await t.pumpWidget(ProviderScope(
      child: MaterialApp(home: Scaffold(body: MapsTab(oracle: oracle))),
    ));
    await t.pumpAndSettle();
    expect(find.text('World'), findsOneWidget);
    expect(find.text('Dungeon'), findsOneWidget);
    expect(find.text('Journey'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run, expect FAIL** (Journey pane is still the placeholder Text).

- [ ] **Step 3: Implement**
  - In `map_screen.dart`: rename `class _HexTab` → `class HexMapPane`, `class _DungeonTab` → `class DungeonMapPane` (and their `_HexTabState`/`_DungeonTabState` → public-friendly `HexMapPaneState`/`DungeonMapPaneState`); update internal references. Delete the now-unused `MapScreen` widget and its `DefaultTabController` build (superseded). Keep the panes' constructors `({required Oracle oracle})`.
  - In `maps_tab.dart`: replace placeholder children with `HexMapPane(oracle: oracle)`, `DungeonMapPane(oracle: oracle)`, `VerdantScreen(oracle: oracle)` (import `verdant_screen.dart`). Make `MapsTab` build the children list (non-const).

- [ ] **Step 4: Run, expect PASS;** then `flutter analyze`.

- [ ] **Step 5: Commit** — `feat: Maps tab with World/Dungeon/Journey panes`.

### Task 6: Fill Party + Oracles tabs

**Files:**
- Modify: `lib/features/party_tab.dart`, `lib/features/oracles_tab.dart`
- Test: `test/party_oracles_tab_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:juice/features/party_tab.dart';
import 'package:juice/features/oracles_tab.dart';
import 'package:juice/engine/oracle.dart';
import 'package:juice/engine/oracle_data.dart';

void main() {
  testWidgets('Party tab shows the three party subtabs', (t) async {
    await t.pumpWidget(const ProviderScope(
      child: MaterialApp(home: Scaffold(body: PartyTab())),
    ));
    await t.pumpAndSettle();
    expect(find.text('Emulator'), findsOneWidget);
    expect(find.text('Sidekick'), findsOneWidget);
    expect(find.text('Behavior'), findsOneWidget);
  });

  testWidgets('Oracles tab shows Oracle/Generators/Tables', (t) async {
    final oracle = Oracle(await OracleData.load());
    await t.pumpWidget(ProviderScope(
      child: MaterialApp(home: Scaffold(body: OraclesTab(oracle: oracle, family: const []))),
    ));
    await t.pumpAndSettle();
    expect(find.text('Oracle'), findsOneWidget);
    expect(find.text('Generators'), findsOneWidget);
    expect(find.text('Tables'), findsOneWidget);
    // Moves hidden with empty family.
    expect(find.text('Moves'), findsNothing);
  });
}
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement**
  - `party_tab.dart`: children = `PartyEmulatorScreen()`, `SidekickScreen()`, `BehaviorTablesScreen()`.
  - `oracles_tab.dart`: build subtab list dynamically. Always: `SubtabDef('oracle','Oracle')` → a small column of three buttons/`FateScreen` sections (use `FateScreen(oracle: oracle, initialSection: FateSection.fateCheck)` as the Oracle pane — it already has its own internal section switch), `SubtabDef('generators','Generators')` → `GeneratorsScreen(oracle: oracle, section: GenSection.story)` (it has its own section switcher), `SubtabDef('tables','Tables')` → `TablesScreen(oracle: oracle)`. Append Moves only if `family.isNotEmpty`: `SubtabDef('moves','Moves')` → `MovesScreen(rulesetIds: family)`. Children list must match tabs list length/order.

  Note: `FateScreen` and `GeneratorsScreen` already expose all their sections via internal controls, so a single instance per pane is correct — do not create one subtab per section.

- [ ] **Step 4: Run, expect PASS;** `flutter analyze`.

- [ ] **Step 5: Commit** — `feat: Party and Oracles & Tables tabs`.

### Task 7: Scenes pane

**Files:**
- Create: `lib/features/scenes_pane.dart`
- Test: `test/scenes_pane_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice/features/scenes_pane.dart';
import 'package:juice/state/providers.dart';
import 'package:juice/shared/shell_route.dart';
import 'package:juice/shared/destination.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('lists scenes and a New scene action', (t) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(journalProvider.future);
    await c.read(journalProvider.notifier).addScene('The Crossing');
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: ScenesPane())),
    ));
    await t.pumpAndSettle();
    expect(find.text('The Crossing'), findsOneWidget);
    expect(find.byKey(const Key('scenes-new')), findsOneWidget);
  });

  testWidgets('tapping a scene navigates to Journal', (t) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(journalProvider.future);
    await c.read(journalProvider.notifier).addScene('The Crossing');
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: ScenesPane())),
    ));
    await t.pumpAndSettle();
    await t.tap(find.text('The Crossing'));
    await t.pumpAndSettle();
    expect(c.read(shellRouteProvider).destination, Destination.journal);
  });
}
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../engine/models.dart';
import '../shared/destination.dart';
import '../shared/shell_route.dart';
import '../state/providers.dart';

/// Tracking → Scenes: derived list of journal scene dividers, newest first.
class ScenesPane extends ConsumerWidget {
  const ScenesPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(journalProvider).valueOrNull ?? const <JournalEntry>[];
    final scenes = entries.where((e) => e.kind == JournalKind.scene).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text('Scenes',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              Flexible(
                child: FilledButton.tonalIcon(
                  key: const Key('scenes-new'),
                  icon: const Icon(Icons.add),
                  label: const Text('New scene'),
                  onPressed: () => _newScene(context, ref),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: scenes.isEmpty
              ? const Center(child: Text('No scenes yet.'))
              : ListView(
                  children: [
                    for (final s in scenes)
                      ListTile(
                        leading: const Icon(Icons.movie_outlined),
                        title: Text(s.title),
                        subtitle: s.chaosFactor != null
                            ? Text('Chaos ${s.chaosFactor}')
                            : null,
                        onTap: () => ref
                            .read(shellRouteProvider.notifier)
                            .goTo(Destination.journal),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Future<void> _newScene(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
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
    await ref.read(journalProvider.notifier).addScene(
          title.trim(),
          chaosFactor: ref.read(crawlProvider).valueOrNull?.chaosFactor,
        );
  }
}
```

- [ ] **Step 4: Run, expect PASS.**

- [ ] **Step 5: Commit** — `feat: Tracking Scenes pane`.

### Task 8: Promote tracker panes + assemble Tracking tab

**Files:**
- Modify: `lib/features/tracker_screen.dart` (promote panes)
- Modify: `lib/features/tracking_tab.dart`
- Test: `test/tracking_tab_test.dart`

> Rumors/Tracks panes don't exist until Phase 4/5. For this task, use placeholder `Center(Text('Rumors'))`/`Center(Text('Tracks'))` children for those two subtabs; replace them in Tasks 14/16.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice/features/tracking_tab.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Tracking shows all six subtabs', (t) async {
    await t.pumpWidget(const ProviderScope(
      child: MaterialApp(home: Scaffold(body: TrackingTab())),
    ));
    await t.pumpAndSettle();
    for (final label in ['Scenes', 'NPCs', 'Threads', 'Rumors', 'Tracks', 'Encounter']) {
      expect(find.text(label), findsOneWidget);
    }
  });
}
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement**
  - In `tracker_screen.dart`: rename `class _ThreadsTab` → `class ThreadsPane`, `class _CharactersTab` → `class CharactersPane` (+ their State classes); update references. Delete the `TrackerScreen` widget + its `DefaultTabController` build (superseded). Keep both panes' const constructors.
  - `tracking_tab.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../shared/destination.dart';
import '../shared/subtab_host.dart';
import 'tracker_screen.dart';
import 'scenes_pane.dart';
import 'encounter_screen.dart';

class TrackingTab extends ConsumerWidget {
  const TrackingTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const SubtabHost(
      destination: Destination.tracking,
      scrollable: true,
      tabs: [
        SubtabDef('scenes', 'Scenes'),
        SubtabDef('npcs', 'NPCs'),
        SubtabDef('threads', 'Threads'),
        SubtabDef('rumors', 'Rumors'),
        SubtabDef('tracks', 'Tracks'),
        SubtabDef('encounter', 'Encounter'),
      ],
      children: [
        ScenesPane(),
        CharactersPane(),
        ThreadsPane(),
        Center(child: Text('Rumors')),
        Center(child: Text('Tracks')),
        EncounterScreen(),
      ],
    );
  }
}
```

- [ ] **Step 4: Run, expect PASS;** `flutter analyze`.

- [ ] **Step 5: Commit** — `feat: Tracking tab (Scenes/NPCs/Threads/Encounter + new-feature placeholders)`.

### Task 9: Global search sheet + retire ToolHost

**Files:**
- Create: `lib/shared/tool_search_sheet.dart`
- Create: `lib/shared/dice_sheet.dart`
- Modify: `lib/shared/home_shell.dart` (Search action; remove ToolHost)
- Modify: `lib/features/journal_screen.dart` (rewire deep-links)
- Delete: `lib/shared/tool_host.dart`
- Modify/Replace: `test/tool_host_test.dart` → `test/tool_search_sheet_test.dart`
- Test: also update `test/journal_payload_ui_test.dart`

- [ ] **Step 1: Write the failing test** (`test/tool_search_sheet_test.dart`)

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice/shared/tool_search_sheet.dart';
import 'package:juice/shared/shell_route.dart';
import 'package:juice/shared/destination.dart';
import 'package:juice/shared/tool_registry.dart';
import 'package:juice/engine/models.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('search filters and tapping a tool navigates', (t) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final tools = buildToolRegistry(family: const [], systems: kAllSystems);
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) {
            return ElevatedButton(
              onPressed: () => showToolSearchSheet(context, tools),
              child: const Text('open'),
            );
          }),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('tool-search')), 'verdant');
    await t.pumpAndSettle();
    await t.tap(find.text('Verdant Journey'));
    await t.pumpAndSettle();
    expect(c.read(shellRouteProvider).destination, Destination.maps);
    expect(c.read(shellRouteProvider).subtab, 'journey');
  });
}
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement**
  - `dice_sheet.dart`:

```dart
import 'package:flutter/material.dart';
import '../engine/dice.dart';
import '../features/dice_roller_screen.dart';

Future<void> showDiceSheet(BuildContext context, Dice dice) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => FractionallySizedBox(
      heightFactor: 0.85,
      child: SafeArea(child: DiceRollerScreen(dice: dice)),
    ),
  );
}
```

  - `tool_search_sheet.dart`: port the launcher list + MRU + grouped results from `tool_host.dart` (`_launcher()` body, the `toolGroups`/`matches`/`recent` logic), wrapped in a `showModalBottomSheet`. On a tool tap: `if (showDiceSheet needed) ...` — specifically `if (tool.id == 'dice') { Navigator.pop(context); showDiceSheet(context, oracle.dice); }` else `final ok = ref.read(shellRouteProvider.notifier).openTool(tool.id); Navigator.pop(context); if (ok) nothing else openHelp/no-op`. Keep `toolMruProvider.record(id)`. Signature: `Future<void> showToolSearchSheet(BuildContext context, List<ToolDef> tools, {Oracle? oracle})`. Use `Key('tool-search')` on the field (preserve the test key from the old launcher).
  - `home_shell.dart`: replace the Tools AppBar `IconButton` onPressed with `() => showToolSearchSheet(context, buildToolRegistry(family: family, systems: systems), oracle: widget.oracle)`; change its icon to `Icons.search` and tooltip to `Search tools`. Add a **Help** AppBar `IconButton` (`Icons.help_outline`, tooltip `Help`) whose onPressed is `() => openHelp(context, ref)` (the same helper added to `journal_screen.dart`; export it or duplicate the 2-line push). Remove `_hostKey`, the `ToolHost` import, and the now-unused lifecycle/host wiring tied to ToolHost (keep the LLM `AppLifecycleListener`). The body is already `_shellBody` from Task 4.
  - `journal_screen.dart`: replace the 7 deep-link call sites:
    - `ToolHost.openToolIfKnown(context, e.sourceTool!)` → `_openTool(e.sourceTool!)` where `_openTool` is a new method: `void _openTool(String id){ if (id=='dice'){ showDiceSheet(context, ref.read(oracleProvider).valueOrNull!.dice); return;} if(!ref.read(shellRouteProvider.notifier).openTool(id)){ ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tool not available'))); } }`
    - `/help` (two sites) and the help button → `openHelp(context, ref)` — add a tiny helper that sets `helpTopicProvider` (if a topic) then `Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HelpScreen()))`. Import `help_screen.dart`.
    - `_openCharacter` → `ref.read(shellRouteProvider.notifier).goTo(Destination.tracking, subtab: 'npcs')`.
    - header thread chip / star chip → `goTo(Destination.tracking, subtab: 'threads')` and `subtab: 'npcs'` respectively.
    - header crawl chip (`gen-exploration`) → `ref.read(shellRouteProvider.notifier).openTool('gen-exploration')`.
    - Remove the `import '../shared/tool_host.dart';` line; add imports for `shell_route.dart`, `destination.dart`, `dice_sheet.dart`, `help_screen.dart`.
  - Delete `lib/shared/tool_host.dart`.
  - Update `test/journal_payload_ui_test.dart`: any assertion that opening a payload entry's "open in tool" mounts a ToolHost panel now asserts `container.read(shellRouteProvider).destination` is the expected destination instead. (Read the file; replace ToolHost-panel expectations with shellRoute assertions.)

- [ ] **Step 4: Run** — the new sheet test, the journal payload test, then `flutter test` (full) and `flutter analyze`. Fix any other tests that imported `tool_host.dart` (grep: `grep -rl tool_host test/`).

- [ ] **Step 5: Commit** — `feat: global tool-search sheet; retire ToolHost overlay; rewire deep-links`.

---

# Phase 3 — Entry line

### Task 10: Dice on the composer, scene off it

**Files:**
- Modify: `lib/features/journal_screen.dart` (`_composerBar`)
- Test: `test/journal_composer_test.dart` (add cases; create if absent)

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice/features/journal_screen.dart';
import 'package:juice/state/providers.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('composer has a dice action and no scene button', (t) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(oracleProvider.future);
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: JournalScreen())),
    ));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('composer-dice')), findsOneWidget);
    expect(find.byIcon(Icons.movie_outlined), findsNothing);
  });

  testWidgets('tapping dice opens the roll sheet', (t) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(oracleProvider.future);
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: JournalScreen())),
    ));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('composer-dice')));
    await t.pumpAndSettle();
    // Dice roller's notation field is present in the sheet.
    expect(find.byType(TextField), findsWidgets);
  });
}
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement** — in `_composerBar`, replace the `IconButton(Icons.movie_outlined, 'New scene')` with:

```dart
IconButton(
  key: const Key('composer-dice'),
  icon: const Icon(Icons.casino_outlined),
  tooltip: 'Roll dice',
  onPressed: () {
    final oracle = ref.read(oracleProvider).valueOrNull;
    if (oracle != null) showDiceSheet(context, oracle.dice);
  },
),
```

Scene creation already survives via `/scene` (slash palette) and Tracking → Scenes — no further change. (`_newScene` stays; it's still called by the slash palette.)

- [ ] **Step 4: Run, expect PASS;** `flutter analyze`.

- [ ] **Step 5: Commit** — `feat: dice on the journal entry line; scene creation via /scene + Tracking`.

---

# Phase 4 — Rumors

### Task 11: Rumor model

**Files:**
- Modify: `lib/engine/models.dart`
- Test: `test/models_rumor_track_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice/engine/models.dart';

void main() {
  test('Rumor round-trips through json', () {
    const r = Rumor(id: '1', text: 'Smugglers use the north gate', note: 'from the barkeep');
    final back = Rumor.fromJson(r.toJson());
    expect(back.id, '1');
    expect(back.text, r.text);
    expect(back.note, r.note);
    expect(back.resolved, isFalse);
  });

  test('Rumor copyWith toggles resolved', () {
    const r = Rumor(id: '1', text: 'x');
    expect(r.copyWith(resolved: true).resolved, isTrue);
  });
}
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement** — append to `models.dart`:

```dart
class Rumor {
  const Rumor({
    required this.id,
    required this.text,
    this.resolved = false,
    this.note = '',
  });
  final String id;
  final String text;
  final bool resolved;
  final String note;

  Rumor copyWith({String? text, bool? resolved, String? note}) => Rumor(
        id: id,
        text: text ?? this.text,
        resolved: resolved ?? this.resolved,
        note: note ?? this.note,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        if (resolved) 'resolved': true,
        if (note.isNotEmpty) 'note': note,
      };

  factory Rumor.fromJson(Map<String, dynamic> j) => Rumor(
        id: j['id'] as String,
        text: j['text'] as String,
        resolved: (j['resolved'] as bool?) ?? false,
        note: (j['note'] as String?) ?? '',
      );
}
```

- [ ] **Step 4: Run, expect PASS.**

- [ ] **Step 5: Commit** — `feat: Rumor model`.

### Task 12: Rumor notifier + persistence + export schema v3

**Files:**
- Modify: `lib/state/providers.dart` (notifier + key)
- Modify: `lib/state/campaign_io.dart` (schema v3 + branch)
- Test: `test/rumors_provider_test.dart`, `test/campaign_io_test.dart` (extend)

- [ ] **Step 1: Write the failing test** (`test/rumors_provider_test.dart`)

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice/state/providers.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('add, toggle, remove rumors persist', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(rumorsProvider.future);
    await c.read(rumorsProvider.notifier).add('North gate');
    var list = c.read(rumorsProvider).value!;
    expect(list.single.text, 'North gate');
    await c.read(rumorsProvider.notifier).toggleResolved(list.single.id);
    expect(c.read(rumorsProvider).value!.single.resolved, isTrue);
    await c.read(rumorsProvider.notifier).remove(list.single.id);
    expect(c.read(rumorsProvider).value, isEmpty);
  });
}
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement**
  - `providers.dart`: add after the Characters block:

```dart
// -- Rumors -----------------------------------------------------------------
class RumorNotifier extends _PersistedList<Rumor> {
  @override
  String get prefsKey => 'juice.rumors.v1';
  @override
  Rumor fromJson(Map<String, dynamic> json) => Rumor.fromJson(json);
  @override
  Map<String, dynamic> toJsonMap(Rumor item) => item.toJson();

  Future<void> add(String text) async {
    await _persist([Rumor(id: _newId(), text: text), ...await _ready]);
  }

  Future<void> replace(Rumor rumor) async {
    await _persist([
      for (final r in await _ready)
        if (r.id == rumor.id) rumor else r,
    ]);
  }

  Future<void> toggleResolved(String id) async {
    await _persist([
      for (final r in await _ready)
        if (r.id == id) r.copyWith(resolved: !r.resolved) else r,
    ]);
  }

  Future<void> remove(String id) async {
    await _persist((await _ready).where((r) => r.id != id).toList());
  }
}

final rumorsProvider =
    AsyncNotifierProvider<RumorNotifier, List<Rumor>>(RumorNotifier.new);
```

  - In `sessionScopedKeys`, add `'juice.rumors.v1',` (before `'juice.settings.v1'`).
  - `campaign_io.dart`: change `campaignSchemaVersion` to `3`; add a branch in `parseCampaign`'s validation loop:

```dart
} else if (key == 'juice.rumors.v1') {
  (value as List)
      .map((e) => Rumor.fromJson(e as Map<String, dynamic>))
      .toList();
}
```

  - Extend `test/campaign_io_test.dart`: add a case asserting a v2 file (no rumors key) still imports (rumors default empty) and that an encoded campaign with rumors round-trips. (Read the file for its existing helpers and mirror them.)

- [ ] **Step 4: Run** both tests + `flutter test test/campaign_io_test.dart`, expect PASS.

- [ ] **Step 5: Commit** — `feat: Rumor persistence + campaign schema v3`.

### Task 13: Rumors pane UI

**Files:**
- Create: `lib/features/rumors_pane.dart`
- Modify: `lib/features/tracking_tab.dart` (swap placeholder)
- Test: `test/rumors_pane_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice/features/rumors_pane.dart';
import 'package:juice/state/providers.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('adds a rumor through the UI', (t) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(rumorsProvider.future);
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: RumorsPane())),
    ));
    await t.tap(find.byKey(const Key('rumors-add')));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).last, 'Bridge is watched');
    await t.tap(find.text('Add'));
    await t.pumpAndSettle();
    expect(find.text('Bridge is watched'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement** — `rumors_pane.dart`: a `ConsumerWidget` listing `rumorsProvider`; header row with `Expanded(Text('Rumors'))` + `Flexible(FilledButton.tonalIcon(key: Key('rumors-add'), ...))` (Flexible per the freeze rule); each rumor a `CheckboxListTile` (value = `resolved`, `onChanged` → `toggleResolved`) with a trailing delete `IconButton` and `onLongPress`/menu to edit text. Add dialog mirrors `_SceneDialog` (reuse the AlertDialog+TextField pattern; "Add" button returns text → `rumorsProvider.notifier.add`). Then in `tracking_tab.dart` swap `Center(child: Text('Rumors'))` → `RumorsPane()`.

- [ ] **Step 4: Run, expect PASS;** `flutter analyze`.

- [ ] **Step 5: Commit** — `feat: Rumors pane`.

---

# Phase 5 — Tracks

### Task 14: Track model

**Files:**
- Modify: `lib/engine/models.dart`
- Test: extend `test/models_rumor_track_test.dart`

- [ ] **Step 1: Add the failing test**

```dart
  test('Track round-trips and clamps via copyWith', () {
    const tr = Track(id: '1', name: 'Reach the keep', filled: 3, max: 10);
    final back = Track.fromJson(tr.toJson());
    expect(back.name, 'Reach the keep');
    expect(back.filled, 3);
    expect(back.max, 10);
    expect(tr.copyWith(filled: 5).filled, 5);
  });
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement** — append to `models.dart`:

```dart
class Track {
  const Track({
    required this.id,
    required this.name,
    this.filled = 0,
    this.max = 10,
    this.note = '',
  });
  final String id;
  final String name;
  final int filled;
  final int max;
  final String note;

  Track copyWith({String? name, int? filled, int? max, String? note}) => Track(
        id: id,
        name: name ?? this.name,
        filled: filled ?? this.filled,
        max: max ?? this.max,
        note: note ?? this.note,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'filled': filled,
        'max': max,
        if (note.isNotEmpty) 'note': note,
      };

  factory Track.fromJson(Map<String, dynamic> j) => Track(
        id: j['id'] as String,
        name: j['name'] as String,
        filled: (j['filled'] as int?) ?? 0,
        max: (j['max'] as int?) ?? 10,
        note: (j['note'] as String?) ?? '',
      );
}
```

- [ ] **Step 4: Run, expect PASS.**

- [ ] **Step 5: Commit** — `feat: Track model`.

### Task 15: Track notifier + persistence + export

**Files:**
- Modify: `lib/state/providers.dart`, `lib/state/campaign_io.dart`
- Test: `test/tracks_provider_test.dart`, extend `test/campaign_io_test.dart`

- [ ] **Step 1: Write the failing test** (`test/tracks_provider_test.dart`)

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice/state/providers.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('add and adjust clamps within [0, max]', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(tracksProvider.future);
    await c.read(tracksProvider.notifier).add('Find the heir');
    final id = c.read(tracksProvider).value!.single.id;
    await c.read(tracksProvider.notifier).adjust(id, 3);
    expect(c.read(tracksProvider).value!.single.filled, 3);
    await c.read(tracksProvider.notifier).adjust(id, -10);
    expect(c.read(tracksProvider).value!.single.filled, 0);
    await c.read(tracksProvider.notifier).adjust(id, 999);
    expect(c.read(tracksProvider).value!.single.filled, 10);
  });
}
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement**
  - `providers.dart` after the Rumors block:

```dart
// -- Tracks -----------------------------------------------------------------
class TrackNotifier extends _PersistedList<Track> {
  @override
  String get prefsKey => 'juice.tracks.v1';
  @override
  Track fromJson(Map<String, dynamic> json) => Track.fromJson(json);
  @override
  Map<String, dynamic> toJsonMap(Track item) => item.toJson();

  Future<void> add(String name, {int max = 10}) async {
    await _persist([Track(id: _newId(), name: name, max: max), ...await _ready]);
  }

  Future<void> adjust(String id, int delta) async {
    await _persist([
      for (final t in await _ready)
        if (t.id == id)
          t.copyWith(filled: (t.filled + delta).clamp(0, t.max))
        else
          t,
    ]);
  }

  Future<void> rename(String id, String name) async {
    await _persist([
      for (final t in await _ready)
        if (t.id == id) t.copyWith(name: name) else t,
    ]);
  }

  Future<void> remove(String id) async {
    await _persist((await _ready).where((t) => t.id != id).toList());
  }
}

final tracksProvider =
    AsyncNotifierProvider<TrackNotifier, List<Track>>(TrackNotifier.new);
```

  - `sessionScopedKeys`: add `'juice.tracks.v1',`.
  - `campaign_io.dart`: add branch:

```dart
} else if (key == 'juice.tracks.v1') {
  (value as List)
      .map((e) => Track.fromJson(e as Map<String, dynamic>))
      .toList();
}
```

  (Schema is already v3 from Task 12.) Extend `test/campaign_io_test.dart` with a tracks round-trip case.

- [ ] **Step 4: Run, expect PASS.**

- [ ] **Step 5: Commit** — `feat: Track persistence`.

### Task 16: Tracks pane UI

**Files:**
- Create: `lib/features/tracks_pane.dart`
- Modify: `lib/features/tracking_tab.dart`
- Test: `test/tracks_pane_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice/features/tracks_pane.dart';
import 'package:juice/state/providers.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('add a track and increment it', (t) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(tracksProvider.future);
    await c.read(tracksProvider.notifier).add('Escape');
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: TracksPane())),
    ));
    await t.pumpAndSettle();
    expect(find.text('Escape'), findsOneWidget);
    await t.tap(find.byKey(const Key('track-inc-0')));
    await t.pumpAndSettle();
    expect(c.read(tracksProvider).value!.single.filled, 1);
  });
}
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement** — `tracks_pane.dart`: list `tracksProvider`; header `Expanded(Text('Tracks'))` + `Flexible(FilledButton.tonalIcon(key: Key('tracks-add')))`. Each track: a `ListTile`/`Card` with name, a `filled / max` label, and `IconButton(key: Key('track-dec-$i'), Icons.remove)` / `IconButton(key: Key('track-inc-$i'), Icons.add)` calling `tracksProvider.notifier.adjust(id, -1|1)`; a small `LinearProgressIndicator(value: filled/max)`; long-press/menu to rename or delete. Add dialog like the Rumors one. Then swap `Center(child: Text('Tracks'))` → `TracksPane()` in `tracking_tab.dart`.

- [ ] **Step 4: Run, expect PASS;** `flutter analyze`.

- [ ] **Step 5: Commit** — `feat: Tracks pane`.

### Task 17: System filtering for destinations + subtabs

**Files:**
- Modify: `lib/shared/home_shell.dart` (`_visibleDestinations`, `_root`)
- Modify: `lib/features/oracles_tab.dart` (Moves gating — already done in Task 6), `lib/features/maps_tab.dart` (Journey gating), `lib/features/party_tab.dart` (whole-destination gating)
- Test: `test/shell_filtering_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice/shared/home_shell.dart';
import 'package:juice/engine/oracle.dart';
import 'package:juice/engine/oracle_data.dart';
import 'package:juice/state/providers.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Party destination hidden when party system disabled', (t) async {
    final oracle = Oracle(await OracleData.load());
    final c = ProviderContainer();
    addTearDown(c.dispose);
    // New campaign without 'party'.
    await c.read(sessionsProvider.future);
    await c.read(sessionsProvider.notifier).create('No party',
        systems: {'juice', 'mythic', 'ironsworn', 'verdant'});
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(home: HomeShell(oracle: oracle)),
    ));
    await t.pumpAndSettle();
    expect(find.text('Party'), findsNothing);
    expect(find.text('Journal'), findsWidgets);
  });
}
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement**
  - `_visibleDestinations`: include `Destination.party` only if `systems.contains('party')`; include `Destination.maps` always (World/Dungeon are core); `journal`, `tracking`, `oracles` always. (Maps Journey subtab and Oracles Moves subtab are gated inside their tabs.)
  - `maps_tab.dart`: build tabs/children lists; include the Journey `SubtabDef`/`VerdantScreen` only if `systems.contains('verdant')` — pass `systems` into `MapsTab` (add a `Set<String> systems` field; `home_shell` already has `systems`).
  - `party_tab.dart`: no internal gating needed (whole destination hidden), but guard each subtab by its system if you want partial — keep simple: whole-destination gate only.
  - Ensure the `IndexedStack` index in `_shellBody` clamps when the selected destination is filtered out (already `.clamp`).

- [ ] **Step 4: Run, expect PASS;** `flutter analyze`; then full `flutter test`.

- [ ] **Step 5: Commit** — `feat: system-aware destination/subtab filtering`.

---

## Final verification

- [ ] `flutter analyze` → "No issues found!"
- [ ] `flutter test` → all green.
- [ ] `grep -rn "TabBarView" lib/` → only comments (no widgets).
- [ ] `grep -rn "tool_host" lib/ test/` → no references (file deleted).
- [ ] On-device (Pixel) smoke per `juice-browser-verify` / `juice-toolhost-loose-constraints` recipe: open each destination + every subtab in a **release-web or device build** and confirm none freezes/blanks (headless cannot catch the loose-constraint class). Pay special attention to Tracking (six scrollable subtabs) and Maps Journey.
- [ ] Update help: add a Help page note that tools now live in tabs + global search. `assets/help_data.json` is hand-maintained (no generator script), so edit it directly.
- [ ] Open PR with `/ship-pr "Tabbed home shell + Rumors/Tracks"`.

## Out of scope (later)

Split journal|map homescreen; City maps. Both reintroduce the unbounded-width freeze class on side-by-side panes and get their own spec/plan.
