# Dice reroll + card-deck oracles — design

**Date:** 2026-06-22
**Scope:** Two independent additions to the randomizer/oracle tooling, shipped as
two PRs. (A) make every dice roll rerollable; (B) add playing-card + tarot decks
as stateful oracles.

---

## A. Dice rerolling

**Problem.** `/dice` slash-command rolls are rerollable from their journal entry
(`entry-reroll-<id>` → re-runs the command, `journal_screen.dart`). But the
**Dice Roller tool** (`dice_roller_screen.dart`, also shown via `dice_sheet`)
logs rolls without reroll metadata, and its result card has no in-place reroll.
So a tool-rolled die can't be re-rolled.

**Design.**
- `dice_roller_screen.dart`: when logging, add `'expression': result.expression`
  to the payload (the normalized notation, e.g. `2d6+1`). Add a **"Roll again"**
  `ResultAction` to the result `ResultCard` that re-rolls `_last.expression` in
  place (local `setState`).
- `journal_screen.dart`:
  - `_canReroll(e)` → also true when `e.payload?['expression'] is String` and the
    oracle is available (in addition to the existing `rerollable`+`command` path).
  - `_reroll(e)` → if the entry has `command`, keep the existing command path;
    else if it has `expression`, run `parseDice(expr).roll(oracle.dice)`, build a
    `GenResult`, and `addResult(..., sourceTool: 'dice', payload: {...,
    'expression': expr})` so the new entry stays rerollable.

**Tests.** A dice-roller entry carries `expression` and is rerollable from the
journal; the in-place "Roll again" yields a fresh roll of the same expression.

---

## B. Card-deck oracles (playing cards + tarot)

**Why.** Drawing from a deck is a classic solo-RPG oracle. Fits the existing
oracle ecosystem (sits beside Fate Check / Roll High / Mythic).

### System
New opt-in system `'cards'` — **not** in `kAllSystems` (off for legacy/default
campaigns, like `dnd`/`shadowdark`). Add `kSystemLabels['cards'] = 'Cards'`. The
New-campaign and Edit-systems dialogs already enumerate `kSystemLabels`, so no UI
change is needed to toggle it.

### Data — authored constants (`models.dart`), facts-only
- `kPlayingDeck`: 52 cards (ranks A,2–10,J,Q,K × suits ♠♥♦♣). No jokers (a future
  variant). Identities only.
- `kTarotDeck`: 78 cards — 22 Major Arcana (The Fool … The World) + 56 Minor
  (Ace–10, Page, Knight, Queen, King × Wands, Cups, Swords, Pentacles). Names only.
- **No meaning/keyword tables.** Divinatory interpretations are copyrighted prose;
  we ship card identities (non-copyrightable facts) and let the player — or the
  on-device interpreter — supply meaning. No build script (trivial static facts).

### Deck state — isolated unit
- `DeckState { List<int> order, int drawn }` — `order` is a shuffled permutation
  of card indices; `drawn` is how many have been consumed from the front.
  `remaining => order.length - drawn`. JSON round-trips; tolerant `fromJson`.
- `DecksState { DeckState standard, DeckState tarot }`, persisted by a new
  session-scoped `decksProvider` at key `juice.decks.v1.<sessionId>` (registered
  in `sessionScopedKeys` so it auto-exports in campaign files). Kept separate from
  `CrawlState` — decks are not crawl/hexcrawl state (single responsibility).

### Engine (`oracle.dart`)
`GenResult drawCard(...)` is awkward because the draw mutates persisted state, so
the engine method returns both the result and the next state:

```
({GenResult result, DeckState next}) drawCard({
  required List<String> deck,      // kPlayingDeck or kTarotDeck
  required DeckState state,
  required String title,           // 'Card' | 'Tarot'
  bool reversible = false,         // tarot orientation
})
```
- If `state.remaining == 0`: reshuffle — `order` = a `Dice`-shuffled `[0..n)`,
  `drawn = 0`.
- Pop `card = deck[order[drawn]]`; `drawn++`.
- If `reversible`: flip `dice.coin()` for orientation; append " (reversed)" to the
  summary and a `Roll(label:'Orientation', …)`.
- `GenResult(title: title, summary: cardName, rolls: [Roll('Card', cardName), …,
  Roll('Deck', 'N/total')])`.

Shuffle uses the injected seedable `Dice`, so tests are deterministic.

### UI — `fate_screen.dart`
A "Cards" section (new `FateSection.cards`), rendered only when
`systems.contains('cards')`:
- **Draw card** (52) and **Draw tarot** (78, reversible) buttons. Each reads
  `decksProvider`, calls `oracle.drawCard(...)`, persists `next`, and sets the
  section's `_lastCard` result.
- A `remaining 41/52 · 70/78` readout + **Reshuffle** buttons per deck
  (reset that `DeckState` to empty → next draw reshuffles).
- The drawn card renders in a `ResultCard` with `onLog` (sourceTool `'cards'`) and
  an **Interpret** action that opens the existing `oracle_interpretation_sheet`
  with the card as input (device-only; on web the LLM is disabled, so the action
  is hidden / a no-op like other AI affordances).

### Deferred (noted, not built)
- Slash commands (`/draw`, `/tarot`) — the command registry's `run(oracle,args)`
  is stateless; a stateful deck doesn't fit cleanly.
- HUD quick-draw as a `defaultOracle` option.
- Jokers / multiple-deck variants.

### Tests
- Engine: `drawCard` decrements `remaining`; reshuffles when exhausted; never
  repeats a card within one shuffle (draw the whole deck → all distinct); tarot
  `reversible` produces both orientations over many draws; 52 / 78 counts.
- `DeckState` / `DecksState` JSON round-trip + tolerant parse.
- `fate_screen`: Cards section renders only when `cards` enabled; Draw produces a
  result and decrements the readout; Reshuffle restores the full count.
- Campaign export/import carries `juice.decks.v1` (covered by the generic
  sessionScopedKeys round-trip).
