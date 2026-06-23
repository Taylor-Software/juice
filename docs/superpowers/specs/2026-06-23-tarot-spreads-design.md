# Tarot spreads: positional multi-card draws

**Date:** 2026-06-23
**Status:** Design — approved

## Problem

The card oracle draws one card at a time (`cards`-gated Cards section in
`fate_screen`, `/card` and `/tarot` slash commands, HUD quick-draw). A
single card is the atom; the natural next unit is the **spread** — an ordered
multi-card draw where each position carries its own framing (Past / Present /
Future, etc.). Spreads are the canonical way solo players turn a tarot deck
into a structured prompt.

## Licensing posture

Spreads ship as **authored facts**, consistent with the existing tarot
meanings (`tarot_meanings.dart`) and the project's facts-only rule for new
content. A spread is a traditional *method* (the concept of a three-card
past/present/future layout, the Celtic Cross arrangement) — non-copyrightable.
Position labels are my own short functional wording, NOT transcribed from any
published deck's booklet. No attribution, no vendored prose. The per-card
meanings reuse the already-authored `kTarotMeanings`.

## Architecture

### 1. Data — `lib/engine/tarot_spreads.dart` (new, pure)

```dart
class TarotSpread {
  const TarotSpread(this.id, this.name, this.positions);
  final String id;               // 'three-card'
  final String name;             // 'Past · Present · Future'
  final List<String> positions;  // ['Past', 'Present', 'Future']
  int get count => positions.length;
}

const kTarotSpreads = <TarotSpread>[
  TarotSpread('three-card', 'Past · Present · Future',
      ['Past', 'Present', 'Future']),
  TarotSpread('cross', 'Five-card Cross',
      ['Situation', 'Challenge', 'Past', 'Future', 'Outcome']),
  TarotSpread('celtic-cross', 'Celtic Cross', [
    'Present', 'Challenge', 'Foundation', 'Recent Past', 'Crown',
    'Near Future', 'Self', 'Environment', 'Hopes & Fears', 'Outcome',
  ]),
];
```

Position labels are functional descriptors authored for this app.

### 2. Engine — `Oracle.drawSpread` (`lib/engine/oracle.dart`)

```dart
/// Draws [positions.length] cards from [deck] without replacement, threading
/// [state] through the existing per-card [drawCard] (so it reshuffles when the
/// deck is exhausted). Each card is reversible when [reversible]. Returns the
/// position→card mapping, the next DeckState to persist, and a GenResult whose
/// summary/asText fold in each position + card + tarot meaning for journaling.
({List<({String position, String shown})> cards, DeckState next, GenResult result})
    drawSpread({
  required List<String> deck,
  required DeckState state,
  required TarotSpread spread,
  bool reversible = false,
}) { ... }
```

- Internally loops `drawCard` once per position, passing the previous call's
  `next` as the new `state`. Title for each per-card call is the position label
  (only the aggregate GenResult is surfaced).
- `GenResult`:
  - `title`: `'Tarot Spread'`
  - `summary`: `spread.name` (e.g. `'Past · Present · Future'`)
  - `rolls`: one `Roll` per position — `label: position`, `value: shown`
    (the card, with `(reversed)` when reversed).
- The aggregate `GenResult` itself carries no meanings (just position→card in
  its rolls). Meanings are folded into the **journal body** separately, by the
  `spreadBody` helper (§4), so the logged entry reads as a full spread with
  meanings — interpretable by the standard per-entry Interpret. The `GenResult`
  is still stored as the entry payload for re-render.

`drawSpread` is pure (no persistence); the provider persists `next`.

### 3. Provider — `DecksNotifier.drawSpread` (`lib/state/providers.dart`)

```dart
/// Draws a [spread] from the tarot deck, persisting the advanced DeckState.
/// Returns the result for the caller to render + log (mirrors how the Cards
/// section draws-then-logs a single card, rather than auto-logging).
Future<({List<({String position, String shown})> cards, GenResult result})>
    drawSpread(Oracle oracle, TarotSpread spread) async {
  final cur = state.valueOrNull ?? const DecksState();
  final out = oracle.drawSpread(
    deck: kTarotDeck, state: cur.tarot, spread: spread, reversible: true);
  await _save(cur.copyWith(tarot: out.next));
  return (cards: out.cards, result: out.result);
}
```

Tarot-only (spreads use the 78-card deck; a standard-deck spread is YAGNI).

### 4. UI — Cards section (`lib/features/fate_screen.dart`)

Below the existing single-card draw row, gated by the same
`systems.contains('cards')`:

- A **spread dropdown** (`Key('spread-picker')`, `DropdownButton<TarotSpread>`
  over `kTarotSpreads`, default `kTarotSpreads.first`) held in a new
  `_spread` state field.
- A **Draw spread** button (`Key('cards-draw-spread')`) →
  `decksProvider.notifier.drawSpread(oracle, _spread)`; result stored in a new
  `_spreadLast` state field.
- When `_spreadLast != null`, render a **labeled grid**: a `Wrap` of position
  tiles, each a fixed-width `Column` with the position label, `CardImage`
  (resolved via `readTarot(shown)` for name + reversed), and the card
  name + orientation + meaning line. Uniform for all three spreads — no
  bespoke geometry.
- A **Log** button (`Key('spread-log')`) writes **one** journal entry:
  `addResult('Tarot Spread', _spreadBody(...), sourceTool: 'cards',
  payload: result.toPayload())`, then a "Added to journal" snackbar.

Shared pure helper for the journal body (so engine GenResult + logged text
agree), e.g. in `tarot_spreads.dart`:

```dart
/// Multi-line journal body for a drawn spread: the spread name, then one
/// 'Position — Card' line per position with its tarot meaning folded in.
String spreadBody(String spreadName,
    List<({String position, String shown})> cards) { ... }
```

### 5. Deck state

Reuses the tarot `DeckState` in `DecksState`. Drawing an N-card spread advances
`drawn` by N. The Cards-section remaining readout (`decks.tarot.remainingOf`)
already reflects this. **Edge case:** a spread that spans the deck's exhaustion
triggers a mid-spread reshuffle (per-card in `drawCard`), so a card already in
the same spread could recur. This only occurs within N cards of exhausting a
78-card deck; not deduped (would complicate the threaded draw for a rare case).
Noted, not handled.

## Testing

- `tarot_spreads_test` (pure): `kTarotSpreads` ids unique; every spread's
  `positions.length == count` and non-empty; `spreadBody` includes each
  position label and (for tarot cards) an orientation+meaning line.
- `oracle` test: `drawSpread` for a 3-card spread returns 3 cards, advances
  `next.drawn` by 3, and the `GenResult` has one roll per position with
  matching labels.
- `fate_cards_test` (widget): selecting a spread + tapping `cards-draw-spread`
  renders 3 `CardImage`s for the three-card spread; `spread-log` adds one
  `cards` journal entry whose body contains all three position labels.

## Out of scope (YAGNI)

- `/spread` slash command (needs a picker; the single-card `/card` `/tarot`
  stay the quick-draw path); HUD quick-draw for spreads.
- Literal geometric Celtic-Cross layout (cross + staff) — fragile under the
  tool-host's loose width constraints for little gain over the grid.
- Per-position authored meaning overrides (position-specific interpretations);
  standard-deck spreads; saving/naming a spread; reversed-orientation toggle.

## Files touched

| File | Change |
|------|--------|
| `lib/engine/tarot_spreads.dart` | new: `TarotSpread`, `kTarotSpreads`, `spreadBody` |
| `lib/engine/oracle.dart` | `drawSpread` (loops `drawCard`, threads state) |
| `lib/state/providers.dart` | `DecksNotifier.drawSpread` (persist + return) |
| `lib/features/fate_screen.dart` | spread picker + draw button + grid + log |
| tests | `tarot_spreads_test`, `oracle` spread test, `fate_cards_test` |
