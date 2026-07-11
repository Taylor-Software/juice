# Tool Evaluation Audit — concept, implementation, UI/UX, ease of use

**Date:** 2026-07-11
**Method:** three-track evaluation — (1) live hands-on drive of the freshly
built release web app (fresh localStorage, desktop 800×450 + mobile 375×812),
(2) fresh-context concept/product-coherence review, (3) implementation-quality
review (architecture, tests, persistence, duplication). `flutter analyze`
clean; full test suite green (2031 tests).

## Verdict by dimension

| Dimension | Grade | One-liner |
|---|---|---|
| Concept | A− | The wedge ("a loop machine") is right, self-diagnosed, and Phases 0–3 verifiably shipped; remaining gap is first-run routing, not strategy. |
| Implementation of concept | B | Engine/UI split genuinely held, 2031 green tests, loop/kit/wizard all work as specced — but persistence parsing is brittle and three god-files absorb all growth. |
| UI/UX | B− | Desktop play loop is good post-stranger-test fixes; the loop Steps panel still clips (S3 residue), the HUD carries dead chrome, mobile Play drowns the journal in chrome. |
| Ease of use | B− | A stranger who finds the wizard + kit path starts a themed session in <60s (verified). But the default first-run path routes AROUND all of it into a legacy-shaped "Campaign 1". |

## What verifiably works (live-drive evidence)

- Launcher premise card + product name (F4/F5) — correct on fresh run.
- Ask-first flow (F1/F2): empty-state "Ask the oracle" → question + odds →
  entry logs as "Q — Yes (d10=2)", answer snackbar. The core loop artifact is
  now an answered question.
- Solo Loop bar: Next beat is contextual ("— Name the scene" → "— Ask
  oracle"), scene lands on the HUD, scene divider + body log to the journal.
- Creation wizard Phase 0: 4 primary rulesets + "Experimental systems"
  drawer + one-line oracle explainers.
- Kit path Phase 3: "Import a kit" → Create lands in Play with a themed
  starter scene ("The Door Was Sealed From Inside") already journaled. <60s.
- Web AI posture: on-device LLM affordances correctly hidden on web.

## Findings (ranked)

### F1 — First-run routes around the wedge (quit-risk, ease-of-use)
`SessionsNotifier.build()` (`lib/state/providers.dart:2298`) fabricates
`SessionMeta(id:'default', name:'Campaign 1')` on first run; its null
`enabledSystems` falls back to legacy `kAllSystems`
(Ironsworn·Mythic·Juice·Party·Verdant), and the launcher's primary CTA is
"Continue · Campaign 1". A brand-new user is routed past the wizard, the
3-system pick, the kit path, and the D&D wedge — into the one campaign shape
the roadmap explicitly de-emphasized. All the Phase 0–3 onboarding is only
reachable by spotting the smaller "New campaign" row.

### F2 — Loop Steps panel still clips and mis-lays-out (S3 residue)
The loop bar caps at 45% of body height inside a `SingleChildScrollView`
with no scrollbar/fade affordance (`lib/features/loop_bar.dart:628-657`),
and the Steps `ExpansionTile` centers intrinsic-width cards. Observed live:
desktop shows only step 1 centered in dead gutters (steps 2–5 undiscoverable);
mobile clips the step-1 card mid-button. The one surface that teaches the
loop is still effectively hidden — for the second audit running.

### F3 — Persistence parsing is brittle; two keys leak (implementation)
Most session-scoped notifiers parse `fromJson(jsonDecode(raw))` unguarded —
including the master `SessionsState` (`providers.dart:2295`), `CrawlState`
(:749), decks (:782), factions (:903), encounter (:960), map (:1095),
settings (:1739), and every `_PersistedList` row (:78). One corrupt pref
value → permanent `AsyncError` that the `valueOrNull ?? []` UI convention
renders as a silent empty screen (for sessions: a bricked app, no signal).
Also `juice.suggestDismissed` + `juice.recap` build scoped keys but are NOT
in `sessionScopedKeys` → orphaned on campaign delete, unmigrated, unexported.

### F4 — HUD dead chrome on every campaign (UI/UX)
The ungated "Light: out" chip + steppers sit on the always-visible HUD of
every fresh campaign (`lib/shared/play_context_hud.dart:147`) — negative-
reading noise for the 99% of campaigns that never use a light timer. Chaos
renders twice when expanded (chip + steppers).

### F5 — Mobile Play drowns the journal (UI/UX; wedge form factor)
At 375×812 the HUD + loop bar + Steps + Assistant chrome consume ~90% of the
viewport before any journal content; the composer squeezes to a two-line
sliver; dock chips overflow off-screen. The wedge user is "phone in hand".

### F6 — No inspiration at the scene-naming moment (concept/ease)
The New-scene dialog is a bare title field. The scene generator, word
oracle, and starter-kit scenes all exist — but none is offered at the one
moment a stranger stares at "Scene title…" with nothing to say.

### F7 — Structural debt (implementation, slow-burn)
`models.dart` 5,278 / `providers.dart` 2,950 / `journal_screen.dart` 2,860
lines; ~1,200 lines of near-identical config-dialog boilerplate in
`custom_sheet.dart`; `journal_entry_tile.dart` (710 lines, the journal's
per-entry surface) has zero test coverage. Campaigns drawer carries 8
import/export rows crowding 2 primary actions.

## Enhancement list (ranked, with disposition)

1. **First-run start flow** — no legacy auto-campaign as the primary path:
   fresh install's primary CTA opens the creation wizard (kit path included);
   the untouched default campaign no longer front-runs the wedge. → **ship
   now (E1)**
2. **Loop Steps panel rework** — stretch cards, visible scroll affordance,
   compact/mobile-aware steps so the loop teacher is actually readable. →
   **ship now (E2)**
3. **Persistence hardening** — tolerant parse on every session-scoped
   `fromJson` + per-row list recovery + register the two leaked keys. →
   **ship now (E3)**
4. **HUD de-noising** — gate the Light chip behind first use (or a
   setting), de-duplicate Chaos. → ship next
5. **Scene-seed in the New-scene dialog** — one "Roll a seed" chip reusing
   the scene generator/word oracle. → ship next
6. **Mobile Play compaction** — collapse Assistant + Steps by default on
   narrow width; single-row dock. → needs design pass
7. **Campaigns-drawer regrouping** — fold the 8 pack/kit rows under
   "Import / Export…". → cosmetic
8. **`custom_sheet` config-dialog generic + `journal_entry_tile` tests +
   god-file splits** — refactor track, schedule when touching those files.

## Kill-list check (wedge Phase 4)

Nothing in this evaluation argues for new systems, new AI seams, or new
sheets. The three ship-now items are all "make the existing wedge reachable
and durable" work — consistent with the roadmap's "subtract, don't add".
