# Backlog + play-loop audit — 2026-06-30

Run after the major epics (UX refresh, Streamline, Content library, Rules-reference,
AI expansion, GM Run-screen) all closed. Three parallel scans: open-deferred
inventory, play-loop UX gaps, code health. Goal: find the next high-value work.

## Headline
- **Code health is clean** — no TODO/FIXME, no orphaned files, no dead code; debug
  prints are confined to the intentional `runInterpreterEval`. Cleanup is NOT the
  next thing.
- **The signature Solo Loop has cheap, high-value friction** — several small gaps
  in `loop_pane.dart` that, fixed together, harden the app's core differentiator.
- **A general expression parser** is the one architectural gateway: it unblocks
  rollable attacks + custom computed-on-computed + complex cross-block refs. Higher
  effort, niche-ish payoff (the computed-extension spec already judged it niche).

## Recommended next: "Solo Loop polish" pack (cheap, cohesive, signature feature)
All in `lib/features/loop_pane.dart` unless noted. One PR.
1. **Scene title at creation** [high] — step 1 hardcodes `addScene('New scene')`;
   no inline rename. Add a one-field dialog/inline field so the title is set on
   creation. (`loop_pane.dart` `_newScene`)
2. **Step 4 inline task-create** [high] — step 4 is a dead-end ("Add one on a
   thread (Track → Threads)"). Add an inline name field + "Track it" that does
   `addReturningId` + `setTally` (now also reachable via the new Tasks pane #229,
   but the loop step itself should self-serve).
3. **Step 5 capture send button** [med] — capture field only fires on
   `onSubmitted`; add an `IconButton(Icons.send)` suffix matching the Run Capture
   panel. Mobile keyboards don't reliably fire submit.
4. **Loop position/result survives navigation** [med] — `_last`/`_odds`/`_capture`
   are widget-local and reset on every tab switch; move to a lightweight ephemeral
   provider so a mid-loop roll/result/typed note survives leaving to log.
5. **Tally roll inline + auto-apply** [low-med] — `roll-tally` result is a 4s
   snackbar; log a `tally-roll` entry and offer auto-apply of the win/fail
   adjustment (undo snackbar). Show the last result under the step-4 row.

## Second: cheap cross-cutting wins (independent, could batch)
- **AI rank churn** [med] — `assistant_rail.dart` re-ranks on EVERY new entry
  (`_signature` keys on `journal.first.id`); on a fast AI session that's a Gemma
  inference per action. Coarsen to scene/result entries or add a min inter-call
  gap. (`assistant_rail.dart:39-77`)
- **GM chat "Clear"** [med] — `gm_chat_screen.dart` has no way to start a fresh
  conversation; stale transcript bleeds across sessions. Add a clear button →
  `gmChatProvider.notifier.clear()`.
- **Track orientation card** [med] — 9 Track subtabs, no first-run explanation of
  which does what. A dismissible "what's here" card on Track/Home.
- **Recap banner "Never"** [low] — `journal_screen.dart` recap banner reappears
  every session; add a persistent opt-out (mirror `aiNudgeSeenProvider`).

## Third: GM live-table depth (meatier, GM-mode value)
- **Run dice panel: ad-hoc dice + likelihood** [high for GM] — `_DiceOraclePanel`
  has only one fixed-odds oracle button; surface a dice-notation field + likelihood
  selector inline (machinery already exists). (`run_screen.dart:635-744`)
- **End Encounter → advance thread** [high] — `_EndEncounterDialog` writes a
  journal note but can't tick a thread's progress clock; add an optional thread
  selector + progress tick to close fight→goal→log in one gesture.
  (`encounter_screen.dart:744-792`)
- **Combat conditions sync back to character** [med] — conditions added on a
  combatant don't mirror to a linked `Character`; mirror on edit or at
  encounter-end. (`encounter_screen.dart`, `EncounterNotifier.setConditions`)

## Larger / blocked (not now)
- **Expression parser** — gateway for rollable attacks + computed-on-computed +
  complex refs. Real, but its dependents are niche per their own specs.
- **GM Tier-3 multiplayer fork** — big architectural bet; needs its own brainstorm.
- **Content (blocked):** Shadowdark/Kal-Arath (no app license), Nimble/Draw Steel
  (stat math doesn't fit `StatBlock`; needs books), SRD 5.2 (needs a 2024 source
  vendored + edition wiring).
- **AI enhancements:** per-campaign override, model unload on disable, edit/delete
  GM turns, auto-summarize old turns. Nice-to-have, not friction.

## Notes on inventory accuracy
The raw deferred-scan over-counted ~several already-shipped items (Tasks pane #229,
custom cross-block refs #194, loop auto-interpret #224, hexcrawl site interior).
Treat the spec "Deferred:" sections as leads to verify against code, not truth
(consistent with the roadmap-stale-docs finding).
