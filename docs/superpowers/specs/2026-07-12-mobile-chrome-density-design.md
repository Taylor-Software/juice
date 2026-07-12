# Mobile chrome density + HUD de-noising — design

**Date:** 2026-07-12
**Source:** tool-evaluation audit F4 (HUD dead chrome) + F5 (mobile Play drowns
the journal) — `docs/superpowers/audits/2026-07-11-tool-evaluation-audit.md`.

## Problem

At 375×812 the campaign header + loop bar + assistant rail consume most of the
viewport before any journal content, and the always-visible "Light: out" chip +
steppers read as negative noise on every campaign that never tracks light.

## Design

One compact breakpoint, `kCompactWidth = 600` (`lib/shared/design_tokens.dart`,
the Material compact width), drives four behaviors:

1. **Rail defaults by viewport.** `assistantRailExpandedProvider` becomes
   `bool?` — null means "user never toggled", and the rail picks its default
   from the viewport (open on wide screens where chips are the new-user
   on-ramp, collapsed on phones where the journal needs the space). A user
   toggle persists and wins on every device size.
2. **Chrome never stacks on phones.** On compact widths, expanding the loop
   bar collapses the assistant rail and vice versa — both sit above the same
   already-short journal.
3. **Typing collapses chrome.** An ephemeral (never persisted)
   `journalComposerFocusProvider` mirrors composer focus; while set on a
   compact viewport the loop bar, rail, and the header's expanded row render
   collapsed — the on-screen keyboard plus chrome can't squeeze the entry list
   to nothing mid-typing. The persisted expand settings are untouched; the
   chrome returns on blur. The flag is cleared post-frame from `deactivate`
   (Riverpod forbids `ref` in `dispose`, and a synchronous write there would
   `markNeedsBuild` the shell header mid-finalization).
4. **Header row scrolls, not wraps, on phones.** The expanded tier-2 control
   row becomes a single horizontally-scrolling line under `kCompactWidth`, so
   pinned threads + starred characters can't stack the header several rows
   deep.

**HUD de-noising (F4):** the Light chip + steppers show only while a timer is
running (`light > 0`). An idle campaign gets a single muted "Light" start chip
at the end of the expanded row (`hdr-light-start`, sets the timer to 1). Chaos
is not duplicated — the value lives in the always-visible tier-1 chip, the
expanded row carries only the steppers.

## Tests

`test/campaign_header_test.dart` covers the idle-start-chip ↔ lit-steppers
transition; existing loop-bar/rail/journal suites cover the expand defaults.
Phone-feel (keyboard collapse, one-line scroll) is device-verified.

## Non-goals

Swipe gestures, haptics, and dock-chip overflow are the separate mobile
ergonomics follow-up.
