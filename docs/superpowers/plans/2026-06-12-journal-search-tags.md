# Cycle 3 Item C: Journal Search + Tags Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Find anything in the campaign journal ("that NPC detail from twelve sessions ago" — the scan's #1 unmet need): free-text search over entries plus per-entry tags, both filterable from the journal screen. The pure search function is the retrieval foundation item D's journal-aware interpreter will reuse.

**Architecture:** `tags` field on JournalEntry (additive JSON, campaign schema stays v2). Pure-Dart search in `lib/engine/journal_search.dart`. Journal screen grows a search toggle + field, tag chips in the existing filter row, and a Tags… entry action (dialog pattern copied from the character sheet's tag editor, tracker_screen.dart:328-456).

**Branch:** `feat/journal-search-tags` off `main`.

Hard rules: analyze exactly 1 pre-existing info (lib/engine/models.dart:2); suite green (currently 299); TDD; exact commit messages, no co-author lines; no new dependencies.

---

### Task 1: Model — JournalEntry.tags

**Files:**
- Modify: `lib/engine/models.dart` (JournalEntry, lines 72-130ish — read the whole class incl. toJson/fromJson first)
- Test: extend `test/journal_test.dart` (read first, match style)

- [ ] **Step 1: failing tests.** JSON round-trip with tags; legacy JSON
  without `tags` key parses to `const []` (tolerance pattern identical to
  Combatant at models.dart:258 — `((j['tags'] as List?) ?? const [])
  .whereType<String>().toList()`); copyWith carries/overrides tags.

- [ ] **Step 2: implement.** `this.tags = const []` constructor param,
  `final List<String> tags`, copyWith `List<String>? tags` (no clear flag
  needed — pass `[]` to clear), `'tags': tags` in toJson, tolerant fromJson.

- [ ] **Step 3: gates + commit.**

```bash
git add lib/engine/models.dart test/journal_test.dart
git commit -m "feat: tags on journal entries (additive JSON, tolerant parse)"
```

---

### Task 2: Pure search engine

**Files:**
- Create: `lib/engine/journal_search.dart`
- Test: `test/journal_search_test.dart`

Binding API:

```dart
/// Case-insensitive multi-term search. Every whitespace-separated term in
/// [query] must match somewhere in the entry (title, body, or a tag) —
/// AND semantics. Blank query returns [entries] unchanged. Preserves
/// input order. Pure Dart; item D's interpreter retrieval reuses this.
List<JournalEntry> searchEntries(List<JournalEntry> entries, String query);

/// Distinct tags across [entries], first-seen order.
List<String> allTags(List<JournalEntry> entries);
```

- [ ] **Step 1: failing tests.** Case-insensitivity; term in title vs body
  vs tag; multi-term AND across fields (one term hits title, other hits a
  tag); no match → empty; blank/whitespace query → identity; order
  preserved; allTags dedupes preserving first-seen order; empty list.

- [ ] **Step 2: implement** (imports: `models.dart` only).

- [ ] **Step 3: gates + commit.**

```bash
git add lib/engine/journal_search.dart test/journal_search_test.dart
git commit -m "feat: journal search engine — multi-term AND over title/body/tags"
```

---

### Task 3: Journal screen — search field, tag chips, Tags… action

**Files:**
- Modify: `lib/features/journal_screen.dart`
- Test: `test/journal_search_ui_test.dart`

Behavior (read the screen's current filter-chip row at ~line 57-85 and the
export/Clear row first):

1. **Search**: IconButton (Icons.search, `Key('journal-search')`, in the
   export/Clear row, hidden when journal empty) toggles a TextField row
   (`Key('journal-search-field')`, hint 'Search journal…', autofocus, with
   a clear/close affordance that empties the query and hides the field).
   Non-empty query filters the visible list via `searchEntries` — composed
   WITH the existing thread filter and the new tag filter (intersection).
2. **Tag chips**: in the existing horizontal chip row (after thread chips),
   one FilterChip per `allTags(entries)` labeled `#tag`
   (`Key('tag-chip-<tag>')`); selecting one filters to entries carrying
   that tag; only one tag selected at a time (tap again to clear), same
   interaction shape as the thread chips. Row appears whenever threads OR
   tags exist.
3. **Tags… action**: new entry-menu item (all kinds) between 'Link to
   thread…' and 'Edit note…'. Dialog lists current tags as InputChips with
   delete (×), plus an 'Add tag' flow copied from the character-sheet
   editor (tracker_screen.dart:441-456 — TextField `Key('tag-input')`,
   Add/Cancel). Saving calls `journalProvider.notifier.replace` with
   updated tags (trimmed, lowercased? NO — preserve case, compare
   case-insensitively in search; dedupe exact duplicates). Entry cards show
   their tags as a small `#a #b` suffix line (style like the thread `⤷`
   line).
4. Stale filter safety: selected tag that no longer exists (entry deleted)
   simply matches nothing — acceptable; clearing is one tap. Search state
   is screen-local (not persisted).

- [ ] **Step 1: failing widget tests.** Seed journal (mock-prefs pattern
  from test/journal_interpret_test.dart) with 3 entries, one tagged
  'omens'. Tests: search icon toggles field; typing 'mill' filters to
  matching entries (others gone); clearing restores; tag chip `#omens`
  filters; Tags… dialog adds a tag (provider state updated + chip row
  gains `#new`); removing a tag via × updates provider; search matches
  tags ('omens' query finds the tagged entry).

- [ ] **Step 2: implement.**

- [ ] **Step 3: gates + commit.**

```bash
git add lib/features/journal_screen.dart test/journal_search_ui_test.dart
git commit -m "feat: journal search field, tag chips, and per-entry tag editing"
```

---

### Task 4: Export + docs

**Files:**
- Modify: `lib/engine/journal_export.dart` + `test/journal_export_test.dart`
- Modify: `README.md`

- [ ] **Step 1 (TDD):** exports render tags — markdown: a trailing
  `` `#a` `#b` `` line per tagged entry (after the thread line); HTML: a
  `<p class="thread">#a #b</p>`-style line (reuse the muted style;
  escaped). Untagged entries unchanged (existing tests must stay green).

- [ ] **Step 2:** README journal clause: mention search + tags (one short
  phrase, e.g. "searchable, taggable" inside the existing journal
  parenthetical).

- [ ] **Step 3: full gates + commit.** `flutter test`, analyze 1 info,
  `flutter build web`.

```bash
git add lib/engine/journal_export.dart test/journal_export_test.dart README.md
git commit -m "feat: tags in journal exports; README search/tags note"
```

---

## Verification (controller)

Browser: seeded journal → search 'mill' filters live; tag an entry via
menu; `#tag` chip appears and filters; export carries tags. PR → CI →
squash-merge → roadmap row C done.
