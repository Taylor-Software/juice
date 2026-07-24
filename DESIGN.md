---
name: Solo Adventurer's Journal
description: A lamplit campaign tome for solo tabletop RPGs — cream paper, terracotta ink, and a serif that only the story is allowed to speak in.
colors:
  cream: "#FBF1EB"
  sand: "#F6E2D7"
  card: "#FBE9E0"
  raised: "#FFFBF9"
  selected: "#F3D7C6"
  terracotta: "#9A4A22"
  terracotta-deep: "#7C3A1A"
  ink: "#2B2018"
  ink-body: "#5A4A40"
  ink-muted: "#7D6759"
  ink-faint: "#8A7466"
  hairline: "#EFE0D6"
  border-input: "#E0C7B7"
  border-hero: "#EFC9B4"
  identity-terracotta: "#9A4A22"
  identity-sage: "#5B7A52"
  identity-mulberry: "#7E3B4E"
  identity-umber: "#59422F"
  identity-gold: "#B5762A"
  chaos: "#B5762A"
  chaos-chip-bg: "#F4D9A8"
  chaos-chip-text: "#7E5214"
  sage: "#5B7A52"
  gold: "#D9A84E"
  result-hero-from: "#FDEFE6"
  result-hero-to: "#F8E0D2"
  ai-nudge-from: "#FCEDE3"
  ai-nudge-to: "#F7E0D2"
  m3-seed: "#B8540E"
  cream-dark: "#241C17"
  sand-dark: "#2E2620"
  card-dark: "#2E2620"
  raised-dark: "#332A23"
  selected-dark: "#42342A"
  terracotta-dark: "#D0814F"
  terracotta-deep-dark: "#B8693A"
  ink-dark: "#F3E8DF"
  ink-body-dark: "#D8C8BC"
  ink-muted-dark: "#AD9B8C"
  ink-faint-dark: "#9C8A7B"
  hairline-dark: "#3D3229"
  border-input-dark: "#4A3C31"
  border-hero-dark: "#5A4233"
  chaos-dark: "#D9A84E"
  chaos-chip-bg-dark: "#4A3A1E"
  chaos-chip-text-dark: "#F4D9A8"
  sage-dark: "#89A57F"
  gold-dark: "#E0BB6B"
  result-hero-from-dark: "#34281F"
  result-hero-to-dark: "#2A2019"
typography:
  display:
    fontFamily: "Newsreader, Georgia, serif"
    fontSize: "30px"
    fontWeight: 500
    lineHeight: 1.15
    letterSpacing: "normal"
  headline:
    fontFamily: "Newsreader, Georgia, serif"
    fontSize: "22px"
    fontWeight: 400
    lineHeight: 1.27
    fontStyle: "italic"
  title:
    fontFamily: "Newsreader, Georgia, serif"
    fontSize: "16px"
    fontWeight: 500
    lineHeight: 1.5
  body:
    fontFamily: "Newsreader, Georgia, serif"
    fontSize: "13.5px"
    fontWeight: 400
    lineHeight: 1.6
  label:
    fontFamily: "HankenGrotesk, Inter, system-ui, sans-serif"
    fontSize: "11px"
    fontWeight: 700
    lineHeight: 1.45
    letterSpacing: "1.2px"
  label-quiet:
    fontFamily: "HankenGrotesk, Inter, system-ui, sans-serif"
    fontSize: "11px"
    fontWeight: 400
    letterSpacing: "0.10px"
rounded:
  xs: "6px"
  sm: "8px"
  md: "12px"
  lg: "14px"
  xl: "18px"
  tile: "7px"
  bar: "3px"
spacing:
  xs: "4px"
  sm: "6px"
  md: "8px"
  lg: "12px"
  xl: "16px"
  "2xl": "28px"
components:
  button-primary:
    backgroundColor: "{colors.terracotta}"
    textColor: "{colors.raised}"
    typography: "{typography.label-quiet}"
    rounded: "{rounded.md}"
    padding: "12px 24px"
    height: "48px"
  button-primary-pressed:
    backgroundColor: "{colors.terracotta-deep}"
    textColor: "{colors.raised}"
  button-secondary:
    backgroundColor: "{colors.raised}"
    textColor: "{colors.terracotta}"
    typography: "{typography.label-quiet}"
    rounded: "{rounded.lg}"
    padding: "10px 18px"
  card-result-hero:
    backgroundColor: "{colors.result-hero-from}"
    textColor: "{colors.ink}"
    typography: "{typography.display}"
    rounded: "{rounded.xl}"
    padding: "12px 8px 8px 16px"
  card-result-collapsed:
    backgroundColor: "{colors.result-hero-from}"
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    rounded: "{rounded.md}"
    padding: "10px 12px"
  chip-chaos:
    backgroundColor: "{colors.chaos-chip-bg}"
    textColor: "{colors.chaos-chip-text}"
    typography: "{typography.label-quiet}"
    rounded: "{rounded.md}"
    padding: "4px 10px"
  chip-selected:
    backgroundColor: "{colors.selected}"
    textColor: "{colors.terracotta}"
    typography: "{typography.label-quiet}"
    rounded: "{rounded.md}"
    padding: "8px 13px"
  input-composer:
    backgroundColor: "{colors.raised}"
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    rounded: "{rounded.xl}"
    padding: "12px 16px"
  source-eyebrow:
    textColor: "{colors.ink-faint}"
    typography: "{typography.label}"
  icon-tile:
    backgroundColor: "{colors.terracotta}"
    textColor: "{colors.raised}"
    rounded: "{rounded.tile}"
    size: "24px"
  hud-band:
    backgroundColor: "{colors.sand}"
    textColor: "{colors.ink}"
    rounded: "{rounded.md}"
    padding: "6px 12px"
---

# Design System: Solo Adventurer's Journal

## Overview

**Creative North Star: "The Lamplit Tome"**

This is a book that happens to roll dice. The whole system is organized around
the fiction that the player is writing in a warm, worn campaign journal by
lamplight — cream paper, terracotta ink, a serif that only the story speaks in.
Everything the app does mechanically (rolling, tracking, generating) is
marginalia in that book's margins: real, useful, deliberately quieter than the
prose it serves. When a surface has to choose between looking capable and
looking like a page, it looks like a page.

The palette is entirely warm — there is no cool gray anywhere in the system.
Depth comes from paper stacking on paper (cream → card → raised), separated by
hairlines rather than shadow. The single accent, Lamplight Terracotta, behaves
like rubrication in a manuscript: it is not a brand color sprinkled for
identity, it is reserved for the two things that matter — the action the player
is about to take, and the answer the oracle just gave. When the oracle answers,
the qualifier after the comma tilts into italic terracotta, and the card it
sits in is the only surface in the entire application permitted to cast a
shadow. That restraint is what makes the moment land.

The system currently runs on two color layers: the shipped `JuiceTokens` tome
palette, and an underlying Material 3 `ColorScheme` seeded from a deep amber
(`#B8540E`) that still governs older tool chrome, dialogs, and system widgets.
**Tome is the destination.** The M3 layer is legacy debt, not a second design
language — new work reads `JuiceTokens`, and touching an old surface is an
opportunity to migrate it. The system is also fully dual-brightness: every tome
token has a dark counterpart, and the dark theme is not an inversion but a
second warm world (`#241C17` lamp-dimmed brown, never black).

**Key Characteristics:**
- Warm-only palette; zero cool grays, zero blues.
- Serif for fiction, sans for machinery — a hard, load-bearing split.
- Flat by default; one shadow, at the dramatic peak.
- A single accent, spent rarely and deliberately.
- Chrome yields to the writer: on a phone, focusing the composer collapses the
  HUD, the panel, and the bottom navigation.
- Every surface must be complete and good with AI turned off.

## Colors

A single warm family runs the entire system: fired clay on aged paper, with two
narrow-purpose accents borrowed from a candle and a leaf.

### Primary

- **Lamplight Terracotta** (`#9A4A22` light / `#D0814F` dark): the one accent.
  It carries primary actions, active and selected states, the AI `✦` marker,
  icon tiles, and the italic tail of an oracle answer. Its dark-mode twin is
  lifted, not inverted — the same clay under a dimmer lamp.
- **Terracotta Deep** (`#7C3A1A` light / `#B8693A` dark): pressed state only.
  It exists to answer a finger, nothing else.

### Secondary

- **Chaos Ochre** (`#B5762A` light / `#D9A84E` dark): reserved *exclusively* for
  the Mythic chaos factor — the number that says how unstable the story is.
  Paired with a **Chaos Chip** fill (`#F4D9A8` light / `#4A3A1E` dark) and text
  (`#7E5214` light / `#F4D9A8` dark). Never use this hue for generic warning or
  emphasis; it means one thing.
- **Lead Gold** (`#D9A84E` light / `#E0BB6B` dark): the lead-PC star and nothing
  else.

### Tertiary

- **Quiet Sage** (`#5B7A52` light / `#89A57F` dark): the only non-warm hue in the
  system, allowed as a success/resolution accent. Use it sparingly enough that
  it reads as an exception; it is the system's one held breath.

### Neutral

- **Lamplit Cream** (`#FBF1EB` light / `#241C17` dark): the page. The app
  background and the base of every stack.
- **Worn Sand** (`#F6E2D7` light / `#2E2620` dark): the HUD band and header
  surfaces — a half-step of separation from the page without a line.
- **Blush Card** (`#FBE9E0` light / `#2E2620` dark): the standard card fill, one
  step raised from the page.
- **Warm Raised** (`#FFFBF9` light / `#332A23` dark): near-white paper for list
  rows and inputs — the surface the player writes *on*.
- **Selected Clay** (`#F3D7C6` light / `#42342A` dark): the fill for a chosen
  chip or a secondary button.
- **Deep Ink** (`#2B2018` light / `#F3E8DF` dark): primary text and headings.
- **Body Ink** (`#5A4A40` light / `#D8C8BC` dark): journal prose and body copy.
- **Muted Ink** (`#7D6759` light / `#AD9B8C` dark): captions and sublabels.
  Darkened in July 2026 to clear WCAG AA (4.5:1) on the card fill; hue preserved.
- **Faint Ink** (`#8A7466` light / `#9C8A7B` dark): metadata, eyebrow labels,
  placeholder text. Also contrast-corrected.
- **Hairline** (`#EFE0D6` light / `#3D3229` dark): every divider and most borders.
  This is how the system separates things instead of using shadow.
- **Input Border** (`#E0C7B7` light / `#4A3C31` dark): input and secondary-button
  strokes — one step more present than a hairline, because it invites a tap.
- **Hero Border** (`#EFC9B4` light / `#5A4233` dark): the outline on every
  gradient card — the result card, the AI nudge, the emphasized track-home card.
  The only border that is not part of the hairline family. It lived as two
  near-identical hard-coded values (`#EFC9B4` / `#F0CDB8`) at four call sites
  with **no dark value at all** until 2026-07-24, which meant a pale peach ring
  around a near-black card in dark mode. It is now one token,
  `JuiceTokens.borderHero`.

### Status

- **Error** (the Material `colorScheme.error` role, not a tome token): the one
  place the system knowingly leaves the warm family, because a failure state
  that reads as decorative is a failure of the design. Used for hostile NPC
  disposition and a failed tally. Deliberately *not* redefined as a tome color —
  it should feel like an intrusion. Everything softer than a real failure
  (dimmed, unavailable, finished) uses Faint Ink instead.

### The Identity Spine

Each campaign is assigned one of five hues at creation (`kIdentityHues`,
`identityHueFor`), painted as a ~6px spine plus icon tile on the launcher row —
a book's binding seen on a shelf. The set is chosen for at-a-glance
distinguishability across **both hue and value**:

- **Terracotta** (`#9A4A22`) · **Sage** (`#5B7A52`) · **Mulberry** (`#7E3B4E`) ·
  **Umber** (`#59422F`) · **Gold** (`#B5762A`)

Mulberry and Umber replaced the original handoff's Indigo (`#4A5A8A`) and Plum
(`#8A4A6A`) on 2026-07-24: those two were the only cool values in the entire
application's chrome. Terracotta and Umber are the closest pair; they separate
by value, Umber being markedly darker and desaturated. Campaigns created before
the change keep their stored hue.

### Named Rules

**The Rubrication Rule.** Lamplight Terracotta marks a decision — an action
about to be taken, or an answer just given. If an element is neither, it is ink,
not accent. Audit test: on any screen, count the terracotta elements. More than
three and the accent has stopped meaning anything.

**The Migration Rule.** New player-facing work reads `JuiceTokens` via
`context.juice`, never a raw `ColorScheme` role. A surface still on M3 is a
to-do, not a precedent. Audit test: `test/design_system_test.dart` pins the
count of `colorScheme.` uses in `lib/` at its 2026-07-24 measurement (131). The
number may go down — lower the ceiling when you migrate a surface — and never up.

**The Warm-Only Rule.** No cool gray, no blue, no pure black, no pure white in
chrome. `#241C17` is the darkest surface in the system and `#FFFBF9` the
lightest. Stock Material colors (`Colors.green`, `Colors.grey`, `Colors.blue`)
are banned outright — status meaning belongs to Quiet Sage or the
`colorScheme.error` role, neutrals to the ink ramp. The single carve-out is
`Colors.white` as an **on-accent glyph fill** (a 14px icon inside a terracotta
tile); it is a foreground, never a surface. Enforced by
`test/design_system_test.dart`.

**The Cartography Exception.** Two palettes in this app are *content*, not
chrome, and the Warm-Only Rule does not reach them: the hex map's terrain hues
(`map_screen.dart` — water blue, marsh teal, mountain slate) are a data
encoding the player reads as terrain, and the sketch editor's swatch row
(`sketch_editor.dart`) is the player's own ink. Their surrounding chrome —
toolbars, selection indicators, borders — obeys the rule normally. These are the
only two exempt files, and adding a third needs a reason written here.

**The One Meaning Rule.** Chaos Ochre means Mythic chaos. Lead Gold means lead
PC. Quiet Sage means resolved, succeeded, or friendly. These three never get
borrowed for decoration.

**The Real Failure Rule.** `colorScheme.error` is the system's only sanctioned
break from the warm family, and it is spent on actual failure — a hostile
disposition, a failed tally — never on "unavailable", "finished", "dimmed", or
"empty". Those are Faint Ink. If red appears and nothing has gone wrong, the
signal is spent.

## Typography

**Display / Narrative Font:** Newsreader (bundled, with Georgia / serif fallback)
**UI / Label Font:** Hanken Grotesk (bundled, with Inter / system-ui fallback)

**Character:** Newsreader is a warm literary serif with real italics — it makes
the oracle's answer read as something spoken in the story rather than returned
by a function. Hanken Grotesk is a neutral, slightly humanist sans that stays
out of the way; it labels, it does not narrate. The pairing is the product's
whole thesis in two typefaces: the story is written, the machinery is printed.

### Hierarchy

- **Display** (Newsreader, 500, 30px, line-height 1.15): the oracle answer on an
  expanded result card. This is the largest type in the application and it
  appears in exactly one place. Everything about the card exists to frame it.
- **Headline** (Newsreader, 400, ~22px, *italic*): scene titles, empty-state
  opening lines, resume-screen titles. Italic is the signal for "this is the
  fiction talking."
- **Title** (Newsreader, 500, ~16px): card headings and section titles inside
  narrative surfaces.
- **Body** (Newsreader, 400, 13.5–15px, line-height 1.6): journal prose. The
  generous leading is deliberate — it is meant to be read in long passes, not
  scanned.
- **Label** (Hanken Grotesk, 700, 11px, letter-spacing 1.2px, UPPERCASE): the
  eyebrow — source labels on result cards ("FATE CHECK"), section headers.
  Colored Faint Ink so it orients without competing.
- **Label Quiet** (Hanken Grotesk, 400, 11px, letter-spacing 0.10px): metadata,
  intensity captions, chip text, button labels.

### Named Rules

**The Two-Voice Rule.** Serif is the story; sans is the machinery. Scene titles,
oracle answers, journal prose, and narrative empty-state lines are Newsreader.
Buttons, chips, labels, counters, and captions are Hanken Grotesk. There is no
third voice and no crossing over. Audit test: if a string is something the
player's *character* could be said to have experienced, it is serif.

The one carve-out is **notation** — `monospace` in the Lonelog symbol legend,
where glyph alignment *is* the content. That is not a third voice; it is a
table. Enforced by `test/design_system_test.dart`.

**The Italic Tail Rule.** In an oracle answer, everything up to and including the
first comma stays upright Deep Ink; everything after it becomes italic Lamplight
Terracotta. "Yes, *and the door was already open.*" The grammar of the answer is
rendered in type — the verdict is stated, the consequence is voiced.

**The Eyebrow Rule.** Uppercase is reserved for the 11px tracked sans eyebrow.
Nothing else in the system is uppercase — not buttons, not headings, not tabs.

## Layout

The application is one shell with a persistent play-context HUD above a verb
body, and it re-forms three times as it widens:

- **< 600px (compact / phone):** bottom `NavigationBar`, HUD row scrolls
  horizontally rather than wrapping, and the "Next" panel defaults collapsed.
  This is the primary design target, not a fallback.
- **≥ 840px (wide):** the bottom bar becomes a labeled `NavigationRail` down the
  left, separated by a 1px vertical divider.
- **≥ 1000px (split):** the journal detaches into a resizable right-hand column
  (drag handle, clamped 320px to 60% of the viewport) while the other five verbs
  occupy the left pane in an `IndexedStack`. Play and reference are visible at
  once — the desktop payoff.

**Rhythm.** The spacing scale is tight and paper-like: 4 / 6 / 8 / 12 / 16 / 28.
Cards sit at 12px horizontal margin from the page edge and 8px from each other.
The result card's internal padding is asymmetric (16 left, 12 top, 8 right and
bottom) so the answer's first letter aligns to the text column while the action
icons tuck toward the edge.

**Density.** Narrative surfaces are generous (1.6 line-height, 28px empty-state
padding); tool and tracker surfaces are compact (`VisualDensity.compact` on
chips and icon buttons). The density difference between reading and operating is
intentional and should be preserved.

**Touch targets.** `VisualDensity.compact` is used widely and shrinks the
*visual* box, not the tappable one — the floor is **44×44 logical pixels** of
hit area for anything a finger uses at the table. Where a control must look
smaller than that, keep the target and let the paint be small (`BoxConstraints(
minWidth: 32, minHeight: 32)` plus surrounding padding is the established
compact-row pattern; below that, add `MaterialTapTargetSize.padded` or an
explicit `SizedBox`). A dense row of steppers is the usual offender.

**Text scale.** The reading text-scale is a shipped user control applied
app-wide at `MaterialApp.builder`. It is a **sizing constraint on every
component**, not a preference to accommodate later: no fixed-height container
may clip its own label, and any row that fits only at 1.0 is broken. Verify new
rows at raised scale the same way you verify them at 375px.

### Named Rules

**The Chrome Yields Rule.** On a phone, focusing the journal composer collapses
the HUD's expanded row, collapses the "Next" panel, and removes the bottom
navigation entirely. A keyboard already takes half the screen; the writer gets
the other half. All three collapses are visual only — persisted state is
untouched and everything returns on blur.

**The 360 Floor Rule.** The journal body lays out at `max(viewport, 360px)`
inside an always-present scroll view — one tree at every height, never a
size-threshold branch. Below the floor the viewport scrolls over the body; above
it, nothing scrolls. A layout branch keyed to height will destroy the composer's
text-input connection on every keyboard cycle.

**The 375 Rule.** 375px is the hard minimum width. Any row that can overflow
there must wrap, scale (`FittedBox`), or scroll — verified, not assumed.

## Elevation & Depth

**Flat by default; shadow as an event.** Depth is tonal, not cast. The system
stacks four warm fills — page (Cream) → band (Sand) → card (Blush) → raised
(Warm Raised) — and separates them with hairlines. There is presently exactly
one `BoxShadow` in the entire codebase, and it belongs to the expanded oracle
result card. That scarcity is doctrine, not an oversight: the shadow *is* the
punctuation on the moment the story turns.

The one sanctioned expansion is the primary button lift, specified in the
original handoff and not yet implemented. It may be added; nothing else may.

### Shadow Vocabulary

- **Answer lift** (`BoxShadow(color: terracotta @ 16%, blurRadius: 22, offset: (0, 8))`):
  the expanded result card only. Tinted with the accent rather than black, so it
  reads as lamplight rather than a drop shadow.
- **Primary lift** (`BoxShadow(color: rgba(154,74,34,.32), blurRadius: 16, offset: (0, 6))`):
  sanctioned for the primary button. Specified, not yet shipped.

### Named Rules

**The One Shadow Rule.** If a surface is not the expanded oracle answer or the
primary button, it does not cast a shadow. Separate it with a hairline or a
tonal step instead. Audit test: `test/design_system_test.dart` fails above two
`BoxShadow(` occurrences in `lib/`. As of 2026-07-24 there is exactly one.

**The Warm Shadow Rule.** Shadows are tinted with the terracotta accent, never
neutral black. A gray shadow on cream paper reads as plastic.

## Shapes

Soft, consistent, unfussy rectangles. Nothing in the system is a circle except
avatars and the dice glyphs; nothing is a sharp 0px corner.

The radius scale runs 6 / 8 / 12 / 14 / 18, with two special values: a 7px icon
tile (24×24, terracotta fill, white glyph — the recurring source marker on
result cards and list rows) and a 3px progress-bar cap.

Borders are 1px and warm. Three border families exist and they are not
interchangeable: **hairline** for dividers and passive card edges, **input
border** for anything tappable or typeable, and the single **hero border**
(`#EFC9B4`) for the result and AI-nudge cards.

A collapsed result card sits at 12px and expands to 18px when it opens — the
corner softening as the answer grows is part of the reveal.

### Named Rules

**The Twelve Rule.** 12px is the default radius. Reach past it only with reason:
18px means "this is a hero surface," 8px and below mean "this is a small
control." An unconsidered radius is a 12.

## Components

Components are **quiet paper with decisive ink**: containers recede into the
page — soft fills, hairline edges, no shadow — and only the action and the
answer carry weight and color. A card should feel like something written on a
page, not something floating above it.

### Buttons

- **Shape:** softly rounded (12px primary, 14px secondary).
- **Primary** (`FilledButton`): terracotta fill, near-white label, themed to a
  48px minimum height so it reads as a full-width commitment by default.
  **Gotcha:** the theme sets `minimumSize: Size.fromHeight(48)`, which forces
  infinite width under loose constraints — inside a `Wrap`, or beside a flex
  sibling in a `Row`, override with `minimumSize: Size(0, 44)` or wrap in
  `Flexible`. An `IconButton` is immune and is the better suffix beside an
  `Expanded` field.
- **Pressed:** fill deepens to Terracotta Deep. No scale, no bounce.
- **Secondary** (`TextButton` / `OutlinedButton`): warm-raised or transparent
  fill, input-border stroke, terracotta label.

### Chips

- **Style:** Selected Clay fill, terracotta label, 12px radius, ~8×13px padding,
  no border. Unselected chips fall back to the card fill with a hairline.
- **State:** selection is expressed by fill, never by an outline change alone.
- **Chaos chip:** the one chip with its own palette — Chaos Chip fill and text,
  no side border, compact density. It lives in the HUD's always-visible tier
  because chaos is narrative state, not a control.

### Cards / Containers

- **Corner style:** 12px standard, 18px hero.
- **Background:** Blush Card standard; the result and AI-nudge cards use a soft
  diagonal gradient instead of a flat fill (`#FDEFE6 → #F8E0D2` for results,
  `#FCEDE3 → #F7E0D2` for the AI nudge, top-left to bottom-right).
- **Shadow strategy:** none — see Elevation. The expanded result card is the
  sole exception.
- **Border:** 1px hairline standard; hero border on gradient cards.
- **Internal padding:** 12–16px; 16px on anything containing prose.

### Inputs / Fields

- **Style:** Warm Raised fill, input-border stroke, 18px radius on the composer
  (it is the widest, softest thing on the journal page), 12px elsewhere.
- **Placeholder:** Faint Ink, sentence case, directive ("Write in your journal…").
- **Focus:** border shifts to terracotta. No glow, no shadow.

### Modals: Sheets, Dialogs, Snackbars

Modals are this system's second-most-common container after the card — 60+ call
sites — and until 2026-07-24 every one of them rendered at raw Material
defaults, the largest surface outside the tome.

- **Bottom sheet** (the default modal; tools, pickers, editors, settings all
  open this way): Lamplit Cream fill, no surface tint, an 18px radius on the
  **top corners only** — a page lifting from the bottom of the book.
- **Dialog** (reserved for a decision that must be answered before continuing —
  confirmations, small edits): Lamplit Cream fill, no surface tint, 18px radius
  all round.
- **Snackbar** (the transient receipt: logged, undone, saved): the page speaking
  back, so it inverts — Deep Ink fill with cream label text and a terracotta
  action. Undo is the archetypal action and must stay reachable.

**Choose by weight:** a sheet for anything the player browses or composes in, a
dialog only for a question, a snackbar only for what already happened. A tool
that opens in a dialog is nearly always a sheet wearing the wrong clothes.

### States: Focus, Disabled, Hover

- **Focus:** terracotta at 12% as the focus fill, with the accent border shift on
  inputs. Never remove a focus indicator — desktop keyboard shortcuts ship and
  web is the front door, so keyboard traversal is a real path, not a hypothetical.
- **Hover:** terracotta at 6%. Present on desktop, meaningless on touch; never
  make it load-bearing for comprehension.
- **Disabled:** Faint Ink. Material's default disabled gray is banned by the
  warm-only palette, so `disabledColor` is themed. Prefer *hiding* an
  inapplicable control over disabling it — the system-gating model means most
  "disabled" states should simply not be on screen.

### Iconography

Material icons, **outlined by default**, filled only when the thing is active or
selected. The size vocabulary in use is four steps and should stay that way:

- **14px** — inside a 24px icon tile, or paired with the `✦` badge.
- **16px** — chip avatars and inline row markers.
- **18px** — the workhorse; list rows, status glyphs, card headers.
- **20px** — icon buttons in a card header (reroll, open-in-tool, overflow).

**One glyph, one meaning** across the whole app: no two affordances share an
icon, and no affordance changes icon between surfaces. Tool search is the
command mark; journal filtering is the funnel; `✦` is always and only AI.

### Scene Divider

The journal's chapter break: a centered uppercase eyebrow between two hairlines,
carrying the scene name and the chaos value in Chaos Ochre ("Scene 3 · Chaos 5").
It is the one place the journal stream is allowed to interrupt itself, and it is
tappable — it is also the scene-jump target.

### Roster Lead Card

The lead PC gets a gradient card (hero border, 18px) while companions and NPCs
stay compact raised rows — role expressed as visual weight, not a badge alone.
The card carries a vitals row (label + big value + a 3px progress bar) that is
**sheet-system-aware**: Ironsworn shows Health/Spirit/Supply/Momentum, D&D shows
HP/AC, Shadowdark shows HP plus the torch countdown. Condition chips sit below;
a quick-action row (roll, −, +, overflow) sits above a hairline.

### Campaign Spine Row

The launcher's campaign list: a ~6px identity-hue spine on the leading edge, an
icon tile, the name, and a quiet genre/system line. Raw system tags reduce to
dots. The spine is the only place the identity hues appear, and it is how a
player recognizes a campaign before reading its name.

### The Map Canvas (signature)

The most distinctive drawing in the product, and it follows its own internal
logic rather than the component language:

- **Rooms** paint as fused cell rectangles with outward-edge outlines; a
  single-cell room keeps the simpler rounded-square path.
- **Caves and tunnels** paint as organic blobs — a deterministic wobbly
  perimeter seeded from the room id hash, so a given cave always draws the same
  way. Geology, not decoration.
- **Doors** are glyphs on the room edge and encode kind: open is a triangle, a
  door is a bar, locked is a crossed bar.
- **Hexes** are filled with the terrain palette (see The Cartography Exception)
  and reveal as the player travels.
- **Chrome floats over the canvas, never above it in the layout.** The map fills
  its pane in a `Stack`; a compact verb bar, a foldable tool group, and a bottom
  detail overlay float on top, each capped at 45% of the pane. Chrome may crowd
  the map; it may never swallow it.

### Navigation

- **Compact:** Material `NavigationBar`, six verbs, always-on labels. Disappears
  entirely while the phone composer has focus.
- **Wide:** `NavigationRail` with `labelType: all` and a 1px vertical divider —
  labels are never hidden behind icons alone.
- **Split:** the rail keeps five verbs; the journal becomes a permanent
  right-hand column with a drag handle.
- **Subtabs** within a verb are chips or tabs, never a second nav bar.

### The Result Card (signature component)

The system's centerpiece and its whole argument. Two states:

- **Collapsed:** 12px radius, gradient fill, hero border, no shadow. One line —
  the answer summary in body serif, with a muted trailing roll fragment
  ("Answer Yes (+04)"). Reads as one entry in a stream.
- **Expanded:** 18px radius, answer lift shadow. A source row (24px terracotta
  icon tile + uppercase tracked eyebrow + right-aligned odds + reroll /
  open-in-tool / menu icons), then the **display-size serif answer with its
  italic terracotta tail**, then an intensity caption in 11px muted sans, then
  the action row above a hairline: `✦ Interpret`, `Voice line`, and a pinned
  right-aligned flag.

The gradient, the border, the shadow, and the only 30px type in the system all
exist to do one job: make the moment the oracle answers feel like the moment the
oracle answers.

### The AI Badge (signature component)

A single `✦` glyph (`Icons.auto_awesome`) in terracotta, optionally followed by a
6px gap and a 600-weight terracotta label. It marks **every** AI-assisted action
in the application without exception — Interpret, Voice, Recap, Narrate, Flesh
Out, Inspire, Ask. One glyph, one meaning: this was suggested, not rolled.

## Do's and Don'ts

### Do:

- **Do** read colors through `context.juice` (`JuiceTokens`) on any
  player-facing surface, and migrate a raw `ColorScheme` surface when you touch
  it.
- **Do** keep the serif/sans split absolute: fiction in Newsreader, machinery in
  Hanken Grotesk.
- **Do** separate surfaces with a hairline (`#EFE0D6` / `#3D3229`) or a tonal
  step, not a shadow.
- **Do** default to a 12px radius and reserve 18px for hero surfaces.
- **Do** mark every AI-assisted action with the shared `AiBadge` `✦`, and design
  the surface to be complete and good with AI switched off — that is the
  default state.
- **Do** verify every new row at 375px width and with the reading text-scale
  raised; both are shipped user-facing conditions.
- **Do** gate every animation behind `MediaQuery.disableAnimations`, and prefer a
  finite `forward()` over a `repeat()` — a perpetual loop hangs every
  `pumpAndSettle` in the test suite.
- **Do** give both brightnesses a real value when adding a token; there is no
  auto-derived dark mode here.
- **Do** open a bottom sheet by default; reserve dialogs for a question that
  must be answered and snackbars for a receipt of something already done.
- **Do** hold a 44×44 hit area even where the paint is compact, and verify new
  rows at a raised reading text-scale as well as at 375px.
- **Do** hide an inapplicable control rather than disabling it — the
  system-gating model means most disabled states shouldn't be on screen at all.
- **Do** keep `test/design_system_test.dart` green. It codifies the four rules
  that are mechanically checkable — One Shadow, Warm-Only, Two-Voice, and the
  Migration ratchet — and it runs in the ordinary `flutter test` sweep. When a
  rule genuinely needs to widen, widen it *here* in DESIGN.md and in the test in
  the same commit, with the reason.

### Don't:

- **Don't** introduce cool grays, blues, pure black, or pure white. The system is
  warm-only, and `#241C17` / `#FFFBF9` are its poles.
- **Don't** spend Lamplight Terracotta on anything that is not an action or an
  answer, and don't borrow Chaos Ochre, Lead Gold, or Quiet Sage for decoration —
  each means exactly one thing.
- **Don't** add a `BoxShadow`. The expanded result card holds the only one, plus
  the sanctioned primary-button lift.
- **Don't** set anything in uppercase except the 11px tracked sans eyebrow.
- **Don't** let it read as a **SaaS dashboard** (cool grays, blue accents, KPI
  card grids), a **dice-roller utility** (neon numerals, dark gamer chrome,
  glassmorphism), or **default Material 3** (untouched seed colors, Roboto,
  stock elevation ramps). Those three are the confirmed anti-references.
- **Don't** put a `FilledButton` under loose or unbounded width constraints
  without overriding `minimumSize` — the 48px full-width theme throws "forces an
  infinite width" inside a `Wrap` or beside a flex sibling.
- **Don't** branch layout on a height threshold in the journal body; one tree at
  every height, floored at 360px.
- **Don't** hard-code a hex where a token exists, and don't add a token that
  duplicates one already in `JuiceTokens`. The hero border spent months as two
  near-identical literals at four call sites with no dark value; that is what
  this rule is for.
- **Don't** remove a focus indicator, and don't rely on hover to communicate
  anything — desktop keyboard traversal is a real path and touch has no hover.
- **Don't** spend `colorScheme.error` on "unavailable", "finished", or "empty".
  Those are Faint Ink. Red means something went wrong.
- **Don't** restore the **paper-grain texture**. The original UX-refresh handoff
  specified a `CustomPainter` dot field (1px dots, ~5% brown, 15px grid) under
  the cream background. It was never built, and the tome reads as paper without
  it — the warm fills and hairlines already do that work. This is a deliberate
  omission, not an unfinished task; reopening it needs a new decision, not a
  reading of the old handoff.
- **Don't** treat the old handoff (`docs/design_handoff_juice_ux_refresh/`) as
  current authority. It is the origin document and remains useful as rationale,
  but where it and this file disagree, **this file and the shipped code win** —
  the muted/faint inks were darkened for WCAG AA after it was written, and the
  identity palette was rewarmed.
