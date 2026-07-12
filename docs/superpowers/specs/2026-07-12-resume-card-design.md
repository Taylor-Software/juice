# "Previously on…" resume card — design

**Date:** 2026-07-12
**Source:** QoL assessment #3 — solo campaigns die between sessions because
re-entry costs are high; the old recap banner was AI-only and content-free
("Returning to this campaign? [Recap]").

## Design

The journal's recap banner becomes a deterministic resume card, shown under
the same eligibility rules as before (arrived with ≥5 entries, newest entry
not yet seen, not opted out via Never):

- **Content for everyone:** pure `resumeLines(entriesNewestFirst)`
  (`lib/engine/resume.dart`) — the latest scene title plus up to 3 one-line
  snippets of the newest entries ("Title — body", mentions flattened,
  96-char cap), oldest of the set first so it reads chronologically.
- **AI stays optional:** the Recap action (and AI badge) render only when
  the interpreter is ready (`_canVoice`); the card itself no longer gates on
  it — web and AI-off users get the deterministic recap.
- Dismiss (marks newest seen) and Never (permanent opt-out) are unchanged.

## Tests

`test/resume_test.dart` (pure): scene pick, chronological snippet order,
sketch/empty skipping, truncation, mention flattening. `test/recap_test.dart`
updated: unsupported-model now expects the card WITHOUT the `recap-action`.
