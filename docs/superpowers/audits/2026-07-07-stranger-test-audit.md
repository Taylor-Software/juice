# Stranger-Test Audit — Wedge Phase 4 (simulated)

**Date:** 2026-07-07
**Method:** Live first-session drive of the real macOS app (launcher → creation
wizard → Play → first oracle roll → Solo Loop → scene → ask), transcribed
screen-by-screen, then independently critiqued by three fresh-context persona
agents with zero session knowledge:
- **Sam** — video-game RPG player, zero TTRPG experience ("app that GMs D&D")
- **Rivka** — 10-year Mythic GME 2e veteran, evaluates against paper workflow
- **Marcus** — 5e group player (never DM), expects "the app is my DM"

This simulates, not replaces, the roadmap's "5 real strangers" — see the
companion kit `docs/stranger-test-kit.md` for running the human sessions.

## Convergent stalls (all three personas independently)

| # | Stall | Personas | Severity |
|---|-------|----------|----------|
| S1 | **The question is never captured.** The `? Yes/No` dock chip, the big empty-state "Roll oracle", and the Solo Loop Ask step all roll with no way to type the question. Result cards and journal entries read "Yes (d10=4)" — an answer to nothing, worthless in the log later. | all 3 (top-ranked twice; "structurally disqualifying" — Rivka) | quit-risk |
| S2 | **First-tap "Roll oracle" is jargon soup.** "FATE CHECK / Yes But + Random Event / Mundane (d6 3) / (003)" with no question asked, no plain-language next step. Every persona read it as broken output. | all 3 | quit-risk |
| S3 | **Solo Loop Steps panel clips.** Step 2's title cut mid-word, steps 3–5 invisible, no scrollbar/fade/chevron. The one place that plainly teaches the loop ("Roll a d10 yes/no") is effectively hidden. | all 3 | quit-risk / friction |
| S4 | **Second "Next beat" tap shows nothing.** State changes off-screen (assistant chips); the primary pane looks frozen → "is it broken?" | all 3 | friction |

## Secondary stalls

| # | Stall | Personas | Severity |
|---|-------|----------|----------|
| S5 | **The premise is never stated.** Nowhere in welcome card → wizard → empty state does the app say: *there is no DM; you narrate; the oracle answers questions you ask.* Marcus (the wedge's target D&D user) bounces at S2 because of this. | Marcus (core diagnosis), Sam | quit-risk |
| S6 | **"Juice" brand collision.** Launcher H1 says "Juice" while the window says "Solo Adventurer's Journal"; the wizard pre-selects a "Juice" oracle chip with no explanation vs Mythic. (Also violates the repo's own display-name rule.) | Rivka, Sam | friction |
| S7 | **AI-offer copy oversells.** "Bring the oracle to life… voice NPCs, recap" reads as "the AI is the DM" (Marcus taps download expecting a narrator); never says "you still narrate". | Marcus | quit-risk (expectation debt) |
| S8 | **Wizard jargon.** "12 surfaces active" (dev-speak), "0-level funnel — start with a group of peasants", role cards that don't say which one means "the app acts as GM". | Sam, Marcus | friction |
| S9 | **Chaos factor not visible on Play HUD for a Mythic campaign.** Rivka's single most load-bearing number; the Light timer gets HUD space instead. (Verify gating: chaos chip may require the scene HUD expanded state.) | Rivka | friction (quit-risk for Mythic natives) |
| S10 | **"Track Random? / Track Event?" chips unexplained**; a mis-tap on ✕ deletes with only a tooltip. | Sam, Rivka | cosmetic |

## What beat paper (Rivka)

Auto-persisted chaos/threads across sessions; auto-logged rolls with
timestamps; Mythic as a first-class setup choice.

## Fixes shipped in this PR (F# → S#)

- **F1 (S1/S2):** Ask-with-question — the `? Yes/No` dock chip and the Loop Ask
  step gain an optional question field; the question is stored on the entry
  title/body so the result card and journal read "Q: … — Yes (d10=4)". The
  empty-state primary action becomes ask-first.
- **F2 (S3):** Steps panel no longer clips — visible scroll affordance + no
  mid-card cut.
- **F3 (S4):** Every Next-beat tap gives visible feedback (snackbar naming the
  now-current step).
- **F4 (S5):** Premise line added to the Play empty state and the welcome card:
  "There's no DM — you narrate. Ask a question, roll, then write what happens."
- **F5 (S6):** Launcher H1 uses the product name (display-string only; the
  Juice oracle system keeps its name per repo rules).
- **F6 (S6/S8):** One-line subtitles on the wizard's oracle chips; "surfaces"
  preview label reworded; role-card copy says which stance means "the oracle
  acts as GM".
- **F7 (S7):** AI-offer body gains "You still narrate — the AI adds flavor to
  the answers."

## Deferred (needs the real humans / bigger design)

- S9 chaos-on-HUD for Mythic (verify gating first; possibly a per-oracle HUD
  chip) — candidate for the human-test round.
- S10 tracking-chip explainers.
- Roadmap kill-list check ("items no stranger reached for": init modifiers,
  pacing timers, edition toggle) — only real humans can answer reach-for.
