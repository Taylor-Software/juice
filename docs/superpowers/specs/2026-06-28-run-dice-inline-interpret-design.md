# Run-screen dice: inline AI interpret (Tier-2)

**Date:** 2026-06-28
**Status:** Approved (batch consent); shipped same PR.
**Part of:** GM-tool epic, Tier-2 — the inline-interpret slice re-scoped out of the
run-screen-polish PR (#199). Completes the Run-screen dice panel.

## Summary

Make the Run-screen dice panel's aiReady-gated Interpret button actually
interpret the last roll inline (the on-device LLM via the shared
`OracleInterpretationSheet`) instead of routing to the Journal verb.

## Design (`lib/features/run_screen.dart`)

- `_DiceOraclePanel` becomes a `ConsumerStatefulWidget` holding `GenResult?
  _last`. `_roll` stores the rolled result (`setState(() => _last = g)`) in
  addition to logging it.
- The Interpret button shows only when `aiReady && _last != null` (a result
  exists). `onPressed` → `_interpret`:
  - builds an `OracleSeed` from `_last.asText` + the active scene
    (`activeSceneEntry` title/body) + `activeCharacterLineProvider` +
    `systemPrimerProvider` + campaign genre/tone;
  - shows the shared `OracleInterpretationSheet` (same sheet the journal uses);
  - on accept, logs a new journal entry via `addResult('Oracle reading',
    '(${lens}): ${reading}', sourceTool: 'interpret')` — a follow-up entry, so
    no need to thread the rolled entry's id.
- Recall is omitted for this quick path (the journal's per-entry Interpret keeps
  full recall); the seed still carries result + scene + PC + primer.

## Testing

- Existing: with AI off, the Interpret button is absent after a roll.
- New: with AI ready, the button is absent before any roll and appears after a
  roll. (The full sheet→log flow rides on the journal interpret tests + the
  `ai_flows` integration harness.)

## Out of scope

- Recall-ranked journal context in the run-screen seed (journal interpret has it).
- Appending to the rolled entry instead of logging a separate reading.
