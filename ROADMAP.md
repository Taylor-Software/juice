# Roadmap

Now / Next / Later. Driven by the 2026-06-11 competitive brief vs
[johnkord/juice-roll](https://github.com/johnkord/juice-roll).
Solo-dev capacity: one or two items in flight at a time.

Strategy in one line: **own "roll + remember your campaign"** — journal
depth and verified correctness — while closing the distribution gap.
Expansion direction: multi-system journal home base — Mythic GME and
the Ironsworn family (both map onto our Threads/Characters tracker —
breadth that compounds our differentiator instead of diluting it).

---

## Now (committed)

| Item | Why | Effort | Status |
|---|---|---|---|
| Web deploy + CI (GitHub Pages, `flutter build web`, analyze+test gate) | Biggest competitive delta is reach, not features — juice-roll lives at a URL, we require a local build | S | **Done** — live at https://taylor-software.github.io/juice/ (2026-06-11) |
| Re-verify BEST-EFFORT tables (wilderness monster grid, NPC dialog grid) against the Juice PDF; encode in `build_oracle.py`, regenerate `oracle_data.json` | Known correctness gaps; protects the "verified engine" claim. juice-roll's `reference/` markdown transcriptions are a useful cross-check, but the PDF is the source of truth | M | **Done** — 3 OCR corrections found, 3 new generators (2026-06-11) |

## Next (1–3 months, scoped not started)

| Item | Why | Effort |
|---|---|---|
| ~~Stateful crawl modes~~ — **shipped 2026-06-11**: wilderness env drift + Lost/Found, dungeon linger (d6), crawl + dialog state persisted | Best Juice-specific play-feel idea in the competitor | M |
| ~~Sessions (multi-campaign)~~ — **shipped 2026-06-11**: per-session key namespace + legacy migration, app-bar switcher (create/switch/delete) | Table stakes for a journal app | M |
| ~~Campaign save/open as JSON files~~ — **shipped 2026-06-11**: export/import via system picker, schemaVersion 1, import-as-new-session (BYO cloud — see below) | Data portability + user-owned cloud sync with zero server | M |
| ~~Mythic GME core spike~~ — **shipped 2026-06-11**: Chaos Factor dial, Fate Chart (source-verified ladder), Scene Test, Event Focus targeting tracked Threads/Characters; CC-BY-NC attribution in-app | Expands audience to the largest solo-RPG oracle community; tracker becomes Mythic's lists for free | L |

Dependencies:
- File save/open lands with or after sessions — exporting one global
  blob then migrating to sessions creates a format break.
- Mythic spike lands after sessions (a Mythic adventure is a session
  with chaos state attached).

## Later (directional)

- ~~**Journal depth**~~ — **shipped 2026-06-11** (PR #8): log↔thread
  links, filter chips, in-place edit. Character-linking deliberately cut.
- ~~**Mythic GME full support**~~ — **shipped 2026-06-11** (PR #9): all
  47 Meaning Tables. Behavior/Statistic/Detail checks deferred — no
  clean machine-readable source exists; revisit if one appears.
- ~~**Ironsworn family**~~ — **shipped 2026-06-11** (PRs #10–#11): all
  four rulesets from official Datasworn data, family exclusivity, merged
  Moves tab, per-asset license attribution (Sundered Isles is
  CC-BY-NC-SA; the rest CC-BY).
- ~~**Abstract Icons oracle**~~ — **shipped 2026-06-11** (PR #12).
  Initially closed as license-blocked; reopened after the official itch
  page (thunder9861.itch.io/juice-oracle) confirmed assets including
  icons are CC BY-NC-SA 4.0. All 60 icons vendored, 1d10+1d6 grid pick
  per the instructions, rendered in Generators.
- ~~**PWA polish**~~ — **shipped 2026-06-11** (PR #7): proper manifest
  identity/colors/description; offline cache via Flutter's service
  worker; install prompt is the browser's native flow.

**First cycle complete** (2026-06-11, PRs #1–#13, incl. the Roll High
oracle added on request).

## Cycle 2: journal-first redesign (started 2026-06-11)

Spec: `docs/superpowers/specs/2026-06-11-journal-redesign-design.md`.
The journal becomes the home surface; every tool is summoned over it
(drawer/bottom sheet) and feeds results back into it.

| Phase | Item | Status |
|---|---|---|
| 1 | Journal core (entry kinds, migration, journal screen) | **Done** — PR #14 (2026-06-11) |
| 2 | Shell swap (journal home + activity-grouped tool drawer) | **Done** — PR #15 (2026-06-11) |
| 3 | Dice roller (notation engine) | **Done** — PR #16 (2026-06-11) |
| 4 | Character sheets (flexible blocks) | **Done** — PR #17 (2026-06-11) |
| 5 | Encounter tracker (initiative + tracks) | **Done** — PR #18 (2026-06-11) |
| 6 | Maps (dungeon rooms + wilderness hex) | **Done** — PR #19 (2026-06-11) |

**Cycle 2 complete** (2026-06-11, PRs #14–#19). The journal is the home
surface; dice, oracles, sheets, encounters, and maps all feed it. Next
planning cycle starts from a fresh competitive scan and user feedback.

## Oracle interpreter (on-device LLM, user-requested)

Spec: `docs/superpowers/specs/2026-06-11-oracle-interpreter-design.md`.
Journal results gain an Interpret action: four lens readings (literal /
symbolic / complication / foreshadow) from a small on-device model;
accepted readings append to the entry. Dice stay authoritative.

| Phase | Item | Status |
|---|---|---|
| 0 | Web spike (litertlm vs -web.task, model availability) | **Done** — findings in spec (2026-06-11) |
| 1 | Engine + service + sheet + journal wiring + web path | **Done** — PR #20 (2026-06-11) |
| 2 | Mobile platform config (Android ABI/OpenCL, iOS Podfile) + device verify | **Done** — PR #21 (2026-06-11); full loop verified on iOS simulator; physical-device pass still open |

Release gates before announcing the web feature: swap the dev-pinned
third-party model mirror in `lib/state/interpreter_gemma.dart` to the
user's own HF mirror of the official `gemma3-1b-it-int4-web.task`
(provenance; see spec "Weights provenance").

## Cycle 3: campaign memory + reach (started 2026-06-11)

Driven by the 2026-06-11 competitive rescan: juice-roll is dormant
(no threat); the community's top unmet need is campaign memory/retrieval
("find that NPC detail from twelve sessions ago"); our two uncontested
claims are the multi-system journal and on-device journal-aware AI.
Web-first PWAs are the community norm — distribution = community channels,
not app stores.

| # | Item | Status |
|---|---|---|
| A | Quick wins: Location grid table, tap-to-roll fate check, WCAG AA contrast pass | **Done** — PR #22 (2026-06-11) |
| B | Journal export (styled HTML/markdown per campaign) | **Done** — PR #23 (2026-06-12) |
| E | Discoverability prep: itch.io page assets, awesome-ironsworn PR, Tomkin community-resources submission, repo topics/screenshots (submissions need owner sign-off) | **Prep done** — PR #24 (2026-06-12); repo metadata live; submissions drafted in docs/discoverability/submissions.md, awaiting owner posting |
| C | Journal search + tags (foundation for D) | **Done** — PR #26 (2026-06-12) |
| D | Journal-aware interpreter (retrieval over journal → seed context) | **Done** — PR #27 (2026-06-12) |

Deferred: store distribution (Play/TestFlight) — community discovers via
web/itch; revisit on demand signal.

**Cycle 3 complete** (2026-06-12, PRs #20-#24, #26-#27 + repo metadata).
The journal remembers: search, tags, styled exports, and an interpreter
whose readings recall related past entries — all retrieval on device.
Open user actions: web model mirror swap (release gate), discoverability
submissions (docs/discoverability/submissions.md), physical-device pass.
Next planning cycle starts from a fresh competitive scan and any user
feedback from the discoverability channels.

## Party emulator (Pettish + Triple-O, user-requested)

Spec: `docs/superpowers/specs/2026-06-12-party-emulator-design.md`.
Flips the solo seat: the player GMs, the app emulates the characters —
what they do (Triple-O), how they feel and why (PET), what they say
(Sidekick) — anchored on existing Characters, journaled, voiceable by the
on-device interpreter.

| Phase | Item | Status |
|---|---|---|
| 1 | Data pipeline (`build_emulator.py`) + Behavior Tables (13 d66 tables) | **Done** — PR #28 (2026-06-12) |
| 2 | Triple-O check + `Character.emulation` + Party Emulator tool | **Done** — PR #29 (2026-06-12) |
| 3 | PET procedures (ACT/REFOCUS/tag spend/session start/tokens/consequences) | **Done** — PR #30 (2026-06-12) |
| 4 | Sidekick dialogue + hexflower walker + `voiceLine` | **Done** — PR #31 (2026-06-12) |

**Party emulator complete** (2026-06-12, PRs #28–#31). Descoped: the
hexflower figure's heavy-border interrupt (visual-only in the source PDF,
never encoded; the context-switch note + conversation Reset cover the
rule's intent — revisit only if a machine-readable border source appears).
Phase 3's live verification caught a lost-update bug class
(read-modify-write from build-captured state); all emulation writes now
read fresh at press time — keep that pattern for future handlers.

## Help system (user-requested)

Spec: `docs/superpowers/specs/2026-06-12-help-system-design.md`.
**Shipped 2026-06-12** — PR #32: in-app Help tool (user guide for every
tool, original-wording quick-references for all seven supported systems,
credits page with every content license + Flutter's package LicensePage),
plus a per-tool "?" deep link in the tool host.

## Cycle 4: The Living Journal (started 2026-06-12)

Spec: `docs/superpowers/specs/2026-06-12-cycle4-living-journal-design.md`.
Driven by the 2026-06-12 competitive rescan: RPG Spark v3 and the Mythic GME
2e app now pair oracles with a journal (@mentions/#tags), iron-vault sets the
mechanics-in-prose bar, and on-device oracle interpretation remains an empty
category. Cycle 4 closes the "journal is home but passive" gap and deepens
both moats — the journal becomes a command surface and a living wiki.

| Phase | Item | Status |
|---|---|---|
| 1 | Command registry + structured journal entries (re-roll, open-in-tool) | **Done** — PR #33 |
| 2 | Slash command palette in the composer | **Done** — PR #34 |
| 3 | Collapsible campaign header + per-campaign default oracle | **Done** — PR #35 |
| 4 | Per-campaign system profiles (scope drawer/palette/header) | **Done** — PR #36 |
| 5 | Entity `@`-mentions + save-NPC/location-as-entity + character filter | **Done** — PR #37 |
| 6 | Ask-anything (`?`/`/ask`) + voice any dialog-shaped entry (C1, C4) | **Done** — PR #38 |
| 7 | Heuristic entity suggestions + `/recap` & "previously on" (C3, C2) | **Done** — PR #39 |

**Cycle 4 complete** (2026-06-13, PRs #33–#39). The journal now answers
questions in one entry, scopes itself to the campaign's systems, links and
suggests entities, and recaps play on device. Patterns carried forward:
additive-and-tolerant JSON (every new field omitted at its default, legacy
campaigns byte-stable), structured payloads with flat fallback, and
press-time fresh reads on every read-modify-write. Deferred: LLM
`suggestOdds` pre-selection (manual odds shipped), mention rename
re-propagation (label frozen, nav by id), B3 scene start/end loop, the
D-theme pass (typography / genre themes / Cmd-K), and store distribution
(web-first holds). Open user actions unchanged: web model mirror swap
(release gate), discoverability submissions, physical-device interpreter pass.

## Cloud storage stance (BYO cloud, no server)

The app stays standalone with no server component and no network code.
Users get cloud sync by saving campaign files into a folder their own
cloud client already syncs (iCloud Drive, Google Drive, Dropbox,
OneDrive). The OS document picker exposes these providers natively:
Android via Storage Access Framework (persistable URI grants for
re-save), iOS/macOS via the document picker (security-scoped
bookmarks), desktop via plain file dialogs, web via download/upload
(File System Access API where available). No OAuth, no provider SDKs,
no accounts — the cloud vendor's own app does the syncing. Campaign
JSON carries `schemaVersion` + `savedAt` for forward migration and a
last-write-wins conflict warning on open.

## Monitor

- juice-roll repo for tracker/journal-shaped features (the move that
  hurts us) and for Android/store distribution.

---

Update cadence: revisit when an item ships or the competitive picture
changes; don't reshuffle mid-item.
