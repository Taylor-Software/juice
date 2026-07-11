# Persistence Hardening — design

**Date:** 2026-07-11
**Source:** tool-evaluation audit F3
(`docs/superpowers/audits/2026-07-11-tool-evaluation-audit.md`).

## Problem

Most persisted-state notifiers parse `fromJson(jsonDecode(raw))` unguarded.
One corrupt SharedPreferences value (partial write on app kill, manual edit,
a future migration bug) throws inside `build()`, leaving the provider in
permanent `AsyncError`. The app-wide `valueOrNull ?? default` read
convention renders that as a silently empty screen — and for
`sessionsProvider` (the master registry every session-scoped provider
depends on) a bricked app with no signal and no recovery path.

Separately, `DismissedSuggestionsNotifier` (`juice.suggestDismissed`) and
`RecapCacheNotifier` (`juice.recap`) build session-scoped keys that are NOT
registered in `sessionScopedKeys`, so campaign deletion orphans their data
and legacy migration / export skips them.

## Design

Corrupt user-persisted storage degrades to the empty/default state instead
of erroring; corrupt rows inside a persisted list are skipped so one bad
entry can't take out the rest.

- Two shared helpers in `lib/state/providers.dart`:
  - `decodePersisted<T>(raw, decode, fallback)` — try/catch around
    `decode(jsonDecode(raw))`, returning `fallback` on any throw.
  - `decodePersistedList<T>(raw, fromJson)` — tolerant outer decode +
    per-row try/catch (skip bad rows).
- Applied to every **user-persisted** read: `_PersistedList.build`
  (journal/threads/characters/places/npcs/rumors/tracks/inventory/units),
  crawl, decks, dungeon factions, encounter, map, campaign settings,
  rulesets, bestiary, custom tables, constructed oracles, user ref cards,
  plus `PlayContext` (`play_context.dart`), `GmChatState` (`gm_chat.dart`),
  and `VerdantJourney` (`verdant.dart`).
- `SessionsNotifier.build()`: a corrupt registry falls through to the
  existing first-run path (fresh `default` registry) instead of
  `AsyncError`-ing the whole app.
- **Bundled-asset loads stay strict** (`oracle_data`, `ruleset_*`, etc.) —
  those are build-script-verified; a parse failure there is a programming
  error worth surfacing loudly, and content files (`foes_*`/`spells_*`)
  already have their own tolerant paths.
- **Campaign import stays strict** — `campaign_io.dart` deliberately throws
  `FormatException` so the import UI can report a bad file.
- Register `juice.suggestDismissed` + `juice.recap` in `sessionScopedKeys`
  (cleanup on delete, legacy migration, export/import). Their payloads are
  small caches; riding the campaign file is harmless.

## Success criteria

- Seeding garbage into any hardened key yields the default state (no
  `AsyncError`), verified by a new test sweeping representative providers —
  including a corrupt sessions registry recovering to a fresh `default`.
- A persisted list with one corrupt row keeps its other rows.
- Deleting a campaign purges its `suggestDismissed`/`recap` keys.
- Full suite stays green.
