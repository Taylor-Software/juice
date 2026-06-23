import 'dice_notation.dart';

/// A run of text that is valid dice notation, by half-open range
/// [start, end). `notation == text.substring(start, end)`.
class DiceSpan {
  const DiceSpan(this.start, this.end, this.notation);
  final int start; // inclusive
  final int end; // exclusive
  final String notation;
}

// A dice term (optional count, `d`, then sides / `%` / `F`) with an optional
// keep-drop or adv/dis suffix, optional `!` explode, and an optional single
// flat modifier — anchored by non-alphanumeric lookarounds so it can't match
// inside a word (`sword20`, `add`). Permissive on shape; parseDice is the real
// grammar check (see scanDice).
final _diceCandidate = RegExp(
  r'(?<![A-Za-z0-9])\d{0,3}d(?:\d{1,4}|%|f)'
  r'(?:(?:kh|kl|dh|dl)\d{1,3}|adv|dis)?!?(?:[+-]\d{1,4})?'
  r'(?![A-Za-z0-9])',
  caseSensitive: false,
);

/// Non-overlapping, in-order dice-notation spans in [text]. Each regex
/// candidate is validated by running [parseDice] in a try/catch; candidates
/// that don't parse (e.g. `d1` — sides must be 2-1000) are dropped, so every
/// returned span is guaranteed valid. `RegExp.allMatches` is already
/// non-overlapping and left-to-right.
List<DiceSpan> scanDice(String text) {
  final out = <DiceSpan>[];
  for (final m in _diceCandidate.allMatches(text)) {
    final token = m[0]!;
    try {
      parseDice(token);
    } on FormatException {
      continue; // looked dice-ish but isn't valid notation
    }
    out.add(DiceSpan(m.start, m.end, token));
  }
  return out;
}
