# Inline tappable dice in journal prose

**Date:** 2026-06-23
**Status:** Design — approved

## Problem

Players write dice notation in their journal prose ("hit it for `2d6+3`",
"roll `d20` to notice"). Today that text is inert. The app already has a full
dice engine (`parseDice` / `DiceExpression.roll` in `dice_notation.dart`) and a
dice-logging pipeline (`diceRollGenResult` + the `expression` payload that makes
an entry rerollable), but the only ways to roll are the Dice Roller tool and the
`/dice` slash command. Making notation in rendered prose tap-to-roll closes the
loop where the player already is — reading their own notes.

## Decisions (from brainstorming)

- **Detect + validate**: a regex finds candidate dice tokens; `parseDice`
  (which throws `FormatException` on invalid input) is the final arbiter, so
  anything that looks dice-ish but doesn't parse is dropped.
- **Single-term-with-±N scope**: detect `2d6`, `d20`, `4d6kh3`, `d20adv`,
  `2d6+3`, `d%`, `4dF` — NOT multi-dice chains like `2d6+1d8` (rare in prose).
- **Plain text runs only**: dice-tap is skipped when `lonelog == true` (Lonelog
  already syntax-highlights its own notation; interleaving is needless
  complexity).
- **Tap rolls + logs**, reusing the existing dice pipeline so the new entry is
  itself rerollable.
- Rendered journal prose only. No composer. No system/AI gate (dice are
  deterministic, always available).

## Architecture

### 1. Pure detection — `lib/engine/dice_scan.dart` (new, no Flutter)

```dart
/// A run of [text] that is valid dice notation, by half-open range.
class DiceSpan {
  const DiceSpan(this.start, this.end, this.notation);
  final int start; // inclusive
  final int end;   // exclusive
  final String notation; // text.substring(start, end)
}

/// Finds non-overlapping, in-order dice-notation spans in [text]. A candidate
/// is a dice term (`d20`, `2d6`, `d%`, `4dF`) with an optional keep/drop or
/// adv/dis or '!' suffix and optional trailing `±N`, anchored so it can't match
/// inside a word (`sword20`, `add`). Every candidate is validated by running
/// [parseDice] in a try/catch — if it throws, the candidate is skipped. So the
/// returned spans are guaranteed to parse.
List<DiceSpan> scanDice(String text) { ... }
```

Candidate regex (case-insensitive), with non-alphanumeric lookarounds:

```
(?<![A-Za-z0-9])          # not preceded by a word char
\d{0,3}d(?:\d{1,4}|%|f)   # dice term: optional count, d, sides/%/F
(?:(?:kh|kl|dh|dl)\d{1,3}|adv|dis)?   # optional keep/drop or adv/dis
!?                        # optional explode
(?:[+-]\d{1,4})?          # optional single flat modifier (no spaces)
(?![A-Za-z0-9])           # not followed by a word char
```

For each regex match, call `parseDice(match)` in a try/catch; keep the span only
if it parses. (The regex is permissive on shape; `parseDice` enforces the real
grammar — e.g. `d1` fails the "sides 2-1000" rule and is dropped.) Matches are
walked left to right with a cursor so spans never overlap.

### 2. Render — `lib/shared/mention_text.dart`

`MentionText` gains an optional callback:

```dart
final void Function(String notation)? onDiceTap;
```

In `_textSpans(text, base, scheme)` — the path that renders a **non-mention**
text run — when `!widget.lonelog && widget.onDiceTap != null`, split the run by
`scanDice(text)`: emit plain `TextSpan`s for the gaps and, for each `DiceSpan`,
a tappable `TextSpan` (styled like a mention link: `colorScheme.primary`,
`fontWeight.w600`) whose `TapGestureRecognizer.onTap` calls
`widget.onDiceTap!(span.notation)`. Recognizers are tracked in the existing
`_recognizers` list (disposed in `dispose`, already handled). When `lonelog` is
true, `_textSpans` keeps its current behavior unchanged (no dice scan).

This composes cleanly: `_textSpans` is only ever called for non-mention runs, so
`@`-mentions are already carved out before dice scanning sees the text.

### 3. Roll + log — `lib/features/journal_screen.dart`

A handler mirroring the existing dice-reroll path (`journal_screen.dart` ~L800):

```dart
void _rollDice(String notation) {
  final oracle = ref.read(oracleProvider).valueOrNull;
  if (oracle == null) return;
  final DiceRollResult r;
  try {
    r = parseDice(notation).roll(oracle.dice);
  } on FormatException {
    return; // scanDice already validated, but stay defensive
  }
  final g = diceRollGenResult(r);
  ref.read(journalProvider.notifier).addResult(
        g.title,
        g.asText,
        sourceTool: 'dice',
        payload: {...g.toPayload(), 'expression': r.expression},
      );
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('${r.expression} = ${r.total}')),
  );
}
```

Wire `onDiceTap: _rollDice` at the `MentionText` call sites that already pass
`onCharacterTap`/`onThreadTap` (the entry-body renders). The logged entry
carries the `expression` payload, so it's rerollable via the journal's existing
reroll affordance — and its own body contains the notation, so it too renders a
tappable token (harmless, consistent).

## Testing

- `dice_scan_test` (pure, the core): `scanDice` finds `2d6+3` / `d20` / `4d6kh3`
  / `d20adv` / `d%` / `4dF`; returns correct ranges; finds multiple in one
  string; **rejects false positives** — `sword20`, `add`, `d1` (invalid sides),
  bare `d`, `100` (no die); skips notation inside `@`-mention-free prose
  correctly; non-overlapping order preserved.
- `mention_text` widget test: a body with `2d6` renders a tappable span that
  fires `onDiceTap('2d6')`; with `lonelog: true` no dice span is produced; a
  body with an `@`-mention + a dice token produces both a mention link and a
  dice link.
- `journal_screen` widget test: tapping an inline dice token in a rendered entry
  adds a `dice` journal entry whose payload has an `expression` (rerollable).

## Out of scope (YAGNI)

- Multi-term expressions (`2d6+1d8-1`); tappable dice in the composer/preview;
  a setting to insert-vs-roll; long-press for options; dice-tap inside Lonelog
  runs.

## Files touched

| File | Change |
|------|--------|
| `lib/engine/dice_scan.dart` | new: `DiceSpan`, `scanDice` (regex + `parseDice` validation) |
| `lib/shared/mention_text.dart` | `onDiceTap` callback + dice spans in non-lonelog text runs |
| `lib/features/journal_screen.dart` | `_rollDice` handler + `onDiceTap:` wiring at entry-body `MentionText`s |
| tests | `dice_scan_test`, `mention_text` test, `journal_screen` tap test |
