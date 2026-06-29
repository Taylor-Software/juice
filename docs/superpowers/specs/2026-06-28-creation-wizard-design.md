# Campaign Creation Wizard (3-step)

**Date:** 2026-06-28
**Status:** Design approved (interactive + mockup); pending build.
**Builds on:** the presets-first creation (#162/#163) and the mode-gating retirement (#202). PR2 of the wizard work — PR1 (#202) was the foundation.

## Summary

Rework `NewCampaignDialog` from a presets-first single dialog into a **guided
3-step wizard**: *who are you?* → *system + tools* → *how to start characters*.
Mode (`{gm, party}`) is unchanged; the wizard's stance choice is framing/setup.

## Steps

### Step 0 — Stance ("Who are you at the table?")
- Campaign **name** field at top.
- Three selectable stance cards:
  - `new-stance-gm` **GM, live table** → `mode = gm`.
  - `new-stance-solo-gm` **Solo, as GM** → `mode = party`, `soloLead = false`.
  - `new-stance-solo-member` **Solo, as a member** → `mode = party`, `soloLead = true`.
- `soloLead` is **framing only** (step-2 default + wording) — NOT persisted; both
  solo stances are `party` mode (the 2-mode model is kept per #202).
- Default selection: solo-member.

### Step 1 — System + tools
- Ruleset `ChoiceChip`s (incl. `ruleset-none`) — single-select (reuse the current
  custom-picker ruleset chips: `ruleset-<id>`).
- Addon `FilterChip`s grouped by `SystemCategory` (oracle / exploration / tools) —
  `cat-<id>` (reuse current). Default addons `{juice, party}`.
- The live `CampaignPreviewPane(systems: …)` below.
- **No mode toggle** (stance set it in step 0). The stale "GM hides party tools"
  hint is gone (mode no longer gates tools after #202).

### Step 2 — Start ("How do you start characters?")
- Genre + tone optional fields.
- Funnel-vs-roster choice:
  - `new-start-funnel` **0-level funnel** — shown/enabled only when the chosen
    ruleset has a funnel (`funnelProfileFor(_ruleset) != null`); else hidden.
  - `new-start-roster` **Start with a roster** — always; the default.
- **Create** button (enabled when name non-blank).

## Navigation

A lightweight paged dialog (`int _step` 0..2 + Back/Next/Create), not Material
`Stepper` (cramped at the 460px dialog width). A 3-dot step indicator at top. Next
is disabled until the step's required choice is made (step 0 needs a stance; step
1 always satisfiable). Create only on step 2.

## Result + post-create wiring

The dialog returns an extended record:
`({String name, Set<String> systems, CampaignMode mode, String genre, String tone, String start})`
where `start` ∈ `{'roster', 'funnel'}`. When `start == 'funnel'`, the returned
`systems` **includes `'funnel'`** (auto-added so the funnel sheet renders), and the
seed system is the chosen ruleset (or `'dcc'` when the ruleset lacks a profile).

`_newCampaign` (home_shell) after `create(...)`:
- `landFor(mode)` (unchanged — gm→Run, party→Sheet).
- if `start == 'funnel'`: `await charactersProvider.notifier.addFunnel(seedSystem)`
  then `goTo(Destination.sheet)` (the funnel entity lives in the roster).
- if `start == 'roster'`: nothing extra (landing already shows the roster/run).
  (Auto-opening the add-character flow is deferred — keep it lean.)

The seed system is recomputed caller-side from the result (ruleset in `systems`
with a funnel profile, else `'dcc'`), OR carried on the record as a `seedSystem`
field — implementer's choice; carrying it on the record is cleaner.

## Presets

The preset grid (`_PresetRow`/`_BrowseAllRow`/`kCampaignPresets`) is **folded out**
of the dialog — the wizard's steps 1–2 cover the same ground explicitly. Keep the
`kCampaignPresets` data + `presetConfig` (still referenced elsewhere / by tests);
just stop rendering the grid here. A "quick start" shortcut that pre-fills the
wizard from a preset is a **deferred** follow-up.

## Testing

`test/` (widget — extend the existing creation tests / `home_shell` harness):
- Step 0: three stance keys present; selecting `new-stance-gm` then walking to
  Create yields `mode == gm`; solo stances yield `party`.
- Navigation: Next advances; Back returns; Create only on step 2; Next gated until
  a stance is chosen.
- Step 1: ruleset single-select + addon toggles flow into the result `systems`;
  preview pane present.
- Step 2: `new-start-funnel` shown only for a funnel-capable ruleset (e.g. dcc/
  dnd/shadowdark) and hidden for a non-funnel ruleset (e.g. ironsworn) / none;
  choosing funnel puts `'funnel'` in `systems` + `start == 'funnel'` + seedSystem.
- Caller: creating with `start == 'funnel'` calls `addFunnel(seedSystem)` (a funnel
  Character exists after) and lands on Sheet; `start == 'roster'` does not.
- Rewrite/replace the old preset-grid creation tests (`preset-*`, `preset-custom`,
  `preset-back`) to the wizard flow.

## Out of scope (deferred)

- "Quick start" presets that pre-fill the wizard.
- Auto-opening the add-character sheet after a roster start.
- A persisted solo-GM vs solo-member distinction (framing only here).
- Editing flow (`_EditSystemsDialog`) — unchanged.
