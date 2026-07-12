# Desktop keyboard shortcuts — design

**Date:** 2026-07-12
**Source:** QoL assessment #6 — the composer has slash commands but no global
keyboard shortcuts; desktop is where long journaling sessions happen.

## Bindings

All are modifier combos (safe while typing — text fields don't consume them),
each bound for both meta (macOS) and control (Windows/Linux):

| Combo | Action | Scope |
|---|---|---|
| Cmd/Ctrl+K | Campaign search sheet | Shell (everywhere) |
| Cmd/Ctrl+R | Quick-roll the default oracle | Shell (everywhere) |
| Cmd/Ctrl+Enter | Log the composer | Journal subtree |
| Cmd/Ctrl+Shift+N | New-scene dialog | Journal subtree |

## Implementation

- Shell: `CallbackShortcuts` + `Focus(autofocus: true)` wrapping the body
  column in `home_shell.dart` — the autofocus node gives the shell focus
  before any field is focused, so shortcuts work immediately.
- Quick roll reuses the HUD button's exact path via the new
  `CampaignHeader.quickRollDefault(context, ref)` (draw-style oracles open
  the roll sheet; yes/no oracles roll + log instantly). On web Cmd+R stays
  the browser reload — the binding simply never fires there.
- Journal: a `CallbackShortcuts` wrapper inside `JournalScreen.build` binds
  send + new-scene; fires while focus is inside the journal (composer).

## Tests

`test/keyboard_shortcuts_test.dart`: Cmd+Enter logs, Cmd+Shift+N opens the
dialog, Cmd+K opens search from the full HomeShell.
