# Organize the Tables screen (sections + search)

**Date:** 2026-06-22
**Status:** Design — approved

## Problem

The Ask → Tables screen (`lib/features/tables_screen.dart`) renders all 59
oracle tables (`oracle.data.allTableKeys`, `intensity` excluded) as a single
flat, alphabetically-sorted `ListView` of cards. At 59 entries it's a wall of
rows — no grouping, no search, hard to find a specific table.

## Decisions (from brainstorming)

- **Sections + search.** Group tables into labeled, collapsible category
  sections AND add a name filter.
- **Auto-derive groups from key prefixes.** No asset/`build_oracle.py` change;
  a pure Dart helper, unit-tested; auto-adapts if tables are added.

## Architecture

### 1. Pure grouping helper — new `lib/engine/table_groups.dart`

```dart
class TableGroup {
  const TableGroup(this.label, this.keys);
  final String label;
  final List<String> keys;
}

/// Groups raw table keys by the prefix before the first '_'. A prefix shared
/// by >=2 keys becomes a group (label = title-cased prefix, with overrides);
/// no-'_' keys and singleton prefixes fall into a 'General' bucket. Groups are
/// sorted by label with 'General' pinned last; keys within a group are sorted.
List<TableGroup> groupTableKeys(List<String> keys);
```

- Prefix = `key.split('_').first`.
- Count members per prefix. Prefix with **count ≥ 2** → its own group.
  Everything else → **General**.
- Label = title-case the prefix, except an override map `{'npc': 'NPC'}`.
- Ordering: groups sorted alphabetically by label; `General` always last.
  Keys within each group sorted ascending.
- Expected groups from current data: Quest(5), NPC(5), Dungeon(8),
  Immersion(5), Interrupt(5), Idea(5), Settlement(4), Wilderness(4),
  Challenge(2), Emotion(2), Monster(2), Trap(2), General(~10:
  random_event, dc, pay_the_price, major_plot_twist, color, property, detail,
  history, because, natural_hazard).
- Invariant: every input key appears in exactly one group; total preserved.

### 2. `tables_screen.dart` rework

- Keep the existing **Dis / — / Adv** skew `SegmentedButton` header.
- Add a **search `TextField`** (`Key('tables-search')`) below the header;
  `_query` in state, case-insensitive `contains` over each table's display title.
- Body = `ListView` of **`ExpansionTile`** sections, one per `TableGroup`:
  - `PageStorageKey(group.label)` so expansion state survives the `setState`
    fired on every roll.
  - `initiallyExpanded: true`.
  - children = the table rows for that group's keys (filtered by `_query`).
- Each row keeps today's behavior verbatim, extracted into
  `Widget _tableTile(String key)`: tap or casino button rolls
  (`oracle.rollTable(key, title, skew: _skew)`), bookmark button adds the last
  result to the journal, last result shown as the subtitle.
- Search behavior: when `_query` is non-empty, hide groups with no matching
  tile; matching groups render their matching tiles. (Expansion stays user-/
  default-controlled; `initiallyExpanded: true` means matches are visible.)
- Table titles stay **full** (`_titleize(key)` → "Quest Objective") so the
  journal-add title is unchanged.

## Testing

- `test/table_groups_test.dart` (pure): prefix grouping; singleton/no-'_' →
  General; `npc` → "NPC" label; General pinned last; every key placed exactly
  once (count preserved); within-group sorting.
- `test/tables_screen_test.dart` (new widget test): pump `TablesScreen` with an
  oracle built from the real asset (dart:io, not rootBundle); assert a couple
  of group headers render (e.g. "Quest", "NPC", "General"); type in
  `tables-search` and assert non-matching tiles disappear; roll a table (tap)
  and assert its result subtitle + the add-to-journal button appear.

## Out of scope (YAGNI)

- Authored/curated group names or ordering (would belong in `build_oracle.py`).
- Stripping the group prefix from tile titles (keeps journal-add title intact).
- Per-group roll-all, favorites, recently-used.

## Files touched

| File | Change |
|------|--------|
| `lib/engine/table_groups.dart` | **new** — `TableGroup` + `groupTableKeys` |
| `lib/features/tables_screen.dart` | sections (ExpansionTile) + search; extract `_tableTile` |
| `test/table_groups_test.dart` | **new** — grouping unit tests |
| `test/tables_screen_test.dart` | **new** — widget test (sections, search, roll) |
