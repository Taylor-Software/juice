# Cycle 3 Item B: Journal Export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Export the active campaign's journal as a styled, shareable document — Markdown or self-contained HTML — via the existing file-save path. (Landscape: styled journal export is a headline/praised feature in Pocketforge and the official Mythic app.)

**Architecture:** Pure-Dart exporter (`lib/engine/journal_export.dart`, fully unit-tested) + a small export action on the journal screen that reuses the `FilePicker.saveFile(bytes:)` pattern from campaign export (lib/shared/home_shell.dart:135-161).

**Branch:** `feat/journal-export` off `main`.

Hard rules: analyze stays at exactly 1 pre-existing info (lib/engine/models.dart:2); suite green (currently 280); TDD; exact commit messages, no co-author lines; no new dependencies.

Rendering rules (both formats; entries are stored newest-first — export
reads OLDEST-FIRST, document order):
- Document header: campaign name as title + "Exported <YYYY-MM-DD>" line
  (exportedAt passed in — no Date.now inside the pure function).
- Scene entry → section heading: title, plus ` — Chaos N` when
  chaosFactor != null. Markdown `## `, HTML `<h2>`.
- Result entry → bold/strong title line, then body (multi-line bodies
  preserved; in HTML, newlines → `<br>`); body may be empty.
- Text entry → plain paragraph (body only).
- Thread link (entry.threadId != null) → trailing line `⤷ <thread title>`
  (small/em in HTML). Unknown thread id → `(closed thread)`, matching the
  journal screen's fallback.
- HTML must escape user text (&, <, >, ", ') EVERYWHERE it interpolates.
- HTML is one self-contained file: inline `<style>` — clean, print-friendly,
  light background, serif body, system fallback fonts, max-width ~42rem
  centered, h2 with a subtle rule. No external resources.
- Empty journal → header only plus an "(empty journal)" line.

---

### Task 1: Pure exporter (TDD)

**Files:**
- Create: `lib/engine/journal_export.dart`
- Test: `test/journal_export_test.dart`

API (binding):

```dart
String journalToMarkdown({
  required String campaignName,
  required List<JournalEntry> entriesNewestFirst,
  required Map<String, String> threadTitles, // id -> title
  required DateTime exportedAt,
});

String journalToHtml({ /* same parameters */ });
```

- [ ] **Step 1: failing tests.** Cover, for BOTH formats where applicable:
  ordering (two entries, newest-first input → oldest appears first in
  output); scene heading with and without chaos; result title+body; text
  paragraph; thread suffix incl. unknown-id fallback; empty journal; HTML
  escaping (entry body `<b>"x" & 'y'</b>` appears escaped, never raw);
  HTML self-containment (contains `<style>`, no `http`/`https` substrings);
  markdown header contains campaign name and `Exported 2026-06-12` for a
  fixed exportedAt.

- [ ] **Step 2: implement.** Pure Dart (`dart:core` only). Keep the two
  renderers sharing one walk over the reversed list (small private helper
  emitting per-entry parts per format is fine; don't over-abstract).

- [ ] **Step 3: gates + commit.**

```bash
git add lib/engine/journal_export.dart test/journal_export_test.dart
git commit -m "feat: journal exporter — markdown + self-contained HTML renderers"
```

---

### Task 2: Journal screen export action

**Files:**
- Modify: `lib/features/journal_screen.dart` (the row with the Clear button, ~line 86-96)
- Test: `test/journal_export_ui_test.dart`

- [ ] **Step 1: failing widget test.** Pump JournalScreen with a seeded
  journal (reuse the mock-prefs pattern from test/journal_interpret_test.dart).
  Tapping `Key('journal-export')` opens a dialog offering
  `Key('export-markdown')` and `Key('export-html')`. Choosing one calls the
  save seam (below) with a filename ending `.md` / `.html` whose content
  contains a known entry title. Empty journal → export button absent (or
  disabled — pick absent, matches the buttons-hidden-when-empty house
  choice).

  Seam for testability: `FilePicker.saveFile` is static and untestable.
  Mirror what the repo already does for campaign export tests — read how
  test/campaign_io_test.dart / any home_shell test handle it. If (as
  expected) the campaign export save itself is untested glue, do the same
  here BUT keep the glue 3 lines: put the dialog + content-building in a
  testable method that RETURNS the (fileName, content, format) it would
  save, and have the tap handler pass that to a `Future<void> Function(String fileName, List<int> bytes)`
  field that defaults to FilePicker.saveFile and is overridable in tests
  via a visible-for-testing static. Simplest mechanism that lets the test
  assert content; copy the established pattern if one exists.

- [ ] **Step 2: implement.** Icon button (Icons.ios_share or
  Icons.download_outlined, tooltip 'Export journal…',
  `Key('journal-export')`) next to Clear, shown only when entries
  non-empty. Dialog: 'Export journal' with two FilledButton.tonal options
  (Markdown / HTML). On choice: build via the Task-1 exporter with
  `DateTime.now()`, threads from threadsProvider (ALL threads incl.
  closed — export must resolve closed-thread titles too; check what
  threadsProvider holds and whether closed threads remain in the list —
  they do, `open` is a flag), filename `<campaign-slug>-journal.md|.html`
  (reuse the slug logic shape from home_shell.dart:140-142), save via
  FilePicker.saveFile with PlatformException → snackbar, exactly like
  campaign export.

- [ ] **Step 3: gates + commit.**

```bash
git add lib/features/journal_screen.dart test/journal_export_ui_test.dart
git commit -m "feat: export journal as markdown or styled HTML from the journal screen"
```

---

### Task 3: Docs

- [ ] README: one sentence in the journal feature area: journals export as
  Markdown or a styled standalone HTML page. Full gates (`flutter test`,
  analyze 1 info, `flutter build web`).

```bash
git add README.md
git commit -m "docs: journal export feature note"
```

---

## Verification (controller)

Browser: seeded journal → export button → choose HTML → file lands in
~/Downloads (web save = browser download); open it, check styling +
content + escaping. Same for Markdown. Then PR → CI → squash-merge →
roadmap row B done.
