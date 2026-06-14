# Lonelog Import (P2b) — Design

**Date:** 2026-06-14
**Status:** Approved (brainstorm) — ready for implementation plan
**Author:** John Taylor + Claude
**Depends on:** P1 Foundation, P2a Export (`2026-06-14-lonelog-export-design.md`)

## Context

P2a exports a campaign as a Lonelog `.md` (YAML front matter + `[STATE]` block + journal
beats). P2b is the reverse: import a Lonelog `.md` into juice. It is **tolerant and lossy
by design** — Lonelog is a deliberately freeform notation, and juice's journal has only
three entry kinds (`text/result/scene`) with no way to reconstruct the structured roll
payloads juice itself produces. The clean parts (YAML header, `[STATE]` entities) round-trip
exactly; the beats are preserved as text.

It mirrors the existing `.juice.json` import (`SessionsNotifier.importCampaign`): parse →
build the per-store JSON → create a new session → write its scoped prefs → switch to it.

## Goal

Import a Lonelog `.md` as a new campaign: parse the header → name/genre/tone, the `[STATE]`
block → threads/characters/tracks, and the beats → grouped journal entries.

## Scope

### In scope
1. A pure parser `Lonelog .md` → structured juice data.
2. Wiring that imports the parsed data as a new session.
3. A Campaigns-menu "Import Lonelog (.md)" action.

### Out of scope
- Reconstructing structured roll payloads (impossible from Lonelog text — lossy by design).
- Merging into the current session (new session only, like `importCampaign`).
- crawl/encounter/map/rumors (P2a didn't export them; nothing to import).
- Pretty rendering of imported notation in the journal — that is **P3**.

## Architecture

- **Pure parser** `lib/engine/lonelog_import.dart`:
  ```dart
  class LonelogImport {
    final String campaignName;
    final String genre;
    final String tone;
    final List<Thread> threads;
    final List<Character> characters;
    final List<Track> tracks;
    final List<JournalEntry> entries; // newest-first (juice convention)
  }

  LonelogImport parseLonelog(String md, {required DateTime importedAt});
  ```
  No Flutter, no clock (timestamps derive from `importedAt`). Synthetic IDs
  (`ll-thread-0`, `ll-char-0`, `ll-track-0`, `ll-entry-0`, …) — unique within a session,
  which is all juice requires. Independent of P1 (no highlighter dependency).
- **Wiring** `SessionsNotifier.importLonelog(String content)` — parses with
  `importedAt: DateTime.now()`, `toJson`s each non-empty store into a `rawByKey` map
  (`juice.journal.v2`, `juice.threads.v1`, `juice.characters.v1`, `juice.tracks.v1`,
  `juice.settings.v1`), creates `SessionMeta(id: _newId(), name: campaignName)`, writes
  `'$base.$id'` prefs, and `_save`s the new active session. Mirrors `importCampaign`.
  Throws `FormatException('Not a Lonelog file')` when the input has neither a `---` front
  matter nor a `[STATE]` / `## Session log` marker.
- **Menu** — "Import Lonelog (.md)" tile in `_showSessions` → `FilePicker.pickFiles`
  (`allowedExtensions: ['md']`, `withData: true`) → `importLonelog(utf8.decode(bytes))` →
  pop; on `FormatException`, a snackbar. Mirrors `_importCampaign`.

## Parser rules (tolerant — unrecognized lines ignored)

- **YAML front matter** (lines between the first `---` and the next `---`): `title` →
  `campaignName` (strip a single pair of surrounding `"` the exporter adds; tolerant of bare
  values); `genre`; `tone`. Missing title → `campaignName = 'Imported Lonelog'`.
- **`[STATE]` … `[/STATE]`** — each tag line:
  - `[Thread:<title>|Open]` / `[Thread:<title>|Closed]` → `Thread(title, open: state == 'Open')`.
  - `[N:<name>]` or `[N:<name>|<t1, t2, …>]` → `Character(name, tags: split on ', ')`.
  - `[Track:<name> <filled>/<max>]` → `Track(name, filled, max)`.
  - Any other line → ignored.
- **Beats** (lines after a `## Session log` heading, or the whole body if absent):
  - `### S<n> *<title>*` or `### S<n> <title>` → `scene` entry (title); if the next non-blank
    line is `(note: Chaos <c>)`, it is consumed and sets `chaosFactor`.
  - Other lines, grouped by blank-line separators → **one `text` entry per group**, body =
    the group's lines joined by `\n`, verbatim.
  - A lone `(note: empty journal)` group → produces no entry.
- **IDs/order/timestamps:** entries parsed in file order (oldest first) get timestamps
  `importedAt.add(Duration(seconds: i))`; the returned `entries` list is reversed to
  newest-first (juice's stored convention). IDs are index-based per store.

## Testing

- `lonelog_import_test.dart` (pure, no Flutter):
  - YAML header parsed (quoted and bare values); missing title → fallback name.
  - `[STATE]` block → correct threads (Open/Closed), characters (name + tags), tracks (f/m).
  - Scene entry + chaos note; grouped multi-line beat → one `text` entry with joined body.
  - `(note: empty journal)` → zero entries.
  - Unknown/garbage lines in the body are tolerated (no throw).
  - **Round-trip:** `campaignToLonelog(...)` → `parseLonelog(...)` recovers the campaign name,
    each thread (title + open state), each track, and the scene/entry count.
- Wiring smoke test (`SharedPreferences` mock + `ProviderContainer`): `importLonelog(sample)`
  creates a new active session named from the header with a parsed thread present.
- `importLonelog` throws `FormatException` on a non-Lonelog string.
- Menu-tile widget test: "Import Lonelog (.md)" present in the Campaigns dialog.

## Files

**New:** `lib/engine/lonelog_import.dart`, `test/lonelog_import_test.dart`.
**Edit:** `lib/state/providers.dart` (`importLonelog`), `lib/shared/home_shell.dart`
(menu tile + `_importLonelog`), `test/lonelog_campaign_ui_test.dart` (tile test).

## Open judgment calls (resolved)

- **New session, not merge** — matches `importCampaign`, non-destructive.
- **Grouped beats** (blank-line separated) → one `text` entry each — chosen over per-line
  (noisy) and semantic-by-symbol (interpretive, fragile).
- **Lossy accepted** — beats become `text` entries with the raw notation as body; P3 renders
  it prettily later. No roll-payload reconstruction.
- **Stacked on P2a** — `importLonelog`/menu touch the same files and the round-trip test
  consumes `campaignToLonelog`.
