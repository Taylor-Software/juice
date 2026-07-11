# Persistence Hardening — plan

Spec: `docs/superpowers/specs/2026-07-11-persistence-hardening-design.md`

1. `lib/state/providers.dart`: add `decodePersisted` /
   `decodePersistedList`; convert `_PersistedList.build`, crawl, decks,
   factions, encounter, map, settings, rulesets, bestiary, custom tables,
   oracles, ref cards; sessions falls through to first-run on corrupt
   registry; add the two missing keys to `sessionScopedKeys`.
2. Inline try/catch fallbacks in `lib/state/play_context.dart`,
   `lib/state/gm_chat.dart`, `lib/state/verdant.dart`.
3. New `test/persistence_tolerance_test.dart`: corrupt-raw sweep across
   representative providers, per-row list recovery, sessions-registry
   recovery, key-registration assertions.
4. `flutter analyze` + full suite; ship via `/ship-pr`, squash-merge;
   CLAUDE.md persistence bullet note.
