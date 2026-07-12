# Mobile ergonomics — swipe actions, roll haptics, phone-width guard

**Date:** 2026-07-12
**Source:** QoL assessment #5 (follow-on to the mobile chrome density work).

## Changes

1. **Swipe actions on journal entries (phones only).** Under `kCompactWidth`
   each entry tile wraps in a `Dismissible`: swipe right opens the existing
   Edit dialog (`confirmDismiss` returns false — nothing dismissed), swipe
   left deletes through the same `_onAction('delete')` path, so it gets the
   standard Undo snackbar. Desktop keeps the popup menu only — mouse-drag
   deletes are too easy to trigger accidentally.
2. **Roll haptics.** `hapticRoll()` (`lib/shared/haptics.dart`) —
   `HapticFeedback.lightImpact` on Android/iOS, no-op elsewhere — fires on
   dice-roller rolls, inline dock rolls, and the HUD quick roll.
3. **Phone-width guard.** `journal_outer_overflow_ui_test.dart` gains a
   375×812 case pinning that the dock + composer + suggestion row fit the
   wedge form factor without overflow (they do post-#287).

## Tests

`test/journal_swipe_test.dart`: swipe-left delete + Undo restore, swipe-right
edit (nothing deleted), desktop width not dismissible. Haptics are a no-op in
tests (device-verified feel).
