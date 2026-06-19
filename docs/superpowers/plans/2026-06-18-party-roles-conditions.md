# Party Roles + Conditions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A per-character role (pc/companion/npc) that groups the roster, plus a generic conditions list shown as roster badges and edited inline.

**Architecture:** Two additive `Character` fields (`role`, `conditions`) following the `starred` house pattern (default + omit-when-default JSON). `CharacterNotifier` gains `setRole`/`setConditions`. `CharactersPane` renders a grouped roster (Party/Companions/NPCs, lead = active PC) with a per-row role dropdown + condition badges + an inline condition editor. No engine change.

**Tech Stack:** Flutter, `flutter_riverpod`, `package:flutter_test`.

---

## File Structure

**Modify:**
- `lib/engine/models.dart` — `CharacterRole`, `Character.role`, `Character.conditions`, `kConditions`.
- `lib/state/providers.dart` — `CharacterNotifier.setRole` / `setConditions`.
- `lib/features/tracker_screen.dart` — grouped roster, role dropdown, condition badges, inline editor, create-role defaults.
- `CLAUDE.md`.

**Test:** `test/character_provider_test.dart`, `test/character_sheet_ui_test.dart` (or a new `test/party_roster_test.dart`).

---

### Task 1: Character.role + conditions + kConditions

**Files:**
- Modify: `lib/engine/models.dart` (Character, lines 1978-2089)
- Test: `test/character_provider_test.dart` (append a model group) or `test/models_*`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';

void main() {
  group('Character.role + conditions', () {
    test('defaults: role pc, no conditions, omitted from json', () {
      const c = Character(id: 'a', name: 'A');
      expect(c.role, CharacterRole.pc);
      expect(c.conditions, isEmpty);
      expect(c.toJson().containsKey('role'), isFalse);
      expect(c.toJson().containsKey('conditions'), isFalse);
    });
    test('npc role + conditions round-trip', () {
      const c = Character(
          id: 'a', name: 'A', role: CharacterRole.npc,
          conditions: ['poisoned', 'hurt']);
      final back = Character.fromJson(c.toJson());
      expect(back.role, CharacterRole.npc);
      expect(back.conditions, ['poisoned', 'hurt']);
    });
    test('copyWith updates role + conditions', () {
      const c = Character(id: 'a', name: 'A');
      final c2 = c.copyWith(role: CharacterRole.companion, conditions: ['hidden']);
      expect(c2.role, CharacterRole.companion);
      expect(c2.conditions, ['hidden']);
    });
    test('kConditions has the authored presets', () {
      expect(kConditions, contains('poisoned'));
      expect(kConditions, contains('exhausted'));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/character_provider_test.dart`
Expected: FAIL — `CharacterRole` / `role` / `conditions` undefined.

- [ ] **Step 3: Add the enum, fields, and presets**

In `lib/engine/models.dart`, add near `Character`:

```dart
enum CharacterRole { pc, companion, npc }

CharacterRole _roleFromName(String? n) => switch (n) {
      'companion' => CharacterRole.companion,
      'npc' => CharacterRole.npc,
      _ => CharacterRole.pc,
    };

/// Authored, system-agnostic status conditions (facts-only). Free-text custom
/// conditions are also allowed.
const kConditions = <String>[
  'poisoned', 'hurt', 'afraid', 'hidden', 'prone',
  'restrained', 'stunned', 'exhausted', 'sick', 'marked', 'blessed',
];
```

In `Character`: add the constructor params `this.role = CharacterRole.pc` and
`this.conditions = const []`; the fields `final CharacterRole role;` /
`final List<String> conditions;`; extend `copyWith` with `CharacterRole? role`
and `List<String>? conditions` (→ `role: role ?? this.role`,
`conditions: conditions ?? this.conditions`); extend `toJson` with
`if (role != CharacterRole.pc) 'role': role.name` and
`if (conditions.isNotEmpty) 'conditions': conditions`; extend `fromJson` with
`role: _roleFromName(j['role'] as String?)` and
`conditions: ((j['conditions'] as List?) ?? const []).whereType<String>().toList()`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/character_provider_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/models.dart test/character_provider_test.dart
git commit -m "feat(party): Character.role + conditions + kConditions presets"
```

---

### Task 2: CharacterNotifier.setRole / setConditions

**Files:**
- Modify: `lib/state/providers.dart` (`CharacterNotifier`, near `toggleStarred`)
- Test: `test/character_provider_test.dart` (append)

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

// inside main():
  group('CharacterNotifier role/conditions', () {
    test('setRole + setConditions persist', () async {
      SharedPreferences.setMockInitialValues({
        'juice.sessions.v1':
            '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
        'juice.characters.v1.default':
            '[{"id":"c1","name":"Ash","stats":[],"tracks":[],"tags":[]}]',
      });
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(charactersProvider.future);
      await c.read(charactersProvider.notifier).setRole('c1', CharacterRole.npc);
      await c.read(charactersProvider.notifier)
          .setConditions('c1', ['poisoned']);
      final ch = (await c.read(charactersProvider.future)).single;
      expect(ch.role, CharacterRole.npc);
      expect(ch.conditions, ['poisoned']);
    });
  });
```

(Merge imports with the file's existing ones.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/character_provider_test.dart -n "role/conditions"`
Expected: FAIL — `setRole`/`setConditions` undefined.

- [ ] **Step 3: Add the methods**

In `CharacterNotifier` (mirror `toggleStarred`/`replace` — read them first to
match the `_ready`/`replace` pattern exactly):

```dart
  Future<void> setRole(String id, CharacterRole role) async {
    final list = await _ready;
    final c = list.where((e) => e.id == id).firstOrNull;
    if (c == null) return;
    await replace(c.copyWith(role: role));
  }

  Future<void> setConditions(String id, List<String> conditions) async {
    final list = await _ready;
    final c = list.where((e) => e.id == id).firstOrNull;
    if (c == null) return;
    await replace(c.copyWith(conditions: conditions));
  }
```

(If `CharacterNotifier` exposes a different ready/lookup idiom than `_ready` +
`replace`, match whatever `toggleStarred` uses.)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/character_provider_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/state/providers.dart test/character_provider_test.dart
git commit -m "feat(party): CharacterNotifier.setRole + setConditions"
```

---

### Task 3: Grouped roster (Party / Companions / NPCs) + lead + role dropdown

**Files:**
- Modify: `lib/features/tracker_screen.dart` (the list view, lines 212-252)
- Test: `test/character_sheet_ui_test.dart` (append)

- [ ] **Step 1: Write the failing test**

```dart
  testWidgets('roster groups by role with headers', (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.characters.v1.default':
          '[{"id":"p1","name":"Tarin","role":null,"stats":[],"tracks":[],"tags":[]},'
          '{"id":"n1","name":"Veyra","role":"npc","stats":[],"tracks":[],"tags":[]}]',
    });
    // NOTE: 'role':null serializes as absent → pc. Build the JSON without the
    // role key for the pc, and with "role":"npc" for the npc.
    await pump(tester); // use the file's existing CharactersPane pump helper
    expect(find.text('Party'), findsOneWidget);
    expect(find.text('NPCs'), findsOneWidget);
    expect(find.text('Companions'), findsNothing); // empty group hidden
  });

  testWidgets('role dropdown re-tags a character', (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.characters.v1.default':
          '[{"id":"p1","name":"Tarin","stats":[],"tracks":[],"tags":[]}]',
    });
    final c = await pumpContainer(tester); // helper returning the container
    await tester.tap(find.byKey(const Key('role-p1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('NPC').last);
    await tester.pumpAndSettle();
    expect((await c.read(charactersProvider.future)).single.role,
        CharacterRole.npc);
  });
```

(Use `character_sheet_ui_test.dart`'s existing `pump`/container helper; fix the
seeded JSON so the pc row omits `role` and the npc row has `"role":"npc"`.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/character_sheet_ui_test.dart -n "groups by role"`
Expected: FAIL — no group headers / no `role-` key.

- [ ] **Step 3: Replace the flat list with a grouped list**

In `tracker_screen.dart`, replace the `ListView.builder` (lines 212-252) with a
grouped `ListView` (or `CustomScrollView`). Partition into buckets, render only
non-empty groups, each with a header + the existing per-character `Card`:

```dart
    final active =
        ref.watch(playContextProvider).valueOrNull?.activeCharacterId;
    final groups = <(String, CharacterRole)>[
      ('Party', CharacterRole.pc),
      ('Companions', CharacterRole.companion),
      ('NPCs', CharacterRole.npc),
    ];
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final (label, role) in groups)
          if (chars.any((c) => c.role == role)) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
              child: Text(label,
                  style: Theme.of(context).textTheme.labelMedium),
            ),
            for (final c in chars.where((c) => c.role == role))
              _rosterCard(context, c, isLead: c.id == active),
          ],
      ],
    );
```

Extract the existing per-row `Card`/`ListTile` (with star, delete, tap → set
active + open sheet) into `_rosterCard(BuildContext, Character, {bool isLead})`,
preserving all current behavior. ADD inside its trailing `Row`, before the star:

```dart
            PopupMenuButton<CharacterRole>(
              key: Key('role-${c.id}'),
              initialValue: c.role,
              tooltip: 'Role',
              onSelected: (r) =>
                  ref.read(charactersProvider.notifier).setRole(c.id, r),
              itemBuilder: (_) => const [
                PopupMenuItem(value: CharacterRole.pc, child: Text('PC')),
                PopupMenuItem(
                    value: CharacterRole.companion, child: Text('Companion')),
                PopupMenuItem(value: CharacterRole.npc, child: Text('NPC')),
              ],
            ),
```

And in the title, when `isLead`, append a small "lead" badge (a `Chip`/`Text`
with the info color). Keep `star-char-<id>` / delete / tap exactly as they are.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/character_sheet_ui_test.dart`
Expected: PASS. (Existing roster tests that find a character row by name still
work — grouping doesn't change names; only adds headers. If a test does
`find.byType(ListTile)` count, adjust for the new structure.)
Run: `flutter analyze lib/features/tracker_screen.dart`
Expected: No issues.

- [ ] **Step 5: Commit**

```bash
git add lib/features/tracker_screen.dart test/character_sheet_ui_test.dart
git commit -m "feat(party): role-grouped roster (Party/Companions/NPCs) + lead + role dropdown"
```

---

### Task 4: Condition badges + inline editor

**Files:**
- Modify: `lib/features/tracker_screen.dart` (`_rosterCard` + a `_editConditions`)
- Test: `test/character_sheet_ui_test.dart` (append)

- [ ] **Step 1: Write the failing test**

```dart
  testWidgets('condition badges show and inline editor toggles them',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.characters.v1.default':
          '[{"id":"p1","name":"Tarin","stats":[],"tracks":[],"tags":[],'
          '"conditions":["poisoned"]}]',
    });
    final c = await pumpContainer(tester);
    expect(find.text('poisoned'), findsWidgets); // badge on the row
    await tester.tap(find.byKey(const Key('conditions-p1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('hidden')); // toggle a preset on in the editor
    await tester.pumpAndSettle();
    // close the editor (a Done/OK button) then assert it persisted:
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    final ch = (await c.read(charactersProvider.future)).single;
    expect(ch.conditions, containsAll(['poisoned', 'hidden']));
  });
```

(Match the editor's actual close-affordance label you implement in Step 3, e.g.
`Done`.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/character_sheet_ui_test.dart -n "condition badges"`
Expected: FAIL — no `conditions-p1` key / no badges.

- [ ] **Step 3: Add badges + the inline editor**

In `_rosterCard`, below the `ListTile` (e.g. wrap the card content in a Column or
use the ListTile `subtitle`/an extra row), render the condition badges + a `+`:

```dart
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 12, 8),
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final cond in c.conditions)
                  Chip(
                    label: Text(cond),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ActionChip(
                  key: Key('conditions-${c.id}'),
                  avatar: const Icon(Icons.add, size: 16),
                  label: const Text('condition'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _editConditions(context, c),
                ),
              ],
            ),
          ),
```

Add the editor method:

```dart
  Future<void> _editConditions(BuildContext context, Character c) async {
    final selected = {...c.conditions};
    final customCtrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('${c.name} — conditions'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final cond in {...kConditions, ...c.conditions})
                      FilterChip(
                        label: Text(cond),
                        selected: selected.contains(cond),
                        onSelected: (on) => setLocal(() =>
                            on ? selected.add(cond) : selected.remove(cond)),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: customCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Add custom condition'),
                  onSubmitted: (v) {
                    final t = v.trim();
                    if (t.isNotEmpty) setLocal(() => selected.add(t));
                    customCtrl.clear();
                  },
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
    await ref
        .read(charactersProvider.notifier)
        .setConditions(c.id, selected.toList());
  }
```

(`setConditions` is called once on close with the final set. The custom text
field commits on submit into `selected`; trims blanks; the `Set` dedupes.)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/character_sheet_ui_test.dart`
Expected: PASS.
Run: `flutter analyze lib/features/tracker_screen.dart`
Expected: No issues.

- [ ] **Step 5: Commit**

```bash
git add lib/features/tracker_screen.dart test/character_sheet_ui_test.dart
git commit -m "feat(party): condition badges + inline condition editor"
```

---

### Task 5: Create-role defaults (Generate NPC → npc)

**Files:**
- Modify: `lib/features/tracker_screen.dart` (`_generateNpc`; confirm add/sheet default pc)
- Test: `test/character_sheet_ui_test.dart` (append)

- [ ] **Step 1: Write the failing test**

```dart
  testWidgets('Generate NPC creates an npc-role character', (tester) async {
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
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect((await c.read(charactersProvider.future)).single.role,
        CharacterRole.npc);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/character_sheet_ui_test.dart -n "Generate NPC creates an npc-role"`
Expected: FAIL — generated character defaults to pc.

- [ ] **Step 3: Set the npc role on the generated character**

In `_generateNpc` (tracker_screen.dart), after creating the character via
`notifier.add(...)` and before/with the note `replace`, set the role to npc. The
cleanest: after the existing `added` is resolved, call
`notifier.setRole(added.id, CharacterRole.npc)` (or fold role into the same
`copyWith` that sets the note). Read the current `_generateNpc` body and make
the minimal change so the created character is `role: npc`. (Add/sheet creators
already default to `pc` via the model default — no change needed there.)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/character_sheet_ui_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/tracker_screen.dart test/character_sheet_ui_test.dart
git commit -m "feat(party): Generate NPC tags the created character as npc"
```

---

### Task 6: Full verify + docs

- [ ] **Step 1:** `flutter analyze` → No issues; `flutter test` → all pass.
- [ ] **Step 2:** Add a `CLAUDE.md` project note:

```markdown
- **Party roles + conditions.** `Character.role` (`CharacterRole {pc, companion,
  npc}`, default pc) groups the Sheet roster into Party / Companions / NPCs
  (empty groups hidden; the active PC `playContextProvider.activeCharacterId` is
  marked "lead"); a per-row role `PopupMenuButton` (`role-<id>`) re-tags.
  `Character.conditions` (generic `List<String>`; presets in `kConditions` +
  free-text) shows as roster badges with an inline editor (`conditions-<id>` →
  `_editConditions`). `CharacterNotifier.setRole`/`setConditions` persist.
  Create defaults: Add + sheet creators → pc, Generate NPC → npc. See
  `docs/superpowers/specs/2026-06-18-party-roles-conditions-design.md`. Deferred:
  lead→subordinate nesting, companion↔party-emulator auto-link, per-sheet
  condition surfacing.
```

- [ ] **Step 3:** Commit `docs(party): document roles + conditions`.

---

## Self-Review

**1. Spec coverage:** role + grouping (T1/T3), conditions + inline editor (T1/T4), notifier setRole/setConditions (T2), lead marker (T3), create defaults (T5), docs (T6). ✓
**2. Placeholder scan:** none; the "match the existing helper/pattern" notes point at concrete existing code (toggleStarred, the pump helper, _generateNpc).
**3. Type consistency:** `CharacterRole{pc,companion,npc}`, `Character.role`/`.conditions`, `kConditions`, `setRole(String,CharacterRole)`, `setConditions(String,List<String>)`, `_rosterCard(...,{isLead})`, `_editConditions(context,c)`, keys `role-<id>`/`conditions-<id>` — consistent across tasks.
