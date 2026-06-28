# Combatant Stat Blocks (Tier-2 combat depth)

**Date:** 2026-06-28
**Status:** Design approved, pending implementation plan
**Builds on:** `docs/superpowers/specs/2026-06-28-gm-run-screen-design.md` (the GM run-screen's deferred "stat-block cards"); part of the GM-tool epic (Tier-2 combat depth).

## Summary

Give each encounter combatant an optional, **user-authored stat block** — AC,
attacks, saves, speed, and notes — so a GM can glance at a monster's numbers
mid-fight. Built **edit-on-Encounter, glance-on-Run**. Facts-only: the GM types
everything; zero vendored content, no SRD, no attribution.

HP already exists on the combatant (the `CharTrack` for ad-hoc, or the linked
character's pool). The stat block adds the rest.

## Decisions (from brainstorming)

- **Storage:** ephemeral, **on the `Combatant`** (a nullable `statBlock`). Typed
  when building the encounter, gone on reset. A reusable bestiary library is a
  deferred Tier-2.5 follow-up.
- **Fields:** AC (int), attacks (list of name + freeform detail), saves
  (freeform line), speed (freeform line), notes (freeform). Saves/speed are their
  own labeled lines (system-agnostic), distinct from the notes blob.
- **Attacks are display-only text** (e.g. "+4, 1d6+2"). No expression parser, no
  rollable attacks — mirrors the custom-sheet roll-model decision to avoid a
  parser. Rollable attacks are deferred.
- **Surfaces:** edit on the Encounter screen (expand a combatant row), read-only
  glance on the Run-screen initiative panel (tap a combatant).

## Model (`lib/engine/models.dart`)

```dart
class Attack {
  const Attack({required this.name, this.detail = ''});
  final String name;
  final String detail; // freeform, e.g. "+4, 1d6+2 slashing"
  // copyWith, toJson {name, if detail!='' detail}, tolerant fromJson
}

class StatBlock {
  const StatBlock({
    this.ac = 0,
    this.attacks = const [],
    this.saves = '',
    this.speed = '',
    this.notes = '',
  });
  final int ac;
  final List<Attack> attacks;
  final String saves, speed, notes;

  bool get isEmpty =>
      ac == 0 && attacks.isEmpty && saves.isEmpty && speed.isEmpty && notes.isEmpty;

  // copyWith; toJson omits empty fields; maybeFromJson tolerant
  //   (non-map -> a default empty StatBlock; bad attacks dropped).
}
```

`Combatant` (existing, `models.dart:2757`) gains a nullable `StatBlock? statBlock`,
threaded through `copyWith` (`{StatBlock? statBlock}`), `toJson` (`if (statBlock !=
null && !statBlock!.isEmpty) 'statBlock': statBlock!.toJson()`), and `fromJson`
(`StatBlock.maybeFromJson(j['statBlock'])`, null when absent — legacy-tolerant).
No other model changes; `EncounterState`/`EncounterNotifier.updateCombatant`
already persist a replaced combatant.

## Shared read-only view

`StatBlockView(StatBlock block)` — a read-only widget rendering the card: AC + HP
+ speed chips, an attacks list (name bold + detail muted), saves + notes labeled
lines. Empty fields are omitted. Lives in `lib/features/sheet_widgets.dart`
(the existing shared-widget home) so both surfaces reuse it (DRY). HP for the
chip is passed in by the caller (the combatant's resolved current/max), since the
block itself doesn't hold HP.

## Edit — Encounter screen (`lib/features/encounter_screen.dart`)

- Each combatant row gains a stat-block button (`IconButton`, key
  `encounter-<id>-statblock`, e.g. `Icons.shield_outlined`) opening
  `_StatBlockDialog` — a `StatefulWidget` editor:
  - AC: int `TextFormField` (`statblock-ac`).
  - Attacks: an editable list — each row a name field + detail field + a remove
    button; an "Add attack" button appends a blank `Attack`
    (`statblock-add-attack`). Empty-named attacks are dropped on save.
  - Saves / speed / notes: `TextFormField`s (`statblock-saves`/`-speed`/`-notes`).
  - Save (`statblock-save`) → `updateCombatant(c.copyWith(statBlock: built))`;
    a fully-empty block saves as `null` (so `toJson` stays clean).
- When a combatant's block is non-empty, the row shows a compact inline
  affordance/summary (AC chip + attack count) so the GM sees at a glance which
  combatants have a block. (The full card renders on tap/expand via the shared
  `StatBlockView`, to keep the row compact.)
- The add-combatant dialog is unchanged (stays lean); the block is filled
  afterward via the row button.

## Glance — Run-screen initiative panel (`lib/features/run_screen.dart`)

- In `_InitiativePanel`, a combatant **with** a non-empty stat block becomes
  tappable (`run-init-<id>-statblock` or wrap the row in an `InkWell`) → opens a
  read-only dialog (`showStatBlock`) rendering `StatBlockView` (+ the resolved HP
  chip). A combatant without a block is not tappable (or shows nothing). No edit
  on the run-screen.

## Testing

`test/` (model — `test/encounter_*` or a new `test/stat_block_test.dart`):
- `StatBlock`/`Attack` JSON round-trip; `maybeFromJson` tolerant (non-map →
  empty; malformed attack entries dropped); `isEmpty` true/false cases.
- `Combatant` round-trips with a block and without one (legacy JSON → null block).

`test/encounter_*` (widget):
- Open `_StatBlockDialog` on a combatant, set AC + add one attack, save →
  `updateCombatant` persisted the block (read it back).
- A fully-empty edit saves `statBlock == null`.

`test/run_screen_test.dart` (widget):
- A combatant seeded with a stat block → tap → `StatBlockView` shows the AC + an
  attack name. A combatant without a block → no glance dialog.

## Out of scope (deferred)

- **Rollable attacks** — needs the deferred expression parser; attacks stay text.
- **Reusable bestiary library** (save/reuse a creature across encounters) —
  Tier-2.5; this slice is ephemeral on the combatant.
- **Structured per-save fields**, senses, CR/XP, conditions-on-block — folded
  into freeform `saves`/`notes` for now.
- **Import / templates / vendored monsters** — facts-only; the GM types it all.
- No export change beyond the combatant JSON already carried by the encounter key.
