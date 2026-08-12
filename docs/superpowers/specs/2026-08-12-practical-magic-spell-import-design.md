# Practical Magic spell import + in-app rename

**Date:** 2026-08-12
**Status:** Design — approved

## Problem

The standalone Practical Magic app (sibling repo `~/StudioProjects/magic`,
GitHub `Taylor-Software/practical-magic`) exports spellbooks as JSON — a
single-character envelope (`practicalmagicCharacter: 1` + character + spells +
history + hanging + running) or a whole-library blob (`Library.toJson()`).
Juice's embedded caster panel (PRs #324/#325) has no way to bring those spells
in; a player who built a spellbook in the standalone app must rebuild it by
hand in juice.

Also: juice's user-facing strings call the feature "Polarity Grammar"
("Enable Polarity Grammar casting"). The product name is **Practical Magic**
(the standalone app's display name); "Polarity Grammar" is the ruleset's
internal name. UI strings should say Practical Magic.

## Scope decision

**Spells only, into a chosen (already opted-in) character.** The import takes
every spell in the pasted export — both export shapes, all characters'
spells flattened — remaps ids, points them at the target caster, and appends.
Mana/level/school, cast history, hanging and running spells in the export are
ignored. Full character import (new juice roster entry) is out of scope.

## Approach

### Package change (sibling repo): shared `decodeShare`

The decode logic today lives in the standalone app's `state.dart`
(`_decodeImport`) — not in the shared `polarity_grammar` package. The parts
juice needs are exactly the parts the package already owns knowledge of:
`Spell.fromJson`, the `shiftAdverbials: v < 2` schema migration,
`kSchemaVersion`, `SchemaTooNewException` (all in
`packages/polarity_grammar/lib/src/model/`).

New in the package (e.g. `lib/src/model/share.dart`):

```dart
/// Pure parse of a Practical Magic export — the character envelope
/// (`practicalmagicCharacter: 1`) or a whole-library blob. No id remapping
/// (hosts mint their own ids). Throws [FormatException] on junk and
/// [SchemaTooNewException] on a newer save.
({
  List<Character> characters,
  List<Spell> spells,
  List<CastRecord> history,
  List<HangingSpell> hanging,
  List<RunningSpell> running,
}) decodeShare(String raw);
```

Body is the parse half of the standalone app's `_decodeImport`, moved
verbatim (both shapes, `schemaVersion` gate, `shiftAdverbials` migration,
"damaged" `FormatException` wrapping). The standalone app's `_decodeImport`
then delegates to `decodeShare` and keeps only its fresh-id remap — one
source of truth, no behavior change there.

Juice bumps its pinned git `ref` in `pubspec.yaml` (currently
`6646f1fa5590…`) to the commit carrying `decodeShare`.

### Juice: `MagicController.importSpells`

```dart
/// Merge-import the spells from a Practical Magic export into
/// [targetPgCharacterId]'s spellbook: every spell in the export (both
/// shapes, all characters' spells flattened), fresh ids, appended — never
/// replaces. Returns the added spells (for count + undo). Throws
/// [FormatException] / [SchemaTooNewException] like decodeShare.
Future<List<pg.Spell>> importSpells(String targetPgCharacterId, String raw);
```

- `pg.decodeShare(raw)` → take `.spells` only.
- Each spell: `copyWith(id: _freshId('spell', now), characterId:
  targetPgCharacterId, editedAt: now)`. Everything else (name, favorite,
  castCount, structure) rides through unchanged.
- Append to `_lib.spells`, `_commit`. Importing the same export twice
  duplicates rather than collides (same posture as the standalone app and
  juice's table-pack import).
- No-op guard: if the target id has no `pg.Character` in the library, throw
  `StateError` (UI can't reach this — the button only renders on a linked
  caster — but the controller shouldn't silently drop data).

### Juice UI: import button + paste dialog

- `magic-import` `TextButton.icon` ("Import spells", `Icons.download`) in the
  Magic section's action `Wrap` in `sheet_widgets.dart`, beside Build spell /
  Card reference — rendered only in the linked-caster state (same as the
  other actions).
- Tap opens a dialog (mirrors the standalone app's paste import and juice's
  `menu-import-tables` posture): title "Import spells", body text "Paste an
  export from the Practical Magic app.", a multiline `TextField`
  (`magic-import-field`), Cancel + Import (`magic-import-confirm`).
- Import: call `importSpells`; on success pop + snackbar via
  `showUndoSnackbar(context, 'Imported N spells', undo)` where undo deletes
  the added spell ids. On `FormatException`/`SchemaTooNewException`, show the
  message inline in the dialog (`magic-import-error`), dialog stays open.

### Rename: Polarity Grammar → Practical Magic (juice UI strings)

- `sheet_widgets.dart`: enable button label → "Enable Practical Magic
  casting"; doc comments updated to say Practical Magic.
- Sweep juice `lib/` for any other user-facing "Polarity" strings (today:
  none besides comments in `character.dart`/`providers.dart` — update the
  comments too for consistency).
- **Unchanged:** `Character.polarityId` field/JSON key, the
  `loreseer.magic.v1.<sessionId>` prefs key, the `polarity_grammar` package
  name, widget keys. Identifier stability, same posture as the juice-oracle
  naming rule.

## Files touched

| Repo | File | Change |
|------|------|--------|
| magic | `packages/polarity_grammar/lib/src/model/share.dart` (new) | `decodeShare` (moved parse half of `_decodeImport`) |
| magic | `packages/polarity_grammar/lib/polarity_grammar.dart` | export `share.dart` |
| magic | `app/lib/state.dart` | `_decodeImport` delegates to `decodeShare` |
| magic | `packages/polarity_grammar/test/` | `decodeShare` unit tests |
| juice | `pubspec.yaml` | git ref bump |
| juice | `lib/state/magic_controller.dart` | `importSpells` |
| juice | `lib/features/sheet_widgets.dart` | import button + dialog; rename strings |
| juice | `lib/engine/models/character.dart`, `lib/state/providers.dart` | comment rename only |
| juice | `test/` | controller + widget tests |

## Testing

- **Package:** `decodeShare` — character envelope, library blob, junk JSON
  (`FormatException`), non-export JSON map (`FormatException`),
  `schemaVersion: 3` (`SchemaTooNewException`), v1 save exercises
  `shiftAdverbials`. Standalone app's existing import tests keep passing
  (delegation is behavior-neutral).
- **Juice controller:** import a character envelope → spells appended with
  fresh ids + target `characterId`; import a library blob with two
  characters → all spells flatten onto the target; import twice → duplicates
  (no collision); junk → throws, library untouched; unknown target id →
  `StateError`.
- **Juice widget:** dialog opens from `magic-import`; junk paste shows
  inline error and stays open; valid paste pops + spells appear in the
  spellbook list; undo removes them.
- Rename: existing `magic-enable` widget test's label expectation updated.

## Out of scope

- Full character import (new roster entry).
- Importing history/hanging/running/mana settings.
- File-picker import (paste only — matches the standalone app's
  clipboard-based sharing).
- Export FROM juice back to the standalone app (juice campaign export
  already carries the magic library; a dedicated share-out is a separate
  feature).
