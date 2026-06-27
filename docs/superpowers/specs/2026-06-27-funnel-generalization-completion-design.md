# Funnel Generalization Completion — Custom Sheet + Ironsworn Family

**Date:** 2026-06-27
**Status:** Design approved, pending implementation plan
**Builds on:** `docs/superpowers/specs/2026-06-27-generalized-funnel-design.md`

## Summary

Close the two remaining gaps that keep the generalized 0-level funnel from
covering **all** campaigns:

- **A. Custom/Homebrew sheet** — the `custom` system (PR #191) is a
  `SystemCategory.ruleset` but is currently *excluded* from the funnel
  completeness invariant and has no `FunnelProfile`, so a custom-sheet campaign
  can't funnel. A `CustomSheet` has no fixed stat keys (they live in the chosen
  template's `stat` block), which is why it was deferred.
- **B. Ironsworn family (Starforged / Sundered Isles)** — the funnel keys off
  `enabledSystems`, and the family is a single `ironsworn` flag plus an app-global
  ruleset discriminator (`rulesetsProvider`: `starforged` / `sundered_isles`). So
  Starforged/Sundered campaigns only ever graduate into *classic* Ironsworn. The
  standalone `starforged` `FunnelProfile` that exists is unreachable dead code;
  there is no `sundered_isles` profile.

Both fit a small shared model change (a `seedVariant` discriminator + a
`graduate` param), leaving the existing 11 fixed-system profiles unchanged in
shape.

## Decisions (from brainstorming)

1. **Custom peasant stats:** template chosen at funnel **creation**; peasant stat
   keys derive from that template's `stat` block (option B).
2. **Custom graduation:** **locked** to the creation template — survivors
   graduate 1:1 into that same template (no graduation template dropdown).
3. **Ironsworn family variant:** a graduation **dropdown defaulting to the active
   ruleset, overridable** (option C).

## Model changes

Two additions thread a "variant" through the funnel; the existing 11 profiles are
untouched in shape.

1. **`FunnelSheet.seedVariant`** (`String`, default `''`) — a sub-discriminator
   within `seedSystem`. For a **custom** funnel it holds the chosen **template
   id** (locked at creation). `''` for every other system. Wired into
   `FunnelSheet.copyWith` / `toJson` / `maybeFromJson` (tolerant: missing → `''`).
   `FunnelSheet.premade` / `addFunnel` accept it.

2. **`FunnelProfile.graduate` gains a trailing `String seedVariant` param** →
   `Character Function(String id, FunnelPeasant p, Map<String,String> picks, String seedVariant)`.
   The 10 fixed systems ignore it; **custom** reads it as the template id;
   **ironsworn** reads the family choice from `picks['variant']` (a graduation
   dropdown, not `seedVariant`). All call sites (`graduateFunnelPeasant` builder,
   tests) pass `s.seedVariant`.

3. **Peasant-schema resolution** — a pure helper in `lib/engine/funnel.dart`:

   ```dart
   typedef FunnelPeasantSchema = ({
     List<({String key, String label})> statKeys,
     int statMin, int statMax, int statDefault,
     List<({String key, String label})> flavorFields,
     int hpMin, int hpMax, bool hasHp,
   });

   FunnelPeasantSchema funnelPeasantSchema(String seedSystem, String seedVariant);
   ```

   For `custom` it derives from `kCustomTemplates[seedVariant]` (the first `stat`
   block's `stats` + `min`/`max`, and whether an `hp` block exists). For every
   other system it returns the fixed values from `funnelProfileFor(seedSystem)`.
   `FunnelSheetView` + `FunnelProfile.seedPeasant` use this helper so rendering +
   seeding stay uniform (no `system == 'custom'` branch in the widget body).

   `seedPeasant` becomes schema-driven: `FunnelProfile.seedPeasant(String
   seedVariant)` seeds `stats` from the resolved schema's keys at `statDefault`,
   `flavor` from `flavorFields`, `hp` at `hpMin`.

## A. Custom funnel

**Creation:** in `tracker_screen._newFunnel`, after the seed-system pick, if seed
== `custom` show a second `SimpleDialog` listing `kCustomTemplates` (Blank /
Generic d20 / OSR roll-under / 2d6 Moves; option keys `funnel-template-<id>`).
The pick becomes `seedVariant`. `CharacterNotifier.addFunnel(String seedSystem,
{String seedVariant = ''})` seeds one peasant from
`funnelPeasantSchema('custom', seedVariant)`. Non-custom seeds skip the template
step (`seedVariant` stays `''`).

**Peasant schema** (via the helper): stat keys/labels + min/max come from the
template's first `stat` block `config` (`stats`, `min`, `max`); `statDefault` =
mid of that range; HP stepper shown only when the template has an `hp` block.
Examples: an `osr`-template funnel → peasants STR/DEX/WIL (3–18) + HP; a
`pbta`-template funnel → its 5 mod-stats, **no** HP; a `generic-d20` funnel → 6
abilities (3–18) + HP.

**Graduation (1:1, locked):** the `custom` `FunnelProfile` has
`graduateChoices: []`. `graduate(id, peasant, picks, seedVariant)`:
1. `final t = kCustomTemplates.firstWhere((x) => x.id == seedVariant)` (fallback:
   first template, or an empty `CustomSheet` if none matches).
2. Build `CustomSheet(blocks: t.blocks)`.
3. Inject `values`: into the **first `stat` block's** value, write the peasant's
   `stats` map (keys match 1:1 since they came from this template); into the
   **first `hp` block's** value (if any), write the peasant's `hp`.
4. `Character.forSheet('custom', id).copyWith(name: heroName, custom: built)`.

**Blank template edge:** no `stat`/`hp` blocks → schema yields an empty stat list
+ a default HP range (e.g. 1–8) so peasants are name+HP-only; graduation produces
an empty `CustomSheet` named after the survivor (nothing to inject). Usable.

## B. Ironsworn family

Classic Ironsworn, Starforged, and Sundered Isles share the same 5 stats
(edge/heart/iron/shadow/wits, 1–3); only the graduated *sheet* differs.

- **Remove the standalone `starforged` profile** from `kFunnelProfiles` (it is
  never in `enabledSystems`, so unreachable). The family routes through the
  `ironsworn` profile. No `sundered_isles` profile is added.
- **`ironsworn` profile gains a `variant` graduation choice:**
  `FunnelChoice('variant', 'Ruleset', ['ironsworn', 'starforged', 'sundered_isles'])`.
  Dropdown labels use friendly names (Ironsworn / Starforged / Sundered Isles).
- **Default from the active ruleset:** the graduate dialog (`FunnelSheetView`,
  has `ref`) reads `rulesetsProvider` and `resolveSystem(systems, rulesets)`; if
  that yields `starforged`/`sundered_isles`/`ironsworn`, it pre-selects that as
  the `variant` default (overridable — option C). When `resolveSystem` returns a
  non-family value or empty, default to `ironsworn`.
- **`graduate` builds the matching sheet** from `picks['variant']`:
  `Character.forSheet(picks['variant'] ?? 'ironsworn', id)` →
  `ironsworn` → `IronswornSheet`; `starforged` → `StarforgedSheet`;
  `sundered_isles` → `StarforgedSheet(assetRuleset: 'sundered_isles')` (via the
  existing `forSheet` arms). Stats map by the 5 shared keys (into
  `IronswornSheet`'s individual `edge/heart/...` fields or `StarforgedSheet`'s);
  no HP pool, so peasant HP is not mapped (unchanged).

Result: a Starforged or Sundered Isles campaign funnels (seed `ironsworn`) and
graduates survivors into the correct family sheet, defaulted to the campaign's
ruleset.

## UI changes

`lib/features/funnel_sheet.dart` + `lib/features/tracker_screen.dart`:

- **`_newFunnel`** gains the custom template step (above). Signature of the
  notifier add becomes `addFunnel(seedSystem, {seedVariant})`.
- **Peasant cards** build stat/HP steppers from `funnelPeasantSchema(s.seedSystem,
  s.seedVariant)` rather than `funnelProfileFor(s.seedSystem)!` — so a custom
  funnel renders the template's stat keys and hides HP when the schema has none.
- **Graduate dialog:** structure unchanged; `picks` is seeded from the target
  profile's `defaultPicks()` plus, for `ironsworn`, the active-ruleset-derived
  `variant` default. The `variant` dropdown renders from the `ironsworn` profile's
  new `graduateChoices`. The graduate call passes `s.seedVariant` as the 4th arg.
- **Header:** a custom funnel shows the template name, e.g.
  `0-Level Funnel — Custom (Generic d20)`, via `kSystemShortName['custom']` + the
  template label; non-custom unchanged.

## Testing

`test/funnel_test.dart` (model/unit) + `test/funnel_sheet_ui_test.dart` (widget):

- **Schema helper:** `funnelPeasantSchema('custom', <each template id>)` yields
  the right stat keys + range + `hasHp` (generic-d20 → 6 abilities, hasHp true;
  osr → str/dex/wil, hasHp true; pbta → 5 mods, hasHp false; blank → empty stats,
  hasHp true default). Non-custom systems return their profile's fixed values.
- **Custom graduate:** for a generic-d20 funnel, `graduate` builds a `CustomSheet`
  whose first `stat` block value holds the peasant's stats and whose `hp` block
  value holds the peasant's hp; the hero is a `Character.custom`; name carried.
  Blank template → empty custom sheet, no crash.
- **Ironsworn family graduate:** `picks: {'variant': 'ironsworn'}` → `IronswornSheet`;
  `'starforged'` → `StarforgedSheet` (not sundered); `'sundered_isles'` →
  `StarforgedSheet` with `isSundered` true. Stats map by the 5 keys.
- **Dialog default:** with `rulesets` containing `starforged`, the graduate
  dialog's `variant` default resolves to `starforged`; with `sundered_isles`, to
  `sundered_isles`; classic/none → `ironsworn`.
- **Registry:** completeness test drops the `'custom'` exclusion (custom now has a
  profile); assert `kFunnelProfiles` has **no** `starforged`/`sundered_isles`
  keys (family via `ironsworn`). `FunnelSheet.seedVariant` round-trips through
  JSON (and defaults `''` when absent).
- **UI:** custom funnel creation (seed custom → template picker → peasant cards
  render the template's stats); graduate spawns a template-built custom hero with
  stats injected + the funnel persists.

## Out of scope (deferred)

- Cross-system graduation stays best-effort by key (unchanged); custom's 1:1 only
  holds within its locked template.
- Only the **first** `stat`/`hp` block of a custom template receives injected
  values (multi-stat-block templates inject into the first).
- `seedVariant` is meaningful only for `custom`; the Ironsworn family variant is a
  graduation pick, not stored on the funnel.
- No auto-archive, batch graduate, or funnel→funnel (unchanged from the base
  funnel spec).
- No backward-compat for pre-existing funnels (pre-release; `seedVariant` defaults
  `''`, which is correct for all non-custom existing funnels).
