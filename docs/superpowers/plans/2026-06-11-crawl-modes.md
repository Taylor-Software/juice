# Stateful Crawl Modes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wilderness exploration and dungeon crawling become stateful — environment drifts hex to hex, Lost/Found cycles per the Juice rules, dungeons distinguish first-entry from lingering — with crawl state (and the NPC dialog marker) persisted across app restarts.

**Architecture:** Engine stays pure where possible: `wildernessTravel` is state-in/state-out (takes a `WildernessState`, returns result + new state). Dungeon linger reuses the existing encounter expansion via an extracted helper. Persistence follows the established Riverpod + SharedPreferences pattern (`AsyncNotifier`, JSON string key). The Generators screen gains a small Crawl section for the three stateful generators; the stateless `_gens` chip list is untouched except for removing the superseded Wilderness Step.

**Tech Stack:** Dart/Flutter, flutter_riverpod, shared_preferences, `package:test` via `flutter test`. No new dependencies.

---

**Rules being implemented (from the Juice instructions, verified locations):**
- *Lost/Found* (~line 2297): exploring rolls the Wilderness Encounter table with d10; rolling result 10 (Destination/Lost) makes you **Lost**; while Lost you roll **d6** on the encounter table (more dangerous bottom rows); rolling 6 (River/Road) while Lost reorients you (back to d10).
- *Environment drift* (Wilderness table header `2dF Env`): each travel step drifts the environment row by the sum of 2 fate dice from the current row (clamped 1..10), instead of re-rolling fresh.
- *Dungeon die size* (~line 3868): d10 on the Dungeon Encounter table when entering an area first time; **d6 when lingering** in an unsafe area (also: Natural Hazard sub-roll uses d6 when lingering).

**Known simplification (pre-existing, unchanged):** weather is a plain d10 pick; the PDF's `1d6@E+T` weather formula needs per-row type offsets our data doesn't carry. Out of scope here.

**Engine API note:** `npcDialog()` keeps its existing signature and internal state (PR #2); this plan adds position getter/restore so the provider can persist it.

### Task 1: Crawl state models

**Files:**
- Modify: `lib/engine/models.dart` (append at end)
- Test: `test/crawl_test.dart` (create)

- [ ] **Step 1: Write the failing test**

Create `test/crawl_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:juice_oracle/engine/models.dart';

void main() {
  group('CrawlState model', () {
    test('defaults: no environment yet, not lost, dialog at center', () {
      const s = CrawlState();
      expect(s.envRow, isNull);
      expect(s.lost, isFalse);
      expect(s.dialogRow, 2);
      expect(s.dialogCol, 2);
    });

    test('json round-trip preserves all fields', () {
      const s = CrawlState(envRow: 7, lost: true, dialogRow: 0, dialogCol: 4);
      final back = CrawlState.fromJson(s.toJson());
      expect(back.envRow, 7);
      expect(back.lost, isTrue);
      expect(back.dialogRow, 0);
      expect(back.dialogCol, 4);
    });

    test('copyWith can clear envRow via sentinel', () {
      const s = CrawlState(envRow: 3, lost: true);
      final reset = s.copyWith(clearEnvRow: true, lost: false);
      expect(reset.envRow, isNull);
      expect(reset.lost, isFalse);
      expect(reset.dialogRow, 2);
    });
  });
}
```

Note the import package name: check `pubspec.yaml` `name:` field (it is `juice_oracle`); existing tests import the same way — match them.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/crawl_test.dart`
Expected: FAIL — `CrawlState` not defined.

- [ ] **Step 3: Implement the model**

Append to `lib/engine/models.dart`:

```dart
/// Persisted crawl-mode state: wilderness position + NPC dialog marker.
class CrawlState {
  const CrawlState({
    this.envRow,
    this.lost = false,
    this.dialogRow = 2,
    this.dialogCol = 2,
  });

  /// Current wilderness environment row 1..10; null until first travel step.
  final int? envRow;

  /// Lost per the Juice Lost/Found cycle (encounter rolls drop to d6).
  final bool lost;

  /// NPC dialog marker on the 5x5 grid (center "Fact" = 2,2).
  final int dialogRow;
  final int dialogCol;

  CrawlState copyWith({
    int? envRow,
    bool clearEnvRow = false,
    bool? lost,
    int? dialogRow,
    int? dialogCol,
  }) =>
      CrawlState(
        envRow: clearEnvRow ? null : (envRow ?? this.envRow),
        lost: lost ?? this.lost,
        dialogRow: dialogRow ?? this.dialogRow,
        dialogCol: dialogCol ?? this.dialogCol,
      );

  Map<String, dynamic> toJson() => {
        'envRow': envRow,
        'lost': lost,
        'dialogRow': dialogRow,
        'dialogCol': dialogCol,
      };

  factory CrawlState.fromJson(Map<String, dynamic> j) => CrawlState(
        envRow: j['envRow'] as int?,
        lost: (j['lost'] as bool?) ?? false,
        dialogRow: (j['dialogRow'] as int?) ?? 2,
        dialogCol: (j['dialogCol'] as int?) ?? 2,
      );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/crawl_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/engine/models.dart test/crawl_test.dart
git commit -m "feat: CrawlState model for wilderness + dialog persistence"
```

### Task 2: Stateful wilderness travel in the engine

**Files:**
- Modify: `lib/engine/oracle.dart` (replace `wildernessStep`, lines ~156-160)
- Test: `test/crawl_test.dart` (append group)

- [ ] **Step 1: Write the failing test**

Append to `test/crawl_test.dart` (add imports `dart:convert`, `dart:io`, and the engine/oracle + oracle_data imports matching how `test/fate_engine_test.dart` loads the asset — copy its `setUpAll` JSON-load pattern exactly, including any `TestWidgetsFlutterBinding` line it uses):

```dart
  group('Wilderness travel state machine', () {
    late OracleData data; // loaded in setUpAll exactly like fate_engine_test.dart

    test('first step rolls an environment; later steps drift by at most 2', () {
      final oracle = Oracle(data);
      for (var i = 0; i < 500; i++) {
        final first = oracle.wildernessTravel(const CrawlState());
        final env1 = first.state.envRow!;
        expect(env1, inInclusiveRange(1, 10));
        final second = oracle.wildernessTravel(first.state);
        final env2 = second.state.envRow!;
        expect((env2 - env1).abs(), lessThanOrEqualTo(2));
        expect(env2, inInclusiveRange(1, 10));
      }
    });

    test('rolling encounter 10 while exploring sets lost; 6 while lost clears it', () {
      final oracle = Oracle(data);
      var state = const CrawlState();
      var sawLost = false;
      var sawFound = false;
      for (var i = 0; i < 5000; i++) {
        final wasLost = state.lost;
        final r = oracle.wildernessTravel(state);
        final enc = r.result.rolls.firstWhere((x) => x.label == 'Encounter');
        if (!wasLost && r.state.lost) {
          sawLost = true;
          expect(enc.value, 'Destination/Lost');
        }
        if (wasLost && !r.state.lost) {
          sawFound = true;
          expect(enc.value, 'River/Road');
        }
        if (wasLost) {
          // lost rolls use a d6: only the first six encounter entries possible
          final idx = data.table('wilderness_encounter').indexOf(enc.value);
          expect(idx, lessThan(6));
        }
        state = r.state;
      }
      expect(sawLost, isTrue);
      expect(sawFound, isTrue);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/crawl_test.dart`
Expected: FAIL — `wildernessTravel` not defined.

- [ ] **Step 3: Implement**

In `lib/engine/oracle.dart`, replace the existing `wildernessStep()` method with:

```dart
  /// One stateful wilderness travel step (replaces the stateless
  /// Wilderness Step). Environment drifts by 2dF from the previous hex
  /// (header "2dF Env"); Lost/Found cycle per instructions p73:
  /// encounter 10 while exploring -> Lost (d6 encounters);
  /// encounter 6 (River/Road) while Lost -> reoriented.
  ({GenResult result, CrawlState state}) wildernessTravel(CrawlState s) {
    final env = s.envRow == null
        ? dice.d10Index()
        : (s.envRow! + dice.fate() + dice.fate()).clamp(1, 10);
    final encIdx = s.lost ? dice.dN(6) : dice.d10Index();
    final encounter = data.table('wilderness_encounter')[encIdx - 1];
    var lost = s.lost;
    String? note;
    if (!lost && encIdx == 10) {
      lost = true;
      note = 'You are now Lost — encounters drop to a d6';
    } else if (lost && encIdx == 6) {
      lost = false;
      note = 'Reoriented — no longer Lost';
    }
    final rolls = <Roll>[
      Roll(
          label: 'Environment',
          value: data.table('wilderness_environment')[env - 1],
          detail: s.envRow == null ? 'd10 ${d10Label(env)}' : '2dF drift'),
      Roll(
          label: 'Encounter',
          value: encounter,
          detail: s.lost ? 'd6 $encIdx (lost)' : 'd10 ${d10Label(encIdx)}'),
      Roll(label: 'Weather', value: _pick('wilderness_weather')),
    ];
    return (
      result: GenResult(title: 'Wilderness Travel', summary: note, rolls: rolls),
      state: s.copyWith(envRow: env, lost: lost),
    );
  }
```

Type note: `.clamp(1, 10)` on an int returns `num` in some contexts — if the analyzer complains assigning to `final env` used as int, write `(s.envRow! + dice.fate() + dice.fate()).clamp(1, 10).toInt()`.

Grep check before committing: `grep -rn "wildernessStep" lib/ test/` — the only caller is the `'Wilderness Step'` chip in `lib/features/generators_screen.dart`. Removing the method now breaks the build, so in THIS task also delete that one chip line (`_Gen('Wilderness Step', (o) => o.wildernessStep()),`); the replacement UI lands in Task 6.

- [ ] **Step 4: Run tests + analyze**

Run: `flutter test && flutter analyze`
Expected: all tests pass (crawl + existing 18); 4 pre-existing infos only.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/oracle.dart lib/features/generators_screen.dart test/crawl_test.dart
git commit -m "feat: stateful wilderness travel with Lost/Found cycle"
```

### Task 3: Dungeon linger

**Files:**
- Modify: `lib/engine/oracle.dart` (`dungeonRoom`, lines ~173-205)
- Test: `test/crawl_test.dart` (append group)

- [ ] **Step 1: Write the failing test**

Append to `test/crawl_test.dart`:

```dart
  group('Dungeon linger', () {
    test('linger rolls d6: only first six encounter entries appear', () {
      final oracle = Oracle(data);
      final firstSix = data.table('dungeon_encounter').take(6).toList();
      for (var i = 0; i < 3000; i++) {
        final r = oracle.dungeonLinger();
        expect(r.title, 'Dungeon Linger');
        final enc = r.rolls.firstWhere((x) => x.label == 'Encounter');
        expect(firstSix, contains(enc.value));
      }
    });

    test('dungeonRoom still produces area, passage, condition, encounter', () {
      final oracle = Oracle(data);
      for (var i = 0; i < 500; i++) {
        final r = oracle.dungeonRoom();
        final labels = r.rolls.map((x) => x.label).toList();
        expect(labels,
            containsAll(['Next Area', 'Passage', 'Condition', 'Encounter']));
      }
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/crawl_test.dart`
Expected: FAIL — `dungeonLinger` not defined.

- [ ] **Step 3: Implement**

In `lib/engine/oracle.dart`, extract the encounter expansion from `dungeonRoom` into a shared helper, then add `dungeonLinger`. Replace the whole `dungeonRoom()` method with:

```dart
  /// Dungeon encounter roll + sub-roll expansion. First entry uses a d10;
  /// lingering >10 minutes in an unsafe area drops to a d6 (instructions
  /// p116), which also caps the Natural Hazard sub-roll at d6.
  List<Roll> _dungeonEncounterRolls({required bool linger}) {
    final encIdx = linger ? dice.dN(6) : dice.d10Index();
    final enc = data.table('dungeon_encounter')[encIdx - 1];
    final rolls = <Roll>[
      Roll(
          label: 'Encounter',
          value: enc,
          detail: linger ? 'd6 $encIdx' : 'd10 ${d10Label(encIdx)}'),
    ];
    switch (enc) {
      case 'Monster':
        rolls.add(Roll(
            label: 'Monster',
            value:
                '${_pick('monster_description')} / ${_pick('monster_ability')}'));
        break;
      case 'Trap':
        rolls.add(Roll(
            label: 'Trap',
            value: '${_pick('trap_action')} / ${_pick('trap_subject')}'));
        break;
      case 'Feature':
        rolls.add(Roll(label: 'Feature', value: _pick('dungeon_feature')));
        break;
      case 'Natural Hazard':
        final hazardIdx = linger ? dice.dN(6) : dice.d10Index();
        rolls.add(Roll(
            label: 'Hazard',
            value: data.table('natural_hazard')[hazardIdx - 1]));
        break;
      case 'Treasure':
        rolls.add(Roll(label: 'Treasure', value: treasure().summary ?? ''));
        break;
    }
    return rolls;
  }

  GenResult dungeonRoom() => GenResult(title: 'Dungeon Room', rolls: [
        Roll(label: 'Next Area', value: _pick('dungeon_next_area')),
        Roll(label: 'Passage', value: _pick('dungeon_passage')),
        Roll(label: 'Condition', value: _pick('dungeon_condition')),
        ..._dungeonEncounterRolls(linger: false),
      ]);

  /// Lingering in the current area: encounter-only roll at d6.
  GenResult dungeonLinger() =>
      GenResult(title: 'Dungeon Linger', rolls: _dungeonEncounterRolls(linger: true));
```

Behavior note (intentional, document in commit body): old `dungeonRoom` rolled the encounter *before* the area/passage/condition rolls; the refactor rolls it after. Roll order doesn't affect distributions (independent rolls). Also `dungeonRoom`'s encounter previously had no die detail; now it shows one — display-only improvement.

- [ ] **Step 4: Run tests + analyze**

Run: `flutter test && flutter analyze`
Expected: all pass; 4 pre-existing infos.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/oracle.dart test/crawl_test.dart
git commit -m "feat: dungeon linger (d6 encounters) via shared encounter expansion"
```

### Task 4: Dialog marker persistence hooks

**Files:**
- Modify: `lib/engine/oracle.dart` (next to `_dialogRow`/`_dialogCol` fields and `npcDialog()`)
- Test: `test/crawl_test.dart` (append group)

- [ ] **Step 1: Write the failing test**

Append to `test/crawl_test.dart`:

```dart
  group('Dialog marker persistence hooks', () {
    test('restore and read back the marker', () {
      final oracle = Oracle(data);
      oracle.restoreDialogPos(0, 4);
      expect(oracle.dialogPos, (row: 0, col: 4));
    });

    test('marker moves on a non-doubles beat and resets on doubles', () {
      final oracle = Oracle(data);
      var sawMove = false;
      var sawReset = false;
      for (var i = 0; i < 500; i++) {
        final before = oracle.dialogPos;
        final r = oracle.npcDialog();
        if (r.summary == 'Conversation ends') {
          expect(oracle.dialogPos, (row: 2, col: 2));
          sawReset = true;
        } else if (oracle.dialogPos != before) {
          sawMove = true;
        }
      }
      expect(sawMove, isTrue);
      expect(sawReset, isTrue);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/crawl_test.dart`
Expected: FAIL — `restoreDialogPos`/`dialogPos` not defined.

- [ ] **Step 3: Implement**

In `lib/engine/oracle.dart`, directly after the `_dialogRow`/`_dialogCol` field declaration, add:

```dart
  /// Current dialog marker, for persistence.
  ({int row, int col}) get dialogPos => (row: _dialogRow, col: _dialogCol);

  /// Restore a persisted dialog marker (values clamped to the 5x5 grid).
  void restoreDialogPos(int row, int col) {
    _dialogRow = row.clamp(0, 4);
    _dialogCol = col.clamp(0, 4);
  }
```

- [ ] **Step 4: Run tests + analyze**

Run: `flutter test && flutter analyze`
Expected: all pass; 4 pre-existing infos.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/oracle.dart test/crawl_test.dart
git commit -m "feat: dialog marker getter/restore for persistence"
```

### Task 5: Persisted crawl provider

**Files:**
- Modify: `lib/state/providers.dart` (append at end)
- Test: `test/crawl_test.dart` (append group)

- [ ] **Step 1: Write the failing test**

Append to `test/crawl_test.dart` (add imports: `package:flutter_riverpod/flutter_riverpod.dart`, `package:shared_preferences/shared_preferences.dart`, `package:juice_oracle/state/providers.dart`):

```dart
  group('Crawl provider persistence', () {
    test('loads persisted state and saves updates', () async {
      SharedPreferences.setMockInitialValues({
        'juice.crawl.v1':
            '{"envRow":4,"lost":true,"dialogRow":1,"dialogCol":3}',
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final loaded = await container.read(crawlProvider.future);
      expect(loaded.envRow, 4);
      expect(loaded.lost, isTrue);
      expect(loaded.dialogRow, 1);

      await container
          .read(crawlProvider.notifier)
          .save(const CrawlState(envRow: 9, lost: false));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('juice.crawl.v1'), contains('"envRow":9'));
    });

    test('reset returns to defaults and persists them', () async {
      SharedPreferences.setMockInitialValues({
        'juice.crawl.v1': '{"envRow":4,"lost":true,"dialogRow":1,"dialogCol":3}',
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(crawlProvider.future);
      await container.read(crawlProvider.notifier).reset();
      final state = await container.read(crawlProvider.future);
      expect(state.envRow, isNull);
      expect(state.lost, isFalse);
      expect(state.dialogRow, 2);
    });
  });
```

(`SharedPreferences.setMockInitialValues` needs `TestWidgetsFlutterBinding.ensureInitialized()` — the file already has it from the asset-loading setUp; if not, add it at the top of `main()`.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/crawl_test.dart`
Expected: FAIL — `crawlProvider` not defined.

- [ ] **Step 3: Implement**

Append to `lib/state/providers.dart`:

```dart
// -- Crawl state (wilderness + dialog marker) -------------------------------
class CrawlNotifier extends AsyncNotifier<CrawlState> {
  static const _key = 'juice.crawl.v1';

  @override
  Future<CrawlState> build() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const CrawlState();
    return CrawlState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> save(CrawlState s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(s.toJson()));
    state = AsyncData(s);
  }

  Future<void> reset() => save(const CrawlState());
}

final crawlProvider =
    AsyncNotifierProvider<CrawlNotifier, CrawlState>(CrawlNotifier.new);
```

- [ ] **Step 4: Run tests + analyze**

Run: `flutter test && flutter analyze`
Expected: all pass; 4 pre-existing infos.

- [ ] **Step 5: Commit**

```bash
git add lib/state/providers.dart test/crawl_test.dart
git commit -m "feat: persisted crawl provider (juice.crawl.v1)"
```

### Task 6: Crawl section in the Generators screen

**Files:**
- Modify: `lib/features/generators_screen.dart`

- [ ] **Step 1: Rewire the screen**

Changes (the `'Wilderness Step'` chip was already removed in Task 2; `'NPC Dialog'` chip moves out of `_gens` here):

1. Remove `_Gen('NPC Dialog', (o) => o.npcDialog()),` from `_gens`.
2. In `_GeneratorsScreenState.build`, add a Crawl section between the result card and the `_gens` chips. No extra helper methods — the chips inline their logic. Replace the whole build method with:

```dart
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = _last;
    final crawl = ref.watch(crawlProvider).valueOrNull ?? const CrawlState();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Generators', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 12),
        if (last != null) ...[
          ResultCard(
            result: last,
            onLog: () {
              ref.read(logProvider.notifier).add(last.title, last.asText);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Logged')),
              );
            },
          ),
          const SizedBox(height: 16),
        ],
        Text('Crawl', style: theme.textTheme.titleMedium),
        if (crawl.envRow != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${widget.oracle.data.table('wilderness_environment')[crawl.envRow! - 1]}'
              '${crawl.lost ? ' — LOST (d6 encounters)' : ''}',
              style: theme.textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ActionChip(
              label: const Text('Wilderness Travel'),
              onPressed: () {
                final r = widget.oracle.wildernessTravel(crawl);
                ref.read(crawlProvider.notifier).save(r.state);
                setState(() => _last = r.result);
              },
            ),
            ActionChip(
              label: const Text('Dungeon Linger'),
              onPressed: () =>
                  setState(() => _last = widget.oracle.dungeonLinger()),
            ),
            ActionChip(
              label: const Text('NPC Dialog'),
              onPressed: () {
                widget.oracle
                    .restoreDialogPos(crawl.dialogRow, crawl.dialogCol);
                final r = widget.oracle.npcDialog();
                final pos = widget.oracle.dialogPos;
                ref.read(crawlProvider.notifier).save(
                    crawl.copyWith(dialogRow: pos.row, dialogCol: pos.col));
                setState(() => _last = r);
              },
            ),
            ActionChip(
              label: const Text('Reset Crawl'),
              onPressed: () => ref.read(crawlProvider.notifier).reset(),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final g in _gens)
              ActionChip(
                label: Text(g.label),
                onPressed: () => _run(g),
              ),
          ],
        ),
      ],
    );
  }
```

Check `OracleData` is imported where needed (`widget.oracle.data.table(...)` — `data` is a public field on Oracle, already accessible; no new import beyond what the file has, but `CrawlState` needs `../engine/models.dart` which is already imported).

- [ ] **Step 2: Analyze + full tests**

Run: `flutter analyze && flutter test`
Expected: 4 pre-existing infos; all tests pass.

- [ ] **Step 3: Browser-verify (controller does this if executing via subagents — implementer skips)**

Build + preview: Generators tab shows Crawl section; Wilderness Travel twice → environment line appears and persists between taps; NPC Dialog beats continue a conversation across taps; Reset Crawl clears the environment line.

- [ ] **Step 4: Commit**

```bash
git add lib/features/generators_screen.dart
git commit -m "feat: Crawl section — stateful travel, linger, dialog, reset"
```

### Task 7: Documentation sync

**Files:**
- Modify: `README.md` (features list, if it enumerates generators)
- Modify: `CLAUDE.md` (project notes — persistence keys if listed)

- [ ] **Step 1: Update docs**

- README: if the feature list mentions "Wilderness Step", rename to "Wilderness Travel (stateful: environment drift + Lost/Found)" and add "Dungeon Linger". Read the file; make the minimal coherent edit. If no generator enumeration exists, no change.
- CLAUDE.md: no change unless it lists SharedPreferences keys (it doesn't as of this writing — verify with a grep for `juice.` and skip if absent).

- [ ] **Step 2: Commit (only if files changed)**

```bash
git add README.md CLAUDE.md
git commit -m "docs: stateful crawl modes"
```

## Self-review notes

- Spec coverage: roadmap line is "dungeon entering/exploring phases, wilderness lost/found, persisted" — entering/exploring = d10 `dungeonRoom` vs d6 `dungeonLinger` (Task 3); lost/found + env drift (Task 2); persistence incl. the dialog marker promised in PR #2's comment (Tasks 1, 4, 5); UI (Task 6).
- Type consistency: `wildernessTravel` returns `({GenResult result, CrawlState state})` — Task 6 uses `r.result`/`r.state`; `dialogPos` returns `({int row, int col})` — Task 6 uses `pos.row`/`pos.col`; `crawlProvider` is `AsyncNotifierProvider<CrawlNotifier, CrawlState>` — Task 6 watches `.valueOrNull`.
- Removal of `wildernessStep` is paired with its only call site in the same commit (Task 2) — no broken intermediate state.
- `clamp(1, 10)` num-vs-int noted where it occurs.
