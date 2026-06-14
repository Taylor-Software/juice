# Lonelog Journal Notation (P3) — Design

**Date:** 2026-06-14
**Status:** Approved (autonomous, goal: continue to completion)
**Depends on:** P1 Foundation (the `highlight()` classifier + `lonelog` system flag)

## Goal

When the `lonelog` system is enabled for a campaign, render Lonelog notation in the
journal's entry bodies with syntax highlighting (symbols, tags, blocks, actors, meta),
reusing P1's `lib/engine/lonelog_highlight.dart`. This makes imported/typed Lonelog
notation legible in the core journal.

## Scope

### In scope
- `MentionText` (the entry-body renderer) gains a `bool lonelog` flag. When true, each
  non-mention text segment is highlighted line-by-line via `highlight()`; `@`-mentions stay
  tappable links (they are pre-extracted by `parseMentions`, so there is no `@[..]` / `@`
  collision with Lonelog's action symbol).
- `JournalScreen` computes `lonelog = activeMeta.enabledSystems.contains('lonelog')`
  (watched) and threads it to `_entry` → `MentionText`, and to `_PayloadCard` → `MentionText`.

### Out of scope (defer)
- A composer symbol/tag quick-insert palette (P3b, if wanted).
- Reconciling Lonelog `[N:]` tags with juice's `@[..](char:ID)` mentions into a single entity
  index (the two markups coexist; the index already comes from juice's mentions).

## Design

`MentionText`:
- New `final bool lonelog;` (default `false`, so existing call sites are unchanged).
- In `build`, for a `MentionKind.text` segment: when `lonelog`, split the segment on `\n`
  and, per line, emit one `TextSpan` per `highlight()` span colored by kind; re-insert the
  `\n` between lines. When `!lonelog`, the current single `TextSpan`.
- Colors from the active `ColorScheme`, matching `LonelogReferenceScreen`'s example colors
  (symbol→primary, actor→tertiary, tag→secondary, block→error, meta→outline, text→base).

`JournalScreen`: compute the flag once where entries are listed; pass `lonelog:` to the three
entry-body `MentionText` call sites (text card, result card, `_PayloadCard` remainder).

## Testing

- `mention_text_test.dart`: `MentionText('@ Pick the lock [N:Bob]', lonelog: true)` renders a
  `RichText` whose spans include more than one color (symbol + tag distinct from base);
  `lonelog: false` renders the body as effectively one text run; a body with an `@[Name](char:ID)`
  mention still yields a tappable (recognizer-bearing) span under `lonelog: true`.

## Files

**New:** `test/mention_text_test.dart`.
**Edit:** `lib/shared/mention_text.dart` (flag + highlighting), `lib/features/journal_screen.dart`
(thread the flag to `_entry`, `_PayloadCard`, and the three `MentionText` call sites).
