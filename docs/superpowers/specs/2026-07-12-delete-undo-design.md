# Delete-undo snackbars — design

**Date:** 2026-07-12
**Source:** stranger-test S10 ("a mis-tap on ✕ deletes with only a tooltip")
+ the QoL assessment: destructive taps had no safety net anywhere.

## Design

Deleting stays one tap — no confirm dialogs — but every user-facing delete now
shows a 5-second SnackBar with an **Undo** action:

- **Primitive:** `_PersistedList<T>.restoreAt(int index, T item)`
  (`lib/state/providers.dart`) re-inserts a captured row at its old index
  (clamped). Works for every list notifier (journal, threads, characters,
  rumors, places, NPCs, tracks) since all of them persist plain ordered lists.
  `DismissedSuggestionsNotifier.undismiss(key)` is the set-shaped equivalent
  for the tracking-chip ✕.
- **Helper:** `showUndoSnackbar(context, message, onUndo)`
  (`lib/shared/undo_snackbar.dart`) — hides any current snackbar, shows the
  message + Undo.
- **Call sites:** journal entry / scene delete (`journal_screen.dart` popup
  'delete'), tracking-chip dismiss (same file), thread + character delete
  (`tracker_screen.dart`), rumor (`rumors_pane.dart`), place
  (`places_pane.dart`), NPC (`people_pane.dart`), progress track
  (`tracks_pane.dart`). Each captures the item + its index before removing.

Scenes have no separate delete surface (a scene is a journal entry), so the
journal path covers them. Inline character stat/track row removals inside the
edit dialog are out of scope (micro-edits within an already-open editor).

## Tests

`test/delete_undo_test.dart`: restoreAt ordering + clamping, undismiss, and a
TracksPane widget test driving delete → snackbar → Undo → restored.
