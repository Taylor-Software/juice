# Solo Loop — One-Tap AI Interpret — Design

**Date:** 2026-06-29
**Status:** Approved (brainstorming)
**Context:** Final deferred follow-up from the Solo Loop feature
(`docs/superpowers/specs/2026-06-29-solo-loop-success-tally-design.md`). Lets the player
turn the Loop's d10 yes/no roll into narrative with one tap, using the existing on-device
LLM Interpret seam.

## Summary

Add an **Interpret** button to the Solo Loop pane's Ask step (step 2), shown only when AI
is ready and a yes/no result is present. It ports the Run screen's proven inline-interpret
(`run_screen.dart` `_interpret`, the `run-dice-interpret` button) verbatim: seed an
`OracleSeed` from the rolled result + active scene + active PC + genre/tone + system
primer, run the shared `OracleInterpretationSheet`, and log the accepted reading as the
standard `'interpret'` journal entry.

No engine changes, no new seam, no new persistence — pure reuse.

## Architecture (mirror of the Run screen)

`LoopPane` is a `ConsumerStatefulWidget` already holding `_last` (the `SoloYesNo` from the
Ask step). Add:

### `_interpret()` (new method on `_LoopPaneState`)

```dart
Future<void> _interpret() async {
  final last = _last;
  if (last == null) return;
  final g = last.toGenResult();
  final journal = ref.read(journalProvider).valueOrNull ?? const <JournalEntry>[];
  final ctx = ref.read(playContextProvider).valueOrNull;
  final scene = activeSceneEntry(journal, ctx?.activeSceneId);
  final settings =
      ref.read(settingsProvider).valueOrNull ?? const CampaignSettings();
  final seed = OracleSeed(
    resultText: g.asText,
    genre: settings.genre,
    tone: settings.tone,
    sceneContext: scene == null ? '' : '${scene.title}\n${scene.body}'.trim(),
    activeCharacter: ref.read(activeCharacterLineProvider),
    systemPrimer: ref.read(systemPrimerProvider),
  );
  final accepted = await showModalBottomSheet<OracleInterpretation>(
    context: context,
    isScrollControlled: true,
    builder: (sheetCtx) => OracleInterpretationSheet(
      seed: seed,
      onAccept: (card) => Navigator.pop(sheetCtx, card),
    ),
  );
  if (accepted == null || !mounted) return;
  await ref.read(journalProvider.notifier).addResult(
        'Oracle reading',
        '(${accepted.lens}): ${accepted.reading}',
        sourceTool: 'interpret',
      );
}
```

This is identical to `run_screen.dart`'s `_interpret` except `_last` is a `SoloYesNo`
(so `g = last.toGenResult()`) rather than a `GenResult`.

### The button (in the Ask step's children, step 2)

Watch `aiReadyProvider` in `build()`. After the existing `loop-ask-result` Text, gate a
button on `aiReady && _last != null`:

```dart
if (aiReady && _last != null)
  OutlinedButton(
    key: const Key('loop-interpret'),
    onPressed: _interpret,
    child: const Text('Interpret'),
  ),
```

`aiReadyProvider` is `false` when AI is disabled or on web (the service forces the
`unsupported` phase), so the button is hidden exactly where every other AI affordance is.

### Imports to add to `loop_pane.dart`

- `import '../engine/models.dart';` (`JournalEntry`, `CampaignSettings`)
- `import '../engine/oracle_interpreter.dart';` (`OracleSeed`, `OracleInterpretation`)
- `import 'oracle_interpretation_sheet.dart';`

(`activeCharacterLineProvider` is from the already-imported `play_context.dart`;
`settingsProvider` / `aiReadyProvider` / `systemPrimerProvider` from the already-imported
`providers.dart`.)

## DRY consideration (decided: do NOT extract)

`run_screen._interpret` and `loop_pane._interpret` are near-identical. We deliberately keep
the small duplication: only two call sites, the seed source differs (`GenResult` vs
`SoloYesNo`), and the body is short. Extracting a shared `interpretInline(ref, context,
GenResult)` helper is a reasonable future cleanup but is premature now (YAGNI). Noted for
the reviewer.

## Testing

- `test/loop_pane_test.dart` (extend):
  - **AI off** (default fake interpreter `unsupported` → `aiReadyProvider` false): after
    tapping `loop-ask`, the `loop-interpret` button is absent.
  - **AI ready** (override `aiReadyProvider` to `true`, or pump a ready fake interpreter):
    after a roll (`_last != null`), the `loop-interpret` button is present.
- The full sheet interaction + the logged `'interpret'` entry are exercised by the existing
  end-to-end harness (`integration_test/ai_flows_test.dart`) for the Run/journal paths and
  are device-verified; this feature reuses that exact sheet, so the unit test covers only
  the new gating + button wiring (the highest-risk new surface).

## Files touched

**Changed**
- `lib/features/loop_pane.dart` — `_interpret()` + the gated `loop-interpret` button + 3 imports.
- `test/loop_pane_test.dart` — gating tests.

## Non-goals / deferred

- No auto-open of the sheet (one-tap button, not unprompted — keeps the player in control).
- No interpret on the `dock-ask-yes-no` dock chip (Loop pane only; keeps the dock lean).
- No shared `_interpret` helper extraction (premature; flagged above).
