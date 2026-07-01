# Cut-to-the-Wedge Roadmap

_Dated 2026-06-30. Strategic roadmap, not an implementation plan. Supersedes the
feature-breadth trajectory. Each item is Core / Freeze / Cut — everything either
serves the loop or gets off the critical path._

## The wedge (one sentence)

**The best guided solo-play loop — scene → ask → interpret → journal → track —
for the handful of systems you actually run.**

Not a sheet library. Not a VTT. Not an oracle grab-bag. A loop machine.

Target user: the solo player mid-session, phone in hand, who needs the next
prompt _now_ and wants the session to feel like it's going somewhere. That
person already exists in the app (the Solo Loop pane). This roadmap makes the
whole app orbit it.

## Chosen d20 system: **D&D 5e**

The wedge must ship _complete_. D&D 5e is the only d20 option shippable complete
today — full SRD 5.1/5.2 spells + monsters already vendored. Shadowdark would be
tighter/more solo-native but ships no content (licensing). Content beats fit.

## Triage

### CORE — invest
- Solo Loop pane + Tally / Tasks
- PlayContext spine (scene / PC / location focus)
- Journal (the loop's artifact — the thing the user keeps)
- Oracle engine: Juice + one yes/no + Mythic-style chaos
- 3 systems deep: **Ironsworn family, D&D 5e, Cairn**
- Custom tables (only cheap moat)
- ONE LLM seam: interpret the oracle result in-fiction

### FREEZE — keep, zero new work
Card/tarot oracles, dice animation, sketch/PDF annotation, hexcrawl toolkit,
GM run-screen, party emulator, bestiary, quick-ref cards, funnel, campaign
search, backup nudge. All shipped, all fine, all off the critical path. No new
PRs, no polish, no follow-ups.

### CUT from default — hide behind "Experimental", stop the attention tax
- Facts-only empty sheets: Kal-Arath, Nimble, Draw Steel, Argosa, Knave, OSE,
  DCC, Shadowdark, Custom-as-headline. They front-door a sheet with no rules
  content = negative value. Code stays; their claim on the roadmap ends.
- GM/Party mode as a _headline_. Solo is the wedge. GM run-screen freezes; the
  mode toggle stays but stops shaping the roadmap.
- On-device-LLM-only religion (see Phase 2).

Deleting code is not the point — deleting these systems' claim on future
attention is. Sheet #14 stops generating specs, plans, quick-ref cards, blurbs.

## Phases

### Phase 0 — Declare the wedge
- Rewrite product one-liner + README H1 around the loop.
- d20 pick: **D&D 5e** (decided).
- Move the non-core sheets into an "Experimental systems" drawer behind a
  toggle in the creation wizard. Mechanical PR.

**Success:** launcher + creation wizard show 3 systems + "more (experimental)".
New user isn't drowned.

### Phase 1 — Make the loop unmissable
- Loop becomes a first-class destination, not a Track subtab. Solo campaigns
  land on the loop, not the journal.
- One-tap "Next beat" that does the smart thing from context (no scene → prompt
  scene; scene set → offer ask / inspire / interpret). Checklist is for
  learning; the button is for playing.
- Interpret-in-line: oracle roll + LLM interpretation render _in_ the loop,
  logged automatically, no navigation. The loop is the reading surface.

**Success:** a full solo session playable without leaving the loop screen.
Navigation events per beat near zero.

### Phase 2 — Fix the AI value gap
- Bring-your-own-key cloud LLM path (optional). Paste an Anthropic/OpenAI key →
  interpretation quality jumps, works on web, no 2.6GB download.
- On-device stays as the private/offline default. Cloud is the "I want it good"
  tier.
- Collapse the 5 AI seams to the ONE on the loop: interpret. Freeze
  narrate / gm-chat / flesh-out / rank-suggestions.

**Success:** interpretation good enough that users keep it on.

### Phase 3 — The only affordable moat
- Shareable loop kits: custom tables + ref cards + a starter scene, bundled
  (builds on the existing `.tables.json` pack path).
- Paste-a-link-get-a-kit import, friction-free.
- Seed with 5–6 authored kits for the 3 core systems. Community optional.

**Success:** a stranger imports a kit and starts a themed solo session in < 60s.

### Phase 4 — Validate with actual strangers (starts now, ongoing)
- 5 people who aren't the author play one full solo session each.
- Watch where they stall — that's the real next phase.
- Kill roadmap items no stranger reached for (candidates: init-modifiers,
  pacing-timers, edition-toggle).

## Explicitly refused
- No sheet #17.
- No new AI seam.
- No GM/multiplayer fork (Tier-3 stays deferred).
- No polish on frozen features.
- No new licensing-blocked system.

Each feels productive. Each is drift.
