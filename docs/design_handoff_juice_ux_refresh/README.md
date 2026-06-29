# Handoff: Solo Adventurer's Journal (Juice) — UX Refresh

## Overview

This package proposes a set of **UX and visual improvements** to the existing **Solo Adventurer's Journal** Flutter app (internal id: `juice`). It is not a greenfield feature — each item below maps to a surface that already exists in the app, and the goal is to make the core solo-play loop *faster, calmer, and more guided* while giving the app a warmer, more literary skin.

The improvements are organized into five themes:

1. **Game flow** — keep the player inside the journal; add a session-start ritual.
2. **Information visibility** — reduce HUD density; add a "where am I?" overview; raise the signal of result entries; summarize character vitals on the roster row.
3. **Speed & discoverability** — a slash-command palette; surface on-device AI in context.
4. **Onboarding & identity** — play-fantasy campaign presets; directive empty states; a scannable campaign list.
5. **Visual refresh** — a bolder "tome" aesthetic (paper grain, serif narrative type, drop caps, restrained motion).

These map to the *Designer Findings* (sections A–D) in the project's `design-overview.md`. Finding IDs are cited throughout (e.g. **A1**, **D5**).

---

## About the Design Files

The files in this bundle are **design references created in HTML** — a single pannable canvas (`Juice-UX-Refresh.standalone.html`) containing 12 annotated mobile mockups. They demonstrate intended **look, hierarchy, and behavior**; they are **not production code to copy**.

**This is a Flutter app.** The task is to **recreate these designs using the app's existing Flutter widgets, theme, and patterns** — `ThemeData` / `TextTheme`, existing screen scaffolds, the established navigation (the four-verb bottom nav: Journal / Sheet / Ask / Map), and whatever state solution the app already uses (Riverpod / Provider / Bloc — match what's there). Do not introduce HTML/CSS concepts. Where this doc gives pixel values, treat them as the **hi-fi target**, then express them through the app's theme rather than hard-coding magic numbers screen-by-screen.

## Fidelity

**High-fidelity.** Colors, typography, spacing, radii, and shadows are final and specified below. Recreate the UI to match, using Flutter equivalents (`TextStyle`, `BoxDecoration`, `BorderRadius`, `BoxShadow`, `Container`/`Card`). Motion and interaction notes are intentional and should be honored (respecting `MediaQuery.disableAnimations` / reduced-motion).

---

## Design Tokens

Centralize these in the app's theme (e.g. a `ThemeExtension` or the existing color/typography config) rather than inlining.

### Color

| Token | Hex | Use |
|---|---|---|
| `bg.cream` | `#FBF1EB` | App background (primary surface) |
| `bg.cream.grain` | `#FBF2EC` | Background under paper-grain texture (refresh skin) |
| `surface.sand` | `#F6E2D7` | Header / HUD band |
| `surface.sand.deep` | `#F4DECF` | Header band on the refreshed skin |
| `surface.card` | `#FBE9E0` | Standard pink card fill |
| `surface.raised` | `#FFFBF9` | Raised list rows / inputs (near-white warm) |
| `surface.selected` | `#F3D7C6` | Selected chip / secondary button fill |
| `surface.selected.alt` | `#F6D9C9` | Selected state (condition chips, etc.) |
| `primary` | `#9A4A22` | Terracotta — primary actions, accents, active states |
| `primary.deep` | `#7C3A1A` | Pressed primary |
| `ink` | `#2B2018` | Primary text |
| `ink.body` | `#5A4A40` | Body / secondary text |
| `ink.body.alt` | `#6B5849` | Body alt |
| `ink.muted` | `#8A7466` | Captions, sublabels |
| `ink.faint` | `#9A8576` | Metadata, placeholder labels |
| `ink.placeholder` | `#A38E7E` | Input placeholders, disabled |
| `hairline` | `#EFE0D6` | Borders / dividers (primary) |
| `hairline.warm` | `#E3CDBE` | Divider on cream |
| `border.input` | `#E0C7B7` | Input + secondary-button borders |
| `accent.sage` | `#5B7A52` | "Fix"/success accent |
| `accent.sage.bg` | `#E7EFE2` | Sage chip background |
| `accent.sage.text` | `#42583B` | Text on sage chip |
| `accent.problem` | `#B25B3A` | "Problem" accent (annotations only) |
| `accent.problem.bg` | `#F6E0D6` | Problem chip background |
| `accent.chaos` | `#B5762A` | Mythic Chaos value |
| `accent.chaos.chip.bg` | `#F4D9A8` | Chaos chip background |
| `accent.chaos.chip.text` | `#8A5A18` | Chaos chip text |
| `accent.gold` | `#D9A84E` | "Lead PC" star |
| `accent.tan` | `#C98A5E` | Secondary thread/numeral accent |

**Campaign identity hues** (for the campaign list color spine + icon tile — same perceived weight, varied hue):

| Name | Spine | Icon tile bg |
|---|---|---|
| Terracotta | `#9A4A22` | `#F3D7C6` |
| Sage | `#5B7A52` | `#E4EDDF` |
| Indigo | `#4A5A8A` | `#E1E5F0` |
| Plum | `#8A4A6A` | (tint of hue) |
| Gold | `#B5762A` | (tint of hue) |

**Gradients**
- AI nudge card: `linear-gradient(115deg, #FCEDE3 → #F7E0D2)` → Flutter `LinearGradient(begin: topLeft-ish, colors: [Color(0xFFFCEDE3), Color(0xFFF7E0D2)])`.
- Result "hero" card: `linear-gradient(165deg, #FDEFE6 → #F8E0D2)`, border `#EFC9B4`.
- Header fade: sand → transparent.

### Typography

Two families. The app may currently use a single sans; the refresh **introduces a serif for narrative content**.

- **Narrative / display — `Newsreader`** (serif; weights 400/500/600 + italics). Used for: scene titles, oracle answers, journal prose, drop caps, big numerals. In Flutter: `GoogleFonts.newsreader(...)` or bundle the family.
- **UI — `Hanken Grotesk`** (sans; weights 400–800). Used for: labels, controls, data, buttons. `GoogleFonts.hankenGrotesk(...)`.

If brand constraints forbid new fonts, map: narrative → the app's existing serif (or nearest available), UI → existing sans. Keep the *role split* (serif = story, sans = controls) regardless of exact families.

| Role | Family | Size | Weight | Style | Notes |
|---|---|---|---|---|---|
| Hero title (cover/section) | Newsreader | 30–52 | 500 | normal/italic | `letter-spacing: -0.02em` |
| Scene title (HUD/header) | Newsreader | 17–20 | 500 | italic | |
| Oracle answer (hero card) | Newsreader | 28–32 | 500 | normal; "and…" italic in primary | |
| Oracle answer (inline card) | Newsreader | 22 | 500 | normal | |
| Journal prose | Newsreader | 14.5–15 | 400 | normal | `line-height ≈ 1.6` |
| Drop cap | Newsreader | 46 | 500 | normal | `primary` color, floats left |
| Section/eyebrow label | Hanken Grotesk | 10–12 | 700 | normal | UPPERCASE, `letter-spacing 0.08–0.16em`, `ink.faint` |
| Card heading | Hanken Grotesk | 15–17 | 700 | normal | |
| Body (annotations) | Hanken Grotesk | 13–13.5 | 400 | normal | `line-height ≈ 1.6`, `ink.body` |
| Button label | Hanken Grotesk | 12.5–15 | 700 | normal | |
| Metadata/caption | Hanken Grotesk | 10–11.5 | 400–600 | normal | `ink.faint` |
| Big numerals (stats) | Hanken Grotesk | 15 | 800 | normal | `primary` |

### Spacing, radius, shadow

- **Spacing scale (px):** 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 28. Use `EdgeInsets` / `SizedBox` / `Gap`.
- **Radii:** chips `9–14`, list rows `12–15`, cards `14–20`, primary buttons `16`, icon tiles `8–13`. `BorderRadius.circular(...)`.
- **Shadows:**
  - Card/elevation soft: `BoxShadow(color: Color(0x14000000) /* rgba(0,0,0,.08) */, blurRadius: 3, offset: Offset(0,1))`
  - Result hero card: `BoxShadow(color: Color(0x29 9A4A22) /* rgba(154,74,34,.16) */, blurRadius: 22, offset: Offset(0,8))`
  - Primary button: `BoxShadow(color: rgba(154,74,34,.32), blurRadius: 16, offset: Offset(0,6))`
- **Paper-grain texture (refresh skin):** a faint repeating dot. In Flutter, paint via a `CustomPainter` (1px dots, ~`Color(0x0D78502 8)` ≈ rgba(120,80,40,.05), 15px grid) layered under the cream background. Keep it subtle.

---

## Screens / Views (the 12 improvements)

Each item: the existing surface it touches, the proposed change, exact content, layout, and Flutter implementation notes.

### 1. Session Resume ritual  *(Finding A2, D7)*
**Surface:** Home launcher "Continue" flow.
**Change:** Instead of reopening the last verb, `Continue` lands on a **resume screen** answering "where did I leave off?" and offering the next action.
**Layout (top→bottom):**
- Header band (`surface.sand` → cream fade): eyebrow "WELCOME BACK" (`primary` tint `#B0613A`), scene title `The Ancient Tower` (Newsreader italic 30), subtitle `Campaign 1 · last played 2 days ago`.
- **Three stat tiles** (Row of equal `Expanded`, `surface.card`, radius 14, pad 12×14): `Scene → Scene 3`, `Chaos → 5` (value in `accent.chaos`), `Light → out`.
- **Open threads** (eyebrow label) → list of `surface.raised` rows (border `hairline`, radius 12): colored dot + title + `n/10` progress. Dot color = thread accent (`primary`, `accent.tan`).
- **Last entry** → eyebrow + the last journal line in Newsreader italic 14.5, `ink.body`.
- **Primary CTA** `Continue the story →` (full-width, `primary`, radius 16, white 700, primary shadow).
- **Secondary row** (two `Expanded`): `Recap so far` and `New scene` — outlined (`border.input`, radius 14, `primary` 600 text).
**Flutter notes:** New `SessionResumeScreen` shown after campaign load when there is prior session state. `Recap so far` uses on-device AI when available; otherwise a deterministic static summary (scene + open threads + last N entries). The three tiles read from the same state as the HUD.

### 2. Inline Oracle Dock  *(Finding A1; also C5)*
**Surface:** Journal verb (composer area).
**Change:** A horizontally-scrolling **action dock** sits between the last entry and the composer so the most-used rolls happen *in place* and results append inline — no trip to the Ask verb.
**Content (chips, left→right):** `⚀ Roll oracle` (filled `primary`), `Scene test`, `Pay the price`, `✦ Inspire` (all `surface.selected`, `primary` 600 text, radius 12, pad 8×13). Chip set is context/system-aware (e.g. Scene Test only when Mythic enabled).
**Below dock:** existing composer — input (`surface.raised`, border `border.input`, radius 16, placeholder "Write in your journal…") + send button (42×42, `primary`, radius 13).
**Inline result:** appends a result card to the journal stream immediately (see #3). Player stays on Journal.
**Flutter notes:** A `SingleChildScrollView(scrollDirection: Axis.horizontal)` of `ActionChip`-style widgets above the composer `TextField`. Each chip calls the same roll/generator services the Ask verb uses, then inserts a journal entry and scrolls to it (use a `ScrollController.animateTo`, **not** `Scrollable.ensureVisible` on the whole tree).

### 3. Journal entry hierarchy  *(Finding D3, B6)*
**Surface:** Journal entry list.
**Change:** Three clearly distinct entry weights so decisions stand out at scroll speed.
- **Prose entry:** Newsreader italic 14.5, `ink.body`, no card (just padding).
- **Result hero card:** gradient `#FDEFE6→#F8E0D2`, border `#EFC9B4`, radius 18–20, hero shadow. Contains: source row (24×24 `primary` icon tile + UPPERCASE source label `Fate Check`, right-aligned odds), **big serif answer** (`Yes, and…`, 28–32, the qualifier italic in `primary`), intensity caption (`Major (d6 = 5)`), and an **inline action row** above a hairline: `✦ Interpret`, `Voice line`, right-aligned `⚑ Pin`.
- **Compact dice/log entry:** `surface.raised` row, small icon tile + `Dice · d20 = 18`.
- **Scene divider:** centered eyebrow on hairlines, e.g. `Scene 3 · Chaos 5` in `accent.chaos`.
**Flutter notes:** Model entries with a `type` enum (`prose`, `result`, `dice`, `sceneDivider`, `sketch`, …) and a `sourceTool`. One builder per type. Per-entry actions move **onto** the card (no hidden long-press), but keep long-press for secondary actions.

### 4. Grouped header HUD  *(Finding D5)*
**Surface:** Persistent Campaign Header HUD.
**Change:** Split the single dense row into **two tiers**:
- **Tier 1 (always):** status dot + scene title (Newsreader italic 19) | right: `Chaos 5` chip (`accent.chaos.chip`) + the **quick-roll** button (38×38, `primary`, radius 13, primary shadow). These are *narrative state* + the one control pressed most.
- **Tier 2 (quiet, collapsible via ▾):** `🜂 Light: out −/+`, `Oracle: Juice ▾`, terrain chip — small `surface.card` pills, `ink.muted`. Collapses to save vertical space.
**Flutter notes:** Replace the current single `Row` with a `Column` of two rows; the second wrapped in an `AnimatedSize`/`AnimatedCrossFade` toggled by a disclosure caret persisted per campaign. Group ordering = *narrative state* (tier 1) vs *roll controls* (tier 2).

### 5. "Where am I?" dashboard  *(Finding D7, A6)*
**Surface:** Track verb — make this the **Track home / overview** above the existing subtabs.
**Change:** Aggregate current state into summary cards that double as navigation:
- **Now** card (`surface.card`): eyebrow "NOW" + current scene + `Open ↗`.
- **Threads** card + **Tracks** card (Row): thread names with thin progress bars; track names with `n/10`.
- **Party** card (mini vitals chips e.g. `♥ 4/5`, `↯ +2`) + **Encounter** card (state `Idle` / live, amber when active, `surface` `#FFF6F0` border `#F0CDB8`).
**Flutter notes:** A `GridView`/`Column`+`Row` of tap-through `Card`s, each `onTap` navigating to its subtab. When an encounter is live, the Encounter card gets `accent.chaos` emphasis and sorts first.

### 6. Roster row at a glance  *(user request: summarized info + quick actions)*
**Surface:** Sheet verb (character roster).
**Change:** The **lead PC** row expands into a rich card; companions/NPCs stay compact.
- **Lead card** (`#FFFBF9→#FCEFE6` gradient, border `#F0CDB8`, radius 18): star (gold) + name (16, 600) + role badge (`PC`, `surface.selected`). Then a **vitals row**: Health / Spirit / Supply each as label + `4/5` (big 15/800 `primary`) + a 5px progress bar (`hairline` track, `primary` fill); plus Momentum value. Condition chips below (`surface.selected.alt`, e.g. `Shaken`, plus a dashed `+ condition`). **Quick-action row** above a hairline: `Roll a move` (filled `primary`), `−`, `+`, `⋯` (outlined 38px squares).
- **Compact NPC row** (`surface.raised`): icon tile + name + `NPC · Wary` + `♥ 3/3`.
**Flutter notes:** Two row variants keyed off role. The vitals bar is sheet-system-aware: Ironsworn → Health/Spirit/Supply/Momentum; D&D 5e → HP/AC; Shadowdark → HP + **torch countdown**; etc. `±` buttons mutate condition meters without opening the full sheet. `Roll a move` deep-links to that character's move flow.

### 7. Slash-command palette  *(Finding C5; speed)*
**Surface:** Journal composer.
**Change:** Typing `/` opens a command palette floating above the composer, reaching every tool from the journal.
**Commands shown:** `/fate [odds]`, `/roll 2d6+1`, `/scene title`, `/inspire npc·weather·room`, `/thread (+ /track)`. Each: 26px icon tile + monospace-ish command + description; selected row highlighted `surface.sand`. Composer shows the typed command with a `primary` caret.
**Flutter notes:** Detect leading `/` in the composer `TextField`; show an `Overlay`/`showModalBottomSheet` list filtered as the user types, backed by the **existing Tool Search index** plus argument parsing (odds, dice expression, generator name). Selecting runs the action and logs inline (ties into #2/#3). Add a small persistent `/` hint chip so it's discoverable.

### 8. Surfacing on-device AI  *(Finding C2)*
**Surface:** Journal (and anywhere AI actions appear).
**Change:** Introduce AI in context rather than only in Settings.
- A **dismissible nudge card** (AI gradient, border `#F0CDB8`, radius 18, subtle left-to-right sheen animation): `✦ Bring the oracle to life`, value copy, buttons `Enable AI` (filled) / `Later` (outlined). Frame the ~2.6 GB on-device download by *value*, shown the first time the player would benefit (e.g. after a notable roll), once, dismissible.
- A shared **`✦` glyph** marks *every* AI-assisted action everywhere (Interpret, Voice line, Recap, Flesh Out, Narrate, Generate). Footnote: "✦ marks an AI-assisted action · all on-device".
**Flutter notes:** Keep AI **off by default** and the on-device messaging intact. The nudge is a one-shot (persist "seen"). Standardize a small `AiBadge`/`✦` leading widget across all AI affordances.

### 9. Play-fantasy campaign presets  *(Finding D6)*
**Surface:** New Campaign dialog (presets).
**Change:** Lead each preset with the **kind of play + icon**, system name as sublabel.
- Rows (`surface.raised`, radius 15, selected = `surface.sand` + `primary` border): 36px icon tile + title + sublabel. E.g. `⚔ Gritty solo fantasy — Vows, perilous odds · Ironsworn`; `🐉 Heroic dungeon crawl — Classes & spells · D&D 5e`; `🕯 Deadly torch-lit delve — Light pressure · Shadowdark`; `🔮 Pure oracle / journaling — No rules, just ask · Juice + Mythic`. A dashed `⚙ Browse all systems · Custom` row at the end.
- Header copy: "New campaign / What kind of story are you telling?". Full-width `Create` button.
**Flutter notes:** Re-label the existing preset chips; keep the same underlying system selections. The chosen genre/mood string is captured for the campaign identity label (#11).

### 10. Directive empty states  *(Finding D1)*
**Surface:** Empty roster, empty journal, etc.
**Change:** Replace passive copy with directive copy that names the next act and shows the primary action prominently. Example: "No characters yet." → **"Every story needs a hero. Create your first character."** with the create button featured.
**Flutter notes:** Each empty state = short emotive line + one prominent primary button (+ optional secondary). Reuse across surfaces via a small `EmptyState` widget (title, body, primaryAction).

### 11. Campaign list identity  *(Finding D2)*
**Surface:** Home launcher campaign list.
**Change:** Give each campaign a **color spine + icon tile + genre/mood line** so it's recognizable at a glance; raw system tags reduce to small dots.
- `Continue · The Ancient Tower` hero card (`primary`, white text, `Scene 3 · 2 days ago`).
- Campaign rows: 6px color spine (identity hue) + icon tile + name + `Gritty fantasy · Ironsworn` + small system dots. Use the identity-hue table above.
**Flutter notes:** Store an identity color + icon + genre label per campaign (derived from the preset/genre at creation, editable). Carry that identity color into the campaign's HUD accent for continuity.

### 12. Iconography consistency  *(Finding B1, B5)*
**Surface:** Top app-bar icons + mode toggle.
**Change:** One glyph, one meaning.
- **Tool search** → a command mark (`⌘`-style), labeled "Find tools & rolls".
- **Journal entry filter** → a distinct search/filter glyph (`⌕`/funnel), kept inside the Assistant rail.
- **Party ⇄ GM** → an explicit **labeled segmented switch** (`Party | GM`), never the ambiguous "person +".
**Flutter notes:** Audit `IconButton`s in the app bar so no two affordances share an icon. Replace the mode toggle with a small segmented control (e.g. `SegmentedButton` or a custom pill) showing the active mode and persisting it per campaign.

---

## Interactions & Behavior

- **Inline rolls (#2, #7):** chip/command → call existing roll service → append entry → smooth-scroll to it via `ScrollController.animateTo` (~300ms, `Curves.easeOut`). Never use `Scrollable.ensureVisible` on the root.
- **HUD tier-2 collapse (#4):** `AnimatedCrossFade`/`AnimatedSize`, ~200ms; state persisted per campaign.
- **AI nudge sheen (#8):** a slow (~4.5s) looping highlight sweep across the card. **Gate behind reduced-motion** (`MediaQuery.of(context).disableAnimations`) — show a static card if disabled.
- **Result card float accent (#12 treat):** the `✦` gently bobs (~3.6s ease-in-out, ±5px). Reduced-motion → static.
- **Dice settle:** existing animated tumble; continue to honor reduced-motion.
- **Card-as-navigation (#5, #11):** whole card is the tap target (`InkWell` with matching `borderRadius`).
- **Quick-action ± (#6):** immediate optimistic state update on the meter, no dialog.

## State Management

Match the app's existing approach (Riverpod/Provider/Bloc). State the redesign reads/needs:

- **Session/campaign:** active scene, chaos level, light timer, current oracle, terrain — already exist; #1/#4/#5 read them. Add `lastPlayedAt` + `lastEntryPreview` for the resume screen.
- **Threads / Tracks:** progress values for the dashboard bars and resume list (exist).
- **Roster:** condition meters + momentum + conditions for the row summary; `±` mutations write back (exist).
- **Encounter:** active/idle + round for the dashboard card (exists).
- **AI:** `aiEnabled`, `modelDownloaded`, plus a one-shot `aiNudgeSeen` flag (new).
- **Per-campaign UI prefs (new, small):** `hudTier2Collapsed`, identity color/icon/genre label, mode (Party/GM — exists).
- **Command palette:** transient; backed by the existing Tool Search registry + an arg parser.

## Assets

- **No raster assets required.** Icons in the mockups are placeholder glyphs/emoji — **replace with the app's existing icon set** (Material/custom). Notable semantic icons to source: dice (`⚀`), AI sparkle (`✦` → use a single consistent custom glyph), command (`⌘`), filter (`⌕`/funnel), mode switch (`⇄`), thread/pin (`⚑`), scene (`🎬`/clapper), per-preset genre icons (`⚔ 🐉 🕯 🔮 🌿`).
- **Fonts:** `Newsreader` (serif) + `Hanken Grotesk` (sans) via `google_fonts` or bundled `pubspec.yaml` assets. If introducing fonts is out of scope, map to existing families but preserve the serif-for-narrative / sans-for-UI split.
- The terracotta `J ✦` mark in the bundle thumbnail is illustrative, not a final logo.

## Files

- `Juice-UX-Refresh.standalone.html` — **self-contained** reference; open in any browser, no assets needed. Pan/zoom the canvas (drag background, scroll to zoom). 12 frames: cover + the 12 improvements with rationale.
- `Juice UX Refresh.dc.html` — editable source of the same canvas (requires the project's `support.js` runtime to render; use the standalone file for plain viewing).
- `README.md` — this document. Self-sufficient: implement from this alone.
- `screenshots/` — PNG of each frame (`01-frame.png` … `13-frame.png`), in document order: 01 cover · 02 Session Resume · 03 Inline Oracle Dock · 04 Entry hierarchy · 05 Grouped HUD · 06 Where-am-I dashboard · 07 Roster row · 08 Slash commands · 09 AI surfacing · 10 Play-fantasy presets · 11 Campaign list · 12 Iconography · 13 Refreshed skin (treat).

### Cross-reference to existing app
These improvements modify existing surfaces documented in `design-overview.md`: §1 Launch & Campaigns (#1, #11), §3 Journal Verb (#2, #3, #4, #7, #8, #10), §5 Sheet/Roster (#6), §8 Track verb (#5), §2 Campaign Creation (#9), §9 Settings/global icons (#12). Designer Findings A–D in that doc are the rationale source.
