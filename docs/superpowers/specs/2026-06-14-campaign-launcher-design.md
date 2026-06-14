# Campaign Launcher — Design

**Date:** 2026-06-14
**Status:** Approved (brainstorm) — ready for implementation plans
**Depends on:** the existing `SessionsNotifier` (create/switchTo/remove/importCampaign/editSystems),
`settingsProvider` (genre/tone), `app.dart` boot, the no-router state-driven shell.

## Goal

A **startup campaign launcher** — the first screen on every cold start — that lets the player
**Continue** the active campaign, **switch** to another, start a **New** one (with systems +
genre/tone), **Load** one from a file, and **Rename**/**Delete** campaigns. It fulfils the original
ask: "a starting dialog… a menu for campaigns: continue, new, load… new goes to campaign settings…
ultimately landing on the journal."

The launcher is almost entirely a presentation layer over existing `SessionsNotifier` APIs; the only
new back-end is a `rename` method and a small genre/tone seed on `create`.

## Decisions (settled in brainstorm)

- **Shows on every cold start** — the main menu. **Continue** is the prominent default (one tap to
  resume the active campaign).
- **New-campaign form collects** name + system toggles (grouped) + optional **genre** and **tone**.
- **Full management** in the launcher: switch / new / load-from-file / **rename** / **delete**.

## Gate mechanism (no router)

A transient in-memory gate, NOT persisted (so it resets to shown each process launch):

```dart
class LauncherGateNotifier extends Notifier<bool> {
  @override
  bool build() => true;              // shown on every cold start
  void dismiss() => state = false;   // any launcher action -> enter the journal
}
final launcherGateProvider =
    NotifierProvider<LauncherGateNotifier, bool>(LauncherGateNotifier.new);
```

In `app.dart`, the resolved-oracle branch chooses the launcher vs the shell:

```dart
data: (o) => ref.watch(launcherGateProvider)
    ? const LauncherScreen()
    : HomeShell(oracle: o),
```

`LauncherScreen` watches `sessionsProvider`; every entry action calls
`ref.read(launcherGateProvider.notifier).dismiss()` last, which rebuilds `app.dart` into
`HomeShell` (journal). Because the gate is in-memory, the next app launch shows the launcher again.

## LauncherScreen

A full-screen `Scaffold` (app title/branding header), gated behind the loaded `sessionsProvider`:

- **Continue** — a prominent primary button labelled with the active campaign's name
  (`Continue · <name>`); `onPressed` → `dismiss()`. (The active session always exists — the boot
  migration guarantees ≥1.)
- **Campaign list** — every `SessionMeta` (active marked). Tapping a non-active row →
  `await switchTo(id)` then `dismiss()`. Each row carries **Rename** and **Delete** affordances
  (Delete disabled/hidden when only one campaign remains).
- **New campaign** → opens the new-campaign form (below); on submit → `create(...)` then `dismiss()`.
- **Import from file** → `FilePicker.pickFiles` (json) → `importCampaign(content)` → `dismiss()`
  (mirrors the existing `_importCampaign` in `home_shell.dart`; on `FormatException`, a SnackBar).

The screen lives in a new `lib/features/launcher_screen.dart`. It honours the loose-constraint
rules (no non-flex Material buttons under unbounded width; lists in a bounded `ListView`).

## New-campaign form (with genre/tone)

A dialog (or inline form) collecting: **name** (required), the **system toggles** grouped as
**Default systems** (juice/mythic/ironsworn/party/verdant, all on) vs **Add-ons** (lonelog/hexcrawl,
off), and optional **genre** + **tone** text fields (hints `e.g. grimdark fantasy` / `e.g. tense and
dangerous`). It is the existing `_NewCampaignDialog` content plus the two text fields; returns
`({String name, Set<String> systems, String genre, String tone})`.

To avoid the settings-provider cascade-timing hazard (`SettingsNotifier._scopedKey` follows the
active session, which `create` has just changed), **`create` seeds genre/tone directly** rather than
the launcher saving them post-switch:

```dart
Future<void> create(String name,
    {Set<String>? systems, String genre = '', String tone = ''}) async {
  final s = state.valueOrNull;
  if (s == null) return;
  final meta = SessionMeta(id: _newId(), name: name, systems: systems?.toList());
  if (genre.isNotEmpty || tone.isNotEmpty) {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('juice.settings.v1.${meta.id}',
        jsonEncode(CampaignSettings(genre: genre, tone: tone).toJson()));
  }
  await _save(SessionsState(active: meta.id, sessions: [...s.sessions, meta]));
}
```

(The added params are optional → existing callers are unaffected.)

## Rename (new API)

The only missing `SessionsNotifier` method:

```dart
/// Rename session [id]; no-op for unknown ids or a blank name.
Future<void> rename(String id, String name) async {
  final s = state.valueOrNull;
  if (s == null || name.trim().isEmpty) return;
  final updated = [
    for (final m in s.sessions)
      if (m.id == id)
        SessionMeta(id: m.id, name: name.trim(), systems: m.systems)
      else
        m,
  ];
  await _save(SessionsState(active: s.active, sessions: updated));
}
```

A simple single-field rename dialog in the launcher invokes it. (Delete reuses the existing
`remove(id)`, which already keeps ≥1 and reassigns `active` to `remaining.first` when the active
campaign is deleted.)

## Slices (each its own plan → PR, independently shippable)

- **L1 — Gate + LauncherScreen (enter flows).** `launcherGateProvider`, `app.dart` gate,
  `LauncherScreen` with **Continue**, **switch-to-existing**, and **Import from file**. A usable
  startup menu over existing APIs; no new SessionsNotifier methods. (New campaign in L1 falls back to
  the existing `_NewCampaignDialog`-style create with name+systems, wired through the launcher.)
- **L2 — Manage flows.** `create` genre/tone seed + the enriched new-campaign form (genre/tone),
  the new `rename` method + rename dialog, and **Delete** in the launcher list.

## Coexistence

The in-journal `folder_copy` Campaigns dialog (`_showSessions`) stays as-is for mid-session
switching/edit/export/import. The launcher is the startup gate. (Unifying the two is out of scope.)

## Testing

- `LauncherGateNotifier`: defaults `true`; `dismiss()` → `false`.
- `SessionsNotifier.rename`: renames the target, no-ops on unknown id / blank name, leaves `active`
  and other sessions untouched.
- `create` genre/tone seed: a campaign created with genre/tone writes the new session's
  `juice.settings.v1.<id>` so its `settingsProvider` reads them back; created without them writes no
  settings key.
- `LauncherScreen` widget tests **in isolation** (override `sessionsProvider` with a fixed
  `_FixedSessions`, plus the gate; per the rootBundle-hang rule, do NOT pump `HomeShell`): Continue
  shows the active name and dismisses the gate; tapping another campaign calls `switchTo` + dismisses;
  New opens the form; Rename/Delete invoke the right methods; Import is present. Assert the gate flips
  via a `launcherGateProvider` listener rather than rendering the shell.

## Files

**New:** `lib/features/launcher_screen.dart`, `test/launcher_screen_test.dart`,
`test/launcher_gate_test.dart` (+ `test/sessions_rename_test.dart` for the notifier).
**Edit:** `lib/app.dart` (the gate branch), `lib/state/providers.dart` (`launcherGateProvider`,
`rename`, `create` genre/tone seed). Possibly extract the system-checkbox group from
`_NewCampaignDialog` for reuse, or duplicate the minimal form in the launcher.

## Asserted calls (veto)

- **In-memory gate** (not persisted) → "every cold start"; dismiss is one tap.
- **Full-screen launcher** chosen over a boot dialog (cleaner main-menu feel; no modal-over-canvas).
- **`create` seeds genre/tone** (avoids the settings cascade-timing hazard) rather than a post-switch
  save.
- **Reuse `remove`** for delete (already reassigns active + keeps ≥1).
- The existing `folder_copy` dialog is left untouched (no unification this pass).

## Out of scope

- Persisted "skip launcher / auto-continue" preference (could be added later).
- Per-campaign timestamps / recency sorting (list-order is fine; Continue = the active session).
- Unifying the in-journal Campaigns dialog with the launcher.
- Onboarding/tutorial content on the launcher.
