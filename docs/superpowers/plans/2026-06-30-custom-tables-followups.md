# Custom Random Tables — follow-ups (Ask surfacing + table packs)

Closes the two remaining deferred items from the Custom Tables P2 work:
1. **Ask-verb surfacing** — custom tables are only reachable from the journal
   composer's inspire → `GenerateSheet` "My Tables". Add them to the
   **Ask → Tables** tab (`TablesScreen`) so they sit beside the built-in tables.
2. **Import/export table packs** — `customTablesProvider` is app-global and is
   deliberately NOT in campaign export. Give the table set its own portable file
   (`.tables.json`) so users can share/back up their authored tables.

Same posture as before: **facts-only** (zero vendored content), pure engine for
serialization, subagent-driven with spec+quality review per group.

## Key decisions
- **Pack format** (forward-compatible wrapper, not a bare list):
  `{"kind":"juice-table-pack","v":1,"tables":[<CustomTable.toJson()>...]}`.
  Decode is tolerant (drops malformed rows/tables, never throws).
- **Import merges by APPEND with fresh ids** — never clobbers existing tables and
  re-importing the same pack just adds copies (predictable, no silent overwrite).
  Each imported table gets a new id derived from a base timestamp + its index.
- **Editor reuse** — `_showTableDialog` is private in `generate_sheet.dart`.
  Extract it to a public `showCustomTableDialog` in a new
  `lib/features/custom_table_editor.dart` so both `GenerateSheet` and
  `TablesScreen` call the one editor. No behavior change to the dialog itself.
- Pack export/import live in the campaigns drawer menu (`home_shell.dart`) next to
  the existing campaign export/import, reusing the `FilePicker` pattern.

---

## Task 1 — Engine: table-pack encode/decode (pure, TDD)

In `lib/engine/custom_table.dart` add:

```dart
/// Stable marker for an exported table pack file.
const kTablePackKind = 'juice-table-pack';

/// Serialize [tables] to a portable pack JSON string.
String encodeTablePack(List<CustomTable> tables) => jsonEncode({
      'kind': kTablePackKind,
      'v': 1,
      'tables': tables.map((t) => t.toJson()).toList(),
    });

/// Decode a pack JSON string into tables. Tolerant: returns an empty list when
/// the payload is not a recognizable pack; drops individual malformed tables.
/// Throws [FormatException] only when the top-level JSON itself is unparseable.
List<CustomTable> decodeTablePack(String raw) {
  final dynamic root = jsonDecode(raw); // may throw FormatException — caller handles
  if (root is! Map) return const [];
  if (root['kind'] != kTablePackKind) return const [];
  final list = root['tables'];
  if (list is! List) return const [];
  return list
      .map(CustomTable.maybeFromJson)
      .whereType<CustomTable>()
      .toList();
}
```

Add `import 'dart:convert';` at the top if not present.

**Tests** (`test/custom_table_test.dart`, new group "table pack"):
- round-trips a multi-table pack (uniform + weighted + ranges) — names, modes,
  dice, rows (incl. spans) survive.
- `decodeTablePack` on a bare list `[]`-wrapped non-pack → `[]` (no throw).
- `decodeTablePack` on wrong `kind` → `[]`.
- `decodeTablePack` on a pack whose `tables` has a junk entry (e.g. `42`) → keeps
  the valid ones (reuses `maybeFromJson`).
- `decodeTablePack('not json')` throws `FormatException`.

---

## Task 2 — Provider: `addAll` with fresh ids

In `CustomTablesNotifier` (`lib/state/providers.dart`) add:

```dart
/// Append [incoming] tables with fresh ids (import never clobbers existing).
Future<void> addAll(List<CustomTable> incoming) async {
  if (incoming.isEmpty) return;
  final base = DateTime.now().microsecondsSinceEpoch;
  final stamped = [
    for (var i = 0; i < incoming.length; i++)
      incoming[i].copyWith(/* id is preserved by copyWith — use a fresh one */),
  ];
  // copyWith keeps id, so build new CustomTable with a fresh id instead:
  final fresh = [
    for (var i = 0; i < incoming.length; i++)
      CustomTable(
        id: '${base + i}',
        name: incoming[i].name,
        mode: incoming[i].mode,
        dice: incoming[i].dice,
        rows: incoming[i].rows,
      ),
  ];
  await _save([...await _ready, ...fresh]);
}
```

(Drop the `stamped` scratch — only `fresh` is used. The implementer should write
just the `fresh` version; the comment above explains why `copyWith` can't be used
to re-id.)

**Tests** (`test/custom_tables_provider_test.dart`):
- `addAll` appends to an existing list and assigns ids distinct from existing ones.
- `addAll([])` is a no-op.
- imported tables preserve name/mode/dice/rows.

---

## Task 3 — Refactor: extract `showCustomTableDialog`

- New file `lib/features/custom_table_editor.dart`: move `_showTableDialog` from
  `generate_sheet.dart` here VERBATIM, rename to public `showCustomTableDialog`.
  Carry its imports (`flutter/material`, `flutter_riverpod`, `../engine/custom_table.dart`,
  `../state/providers.dart`).
- `generate_sheet.dart`: delete the moved function; `import` the new file; replace
  the two `_showTableDialog(context, ref, ...)` call sites with
  `showCustomTableDialog(context, ref, ...)`.
- No behavior change. `flutter analyze` clean + existing `generate_sheet_test.dart`
  still green (the `table-new` / dialog tests exercise the moved code through the
  same keys).

---

## Task 4 — Ask surfacing: "My Tables" in `TablesScreen`

In `lib/features/tables_screen.dart` add a section at the TOP of the `ListView`
(above the built-in table groups), only when the user has custom tables OR always
show the "New table" affordance (show always — gives a discovery path):

- Watch `customTablesProvider`.
- Render an `ExpansionTile` titled "My Tables" (key `tables-my-tables`),
  `initiallyExpanded: true`, containing one `Card`/`ListTile` per custom table
  (key `my-table-<id>`): tap or a roll `IconButton` rolls via
  `rollCustomTable(t, Dice())` and logs through
  `journalProvider.notifier.addResult(r.title, r.asText, sourceTool: 'custom-table', payload: r.toPayload())`
  with a "Added to journal" snackbar; an edit `IconButton` (key `my-table-edit-<id>`)
  opens `showCustomTableDialog(context, ref, t)`.
- A trailing "New table" `ListTile`/button (key `tables-my-new`) →
  `showCustomTableDialog(context, ref, null)`.
- Hide the whole section when searching (`_query` non-empty) so it doesn't clutter
  built-in-table search results — OR filter custom tables by the query too. Keep it
  simple: when `_query` is non-empty, hide the My Tables section.
- New imports: `../engine/custom_table.dart`, `../engine/dice.dart`,
  `custom_table_editor.dart`.

**Tests** (`test/tables_screen_test.dart` — follow the existing harness there;
check what providers it overrides for oracle data + mock prefs):
- with a seeded custom table, the `my-table-<id>` row renders and rolling it adds a
  `custom-table` journal entry.
- the `tables-my-new` affordance opens the editor (find `table-name` field).
- the My Tables section is hidden when a search query is active.

---

## Task 5 — Export/Import table-pack UI

In `lib/shared/home_shell.dart`, add two `ListTile`s to the campaigns drawer menu
(after the Lonelog import item, before the blob-GC item), and two handlers
mirroring `_exportCampaign`/`_importCampaign`:

```dart
ListTile(
  key: const Key('menu-export-tables'),
  leading: const Icon(Icons.table_chart_outlined),
  title: const Text('Export table pack'),
  onTap: () => _exportTablePack(dialogContext),
),
ListTile(
  key: const Key('menu-import-tables'),
  leading: const Icon(Icons.table_view_outlined),
  title: const Text('Import table pack'),
  onTap: () => _importTablePack(dialogContext),
),
```

Handlers:
- `_exportTablePack`: read `customTablesProvider` value; if empty → snackbar
  "No custom tables to export." and return (still pop). Else
  `encodeTablePack(tables)` → `FilePicker.saveFile(fileName: 'tables.tables.json',
  type: custom, allowedExtensions: ['json'], bytes: utf8.encode(...))`. Wrap in the
  same `PlatformException` try/catch as `_exportCampaign`. (No `lastExportProvider`
  stamp — that's campaign-backup specific.)
- `_importTablePack`: `FilePicker.pickFiles(allowedExtensions: ['json'],
  withData: true)`; on bytes, `decodeTablePack(utf8.decode(bytes))` inside a
  try/catch for `FormatException` (snackbar "Not a valid table pack."); if the
  decoded list is empty → snackbar "No tables found in file."; else
  `customTablesProvider.notifier.addAll(decoded)` + snackbar
  "Imported N table(s)." Pop the menu.

Reuse existing imports (`FilePicker`, `utf8`, `Uint8List`, `PlatformException`).
Add `import '../engine/custom_table.dart';` if not already imported.

A widget test for the menu wiring is optional (file I/O is hard to drive in
widget tests — the existing export/import items have no such test). Skip unless
trivial; the engine + provider paths are unit-tested.

---

## Task 6 — Docs + full verify

- Update the **Custom random tables** bullet in `CLAUDE.md`: note Ask-verb
  surfacing (TablesScreen "My Tables") + table-pack import/export
  (`.tables.json`, `encodeTablePack`/`decodeTablePack`, `addAll`), and remove
  those two items from the "Deferred:" list (leaving per-campaign/exported scope).
- `flutter analyze` clean; full `flutter test` suite green.

---

## Out of scope (still deferred)
- Per-campaign / exported-with-campaign scope for custom tables.
- Importing community packs from a URL/registry.
- Pack merge-by-id / dedupe (we always append fresh).
