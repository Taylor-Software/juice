# Play-loop UX audit — solo/GM TTRPG sessions

**Date:** 2026-06-21
**Method:** Hybrid. 7 code-grounded play-through agents (5 scenario lenses + spine/linking
+ tool-access traces) → cluster 80 raw findings into ranked opportunities → adversarial
verify each against real code (refute friction that already has a shortcut) → completeness
critic. Plus 5 live screenshots of the running web build to ground the feel.
**Deliverable:** evaluation + ranked improvement opportunities.

> **Status update (2026-06-21):** First increment shipped on `feat/play-context-hud` —
> **#3 persistent shell HUD** (lifted `_CampaignHeader` → `lib/shared/play_context_hud.dart`,
> mounted above the verb body, visible on every verb + on empty campaigns) and the
> **#2 `setActiveScene` wiring** it consumes (the HUD scene line follows `activeSceneId`).
> Resolves gaps **G3** (HUD was journal-only) and the live-confirmed "chaos buried" friction.
>
> **Increment 2 shipped (2026-06-21):** the **#1 result-card action mechanism** —
> `ResultCard` gained a reusable `actions` slot (`ResultAction` chips below the rolls,
> `lib/shared/result_card.dart`). First consumer wired: the Mythic result card offers a
> one-tap **"Random Event"** (`Oracle.mythicRandomEvent` = Event Focus + Action + Subject,
> folding a 3-step manual chain into one). The slot is the foundation for the remaining
> per-caller quick-actions (apply damage/heal, mark track, roll consequences, save-as-NPC) —
> those wirings stay open.
>
> **Increment 3 shipped (2026-06-21):** the **#7 Mythic advance-scene macro** — the New-scene
> dialog (`scenes_pane`) gained a "Roll Mythic Scene Test" toggle (shown only when `mythic` is
> enabled, default on). Creating a scene then rolls + logs the Scene Test, and on an
> *Interrupted* outcome also rolls a random event (`mythicRandomEvent`) — composing increment 1's
> spine wiring and increment 2's random-event combiner into one tap. Folds the Scene Test +
> new-scene + (interrupt→random-event) chain that was split across screens. Resolves gap **G2**.
>
> **Increment 4 shipped (2026-06-21):** gap **G8** — campaign export/import now preserves the
> campaign profile. The `.juice.json`/`.juice.zip` file carries `systems` + `mode`
> (`campaign_io.dart`, additive keys, no schema bump); import restores them onto the new
> `SessionMeta` and lands on the restored mode (was hardcoded party). Fixes imported GM/D&D
> campaigns mis-landing on the party home with the wrong systems.
>
> **Increment 5 shipped (2026-06-21):** **#6** — Shadowdark torch clock. The Shadowdark sheet
> gained a "Light" section with a `torch` countdown (`ShadowdarkSheet.torch`, a neutral
> player-controlled timer with −/+ steppers + lit/out indicator; 0 = out). Facts-only: no
> rulebook duration asserted. Gives the signature Shadowdark light-pressure mechanic a home.
>
> **Increment 6 shipped (2026-06-21):** **#5** — party-wide effect broadcast. Each roster group
> header (≥2 members) has an "Effect" button → a modal that applies ±N HP and/or condition(s) to
> a checkbox set of members in one gesture (`CharacterNotifier.applyPartyEffect`, persisted once).
> HP resolves per character via `Character.withHpDelta` (D&D/Shadowdark `currentHp` or first
> track; no-pool sheets unchanged). Replaces editing 3-5 sheets one by one for a fireball/heal.
>
> **Increment 7 shipped (2026-06-21):** the remaining **#1** per-caller result-card wirings,
> assessed and closed. Shipped: the Ironsworn move result card gains an **"Ask oracle"** action
> (one-tap 50/50 yes/no logged as a follow-up — the common post-move question, in place).
> The other enumerated wirings were assessed and intentionally NOT built (would be speculative or
> redundant): **save-as-NPC** is already covered (the contextual Generate-NPC roster flow creates
> the character directly; journal `gen-npcs` results have a context-menu "Save as character");
> **apply damage/heal** and **mark track** have no bound target on a *free* oracle/dice result —
> bulk damage/heal is delivered by #5 (party effect) + per-row/combatant HP editing, and
> event-driven clock ticks are the separate gap **G5** (not a result-card action). The reusable
> `ResultAction` slot remains available for any future caller that does have a bound target.
>
> **Increment 8 shipped (2026-06-21):** **#4 / G6** — persistent quick-roll. The shell HUD's
> always-visible row gained a dice button (`hdr-quick-roll`) that rolls the campaign's default
> oracle (Juice 50/50 / Mythic Fate Chart at current Chaos / Roll-High Unknown) and logs it, from
> **any** verb and even when the HUD is collapsed. The loop's most frequent action is now one tap
> everywhere, not buried in the Ask verb or the collapsed assistant rail.
>
> Remaining opportunities below are still open.

Scenario lenses played:
1. D&D party (multi-PC) + Mythic GME + Juice, party mode
2. Ironsworn solo (single PC)
3. Shadowdark + Mythic, single-PC player lens
4. Shadowdark + Mythic, party lens
5. GM guiding a live table via the party emulator (gm mode)

---

## The core finding: a hub with no spoke-to-spoke wiring

The play loop is **roll → interpret → record → mutate state → advance**, but the five verbs
(Journal / Sheet / Ask / Map / Track) are siloed. The *result* of one step almost never flows
into the next without the player manually re-navigating. The `PlayContext` spine
(`lib/state/play_context.dart`) was built to be the connective tissue — and it is barely wired:

- `setActiveScene` is **never called** anywhere in the app (0 refs); `activeSceneId` is a dead field.
- `setActiveCharacter` fires only on explicit roster/mention taps — not on combatant or
  emulator selection, and it's cleared on sheet-back, so by the time the player is in the
  Journal the active PC is `null` (which suppresses the "Make a move" suggestion chip).
- Every `ResultCard` offers exactly one action: **Add to journal**. No roll result can apply
  damage, mark a track, bump chaos, or advance a scene in place.

So the dominant, every-turn friction is **state mutation requires leaving the screen you're on**,
and the highest-leverage fixes are: (a) make results actionable in place, and (b) actually wire
the spine on the mutations that imply it. Those two collapse most cross-verb trips.

Live grounding (web build) confirmed the feel: Ask→Oracle is one long stacked page (Fate Check →
Roll High → Mythic, so the **Chaos Factor lives mid-scroll**); the **Assistant rail is collapsed
by default** (chips + Ask-GM one tap away, easy to miss); **Track is 7 horizontal subtabs**; and
the existing campaign header that *does* hold a chaos chip + oracle picker only renders inside the
Journal verb and only once the journal is non-empty — invisible on a fresh campaign and on every
other verb.

---

## Ranked opportunities

`Impact` = taps-saved × frequency × #scenarios. `EX` = a partial affordance already exists
(verifier-confirmed) → scope is the *refinement*, not net-new. File refs are entry points.

### Tier 1 — flagship loop-tighteners (build these first)

| # | Opportunity | Impact | Effort | Notes |
|---|---|---|---|---|
| 1 | **Outcome-aware quick-actions on every result card.** Turn `ResultCard`'s single `onLog` into a slot-based action row: apply damage/heal, mark vow/track, roll consequences/complications, bump chaos, save-as-NPC, advance scene — actions derived from the result's `sourceTool`/`outcome`. | HIGH | large | `lib/shared/result_card.dart:7` (only `onLog` today). The universal fix — hits all 5 scenarios, removes the "update state" cross-verb trip. |
| 2 | **Auto-wire the spine on implying mutations.** `setActiveScene(entryId)` inside `JournalNotifier.addScene`; `setActiveCharacter` on combatant/emulator/sidekick selection; surface (don't force) an "Advance to scene" chip. | HIGH | small | `lib/state/providers.dart:116`, `play_context.dart`. Cheap; unlocks suggestions, the context HUD, and richer Ask-GM downstream. |
| 3 | **Promote the campaign header to a persistent shell HUD.** The chaos chip+steppers, scene title, default-oracle picker, pinned threads/stars already exist — but live inside `JournalScreen`'s ListView, gated on `entries.isNotEmpty`, so they vanish on Sheet/Ask/Map/Track and on empty campaigns. Lift `_CampaignHeader` into the shell. | HIGH | medium | EX: `lib/features/journal_screen.dart:1695,1722,1761`; shell at `lib/shared/home_shell.dart:464`. Resolves "chaos buried" + "narrate blind". |
| 4 | **Persistent one-tap quick-roll.** A fate/oracle/dice roll one-tap only exists in the *collapsed* rail on the Journal verb. Add a shell-level quick-roll (FAB or HUD button) reachable from every verb. | MED-HIGH | medium | `lib/features/assistant_rail.dart:71,29`; `home_shell.dart:500`. Step-2 (roll) is the most frequent action; it should never be 3+ taps. |

### Tier 2 — scenario-defining gems

| # | Opportunity | Impact | Effort | Notes |
|---|---|---|---|---|
| 5 | **Party-wide effect broadcast.** One gesture to apply ±N HP / heal / condition(s) to a checkbox set of the party (default all). Today a "fireball hits the party" = open each of 3-5 sheets, edit, back out, repeat. | HIGH | medium | D&D-party, Shadowdark-party. `lib/features/tracker_screen.dart:~476`; `CharacterNotifier` only does single-char mutations today. |
| 6 | **Shadowdark torch / turn clock.** The signature 6-turn torch-burn pressure has no home — no sheet field, no campaign track. Add an optional torch resource (sheet field like the D&D slot strip) + a campaign-gated track seeded to 6. | HIGH | medium | Shadowdark lenses. `lib/features/shadowdark_sheet.dart`; keep the facts-only posture (a number + steppers, no prose). |
| 7 | **Mythic "advance scene" macro.** Unify the split loop-end: Scene Test (Fate screen) + new-scene (Track/Scenes) + chaos bump are three screens. One action: roll scene test → snapshot chaos → on Interrupt/Altered offer reroll → create scene → bump chaos → log. | HIGH | small-med | G2 + #7. `fate_screen.dart:254`, `scenes_pane.dart:72`. Most-repeated macro in solo Mythic play. |
| 8 | **GM emulator/voice shortcut chips.** In gm mode the party-emulator / sidekick / behavior tools sit 4-6 taps deep (verb change + scroll 8 subtabs). Add "Emulate \<activeName\>" / "Voice a line" rail chips that route + pre-select the active character. | MED | medium | GM table. `lib/engine/suggestions.dart`, `assistant_rail.dart`, `role_tags.dart`. |
| 9 | **End-of-encounter resolution dialog.** Ending an encounter silently clears combatants + round counter. Replace with a dialog: summary (optional Ask-GM), per-combatant "apply final HP/conditions to linked character", reset emulation. | MED | medium | GM, Shadowdark. `lib/features/encounter_screen.dart:269`. |
| 10 | **Live Character↔Combatant sync (finish it).** EX: HP read-through already exists (`encounter_screen.dart:113-129`). Missing: conditions, spell slots, NPC agenda/emulation render live on the combatant row. | MED | large | EX. Make the linked Character the source of truth where `characterId` is set. |
| 11 | **Encounter-aware landing + Sheet turn-order glance.** Party mode always lands on Sheet, burying an in-progress encounter. If combatants exist, land on Track→Encounter; add a "current turn" chip on the Sheet header. | MED | small | `lib/shared/destination.dart:11`; `EncounterState` in `providers.dart:503`. |

### Tier 3 — loop quality, linking, discoverability

| # | Opportunity | Impact | Effort | Notes |
|---|---|---|---|---|
| 12 | **Outcome-reactive suggestions.** The `SuggestionEngine` is static (6 booleans). Feed it the latest journal entry (kind/outcome) + active combatant: Miss→"Roll consequences", Mythic doubles→"Roll Event Focus", etc. | MED | medium | `lib/state/suggestions_provider.dart`, `suggestions.dart:36`. |
| 13 | **Richer (budget-safe) Ask-GM context + editable preview.** Today only the latest scene title (1-3 words) feeds the LLM. Add capped: scene + last 1-3 entries + active PC HP/conditions + chaos + combatants, with a collapsible preview. | MED | medium | `lib/state/interpreter.dart`; ~1280-token budget (`kAskGmMaxFieldChars`). |
| 14 | **Bi-directional backlinks.** EX: journal→character filter chips exist. Missing reverse: a "Mentions" badge on sheets, entry-count on threads, encounter→map `locationRef` jump. | MED | medium | EX. `journal_screen.dart:383,485`; `models.dart:1600`. |
| 15 | **One-tap "Save as character/NPC" from generator + emulator results.** EX: gen-npc results have a context-menu Save; emulator/behavior results log via `.add()` (no sourceTool) so they can't. Make it a first-class button. | MED | small | EX. `journal_screen.dart:238,581`. |
| 16 | **Discoverability bundle.** Slash-command hint ("Type / for commands"), label the unlabeled dice "magic icon" + add it to tool-search, badge the active oracle, show enabled-systems chips on campaign cards, reveal (greyed) mode-gated tools instead of hiding them. | MED | medium | EX (partial). `home_shell.dart:86,601`; composer hint. |
| 17 | **Causal grouping of journal entries.** Move + its complication/oracle currently render as two unrelated rows. Add optional `parentEntryId`; render children indented/collapsible. | LOW | medium | `journal_screen.dart`; pairs with #1. |
| 18 | **Inline conditions/status on open sheets.** Conditions live only on roster card chips → exit sheet → edit → re-enter (3-5 taps). Add a Status section to the sheets (respect Shadowdark's lean posture). | LOW | medium | `sheet_widgets.dart`, `shadowdark_sheet.dart`. |
| 19 | **Per-roll reroll + working backnav for home-less results** (dice/help dead-end source chip; reroll one sub-roll of a multi-roll NPC). | LOW | small | `dice_roller_screen.dart:182`; multi-roll payloads. |
| 20 | **Auto-prefill Ironsworn move stat stepper** (defaults to 2; ruleset has no stat field → resolve from active PC if possible). | LOW | small | `moves_screen.dart:166`. Verifier flagged limited value (no stat in ruleset JSON). |

### Outer-loop gaps (the critic caught these — none are intra-turn)

| # | Gap | Impact | Notes |
|---|---|---|---|
| G1 | **No session boundary.** Start/end-of-play is unmodeled. Add a `sessionBreak` entry / `lastPlayedAt` so "Continue" can offer a recap and end-of-session wrap. | HIGH | `launcher_screen.dart:159`. |
| G2 | Mythic scene-advance split across two screens → see #7. | HIGH | merged into #7. |
| G3 | Context HUD is journal-only → see #3. | HIGH | merged into #3. |
| G4 | **Map↔journal is one-way; `activeLocation` never set from the map nor used.** | MED | `map_screen.dart:393`, `play_context.dart:49`. |
| G5 | **Tracks/clocks are inert dials** — no event-driven tick, no fill→fire→journal closure. | MED | `tracks_pane.dart:61`. Pairs with #1/#12. |
| G6 | Quick-roll only in collapsed rail → see #4. | MED | merged into #4. |
| G7 | **Recap/voice output buried** — `summarize` shows a throwaway dialog, not persisted as an entry. | MED | `journal_screen.dart:220`. |
| G8 | **Import hard-resets mode to party** ("files carry no mode") → imported GM campaign mis-lands on Sheet with Rumors hidden. Persist mode in the campaign file. | MED | `launcher_screen.dart:75`, `home_shell.dart:280`. Closest thing to a bug here. |

---

## Recommended next-build set

If picking a small high-leverage slice to spec next:

1. **#2 spine auto-wiring** (small, HIGH) — foundation everything else leans on.
2. **#1 outcome-aware result-card actions** (large, HIGH) — the universal loop-tightener.
3. **#3 persistent HUD** (medium, HIGH) — lifts an existing widget; immediate "I can see my game" win.
4. One scenario gem to prove the pattern end-to-end: **#7 Mythic advance-scene macro** (small-med) or **#5 party-wide effects** (medium).

Plus **G8** as a quick correctness fix (import drops campaign mode).

---

## Method notes / caveats

- All findings are file:line-grounded; the verify pass refuted 5 opportunities down to "partial —
  affordance exists" (#3/10/14/15/16) rather than net-new — honored above as EX.
- Live driving used the Flutter web build (CanvasKit). The on-device LLM is **disabled on web**, so
  the AI-assisted half of the loop (Ask-GM/voice/recap) was assessed from code, not felt live.
- Minor branding nit spotted live: the **launcher H1 still reads "Juice"**; the in-shell title bar
  correctly reads "Solo Adventurer's Journal".
- Workflow run: `wf_93bc1051-5d7`, 29 agents, ~1.9M tokens.
