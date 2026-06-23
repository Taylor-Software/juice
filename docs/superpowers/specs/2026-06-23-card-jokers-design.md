# Card jokers: opt-in 54-card standard deck

**Date:** 2026-06-23
**Status:** Design — approved

## Problem

The standard card oracle is a fixed 52-card deck (`kPlayingDeck`). Some
solo-RPG systems use a 54-card deck including the two jokers (as wild draws the
player interprets). The deck deserves an opt-in jokers variant.

## Decisions (from brainstorming)

- **Opt-in** per campaign (default off): jokers are not forced on the 52-card
  users.
- **Identity-only, no art, no mechanic.** Jokers ship as the names `Red Joker`
  / `Black Joker` (facts-only, consistent with the card-identities posture).
  The matching-style CC0 art does not exist (the Fomin English-pattern deck has
  no jokers on Wikimedia Commons), so jokers render with no image — `CardImage`
  already shows nothing for an unknown card. No fetch, no `card_images` change.
- Assigning a joker any meaning (wild / timer / twist) is interpretation, so
  it stays out — the player supplies meaning, same as every other card.

## Architecture

### 1. Data — `lib/engine/models.dart` (facts-only constants)

```dart
/// The two jokers, by identity only (no asserted meaning). Used by the opt-in
/// 54-card variant.
const kPlayingJokers = ['Red Joker', 'Black Joker'];

/// The standard deck plus the two jokers (54 cards), for the opt-in variant.
final List<String> kPlayingDeckWithJokers = [...kPlayingDeck, ...kPlayingJokers];
```

`kPlayingDeckWithJokers` is `final` (not `const`) because `kPlayingDeck` is a
computed `final` list.

### 2. State — `DecksState.jokers` (`lib/engine/models.dart`)

`DecksState` gains a `bool jokers` (default `false`):

```dart
const DecksState({
  this.standard = const DeckState(),
  this.tarot = const DeckState(),
  this.jokers = false,
});
final bool jokers;

DecksState copyWith({DeckState? standard, DeckState? tarot, bool? jokers}) =>
    DecksState(
      standard: standard ?? this.standard,
      tarot: tarot ?? this.tarot,
      jokers: jokers ?? this.jokers,
    );

Map<String, dynamic> toJson() => {
      'standard': standard.toJson(),
      'tarot': tarot.toJson(),
      'jokers': jokers,
    };

factory DecksState.fromJson(Map<String, dynamic> j) => DecksState(
      standard: DeckState.fromJson(j['standard']),
      tarot: DeckState.fromJson(j['tarot']),
      jokers: j['jokers'] == true, // tolerant: missing/non-bool → false
    );
```

Persisted by the existing `decksProvider` (`juice.decks.v1.<sessionId>`, in
`sessionScopedKeys`), so the preference is per-campaign and auto-exported.

### 3. Draw selection + toggle — `DecksNotifier` (`lib/state/providers.dart`)

A helper for the active standard deck list:

```dart
List<String> _standardDeck(DecksState s) =>
    s.jokers ? kPlayingDeckWithJokers : kPlayingDeck;
```

In `draw`, the standard-deck branch passes `_standardDeck(cur)` as `deck`
instead of the literal `kPlayingDeck` (tarot path unchanged). `drawAndLog`
needs no change — it delegates to `draw`, so it inherits the selection.
`Oracle.drawCard` already reshuffles when `order.length != deck.length`, so a
mid-session size change (52 ↔ 54) reshuffles cleanly.

```dart
/// Toggles the jokers variant for the standard deck, resetting the standard
/// DeckState so the next draw reshuffles a full 52- or 54-card deck (keeps the
/// remaining-readout denominator coherent).
Future<void> setJokers(bool value) async {
  final cur = state.valueOrNull ?? await future;
  await _save(cur.copyWith(jokers: value, standard: const DeckState()));
}
```

### 4. UI — Cards section (`lib/features/fate_screen.dart`)

In the existing `Wrap` (standard readout / Reshuffle / tarot readout /
Reshuffle), beside the standard readout:

- A `FilterChip` (`Key('cards-jokers-toggle')`, label `'Jokers'`,
  `selected: decks.jokers`, `onSelected: (v) => ref.read(decksProvider.notifier)
  .setJokers(v)`).
- The standard readout denominator becomes the active deck length:
  `final deckLen = decks.jokers ? kPlayingDeckWithJokers.length :
  kPlayingDeck.length;` → `'Deck ${decks.standard.remainingOf(deckLen)}/$deckLen'`.

No change to the draw buttons, the tarot path, the reference, or `card_images`.

## Testing

- `card_oracle` (pure + provider):
  - `kPlayingDeckWithJokers.length == 54` and contains both jokers; `kPlayingDeck`
    stays 52 (unchanged).
  - `DecksState` with `jokers: true` round-trips through JSON; `fromJson` of a
    payload missing `jokers` defaults to `false`.
  - `setJokers(true)` persists `jokers == true` and resets `standard` to a fresh
    `DeckState`; with jokers on, a `draw(tarot: false)` yields a standard
    `order.length == 54` (drew from the 54-card deck); with jokers off, `== 52`.
- `fate_cards` (widget): the `cards-jokers-toggle` chip is present (cards system
  enabled); tapping it on makes the standard readout show `/54`.

## Out of scope (YAGNI)

- Joker art (no matching CC0 source); any joker mechanic (wild/timer/twist —
  interpretation); jokers in the tarot deck; per-draw joker control.

## Files touched

| File | Change |
|------|--------|
| `lib/engine/models.dart` | `kPlayingJokers`, `kPlayingDeckWithJokers`; `DecksState.jokers` (+ copyWith/JSON) |
| `lib/state/providers.dart` | `_standardDeck` selection in `draw`/`drawAndLog`; `DecksNotifier.setJokers` |
| `lib/features/fate_screen.dart` | `cards-jokers-toggle` chip + readout denominator |
| tests | `card_oracle_test` (deck/state/provider), `fate_cards_test` (toggle) |
