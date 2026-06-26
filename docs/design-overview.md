# Loreseer — Design Overview

This document describes every major screen, feature, and configuration option in **Loreseer** (internal id: `juice`). It is intended for designers who need a comprehensive map of the product's UI surfaces and options.

All screenshots are in `docs/screenshots/design/`.

---

## 1. Launch & Campaigns

### Home Launcher (`00-home-launcher.png`)
The first screen shown on launch. Displays the Juice branding ("Juice — Solo TTRPG toolkit"), a **Continue** button resuming the last active campaign, and a **Campaigns** list showing all saved campaigns with their system tags. From here users can switch campaigns, create new ones, or import from file.

### Campaigns Overlay (`01-campaigns-list.png`, `45-campaigns-overlay.png`)
Accessible via the folder icon (top-right of the main shell). Lists all campaigns with their enabled system tags (e.g., "Ironsworn · Mythic · Juice · Party · Verdant"). Each row has:
- **Radio button** — switch active campaign
- **Sliders icon** — edit campaign systems
- **Trash icon** — delete campaign

Bottom actions:
- **+ New campaign** — opens the New Campaign dialog
- **Export campaign** — saves a `.juice.json` (or `.juice.zip` if the campaign has image blobs)
- **Export as Lonelog (.md)** — exports journal as Lonelog-format Markdown

---

## 2. Campaign Creation

### Presets (`02-new-campaign-presets.png`)
The New Campaign dialog opens with 11 preset chips covering the most common setups:
- **Oracle** — pure oracle play (Juice, Mythic, Roll High)
- **Ironsworn / Starforged / Sundered Isles** — Ironsworn-family rulesets
- **D&D 5e / Shadowdark / Nimble / Draw Steel / Tales of Argosa / Cairn / Knave 2e / OSE B/X / Kal-Arath** — bespoke character sheets
- **GM Toolkit** — GM-mode with Rumors

There is also a **Custom** chip to configure systems manually.

### Custom Config — Top (`02b-new-campaign-custom-top.png`)
Grouped pickers for custom setup:
- **Ruleset** (single-select): None, Ironsworn, Ironsworn: Delve, Starforged, Sundered Isles, D&D 5e, Shadowdark, Nimble, Draw Steel, Tales of Argosa, Cairn, Knave 2e, OSE/B/X, Kal-Arath
- **Oracles** (multi-select): Juice, Mythic, Cards (tarot & playing card deck)

### Custom Config — Bottom (`03-new-campaign-custom.png`)
- **Exploration & Maps** (multi-select): Verdant Journey, Hexcrawl
- **Tools** (multi-select): Party Emulator, Lonelog
- **Mode** (Party / GM toggle)
- **Live preview pane** — shows which app surfaces activate with the current selection

---

## 3. Journal Verb

The Journal is the primary verb — always the home surface.

### App Shell & Campaign Header HUD
Persistent across all verbs. Contains:
- **Scene line** — current active scene name (e.g., "The Ancient Tower")
- **Light: out / Light timer** — flame chip + −/+ steppers for global light countdown (neutral timer, ungated)
- **Chaos stepper** — −/+ for Mythic GME chaos level (shown when Mythic enabled)
- **Oracle picker** — selects the default oracle for quick-rolls (Juice, Mythic, or Roll High)
- **Wilderness chip** — shows current Verdant Journey hex environment (when Verdant enabled)
- **Quick-roll dice button** — rolls the default oracle from any verb and logs the result

### Journal Empty (`04-journal-empty.png`)
Fresh journal showing the collapsed Assistant rail header and the composer bar at the bottom.

### Assistant Rail Expanded (`05-journal-assistant-rail.png`)
The rail sits atop the journal and expands via a chevron. Expanded state shows:
- **Filter chips** — "All" + pinned threads (e.g., "Find the Tower's Secret")
- **Suggestion chips** — rule-based contextual actions (e.g., "Roll the oracle", "Start a scene")
- **Journal toolbar** — flag, search, export, clear buttons
- **"Ask the GM" text field** — multi-turn GM chat (requires AI; see Settings)

### Composer
Bottom bar always visible on Journal verb:
- **Text field** — "Write in your journal…"
- **Dice icon** — opens Dice Roller sheet
- **Sparkle icon** — opens Inspire generator (24 flavor generators)
- **Pen/sketch icon** — opens Sketch Editor for a new drawing entry
- **Image icon** — import image for annotated sketch
- **Cards icon** — (shown when Cards system enabled) opens draw sheet
- **Send arrow** — submits the entry

### Journal Entry States
- **Text entry** (`07-journal-with-entry.png`) — plain journal note with timestamp
- **Result card** (`10-journal-populated.png`) — oracle/dice result (Dice Roll, Fate Check, Mythic Scene Test, etc.) with source-tool badge; tapping reveals per-entry actions (Interpret, Voice Line, etc.)
- **Scene divider** (`47-journal-populated-state.png`) — section header with scene name + Chaos level, separates journal into scenes
- **Mythic Scene Test result** — Answer + Intensity displayed in a card

### HUD Quick-Roll Result (`48-hud-quick-roll-result.png`)
Clicking the dice button in the HUD rolls the active oracle (here: Juice Fate Check at Normal odds) → "No But (-+5), Major (d6 5)" — logged as a journal entry with a snackbar confirmation.

---

## 4. Dice Roller

Accessible via the dice icon in the Journal composer or via the Tool Search.

### Dice Roller Sheet (`08-dice-roller.png`)
- **Expression field** — freeform dice expression (e.g., `2d6+3`)
- **Quick-roll buttons** — d4, d6, d8, d10, d12, d20, d100, dF (Fudge)
- **Advantage/Disadvantage toggle** (dis / – / adv)
- **Roll button**
- **History section** — list of recent rolls

### Dice Result (`09-dice-result.png`)
After rolling (e.g., d20=18):
- Animated tumble settles on result (honors `prefers-reduced-motion`)
- Individual die faces shown
- Total
- History updated

---

## 5. Sheet Verb (Character Roster)

### Empty Roster (`11-sheet-empty.png`)
"No characters yet. Track NPCs and PCs." with + (Add character) and person+ (Generate NPC) FABs.

### New Character Dialog (`12-new-character-dialog.png`)
Picker for character sheet type: **Generic**, **Ironsworn**, **Starforged**, **Sundered Isles** (plus any other enabled systems). Hint text explains enabling other systems in campaign settings to unlock more sheet types.

### Roster with Character (`13-sheet-roster-ironsworn.png`)
Character row shows:
- Star (mark as lead/active PC)
- Role badge — PC / Companion / NPC (via ••• popup)
- Condition badges (colored chips; editable inline)
- Delete icon
- **Party Effect button** (on group headers with ≥2 members) — apply ±HP and/or conditions to a checkbox selection in one action

Roster groups: **Party** (PCs), **Companions**, **NPCs** (empty groups hidden).

### Ironsworn Character Sheet

**Top section** (`14-ironsworn-sheet-top.png`):
- Character name (editable)
- **Stats** — EDGE, HEART, IRON, SHADOW, WITS (steppers, 1–4)
- **Condition Meters** — Health, Spirit, Supply (0–5 tracks)

**Mid section** (`15-ironsworn-sheet-mid.png`):
- Health / Spirit / Supply current values with −/+ steppers
- **Momentum** — current value, **Burn** button (reset to baseline), min/max
- **Debilities** — chip toggles: Wounded, Shaken, Unprepared, Encumbered, Maimed, Corrupted, Cursed, Tormented

**Bottom section** (`16-ironsworn-sheet-bottom.png`):
- XP earned / XP spent
- Bonds track (0–10)
- **Vows** list (+ Add vow)
- **Assets** list (+ Add asset) — rendered from Ironsworn asset data

### Ironsworn Moves (`17-ironsworn-moves.png`)
The **Sheet > Moves** tab (shown in Party mode with Ironsworn ruleset). Collapsible sections: Adventure Moves, Relationship Moves, Combat Moves, Suffer Moves, Quest Moves. Attribution: "Ironsworn Rulebook © Shawn Tomkin — CC-BY 4.0".

---

## 6. Ask Verb (Oracle & Tables)

### Fate Check Oracle (`18-ask-oracle-fate.png`)
Default oracle tab. Features:
- **Odds selector** — segmented: Unlikely / Normal / Likely (+ more via the full fate check dialog)
- **Roll Fate Check** button — rolls Juice oracle and logs result
- **Random Event** button
- **Pay the Price** button

### Roll High Oracle (`19-ask-oracle-rollhigh.png`)
Alternate oracle tab:
- **Dice selector** — d100 / d20 / 2d6 tabs
- **Odds dropdown** — adjusts difficulty threshold
- **Roll Oracle** button
- **Mythic GME section** — Chaos level display + Scene Test / Random Event / Meaning Table buttons (shown when Mythic enabled)

### Tables Tab (`20-ask-tables.png`)
Searchable oracle/random tables with:
- **Advantage/Disadvantage toggle** (dis / – / adv) applied to all table rolls
- **Search field**
- Tables grouped by category: Challenge, Dungeon, etc.
- Tap a table → rolls and logs a result entry

---

## 7. Map Verb

Three subtabs: **World**, **Dungeon**, **Journey**.

### World Tab — Empty (`21-map-world-empty.png`)
"No hexes yet. Travel reveals the map as you go." with a **Travel** button. Map controls in the header (icons for bookmark, annotate, clear).

### World Tab — Verdant Travel (`22-map-world-travel.png`, `23-map-world-verdant.png`)
After traveling, the current hex name appears above the Travel button (e.g., "Scrub 0 Grassland") and a **Wilderness Travel** result card shows:
- **Environment** — terrain type + dice expression + drift value
- **Encounter** — encounter category + die result
- **Weather** — condition

This is the Verdant Journey oracle system. Each Travel click generates a new hex and appends its encounter to the journal.

### Dungeon Tab — Empty (`24-map-dungeon-empty.png`)
"No rooms yet. New room rolls the dungeon oracle and maps it." with a **New room** button.

### Dungeon Tab — Room Card (`25-map-dungeon-room-card.png`)
After adding rooms via "New room":
- Each room shows a detail card: room type, next area, passage, condition, encounter, monster
- **Linger** button — stay in room
- **Set encounter here** button — links an encounter to this location

### Journey Tab (`26-map-journey-top.png`, `27-map-journey-bottom.png`, `27b-map-journey-round.png`)
Verdant Journey tracker:
- **Day / Watch** — current position in the day cycle (Morning/Afternoon/Evening/Night chips)
- **Party in party** / **Independent followers** — stepper counters feeding Encounter Risk
- **Encounter Risk** — computed value displayed in amber
- **Travel pace** — Normal / Slow +2 / Fast −2 segmented buttons
- **Transport** — dropdown (On foot, Horse, etc.)
- **Safety Level** — current modifier (+0) with "New-round baseline" sub-label
- **Safer +2 / Riskier −1 / Deadly −2** — adjust safety for next roll
- **Journey Round** — step-by-step procedure ("1. Round Starts — declare Watch")
- **Next step** button — advances through the round procedure

---

## 8. Track Verb

Seven subtabs: **Scenes**, **Threads**, **Tracks**, **Encounter**, **Emulator**, **Sidekick**, **Behavior**.

### Scenes (`28-track-scenes-empty.png`, `29-track-new-scene-dialog.png`, `30-track-scenes-populated.png`)
Scene management:
- **+ New scene** button → dialog with title field + "Roll Mythic Scene Test" checkbox
- **Generate** button — AI-generated scene name (requires AI)
- Each scene row shows name, Chaos level, edit pencil icon
- Creating a scene updates the Campaign Header HUD scene line

### Threads (`31-track-threads-empty.png`, `32-track-new-thread-dialog.png`, `33-track-threads-populated.png`)
Quest/vow tracker:
- FAB (+ button) → "New Thread" dialog with Title + Note fields
- Thread row: checkbox (complete), title, pin icon, delete icon
- "No threads yet. Track quests, vows, mysteries."

### Tracks (`34-track-tracks-empty.png`, `35-track-tracks-populated.png`)
Progress tracks for challenges:
- **+ New** button → "New track" dialog (name only)
- Track row: name, progress stepper (0/10, −/+), ••• menu

### Encounter (`36-track-encounter.png`)
Combat tracker:
- **Round counter** (Round 1) + **Next turn** button + flag icon
- Combatants list ("No combatants. Add from your characters or ad-hoc.")
- Add buttons: **From characters** (imports roster), **Ad-hoc** (quick add), **Generate** (AI monster)

### Emulator (`37-track-emulator.png`)
Party Emulator (Triple-O system):
- **Character dropdown** — select which PC to emulate
- **Emulation section** — Agenda, Focus, Tokens (stepper)
- **Roll Agenda** / **Roll Focus** buttons

### Sidekick — Dialogue (`38-track-sidekick-dialogue.png`)
PET (Player Emulator with Tags) system:
- **Character dropdown** — select companion
- **Mood** — current mood label (Default, etc.)
- **Roll line** button — generates a spoken line
- Attribution: "PET & Sidekick © Tam H (hedonic.ink), CC-BY 4.0 / Triple-O © Cezar Capacle / Critical Kit, CC-BY-SA 4.0"

### Sidekick — Hexflower (`39-track-sidekick-hexflower.png`)
Alternative navigation mode for the Sidekick:
- **Topic / Context** display (e.g., "Topic: fact · Context: current events (red)")
- **Step (2d6)** button — rolls and moves to adjacent hex
- **Reset** button
- Visual hex grid showing topic labels: fact, query, want, need, denial, action

### Behavior Tables (`40-track-behavior.png`)
NPC/enemy behavior oracle (PET system):
- **Spark** section — broad behavior chips: Action, Focus, Method, Disposition, Motivation, Dynamics
- **Specific** section — context chips: Combat, Social, Exploration, Delving, Interpretation, Downtime, Planning
- **Combos** section — combined rolls: Action + Focus, Action + Method, Action + Motivation
- Attribution: "PET & Sidekick © Tam H (hedonic.ink), CC-BY 4.0"

---

## 9. Settings & Global Controls

### Settings Sheet (`41-settings-sheet.png`)
Opened via the gear icon (top-right). Two sections:

**AI assistant:**
- Toggle: "Enable AI assistant" — Interpret rolls, voice lines, recaps — all on-device
- Subtitle: "Runs on-device. Download the model (~2.6 GB) over Wi-Fi. One time only."
- **Download model** button (when not yet downloaded)
- Model: Gemma 4 E2B int4 (~2.6 GB, downloaded once, never bundled)
- AI is OFF by default; must be explicitly enabled + downloaded

**Third-party content:**
- "All oracle, map and character-sheet content credits and licenses are listed in one place under Help."
- **View credits & licenses** button

### Rulesets Dialog (`44-rulesets-dialog.png`)
Opened via the sliders icon. Toggles for Ironsworn-family rulesets:
- Ironsworn (Rules © Shawn Tomkin, CC-BY 4.0)
- Ironsworn: Delve
- Ironsworn: Starforged
- Starforged: Sundered Isles

These control which asset sets and moves are available in the character sheet.

### Tool Search (`43-tool-search.png`)
Opened via the magnifying glass (top-right). Searchable list of all tool destinations:
- **Recent** — last-opened tool
- **Ask the Oracle** — Fate Check, Roll High Oracle, Mythic GME
- **Dice** — Dice Roller
- **Party** — Party Emulator, Sidekick Dialogue, …
- Typing filters the list

### Mode Toggle (`46-mode-toggle-tooltip.png`)
The person+ icon (top-right) toggles between **Party mode** and **GM mode**:
- **Party mode** (default) — shows Sheet, Emulator, Sidekick, Behavior; hides Rumors
- **GM mode** — shows Track > Rumors subtab; hides Emulator/Sidekick/Behavior/Moves
- Mode is per-campaign, set at creation or toggled at any time

### Help Screen (`42-help-screen.png`, `42b-help-bottom.png`)
Opened via the ? icon. Full in-app documentation organized as:

**User guide topics:**
Getting started, The journal, Sessions & campaign files, Fate Check, Roll High Oracle, Mythic GME, Dice Roller, Story & Scenes, NPCs & Dialog, Generators & tables, Reading tarot, Party Emulator, Behavior Tables, Sidekick Dialogue, Threads & Characters, Encounter Tracker, Maps, Verdant Journey, Moves & Oracles, Oracle interpreter (on-device AI)

**System references:**
Juice oracle, Roll High, Mythic Game Master Emulator, Ironsworn & Starforged, Triple-O (player emulator), PET (Player Emulator with Tags), Sidekick

**About & licenses:**
Credits & licenses (full third-party attribution)

---

## 10. AI Features (Requires Download + Enable)

All AI features are hidden until the ~2.6 GB Gemma 4 E2B model is downloaded **and** the "Enable AI assistant" toggle is on in Settings. The model runs entirely on-device; no network calls after download. AI is disabled on web.

When enabled, the following affordances appear:

| Surface | Action | Description |
|---|---|---|
| Journal entry | **Interpret** | LLM narrates the meaning of a rolled result in context |
| Journal entry | **Voice Line** | Generates a spoken NPC/character line |
| Journal toolbar | **Recap** | Summarizes recent journal entries since last scene break |
| Assistant rail | **Ask the GM** | Multi-turn GM chat; each response can be saved to journal |
| Journal composer | **Narrate** (sparkle popup) | Continue scene / Add complication — logs a `narrate` entry |
| Roster character | **Flesh Out** | Appends AI-generated detail to character description |
| Thread | **Flesh Out** | Appends AI-generated detail to thread notes |
| Scene (Scenes pane) | **Flesh Out** | Appends AI-generated description to scene body |
| Dungeon room | **Flesh Out** | Appends AI-generated room detail |
| World hex site | **Flesh Out** | Appends AI-generated site detail |
| Track > Encounter | **Generate** | Generates a monster combatant |
| Track > Scenes | **Generate** | Generates a scene title |
| Assistant rail | **Ranked chips** | LLM reorders suggestion chips by contextual relevance + shows a "why" caption on the top pick |

---

## 11. Oracle Systems

Three oracle systems can be enabled per campaign (mix-and-match):

### Juice Oracle (default)
The `jrruethe/juice` oracle system — the app's native oracle. Provides Fate Check (Unlikely/Normal/Likely/…) with answer + intensity. Results logged as `result` entries with `sourceTool: 'juice'`.

### Mythic GME
Chaos-based oracle. Features: Scene Test (altered/interrupted), Random Event, Meaning Tables. Chaos level shown in the Campaign Header HUD and on scene dividers. Results use `sourceTool: 'mythic'`.

### Roll High Oracle
Simple d100/d20/2d6 roll-over oracle with configurable odds threshold. No Chaos mechanic.

### Card Oracles (opt-in `cards` system)
- **Standard deck** — 52 cards (optionally 54 with jokers), drawn without replacement; reshuffles on exhaustion
- **Tarot deck** — 78 cards (22 Major Arcana + 56 Minor), reversible (coin-flip orientation)
- **Spreads** — 3-card, 5-card Cross, 10-card Celtic Cross; each position logged in one journal entry
- Located in Ask verb > Oracle tab when `cards` system is enabled

---

## 12. Character Sheet Systems

Each sheet system is an opt-in system selected at campaign creation. All are facts-only (no vendored rulebook prose).

| System | Sheet type | Signature mechanics |
|---|---|---|
| Ironsworn / Starforged / Sundered Isles | Pre-made | Stats (Edge/Heart/Iron/Shadow/Wits), Condition Meters, Momentum, Debilities, Vows, Assets, Moves |
| D&D 5e | Pre-made | Ability scores + modifiers, saving throws, skills, HP/AC, conditions, spell slots (caster classes), death saves |
| Shadowdark | Pre-made | 6 stats, class/ancestry/alignment, gear, HP/AC, **Torch countdown** (light pressure mechanic) |
| Nimble | Pre-made | 4 stats (modifiers), **Wounds dying-track** stepper, advantage/disadvantage save toggles |
| Draw Steel | Pre-made | 5 characteristics, **Power roll buttons** (2d10 + score → Tier 1/2/3 snackbar), heroic resource |
| Tales of Argosa | Pre-made | 6 stats, **Roll-under buttons** (d20 ≤ stat), **Luck** stepper with reset, **Stagger** computed badge |
| Cairn | Pre-made | STR/DEX/WIL saves, **Deprived** checkbox, **Fatigue** stepper, armor (0–3), HP = Hit Protection |
| Knave 2e | Pre-made | 6 stats as modifiers, pass-target saves, **Wounds** stepper, **Inventory slots** computed badge |
| OSE/B/X | Pre-made | 6 stats (3–18), 5 save tracks with roll buttons, descending AC stepper, THAC0 field |
| Kal-Arath | Pre-made | 5 stats (−1..+5), **2d6 roll buttons**, **Fate Points** stepper, demonic pact dropdown |
| Generic | Freeform | Name, notes, custom HP/resource tracks |

---

## 13. Generators

The **Inspire** button (sparkle) in the Journal composer opens `GenerateSheet` with:

### Visual & Stateful Generators (top)
- **Location grid** — 5×5 compass grid showing biome/terrain features
- **NPC Dialog walk** — stateful hexflower walk through NPC motivations
- **Abstract Icon** — random symbolic image

### Flavor Generators (24 total)
Tappable chips that roll and log a result: Location, NPC Name, NPC Appearance, Dungeon Room, Weather, etc.

### Entity Generators (contextual, not in Inspire sheet)
- **Generate NPC** — in the character roster; prefills name/appearance then opens edit dialog
- **Generate scene** — in Track > Scenes
- **Generate monster** — in Track > Encounter

---

## 14. Export & Import

- **Export campaign** — saves `.juice.json` (plain JSON) or `.juice.zip` (with blob images/PDFs) to a user-selected location
- **Export as Lonelog (.md)** — renders the journal in Lonelog notation format as a Markdown file
- **Import from file** — from the home launcher; supports `.juice.json`, `.juice.zip`, and legacy schema versions (v1/v2 → v3 migration)
- Campaign files are schema v3. Export bundles referenced blob images (sketch annotation backgrounds, PDF sources) automatically.

---

## 15. Sketch & Annotation

Accessible via the pen icon in the Journal composer (new sketch) or by tapping a sketch journal entry.

### Sketch Editor
- **Tools** — Pen, Eraser (whole-element delete), Line, Rectangle, Ellipse, Text (tap-to-place), Pan/Zoom (hand tool)
- **Palette** — color chips + two width options
- **Undo** — snapshot stack covering draw/erase/shape/text/clear
- **Clear / Save / Cancel**
- **Pan-zoom** — InteractiveViewer at up to 6× scale; draw coordinates stored in canvas space

### Image Annotation
- **Annotate image** (`composer-annotate-image`) — import an image file → open as sketch background
- **Annotate PDF** (`composer-annotate-pdf`) — import a PDF → page picker → render page to PNG → sketch over it

### Map Snapshot → Annotate
World and Dungeon map panes have a **snapshot** button that rasterizes the current map canvas to PNG and opens it as an annotated sketch background — no model change, captured as a standard `backgroundBlobId` sketch entry.

---

## 16. Lonelog

An opt-in journaling notation system (system id: `lonelog`, not in `kAllSystems`). When enabled:
- A Lonelog reference is available in Help
- The **Export as Lonelog (.md)** action becomes available in the Campaigns overlay
- The notation system provides structured symbols, block tags, and addon conventions for long-form solo journal export

---

---

## 17. Designer Findings

Observations from hands-on review of the debug macOS build. Organized by concern type. These are starting points for design investigation, not bug reports.

---

### A. Game Flow — The Solo Play Loop

The core loop of solo TTRPG play is roughly:

> **Set scene → roll oracle → interpret result → record in journal → advance thread or track → repeat**

The app has all the pieces but they're distributed across five verbs with no explicit path connecting them.

**Key friction points:**

1. **Oracle rolls leave the journal.** Ask verb is a separate destination. Roll a Fate Check → result auto-logs → player is now on Ask, not Journal. They must navigate back to write about the result. The HUD quick-roll partially addresses this (logs from any verb) but covers only the default oracle.

2. **No session-start ritual.** "Continue" on launch returns to whatever verb was last open. There's no session summary, no "you left off in Scene 3 at Chaos 5 with these open threads" view. Players must mentally reconstruct context across the HUD scene line, journal scroll, and Threads list.

3. **Scenes live in Track but feel like Journal.** Creating a scene from Track > Scenes adds a divider to the journal and updates the HUD. But scenes are conceptually journal structure — a player's first instinct is to look in the journal, not Track. The Assistant Rail's "Start a scene" chip helps, but only when the rail is expanded.

4. **Encounter combat is isolated.** Track > Encounter has no automatic journal logging. Combat results, HP changes, and round notes require the player to manually navigate to the Journal and write. A session of dungeon combat generates zero automatic journal entries.

5. **Verdant Journey is spread across three surfaces.** Map > World (hex reveal), Map > Journey (day/watch tracker), and Campaign Header HUD (terrain chip) must all be used together for a hexcrawl session. There's no single "journey in progress" view.

6. **Thread management is split.** Threads are created and managed in Track > Threads. They appear as filter chips in the Journal's Assistant Rail. A player tracking an active quest moves between two verbs with no deep link between them.

---

### B. UI Consistency — Patterns That Diverge

1. **Two search icons with different behaviors.** The top-right magnifying glass opens Tool Search (navigate to a tool). The Assistant Rail has a separate search icon that filters journal entries. Same icon metaphor, completely different function. Users scanning the top bar will confuse them.

2. **Two light timers.** The Campaign Header HUD has a global light timer (ungated, neutral). The Shadowdark character sheet has a per-character Torch countdown. Both are intentional, but in a Shadowdark campaign both are visible simultaneously with no visual distinction about which governs play.

3. **Numeric input type varies across sheets.** Most stats use steppers (bounded, tap-friendly). OSE/B/X's THAC0 is a freeform text field. Save targets on OSE are steppers. No apparent rule for when a number becomes a text field vs. a stepper.

4. **Flesh Out entry points are different per surface.** Characters and threads: in the edit dialog. Dungeon rooms and world hex sites: inline button on the detail card. Scenes: in the Track > Scenes row. The flow after tapping is the same (Append/Cancel review) but the trigger location varies with no visual common thread.

5. **Mode toggle icon ambiguity.** The person+ icon in the top-right bar toggles Party ↔ GM mode. The same icon shape (person with a +) conventionally means "add a person." The tooltip reads "Party mode (tap for GM)" which clarifies on press, but the resting state gives no affordance that this is a mode switch rather than an add action.

6. **Dice roller history doesn't auto-log to journal.** Inline journal dice (tapping the dice icon in the composer) logs results. The standalone Dice Roller sheet also has a history section, but those rolls don't appear in the journal unless the user manually copies them. Two dice surfaces, different persistence behaviors.

---

### C. Discoverability Gaps

1. **Assistant Rail is collapsed by default.** The thin expand chevron is easily overlooked. The rail contains the most powerful in-session affordances (suggestion chips, Ask the GM, journal filters) but new users may never find it.

2. **AI exists but Settings is the only entry point.** The ~2.6 GB model download and enable toggle are in Settings (gear icon). Nothing on the oracle, journal, or sheet surfaces prompts users toward AI. Users who don't explore Settings won't know on-device AI is available.

3. **Cards system requires upfront configuration.** Card oracles (standard deck, tarot, spreads) must be enabled at campaign creation or via Edit Systems. The Ask verb shows no cards section if the system wasn't configured. There's no in-context prompt to enable it.

4. **Moves tab is inside Sheet verb.** Ironsworn move references live in Sheet > Moves (Party mode). Players mid-session might look in Ask verb for move prompts; the connection between ruleset sheet and moves tab is non-obvious.

5. **Generators are only in the Journal composer.** The Inspire button (sparkle) opens 24 flavor generators + 3 visual generators. This is buried inside the composer flow. Players looking for generators from the Ask verb or Track verb have no direct path.

---

### D. Presentation Optimization Opportunities

1. **Empty states don't direct.** "No characters yet. Track NPCs and PCs." is accurate but passive. The empty journal ("Write in your journal…") similarly gives no guidance on what to do first. Empty states are ideal moments to show the primary action prominently and explain why it matters.

2. **Campaign list tags are text-only.** Campaigns show system tags as small text strings ("Ironsworn · Mythic · Juice · Party · Verdant"). With multiple campaigns, distinguishing them at a glance requires reading. Color, icons, or a short genre/tone label (from campaign creation) could replace or augment raw system id strings.

3. **Oracle result cards and text entries are visually similar.** Oracle results render as distinct cards with source badges. Scene dividers have a visual separator. Plain text entries are minimal. At a scroll-height glance, result cards don't have enough visual weight to anchor the player's eye — they're the most semantically important entries (decisions, rolls) but aren't treated as such visually.

4. **HUD quick-roll feedback is transient.** The snackbar showing "No But (-+5), Major (d6 5)" dismisses in ~3 seconds. From any non-Journal verb, the result is in the journal but not visible. Players in the middle of a map or track session may miss the details before the snackbar disappears.

5. **The Campaign Header HUD carries a lot of density.** At a glance: scene line, light timer, Chaos stepper, oracle picker, terrain chip, quick-roll button. On a Mythic + Verdant + Ironsworn campaign this is seven distinct elements in one persistent row. Priority ordering and visual grouping (oracle-adjacent controls vs. narrative state) could reduce cognitive load.

6. **Presets naming is system-first, not play-fantasy-first.** Preset chips are labeled by system name (Ironsworn, D&D 5e, Cairn, etc.). A player who doesn't know TTRPG system names can't select a preset confidently. Labels like "Ironsworn (gritty fantasy)" or a sub-label with the genre/mood of each system could lower the barrier.

7. **No in-session progress summary.** The Track verb has Scenes, Threads, Tracks, and Encounter separately. There's no aggregated "where am I" view: current scene + active threads + progress tracks + encounter state in one place. This would reduce the tab-switching required to get oriented at the start of a play session.

---

*Designer findings added 2026-06-25. Based on hands-on review of the macOS debug build.*

*Generated 2026-06-25. Screenshots in `docs/screenshots/design/`. App build: debug macOS.*
