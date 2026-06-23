# Card quick-access: HUD draw button + /card and /tarot slash commands

**Date:** 2026-06-22
**Status:** Design — approved

## Problem

The card oracle now carries authored meanings + bundled art (#129–#131), but
the only way to draw is Ask → Cards (the `cards`-gated section in
`fate_screen`). The deck deserves the same fast access the rest of the play loop
has — the HUD quick-roll button and composer slash commands.

## Decisions (from brainstorming)

- **HUD quick-draw button** that pulls the **tarot** deck (the showcase: art +
  meaning), beside the existing quick-roll dice button; gated on the `cards`
  system.
- **`/card`** (standard 52) + **`/tarot`** (78) built-in slash commands from the
  composer; palette-suggested only when `cards` is enabled.
- DRY the "draw a card and record it with its meaning" logic into one shared
  path so the HUD, slash commands, and the Cards section agree.

## Architecture

### 1. Shared draw+log core

`lib/engine/tarot_meanings.dart` — new pure helper:

```dart
/// The "\n<Orientation> — <meaning>" suffix for a drawn tarot card, or '' when
/// [shown] isn't a tarot card (e.g. a standard-deck draw).
String tarotMeaningSuffix(String shown) {
  final r = readTarot(shown);
  if (r.meaning == null) return '';
  return '\n${r.reversed ? 'Reversed' : 'Upright'} — '
      '${r.reversed ? r.meaning!.reversed : r.meaning!.upright}';
}
```

`lib/state/providers.dart` — `DecksNotifier.drawAndLog`:

```dart
/// Draws a card (persisting deck state) AND logs it to the journal with its
/// tarot meaning folded in. Returns the GenResult. Used by the HUD button and
/// the /card, /tarot slash commands.
Future<GenResult> drawAndLog(Oracle oracle, {required bool tarot}) async {
  final g = await draw(oracle, tarot: tarot); // existing: draws + persists
  ref.read(journalProvider.notifier).addResult(
        g.title,
        g.asText + tarotMeaningSuffix(g.summary ?? ''),
        sourceTool: 'cards',
        payload: g.toPayload(),
      );
  return g;
}
```

`fate_screen._cardBody` is refactored to `g.asText + tarotMeaningSuffix(g.summary
?? '')` (no behavior change — DRY only). The Cards section keeps its draw → show
inline → manual-log flow (it does not use `drawAndLog`, since it shows the card
before logging).

### 2. HUD quick-draw button (`lib/shared/play_context_hud.dart`)

An `IconButton(key: 'hdr-quick-draw')` in the always-visible row beside
`hdr-quick-roll`, rendered only when `systems.contains('cards')` and `oracle !=
null`. Tooltip "Draw tarot"; on press → `ref.read(decksProvider.notifier)
.drawAndLog(oracle, tarot: true)` then a `Drew <g.summary>` snackbar. The HUD
already exposes `oracle` and `systems` in `build`.

### 3. Slash commands (`lib/features/journal_screen.dart`)

- Consts `_builtinCard = 'card'`, `_builtinTarot = 'tarot'`.
- `_send` dispatch (beside `_builtinScene`/`_builtinRecap`): on `_builtinCard ==
  tok` / `_builtinTarot == tok`, clear the composer and
  `await ref.read(decksProvider.notifier).drawAndLog(oracle, tarot: <bool>)`
  (oracle via `oracleProvider.valueOrNull`; guard null), then a snackbar.
- Palette suggestions (the `showScene`/`showRecap` block): `showCard =
  _builtinCard.startsWith(tok) && cardsOn`, `showTarot = _builtinTarot.startsWith(tok)
  && cardsOn`, where `cardsOn = enabledSystems.contains('cards')`.

## Testing

- `decks_provider` test: `drawAndLog(tarot: true)` adds one `cards` journal entry
  whose body contains an orientation+meaning; `drawAndLog(tarot: false)` adds an
  entry with no meaning suffix; deck state advances.
- HUD (`campaign_header_test`): with `cards` enabled, `hdr-quick-draw` is present
  and tapping it adds a `cards` journal entry; with `cards` disabled, the button
  is absent.
- Journal slash: typing `/card` / `/tarot` + send draws and logs; the palette
  shows the `slash-cmd-card`/`slash-cmd-tarot` suggestions only when `cards` is
  enabled.

## Out of scope (YAGNI)

- Jokers; a HUD button for the standard deck; a configurable default-deck
  setting; per-draw orientation control. Reversed orientation stays the deck's
  coin-flip.

## Files touched

| File | Change |
|------|--------|
| `lib/engine/tarot_meanings.dart` | `tarotMeaningSuffix` helper |
| `lib/state/providers.dart` | `DecksNotifier.drawAndLog` |
| `lib/features/fate_screen.dart` | `_cardBody` reuses the suffix helper |
| `lib/shared/play_context_hud.dart` | `hdr-quick-draw` button (gated on `cards`) |
| `lib/features/journal_screen.dart` | `/card` + `/tarot` dispatch + palette |
| tests | `tarot_meanings_test`, `decks` provider test, `campaign_header_test`, journal slash test |
