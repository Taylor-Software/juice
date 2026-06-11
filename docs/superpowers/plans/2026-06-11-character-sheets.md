# Character Sheets (Redesign Phase 4) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Grow `Character` from {name, note} into a flexible, system-agnostic sheet — stats (label/value), tracks (current/max with steppers), tags — with an in-panel editor, while old data and old campaign files keep working.

**Architecture:** Additive model change: three new fields on `Character` with empty-list JSON defaults, so legacy persisted data and v1/v2 campaign files parse unchanged (no schema bump — campaign v2 keys are additive by design). The Characters tab swaps inline between list view and a sheet editor (`_editingId` state — no Navigator routes, so the keep-alive tool panel and PopScope are untouched). Every editor mutation auto-saves via the existing `replace()`.

**Tech Stack:** Existing rails only. Spec: `docs/superpowers/specs/2026-06-11-journal-redesign-design.md` (Phase 4). Baseline: 143 tests green; `flutter analyze --no-fatal-infos` = 1 pre-existing info (lib/engine/models.dart dangling doc comment).

---

### Task 1: Model — stats, tracks, tags

**Files:**
- Modify: `lib/engine/models.dart` (Character class, currently `{id, name, note}`)
- Test: `test/character_sheet_test.dart` (new)

- [ ] **Step 1: Failing tests** (`test/character_sheet_test.dart`):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';

void main() {
  test('legacy character JSON parses with empty blocks', () {
    final c = Character.fromJson({'id': '1', 'name': 'Ash', 'note': 'ranger'});
    expect(c.stats, isEmpty);
    expect(c.tracks, isEmpty);
    expect(c.tags, isEmpty);
    expect(c.note, 'ranger');
  });

  test('full sheet round-trips', () {
    final c = Character(
      id: '2',
      name: 'Brynn',
      note: 'smith',
      stats: const [CharStat(label: 'Iron', value: '+2')],
      tracks: const [CharTrack(label: 'HP', current: 7, max: 10)],
      tags: const ['wounded', 'bond'],
    );
    final back = Character.fromJson(c.toJson());
    expect(back.stats.single.label, 'Iron');
    expect(back.stats.single.value, '+2');
    expect(back.tracks.single.current, 7);
    expect(back.tracks.single.max, 10);
    expect(back.tags, ['wounded', 'bond']);
  });

  test('copyWith replaces blocks and clamps track current', () {
    final c = Character(id: '3', name: 'X');
    final edited = c.copyWith(
      tracks: const [CharTrack(label: 'HP', current: 5, max: 10)],
    );
    expect(edited.tracks.single.label, 'HP');
    expect(edited.name, 'X');
    // CharTrack.clamped helper
    const t = CharTrack(label: 'HP', current: 5, max: 10);
    expect(t.adjusted(7).current, 10); // clamped to max
    expect(t.adjusted(-9).current, 0); // clamped to 0
  });

  test('malformed block entries are skipped, not fatal', () {
    final c = Character.fromJson({
      'id': '4',
      'name': 'Y',
      'stats': [{'label': 'Edge', 'value': '1'}, 'junk'],
      'tracks': [{'label': 'HP'}],
      'tags': ['ok', 42],
    });
    expect(c.stats.single.label, 'Edge');
    expect(c.tracks.single.max, 0); // missing fields default 0
    expect(c.tags, ['ok']);
  });
}
```

- [ ] **Step 2: Run** — FAIL (CharStat undefined).
- [ ] **Step 3: Implement** in `models.dart` (place beside Character):

```dart
/// One labeled stat on a character sheet; value is free text ('17', '+2', 'd8').
class CharStat {
  const CharStat({required this.label, required this.value});
  final String label;
  final String value;

  Map<String, dynamic> toJson() => {'label': label, 'value': value};

  static CharStat? maybeFromJson(dynamic j) => j is Map<String, dynamic>
      ? CharStat(
          label: (j['label'] as String?) ?? '',
          value: (j['value'] as String?) ?? '')
      : null;
}

/// A current/max track (HP, momentum, supply…).
class CharTrack {
  const CharTrack({required this.label, required this.current, required this.max});
  final String label;
  final int current;
  final int max;

  /// New track with [delta] applied to current, clamped to 0..max.
  CharTrack adjusted(int delta) =>
      CharTrack(label: label, current: (current + delta).clamp(0, max), max: max);

  Map<String, dynamic> toJson() =>
      {'label': label, 'current': current, 'max': max};

  static CharTrack? maybeFromJson(dynamic j) => j is Map<String, dynamic>
      ? CharTrack(
          label: (j['label'] as String?) ?? '',
          current: (j['current'] as int?) ?? 0,
          max: (j['max'] as int?) ?? 0)
      : null;
}
```

Character gains `final List<CharStat> stats; final List<CharTrack> tracks; final List<String> tags;` (constructor defaults `const []`), `copyWith` gains the three (replace-whole-list semantics), `toJson` emits them as lists, `fromJson` parses defensively: `stats: ((j['stats'] as List?) ?? const []).map(CharStat.maybeFromJson).whereType<CharStat>().toList()` (same shape for tracks; tags: `((j['tags'] as List?) ?? const []).whereType<String>().toList()`).

- [ ] **Step 4: Full** `flutter test` green (campaign_io validation path uses Character.fromJson — still tolerant).
- [ ] **Step 5: Commit** `git add -A lib test && git commit -m "feat: character sheet model — stats, tracks, tags (legacy JSON compatible)"`

### Task 2: Sheet editor UI

**Files:**
- Modify: `lib/features/tracker_screen.dart` (replace `_CharactersTab`; keep `_ThreadsTab`, `_EditDialog`, `_Empty` untouched)
- Test: `test/character_sheet_ui_test.dart` (new)

- [ ] **Step 1: Failing tests:**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/features/tracker_screen.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const seeded =
      '[{"id":"c1","name":"Ash","note":"","stats":[],"tracks":[{"label":"HP","current":7,"max":10}],"tags":[]}]';

  Future<ProviderContainer> pump(WidgetTester tester,
      {String chars = seeded}) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.characters.v1.default': chars,
    });
    await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: Scaffold(body: TrackerScreen()))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Characters'));
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
        tester.element(find.byType(TrackerScreen)));
  }

  testWidgets('list row shows first-track summary', (tester) async {
    await pump(tester);
    expect(find.text('Ash'), findsOneWidget);
    expect(find.text('HP 7/10'), findsOneWidget);
  });

  testWidgets('track steppers adjust and persist, clamped', (tester) async {
    final container = await pump(tester);
    await tester.tap(find.text('Ash')); // open sheet editor
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('track-plus-0')));
    await tester.pumpAndSettle();
    expect(find.text('8/10'), findsOneWidget);
    final chars = await container.read(charactersProvider.future);
    expect(chars.single.tracks.single.current, 8);
    // Clamp at max: tap plus 5 more times -> stays 10.
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.byKey(const Key('track-plus-0')));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('10/10'), findsOneWidget);
  });

  testWidgets('add stat and tag from the editor', (tester) async {
    final container = await pump(tester);
    await tester.tap(find.text('Ash'));
    await tester.pumpAndSettle();
    // Add stat via dialog.
    await tester.tap(find.byKey(const Key('add-stat')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('stat-label')), 'Iron');
    await tester.enterText(find.byKey(const Key('stat-value')), '+2');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('Iron'), findsOneWidget);
    // Add tag.
    await tester.tap(find.byKey(const Key('add-tag')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('tag-input')), 'wounded');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('wounded'), findsOneWidget);
    final c = (await container.read(charactersProvider.future)).single;
    expect(c.stats.single.value, '+2');
    expect(c.tags, ['wounded']);
    // Back to list.
    await tester.tap(find.byKey(const Key('sheet-back')));
    await tester.pumpAndSettle();
    expect(find.text('HP 7/10'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement.** Replace `_CharactersTab` with a ConsumerStatefulWidget holding `String? _editingId`:

**List view** (when `_editingId == null`): as today, plus subtitle becomes first-track summary `'${t.label} ${t.current}/${t.max}'` when tracks non-empty (falls back to note as now); row onTap → `setState(_editingId = c.id)`; FAB keeps the existing quick add (name+note dialog), newly added characters open straight into the editor (`_editingId = added.id`).

**Sheet editor** (when set; resolve the character from the watched list each build — live data; if id vanished, fall back to list): ListView with:
- Header row: IconButton(key `Key('sheet-back')`, arrow_back → `_editingId = null`), name (titleLarge), edit-name pencil (reuses existing `_EditDialog` for name+note).
- 'Stats' section: each stat a row (label bold, value, delete icon → replace with stat removed); `ActionChip`/OutlinedButton key `Key('add-stat')` → dialog with two fields (keys `stat-label`, `stat-value`, Cancel/Add buttons) — Add appends `CharStat` (skip when label empty).
- 'Tracks' section: each track a row — label, `IconButton(remove_circle_outline, key: Key('track-minus-$i'))`, `Text('${t.current}/${t.max}')`, `IconButton(add_circle_outline, key: Key('track-plus-$i'))`, delete icon. Steppers call `notifier.replace(c.copyWith(tracks: [...with t.adjusted(±1)]))`. 'Add track' button key `Key('add-track')` → dialog: label + max (number); new track starts current == max.
- 'Tags' section: Wrap of `InputChip(label, onDeleted → remove)`; add button key `Key('add-tag')` → dialog with field key `Key('tag-input')` + Add.
- 'Notes' section: the note text + the same pencil dialog (existing behavior preserved).

All mutations: `ref.read(charactersProvider.notifier).replace(updated)` immediately (auto-save). No Navigator pushes.

- [ ] **Step 4: Full** `flutter test` green; analyze 1 baseline info.
- [ ] **Step 5: Commit** `git add -A lib test && git commit -m "feat: character sheet editor (stats, track steppers, tags) in Characters tool"`

### Task 3: Verify, docs, ship (controller-run)

- [ ] Campaign round-trip test addition (test/campaign_io_test.dart): encode a campaign whose `juice.characters.v1` payload contains a full sheet, parse it back, expect rawByKey survives (validates through the new fromJson).
- [ ] Gates: analyze, `flutter test`, `python3 build_oracle.py`, `flutter build web`.
- [ ] Browser verify: Tools → Threads & Characters → Characters tab → open seeded/new character (FAB name dialog cannot be typed headless — seed localStorage instead), stepper +/- updates track, list row shows summary. Disclose headless typing limits.
- [ ] README: tracker bullet mentions flexible character sheets (stats/tracks/tags).
- [ ] ROADMAP: phase 4 Done; phase 5 next.
- [ ] PR `feat/character-sheets`, CI green before merge, squash-merge, deploy verify.
