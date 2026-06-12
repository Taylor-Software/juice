# Cycle 3 Item D: Journal-Aware Interpreter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The interpreter remembers your campaign: when interpreting a result, the 2-3 most relevant past journal entries ride along in the prompt as `recall:` lines, so readings can reference established NPCs, places, and threads. This is the spec's designed RAG hook (`OracleSeed.sceneContext` doc comment) and the differentiator no competitor ships — cloud AI GMs all admit memory drift; ours retrieves deterministically from the player's own journal, on device.

**Architecture:** Pure-Dart relevance ranking in `lib/engine/journal_search.dart` (term-overlap scoring with tag boost + recency tiebreak — no embeddings, deterministic, testable). `OracleSeed` gains a `journalContext` list; `buildOraclePrompt` emits `recall:` lines; one new system-instruction rule. Journal screen builds the context at Interpret time; the sheet passes it through.

**Token budget (hard constraint):** the web model is only proven at 1280
total tokens in the fallback path. System instruction ≈700, output ≈250.
Recall block is therefore capped at **2 entries, each truncated to 100
characters** (≈70 tokens worst case). These caps are constants in the
engine, asserted by tests.

**Branch:** `feat/journal-aware-interpreter` off `main`.

Hard rules: analyze exactly 1 pre-existing info (lib/engine/models.dart:2); suite green (currently 325); TDD; exact commit messages, no co-author lines; engine files stay pure Dart.

---

### Task 1: Relevance ranking — `relatedEntries`

**Files:**
- Modify: `lib/engine/journal_search.dart`
- Test: extend `test/journal_search_test.dart`

Binding API (append to journal_search.dart):

```dart
/// The [limit] entries most relevant to [target], for interpreter recall.
/// Deterministic term-overlap ranking — no embeddings:
/// - Terms: lowercase alphanumeric words of length >= 3 from the target's
///   title + body + tags, minus stopwords (small built-in english list).
/// - Score: +1 per distinct shared term in an entry's title/body,
///   +3 per shared tag (tags are curated signal).
/// - Excludes [target] itself (by id) and scene entries (they're headers,
///   not content). Score 0 entries are dropped.
/// - Ties break toward the more recent timestamp.
List<JournalEntry> relatedEntries(
  List<JournalEntry> entries,
  JournalEntry target, {
  int limit = 2,
});
```

Stopword list: keep it tiny and boring — `the a an and or of to in on at
is was are it its with for…` (~25 words, const set). Don't over-engineer.

- [ ] **Step 1: failing tests.** Shared-term scoring (entry sharing 2 terms
  outranks 1); tag match outweighs two body terms (+3 vs +2); target
  excluded by id; scene entries excluded as candidates; zero-score dropped
  (unrelated entry absent even under limit); recency tiebreak; limit
  respected; stopwords/short words don't match ('the', 'of', 'an' in both
  → score 0); deterministic order on repeat calls.

- [ ] **Step 2: implement.** Pure Dart.

- [ ] **Step 3: gates + commit.**

```bash
git add lib/engine/journal_search.dart test/journal_search_test.dart
git commit -m "feat: relatedEntries — deterministic term-overlap ranking for interpreter recall"
```

---

### Task 2: Engine — recall in seed + prompt

**Files:**
- Modify: `lib/engine/oracle_interpreter.dart`
- Test: extend `test/oracle_interpreter_test.dart`

- [ ] **Step 1: failing tests.**
  - `OracleSeed` accepts `journalContext: ['a', 'b']` (default const []).
  - Prompt with context contains, between the `result:` and `scene:` lines:
    `recall: a` and `recall: b` (one line each, in order).
  - Each recall line is truncated to 100 chars (a 300-char context string
    renders as 100 chars + '…'); at most 2 recall lines render even if more
    are passed (engine-side enforcement of the token budget).
  - No context → no `recall:` line anywhere (existing prompt goldens stay
    green).
  - Recall strings are whitespace-flattened like the other fields.
  - System instruction mentions `recall` (new rule line).

- [ ] **Step 2: implement.**
  - `OracleSeed.journalContext` (`List<String>`, default const []).
  - Constants: `kRecallMaxEntries = 2`, `kRecallMaxChars = 100` with a
    comment citing the 1280-token web budget.
  - `buildOraclePrompt`: after the `result:` line, for each of the first
    `kRecallMaxEntries` context strings: flatten whitespace, truncate to
    `kRecallMaxChars` (append '…' when cut), emit `recall: <text>`.
  - System instruction, one added rule line (keep it short — every token
    counts):
    `- recall: lines are excerpts from the player's earlier journal. Treat them as established facts; weave them in when they fit.`

- [ ] **Step 3: gates + commit.**

```bash
git add lib/engine/oracle_interpreter.dart test/oracle_interpreter_test.dart
git commit -m "feat: recall lines in the interpreter prompt (capped for the web token budget)"
```

---

### Task 3: Wiring — journal builds recall, sheet passes it through

**Files:**
- Modify: `lib/features/journal_screen.dart` (`_interpret`, ~line 360)
- Modify: `lib/features/oracle_interpretation_sheet.dart` (`_generate`'s seed reconstruction)
- Test: extend `test/journal_interpret_test.dart` (and the fake if needed — it already records `lastSeed`)

- [ ] **Step 1: failing tests.**
  - Journal test: journal seeded with the target result entry plus an older
    result entry sharing a distinctive word (e.g. 'Magistrate') and an
    unrelated entry. Interpret → accept; assert
    `fake.lastSeed!.journalContext` has the related entry's text (formatted
    `'title — body'` or `'body'` when title empty) and NOT the unrelated
    one, and not the target's own text.
  - Sheet passthrough test (in test/oracle_interpretation_sheet_test.dart):
    a seed with `journalContext: ['x']` reaches the fake's `lastSeed`
    unchanged after generation (the sheet's seed reconstruction must carry
    it).

- [ ] **Step 2: implement.**
  - `journal_screen._interpret`: before building the seed,
    `final related = relatedEntries(entries, entry);` (entries from
    `journalProvider`), format each as `title — body` (title empty → body
    alone), pass as `journalContext`.
  - Sheet `_generate`: add `journalContext: widget.seed.journalContext` to
    the reconstructed `OracleSeed`.

- [ ] **Step 3: gates + commit.**

```bash
git add lib/features/journal_screen.dart lib/features/oracle_interpretation_sheet.dart test/journal_interpret_test.dart test/oracle_interpretation_sheet_test.dart
git commit -m "feat: interpreter recall — related journal entries ride into the prompt"
```

---

### Task 4: Docs

- [ ] README interpreter bullet: one sentence — readings can draw on the
  most relevant earlier journal entries, retrieved on device. CLAUDE.md: no
  change needed (no new rails). Spec: append one line to the design spec's
  Architecture §1 noting the hook is now implemented (D, PR pending).
  Full gates: `flutter test`, analyze 1 info, `flutter build web`.

```bash
git add README.md docs/superpowers/specs/2026-06-11-oracle-interpreter-design.md
git commit -m "docs: journal-aware interpreter notes"
```

---

## Verification (controller)

Browser (model cached on the localhost:8765 origin): seed a journal where
an older entry establishes a fact ('the Magistrate sealed the mill'), then
Interpret a related result — confirm a generation completes (no token
overflow on either maxTokens path) and judge whether readings pick up the
recalled fact. PR → CI → squash-merge → roadmap row D done → cycle 3
closeout.
