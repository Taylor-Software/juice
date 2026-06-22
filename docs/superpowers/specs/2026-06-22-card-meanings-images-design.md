# Card meanings (no-AI) + guide + reference + public-domain card images

**Date:** 2026-06-22
**Status:** Design — approved (pending spec review)

## Problem

The opt-in `cards` system draws from a 52-card standard deck and a 78-card tarot
deck, but ships **card identities only** — no meanings. The original card-deck
spec omitted them deliberately ("divinatory interpretations are copyrighted
prose"). Result: a newcomer who draws "The Tower (reversed)" gets a name and
nothing else, and the only interpretation path is the on-device AI. We want a
useful, **AI-free** baseline: a generic meaning for every tarot card (upright +
reversed), a how-to guide, a browsable reference, and — bundled — the actual
card art.

## Decisions (from brainstorming)

- **Meaning source: original authored generic text.** We write our own short
  upright/reversed descriptions. Original content = no copyright, no attribution,
  no vendored prose — same posture as the system primers and facts-only sheets.
  Common card associations are ideas, not protected expression.
- **Coverage: all 78 tarot cards, upright + reversed.** 22 Majors distinct; 56
  Minors concise (suit theme + rank/court).
- **Surfacing: on-draw + journal + guide page + browsable reference.**
- **Images: bundle public-domain / CC0 art** for BOTH decks (tarot 78 + standard
  52). Standard deck is images-only (no meanings; not reversible).

## Licensing analysis (load-bearing)

- **Meanings** — original authored text. No source, no attribution, no
  vendoring. Inside the free / facts-only model.
- **Tarot images** — Rider–Waite–Smith (Pamela Colman Smith, 1909). Public
  domain in the US (pre-1929) and in life+70 jurisdictions (Smith d. 1951 → PD
  2022). Faithful scans of PD 2-D art carry no new copyright (US: *Bridgeman v.
  Corel*). Bundling adds **no** legal/attribution obligation.
- **Standard images** — must be a **PD or CC0** set (e.g. Dmitry Fomin's CC0
  English-pattern deck on Wikimedia Commons). **Avoid** attribution/copyleft sets
  such as Chris Aguilar's "Vectorized Playing Cards" (LGPL) — that would add an
  obligation the licensing rule forbids.
- **Diligence requirement:** the fetch script (P2) must record each image's
  source URL + license tag, and the build fails review if any asset isn't PD/CC0.
- **Courtesy credit** (optional, NOT a legal obligation): one line in the guide /
  About — "Card images: Rider–Waite–Smith (1909) and a CC0 standard deck, public
  domain." Trivial to drop.

This deviates from "minimal vendoring" by bundling ~130 images, but only with
unencumbered assets, per the owner's explicit choice.

---

## Phase 1 — meanings + guide + reference (text only)

### P1.1 Data — `lib/engine/tarot_meanings.dart` (pure, authored)

```dart
class TarotMeaning {
  const TarotMeaning(this.upright, this.reversed);
  final String upright;
  final String reversed;
}

/// Authored generic associations, keyed by the exact card names in kTarotDeck.
const Map<String, TarotMeaning> kTarotMeanings = {
  'The Fool': TarotMeaning(
      'Beginnings, leaps of faith, open roads, innocence.',
      'Recklessness, hesitation at the edge, a poorly judged risk.'),
  // … all 78 …
};

/// Parse a drawn card string ("The Tower (reversed)") into name + orientation
/// + its meaning (null if the card isn't tarot, e.g. a standard-deck draw).
({String name, bool reversed, TarotMeaning? meaning}) readTarot(String shown);
```

- 22 Majors authored individually. 56 Minors authored concisely from a per-suit
  theme (Wands = drive/creativity, Cups = emotion/relationship, Swords =
  conflict/intellect, Pentacles = work/material) crossed with rank (Ace = seed,
  pip progression, Page/Knight/Queen/King court roles). Each entry is 1–2 short
  clauses, upright and reversed.
- Pure file → no rootBundle → safe in tests. A test asserts every `kTarotDeck`
  entry has a `kTarotMeanings` key (full coverage) and upright ≠ reversed.

### P1.2 On-draw display (`lib/features/fate_screen.dart`)

After a tarot draw, below the result `ResultCard`, render the meaning:
`readTarot(_cardLast!.summary)` → if `meaning != null`, show the orientation
label + the upright/reversed text. Standard-deck draws return null → nothing
extra (no collision: standard names like "Ace of Spades" aren't tarot keys).

### P1.3 Journal integration

When a tarot card is logged (the `ResultCard` "add to journal" action,
`sourceTool: 'cards'`), fold the meaning into the entry body so the reading is
preserved without AI, e.g. body = `"The Tower (reversed) — <reversed text>"`.
Implementation: build the logged text from `readTarot(...)` at the call site in
`fate_screen`; standard draws log unchanged.

### P1.4 Browsable reference — `lib/features/tarot_reference.dart`

A `ConsumerWidget` (opened as a route or sheet) listing all 78 cards grouped
into sections — **Major Arcana**, **Wands**, **Cups**, **Swords**,
**Pentacles** — with a search box, reusing the sections+search pattern from
`tables_screen.dart` (ExpansionTile + filter). Each row shows the card name and
its upright + reversed text. Opened via a **"Card meanings"** button added to
the Cards section in `fate_screen` (gated on `systems.contains('cards')`), and
linked from the guide page.

### P1.5 Guide — Help page (`assets/help_data.json`, authored)

Add a **"Reading tarot"** page under the *User guide* section: what upright vs
reversed means, the four suits + Major/Minor split, a simple "how to read a
single card / a few cards" note, and a plain disclaimer: *"These are generic
starting points, not fixed truths — read them against your story."* Linked to
the reference. (Help is hand-authored JSON; no build script.)

---

## Phase 2 — bundled public-domain card images

### P2.1 Assets

- `assets/tarot/<slug>.png` — 78 RWS images. `slug` from the card name
  (e.g. `the-tower`, `ace-of-wands`).
- `assets/playing/<slug>.png` — 52 standard images (e.g. `ace-of-spades`).
- Register `assets/tarot/` and `assets/playing/` in `pubspec.yaml`.
- **Fetch scripts** `fetch_tarot_images.py` / `fetch_playing_images.py`:
  download each card from its documented PD/CC0 source (Wikimedia Commons),
  record source URL + license per file in a generated `ASSET_SOURCES.md`, and
  resize/optimize (max ~600 px long edge, PNG or WebP) to bound app size.
  Re-runnable; the scripts are the provenance record (like `build_oracle.py`).

### P2.2 Image helpers (pure)

```dart
String? tarotImageAsset(String cardName);   // 'assets/tarot/the-tower.png'
String? playingCardImageAsset(String cardName);
String? cardImageAsset(String cardName);    // tries tarot then playing
```
Slugger is shared/tested. Returns null for unknown names.

### P2.3 Reversed rendering

Reversed tarot cards render the SAME asset rotated 180° (`RotatedBox`/
`Transform.rotate`) — no separate reversed assets. Standard deck is upright-only.

### P2.4 Render points

- **Draw card** (P1.2 area): show the image above/beside the meaning.
- **Reference rows** (P1.4): a leading thumbnail per card.
- **Journal entry:** a `cards`-sourced entry renders its bundled image inline,
  derived from the card name in the entry (rotated if reversed). **No BlobStore /
  export bundling** — the image is an app asset, always present; the entry only
  needs the card identity it already stores. A small renderer hook in
  `journal_screen` detects `sourceTool == 'cards'` + a resolvable
  `cardImageAsset` and shows the thumbnail.

### P2.5 Credit

Optional courtesy line appended to the guide page and/or the About/licenses help
page (not a legal obligation; PD/CC0).

---

## Testing

- `test/tarot_meanings_test.dart` — every `kTarotDeck` card has a meaning;
  `readTarot` parses "(reversed)" and orientation; returns null for a standard
  card; upright ≠ reversed.
- `test/card_images_test.dart` (P2) — `cardImageAsset` slugging for sample
  cards; null for unknown; (optionally) assert every deck card maps to a declared
  asset path.
- `test/tarot_reference_test.dart` — sections render (Major Arcana + suits),
  search filters, a card shows upright + reversed text (+ thumbnail in P2).
- `fate_screen` test — drawing a tarot card shows the meaning; logging includes
  it; standard draw shows none.
- Help data test — the "Reading tarot" page exists and is well-formed.

## Out of scope / deferred

- Cartomancy meanings for the standard deck (images only chosen).
- Per-card esoteric depth — text stays concise/generic.
- User-imported custom decks/art (bundled-only for now).
- Sharper re-rendering, alternate decks, animations.

## Files touched

| File | Phase | Change |
|------|-------|--------|
| `lib/engine/tarot_meanings.dart` | P1 | **new** — `TarotMeaning`, `kTarotMeanings` (78), `readTarot` |
| `lib/features/fate_screen.dart` | P1/P2 | on-draw meaning + "Card meanings" button; image on draw |
| `lib/features/tarot_reference.dart` | P1/P2 | **new** — sections+search reference (+ thumbnails) |
| `lib/features/journal_screen.dart` | P1/P2 | tarot card entry carries meaning; render bundled image |
| `assets/help_data.json` | P1 | **new** "Reading tarot" guide page (+ credit) |
| `lib/engine/card_images.dart` | P2 | **new** — slug + asset-path helpers |
| `assets/tarot/*`, `assets/playing/*` | P2 | **new** — 78 + 52 PD/CC0 images |
| `fetch_tarot_images.py`, `fetch_playing_images.py` | P2 | **new** — provenance + fetch/optimize |
| `pubspec.yaml` | P2 | register the two asset dirs |
| tests above | P1/P2 | **new** |
