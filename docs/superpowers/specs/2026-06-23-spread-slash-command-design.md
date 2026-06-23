# `/spread` slash command — design

**Date:** 2026-06-23
**Status:** Design — approved

## Problem

Tarot spreads (#135) draw only from the Cards section's picker UI. The
single-card draws got `/card` and `/tarot` composer slash commands (#133); the
spread deserves the same fast access. It was deferred because "a spread needs a
picker" — resolved here by a **text argument** that selects the spread instead
of a UI picker.

## Architecture

Mirrors the shipped `/card` / `/tarot` path exactly.

### 1. Pure resolver — `lib/engine/tarot_spreads.dart`

```dart
/// Resolves a spread from free-text [arg]: a case-insensitive match against a
/// spread's id (prefix) or name (substring). Empty or no match → the first
/// spread (the 3-card default). Used by the /spread slash command's argument.
TarotSpread resolveSpread(String arg) {
  final q = arg.trim().toLowerCase();
  if (q.isEmpty) return kTarotSpreads.first;
  for (final s in kTarotSpreads) {
    if (s.id.toLowerCase().startsWith(q) || s.name.toLowerCase().contains(q)) {
      return s;
    }
  }
  return kTarotSpreads.first;
}
```

Examples: `''`/`'3'` → 3-card; `'celtic'` → Celtic Cross (id `celtic-cross`);
`'cross'` → 5-card Cross (id `cross`, matched before `celtic-cross` by list
order); `'five'` → 5-card Cross (name substring).

### 2. Provider — `DecksNotifier.drawSpreadAndLog` (`lib/state/providers.dart`)

```dart
/// Draws a [spread] (persisting deck state) AND logs it as one `cards` journal
/// entry, folding each position's meaning in via spreadBody. Mirrors
/// drawAndLog for single cards; used by the /spread slash command. (The Cards
/// section keeps its own draw → show → manual-log flow.)
Future<void> drawSpreadAndLog(Oracle oracle, TarotSpread spread) async {
  final out = await drawSpread(oracle, spread); // existing: draws + persists
  await ref.read(journalProvider.notifier).addResult(
        'Tarot Spread',
        spreadBody(spread.name, out.cards),
        sourceTool: 'cards',
      );
}
```

No payload (consistent with the Cards-section spread log — `spreadBody` text is
the canonical reading; a single-card payload doesn't fit a multi-card spread).

### 3. Journal — `lib/features/journal_screen.dart`

- Const `static const _builtinSpread = 'spread';` (beside `_builtinCard`/
  `_builtinTarot`).
- Command method:

```dart
Future<void> _drawSpreadCmd(String arg) async {
  final oracle = ref.read(oracleProvider).valueOrNull;
  if (oracle == null) return;
  final spread = resolveSpread(arg);
  await ref.read(decksProvider.notifier).drawSpreadAndLog(oracle, spread);
  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Drew ${spread.name}')),
    );
  }
}
```

- Dispatch in `_send` (beside the `_builtinTarot` case):

```dart
if (_builtinSpread == tok) {
  _composer.clear();
  await _drawSpreadCmd(parsed.rest);
  return;
}
```

  (`parsed.rest` is the post-token argument, same field `/ask` uses.)

- Palette suggestion (beside `showCard`/`showTarot`, where `cardsOn =
  enabledSystems.contains('cards')`):

```dart
final showSpread = _builtinSpread.startsWith(tok) && cardsOn;
```

  A `slash-cmd-spread` chip (rendered when `showSpread`) that clears the
  composer and calls `_drawSpreadCmd('')` (the default 3-card — the chip is the
  quick path; a specific spread is typed as `/spread <token>` + Enter). Add
  `&& !showSpread` to the "No matching command" empty-state guard.

## Testing

- `tarot_spreads_test` (pure): `resolveSpread('')` / unknown → `kTarotSpreads.first`;
  `'celtic'` → the 10-card spread; `'cross'` → the 5-card spread; `'five'`
  (name substring) → the 5-card spread; case-insensitive.
- `decks` provider test (`card_oracle_test`): `drawSpreadAndLog` adds exactly one
  `cards` journal entry whose body contains the spread name and each position
  label, and advances the tarot deck by the spread's card count.
- Journal slash test (`slash_palette_test` or a focused journal test): typing
  `/spread` + send adds one `cards` entry (3-card by default); `/spread celtic`
  adds a 10-card spread entry; the `slash-cmd-spread` palette chip shows only
  when `cards` is enabled.

## Out of scope (YAGNI)

- A visual spread picker in the palette (the text arg replaces it); per-position
  arguments; standard-deck spreads; a HUD spread button; fuzzy/typo-tolerant arg
  matching beyond prefix/substring.

## Files touched

| File | Change |
|------|--------|
| `lib/engine/tarot_spreads.dart` | `resolveSpread(arg)` |
| `lib/state/providers.dart` | `DecksNotifier.drawSpreadAndLog` |
| `lib/features/journal_screen.dart` | `_builtinSpread`, `_drawSpreadCmd`, dispatch, palette chip + guard |
| tests | `tarot_spreads_test`, `card_oracle_test` (provider), journal slash test |
