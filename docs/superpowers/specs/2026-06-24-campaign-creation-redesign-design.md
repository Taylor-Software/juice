# Campaign Creation Redesign — Design

**Date:** 2026-06-24
**Status:** Approved (brainstorming) → ready for plan
**Goal:** Replace the flat 15-checkbox campaign-creation dialog with a presets-first
flow (P1) that streamlines what players see based on campaign decisions, then a
grouped multi-step wizard with live preview (P2). Pre-release — no backward compat.

---

## Problem

Today (`NewCampaignDialog` in `lib/shared/home_shell.dart`) campaign creation is a
mode toggle (`new-campaign-mode` Party|GM) plus **15 flat `sys-*` checkboxes** with
no grouping, no guidance, and defaults seeded from `kAllSystems`
(`{juice, mythic, ironsworn, party, verdant}`). Observed problems:

1. **The wall.** A new solo player faces 15 unlabeled toggles and can't tell oracles
   from sheets from tools.
2. **Sheets pretend to be independent.** 9 character-sheet systems (soon 10 with OSE),
   each its own checkbox — but a campaign realistically uses **one** ruleset. The
   checkbox model invites turning on several, cluttering the roster "new sheet" picker.
3. **Dead toggle combos.** `party` system + GM mode = the emulator/sidekick/behavior
   subtabs stay hidden anyway (mode wins via `role_tags.visibleForMode`). `ironsworn` +
   GM mode hides Moves. Nothing surfaces this at creation.
4. **Defaults fight intent.** `kAllSystems` defaults-on Ironsworn + Mythic + Juice +
   Party + Verdant. A D&D campaign inherits Ironsworn noise and must hunt for `dnd`.

---

## Ground truth — the systems and what they gate

16 systems total (assumes OSE — PR #161, currently open — has merged; it is the 10th
ruleset). `kAllSystems` = `{juice, mythic, ironsworn, party, verdant}` (creation
defaults, all toggleable; a campaign may legally have zero).

| System | Category | Gates |
|---|---|---|
| juice | oracle | Juice oracle tab (Ask) |
| mythic | oracle | Mythic GME Fate Chart + meaning tables (Ask) |
| cards | oracle | Cards/tarot/spreads section (Ask/Fate), HUD quick-draw, `/card` `/tarot` `/spread` |
| ironsworn | ruleset | Ironsworn/Starforged/Sundered sheets + `new-*` roster actions; Moves subtab (party mode only) |
| dnd | ruleset | D&D 5e sheet + `new-dnd`; spell slots |
| shadowdark | ruleset | Shadowdark sheet + `new-shadowdark`; torch |
| nimble | ruleset | Nimble sheet + `new-nimble`; wounds; adv/dis |
| draw-steel | ruleset | Draw Steel sheet + `new-draw-steel`; power rolls |
| argosa | ruleset | Argosa sheet + `new-argosa`; roll-under; Luck; Stagger |
| cairn | ruleset | Cairn sheet + `new-cairn`; d20-under saves; Deprived; Fatigue |
| knave | ruleset | Knave sheet + `new-knave`; d20+score saves; inventory slots |
| ose | ruleset | OSE/B-X sheet + `new-ose`; d20≥target saves; THAC0 |
| verdant | exploration | Verdant Journey tab (Map) |
| hexcrawl | exploration | Hexcrawl tab (Map); region/dungeon/site generators |
| party | tools | Emulator/Sidekick/Behavior subtabs (Track, party mode only); `make-move` chip |
| lonelog | tools | Resources + Battle panes (Track); Lonelog legend (Ask) |

**Mode** (`CampaignMode {gm, party}`, default party): `rumors` is GM-only;
`emulator`/`sidekick`/`behavior`/`moves` are party-only; everything else both.
`landingDestination`: gm→Track, party→Sheet.

**AI** is app-global (`juice.ai_enabled.v1`), NOT a campaign setting — out of scope here.

---

## Design

### Section 1 — category model (the spine)

A new authored constant tags every system with one category:

```dart
enum SystemCategory { ruleset, oracle, exploration, tools }

const kSystemCategory = <String, SystemCategory>{
  'ironsworn': SystemCategory.ruleset,
  'dnd': SystemCategory.ruleset,
  'shadowdark': SystemCategory.ruleset,
  'nimble': SystemCategory.ruleset,
  'draw-steel': SystemCategory.ruleset,
  'argosa': SystemCategory.ruleset,
  'cairn': SystemCategory.ruleset,
  'knave': SystemCategory.ruleset,
  'ose': SystemCategory.ruleset,
  'juice': SystemCategory.oracle,
  'mythic': SystemCategory.oracle,
  'cards': SystemCategory.oracle,
  'verdant': SystemCategory.exploration,
  'hexcrawl': SystemCategory.exploration,
  'party': SystemCategory.tools,
  'lonelog': SystemCategory.tools,
};
```

- **Ruleset** is the only single-select category at creation (radio). "System-agnostic"
  = pick none. The data model still *allows* multiple ruleset systems on a campaign
  (Edit Systems keeps multi-toggle for power users) — single-select is a creation-time
  default, not a hard constraint.
- `ironsworn` is a ruleset that also carries oracle/moves flavor; it stays in `ruleset`,
  and its Moves subtab keeps the existing `ironsworn + party-mode` gate.
- A completeness test asserts every member of the full system set appears in
  `kSystemCategory`, so a new system can't be added uncategorized.

This constant is pure data — no behavior change on its own. Both P1 and P2 read it.

### Section 2 — preset set (P1)

```dart
class CampaignPreset {
  final String id;
  final String label;
  final IconData icon;
  final CampaignMode mode;
  final Set<String> systems;
  const CampaignPreset({...});
}

/// Pure: resolves a preset to the (mode, systems) a new campaign is created with.
(CampaignMode, Set<String>) presetConfig(CampaignPreset p) => (p.mode, p.systems);
```

Presets are **lean** — a working baseline, not everything. Extras come from the P2
add-on step or Edit Systems.

**Ruleset presets** — each: `mode: party`, `systems: {<ruleset>, juice, party}`:
Ironsworn / Starforged · D&D 5e · Shadowdark · Nimble · Draw Steel ·
Tales of Argosa · Cairn · Knave 2e · OSE / B/X

**Shape presets:**
- **System-agnostic oracle** — `party`, `{juice, mythic, cards, party}`
- **GM toolkit** — `gm`, `{juice, mythic}` (no sheet; Rumors visible in GM mode)

**Custom** — opens the grouped category picker (P1 inline; P2 wizard entry), nothing
preselected.

Each ruleset card is a complete one-tap campaign — this is what removes the wall. A
self-labeling grid of ~12 cards reads faster than 15 unlabeled toggles + a mode switch.

### Section 3 — mode auto-suggest

- Ruleset preset → **Party** (solo player with a sheet).
- GM toolkit → **GM**.
- System-agnostic → **Party**.
- Custom / P2 wizard → mode defaults to Party; the picker shows a live hint
  (*"GM mode hides party tools & shows Rumors"*) so the dead-combo trap is visible.
  User can override.

Only Custom users ever touch the raw mode toggle, and they see what it costs.

### Section 4 — phase split

**P1 — presets-first, single dialog**
- `NewCampaignDialog` reworked: name field + presets grid. Tapping a preset highlights
  it and stages its `(mode, systems)`; Create applies it via
  `SessionsNotifier.create(name, mode, systems)`.
- **Custom** expands the grouped category picker inline: ruleset radio (incl. "none"),
  oracle/exploration/tools multi. Replaces today's flat checkboxes.
- `_EditSystemsDialog` regrouped by the same categories (one grouping source of truth);
  Edit stays multi-toggle everywhere (advanced).
- `kAllSystems` stays as a constant but creation no longer seeds from it — the selected
  preset seeds. **The plan must audit every other `kAllSystems` consumer** (tests,
  migration, any runtime read) before changing creation behavior.

**P2 — grouped wizard**
- Multi-step: (1) name + ruleset cards · (2) add-ons by category with an **embedded
  live preview** (a Flutter port of the feature matrix that reuses the same gating
  predicates, so preview and runtime can't drift) · (3) mode (auto-suggested + hint)
  → Create.
- Presets remain the fast path on step 0; Custom flows into the wizard.

### Components

| File | Change |
|---|---|
| `lib/engine/models.dart` | `SystemCategory` enum, `kSystemCategory` map |
| `lib/engine/campaign_presets.dart` (new) | `CampaignPreset`, `kCampaignPresets`, `presetConfig` |
| `lib/shared/home_shell.dart` | `NewCampaignDialog` presets grid + inline Custom; `_EditSystemsDialog` regroup |
| `lib/features/campaign_setup/` (new, P2) | wizard steps + embedded preview pane |
| `test/campaign_presets_test.dart` (new) | category completeness, `presetConfig`, single-select guard |
| `test/campaign_creation_test.dart` | preset grid renders, tap+Create → right config, Custom expand |

### Data flow

`NewCampaignDialog` (or wizard) → selected `CampaignPreset` or hand-built
`(mode, Set<String> systems)` → `SessionsNotifier.create(name, mode, systems)` →
session persisted → `landingDestination(mode)` routes the entry. No change to how
systems gate UI at runtime — only how the initial set is chosen.

### Testing strategy

- **Pure unit:** `presetConfig` resolves each preset's `(mode, systems)`;
  `kSystemCategory` completeness (every system categorized); ruleset single-select guard.
- **Widget (P1):** presets grid renders; tap preset + Create → campaign created with the
  preset's systems + mode; Custom expand shows grouped radio (ruleset) + multi (others).
- **Widget (P2):** wizard step navigation; preview pane updates as systems toggle; mode
  hint visible on the mode step.
- Existing `character_sheet_ui_test` / creation tests updated for the new dialog shape.

---

## Scope / YAGNI

- **In:** category constant, presets, reworked creation dialog (P1), grouped Edit dialog,
  grouped wizard + live preview (P2).
- **Out:** AI per-campaign override (app-global, unchanged); changing how systems gate
  runtime UI; multi-ruleset hard constraint (model stays permissive); migration of
  existing campaigns (pre-release, none exist).

## Open risks

- `kAllSystems` has consumers beyond creation defaults — the plan's first task is an
  audit so we don't silently break a test or runtime read when creation stops seeding
  from it.
- P2's embedded preview must reuse the real gating predicates (shared helper), not a
  hand-copied table, or it will drift from actual behavior.
