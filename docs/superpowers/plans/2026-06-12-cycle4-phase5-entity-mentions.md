# Cycle 4 Phase 5: Entity Mentions + Save-as-Entity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** `@`-mention characters and open threads in journal prose; mentions render as tappable links; NPC/location results can be saved as tracked entities; the journal filters by character.

**Architecture:** A pure mention parser (`lib/engine/mention_parser.dart`) handling the `@[Name](char:ID)` / `@[Name](thread:ID)` token; a `MentionText` widget rendering tappable spans; `@` autocomplete in the composer; id-returning entity creates so save-as-entity can backfill a mention; export renders mentions as plain names.

**Tech Stack:** Flutter + flutter_riverpod. House rules: TDD; format hook; analyze baseline exactly 1 info; never construct GemmaInterpreterService in tests; commits exact, no co-author. Lost-update rule on read-modify-write.

**Branch:** `cycle4-phase5-entity-mentions` off main (after phase 4 merges). Plan committed first.

**Spec:** docs/superpowers/specs/2026-06-12-cycle4-living-journal-design.md §4.

---

### Task 1: Mention parser (pure)

**Files:**
- Create: `lib/engine/mention_parser.dart`
- Test: `test/mention_parser_test.dart`

- [ ] **Step 1: Failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/mention_parser.dart';

void main() {
  test('plain text → one text segment', () {
    final segs = parseMentions('hello world');
    expect(segs, hasLength(1));
    expect(segs.single.text, 'hello world');
    expect(segs.single.kind, MentionKind.text);
  });

  test('parses a char mention into a tappable segment', () {
    final segs = parseMentions('met @[Mara](char:c1) at dawn');
    expect(segs.map((s) => s.kind),
        [MentionKind.text, MentionKind.character, MentionKind.text]);
    expect(segs[1].text, 'Mara');
    expect(segs[1].id, 'c1');
    expect(segs[0].text, 'met ');
    expect(segs[2].text, ' at dawn');
  });

  test('parses a thread mention', () {
    final segs = parseMentions('re @[The Vow](thread:t9)');
    expect(segs.last.kind, MentionKind.thread);
    expect(segs.last.id, 't9');
    expect(segs.last.text, 'The Vow');
  });

  test('mentionToken builds the canonical form', () {
    expect(mentionToken('Mara', MentionKind.character, 'c1'),
        '@[Mara](char:c1)');
    expect(mentionToken('The Vow', MentionKind.thread, 't9'),
        '@[The Vow](thread:t9)');
  });

  test('mentionsToPlain strips tokens to display names', () {
    expect(mentionsToPlain('met @[Mara](char:c1) and @[Vow](thread:t9)'),
        'met Mara and Vow');
  });

  test('mentionedCharIds collects character ids only', () {
    final ids = mentionedCharIds('@[Mara](char:c1) @[Vow](thread:t9) @[Bo](char:c2)');
    expect(ids, {'c1', 'c2'});
  });

  test('malformed token renders as plain text', () {
    final segs = parseMentions('email a@[b].c not a mention');
    expect(segs, hasLength(1));
    expect(segs.single.kind, MentionKind.text);
  });
}
```

- [ ] **Step 2: Run, see fail.** `flutter test test/mention_parser_test.dart`

- [ ] **Step 3: Implement** `lib/engine/mention_parser.dart`:

```dart
/// Entity-mention markup for journal prose (spec: cycle4 §4).
/// Token form: `@[Display Name](char:ID)` or `@[Title](thread:ID)`.
library;

enum MentionKind { text, character, thread }

class MentionSegment {
  const MentionSegment(this.text, this.kind, [this.id]);
  final String text;
  final MentionKind kind;
  final String? id; // entity id for character/thread; null for text
}

final _mentionRe = RegExp(r'@\[([^\]]+)\]\((char|thread):([^)]+)\)');

/// Splits [body] into text and mention segments in order.
List<MentionSegment> parseMentions(String body) {
  final out = <MentionSegment>[];
  var last = 0;
  for (final m in _mentionRe.allMatches(body)) {
    if (m.start > last) {
      out.add(MentionSegment(body.substring(last, m.start), MentionKind.text));
    }
    final kind =
        m.group(2) == 'char' ? MentionKind.character : MentionKind.thread;
    out.add(MentionSegment(m.group(1)!, kind, m.group(3)));
    last = m.end;
  }
  if (last < body.length) {
    out.add(MentionSegment(body.substring(last), MentionKind.text));
  }
  return out.isEmpty ? [MentionSegment(body, MentionKind.text)] : out;
}

String mentionToken(String display, MentionKind kind, String id) =>
    '@[$display](${kind == MentionKind.character ? 'char' : 'thread'}:$id)';

/// Replaces every mention token with its display name (export / search).
String mentionsToPlain(String body) =>
    body.replaceAllMapped(_mentionRe, (m) => m.group(1)!);

/// Character ids referenced by mentions in [body].
Set<String> mentionedCharIds(String body) => {
      for (final m in _mentionRe.allMatches(body))
        if (m.group(2) == 'char') m.group(3)!,
    };
```

- [ ] **Step 4: Run, see pass.**

- [ ] **Step 5: Commit.** `git add lib/engine/mention_parser.dart test/mention_parser_test.dart && git commit -m "feat: entity-mention parser (@[name](char|thread:id))"`

---

### Task 2: id-returning entity creates

**Files:**
- Modify: `lib/state/providers.dart` (ThreadNotifier, CharacterNotifier)
- Test: extend `test/journal_test.dart` or a small new test

- [ ] **Step 1: Failing tests** — `ThreadNotifier.addReturningId(title)` returns the new id and the thread is present with that id; `CharacterNotifier.addReturningId(name)` same. (ProviderContainer pattern.)

- [ ] **Step 2: Run, see fail.**

- [ ] **Step 3: Implement.** Add to each notifier (mirroring `add`, but capture the id):

ThreadNotifier:
```dart
  Future<String> addReturningId(String title) async {
    final id = _newId();
    await _persist([Thread(id: id, title: title), ...await _ready]);
    return id;
  }
```
CharacterNotifier:
```dart
  Future<String> addReturningId(String name) async {
    final id = _newId();
    await _persist([Character(id: id, name: name), ...await _ready]);
    return id;
  }
```
(Leave the existing `add` methods; these are additive.)

- [ ] **Step 4: Run, see pass.**

- [ ] **Step 5: Commit.** `git commit -m "feat: id-returning entity creates for mention backfill"`

---

### Task 3: MentionText render widget + journal wiring

**Files:**
- Create: `lib/shared/mention_text.dart`
- Modify: `lib/features/journal_screen.dart` (entry text/result rendering uses MentionText for the body/remainder)
- Test: `test/mention_text_test.dart`

- [ ] **Step 1: Failing tests** — pump a `MentionText` in a MaterialApp; a char mention renders the name and tapping it calls the char callback with the id; a thread mention calls the thread callback; plain text renders with no tappable spans. Plus a journal-level test: an entry whose body has `@[Mara](char:c1)` renders 'Mara' (not the raw token) and tapping it opens the tracker tool (pump under HomeShell or assert the callback). Mirror existing widget-test pumps.

- [ ] **Step 2: Run, see fail.**

- [ ] **Step 3: Implement** `lib/shared/mention_text.dart`:

```dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../engine/mention_parser.dart';

/// Renders journal prose with `@`-mentions as tappable links.
class MentionText extends StatefulWidget {
  const MentionText(this.body,
      {super.key, this.style, this.onCharacterTap, this.onThreadTap});
  final String body;
  final TextStyle? style;
  final void Function(String id)? onCharacterTap;
  final void Function(String id)? onThreadTap;

  @override
  State<MentionText> createState() => _MentionTextState();
}

class _MentionTextState extends State<MentionText> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
    final theme = Theme.of(context);
    final base = widget.style ?? theme.textTheme.bodyMedium;
    final linkStyle = base?.copyWith(
        color: theme.colorScheme.primary, fontWeight: FontWeight.w600);
    final spans = <InlineSpan>[];
    for (final seg in parseMentions(widget.body)) {
      if (seg.kind == MentionKind.text) {
        spans.add(TextSpan(text: seg.text, style: base));
      } else {
        final rec = TapGestureRecognizer()
          ..onTap = () {
            if (seg.kind == MentionKind.character) {
              widget.onCharacterTap?.call(seg.id!);
            } else {
              widget.onThreadTap?.call(seg.id!);
            }
          };
        _recognizers.add(rec);
        spans.add(TextSpan(text: seg.text, style: linkStyle, recognizer: rec));
      }
    }
    return Text.rich(TextSpan(children: spans));
  }
}
```

journal_screen.dart: in the `JournalKind.text` ListTile `title` and the `_PayloadCard` remainder + flat result body, replace the plain `Text(e.body)` with
`MentionText(e.body, onCharacterTap: _openCharacter, onThreadTap: _openThread)`.
Add helpers:
```dart
  void _openCharacter(String id) =>
      ToolHost.openToolIfKnown(context, 'threads-characters');
  void _openThread(String id) =>
      setState(() => _filterThreadId = id);
```
(Keep it simple: character tap opens the tracker tool; thread tap filters the journal to that thread — both reuse existing affordances. Import mention_text.dart.)

- [ ] **Step 4: Run, see pass.** Also `flutter test test/journal_screen_test.dart` (existing entries with no mentions render unchanged — MentionText on plain text yields one span).

- [ ] **Step 5: Commit.** `git commit -m "feat: render @-mentions as tappable links in the journal"`

---

### Task 4: @ autocomplete in the composer

**Files:**
- Modify: `lib/features/journal_screen.dart` (composer listener + an `@` suggestion panel)
- Test: `test/mention_autocomplete_test.dart`

- [ ] **Step 1: Failing tests** — seed a character 'Mara' (c1) and an open thread 'The Vow' (t9). Typing `@ma` in the composer shows a suggestion for Mara; tapping it replaces the `@ma` token with `@[Mara](char:c1) ` in the composer text. Typing `@` with no query shows both a character section and a thread section. Selecting a thread inserts `@[The Vow](thread:t9) `. (Mirror slash_palette_test's pump.)

- [ ] **Step 2: Run, see fail.**

- [ ] **Step 3: Implement.**

Reuse the existing composer listener (`_onComposerChanged` from phase 2). Detect an active `@`-token at the caret: the substring from the last `@` to the caret with no intervening space. Add state `String? _mentionQuery`. Compute it in the listener; when non-null, render an `@`-suggestion panel above the composer (sibling to the slash palette — they're mutually exclusive: slash requires leading `/`, mention is mid-text `@`).

```dart
  // Active @-mention query (text from the last '@' to the caret), or null.
  String? _mentionQuery;

  void _onComposerChanged() {
    final text = _composer.text;
    final slash = text.startsWith('/');
    final sel = _composer.selection.baseOffset;
    String? mention;
    if (!slash && sel > 0) {
      final upToCaret = text.substring(0, sel);
      final at = upToCaret.lastIndexOf('@');
      if (at >= 0 && !upToCaret.substring(at).contains(' ')) {
        mention = upToCaret.substring(at + 1);
      }
    }
    setState(() {
      _slashActive = slash;
      _mentionQuery = mention;
    });
  }
```

Panel (`_mentionPanel`) shows characters whose name contains the query + open threads whose title contains it (two labeled sections), each a ListTile keyed `mention-char-<id>` / `mention-thread-<id>`. On tap, replace the active `@query` with the token:

```dart
  void _insertMention(String display, MentionKind kind, String id) {
    final text = _composer.text;
    final sel = _composer.selection.baseOffset;
    final at = text.substring(0, sel).lastIndexOf('@');
    final token = '${mentionToken(display, kind, id)} ';
    final next = text.replaceRange(at, sel, token);
    _composer.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: at + token.length),
    );
    setState(() => _mentionQuery = null);
  }
```

Render `if (_mentionQuery != null) _mentionPanel()` above the composer (and ensure the slash palette and mention panel don't both show: slash requires leading `/`, mention is suppressed when slash-active). Build the panel from `charactersProvider` + open `threadsProvider`.

- [ ] **Step 4: Run, see pass.** Full `flutter test`.

- [ ] **Step 5: Commit.** `git commit -m "feat: @-mention autocomplete in the journal composer"`

---

### Task 5: Save-as-entity + character filter + export plain names

**Files:**
- Modify: `lib/features/journal_screen.dart` (payload card actions; character filter chip; _interpret/_onAction)
- Modify: `lib/engine/journal_export.dart` (plain-name bodies)
- Modify: `lib/engine/journal_search.dart` (search over plain text — verify mentions don't break search; if it searches raw body, switch to mentionsToPlain)
- Test: `test/save_as_entity_test.dart` + extend `test/journal_export_test.dart` + `test/journal_search_test.dart`

- [ ] **Step 1: Failing tests**
  - Save-as: a result entry whose `sourceTool == 'gen-npcs'` (or 'gen-details' with a name) shows a "Save as character" action (PopupMenu item or button keyed `save-char-<id>`); invoking it creates a character whose name is the entry summary/first roll value AND appends a `@[Name](char:<newid>)` mention to the entry body. A 'gen-exploration'/location entry offers "Save as thread". (Decide the trigger by sourceTool; keep it to NPC→character, location→thread.)
  - Export: an entry body with `@[Mara](char:c1)` exports (md + html) as 'Mara' (no raw token). Extend journal_export_test.
  - Search: searching 'Mara' matches an entry whose body has `@[Mara](char:c1)`. (If journal_search already lowercases the raw body, the token text 'Mara' is still substring-present, so it may pass; add the test to lock it and switch to mentionsToPlain if needed.)

- [ ] **Step 2: Run, see fail.**

- [ ] **Step 3: Implement.**
  - In the entry PopupMenu (`menu` in `_entry`), add a conditional item when the entry is a result with a save-able sourceTool:
    ```dart
    if (e.kind == JournalKind.result && _saveAsKind(e) != null)
      PopupMenuItem(value: 'save-entity', child: Text(
        _saveAsKind(e) == MentionKind.character ? 'Save as character' : 'Save as thread')),
    ```
    with `_saveAsKind(e)` returning character for sourceTool in {'gen-npcs'}, thread for {'gen-exploration'} (and null otherwise — keep the set small and explicit). Handle 'save-entity' in `_onAction`:
    ```dart
    case 'save-entity':
      final kind = _saveAsKind(entry)!;
      final name = entry.payload?['summary'] as String? ??
          (entry.payload?['rolls'] as List?)?.cast<Map>().firstOrNull?['display']
              as String? ??
          entry.title;
      final id = kind == MentionKind.character
          ? await ref.read(charactersProvider.notifier).addReturningId(name)
          : await ref.read(threadsProvider.notifier).addReturningId(name);
      final fresh = (ref.read(journalProvider).valueOrNull ?? const [])
          .where((x) => x.id == entry.id).firstOrNull;
      if (fresh == null) return;
      await ref.read(journalProvider.notifier).replace(fresh.copyWith(
          body: '${fresh.body}\n${mentionToken(name, kind, id)}'));
    ```
  - Character filter chip: in the filter-chip row, add chips for characters referenced by any entry's mentions (`mentionedCharIds` across entries → resolve names from charactersProvider), keyed `char-filter-<id>`; selecting filters `visible` to entries whose body mentions that id. Add `String? _filterCharId` state and apply it in `build` alongside thread/tag filters.
  - Export: in journal_export.dart, wrap body text with `mentionsToPlain(...)` before `_esc`/`_escBody` (both md and html paths). Import mention_parser.dart.
  - Search: in journal_search.dart, if it matches against `e.body`, change to `mentionsToPlain(e.body)` so tokens don't pollute matches.

- [ ] **Step 4: Run, see pass.** Full `flutter test` + `flutter analyze`.

- [ ] **Step 5: Commit.** `git commit -m "feat: save NPC/location results as entities; filter + export honor mentions"`

---

### Task 6: Docs

- [ ] **Step 1:** README note:
```markdown
- Mentions: type `@` in the journal to link a character or thread; mentions render as tappable links and filter the journal. Save an NPC or location result as a tracked entity in one tap.
```
- [ ] **Step 2:** `flutter analyze` + `flutter test` green.
- [ ] **Step 3: Commit.** `git commit -m "docs: README note for entity mentions"`

---

## Self-review notes

- Spec §4 coverage: `@` autocomplete (Task 4), markup token (Task 1), tappable spans (Task 3), display-name-frozen-at-insert (token stores the name; tap resolves by id — Task 3 navigation by id), export plain names (Task 5), character filter (Task 5), save-as-entity backfilling a mention (Task 5, needs Task 2's id-returning creates).
- Mutual exclusivity: slash palette (leading `/`) and `@` mention panel (mid-text `@`, suppressed when slash-active) never both show.
- Lost-update: save-entity re-reads the fresh entry before `replace` (mirrors `_interpret`).
- Verify-against-source: journal_search.dart's match target (Task 5 — switch to mentionsToPlain only if it matches raw body); the existing composer listener `_onComposerChanged` from phase 2 (extend, don't duplicate).
- Type names: parseMentions, mentionToken, mentionsToPlain, mentionedCharIds, MentionKind, MentionSegment, MentionText, addReturningId, _mentionQuery, _filterCharId, keys mention-char-<id>/mention-thread-<id>/char-filter-<id>/save-char/save-entity.
- Deferred (spec): mention rename re-propagation (label frozen; tap resolves by id).
