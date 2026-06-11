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
| 3 | Dice roller (notation engine) | next |
| 4 | Character sheets (flexible blocks) | planned |
| 5 | Encounter tracker (initiative + tracks) | planned |
| 6 | Maps (dungeon rooms + wilderness hex) | planned |

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
