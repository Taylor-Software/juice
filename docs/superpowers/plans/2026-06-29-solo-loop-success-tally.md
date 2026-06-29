# Solo Loop + Success Tally Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a bidirectional Success Tally (optional on `Thread`) and a wired "Solo Loop" Track-verb subtab that threads scene → d10 yes/no oracle → inspire → tally → log.

**Architecture:** Two new pure-engine files (`tally.dart`, `solo_oracle.dart`) hold all math as deterministic functions (classify-by-roll cores + thin `Dice` wrappers). `Thread` gains an optional `Tally`, persisted in the existing `juice.threads.v1` key. A new stateless `LoopPane` widget composes existing providers (play-context spine, threads, journal, the inspire sheet). `ThreadsPane` renders a tally row when present.

**Tech Stack:** Flutter, Riverpod (`AsyncNotifierProvider`), SharedPreferences (existing persistence), `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-06-29-solo-loop-success-tally-design.md`

---

## File Structure

**New**
- `lib/engine/tally.dart` — `Tally` value type + presets + `classifyVsTally`/`rollVsTally`.
- `lib/engine/solo_oracle.dart` — `SoloLikelihood`, `SoloTwist`, `SoloYesNo`, `classifyYesNo`/`soloYesNo`.
- `lib/features/loop_pane.dart` — the "Loop" subtab widget.
- `test/tally_test.dart`, `test/solo_oracle_test.dart`, `test/loop_pane_test.dart`, `test/thread_tally_test.dart`.

**Changed**
- `lib/engine/models.dart` — `Thread.tally` field + copyWith(`clearTally`) + JSON.
- `lib/state/providers.dart` — `ThreadNotifier.setTally`/`clearTally`/`adjustTally`.
- `lib/features/tracker_screen.dart` — tally row on thread cards (`ThreadsPane`).
- `lib/features/tracking_tab.dart` — register the "Loop" subtab.
- `lib/features/settings_sheet.dart` — courtesy credit line.

**Reference (do not modify — read for signatures)**
- `lib/engine/dice.dart:4` — `Dice.dN(int n)` → 1..n.
- `lib/engine/models.dart:56` — `Roll{label,value,detail?}`; `:66` — `GenResult{title,rolls,summary?}`.
- `lib/state/providers.dart:97` — `JournalNotifier.addResult(title, body, {sourceTool, payload})`.
- `lib/state/providers.dart:215-273` — `ThreadNotifier` (`replace`, `_ready`, `_newId`), `threadsProvider`.
- `lib/state/play_context.dart:80` — `activeSceneEntry(journal, activeSceneId)`; `:42` — `setActiveScene`; `:61` — `playContextProvider`.
- `lib/features/generate_sheet.dart:14` — `showGenerateSheet(BuildContext)`.

---

## Task 1: Tally value type (pure)

**Files:**
- Create: `lib/engine/tally.dart`
- Test: `test/tally_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/tally_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/tally.dart';

void main() {
  group('Tally', () {
    test('clamps current into 0..target on construct and adjust', () {
      expect(const Tally(start: 4, current: 9, target: 8).current, 8);
      expect(const Tally(start: 4, current: -3, target: 8).current, 0);
      final t = const Tally(start: 4, current: 4, target: 8);
      expect(t.adjust(2).current, 6);
      expect(t.adjust(-10).current, 0);
      expect(t.adjust(100).current, 8);
    });

    test('target floored at 1', () {
      expect(const Tally(start: 0, current: 0, target: 0).target, 1);
    });

    test('failed at 0, won at target', () {
      expect(const Tally(start: 1, current: 0, target: 4).failed, isTrue);
      expect(const Tally(start: 1, current: 0, target: 4).won, isFalse);
      expect(const Tally(start: 3, current: 4, target: 4).won, isTrue);
      expect(const Tally(start: 3, current: 2, target: 4).failed, isFalse);
    });

    test('label is current(target)', () {
      expect(const Tally(start: 4, current: 4, target: 8).label, '4(8)');
    });

    test('JSON round-trips; maybeFromJson tolerant', () {
      final t = const Tally(start: 4, current: 5, target: 8);
      expect(Tally.maybeFromJson(t.toJson()), equals(t));
      expect(Tally.maybeFromJson(null), isNull);
      expect(Tally.maybeFromJson(const {'start': 'x'}), isNull);
    });

    test('presets are the four Cairn-Solo sizes', () {
      expect(kTallyPresets.map((p) => (p.$2, p.$3)).toList(),
          [(2, 4), (3, 6), (4, 8), (5, 10)]);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/tally_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:juice_oracle/engine/tally.dart'`.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/engine/tally.dart
import 'dice.dart';

/// A bidirectional "major task" tracker: [current] moves between 0 (fail) and
/// [target] (win). Distinct from Thread's one-way progress clock.
class Tally {
  const Tally({required this.start, required int current, required int target})
      : target = target < 1 ? 1 : target,
        current = current < 0
            ? 0
            : (current > (target < 1 ? 1 : target)
                ? (target < 1 ? 1 : target)
                : current);

  final int start;
  final int current; // clamped 0..target
  final int target; // >= 1

  bool get failed => current <= 0;
  bool get won => current >= target;
  String get label => '$current($target)';

  Tally adjust(int delta) =>
      Tally(start: start, current: current + delta, target: target);

  Tally copyWith({int? start, int? current, int? target}) => Tally(
        start: start ?? this.start,
        current: current ?? this.current,
        target: target ?? this.target,
      );

  Map<String, dynamic> toJson() =>
      {'start': start, 'current': current, 'target': target};

  static Tally? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final s = json['start'], c = json['current'], t = json['target'];
    if (s is! int || c is! int || t is! int) return null;
    return Tally(start: s, current: c, target: t);
  }

  @override
  bool operator ==(Object other) =>
      other is Tally &&
      other.start == start &&
      other.current == current &&
      other.target == target;

  @override
  int get hashCode => Object.hash(start, current, target);
}

/// The four authored task sizes (label, start, target) — Cairn Solo p.28 facts.
const List<(String, int, int)> kTallyPresets = [
  ('Modest task', 2, 4),
  ('Minor challenge', 3, 6),
  ('Difficult task', 4, 8),
  ('Long/dangerous task', 5, 10),
];

/// Outcome of rolling against a tally's current value (Cairn Solo p.28):
/// roll d{target}; <= current is a clean result, else a complication.
enum TallyRollOutcome { clean, complication }

TallyRollOutcome classifyVsTally(Tally t, int roll) =>
    roll <= t.current ? TallyRollOutcome.clean : TallyRollOutcome.complication;

TallyRollOutcome rollVsTally(Tally t, Dice dice) =>
    classifyVsTally(t, dice.dN(t.target));
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/tally_test.dart`
Expected: PASS.

- [ ] **Step 5: Add a classifyVsTally test, run, commit**

Append to `test/tally_test.dart` inside `main()`:

```dart
  group('rollVsTally', () {
    test('classify: <= current is clean, else complication', () {
      final t = const Tally(start: 4, current: 5, target: 8);
      expect(classifyVsTally(t, 5), TallyRollOutcome.clean);
      expect(classifyVsTally(t, 1), TallyRollOutcome.clean);
      expect(classifyVsTally(t, 6), TallyRollOutcome.complication);
    });
  });
```

Run: `flutter test test/tally_test.dart` → Expected: PASS.

```bash
git add lib/engine/tally.dart test/tally_test.dart
git commit -m "feat(tally): Tally value type + roll-vs-tally (pure)"
```

---

## Task 2: d10 Yes/No solo oracle (pure)

**Files:**
- Create: `lib/engine/solo_oracle.dart`
- Test: `test/solo_oracle_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/solo_oracle_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/solo_oracle.dart';

void main() {
  group('classifyYesNo', () {
    // target: unlikely=3, even=5, likely=7
    test('roll 1 is always yes + boon', () {
      for (final o in SoloLikelihood.values) {
        final r = classifyYesNo(o, 1);
        expect(r.yes, isTrue);
        expect(r.twist, SoloTwist.boon);
      }
    });

    test('roll 10 is always no + complication', () {
      for (final o in SoloLikelihood.values) {
        final r = classifyYesNo(o, 10);
        expect(r.yes, isFalse);
        expect(r.twist, SoloTwist.complication);
      }
    });

    test('even (target 5): under=yes, exact=yes+complication, over=no', () {
      expect(classifyYesNo(SoloLikelihood.even, 4),
          predicate<SoloYesNo>((r) => r.yes && r.twist == SoloTwist.none));
      expect(classifyYesNo(SoloLikelihood.even, 5),
          predicate<SoloYesNo>((r) => r.yes && r.twist == SoloTwist.complication));
      expect(classifyYesNo(SoloLikelihood.even, 6),
          predicate<SoloYesNo>((r) => !r.yes && r.twist == SoloTwist.none));
    });

    test('likely (target 7): 6=yes, 7=yes+complication, 8=no', () {
      expect(classifyYesNo(SoloLikelihood.likely, 6).yes, isTrue);
      expect(classifyYesNo(SoloLikelihood.likely, 7).twist, SoloTwist.complication);
      expect(classifyYesNo(SoloLikelihood.likely, 8).yes, isFalse);
    });

    test('toGenResult carries the roll + a phrase, sourceTool-ready', () {
      final g = classifyYesNo(SoloLikelihood.likely, 1).toGenResult();
      expect(g.title, contains('Yes/No'));
      expect(g.asText.toLowerCase(), contains('boon'));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/solo_oracle_test.dart`
Expected: FAIL — URI does not exist.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/engine/solo_oracle.dart
import 'dice.dart';
import 'models.dart';

/// d10 likelihood target (Cairn Solo p.27): yes on <= target, with twists.
enum SoloLikelihood { unlikely, even, likely }

extension SoloLikelihoodX on SoloLikelihood {
  int get target => switch (this) {
        SoloLikelihood.unlikely => 3,
        SoloLikelihood.even => 5,
        SoloLikelihood.likely => 7,
      };
  String get label => switch (this) {
        SoloLikelihood.unlikely => 'Unlikely',
        SoloLikelihood.even => 'Even',
        SoloLikelihood.likely => 'Likely',
      };
}

enum SoloTwist { none, boon, complication }

class SoloYesNo {
  const SoloYesNo({
    required this.yes,
    required this.twist,
    required this.roll,
    required this.odds,
  });
  final bool yes;
  final SoloTwist twist;
  final int roll; // d10 face 1..10
  final SoloLikelihood odds;

  /// Player-facing sentence, e.g. "Yes, and a boon".
  String get phrase {
    final base = yes ? 'Yes' : 'No';
    return switch (twist) {
      SoloTwist.none => base,
      SoloTwist.boon => '$base, and a boon',
      SoloTwist.complication =>
        yes ? '$base, but a complication' : '$base, and a complication',
    };
  }

  GenResult toGenResult() => GenResult(
        title: 'Yes/No — ${odds.label}',
        summary: phrase,
        rolls: [Roll(label: 'Result', value: phrase, detail: 'd10=$roll')],
      );
}

/// Pure mapping of a known d10 [roll] under [odds] (Cairn Solo p.27 table).
SoloYesNo classifyYesNo(SoloLikelihood odds, int roll) {
  final t = odds.target;
  late final bool yes;
  late final SoloTwist twist;
  if (roll == 1) {
    yes = true;
    twist = SoloTwist.boon;
  } else if (roll == 10) {
    yes = false;
    twist = SoloTwist.complication;
  } else if (roll < t) {
    yes = true;
    twist = SoloTwist.none;
  } else if (roll == t) {
    yes = true;
    twist = SoloTwist.complication;
  } else {
    yes = false;
    twist = SoloTwist.none;
  }
  return SoloYesNo(yes: yes, twist: twist, roll: roll, odds: odds);
}

SoloYesNo soloYesNo(SoloLikelihood odds, Dice dice) =>
    classifyYesNo(odds, dice.dN(10));
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/solo_oracle_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/solo_oracle.dart test/solo_oracle_test.dart
git commit -m "feat(solo-oracle): d10 yes/no (3/5/7) with boon/complication twists"
```

---

## Task 3: Thread.tally field + JSON

**Files:**
- Modify: `lib/engine/models.dart:183-243` (`Thread`)
- Test: `test/thread_tally_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/thread_tally_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/engine/tally.dart';

void main() {
  test('Thread carries an optional tally through copyWith + JSON', () {
    final t = Thread(id: 'a', title: 'Escape')
        .copyWith(tally: const Tally(start: 4, current: 4, target: 8));
    expect(t.tally?.label, '4(8)');

    final round = Thread.fromJson(t.toJson());
    expect(round.tally, equals(t.tally));

    // clearTally drops it
    expect(t.copyWith(clearTally: true).tally, isNull);

    // absent in JSON when null
    expect(Thread(id: 'b', title: 'x').toJson().containsKey('tally'), isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/thread_tally_test.dart`
Expected: FAIL — `Thread` has no `tally` / `copyWith` has no `tally`/`clearTally`.

- [ ] **Step 3: Add the field, copyWith flag, and JSON**

In `lib/engine/models.dart`, add the import near the top (with the other engine imports):

```dart
import 'tally.dart';
```

Replace the `Thread` constructor head + fields (lines ~184–204) to add `this.tally`:

```dart
  Thread({
    required this.id,
    required this.title,
    this.note = '',
    this.open = true,
    this.pinned = false,
    int progress = 0,
    int progressMax = 10,
    this.tally,
  })  : progressMax = progressMax < 1 ? 1 : progressMax,
        progress = progress.clamp(0, progressMax < 1 ? 1 : progressMax);
  final String id;
  final String title;
  final String note;
  final bool open;
  final bool pinned;

  /// Numeric progress clock (n/[progressMax]); always clamped into 0..max.
  final int progress;

  /// Clock denominator (default 10); always >= 1.
  final int progressMax;

  /// Optional bidirectional success/failure tally (Cairn-Solo style); null when
  /// this thread is a plain storyline. Distinct from the [progress] clock.
  final Tally? tally;
```

Replace `copyWith` (lines ~206–222) to thread `tally`/`clearTally`:

```dart
  Thread copyWith({
    String? title,
    String? note,
    bool? open,
    bool? pinned,
    int? progress,
    int? progressMax,
    Tally? tally,
    bool clearTally = false,
  }) =>
      Thread(
        id: id,
        title: title ?? this.title,
        note: note ?? this.note,
        open: open ?? this.open,
        pinned: pinned ?? this.pinned,
        progress: progress ?? this.progress,
        progressMax: progressMax ?? this.progressMax,
        tally: clearTally ? null : (tally ?? this.tally),
      );
```

Replace `toJson` (lines ~224–232) to emit `tally` when present:

```dart
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'note': note,
        'open': open,
        if (pinned) 'pinned': true,
        if (progress > 0) 'progress': progress,
        if (progressMax != 10) 'progressMax': progressMax,
        if (tally != null) 'tally': tally!.toJson(),
      };
```

Replace `fromJson` (lines ~234–242) to parse `tally` tolerantly:

```dart
  factory Thread.fromJson(Map<String, dynamic> j) => Thread(
        id: j['id'] as String,
        title: j['title'] as String,
        note: (j['note'] as String?) ?? '',
        open: (j['open'] as bool?) ?? true,
        pinned: (j['pinned'] as bool?) ?? false,
        progress: (j['progress'] as int?) ?? 0,
        progressMax: (j['progressMax'] as int?) ?? 10,
        tally: Tally.maybeFromJson((j['tally'] as Map?)?.cast<String, dynamic>()),
      );
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/thread_tally_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/models.dart test/thread_tally_test.dart
git commit -m "feat(thread): optional Tally field + tolerant JSON"
```

---

## Task 4: ThreadNotifier tally methods

**Files:**
- Modify: `lib/state/providers.dart:215-270` (`ThreadNotifier`)

No new test file — covered indirectly by the widget test in Task 6. These are thin
wrappers over the existing `replace`.

- [ ] **Step 1: Add the methods**

In `lib/state/providers.dart`, ensure the `tally.dart` import exists at the top
(add `import '../engine/tally.dart';` if not already imported via models). Then add
these methods inside `ThreadNotifier` (after `setProgress`, before `remove`):

```dart
  /// Attaches (or replaces) a success tally on thread [id].
  Future<void> setTally(String id, Tally tally) async {
    final thread = (await _ready).where((t) => t.id == id).firstOrNull;
    if (thread == null) return;
    await replace(thread.copyWith(tally: tally));
  }

  /// Removes the tally from thread [id], leaving the thread itself intact.
  Future<void> clearTally(String id) async {
    final thread = (await _ready).where((t) => t.id == id).firstOrNull;
    if (thread == null) return;
    await replace(thread.copyWith(clearTally: true));
  }

  /// Nudges the tally's current value by [delta] (clamped by Tally).
  Future<void> adjustTally(String id, int delta) async {
    final thread = (await _ready).where((t) => t.id == id).firstOrNull;
    final tally = thread?.tally;
    if (thread == null || tally == null) return;
    await replace(thread.copyWith(tally: tally.adjust(delta)));
  }
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/state/providers.dart`
Expected: No errors (warnings unrelated to this change are acceptable).

- [ ] **Step 3: Commit**

```bash
git add lib/state/providers.dart
git commit -m "feat(threads): setTally/clearTally/adjustTally notifier methods"
```

---

## Task 5: Tally row on thread cards

**Files:**
- Modify: `lib/features/tracker_screen.dart` (`ThreadsPane`, thread card body ~67-286)

- [ ] **Step 1: Read the existing card layout**

Run: `flutter test test/ 2>/dev/null; sed -n '67,180p' lib/features/tracker_screen.dart`
(Read to find where the progress-clock steppers render inside a thread `Card`/`Column`.
Insert the tally block immediately after the progress-clock row.)

- [ ] **Step 2: Add the tally row widget**

Add this private widget at the bottom of `lib/features/tracker_screen.dart` (top-level,
after the `ThreadsPane` class). Ensure imports at the top include:
`import '../engine/tally.dart';`, `import '../engine/dice.dart';`.

```dart
class _ThreadTallyRow extends ConsumerWidget {
  const _ThreadTallyRow(this.thread);
  final Thread thread;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(threadsProvider.notifier);
    final tally = thread.tally;
    if (tally == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: Key('thread-tally-add-${thread.id}'),
          icon: const Icon(Icons.flag_outlined, size: 18),
          label: const Text('Add success tally'),
          onPressed: () => _pickPreset(context, ref),
        ),
      );
    }
    final status = tally.won
        ? 'Success'
        : tally.failed
            ? 'Failed'
            : tally.label;
    final color = tally.won
        ? Colors.green
        : tally.failed
            ? Colors.red
            : Theme.of(context).colorScheme.primary;
    return Row(
      children: [
        Chip(
          label: Text(status),
          labelStyle: TextStyle(color: color, fontWeight: FontWeight.bold),
        ),
        IconButton(
          key: Key('thread-tally-dec-${thread.id}'),
          icon: const Icon(Icons.remove),
          tooltip: 'Setback (−1)',
          onPressed: () => notifier.adjustTally(thread.id, -1),
        ),
        IconButton(
          key: Key('thread-tally-inc-${thread.id}'),
          icon: const Icon(Icons.add),
          tooltip: 'Progress (+1)',
          onPressed: () => notifier.adjustTally(thread.id, 1),
        ),
        IconButton(
          key: Key('thread-tally-roll-${thread.id}'),
          icon: const Icon(Icons.casino_outlined),
          tooltip: 'Roll vs tally',
          onPressed: () {
            final outcome = rollVsTally(tally, Dice());
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(outcome == TallyRollOutcome.clean
                  ? 'Roll vs ${tally.label}: clean'
                  : 'Roll vs ${tally.label}: complication'),
            ));
          },
        ),
        IconButton(
          key: Key('thread-tally-remove-${thread.id}'),
          icon: const Icon(Icons.close),
          tooltip: 'Remove tally',
          onPressed: () => notifier.clearTally(thread.id),
        ),
      ],
    );
  }

  Future<void> _pickPreset(BuildContext context, WidgetRef ref) async {
    final choice = await showModalBottomSheet<(String, int, int)>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final p in kTallyPresets)
              ListTile(
                key: Key('tally-preset-${p.$1}'),
                title: Text(p.$1),
                trailing: Text('${p.$2}(${p.$3})'),
                onTap: () => Navigator.pop(context, p),
              ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    await ref.read(threadsProvider.notifier).setTally(
          thread.id,
          Tally(start: choice.$2, current: choice.$2, target: choice.$3),
        );
  }
}
```

- [ ] **Step 3: Mount the row inside the thread card**

In the thread-card builder (inside `ThreadsPane`, the `Column` that holds the title,
progress steppers, and the `thread-entries-<id>` chip), add after the progress-clock row:

```dart
          _ThreadTallyRow(t),
```

(`t` is the loop variable for the current `Thread`; match the existing name in that
builder.)

- [ ] **Step 4: Verify it compiles**

Run: `flutter analyze lib/features/tracker_screen.dart`
Expected: No errors.

- [ ] **Step 5: Commit**

```bash
git add lib/features/tracker_screen.dart
git commit -m "feat(threads): tally row on thread cards (add/step/roll/remove)"
```

---

## Task 6: LoopPane + register subtab

**Files:**
- Create: `lib/features/loop_pane.dart`
- Modify: `lib/features/tracking_tab.dart`
- Test: `test/loop_pane_test.dart`

- [ ] **Step 1: Write the LoopPane widget**

```dart
// lib/features/loop_pane.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/dice.dart';
import '../engine/solo_oracle.dart';
import '../engine/tally.dart';
import '../state/play_context.dart';
import '../state/providers.dart';
import 'generate_sheet.dart';

/// The "Solo Loop" Track subtab: a checklist that wires the active scene, a d10
/// yes/no oracle, the inspire sheet, success-tally tasks, and journal logging.
class LoopPane extends ConsumerStatefulWidget {
  const LoopPane({super.key});
  @override
  ConsumerState<LoopPane> createState() => _LoopPaneState();
}

class _LoopPaneState extends ConsumerState<LoopPane> {
  SoloLikelihood _odds = SoloLikelihood.even;
  SoloYesNo? _last;
  final _capture = TextEditingController();

  @override
  void dispose() {
    _capture.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final journal = ref.watch(journalProvider).valueOrNull ?? const [];
    final ctx = ref.watch(playContextProvider).valueOrNull;
    final scene = activeSceneEntry(journal, ctx?.activeSceneId);
    final threads = ref.watch(threadsProvider).valueOrNull ?? const [];
    final tallied = threads.where((t) => t.tally != null).toList();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _step(context, '1 · Scene',
            scene == null ? 'No scene yet.' : scene.title, [
          FilledButton.tonalIcon(
            key: const Key('loop-new-scene'),
            icon: const Icon(Icons.add),
            label: const Text('New scene'),
            onPressed: _newScene,
          ),
        ]),
        _step(context, '2 · Ask a question', 'Roll a d10 yes/no.', [
          SegmentedButton<SoloLikelihood>(
            segments: const [
              ButtonSegment(value: SoloLikelihood.unlikely, label: Text('Unlikely')),
              ButtonSegment(value: SoloLikelihood.even, label: Text('Even')),
              ButtonSegment(value: SoloLikelihood.likely, label: Text('Likely')),
            ],
            selected: {_odds},
            onSelectionChanged: (s) => setState(() => _odds = s.first),
          ),
          const SizedBox(width: 8),
          FilledButton(
            key: const Key('loop-ask'),
            onPressed: _ask,
            child: const Text('Ask'),
          ),
          if (_last != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${_last!.phrase} (d10=${_last!.roll})',
                key: const Key('loop-ask-result'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
        ]),
        _step(context, '3 · Inspire', 'Open the generators for a prompt.', [
          OutlinedButton.icon(
            key: const Key('loop-inspire'),
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Inspire'),
            onPressed: () => showGenerateSheet(context),
          ),
        ]),
        _step(
          context,
          '4 · Tasks',
          tallied.isEmpty
              ? 'No tallied tasks. Add one on a thread (Track → Threads).'
              : null,
          [
            for (final t in tallied)
              ListTile(
                key: Key('loop-task-${t.id}'),
                dense: true,
                title: Text(t.title),
                subtitle: Text(t.tally!.won
                    ? 'Success'
                    : t.tally!.failed
                        ? 'Failed'
                        : t.tally!.label),
                trailing: Wrap(spacing: 0, children: [
                  IconButton(
                    key: Key('loop-task-dec-${t.id}'),
                    icon: const Icon(Icons.remove),
                    onPressed: () =>
                        ref.read(threadsProvider.notifier).adjustTally(t.id, -1),
                  ),
                  IconButton(
                    key: Key('loop-task-inc-${t.id}'),
                    icon: const Icon(Icons.add),
                    onPressed: () =>
                        ref.read(threadsProvider.notifier).adjustTally(t.id, 1),
                  ),
                ]),
              ),
          ],
        ),
        _step(context, '5 · Capture', null, [
          TextField(
            key: const Key('loop-capture-field'),
            controller: _capture,
            decoration: const InputDecoration(
              hintText: 'Quick note to the journal…',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _capture(),
          ),
        ]),
        const SizedBox(height: 16),
        Text(
          'Solo loop inspired by Cairn Solo (CC-BY-SA 4.0, Andrew Cavanagh, EpicEmpires.org).',
          key: const Key('loop-credit'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _step(BuildContext context, String title, String? body,
          List<Widget> children) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              if (body != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(body),
                ),
              Wrap(
                  spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center,
                  children: children),
            ],
          ),
        ),
      );

  Future<void> _newScene() async {
    final id = await ref
        .read(journalProvider.notifier)
        .addScene('New scene');
    await ref.read(playContextProvider.notifier).setActiveScene(id);
  }

  Future<void> _ask() async {
    final result = soloYesNo(_odds, Dice());
    setState(() => _last = result);
    final g = result.toGenResult();
    await ref
        .read(journalProvider.notifier)
        .addResult(g.title, g.asText, sourceTool: 'solo-loop', payload: g.toPayload());
  }

  Future<void> _captureNote() async {
    final text = _capture.text.trim();
    if (text.isEmpty) return;
    await ref.read(journalProvider.notifier).addText(text);
    _capture.clear();
  }
}
```

Note: rename the capture handler call — in the `TextField`, change
`onSubmitted: (_) => _capture()` to `onSubmitted: (_) => _captureNote()`.

- [ ] **Step 2: Register the subtab**

In `lib/features/tracking_tab.dart`, add the import:

```dart
import 'loop_pane.dart';
```

Add `const SubtabDef('loop', 'Loop'),` to the `tabs` list immediately after the `home`
entry (line ~33), and `const LoopPane(),` to the `children` list immediately after
`const TrackHomePane(),` (line ~46). Order must match between the two lists.

- [ ] **Step 3: Write the widget test**

```dart
// test/loop_pane_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice_oracle/features/loop_pane.dart';
import 'package:juice_oracle/state/providers.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: Scaffold(body: LoopPane())),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('renders the five steps + credit', (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('loop-ask')), findsOneWidget);
    expect(find.byKey(const Key('loop-inspire')), findsOneWidget);
    expect(find.byKey(const Key('loop-new-scene')), findsOneWidget);
    expect(find.byKey(const Key('loop-credit')), findsOneWidget);
  });

  testWidgets('Ask rolls, shows a result, and logs one journal entry',
      (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('loop-ask')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('loop-ask-result')), findsOneWidget);

    final container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('loop-ask'))));
    final journal = container.read(journalProvider).valueOrNull ?? const [];
    expect(journal.where((e) => e.sourceTool == 'solo-loop'), hasLength(1));
  });
}
```

This pane does NOT pump `JournalScreen`/`HomeShell`, so it avoids the rootBundle-hang
(no oracle/verdant/emulator/ruleset asset loads). Only mock prefs are needed.

- [ ] **Step 4: Run the test**

Run: `flutter test test/loop_pane_test.dart`
Expected: PASS (both tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/loop_pane.dart lib/features/tracking_tab.dart test/loop_pane_test.dart
git commit -m "feat(loop): Solo Loop Track subtab (scene/ask/inspire/tasks/capture)"
```

---

## Task 7: Courtesy credit in Settings

**Files:**
- Modify: `lib/features/settings_sheet.dart`

- [ ] **Step 1: Find the sources/attribution block**

Run: `grep -n "settings-sources\|Attribution\|kContentAttributions\|Sources" lib/features/settings_sheet.dart`
Expected: a `settings-sources` section listing attribution lines.

- [ ] **Step 2: Add the credit line**

In the sources section body, add a line (matching the surrounding style — e.g. a `Text`
inside the existing list):

```dart
Text(
  'Solo loop inspired by Cairn Solo (CC-BY-SA 4.0, Andrew Cavanagh, EpicEmpires.org).',
  style: Theme.of(context).textTheme.bodySmall,
),
```

- [ ] **Step 3: Verify it compiles**

Run: `flutter analyze lib/features/settings_sheet.dart`
Expected: No errors.

- [ ] **Step 4: Commit**

```bash
git add lib/features/settings_sheet.dart
git commit -m "docs(settings): courtesy credit for Cairn Solo loop inspiration"
```

---

## Task 8: Full verification + bookkeeping

- [ ] **Step 1: Analyze the whole project**

Run: `flutter analyze`
Expected: No new errors introduced by this work.

- [ ] **Step 2: Run the full test suite**

Run: `flutter test`
Expected: All tests pass, including the four new files.

- [ ] **Step 3: Update CLAUDE.md project notes**

Add a bullet under "Project notes" summarizing: the Solo Loop subtab + Success Tally on
threads, the pure `tally.dart`/`solo_oracle.dart` engine files, the `solo-loop` sourceTool,
no new persistence key, and the Cairn-Solo facts-only/CC-BY-SA courtesy-credit posture.
Reference the spec + this plan.

- [ ] **Step 4: Commit bookkeeping**

```bash
git add CLAUDE.md
git commit -m "docs: note Solo Loop + Success Tally feature"
```

- [ ] **Step 5: Push + open PR**

```bash
git push -u origin feat/solo-loop-tally
gh pr create --title "feat(solo-loop): Solo Loop subtab + Success Tally on threads" \
  --body "Implements docs/superpowers/specs/2026-06-29-solo-loop-success-tally-design.md"
```

---

## Self-Review notes

- **Spec coverage:** Tally model (T1) ✓, d10 yes/no oracle (T2) ✓, Thread.tally + JSON (T3) ✓,
  notifier methods (T4) ✓, threads-pane tally row + presets + roll-vs-tally (T5) ✓, Loop
  subtab with all five steps (T6) ✓, courtesy credit (T7) ✓, no-new-key / no-new-AI-seam /
  no Word Oracle all honored. Deferred items left unbuilt by design.
- **Type consistency:** `Tally`, `SoloLikelihood`, `SoloTwist`, `SoloYesNo`, `classifyYesNo`,
  `soloYesNo`, `classifyVsTally`, `rollVsTally`, `kTallyPresets`, `Thread.copyWith(tally,
  clearTally)`, `setTally/clearTally/adjustTally`, `sourceTool: 'solo-loop'` — used
  consistently across tasks.
- **Note for implementer:** the package import prefix is `package:juice_oracle/` (the Dart
  package keeps the legacy `juice_oracle` name — see CLAUDE.md). Confirm against an existing
  test's imports before running.
