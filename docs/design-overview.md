# Solo Adventurer's Journal — Design Overview

This document describes every major screen, feature, and configuration option in **Solo Adventurer's Journal** (internal id: `juice`). It is intended for designers who need a comprehensive map of the product's UI surfaces and options.

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

*Generated 2026-06-25. Screenshots in `docs/screenshots/design/`. App build: debug macOS.*
