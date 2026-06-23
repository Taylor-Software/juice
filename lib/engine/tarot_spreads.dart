// Authored, facts-only tarot spreads: a spread is a traditional *method*
// (non-copyrightable) and the position labels are this app's own short
// functional wording — no vendored booklet prose. Per-card meanings reuse the
// already-authored kTarotMeanings via tarotMeaningSuffix.

import 'tarot_meanings.dart';

/// A named tarot spread: an ordered list of position labels.
class TarotSpread {
  const TarotSpread(this.id, this.name, this.positions);
  final String id;
  final String name;
  final List<String> positions;
  int get count => positions.length;
}

/// The built-in spreads. The first is the UI default (kept small/common).
const kTarotSpreads = <TarotSpread>[
  TarotSpread(
      'three-card', 'Past · Present · Future', ['Past', 'Present', 'Future']),
  TarotSpread('cross', 'Five-card Cross',
      ['Situation', 'Challenge', 'Past', 'Future', 'Outcome']),
  TarotSpread('celtic-cross', 'Celtic Cross', [
    'Present',
    'Challenge',
    'Foundation',
    'Recent Past',
    'Crown',
    'Near Future',
    'Self',
    'Environment',
    'Hopes & Fears',
    'Outcome',
  ]),
];

/// Multi-line journal body for a drawn spread: the spread name, then one
/// 'Position — Card' line per position with its tarot meaning folded in
/// (tarotMeaningSuffix prepends its own newline, so the meaning sits on the
/// next line). Shared by the Cards-section Log button so the stored text is
/// the canonical reading.
String spreadBody(
    String spreadName, List<({String position, String shown})> cards) {
  final b = StringBuffer(spreadName);
  for (final c in cards) {
    b.write('\n${c.position} — ${c.shown}${tarotMeaningSuffix(c.shown)}');
  }
  return b.toString();
}
