# SRD edition feature — PR2 of 2

Adds a per-campaign D&D edition preference (5.1 vs 5.2) + a Reference edition
filter, so the now-merged 5.1+5.2 content (PR #233) shows ONE edition at a time (no
duplicate Fireball). All three content surfaces — Reference view, the D&D caster
sheet spell picker, the encounter monster picker — read `contentSpellsProvider` /
`contentMonstersProvider`, so filtering those two providers covers everything.

## Task 1 — `SessionMeta.dndEdition` (lib/engine/models.dart)
Add `final String? dndEdition;` to `SessionMeta` (~line 4293). Thread through:
- const ctor param `this.dndEdition`,
- `toJson`: `if (dndEdition != null) 'dndEdition': dndEdition`,
- `copyWith`: add `String? dndEdition` param + `dndEdition: dndEdition ?? this.dndEdition`,
- `fromJson`: `dndEdition: j['dndEdition'] as String?`.
Null = use the latest ('5.2'). Don't add a non-null default to the field (keeps
JSON compact + back-compat).

## Task 2 — provider + persistence (lib/state/providers.dart)
- `final dndEditionProvider = Provider<String>((ref) => ref.watch(sessionsProvider)
  .valueOrNull?.activeMeta.dndEdition ?? '5.2');`
- `SessionsNotifier.setDndEdition(String edition)` — set on the ACTIVE meta via its
  `copyWith` + persist (mirror how `setMode`/`editSystems` update the active meta;
  check the existing pattern — they take an id or act on active). Match whichever
  signature the siblings use.
- Filter the two aggregators: in `contentMonstersProvider` and
  `contentSpellsProvider`, watch `dndEditionProvider` and drop edition-tagged
  entries that don't match: keep `e.edition == null || e.edition == ed`. (Only D&D
  entries carry an edition today, so other systems are unaffected.) Apply the filter
  to the final returned list.

## Task 3 — Reference edition toggle (lib/features/reference_view.dart)
Add a small `SegmentedButton<String>` (key `reference-edition`, segments
"5.1"/"5.2") in the ReferenceView header, shown ONLY when D&D content is enabled
(`ref.watch(enabledContentSystemsProvider).contains('dnd')`). Selected =
`ref.watch(dndEditionProvider)`; onChange → `ref.read(sessionsProvider.notifier)
.setDndEdition(v)`. Keep it loose-constraint-safe (Flexible / bounded, not a bare
button in an unbounded Row). Don't disturb the existing All/Monsters/Spells/Rules
SegmentedButton.

## Task 4 — Tests + docs + verify
- Provider test: seed a campaign, assert `contentSpellsProvider` with edition 5.2
  (default) contains a `dnd-2024-*` spell and NO `5.1` dnd spell; `setDndEdition('5.1')`
  flips it (5.1 present, no `5.2`). Same shape for `contentMonstersProvider`. Other
  systems' entries (if any seeded) are unaffected. (Override the asset-loading
  providers or use the real assets like `dnd52_content_test`; keep it light — no
  widget pump unless needed for the toggle test.)
- SessionMeta round-trip test: `dndEdition` survives toJson/fromJson + copyWith.
- Widget test (if cheap in the existing reference test harness, else skip w/ note):
  `reference-edition` toggle flips the visible content + persists.
- CLAUDE.md: update the content-library bullet — note SRD 5.2 shipped + the
  per-campaign edition preference (`SessionMeta.dndEdition`, `dndEditionProvider`,
  `reference-edition` toggle); move SRD 5.2 out of the "deferred/blocked" wording.
- `flutter analyze` clean; full `flutter test` green.

## Known edge (acceptable, note in PR)
A D&D sheet that attached a spell id from one edition (e.g. `dnd-2024-fireball`)
then switches edition won't resolve that id (it's filtered out) — the spell just
won't render. The "N spells unavailable" hint remains a separate deferred item.

## Out of scope
- A non-D&D / global edition concept; edition for other systems.
- Migrating existing campaigns to a specific edition (null → 5.2 default is fine,
  pre-release).
