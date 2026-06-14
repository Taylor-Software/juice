# Lonelog Export (P2a) — Design

**Date:** 2026-06-14
**Status:** Approved (brainstorm) — ready for implementation plan
**Author:** John Taylor + Claude
**Depends on:** P1 Foundation (`2026-06-14-lonelog-foundation-design.md`)

## Context

juice already has two journal export paths: lossless `.juice.json` (full backup/restore,
`lib/state/campaign_io.dart`) and a *pretty narrative* `journalToMarkdown`
(`lib/engine/journal_export.dart`, mentions rendered as plain names). Lonelog support
(roadmap P2) adds a **third** format with a distinct purpose: a **faithful, parseable
Lonelog `.md`** for portability/interop — a log other Lonelog tools (or paper) can read,
and that juice can later read back (P2b import).

This spec is **P2a — export only** (juice → Lonelog `.md`). Import (Lonelog `.md` → juice,
inherently lossy because Lonelog is deliberately freeform) is deferred to **P2b**.

juice's journal entries are typed (`JournalKind` `text/result/scene`, with structured roll
payloads); threads/characters/tracks live in separate session-scoped stores. So a Lonelog
export is an interpretive mapping from juice's model onto Lonelog notation.

## Goal

Export the active campaign as a faithful, parseable Lonelog `.md` (YAML front matter +
state block + journal beats), invoked from the Campaigns menu, distinct from `.juice.json`
and the existing pretty markdown.

## Scope

### In scope
1. A pure engine that renders a campaign to Lonelog `.md`.
2. A wiring method that gathers the active session's data and returns the `.md`.
3. A Campaigns-menu action that saves it via the file picker.

### Out of scope (deferred)
- Lonelog `.md` **import** / parsing → **P2b**.
- Weaving entities inline into beats (the state-block approach is used instead).
- crawl/encounter/map/rumors stores (tool state, not journal notation; encounter →
  `[COMBAT]` is P4).
- Embedding juice IDs for lossless round-trip (kept pure-Lonelog; P2b import is heuristic
  by design).

## Architecture

- **Pure engine** `lib/engine/lonelog_export.dart` — no Flutter, no clock:
  ```dart
  String campaignToLonelog({
    required String campaignName,
    String genre = '',
    String tone = '',
    required List<Thread> threads,
    required List<Character> characters,
    required List<Track> tracks,
    required List<JournalEntry> entriesNewestFirst,
    required Map<String, String> threadTitles,
    required DateTime exportedAt,
  });
  ```
  Mirrors `journal_export.dart`. Reuses `slugify` and `mentionsToPlain`.
- **Wiring** `SessionsNotifier.exportActiveAsLonelog()` — reads the active session's
  journal/threads/characters/tracks + name + genre/tone (from `CampaignSettings` via
  `settingsProvider`), calls the engine, returns the string. Mirrors `exportActive()`.
- **Menu** — `_showSessions` in `home_shell.dart` gains an "Export as Lonelog (.md)" tile
  → `FilePicker.saveFile` with `<slug>.lonelog.md`, reusing the `_exportCampaign` pattern.

## Output format

```markdown
---
title: <campaign name>
genre: <settings.genre, omitted when empty>
tone: <settings.tone, omitted when empty>
tools: juice-oracle
exported: 2026-06-14
---

[STATE]
[Thread:Slay the wyrm|Open]
[Thread:Find the heir|Closed]
[N:Captain Vance|gruff, ally]
[PC:Kael|HP 8|brave]
[Track:Ritual 3/6]
[/STATE]

## Session log

### S1 *first scene title*
d: Fate Check — Likely -> Yes, but...
The guard hesitates at the gate.
=> [#Thread:Slay the wyrm]
```

- **YAML front matter:** `title` (campaign name), `genre`/`tone` (from `CampaignSettings`,
  each omitted when empty), `tools: juice-oracle`, `exported: <date>`.
- **`[STATE]…[/STATE]`** is a **juice-defined** structural block (guidelines-compliant: new
  blocks use `[NAME]/[/NAME]`); there is no canonical core Lonelog block for a generic
  threads/NPCs/tracks snapshot. It lists one tag line per entity.
- **`## Session log`** then the beats, oldest entry first.

### Entity → tag mapping (in `[STATE]`)
- `Thread{title, open}` → `[Thread:<title>|<Open|Closed>]`.
- `Character{name, tags}` → `[N:<name>|<tags joined by ", ">]` (or just `[N:<name>]` when no
  tags). (P2a uses `[N:]` for all characters; `[PC:]` distinction is deferred — juice has no
  PC/NPC flag on `Character`.)
- `Track{name, filled, max}` → `[Track:<name> <filled>/<max>]`.

### Beat mapping (oldest-first)
- `scene` → blank line + `### S<n> *<title>*` (n increments per scene encountered);
  `chaosFactor != null` → a following `(note: Chaos <c>)` line.
- `result` → `d: <title> -> <first line of mentionsToPlain(body)>`; when body empty,
  `d: <title>`.
- `text` → bare prose: `mentionsToPlain(body)`.
- `entry.threadId != null` → trailing `=> [#Thread:<threadTitles[id] ?? '(closed thread)'>]`.
- `entry.tags` non-empty → trailing `(note: <#tag1 #tag2 …>)`.
- Empty journal → a `(note: empty journal)` line under `## Session log`.

## Success criteria / testing

- `lonelog_export_test.dart` (pure, no Flutter, no rootBundle):
  - YAML header contains title + `tools: juice-oracle` + date; `genre`/`tone` present only when set.
  - `[STATE]` block opens/closes and lists a tag line for each thread/character/track with
    correct `Open/Closed`, joined tags, and `filled/max`.
  - Scene numbering increments; chaos note rendered when present.
  - Each entry kind maps per the rules above; threadId and tags trailers render.
  - Empty journal → placeholder.
  - Filename slug via `slugify`.
- Wiring smoke test (provider-overridden, no rootBundle): `exportActiveAsLonelog()` returns
  a non-empty `.md` containing the campaign title and a seeded thread's tag.

## Files

**New:** `lib/engine/lonelog_export.dart`, `test/lonelog_export_test.dart`.
**Edit:** `lib/state/providers.dart` (`exportActiveAsLonelog`),
`lib/shared/home_shell.dart` (menu tile + save handler).

## Open judgment calls (resolved)

- **`[STATE]` block** vs plain tag lines: use the block (the user chose "state block"); it is
  juice-defined and guidelines-compliant. Not added to the P1 legend's canonical block list
  (it is an export convention, not core notation).
- **Pure Lonelog**, provenance only in YAML; no embedded juice IDs.
- **`result` → `d:`** generic mechanics beat (Lonelog v1.5 uses `d:` for oracle dice too),
  rather than distinguishing `?`/`->` per payload command — simpler and faithful.
