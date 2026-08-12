# Polarity Grammar magic system integration

**Date:** 2026-08-11
**Status:** Design — approved

## Problem

Incorporate **The Polarity Grammar** — a homebrew magic system (own IP, sibling
repo `~/StudioProjects/magic`, GitHub `Taylor-Software/practical-magic`) — into
juice as an opt-in per-character casting panel. Spells are sentences (Effects +
Form + target phrases + adverbial dials); mana cost is the sum of every card
used, derived live, never stored on the spell. The system converts its mana
economy into any host ruleset's (D&D 5e, Pathfinder 1e/2e, B/X, OSE, Shadowdark,
DCC, OSR points/slot/tier), so it isn't tied to one sheet type — any juice
character, regardless of ruleset, should be able to opt in.

The `packages/polarity_grammar` Flutter package (deck data, cost engine,
models, `PolarityStore` interface, 27 widget files, ~8200 lines, 438 passing
tests, zero Riverpod/path_provider/shared_preferences deps) was purpose-built
for this: its `PolarityStore` abstract class exists specifically so a host app
supplies its own persistence, and its README states the embedding intent
outright.

## Licensing

Two different licenses in the sibling repo:

- **Game system text** (`polarity-grammar.md`, `quickstart.md`, card text) —
  **CC BY 4.0**. Freely shareable/adaptable with credit.
- **App/package source code** — currently **unlicensed** ("all rights
  reserved, pending a separate decision"). Same author as juice (John Taylor),
  so this is a non-blocking formality, not a legal risk — noted for the
  author's own future licensing decision, not something this integration needs
  to resolve.

No third-party content is vendored; nothing here touches juice's existing
CC-BY/OGL/CC-BY-SA content-licensing posture ([[licensing-constraint]]).

## Approach

### Dependency: pinned git dependency

```yaml
polarity_grammar:
  git:
    url: https://github.com/Taylor-Software/practical-magic.git
    path: packages/polarity_grammar
    ref: <commit-sha>
```

Not a relative `path:` dependency (juice has zero path/git deps today; a path
dep breaks for anyone/anything without `magic` checked out as an exact sibling
— CI, other machines) and not a vendored copy (would fork the source out of
its one real home, silently diverging from `polarity-grammar.md`). A pinned
git ref matches the discipline juice already runs on itself: the ruleset
document is upstream of the code, and code changes ride a deliberate ref bump,
not an automatic float.

**Deferred implementation detail, not a design fork:** pub needs git
credentials to fetch a private repo in CI — whatever auth juice's own CI
already uses for this repo (deploy key / token) needs the same reach into
`Taylor-Software/practical-magic`. Handled in the implementation plan, not
here.

### Character link: 1:1, id-shared in spirit

The package's `Character` (id, name, `baseMana`, `currentMana`, `spellLevel`,
`characterLevel`, `school`, `systemId`) is a different, much narrower record
than juice's `Character` (full sheet/HP/roster/role/conditions). They are not
mergeable into one type. Instead:

- juice's `Character` gains `String? polarityId` — set the moment magic is
  enabled on that character, null otherwise.
- The package's `Library` holds one `pg.Character` per juice character that
  has opted in, keyed by that same id value (`pg.Character.id ==
  juiceCharacter.polarityId`) — so there is exactly one caster record per
  juice character, never a separate roster to manage in parallel.
- Enabling magic on a juice `Character` creates its `pg.Character` (default
  mana/level) in the campaign's `Library` and sets `polarityId`; there is no
  path where a `pg.Character` exists without a juice `Character` pointing at
  it.

### Opt-in: per-character toggle, no campaign-level system flag

No `magic` entry in `kKnownSystems`/`kAllSystems`, no campaign wizard toggle.
Every character, in every campaign, can individually enable Polarity Grammar
casting regardless of which ruleset sheet they use — matching how
`CharacterRole` and `conditions` already work today (roster-wide facilities,
not system-gated). This deliberately breaks from the "system flag" pattern
every other ruleset/addon uses, because Polarity Grammar isn't a ruleset
alternative to those — it's a layer that sits across whichever ruleset a
character already has.

### UI surface: `magicSection()`, mirroring `conditionsSection()`

There is **no shared sheet wrapper** in juice — 15 independent `*SheetView`
files (`lib/features/*.dart`) each build their own `ListView`. The existing
precedent for "one shared per-character block dropped into every sheet type"
is `conditionsSection()` (`lib/features/sheet_widgets.dart:614`), called from 10
of the 15 sheet files today (`CustomSheetView`, `DndSheetView`, `FunnelSheetView`,
`IronswornSheetView`, `StarforgedSheetView` omit it — the other 10 call it
unconditionally — this integration adds `magicSection` to all 15, since
Polarity Grammar applies uniformly).

A new `magicSection(BuildContext context, WidgetRef ref, Character c)` in
`sheet_widgets.dart`:

- `c.polarityId == null` → a single "Enable Polarity Grammar casting" button.
  Tapping creates the `pg.Character` + sets `polarityId` (via
  `CharacterNotifier`).
- `c.polarityId != null` → the full P1 panel, inline where space allows,
  pushing the package's own full-screen widgets where they already assume a
  `Scaffold`:
  - inline: `mana_bar.dart` (mana pool), `spellbook.dart` (saved spell list,
    tap to cast via `cast_panel.dart`)
  - pushed as a route (juice already pushes full-screen tool routes
    elsewhere — GM chat, sketch editor — so this isn't a new navigation
    shape): `spell_builder.dart` (build/price/save a new spell),
    `card_reference.dart` (browse all 44 effect pairs),
    `conversion_calculator.dart`, `user_guide.dart`.

P1 wires the **entire** standalone-app feature set (build, price, save, cast,
browse reference, convert, learn) — not a cut-down caster panel. The package
is already built and tested; `app/` is effectively the reference wiring to
port into `magicSection()` + its pushed routes.

Import collisions (`pg.Character`/`pg.Library`/`pg.Spell` vs juice's own) are
resolved with `import 'package:polarity_grammar/polarity_grammar.dart' as
pg;` wherever both appear in the same file. The package's `Character` never
touches juice's `Character` type directly — only `polarityId` bridges them.

### Persistence: session-scoped, one `Library` per campaign

- `JuiceMagicStore implements TextLibraryStore` (thin adapter — the package
  already owns JSON (de)serialization, quarantine-on-corrupt, and
  schema-too-new handling via `TextLibraryStore`).
- Key: `loreseer.magic.v1.<sessionId>` (current session-scoped keys all use
  the `loreseer.` prefix, not `juice.` — CLAUDE.md's note that `juice.*` keys
  are kept for stability is stale as of this writing), registered in
  `sessionScopedKeys` → auto-exported with the campaign file, same posture as
  every other per-campaign store (threads, npcs, decks, etc).
- One `Library` holds every opted-in character's `pg.Character` + their
  spellbook + cast history for that campaign.

## Architecture — files touched

| File | Change |
|------|--------|
| `pubspec.yaml` | add `polarity_grammar` git dependency |
| `lib/engine/models/character.dart` | `Character.polarityId` (String?, ctor/copyWith/toJson/fromJson) |
| `lib/state/providers.dart` | `JuiceMagicStore` adapter; `magicLibraryProvider` (session-scoped, mirrors e.g. `decksProvider`); enable/disable + create-`pg.Character` actions on `CharacterNotifier` (or a sibling notifier) |
| `lib/features/sheet_widgets.dart` | new `magicSection()` |
| all 15 `lib/features/*_sheet.dart` (`ArgosaSheetView`, `CairnSheetView`, `CustomSheetView`, `DccSheetView`, `DndSheetView`, `DrawSteelSheetView`, `EmbarkSheetView`, `FunnelSheetView`, `IronswornSheetView`, `KalArathSheetView`, `KnaveSheetView`, `NimbleSheetView`, `OseSheetView`, `ShadowdarkSheetView`, `StarforgedSheetView`) | one-line insertion of `magicSection(context, ref, character)` into each `ListView`, applied uniformly (including funnel peasants — the per-character toggle makes no sheet-type exception) |
| new: `lib/features/magic_screen.dart` (or similar) | pushed-route wiring for `spell_builder`/`card_reference`/`conversion_calculator`/`user_guide` |
| `sessionScopedKeys` registry | add `loreseer.magic.v1` |

## Testing

- `Character.polarityId` round-trips (`toJson`/`fromJson`).
- `JuiceMagicStore` round-trips a `Library` through the adapter (mirrors
  `TextLibraryStore` contract tests already in the package).
- `magicSection()` widget test: disabled state shows the enable button;
  enabling sets `polarityId` and creates a `pg.Character`; mana bar / spellbook
  render once enabled.
- Smoke-test the pushed routes open (spell builder, card reference) without
  wiring every internal package widget test — those already pass in
  `packages/polarity_grammar` and aren't re-tested here.
- Export/import round-trip: a campaign file with `loreseer.magic.v1` data
  survives export → import (mirrors `test/persistence_tolerance_test.dart`
  conventions).

## Out of scope (deferred, flagged not resolved)

- **Design-system reconciliation.** The package's card *stock* (parchment,
  Cinzel/EB Garamond) is hardcoded by design — "cards are physical objects,"
  stays parchment in both light/dark. Chrome widgets read ambient
  `Theme.of(context)`, so embedded in juice they inherit `JuiceTokens`
  automatically. Whether the parchment card-stock exception is compatible with
  DESIGN.md's enforced rules (One Shadow, Warm-Only) is an open question for
  the author to bless or amend in DESIGN.md — not resolved by this spec. Run
  `test/design_system_test.dart` against the new screens once wired and
  address whatever it flags.
- CI git-credential wiring for the private dependency (implementation detail).
- Campaign-level `magic` system flag, quick-ref card, system-primer line — not
  built, since activation is per-character, not per-ruleset, and the AI seams
  (system primer / quick ref) key off the active *ruleset*, not this
  cross-cutting layer.
