# Cycle 4 Phase 4: Per-Campaign System Profiles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Each campaign declares which systems it uses (Juice / Mythic / Ironsworn / Party); the tool drawer, slash palette, and campaign header scope to that set. Existing campaigns keep everything.

**Architecture:** Additive `SessionMeta.systems` (null = all, legacy-safe) with a `kAllSystems` const + `enabledSystems` helper; the campaign-create dialog picks systems; `buildToolRegistry` gains a `systems` filter via a tool→system map; the slash palette filters commands by `CommandDef.system`; the header's chaos dial gates on the `mythic` profile instead of the phase-3 heuristic.

**Tech Stack:** Flutter + flutter_riverpod. House rules: TDD; format hook; analyze baseline exactly 1 info; never construct GemmaInterpreterService in tests; commits exact, no co-author. Lost-update rule on any read-modify-write.

**Branch:** `cycle4-phase4-system-profiles` off main (after phase 3 merges). Plan committed first.

**Spec:** docs/superpowers/specs/2026-06-12-cycle4-living-journal-design.md §6.

---

### Task 1: SessionMeta.systems + kAllSystems + enabledSystems

**Files:**
- Modify: `lib/engine/models.dart` (SessionMeta)
- Test: `test/system_profiles_test.dart` (create)

- [ ] **Step 1: Failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';

void main() {
  test('kAllSystems is the four optional systems', () {
    expect(kAllSystems, {'juice', 'mythic', 'ironsworn', 'party'});
  });

  test('legacy meta (no systems) enables all', () {
    final m = SessionMeta.fromJson({'id': 'a', 'name': 'A'});
    expect(m.systems, isNull);
    expect(m.enabledSystems, kAllSystems);
  });

  test('explicit systems round-trip and drive enabledSystems', () {
    const m = SessionMeta(id: 'a', name: 'A', systems: ['juice', 'mythic']);
    final back = SessionMeta.fromJson(m.toJson());
    expect(back.systems, ['juice', 'mythic']);
    expect(back.enabledSystems, {'juice', 'mythic'});
  });

  test('empty systems means only core (no optional systems)', () {
    const m = SessionMeta(id: 'a', name: 'A', systems: []);
    expect(m.enabledSystems, isEmpty);
  });

  test('toJson omits systems when null (byte-stable legacy)', () {
    expect(const SessionMeta(id: 'a', name: 'A').toJson().containsKey('systems'),
        isFalse);
  });
}
```

- [ ] **Step 2: Run, see fail.** `flutter test test/system_profiles_test.dart`

- [ ] **Step 3: Implement** in `lib/engine/models.dart`:

Above `SessionMeta`:
```dart
/// The optional systems a campaign can enable; dice, encounter, the
/// tracker, and help are always available (core).
const kAllSystems = {'juice', 'mythic', 'ironsworn', 'party'};
```

`SessionMeta`:
```dart
class SessionMeta {
  const SessionMeta({required this.id, required this.name, this.systems});
  final String id;
  final String name;

  /// Enabled optional systems; null means all (legacy campaigns).
  final List<String>? systems;

  /// Resolved set: the declared systems, or every system when unset.
  Set<String> get enabledSystems => systems?.toSet() ?? kAllSystems;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (systems != null) 'systems': systems,
      };

  factory SessionMeta.fromJson(Map<String, dynamic> j) => SessionMeta(
        id: j['id'] as String,
        name: j['name'] as String,
        systems: (j['systems'] as List?)?.whereType<String>().toList(),
      );
}
```

- [ ] **Step 4: Run, see pass.**

- [ ] **Step 5: Commit.** `git add lib/engine/models.dart test/system_profiles_test.dart && git commit -m "feat: SessionMeta.systems profile (null = all, legacy-safe)"`

---

### Task 2: create(name, {systems}) + campaign-create picker

**Files:**
- Modify: `lib/state/providers.dart` (SessionsNotifier.create)
- Modify: `lib/shared/home_shell.dart` (_createSession dialog)
- Test: extend `test/system_profiles_test.dart` (provider) + `test/home_shell_test.dart` (picker)

- [ ] **Step 1: Failing tests**
  - Provider: `create('X', systems: {'juice'})` stores a meta whose `enabledSystems == {'juice'}`; `create('Y')` (no arg) stores `systems == null` (all). (ProviderContainer pattern.)
  - home_shell: opening New campaign shows four system checkboxes (keys `sys-juice`/`sys-mythic`/`sys-ironsworn`/`sys-party`), all checked by default; unchecking `sys-party` then creating yields an active campaign whose `enabledSystems` excludes party. (Mirror home_shell_test's existing dialog-driving pattern.)

- [ ] **Step 2: Run, see fail.**

- [ ] **Step 3: Implement.**

`SessionsNotifier.create`:
```dart
  Future<void> create(String name, {Set<String>? systems}) async {
    final s = state.valueOrNull;
    if (s == null) return;
    final meta = SessionMeta(
        id: _newId(),
        name: name,
        systems: systems == null ? null : systems.toList());
    await _save(
        SessionsState(active: meta.id, sessions: [...s.sessions, meta]));
  }
```

home_shell `_createSession`: replace the single-TextField dialog with a stateful dialog holding the name field + four `CheckboxListTile`s (keys `sys-<id>`), all default true; on Create call `create(name, systems: picked)`. Build it as a small `StatefulWidget` `_NewCampaignDialog` returning `({String name, Set<String> systems})?`, since the existing inline dialog can't hold checkbox state. Title 'New campaign', labels: Juice oracle / Mythic GME / Ironsworn family / Party emulator. Keep the existing Cancel/Create actions; Create disabled when name is empty is optional (match existing behavior — it currently allows empty then guards). Guard: if name trimmed empty, do nothing.

- [ ] **Step 4: Run, see pass.** Also run `flutter test test/home_shell_test.dart`.

- [ ] **Step 5: Commit.** `git commit -m "feat: campaign-create system picker wired to SessionMeta.systems"`

---

### Task 3: Tool→system map + buildToolRegistry(systems) filter

**Files:**
- Modify: `lib/shared/tool_registry.dart`
- Modify: `lib/shared/home_shell.dart` (pass enabledSystems; gate family by ironsworn)
- Test: `test/tool_registry_test.dart`

- [ ] **Step 1: Failing tests** — in tool_registry_test:
  - `const toolSystem` map covers every tool id the registry can emit; values ∈ {juice, mythic, ironsworn, party, core}.
  - `buildToolRegistry(family: [], systems: kAllSystems)` == today's no-family set (16 base — confirm current count from the existing test).
  - `buildToolRegistry(family: [], systems: {'juice'})` includes fate-check, roll-high, gen-*, maps, tables AND the core tools (dice, encounter, threads-characters, help) but EXCLUDES mythic, party-emulator, behavior-tables, sidekick-dialogue.
  - `buildToolRegistry(family: ['classic'], systems: {'juice'})` excludes moves (ironsworn not enabled) even though family is non-empty.
  - `buildToolRegistry(family: ['classic'], systems: {'ironsworn','juice'})` includes moves.

- [ ] **Step 2: Run, see fail.**

- [ ] **Step 3: Implement.**

Add to tool_registry.dart:
```dart
/// Registry tool id -> the system that owns it; 'core' tools always show.
/// roll-high rides with the Juice profile (same Fate surface).
const toolSystem = <String, String>{
  'fate-check': 'juice',
  'roll-high': 'juice',
  'mythic': 'mythic',
  'dice': 'core',
  'gen-story': 'juice',
  'gen-npcs': 'juice',
  'party-emulator': 'party',
  'sidekick-dialogue': 'party',
  'behavior-tables': 'party',
  'gen-exploration': 'juice',
  'maps': 'juice',
  'gen-encounters': 'juice',
  'encounter': 'core',
  'gen-details': 'juice',
  'threads-characters': 'core',
  'tables': 'juice',
  'moves': 'ironsworn',
  'help': 'core',
};
```

Change the signature + filter:
```dart
List<ToolDef> buildToolRegistry({
  required List<String> family,
  Set<String> systems = kAllSystems,
}) {
  final all = <ToolDef>[ /* existing list unchanged, incl. the moves entry */ ];
  return all
      .where((t) =>
          (toolSystem[t.id] ?? 'core') == 'core' ||
          systems.contains(toolSystem[t.id]))
      .toList();
}
```
(Keep the existing `if (family.isNotEmpty) ToolDef(id:'moves', …)` inside `all`; the systems filter then drops it when ironsworn is disabled. Import `kAllSystems` from models.dart.)

home_shell `build`: compute `enabledSystems` from the active meta, force family empty when ironsworn is disabled, and pass systems:
```dart
final active = ref.watch(sessionsProvider).valueOrNull?.activeMeta;
final systems = active?.enabledSystems ?? kAllSystems;
final family = !systems.contains('ironsworn')
    ? const <String>[]
    : [
        if (rulesets.contains('classic')) 'classic',
        if (rulesets.contains('delve')) 'delve',
        if (rulesets.contains('starforged')) 'starforged',
        if (rulesets.contains('sundered_isles')) 'sundered_isles',
      ];
...
tools: buildToolRegistry(family: family, systems: systems),
```
Also hide the Rulesets gear IconButton (the `Icons.tune` action) when `!systems.contains('ironsworn')` — wrap it in `if (systems.contains('ironsworn'))`.

- [ ] **Step 4: Run, see pass.** `flutter test test/tool_registry_test.dart test/home_shell_test.dart`.

- [ ] **Step 5: Commit.** `git commit -m "feat: scope the tool drawer to the campaign's system profile"`

---

### Task 4: Scope the slash palette + header chaos to the profile

**Files:**
- Modify: `lib/engine/command_registry.dart` (add `commandsForSystems`)
- Modify: `lib/features/journal_screen.dart` (palette uses it; chaos gate)
- Test: `test/command_registry_test.dart` + `test/slash_palette_test.dart` + `test/campaign_header_test.dart`

- [ ] **Step 1: Failing tests**
  - command_registry: `commandsForSystems(reg, {'juice'})` → ids include fate-juice, dice (core), meaning, name, detail; exclude fate-mythic; fate-roll-high INCLUDED (rides with juice). `commandsForSystems(reg, {'mythic'})` → fate-mythic + core (dice) only, no juice gens. Core always present.
  - slash_palette: pump with a session whose meta systems = {'juice'} (seed `juice.sessions.v1` with `"systems":["juice"]`); typing `/fate` shows Fate Check (Juice) + (Roll High) but NOT Fate Check (Mythic).
  - campaign_header: with systems excluding mythic, the chaos chip is absent even when a scene entry has a chaosFactor; with mythic enabled it shows.

- [ ] **Step 2: Run, see fail.**

- [ ] **Step 3: Implement.**

command_registry.dart:
```dart
/// Commands available under [systems]: core commands always, plus any whose
/// system is enabled. 'roll-high' rides with the Juice profile.
List<CommandDef> commandsForSystems(
    List<CommandDef> registry, Set<String> systems) {
  return registry.where((c) {
    if (c.system == 'core') return true;
    if (c.system == 'roll-high') return systems.contains('juice');
    return systems.contains(c.system);
  }).toList();
}
```

journal_screen.dart `_slashPalette`: read the active profile and filter before matching:
```dart
final systems = ref.watch(sessionsProvider).valueOrNull?.activeMeta
        .enabledSystems ??
    kAllSystems;
final registry = commandsForSystems(buildCommandRegistry(), systems);
final matches = matchCommands(registry, parsed.token);
```
(`_send`'s Enter path must use the same scoped registry — extract a helper or read systems there too so Enter can't run a hidden command. Apply the same `commandsForSystems` filter in `_send`.)

`_CampaignHeader`: replace the `usesMythic` heuristic:
```dart
final systems = ref.watch(sessionsProvider).valueOrNull?.activeMeta
        .enabledSystems ?? kAllSystems;
final showChaos = systems.contains('mythic');
...
if (showChaos && crawl != null) ... // chaos chip + dial
```
Import `kAllSystems` (models.dart) where needed.

- [ ] **Step 4: Run until green.** Targeted files, then FULL `flutter test` + `flutter analyze`. Existing slash_palette/campaign_header tests seed sessions WITHOUT `systems` (→ null → all), so they keep passing; only the new profile-scoped tests assert the narrowing.

- [ ] **Step 5: Commit.** `git commit -m "feat: scope slash palette and header chaos to the system profile"`

---

### Task 5: Docs

- [ ] **Step 1:** README note:
```markdown
- System profiles: pick which systems a campaign uses (Juice, Mythic, Ironsworn, Party) when you create it — the tools, slash commands, and header scope to that set. Existing campaigns keep everything.
```
- [ ] **Step 2:** `flutter analyze` + `flutter test` green.
- [ ] **Step 3: Commit.** `git commit -m "docs: README note for system profiles"`

---

## Self-review notes

- Spec §6 coverage: SessionMeta.systems (Task 1), create picker (Task 2), drawer scoping via toolSystem map + filter (Task 3), slash palette scoping (Task 4), header chaos gated on the mythic profile (Task 4), rulesets-gear hidden + family forced empty when ironsworn off (Task 3). Help-index highlighting (spec mentions) is deferred — low value; note in PR.
- Legacy safety: null systems → kAllSystems everywhere (enabledSystems helper), so every existing campaign and every test that doesn't set systems is unchanged.
- roll-high rides with juice in BOTH the tool map (toolSystem['roll-high']='juice') and commandsForSystems — consistent.
- Type names: kAllSystems, SessionMeta.systems/enabledSystems, toolSystem, commandsForSystems, buildToolRegistry(systems:), create(systems:), keys sys-<id>.
- Verify-against-source: the existing tool_registry_test base count (16/17) — read it and update the numbers to match the systems-filtered expectations; home_shell_test's create-dialog driving — match its pattern.
- Deferred: help-index highlighting.
