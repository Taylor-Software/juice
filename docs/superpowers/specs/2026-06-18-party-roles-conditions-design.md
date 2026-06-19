# Party Roles + Conditions — Design

**Status:** Approved

## Problem

Most solo play is "a PC with companions" or "a party of several PCs," but the
character roster is a flat, ungrouped list with no notion of who's a player
character, a companion, or a background NPC — and no at-a-glance status. This
thread adds a per-character **role** (groups the roster) and a generic
per-character **conditions** list (status badges, edited inline), both surfaced
on the roster. Backward compatibility is out of scope (pre-release).

## Scope

**In:**
- `CharacterRole {pc, companion, npc}` on `Character` (default `pc`).
- `Character.conditions` (`List<String>`) + an authored preset list `kConditions`
  + free-text custom conditions.
- Roster grouped into **Party** (pc) / **Companions** (companion) / **NPCs**
  (npc) sections; empty groups hidden; the active/focused PC marked **lead**.
- A per-row **role** control (dropdown) and **condition badges** + an inline
  condition editor (toggle presets + add custom) reachable from the row.
- Create defaults: `Add` + the sheet creators → pc; `Generate NPC` → npc.

**Out (later / v2):**
- Explicit lead→subordinate nesting (`leadId`).
- Auto-linking companions to the party-emulator / sidekick by role.
- Surfacing each sheet's own conditions (D&D conditions/exhaustion, Ironsworn/
  Starforged debilities/impacts) — generic conditions only here.
- Condition mechanical effects (they're labels, not rules).

## Components

### Model — `lib/engine/models.dart`

Add `enum CharacterRole { pc, companion, npc }` (+ a `_roleFromName` helper,
default `pc`). On `Character`, add two fields following the `starred` house
pattern (default + omit-when-default in JSON):

```dart
  final CharacterRole role;        // default CharacterRole.pc
  final List<String> conditions;   // default const []
```

- Constructor: `this.role = CharacterRole.pc`, `this.conditions = const []`.
- `copyWith`: add `CharacterRole? role`, `List<String>? conditions` (lists
  replaced wholesale, matching the existing list-copy convention).
- `toJson`: `if (role != CharacterRole.pc) 'role': role.name` and
  `if (conditions.isNotEmpty) 'conditions': conditions`.
- `fromJson`: `role: _roleFromName(j['role'] as String?)`,
  `conditions: ((j['conditions'] as List?) ?? const []).whereType<String>().toList()`.

Add the preset list (authored, generic status words — facts-only, no licensing):

```dart
const kConditions = <String>[
  'poisoned', 'hurt', 'afraid', 'hidden', 'prone',
  'restrained', 'stunned', 'exhausted', 'sick', 'marked', 'blessed',
];
```

### Notifier — `lib/state/providers.dart` (`CharacterNotifier`)

Mirror the existing `toggleStarred`/`replace` pattern:
- `setRole(String id, CharacterRole role)` — `replace(c.copyWith(role: role))`.
- `setConditions(String id, List<String> conditions)` — `replace(c.copyWith(
  conditions: conditions))`. (Inline editor builds the new list and calls this.)

### Roster — `lib/features/tracker_screen.dart` (CharactersPane)

Replace the flat `ListView.builder` with a grouped list:
- Partition `chars` by `role` into pc / companion / npc buckets (preserve the
  existing order within each; the active PC and starred can float to the top of
  the pc bucket — keep simple: original order, lead marked, not reordered).
- Render, in order, only non-empty groups: a section header (`Party`,
  `Companions`, `NPCs`) then each character `Card`.
- Each row keeps the existing name + first-track subtitle + star + delete + tap.
  ADD: a role control (`PopupMenuButton<CharacterRole>`, keyed
  `role-<id>`, calling `setRole`); and a condition area showing the character's
  `conditions` as small badges + a `+` (keyed `conditions-<id>`) that opens the
  inline editor.
- The active PC (`playContextProvider.activeCharacterId`) in the Party group
  shows a small "lead" badge.

### Inline condition editor — `lib/features/tracker_screen.dart`

A small dialog/bottom-sheet (`_editConditions(context, character)`): renders the
union of `kConditions` + the character's current custom conditions as toggle
chips (selected = in the character's list), plus a text field to add a custom
condition. On close, calls `setConditions(id, selected)`. (Build the new list
from the toggles; trim/dedupe custom entries.)

## Data flow

`charactersProvider` (+ `playContextProvider` for the lead) → grouped roster.
Role dropdown → `setRole`. Condition `+`/badge → `_editConditions` →
`setConditions`. Create paths set `role` (pc default; generate-npc → npc).

## Error handling

- Empty roster → existing empty state.
- A character with no conditions → no badges, just the `+` affordance.
- Deleting the active PC → `playContextProvider` already resolves a stale id to
  null (no lead marker); no crash.
- Custom condition: blank/whitespace ignored; duplicates collapsed.

## Testing

- `models` test — `Character.role`/`conditions` round-trip (absent role→pc, npc
  persists; conditions list round-trips; both omitted when default/empty).
- `character_provider_test` — `setRole` + `setConditions` persist.
- `character_sheet_ui_test` (or a new roster test) — roster groups by role
  (PCs/Companions/NPCs headers; empty groups hidden); the role dropdown re-tags
  (moves a row between groups); condition badges render; the inline editor
  toggles a preset + adds a custom and they appear as badges; active PC shows
  the lead marker; `Generate NPC` creates an npc-role character. Pump
  CharactersPane directly (override oracleProvider where the create paths roll).
- Full suite green; `dart format` + `flutter analyze` clean.

## Docs

- `CLAUDE.md` note: `CharacterRole` + `Character.conditions` (+ `kConditions`),
  the role-grouped roster (Party/Companions/NPCs, lead = active PC), inline
  condition editor, create-role defaults. Deferred: lead→subordinate nesting,
  companion↔emulator auto-link, per-sheet condition surfacing.
- No new licensed content (generic status words).
