# Draw Steel character sheet (facts-only P1)

**Date:** 2026-06-24
**Status:** Approved

## Problem

Add a pre-made character sheet for the Draw Steel TTRPG (MCDM Productions) — the same facts-only posture used for Nimble/Shadowdark. Draw Steel's signature mechanic is the **power roll** (2d10 + characteristic → three tiers), so the sheet includes per-characteristic quick-roll buttons surfaced inline.

## License

**Draw Steel Creator License** (MCDM Productions) permits: rules reuse, proper names, commercial sale, apps (no explicit prohibition). Restrictions: no reproducing art, no MCDM logo, non-affiliation disclaimer required in legal and promotional materials.

Required statement (verbatim, per license):
> "This is an independent product published under the Draw Steel Creator License and is not affiliated with MCDM Productions, LLC."

Placement: `kSystemBlurbs['draw-steel']` (shown at campaign create/edit) + the settings/about sheet.

Facts-only posture: authored class/characteristic NAMES only (non-copyrightable game mechanic facts). No rulebook prose, no class feature text, no art.

## Constants (to verify at implementation time)

During implementation, fetch the current class list and heroic resource names from the [MCDM Draw Steel resources page](https://www.mcdmproductions.com/draw-steel-resources) (Rules Reference PDF / character sheet PDFs / pregenerated heroes). Mark any unverified constants with `// VERIFY` comments.

Known with high confidence:
- Characteristics: `might`, `agility`, `reason`, `intuition`, `presence` (scores −5 to +5)
- Power roll tiers: ≤11 → Tier 1, 12–16 → Tier 2, ≥17 → Tier 3
- Core classes include: Fury, Conduit, Tactician, Elementalist, Shadow

Needs verification: full class list, heroic resource name per class (e.g., Fury → "Fury", Conduit → "Piety").

```dart
const kDrawSteelCharacteristics = ['might', 'agility', 'reason', 'intuition', 'presence'];

// Verify against published Draw Steel Heroes book / MCDM resources
const kDrawSteelClasses = <String>[/* ... */];

// class name → heroic resource label (facts-only: these are non-copyrightable names)
const kDrawSteelHeroicResource = <String, String>{/* ... */};
```

## Model — `lib/engine/models.dart`

`DrawSteelSheet` follows the `NimbleSheet` pattern: const constructor, all fields player-editable, `copyWith` with clamps, `toJson`/`maybeFromJson`.

```dart
class DrawSteelSheet {
  final String className;         // from kDrawSteelClasses
  final String ancestry;          // freeform
  final int level;                // 1–10
  final Map<String, int> characteristics; // keys = kDrawSteelCharacteristics, values −5..+5
  final int maxStamina;           // HP equivalent
  final int currentStamina;
  final int recoveries;           // current remaining
  final int maxRecoveries;        // player-set
  final int stability;            // resist push/knockdown
  final int heroicResource;       // current amount of class resource
  final String skills;            // freeform
  final String notes;             // freeform
}
```

`Character` gains a `DrawSteelSheet? drawSteel` field (ctor/copyWith/toJson/fromJson/`clearDrawSteel`), mirroring `Character.nimble`.

`Character.withHpDelta` gets a `drawSteel` branch: adjusts `currentStamina` (clamped 0..maxStamina).

## Sheet UI — `lib/features/draw_steel_sheet.dart`

`DrawSteelSheetView({required Character character, required VoidCallback onBack})` — `ConsumerWidget`, mirrors `NimbleSheetView` structure.

**Sections (top to bottom):**

1. **Header** — class dropdown (`draw-steel-class`), ancestry `TextFormField`, level stepper (`draw-steel-level`)

2. **Characteristics** — 5 rows, one per characteristic:
   ```
   [Might]  [−] [score] [+]  [🎲]
   ```
   - Score stepper key: `draw-steel-char-<k>` (e.g., `draw-steel-char-might`)
   - 🎲 button key: `draw-steel-roll-<k>`
   - On tap: `roll = Random().nextInt(10)+1 + Random().nextInt(10)+1 + score`
   - Tier: `roll <= 11 → 'Tier 1'`, `roll <= 16 → 'Tier 2'`, `else 'Tier 3'`
   - Result shown via `ScaffoldMessenger.showSnackBar`: `"Might: $roll — Tier N"`
   - Ephemeral only — no journal log (keeps the sheet interaction lightweight)

3. **Stamina** — currentStamina / maxStamina steppers (`draw-steel-stamina` / `draw-steel-max-stamina`)

4. **Recoveries** — current / max steppers (`draw-steel-recoveries` / `draw-steel-max-recoveries`)

5. **Stability** — single stepper (`draw-steel-stability`)

6. **Heroic Resource** — label = `kDrawSteelHeroicResource[className] ?? 'Resource'`; current int stepper (`draw-steel-resource`)

7. **Conditions** — `conditionsSection(context, ref, character, 'draw-steel')` (shared widget)

8. **Skills** — multiline `TextFormField` (`draw-steel-skills`)

9. **Notes** — multiline `TextFormField` (`draw-steel-notes`)

Keyed root: `draw-steel-sheet`.

## System integration

| Touch point | Change |
|-------------|--------|
| `lib/engine/models.dart` | `kDrawSteelCharacteristics`, `kDrawSteelClasses`, `kDrawSteelHeroicResource`, `DrawSteelSheet`, `Character.drawSteel`, `withHpDelta` branch |
| `lib/features/draw_steel_sheet.dart` | new `DrawSteelSheetView` |
| `lib/features/system_primer.dart` | `'draw-steel'` primer line (setting descriptor + "power roll 2d10+characteristic → three tiers") |
| `lib/features/tracker_screen.dart` | render branch `if (c.drawSteel != null)`; `new-draw-steel` create option gated on `systems.contains('draw-steel')` |
| `lib/shared/home_shell.dart` | `sys-draw-steel` toggle in `NewCampaignDialog` + `_EditSystemsDialog`; `kSystemBlurbs['draw-steel']` with MCDM non-affiliation statement |
| `lib/features/encounter_screen.dart` | HP read-through: `currentStamina`/`maxStamina` when `linked.drawSteel != null` |
| `lib/features/settings_sheet.dart` | MCDM non-affiliation statement in about/credits section |

System key: `'draw-steel'`. NOT in `kAllSystems`. Default off.

`CharacterNotifier.addDrawSteel()` creates a new character with default `DrawSteelSheet()` via roster route `new-draw-steel`.

## Power roll mechanic

```dart
// On 🎲 tap for characteristic k with score s:
final r1 = Random().nextInt(10) + 1;
final r2 = Random().nextInt(10) + 1;
final total = r1 + r2 + s;
final tier = total <= 11 ? 'Tier 1' : total <= 16 ? 'Tier 2' : 'Tier 3';
ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(content: Text('${k[0].toUpperCase()}${k.substring(1)}: $total — $tier')),
);
```

No dice animation (inline sheet interaction; animation is roller-screen only). No journal log (ephemeral check, same rationale as HUD chaos chip steppers).

## Testing

- `DrawSteelSheet` model: copyWith clamps, unknown class → first class, `maybeFromJson` round-trip, `withHpDelta` clamps.
- `DrawSteelSheetView` widget test: class dropdown changes class, stepper updates characteristic, 🎲 button triggers snackbar containing tier label.
- `kSystemBlurbs['draw-steel']` contains MCDM non-affiliation text.
- `sessionScopedKeys` does NOT need a new entry (sheet data lives on `Character.drawSteel`, already in `juice.characters.v1`).

## Files touched

| File | Action |
|------|--------|
| `lib/engine/models.dart` | add constants + `DrawSteelSheet` + `Character.drawSteel` |
| `lib/features/draw_steel_sheet.dart` | create |
| `lib/features/system_primer.dart` | add primer line |
| `lib/features/tracker_screen.dart` | render branch + create option |
| `lib/shared/home_shell.dart` | toggle + blurb |
| `lib/features/encounter_screen.dart` | HP read-through |
| `lib/features/settings_sheet.dart` | MCDM disclaimer |
| `test/draw_steel_sheet_test.dart` | create |

## Out of scope (P2)

- Draw Steel SRD content (class features, ability text, monsters) — no open data rail yet; would need the [Creator License SRD](https://www.mcdmproductions.com/draw-steel-resources) + proper attribution
- Advantage/disadvantage on power rolls (roll twice, keep best/worst) — defer; player can tap twice
- Condition pickers beyond the shared `conditionsSection`
- Heroic resource auto-gain triggers
