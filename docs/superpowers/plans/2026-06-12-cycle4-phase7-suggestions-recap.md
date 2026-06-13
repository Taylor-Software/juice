# Cycle 4 Phase 7: Entity Suggestions + Recap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** The journal proactively offers to track recurring people/places (C3), and can recap what's happened — with a "Previously on…" nudge when you return (C2). Final cycle-4 phase; ends with closeout.

**Architecture:** A pure suggestion engine over journal text + existing entities; dismissible chips above the composer that create a tracked entity on tap (never auto-create). A new `InterpreterService.summarize` seam powers `/recap` and a cached "Previously on" banner shown when new entries exist since last visit.

**Tech Stack:** Flutter + flutter_riverpod. House rules: TDD; format hook; analyze baseline exactly 1 info; never construct GemmaInterpreterService in tests (FakeInterpreterService); the Gemma `summarize` reuses `_generate`'s watchdog/stopGeneration discipline; commits exact, no co-author.

**Branch:** `cycle4-phase7-suggestions-recap` off main (after phase 6 merges). Plan committed first.

**Spec:** docs/superpowers/specs/2026-06-12-cycle4-living-journal-design.md §7 (C3, C2).

---

### Task 1: Entity-suggestion engine (pure)

**Files:**
- Create: `lib/engine/entity_suggestions.dart`
- Test: `test/entity_suggestions_test.dart`

- [ ] **Step 1: Failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/entity_suggestions.dart';
import 'package:juice_oracle/engine/models.dart';

JournalEntry _e(String id, String body,
        {JournalKind kind = JournalKind.text,
        String? sourceTool,
        Map<String, dynamic>? payload}) =>
    JournalEntry(
        id: id,
        timestamp: DateTime.utc(2026, 6, 12),
        title: '',
        body: body,
        kind: kind,
        sourceTool: sourceTool,
        payload: payload);

void main() {
  test('suggests an NPC result by its summary name', () {
    final s = suggestEntities(
      [
        _e('1', 'Name: Kestrel\nRole: Scout',
            kind: JournalKind.result,
            sourceTool: 'gen-npcs',
            payload: {'v': 1, 'summary': 'Kestrel', 'rolls': const []}),
      ],
      existingCharNames: const {},
      existingThreadTitles: const {},
      dismissed: const {},
    );
    expect(s.map((x) => x.name), contains('Kestrel'));
    expect(s.firstWhere((x) => x.name == 'Kestrel').kind,
        SuggestionKind.character);
  });

  test('suggests a capitalized name that recurs at least twice', () {
    final s = suggestEntities(
      [
        _e('1', 'We met Brannoc by the well.'),
        _e('2', 'Brannoc warned us about the road.'),
      ],
      existingCharNames: const {},
      existingThreadTitles: const {},
      dismissed: const {},
    );
    expect(s.map((x) => x.name), contains('Brannoc'));
  });

  test('a name appearing once is not suggested', () {
    final s = suggestEntities(
      [_e('1', 'A lone traveller named Sessaly passed by.')],
      existingCharNames: const {},
      existingThreadTitles: const {},
      dismissed: const {},
    );
    expect(s.map((x) => x.name), isNot(contains('Sessaly')));
  });

  test('existing characters and dismissed names are not suggested', () {
    final entries = [
      _e('1', 'Brannoc again.'),
      _e('2', 'Brannoc once more.'),
      _e('3', 'Kara and Kara.'),
    ];
    final s = suggestEntities(
      entries,
      existingCharNames: {'brannoc'},
      existingThreadTitles: const {},
      dismissed: {'character:kara'},
    );
    final names = s.map((x) => x.name).toList();
    expect(names, isNot(contains('Brannoc'))); // already tracked
    expect(names, isNot(contains('Kara'))); // dismissed
  });

  test('sentence-initial common words are not mistaken for names', () {
    final s = suggestEntities(
      [_e('1', 'The door opened. The room was dark.')],
      existingCharNames: const {},
      existingThreadTitles: const {},
      dismissed: const {},
    );
    expect(s, isEmpty);
  });

  test('suggestionKey is stable kind:lowername', () {
    expect(suggestionKey(SuggestionKind.character, 'Mara'), 'character:mara');
    expect(suggestionKey(SuggestionKind.thread, 'The Vow'), 'thread:the vow');
  });
}
```

- [ ] **Step 2: Run, see fail.**

- [ ] **Step 3: Implement** `lib/engine/entity_suggestions.dart`:

```dart
/// Heuristic "track this?" suggestions over journal prose + result payloads.
/// Conservative by design (spec cycle4 §7 C3): never auto-creates; the UI
/// turns an accepted suggestion into a tracked entity.
library;

import 'mention_parser.dart';
import 'models.dart';

enum SuggestionKind { character, thread }

class EntitySuggestion {
  const EntitySuggestion(this.name, this.kind);
  final String name;
  final SuggestionKind kind;
}

/// Stable dedupe/dismiss key: 'character:mara' / 'thread:the vow'.
String suggestionKey(SuggestionKind kind, String name) =>
    '${kind == SuggestionKind.character ? 'character' : 'thread'}:'
    '${name.toLowerCase()}';

// Words that start sentences but aren't names. Small, high-frequency set.
const _stop = {
  'the', 'a', 'an', 'we', 'i', 'he', 'she', 'they', 'it', 'you', 'this',
  'that', 'there', 'then', 'but', 'and', 'so', 'as', 'at', 'in', 'on', 'of',
  'to', 'my', 'our', 'his', 'her', 'their', 'no', 'yes', 'if', 'when', 'after',
  'before', 'meanwhile', 'later', 'now', 'name', 'role', 'area',
};

final _word = RegExp(r'\b([A-Z][a-z]{2,})\b');

/// Suggestions worth offering, most-frequent first. [existingCharNames] and
/// [existingThreadTitles] are lowercased; [dismissed] holds suggestionKey()s.
List<EntitySuggestion> suggestEntities(
  List<JournalEntry> entries, {
  required Set<String> existingCharNames,
  required Set<String> existingThreadTitles,
  required Set<String> dismissed,
}) {
  final out = <EntitySuggestion>[];
  final seen = <String>{};

  void add(String name, SuggestionKind kind) {
    final key = suggestionKey(kind, name);
    final lower = name.toLowerCase();
    if (seen.contains(key) || dismissed.contains(key)) return;
    if (kind == SuggestionKind.character && existingCharNames.contains(lower)) {
      return;
    }
    if (kind == SuggestionKind.thread && existingThreadTitles.contains(lower)) {
      return;
    }
    seen.add(key);
    out.add(EntitySuggestion(name, kind));
  }

  // (a) NPC result payloads → character by summary name.
  for (final e in entries) {
    if (e.kind == JournalKind.result && e.sourceTool == 'gen-npcs') {
      final name = e.payload?['summary'] as String?;
      if (name != null && name.trim().isNotEmpty) {
        add(name.trim(), SuggestionKind.character);
      }
    }
  }

  // (b) Proper nouns recurring >= 2 times across prose (ignoring text already
  // inside mentions, and the small stop set).
  final counts = <String, int>{};
  final display = <String, String>{};
  for (final e in entries) {
    final plain = mentionsToPlain(e.body);
    for (final m in _word.allMatches(plain)) {
      final w = m.group(1)!;
      if (_stop.contains(w.toLowerCase())) continue;
      final lower = w.toLowerCase();
      counts[lower] = (counts[lower] ?? 0) + 1;
      display[lower] ??= w;
    }
  }
  final repeated = counts.entries.where((e) => e.value >= 2).toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final e in repeated) {
    add(display[e.key]!, SuggestionKind.character);
  }
  return out;
}
```

- [ ] **Step 4: Run, see pass.**

- [ ] **Step 5: Commit.** `git add lib/engine/entity_suggestions.dart test/entity_suggestions_test.dart && git commit -m "feat: heuristic entity-suggestion engine"`

---

### Task 2: summarize interpreter seam

**Files:**
- Modify: `lib/engine/oracle_interpreter.dart` (summary prompt + parse)
- Modify: `lib/state/interpreter.dart` (abstract method)
- Modify: `lib/state/interpreter_gemma.dart` (impl via `_generate`)
- Modify: `test/fake_interpreter.dart` (scripting)
- Test: extend `test/interpreter_test.dart`

- [ ] **Step 1: Failing tests** — add to interpreter_test.dart: `buildSummaryPrompt(['a','b'])` contains both entries + a recap instruction; `parseSummary('<think>x</think> The party fled.')` strips think tags → 'The party fled.'. Fake: a test using `FakeInterpreterService(initial: ready)..queuedSummary.add('Recap text')` returns it from `summarize([...])` and records `lastSummaryEntries`.

- [ ] **Step 2: Run, see fail.**

- [ ] **Step 3: Implement.**

oracle_interpreter.dart (mirror buildVoicePrompt/parseVoiceResponse ~line 294):
```dart
const String summarySystemInstruction =
    'You recap a solo RPG journal. Given recent entries in order, write a '
    'tight 2-3 sentence "previously on" recap in past tense, plain prose, no '
    'lists or preamble.';

/// Builds the recap prompt from recent entry texts (oldest first), capped
/// like the other builders.
String buildSummaryPrompt(List<String> entries) {
  final capped = entries.length > 20 ? entries.sublist(entries.length - 20)
      : entries;
  final body = capped.map((e) => '- $e').join('\n');
  return 'Recent journal entries (oldest first):\n$body\n\nRecap:';
}

/// Plain-text parse: strip think-tags, trim (as parseVoiceResponse).
String parseSummary(String raw) {
  var s = raw.replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '');
  return s.trim();
}
```
(If parseVoiceResponse already has a think-strip helper, reuse it.)

interpreter.dart abstract — add:
```dart
  /// One-shot recap of recent journal entries (plain text). Requires ready.
  Future<String> summarize(List<String> entries);
```

interpreter_gemma.dart — add (mirrors voiceLine):
```dart
  @override
  Future<String> summarize(List<String> entries) async {
    return parseSummary(await _generate(buildSummaryPrompt(entries)));
  }
```

fake_interpreter.dart — add:
```dart
  final List<String> queuedSummary = [];
  Object? summaryError;
  List<String>? lastSummaryEntries;
  int summaryCalls = 0;

  @override
  Future<String> summarize(List<String> entries) async {
    lastSummaryEntries = entries;
    summaryCalls++;
    if (summaryError != null) throw summaryError!;
    if (queuedSummary.isEmpty) return 'A canned recap.';
    return queuedSummary.removeAt(0);
  }
```

- [ ] **Step 4: Run, see pass.** Full `flutter test` (the abstract addition forces the fake to implement it — confirm no other InterpreterService impls exist besides Gemma + fake).

- [ ] **Step 5: Commit.** `git commit -m "feat: InterpreterService.summarize seam for journal recap"`

---

### Task 3: Suggestion chips above the composer

**Files:**
- Modify: `lib/state/providers.dart` (dismissed-suggestions persistence)
- Modify: `lib/features/journal_screen.dart` (chips + accept/dismiss)
- Test: `test/suggestion_chips_test.dart`

- [ ] **Step 1: Failing tests** — seed two text entries both mentioning 'Brannoc' (no existing character). A suggestion chip 'Track Brannoc?' (Key('suggest-character-brannoc')) appears above the composer. Tapping it creates a character named 'Brannoc' (charactersProvider) and the chip disappears. A dismiss affordance (Key('suggest-dismiss-character:brannoc')) hides it and persists (re-pump: chip absent). Mirror slash_palette_test's pump.

- [ ] **Step 2: Run, see fail.**

- [ ] **Step 3: Implement.**

Persistence — a session-scoped string set provider `dismissedSuggestionsProvider` (mirror toolMruProvider or a simple SharedPreferences-backed AsyncNotifier keyed `juice.suggestDismissed.<sid>` holding a JSON list). Methods: `dismiss(String key)`. (Read how toolMruProvider persists a list and mirror it.)

journal_screen — compute suggestions in the data branch:
```dart
final existingChars = {
  for (final c in (ref.watch(charactersProvider).valueOrNull ?? const <Character>[]))
    c.name.toLowerCase()
};
final existingThreads = {
  for (final t in (ref.watch(threadsProvider).valueOrNull ?? const <Thread>[]))
    t.title.toLowerCase()
};
final dismissed = ref.watch(dismissedSuggestionsProvider).valueOrNull ?? const <String>{};
final suggestions = suggestEntities(entries,
    existingCharNames: existingChars,
    existingThreadTitles: existingThreads,
    dismissed: dismissed).take(3).toList();
```
Render a one-row wrap of chips just above the composer (below the ask/slash/mention area), each an InputChip with an onPressed (accept) and onDeleted (dismiss):
```dart
if (suggestions.isNotEmpty)
  Padding(
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
    child: Wrap(spacing: 8, children: [
      for (final s in suggestions)
        InputChip(
          key: Key('suggest-${s.kind == SuggestionKind.character ? 'character' : 'thread'}-${s.name.toLowerCase()}'),
          avatar: Icon(s.kind == SuggestionKind.character ? Icons.person_add_alt : Icons.bookmark_add_outlined, size: 16),
          label: Text('Track ${s.name}?'),
          onPressed: () => _acceptSuggestion(s),
          onDeleted: () => ref.read(dismissedSuggestionsProvider.notifier)
              .dismiss(suggestionKey(s.kind, s.name)),
          deleteIcon: Key('suggest-dismiss-${suggestionKey(s.kind, s.name)}') != null
              ? const Icon(Icons.close, size: 16) : null,
        ),
    ]),
  ),
```
(Give the delete icon a key via wrapping; if InputChip.deleteIcon keying is awkward, use a separate trailing IconButton keyed `suggest-dismiss-<key>` instead of onDeleted.)

`_acceptSuggestion`:
```dart
Future<void> _acceptSuggestion(EntitySuggestion s) async {
  if (s.kind == SuggestionKind.character) {
    await ref.read(charactersProvider.notifier).addReturningId(s.name);
  } else {
    await ref.read(threadsProvider.notifier).addReturningId(s.name);
  }
}
```
(Once created, the entity name matches an existing entity so the suggestion naturally drops out.)

- [ ] **Step 4: Run, see pass.** Full `flutter test`.

- [ ] **Step 5: Commit.** `git commit -m "feat: dismissible track-this-entity suggestion chips"`

---

### Task 4: /recap + "Previously on" banner

**Files:**
- Modify: `lib/state/providers.dart` (recap cache: last-seen + summary per session)
- Modify: `lib/features/journal_screen.dart` (/recap built-in + banner)
- Test: `test/recap_test.dart`

- [ ] **Step 1: Failing tests** — with FakeInterpreterService ready + `queuedSummary.add('The party fled the keep.')`:
  - `/recap` (slash built-in, Key('slash-cmd-recap')) runs summarize over the entries since the last scene divider and shows the result (a dialog/banner containing 'The party fled the keep.'); fake.lastSummaryEntries is non-empty.
  - "Previously on" banner: seed a journal with entries and NO stored last-seen; on pump the banner (Key('recap-banner')) appears with a Recap action; tapping runs summarize. Dismissing (Key('recap-dismiss')) hides it and records last-seen so a re-pump doesn't show it.
  - Unsupported interpreter: `/recap` shows a "needs the model" snackbar (no crash); banner's Recap action absent or disabled.

- [ ] **Step 2: Run, see fail.**

- [ ] **Step 3: Implement.**

Recap cache provider keyed `juice.recap.<sid>` storing `{lastSeenId, summary}` (mirror settings provider). Methods: `markSeen(String entryId)`, `cacheSummary(String entryId, String summary)`.

journal_screen:
- `/recap` built-in (like `/scene`): add `_builtinRecap = 'recap'`; palette row Key('slash-cmd-recap'); `_send` Enter handles `'recap' == tok`. Action `_recap()`:
  ```dart
  Future<void> _recap() async {
    if (!_canVoice) { // reuse interpreter-supported gate
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Recap needs the on-device model.')));
      return;
    }
    final entries = ref.read(journalProvider).valueOrNull ?? const [];
    // Entries since the last scene divider (oldest first).
    final sinceScene = _entriesSinceLastScene(entries);
    final texts = [for (final e in sinceScene) e.title.isEmpty ? e.body : '${e.title}: ${e.body}'];
    String summary;
    try {
      summary = await ref.read(interpreterServiceProvider).summarize(texts);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Recap failed: $e')));
      return;
    }
    if (!mounted) return;
    await showDialog<void>(context: context, builder: (_) => AlertDialog(
      title: const Text('Previously…'),
      content: Text(summary),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    ));
  }
  ```
  (`_entriesSinceLastScene`: walk newest-first until a scene divider, reverse to oldest-first; if no scene, take the last ~10.)
- "Previously on" banner: in the data branch, when entries non-null & non-empty & the newest entry id != recap cache lastSeenId & `_canVoice`, render a dismissible Material banner (Key('recap-banner')) above the header with a "Recap" action (calls `_recap`) and a dismiss (Key('recap-dismiss')) that calls `markSeen(newestId)`.

- [ ] **Step 4: Run, see pass.** Full `flutter test` + analyze.

- [ ] **Step 5: Commit.** `git commit -m "feat: /recap and a Previously-on banner via the interpreter"`

---

### Task 5: Docs + cycle closeout

**Files:**
- Modify: `README.md`
- Modify: `ROADMAP.md` (cycle 4 section)
- Modify: `docs/superpowers/specs/2026-06-12-cycle4-living-journal-design.md` (status → shipped)

- [ ] **Step 1:** README note:
```markdown
- The journal helps you keep track: it suggests recurring people to track as characters, and (with the model) gives a "previously on" recap of recent play via `/recap`.
```

- [ ] **Step 2:** ROADMAP — add a "Cycle 4: The Living Journal" section above "Cloud storage stance", listing PRs #33–#3X (the 7 phases), the deferrals (LLM suggestOdds, mention rename re-propagation, B3 scene loop, D-theme, stores), and noting the lost-update + tolerant-payload patterns carried forward.

- [ ] **Step 3:** Flip the cycle-4 spec status to **shipped** with the phase→PR map.

- [ ] **Step 4:** `flutter analyze` (baseline) + `flutter test` (green).

- [ ] **Step 5: Commit.** `git commit -m "docs: cycle 4 closeout — suggestions/recap shipped"`

---

## Self-review notes

- Spec §7 C3: heuristic suggestions (payload NPC + repeated proper nouns), conservative (≥2, stop-set, existing/dismissed excluded), dismissible + persisted, never auto-creates (Task 1+3). C2: summarize seam (Task 2), `/recap` + previously-on banner with cache (Task 4).
- Graceful degradation: suggestions are heuristic (work with no model); recap/banner gated on interpreter-supported.
- New abstract method forces both impls — confirm only Gemma + fake implement InterpreterService.
- Verify-against-source: toolMruProvider persistence pattern (Task 3 dismissed set), settings provider pattern (Task 4 recap cache), parseVoiceResponse think-strip (Task 2 reuse).
- Type names: suggestEntities/EntitySuggestion/SuggestionKind/suggestionKey, summarize/buildSummaryPrompt/parseSummary/summarySystemInstruction, queuedSummary, dismissedSuggestionsProvider, recap cache provider, keys suggest-<kind>-<name>/suggest-dismiss-<key>/slash-cmd-recap/recap-banner/recap-dismiss.
- Deferred: cross-session recap auto-run on open (banner offers it, doesn't auto-run the LLM).
