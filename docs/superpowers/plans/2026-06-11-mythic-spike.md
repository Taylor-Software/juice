# Mythic GME Core Spike Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mythic GME 2e core mechanics — Chaos Factor, Fate Chart rolls, Scene Test, Event Focus that rolls against the player's actual Threads/Characters lists — as a section on the Fate tab, with per-session chaos persisted.

**Architecture:** Same verified-data pipeline: chart + focus data and mechanics encoded and self-verified in `build_oracle.py` (the 2e Fate Chart is diagonal-generated from a 17-entry threshold ladder — encode the ladder + band formula, verify cells against published triples), emitted into the asset, typed accessors, Dart engine mirrors Python, UI consumes. Chaos lives on `CrawlState` (the per-session play-state bucket) so it persists, survives campaign export/import (additive field, schema stays v1), and resets with Reset Crawl.

**Tech Stack:** Existing only — Python 3, Dart/Flutter, riverpod, shared_preferences. No new dependencies.

---

**Sourced mechanics (cross-verified against the published 2e chart triples and two independent open-source implementations — idispatch75/mythic-gme-adventures and saif-ellafi/foundryvtt-mythic-gme):**

- **Odds rows** (top→bottom): Certain, Nearly Certain, Very Likely, Likely, 50/50, Unlikely, Very Unlikely, Nearly Impossible, Impossible.
- **Threshold ladder** (17 entries): `[99,99,99,95,90,85,75,65,50,35,25,15,10,5,1,1,1]`. Cell target for (oddsIndex 0..8, chaos 1..9) = `ladder[9 - chaos + oddsIndex]`.
- **Exceptional bands** for target T: exceptional yes ≤ `T*20//100`, exceptional no ≥ `100 - ((100-T)*20//100) + 1`; published special cases: T=1 → (0, 1, 81), T=99 → (20, 99, 101).
- **Known cells to verify against** (excYes, target, excNo): chaos 5 / 50-50 → (10, 50, 91); chaos 1 / Certain → (10, 50, 91); chaos 1 / Nearly Certain → (7, 35, 88); chaos 2 / Certain → (13, 65, 94).
- **Random event on a fate roll:** d100 with equal tens and units digits where the digit ≤ chaos (i.e. `roll < 100 && roll % 11 == 0 && roll ~/ 11 <= chaos`).
- **Scene Test:** 1d10; ≤ chaos → even = Interrupted Scene, odd = Altered Scene; else Expected Scene. Chaos adjusts ±1 at scene end by player judgment (the UI dial covers this).
- **Event Focus** (d100, ranges → label → list target kind):
  1–5 Remote Event · 6–10 Ambiguous Event · 11–20 New NPC · 21–40 NPC Action (character) · 41–45 NPC Negative (character) · 46–50 NPC Positive (character) · 51–55 Move toward a Thread (thread) · 56–65 Move away from a Thread (thread) · 66–70 Close a Thread (thread) · 71–80 PC Negative · 81–85 PC Positive · 86–100 Current Context.
- **License:** Mythic text CC-BY-NC (Word Mill Games). App is free; attribution rendered in the UI section and README.

### Task 1: Python data + mechanics + verification

**Files:**
- Modify: `build_oracle.py` (data after the dialog tables; mechanics near `monster_encounter`; checks in `verify()` as section 8; emission in `emit_json`)
- Modify: `assets/oracle_data.json` (regenerated)

- [ ] **Step 1: Add the data**

```python
# Mythic GME 2e core (Word Mill Games, CC-BY-NC 4.0; attribution rendered
# in-app). Fate Chart is diagonal-generated from a 17-entry threshold
# ladder; cell (odds_index, chaos) = ladder[9 - chaos + odds_index].
MYTHIC_ODDS = ["Certain", "Nearly Certain", "Very Likely", "Likely",
               "50/50", "Unlikely", "Very Unlikely", "Nearly Impossible",
               "Impossible"]
MYTHIC_LADDER = [99, 99, 99, 95, 90, 85, 75, 65, 50, 35, 25, 15, 10, 5, 1, 1, 1]

def mythic_bands(t):
    """(exceptional_yes_max, target, exceptional_no_min) for target t."""
    if t == 1:
        return (0, 1, 81)
    if t == 99:
        return (20, 99, 101)
    return (t * 20 // 100, t, 100 - ((100 - t) * 20 // 100) + 1)

def mythic_target(odds_index, chaos):
    return MYTHIC_LADDER[9 - chaos + odds_index]

# (max_roll, label, list_target) — list_target: which tracker list the
# event points at, or None.
MYTHIC_EVENT_FOCUS = [
    (5, "Remote Event", None),
    (10, "Ambiguous Event", None),
    (20, "New NPC", None),
    (40, "NPC Action", "character"),
    (45, "NPC Negative", "character"),
    (50, "NPC Positive", "character"),
    (55, "Move toward a Thread", "thread"),
    (65, "Move away from a Thread", "thread"),
    (70, "Close a Thread", "thread"),
    (80, "PC Negative", None),
    (85, "PC Positive", None),
    (100, "Current Context", None),
]
```

- [ ] **Step 2: Add the mechanics function (for simulation verification)**

```python
def mythic_fate(odds_index, chaos):
    """Roll the 2e Fate Chart. Returns answer + random-event flag."""
    exc_yes, target, exc_no = mythic_bands(mythic_target(odds_index, chaos))
    roll = d(100)
    if roll <= exc_yes:
        answer = "Exceptional Yes"
    elif roll <= target:
        answer = "Yes"
    elif roll < exc_no:
        answer = "No"
    else:
        answer = "Exceptional No"
    random_event = roll < 100 and roll % 11 == 0 and roll // 11 <= chaos
    return {"roll": roll, "answer": answer, "random_event": random_event}
```

- [ ] **Step 3: Add verify() section 8**

```python
    # 8. Mythic 2e fate chart + event focus.
    if len(MYTHIC_LADDER) != 17 or len(MYTHIC_ODDS) != 9:
        failures.append("mythic ladder/odds shape wrong")
    # Published cell triples (excYes, target, excNo).
    for (oi, chaos, expected) in [
        (4, 5, (10, 50, 91)),   # 50/50 at chaos 5
        (0, 1, (10, 50, 91)),   # Certain at chaos 1
        (1, 1, (7, 35, 88)),    # Nearly Certain at chaos 1
        (0, 2, (13, 65, 94)),   # Certain at chaos 2
    ]:
        got = mythic_bands(mythic_target(oi, chaos))
        if got != expected:
            failures.append(f"mythic cell odds={oi} chaos={chaos}: {got} != {expected}")
    # Monotonicity: more chaos -> target never drops; worse odds -> never rises.
    for oi in range(9):
        targets = [mythic_target(oi, c) for c in range(1, 10)]
        if targets != sorted(targets):
            failures.append(f"mythic targets not monotonic in chaos for odds {oi}")
    for c in range(1, 10):
        col = [mythic_target(oi, c) for oi in range(9)]
        if col != sorted(col, reverse=True):
            failures.append(f"mythic targets not monotonic in odds for chaos {c}")
    # Event focus: increasing thresholds ending at 100.
    focus_maxes = [m for m, _, _ in MYTHIC_EVENT_FOCUS]
    if focus_maxes != sorted(focus_maxes) or focus_maxes[-1] != 100 or \
            len(set(focus_maxes)) != len(focus_maxes):
        failures.append("mythic event focus ranges malformed")
    # Simulation: 50/50 at chaos 5 -> ~50% yes-like, ~10% each exceptional,
    # random event rate ~5% (doubles 11..55).
    sims = [mythic_fate(4, 5) for _ in range(N)]
    yes_like = sum(s["answer"].endswith("Yes") for s in sims) / N
    exc = sum(s["answer"] == "Exceptional Yes" for s in sims) / N
    re_rate = sum(s["random_event"] for s in sims) / N
    if abs(yes_like - 0.50) > 0.01:
        failures.append(f"mythic 50/50 yes-like {yes_like:.3f} != ~0.50")
    if abs(exc - 0.10) > 0.005:
        failures.append(f"mythic exceptional-yes {exc:.4f} != ~0.10")
    if abs(re_rate - 0.05) > 0.005:
        failures.append(f"mythic random-event rate {re_rate:.4f} != ~0.05")
```

- [ ] **Step 4: Emit (in `emit_json` after the `"dialog"` entry)**

```python
        "mythic": {
            "odds": MYTHIC_ODDS,
            "bands": [list(mythic_bands(t)) for t in MYTHIC_LADDER],
            "event_focus": [list(e) for e in MYTHIC_EVENT_FOCUS],
        },
```

(`bands` is the 17-entry ladder as (excYes, target, excNo) triples; Dart
indexes it with the same `9 - chaos + oddsIndex` window — no formula
duplication in Dart.)

- [ ] **Step 5: Build, regenerate, commit**

```bash
python3 build_oracle.py && cp oracle_data.json assets/oracle_data.json
python3 -c "import json; d=json.load(open('assets/oracle_data.json')); m=d['mythic']; print(len(m['odds']), len(m['bands']), len(m['event_focus']))"
```
Expected: `All engine verifications passed.` then `9 17 12`.

```bash
git add build_oracle.py assets/oracle_data.json
git commit -m "feat: encode Mythic 2e fate chart + event focus, source-verified"
```

### Task 2: Dart accessors + chaos on CrawlState

**Files:**
- Modify: `lib/engine/oracle_data.dart` (append before `allTableKeys`)
- Modify: `lib/engine/models.dart` (CrawlState)
- Test: `test/mythic_test.dart` (create)

- [ ] **Step 1: Write the failing test**

Create `test/mythic_test.dart` (copy the asset-load pattern from `test/fate_engine_test.dart` — top-level `_loadData()` + binding init):

```dart
  group('Mythic data integrity', () {
    test('odds, bands ladder, and focus ranges have the right shape', () {
      expect(data.mythicOdds.length, 9);
      expect(data.mythicBands.length, 17);
      for (final band in data.mythicBands) {
        expect(band.length, 3);
      }
      expect(data.mythicEventFocus.length, 12);
      expect(data.mythicEventFocus.last[0], 100);
    });
  });

  group('CrawlState chaos factor', () {
    test('defaults to 5 and round-trips', () {
      const s = CrawlState();
      expect(s.chaosFactor, 5);
      final back = CrawlState.fromJson(
          const CrawlState(chaosFactor: 8).toJson());
      expect(back.chaosFactor, 8);
    });

    test('older persisted json without the field defaults to 5', () {
      final s = CrawlState.fromJson({'envRow': 3, 'lost': false});
      expect(s.chaosFactor, 5);
    });
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/mythic_test.dart`
Expected: FAIL — accessors and field undefined.

- [ ] **Step 3: Implement**

`lib/engine/oracle_data.dart` (append before `allTableKeys`):

```dart
  // Mythic GME 2e --------------------------------------------------------
  Map<String, dynamic> get _mythic => _json['mythic'] as Map<String, dynamic>;

  /// Odds labels, Certain..Impossible.
  List<String> get mythicOdds =>
      (_mythic['odds'] as List).cast<String>();

  /// 17-entry threshold ladder of [excYesMax, target, excNoMin]; cell for
  /// (oddsIndex, chaos) is index `9 - chaos + oddsIndex`.
  List<List<int>> get mythicBands => (_mythic['bands'] as List)
      .map((e) => (e as List).cast<int>())
      .toList();

  /// [maxRoll, label, listTarget|null] event focus ranges.
  List<List<dynamic>> get mythicEventFocus =>
      (_mythic['event_focus'] as List).map((e) => e as List).toList();
```

`lib/engine/models.dart` — extend CrawlState: add field `final int chaosFactor;` with constructor default `this.chaosFactor = 5`, thread it through `copyWith` (`int? chaosFactor` → `chaosFactor: chaosFactor ?? this.chaosFactor`), `toJson` (`'chaosFactor': chaosFactor`), and `fromJson` (`chaosFactor: (j['chaosFactor'] as int?) ?? 5`).

- [ ] **Step 4: Run tests**

Run: `flutter test`
Expected: all pass (45 existing + 3 new = 48).

- [ ] **Step 5: Commit**

```bash
git add lib/engine/oracle_data.dart lib/engine/models.dart test/mythic_test.dart
git commit -m "feat: mythic data accessors + per-session chaos factor"
```

### Task 3: Engine — fate roll, scene test, event focus (TDD)

**Files:**
- Modify: `lib/engine/oracle.dart` (append a Mythic section after `npcDialog`)
- Test: `test/mythic_test.dart` (append)

- [ ] **Step 1: Write the failing test**

```dart
  group('Mythic engine', () {
    test('50/50 at chaos 5: ~50% yes-like, ~10% exceptional yes, ~5% events', () {
      final oracle = Oracle(data);
      const n = 40000;
      var yesLike = 0, excYes = 0, events = 0;
      for (var i = 0; i < n; i++) {
        final r = oracle.mythicFate(4, 5);
        final answer = r.rolls.firstWhere((x) => x.label == 'Answer').value;
        if (answer.endsWith('Yes')) yesLike++;
        if (answer == 'Exceptional Yes') excYes++;
        if (r.rolls.any((x) => x.label == 'Random Event')) events++;
      }
      expect(yesLike / n, closeTo(0.50, 0.01));
      expect(excYes / n, closeTo(0.10, 0.01));
      expect(events / n, closeTo(0.05, 0.01));
    });

    test('certain at chaos 9 is nearly always yes', () {
      final oracle = Oracle(data);
      var yes = 0;
      for (var i = 0; i < 2000; i++) {
        final r = oracle.mythicFate(0, 9);
        if (r.rolls
            .firstWhere((x) => x.label == 'Answer')
            .value
            .endsWith('Yes')) {
          yes++;
        }
      }
      expect(yes / 2000, greaterThan(0.97));
    });

    test('scene test rates follow chaos', () {
      final oracle = Oracle(data);
      var expectedScenes = 0;
      const n = 9000;
      for (var i = 0; i < n; i++) {
        final r = oracle.mythicSceneTest(3);
        final v = r.rolls.first.value;
        expect(['Expected Scene', 'Altered Scene', 'Interrupted Scene'],
            contains(v));
        if (v == 'Expected Scene') expectedScenes++;
      }
      expect(expectedScenes / n, closeTo(0.70, 0.02));
    });

    test('event focus targets the provided lists when relevant', () {
      final oracle = Oracle(data);
      var sawThreadTarget = false, sawCharacterTarget = false;
      for (var i = 0; i < 2000; i++) {
        final r = oracle.mythicEventFocus(
          threads: ['Find the sword'],
          characters: ['Old Marta'],
        );
        final focus = r.rolls.first.value;
        final target =
            r.rolls.where((x) => x.label == 'Target').firstOrNull?.value;
        if (focus.contains('Thread')) {
          expect(target, 'Find the sword');
          sawThreadTarget = true;
        }
        if (focus.startsWith('NPC')) {
          expect(target, 'Old Marta');
          sawCharacterTarget = true;
        }
      }
      expect(sawThreadTarget && sawCharacterTarget, isTrue);
    });
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/mythic_test.dart`
Expected: FAIL — methods undefined.

- [ ] **Step 3: Implement in `lib/engine/oracle.dart`**

```dart
  // -- Mythic GME 2e (Word Mill Games, CC-BY-NC) --------------------------

  /// Fate Chart roll: [oddsIndex] 0..8 (Certain..Impossible), [chaos] 1..9.
  GenResult mythicFate(int oddsIndex, int chaos) {
    final band = data.mythicBands[9 - chaos + oddsIndex];
    final excYes = band[0], target = band[1], excNo = band[2];
    final roll = dice.d100();
    final String answer;
    if (roll <= excYes) {
      answer = 'Exceptional Yes';
    } else if (roll <= target) {
      answer = 'Yes';
    } else if (roll < excNo) {
      answer = 'No';
    } else {
      answer = 'Exceptional No';
    }
    final rolls = <Roll>[
      Roll(label: 'Answer', value: answer, detail: 'd100 $roll vs $target'),
      Roll(
          label: 'Odds',
          value: data.mythicOdds[oddsIndex],
          detail: 'chaos $chaos'),
    ];
    if (roll < 100 && roll % 11 == 0 && roll ~/ 11 <= chaos) {
      rolls.add(const Roll(
          label: 'Random Event', value: 'Doubles! Roll Event Focus'));
    }
    return GenResult(title: 'Mythic Fate Chart', rolls: rolls);
  }

  /// Scene Test at the start of an expected scene.
  GenResult mythicSceneTest(int chaos) {
    final roll = dice.dN(10);
    final String outcome;
    if (roll > chaos) {
      outcome = 'Expected Scene';
    } else if (roll.isOdd) {
      outcome = 'Altered Scene';
    } else {
      outcome = 'Interrupted Scene';
    }
    return GenResult(title: 'Mythic Scene Test', rolls: [
      Roll(label: 'Scene', value: outcome, detail: 'd10 $roll vs chaos $chaos'),
    ]);
  }

  /// Event Focus; thread/NPC-flavored results pick from the player's lists.
  GenResult mythicEventFocus({
    List<String> threads = const [],
    List<String> characters = const [],
  }) {
    final roll = dice.d100();
    final entry = data.mythicEventFocus
        .firstWhere((e) => roll <= (e[0] as int));
    final label = entry[1] as String;
    final kind = entry[2] as String?;
    final rolls = <Roll>[
      Roll(label: 'Focus', value: label, detail: 'd100 $roll'),
    ];
    final pool = kind == 'thread'
        ? threads
        : kind == 'character'
            ? characters
            : const <String>[];
    if (kind != null) {
      rolls.add(Roll(
        label: 'Target',
        value: pool.isEmpty
            ? '(no ${kind}s tracked — invent one)'
            : pool[dice.dN(pool.length) - 1],
      ));
    }
    return GenResult(title: 'Mythic Event Focus', rolls: rolls);
  }
```

- [ ] **Step 4: Run the full suite**

Run: `flutter test && flutter analyze`
Expected: 52 tests pass; 4 pre-existing infos only.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/oracle.dart test/mythic_test.dart
git commit -m "feat: mythic fate chart, scene test, event focus in Dart engine"
```

### Task 4: Fate-tab UI + docs

**Files:**
- Modify: `lib/features/fate_screen.dart`
- Modify: `README.md`

- [ ] **Step 1: Add the Mythic section**

In `_FateScreenState`: add fields

```dart
  int _oddsIndex = 4; // 50/50
  GenResult? _mythicLast;
```

Add import `../shared/result_card.dart`.

Append to the ListView children (after the Random Event / Pay the Price Row):

```dart
        const SizedBox(height: 24),
        const Divider(),
        Text('Mythic GME', style: theme.textTheme.headlineSmall),
        Text(
          'Mythic Game Master Emulator © Word Mill Games (wordmillgames.com), '
          'used under CC-BY-NC 4.0.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        Builder(builder: (context) {
          final crawl =
              ref.watch(crawlProvider).valueOrNull ?? const CrawlState();
          final chaos = crawl.chaosFactor.clamp(1, 9);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Chaos Factor: $chaos',
                      style: theme.textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: chaos > 1
                        ? () => ref.read(crawlProvider.notifier).save(
                            crawl.copyWith(chaosFactor: chaos - 1))
                        : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: chaos < 9
                        ? () => ref.read(crawlProvider.notifier).save(
                            crawl.copyWith(chaosFactor: chaos + 1))
                        : null,
                  ),
                ],
              ),
              DropdownMenu<int>(
                initialSelection: _oddsIndex,
                label: const Text('Odds'),
                dropdownMenuEntries: [
                  for (var i = 0; i < widget.oracle.data.mythicOdds.length; i++)
                    DropdownMenuEntry(
                        value: i, label: widget.oracle.data.mythicOdds[i]),
                ],
                onSelected: (v) =>
                    setState(() => _oddsIndex = v ?? _oddsIndex),
              ),
              const SizedBox(height: 12),
              if (_mythicLast != null) ...[
                ResultCard(
                  result: _mythicLast!,
                  onLog: () {
                    ref.read(logProvider.notifier).add(
                        _mythicLast!.title, _mythicLast!.asText);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Logged')),
                    );
                  },
                ),
                const SizedBox(height: 12),
              ],
              FilledButton.icon(
                onPressed: () => setState(() => _mythicLast =
                    widget.oracle.mythicFate(_oddsIndex, chaos)),
                icon: const Icon(Icons.casino_outlined),
                label: const Text('Fate Chart'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() => _mythicLast =
                          widget.oracle.mythicSceneTest(chaos)),
                      child: const Text('Scene Test'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        final threads = (ref
                                    .read(threadsProvider)
                                    .valueOrNull ??
                                const [])
                            .where((t) => t.open)
                            .map((t) => t.title)
                            .toList();
                        final characters = (ref
                                    .read(charactersProvider)
                                    .valueOrNull ??
                                const [])
                            .map((c) => c.name)
                            .toList();
                        setState(() => _mythicLast =
                            widget.oracle.mythicEventFocus(
                                threads: threads, characters: characters));
                      },
                      child: const Text('Event Focus'),
                    ),
                  ),
                ],
              ),
            ],
          );
        }),
```

Type note: `threadsProvider` value is `List<Thread>` — the `?? const []`
fallback needs a typed empty list (`const <Thread>[]`, `const <Character>[]`)
if inference complains.

- [ ] **Step 2: Analyze + tests**

Run: `flutter analyze && flutter test`
Expected: 4 pre-existing infos; 52 tests pass.

- [ ] **Step 3: README**

Add to the feature area (near the Fate Check description): one line noting
Mythic GME support (Fate Chart with Chaos Factor, Scene Test, Event Focus
rolling against your tracked Threads/Characters), with attribution:
"Mythic Game Master Emulator © Word Mill Games, content used under
CC-BY-NC 4.0 — this app is free and non-commercial."

- [ ] **Step 4: Commit**

```bash
git add lib/features/fate_screen.dart README.md
git commit -m "feat: Mythic GME section — chaos dial, fate chart, scene test, event focus"
```

## Self-review notes

- Roadmap acceptance ("Chaos Factor, Fate Chart (odds × chaos d100), scene test (altered/interrupted), Event Focus rolling against our existing Threads/Characters lists. License: free + attribute") — Tasks 1–4 cover all five clauses; attribution rendered in UI + README.
- Type consistency: `mythicBands` returns `List<List<int>>` indexed `9 - chaos + oddsIndex` in both Python verify and Dart; `mythicEventFocus` rows are `[int, String, String?]` consumed positionally in engine; UI passes `oddsIndex` int + chaos from `CrawlState.chaosFactor`.
- Chaos on CrawlState: additive json field with default — old persisted state and old campaign files import cleanly (campaign schemaVersion unchanged); Reset Crawl resets chaos to 5, which matches Mythic's "start at 5".
- Event Focus uses only open threads; characters list used as-is.
- Deliberate cuts (Later item): Meaning Tables, Behavior/Statistic/Detail checks, automatic chaos adjustment at scene end (manual dial covers the spike).
