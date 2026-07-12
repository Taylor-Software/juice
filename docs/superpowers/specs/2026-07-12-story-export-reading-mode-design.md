# Story export + reading mode — design

**Date:** 2026-07-12
**Source:** QoL assessment #1 — the journal's proudest artifact is the
narrative itself, but export was transcript-shaped (full Markdown/HTML) or
notation-shaped (Lonelog).

## Design

One shared predicate, `isStoryEntry(JournalEntry)`
(`lib/engine/journal_export.dart`): prose = `text` / `scene` / `session`
entries plus `result` entries whose `sourceTool` is `narrate` or `interpret`
(AI narration and oracle interpretations read as story). Everything else —
dice/oracle results, readings, sketches — is mechanics.

- **Story export:** `journalToStory(...)` (pure, same file) renders oldest
  first — `#` session breaks, `##` scene headers **with their descriptions**
  (the flesh-out scene body), and prose paragraphs with `@[...]` mentions
  flattened to plain names. Chaos snapshots, tags, thread links, and all
  mechanics are omitted. Surfaced as a third option in the existing journal
  export dialog (`export-story` → `<slug>-story.md`); the full transcript
  exports are unchanged.
- **Reading mode:** a `journal-reading-mode` toggle in the journal actions row
  filters the entry list through the same predicate. State is a file-local
  non-autoDispose `StateProvider` — survives verb switches, resets on launch,
  never persisted.

## Tests

`test/story_export_test.dart`: full-render golden string (ordering, scene
body, mention flattening), mechanics-never-leak, empty placeholder, predicate
table, and a widget test driving the reading-mode toggle both ways.
