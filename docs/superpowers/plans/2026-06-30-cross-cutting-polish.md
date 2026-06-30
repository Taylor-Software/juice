# Cross-cutting polish batch

Four cheap, independent wins from the 2026-06-30 audit, one PR. No model/persistence
schema changes except one new app-global bool flag (mirrors `aiNudgeSeenProvider`).

## Task 1 — AI rank-churn fix (`lib/features/assistant_rail.dart`)
`_signature` keys on `journal.first.id`, so the rail queues a fresh `rankSuggestions`
LLM call on EVERY new journal entry (capture notes, rolls, narration). Coarsen the
invalidation: replace `final top = journal.isEmpty ? '' : journal.first.id;` with the
id of the newest entry whose `kind` is `JournalKind.scene` or `JournalKind.result`
(the semantically meaningful state changes), falling back to `''` when none:
```dart
final top = journal
    .firstWhere(
      (e) => e.kind == JournalKind.scene || e.kind == JournalKind.result,
      orElse: () => /* sentinel */,
    ) ...
```
Use a null-safe lookup instead (no sentinel): e.g.
`final meaningful = journal.where((e) => e.kind == JournalKind.scene || e.kind ==
JournalKind.result).firstOrNull; final top = meaningful?.id ?? '';`
(Journal is newest-first, so `.firstOrNull` is the newest such entry.) Keep the rest
of the signature (scene + candidate ids) unchanged. Confirm `JournalKind` import +
the enum values exist.

## Task 2 — GM chat "Clear" (`lib/features/gm_chat_screen.dart`)
`GmChatNotifier.clear()` already exists (providers.dart:191). Add an app-bar
`IconButton` (key `gm-chat-clear`, `Icons.delete_sweep_outlined`, tooltip "Clear
chat") that shows a confirm dialog ("Clear this GM conversation?" Cancel/Clear) →
`ref.read(gmChatProvider.notifier).clear()` + a "Chat cleared" snackbar. Only show
it when the chat is non-empty. Read the screen first for its exact provider name +
app-bar structure.

## Task 3 — Track orientation card (`lib/features/track_home_pane.dart`)
Add a dismissible "What's here" card at the TOP of `TrackHomePane` explaining the
Track subtabs in one line each (Loop = guided solo play; Tasks = tally-tracked goals;
Scenes = beats; Threads = open storylines; Encounter = combat; Rumors = leads;
Tracks = clocks). Dismiss persists via a NEW app-global bool flag
`trackHelpSeenProvider` (`juice.track_help_seen.v1`) — copy the `WelcomeSeenNotifier`/
`welcomeSeenProvider` pattern verbatim (providers.dart:1451) including the AsyncNotifier
+ `markSeen()`. Card hidden when seen. Keys: `track-help-card`, `track-help-dismiss`.
Read track_home_pane.dart first to slot the card above the existing cards.

## Task 4 — Recap banner "Never" opt-out (`lib/features/journal_screen.dart`)
The recap banner (~lines 440-487, shows when `entries.length >= 5 && cache?.lastSeenId
!= entries.first.id`) reappears every session. Add a third action "Never" (key
`recap-never`) beside the existing dismiss that sets a NEW app-global bool flag
`recapSuppressedProvider` (`juice.recap_suppressed.v1`, same `WelcomeSeenNotifier`
pattern). Gate the whole banner on `!recapSuppressed`. Read the banner block first.

## Task 5 — Tests + verify
Add focused tests where cheap:
- `assistant_rail` signature: not directly unit-testable without the widget; instead
  add a tiny pure-ish test only if a seam exists — otherwise rely on the full suite +
  a manual note. (Do NOT over-engineer; the change is a one-liner.)
- provider tests for `trackHelpSeenProvider` + `recapSuppressedProvider` round-trip
  (mirror existing `welcomeSeenProvider` test if one exists).
- widget test: `gm-chat-clear` clears the transcript; `track-help-dismiss` hides the
  card + persists; `recap-never` hides the banner + persists. Add these where the
  existing test files for those screens make it cheap; skip a surface if its harness
  is heavy (note which you skipped and why).
- `flutter analyze` clean; full `flutter test` green.

## Out of scope
- A general settings screen for these toggles (each is a one-shot dismiss).
- Re-showing dismissed help/recap (no un-dismiss UI).
