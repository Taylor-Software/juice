# GM / Party Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A per-campaign GM/Party mode (stored on `SessionMeta`) with an app-bar toggle that declutters each verb's role-tagged sub-options to the active role.

**Architecture:** Add `CampaignMode {gm, party}` to `SessionMeta` (default `party`); a pure `role_tags.dart` maps the role-filtered subtab keys and answers `visibleForMode`. `modeProvider` exposes the active campaign's mode; `SessionsNotifier.setMode` persists it (mirroring `editSystems`). `TrackingTab`/`SheetTab` (both ConsumerWidgets) read `modeProvider` and drop role-hidden subtabs. An app-bar toggle flips it. No engine change.

**Tech Stack:** Flutter, `flutter_riverpod`, `shared_preferences`, `package:flutter_test`.

---

## File Structure

**Create:**
- `lib/engine/role_tags.dart` — `SubtabRole`, `kSubtabRoles`, `visibleForMode`.
- `test/role_tags_test.dart`, `test/mode_provider_test.dart`.

**Modify:**
- `lib/engine/models.dart` — `CampaignMode` enum + `SessionMeta.mode`.
- `lib/state/providers.dart` — `setMode`, `modeProvider`, fix `editSystems` to preserve `mode`.
- `lib/features/tracking_tab.dart` — mode-filter Rumors / Emulator / Sidekick / Behavior.
- `lib/features/sheet_tab.dart` — Moves party-only.
- `lib/shared/home_shell.dart` — app-bar GM/Party toggle.
- `CLAUDE.md`.

**Deferred (per spec escape hatch):** the per-mode landing default (GM→Journal, Party→Sheet). There's no clean on-activate hook (`shellRoute` defaults to journal; `switchTo` doesn't navigate); wiring it risks fighting nav persistence. The decluttering is the deliverable; landing is dropped from v1.

---

### Task 1: CampaignMode + SessionMeta.mode (+ editSystems preserves it)

**Files:**
- Modify: `lib/engine/models.dart` (SessionMeta, lines 2152-2174)
- Modify: `lib/state/providers.dart` (editSystems, lines 1052-1063)
- Test: `test/mode_provider_test.dart` (model round-trip group)

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';

void main() {
  group('SessionMeta.mode', () {
    test('absent mode defaults to party', () {
      final m = SessionMeta.fromJson({'id': 'a', 'name': 'A'});
      expect(m.mode, CampaignMode.party);
    });
    test('gm mode round-trips', () {
      const m = SessionMeta(id: 'a', name: 'A', mode: CampaignMode.gm);
      final back = SessionMeta.fromJson(m.toJson());
      expect(back.mode, CampaignMode.gm);
    });
    test('party mode omitted from json (default)', () {
      const m = SessionMeta(id: 'a', name: 'A');
      expect(m.toJson().containsKey('mode'), isFalse);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/mode_provider_test.dart`
Expected: FAIL — `CampaignMode` / `SessionMeta.mode` undefined.

- [ ] **Step 3: Add the enum + field**

In `lib/engine/models.dart`, add near `SessionMeta`:

```dart
/// The player's current focus for a campaign: running the world (gm) or
/// playing their character(s) (party). Declutters role-specific sub-options.
enum CampaignMode { gm, party }

CampaignMode _modeFromName(String? n) =>
    n == 'gm' ? CampaignMode.gm : CampaignMode.party;
```

Replace the `SessionMeta` class with:

```dart
class SessionMeta {
  const SessionMeta(
      {required this.id,
      required this.name,
      this.systems,
      this.mode = CampaignMode.party});
  final String id;
  final String name;

  /// Enabled optional systems; null means all (legacy campaigns).
  final List<String>? systems;

  /// Player focus mode (default party; legacy campaigns → party).
  final CampaignMode mode;

  /// Resolved set: the declared systems, or every system when unset.
  Set<String> get enabledSystems => systems?.toSet() ?? kAllSystems;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (systems != null) 'systems': systems,
        if (mode != CampaignMode.party) 'mode': mode.name,
      };

  factory SessionMeta.fromJson(Map<String, dynamic> j) => SessionMeta(
        id: j['id'] as String,
        name: j['name'] as String,
        systems: (j['systems'] as List?)?.whereType<String>().toList(),
        mode: _modeFromName(j['mode'] as String?),
      );
}
```

- [ ] **Step 4: Fix `editSystems` to preserve mode**

In `lib/state/providers.dart` `editSystems`, the rebuilt `SessionMeta` currently
drops `mode`. Change it to carry it:

```dart
        SessionMeta(
            id: m.id, name: m.name, systems: systems.toList(), mode: m.mode)
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/mode_provider_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/engine/models.dart lib/state/providers.dart test/mode_provider_test.dart
git commit -m "feat(mode): CampaignMode on SessionMeta (editSystems preserves it)"
```

---

### Task 2: role_tags.dart (pure filter)

**Files:**
- Create: `lib/engine/role_tags.dart`
- Test: `test/role_tags_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/engine/role_tags.dart';

void main() {
  group('visibleForMode', () {
    test('untagged keys are always visible', () {
      expect(visibleForMode('scenes', CampaignMode.gm), isTrue);
      expect(visibleForMode('scenes', CampaignMode.party), isTrue);
      expect(visibleForMode('encounter', CampaignMode.party), isTrue);
    });
    test('rumors is gm-only', () {
      expect(visibleForMode('rumors', CampaignMode.gm), isTrue);
      expect(visibleForMode('rumors', CampaignMode.party), isFalse);
    });
    test('party tools + moves are party-only', () {
      for (final k in ['emulator', 'sidekick', 'behavior', 'moves']) {
        expect(visibleForMode(k, CampaignMode.party), isTrue, reason: k);
        expect(visibleForMode(k, CampaignMode.gm), isFalse, reason: k);
      }
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/role_tags_test.dart`
Expected: FAIL — `role_tags.dart` not found.

- [ ] **Step 3: Create `lib/engine/role_tags.dart`**

```dart
import 'models.dart';

/// Role affinity of a mode-filtered sub-option.
enum SubtabRole { gm, party, both }

/// Sub-options that are role-specific. Anything absent is [SubtabRole.both]
/// (always visible). Keys match SubtabDef keys (Track) / Sheet 'moves'.
const Map<String, SubtabRole> kSubtabRoles = {
  'rumors': SubtabRole.gm,
  'emulator': SubtabRole.party,
  'sidekick': SubtabRole.party,
  'behavior': SubtabRole.party,
  'moves': SubtabRole.party,
};

/// Whether a sub-option [key] is shown in [mode]. Untagged → always.
bool visibleForMode(String key, CampaignMode mode) {
  switch (kSubtabRoles[key] ?? SubtabRole.both) {
    case SubtabRole.both:
      return true;
    case SubtabRole.gm:
      return mode == CampaignMode.gm;
    case SubtabRole.party:
      return mode == CampaignMode.party;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/role_tags_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/role_tags.dart test/role_tags_test.dart
git commit -m "feat(mode): pure role_tags filter (gm/party/both)"
```

---

### Task 3: modeProvider + setMode

**Files:**
- Modify: `lib/state/providers.dart` (add `setMode` after `editSystems`; add `modeProvider`)
- Test: `test/mode_provider_test.dart` (append)

- [ ] **Step 1: Write the failing test** (append to the file from Task 1)

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

// inside main():
  group('modeProvider + setMode', () {
    test('reads the active campaign mode (default party)', () async {
      SharedPreferences.setMockInitialValues({
        'juice.sessions.v1':
            '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      });
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(sessionsProvider.future);
      expect(c.read(modeProvider), CampaignMode.party);
    });

    test('setMode flips + persists + preserves systems', () async {
      SharedPreferences.setMockInitialValues({
        'juice.sessions.v1':
            '{"active":"default","sessions":[{"id":"default","name":"C1","systems":["ironsworn"]}]}',
      });
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(sessionsProvider.future);
      await c.read(sessionsProvider.notifier).setMode('default', CampaignMode.gm);
      expect(c.read(modeProvider), CampaignMode.gm);
      // systems untouched:
      expect(
          c.read(sessionsProvider).valueOrNull?.activeMeta.enabledSystems
              .contains('ironsworn'),
          isTrue);
      // persisted:
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('juice.sessions.v1'), contains('"mode":"gm"'));
    });
  });
```

(Merge imports with the file's existing top-of-file imports; don't duplicate.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/mode_provider_test.dart`
Expected: FAIL — `setMode` / `modeProvider` undefined.

- [ ] **Step 3: Add `setMode` + `modeProvider`**

In `lib/state/providers.dart`, add `setMode` right after `editSystems` in
`SessionsNotifier`:

```dart
  /// Set the player-focus mode for session [id]. Preserves systems.
  Future<void> setMode(String id, CampaignMode mode) async {
    final s = state.valueOrNull;
    if (s == null) return;
    final updated = [
      for (final m in s.sessions)
        if (m.id == id)
          SessionMeta(id: m.id, name: m.name, systems: m.systems, mode: mode)
        else
          m,
    ];
    await _save(SessionsState(active: s.active, sessions: updated));
  }
```

And declare `modeProvider` near the other session-derived providers:

```dart
final modeProvider = Provider<CampaignMode>((ref) =>
    ref.watch(sessionsProvider).valueOrNull?.activeMeta.mode ??
    CampaignMode.party);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/mode_provider_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/state/providers.dart test/mode_provider_test.dart
git commit -m "feat(mode): modeProvider + SessionsNotifier.setMode"
```

---

### Task 4: TrackingTab mode filtering

**Files:**
- Modify: `lib/features/tracking_tab.dart` (build, lines 23-54)
- Test: `test/tracking_tab_test.dart` (append)

- [ ] **Step 1: Write the failing test**

```dart
  testWidgets('GM mode shows Rumors, hides party tools', (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1",'
              '"systems":["party"],"mode":"gm"}]}',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(sessionsProvider.future);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: TrackingTab(systems: {'party'})))));
    await tester.pumpAndSettle();
    expect(find.text('Rumors'), findsOneWidget);
    expect(find.text('Emulator'), findsNothing);
  });

  testWidgets('Party mode hides Rumors, shows party tools', (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1",'
              '"systems":["party"],"mode":"party"}]}',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(sessionsProvider.future);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: TrackingTab(systems: {'party'})))));
    await tester.pumpAndSettle();
    expect(find.text('Rumors'), findsNothing);
    expect(find.text('Emulator'), findsOneWidget);
  });
```

(Add imports: `flutter_riverpod`, `sessionsProvider` from providers.dart, `AppTheme`, `shared_preferences`, and the role/mode types if referenced — match the existing test file's imports.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/tracking_tab_test.dart -n "mode"`
Expected: FAIL — Rumors always present, Emulator gated only by party.

- [ ] **Step 3: Add mode filtering**

In `lib/features/tracking_tab.dart` `build`, read the mode and gate the
role-tagged subtabs with `visibleForMode`. Add imports
`'../engine/role_tags.dart'`, `'../engine/models.dart'`, `'../state/providers.dart'`
as needed. Replace the body:

```dart
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lonelog = systems.contains('lonelog');
    final party = systems.contains('party');
    final mode = ref.watch(modeProvider);
    final rumors = visibleForMode('rumors', mode);
    final partyTools = party &&
        visibleForMode('emulator', mode); // emulator/sidekick/behavior share the party role
    return SubtabHost(
      destination: Destination.track,
      scrollable: true,
      tabs: [
        const SubtabDef('scenes', 'Scenes'),
        const SubtabDef('threads', 'Threads'),
        if (rumors) const SubtabDef('rumors', 'Rumors'),
        const SubtabDef('tracks', 'Tracks'),
        const SubtabDef('encounter', 'Encounter'),
        if (partyTools) const SubtabDef('emulator', 'Emulator'),
        if (partyTools) const SubtabDef('sidekick', 'Sidekick'),
        if (partyTools) const SubtabDef('behavior', 'Behavior'),
        if (lonelog) const SubtabDef('resources', 'Resources'),
        if (lonelog) const SubtabDef('battle', 'Battle'),
      ],
      children: [
        const ScenesPane(),
        const ThreadsPane(),
        if (rumors) const RumorsPane(),
        const TracksPane(),
        const EncounterScreen(),
        if (partyTools) const PartyEmulatorScreen(),
        if (partyTools) const SidekickScreen(),
        if (partyTools) const BehaviorTablesScreen(),
        if (lonelog) const ResourcesPane(),
        if (lonelog) const BattlePane(),
      ],
    );
  }
```

(Keep tabs[i] / children[i] index-aligned — the `if` conditions are identical and in the same order.)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/tracking_tab_test.dart`
Expected: PASS. (Existing tracking_tab tests that don't set a mode default to `party` — verify they don't assert Rumors present; if one does, set its seeded mode to `gm` or update it to the party-mode reality.)
Run: `flutter analyze lib/features/tracking_tab.dart`
Expected: No issues.

- [ ] **Step 5: Commit**

```bash
git add lib/features/tracking_tab.dart test/tracking_tab_test.dart
git commit -m "feat(mode): Track filters Rumors (gm) + party tools (party) by mode"
```

---

### Task 5: SheetTab Moves party-only

**Files:**
- Modify: `lib/features/sheet_tab.dart` (build, lines 16-31)
- Test: `test/verb_nav_test.dart` (append; it already pumps SheetTab)

- [ ] **Step 1: Write the failing test**

```dart
  testWidgets('Sheet shows Moves only in party mode', (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1","mode":"gm"}]}',
      'juice.characters.v1.default': '[]',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(sessionsProvider.future);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: SheetTab(family: ['classic'])))));
    await tester.pumpAndSettle();
    // GM mode + family non-empty: Moves hidden → bare roster (no Moves tab).
    expect(find.text('Moves'), findsNothing);
    expect(find.byType(CharactersPane), findsOneWidget);
  });
```

(Add `sessionsProvider` import if not present in verb_nav_test.dart.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/verb_nav_test.dart -n "Moves only in party"`
Expected: FAIL — Moves tab present in gm mode.

- [ ] **Step 3: Add mode filtering**

In `lib/features/sheet_tab.dart` `build`, gate Moves on party mode. Add imports
`'../engine/role_tags.dart'`, `'../state/providers.dart'`:

```dart
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(modeProvider);
    // Bare roster when there's no Ironsworn family OR Moves is mode-hidden.
    if (family.isEmpty || !visibleForMode('moves', mode)) {
      return const CharactersPane();
    }
    return SubtabHost(
      destination: Destination.sheet,
      tabs: const [
        SubtabDef('characters', 'Characters'),
        SubtabDef('moves', 'Moves'),
      ],
      children: [
        const CharactersPane(),
        MovesScreen(rulesetIds: family),
      ],
    );
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/verb_nav_test.dart`
Expected: PASS (existing SheetTab tests default to party mode → Moves still shows where family non-empty; verify the existing "Moves appears" test seeds party mode or no mode).
Run: `flutter analyze lib/features/sheet_tab.dart`
Expected: No issues.

- [ ] **Step 5: Commit**

```bash
git add lib/features/sheet_tab.dart test/verb_nav_test.dart
git commit -m "feat(mode): Sheet shows Moves only in party mode"
```

---

### Task 6: App-bar GM/Party toggle

**Files:**
- Modify: `lib/shared/home_shell.dart` (AppBar actions, ~line 545 before Campaigns)
- Test: `test/home_shell_test.dart` (append)

- [ ] **Step 1: Write the failing test**

```dart
  testWidgets('mode toggle flips and persists the campaign mode',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    });
    // Pump the home shell using this file's existing harness (see other
    // home_shell_test cases for the exact pump helper + provider overrides).
    final c = await pumpShell(tester); // reuse the file's helper
    expect(c.read(modeProvider), CampaignMode.party);
    await tester.tap(find.byKey(const Key('mode-toggle')));
    await tester.pumpAndSettle();
    expect(c.read(modeProvider), CampaignMode.gm);
  });
```

(Use `home_shell_test.dart`'s existing shell-pump helper + provider overrides — match how its other tests mount `HomeShell`/`HomeScaffold`. If there's no reusable helper, mirror the setup of an adjacent test in that file. Add `modeProvider`/`CampaignMode` imports.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/home_shell_test.dart -n "mode toggle"`
Expected: FAIL — no `mode-toggle` key.

- [ ] **Step 3: Add the toggle**

In `lib/shared/home_shell.dart`, insert into the AppBar `actions:` list, just
before the Campaigns `IconButton`:

```dart
          IconButton(
            key: const Key('mode-toggle'),
            icon: Icon(ref.watch(modeProvider) == CampaignMode.gm
                ? Icons.castle_outlined
                : Icons.groups_outlined),
            tooltip: ref.watch(modeProvider) == CampaignMode.gm
                ? 'GM mode (tap for Party)'
                : 'Party mode (tap for GM)',
            onPressed: () {
              final sessions = ref.read(sessionsProvider).valueOrNull;
              if (sessions == null) return;
              final next = ref.read(modeProvider) == CampaignMode.gm
                  ? CampaignMode.party
                  : CampaignMode.gm;
              ref.read(sessionsProvider.notifier).setMode(sessions.active, next);
            },
          ),
```

Ensure `home_shell.dart` imports expose `modeProvider`/`CampaignMode` (they come
from `providers.dart` / `models.dart`, already imported here). The surrounding
`build` is a `Consumer`/`ConsumerState` with `ref` in scope (the actions list
already uses `ref`).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/home_shell_test.dart`
Expected: PASS.
Run: `flutter analyze lib/shared/home_shell.dart`
Expected: No issues.

- [ ] **Step 5: Commit**

```bash
git add lib/shared/home_shell.dart test/home_shell_test.dart
git commit -m "feat(mode): app-bar GM/Party toggle"
```

---

### Task 7: Full verify + docs

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Full analyze + test**

Run: `flutter analyze` → No issues found.
Run: `flutter test` → All tests pass.
(Watch for existing Track/Sheet tests that assumed Rumors/Moves always present —
they now depend on mode; the default is `party`, so Rumors is hidden by default.
Fix any such pre-existing assertion to seed the intended mode.)

- [ ] **Step 2: CLAUDE.md note**

Add under "## Project notes":

```markdown
- **GM/Party mode** (`CampaignMode {gm, party}` on `SessionMeta`, default
  `party`; legacy campaigns → party). `modeProvider` exposes the active
  campaign's mode; `SessionsNotifier.setMode` persists it (and `editSystems`
  preserves it). A pure `lib/engine/role_tags.dart` (`visibleForMode`) tags
  role-specific sub-options: `rumors` → gm; `emulator`/`sidekick`/`behavior`/
  `moves` → party; everything else `both`. `TrackingTab` and `SheetTab` (both
  read `modeProvider`) drop the hidden subtabs; an app-bar `mode-toggle` flips
  it. NOTE: default `party` means legacy campaigns hide the Track `Rumors`
  subtab until toggled to GM. Deferred: per-mode landing default + creation-time
  mode picker + per-mode assistant suggestions. See
  `docs/superpowers/specs/2026-06-18-gm-party-mode-design.md`.
```

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(mode): document GM/Party mode"
```

---

## Self-Review

**1. Spec coverage:**
- `CampaignMode` on `SessionMeta` (default party, legacy→party) → Task 1. ✓
- `editSystems` preserves mode → Task 1 (a real bug the spec implied). ✓
- `role_tags.dart` pure filter → Task 2. ✓
- `modeProvider` + `setMode` → Task 3. ✓
- Track filtering (Rumors gm; party tools party) → Task 4. ✓
- Sheet Moves party-only → Task 5. ✓
- App-bar toggle → Task 6. ✓
- Docs → Task 7. ✓
- Landing default → explicitly DEFERRED (spec escape hatch); creation-time picker → deferred. Both noted.

**2. Placeholder scan:** No "TBD"/"implement later". Test-harness notes ("reuse the file's pump helper") point at concrete adjacent tests in the same file, not vague logic.

**3. Type consistency:** `CampaignMode{gm,party}`, `SessionMeta(...,mode:)`, `setMode(String,CampaignMode)`, `modeProvider`, `SubtabRole{gm,party,both}`, `kSubtabRoles`, `visibleForMode(String,CampaignMode)`, key `mode-toggle` — consistent across tasks. Track/Sheet both read `modeProvider` (no `_root` signature change).

**Regression watch:** default `party` hides Rumors for all existing campaigns. This is intended (toggle to GM reveals it) and called out in docs; any existing test asserting Rumors-present must seed `mode:"gm"`. Task 4/7 steps flag this.
