// Authored, facts-only tarot spreads: a spread is a traditional *method*
// (non-copyrightable) and the position labels are this app's own short
// functional wording — no vendored booklet prose. Per-card meanings reuse the
// already-authored kTarotMeanings via tarotMeaningSuffix.

import 'tarot_meanings.dart';

/// One card's placement in a spread's geometric layout: an integer grid cell
/// (`col`,`row`, origin top-left) and whether the card lies *crossing* (rotated
/// a quarter turn atop the card sharing its cell) — the signature of the Celtic
/// Cross. Non-copyrightable: a spread's shape is a traditional method.
class SpreadCell {
  const SpreadCell(this.col, this.row, {this.crossing = false});
  final int col;
  final int row;
  final bool crossing;
}

/// A named tarot spread: an ordered list of position labels plus a parallel
/// [cells] layout (one cell per position, same order) for a proper geometric
/// render — a row, a plus, or the Celtic Cross wheel + staff.
class TarotSpread {
  const TarotSpread(this.id, this.name, this.positions, this.cells);
  final String id;
  final String name;
  final List<String> positions;
  final List<SpreadCell> cells;
  int get count => positions.length;
}

/// The built-in spreads. The first is the UI default (kept small/common).
const kTarotSpreads = <TarotSpread>[
  TarotSpread(
    'three-card',
    'Past · Present · Future',
    ['Past', 'Present', 'Future'],
    [SpreadCell(0, 0), SpreadCell(1, 0), SpreadCell(2, 0)],
  ),
  // A plus: centre + arms.  Situation·Challenge stack vertically through the
  // centre column; Past/Future are the horizontal arms; Outcome crowns it.
  TarotSpread(
    'cross',
    'Five-card Cross',
    ['Situation', 'Challenge', 'Past', 'Future', 'Outcome'],
    [
      SpreadCell(1, 1), // Situation (centre)
      SpreadCell(1, 2), // Challenge (below)
      SpreadCell(0, 1), // Past (left arm)
      SpreadCell(2, 1), // Future (right arm)
      SpreadCell(1, 0), // Outcome (crown)
    ],
  ),
  // The wheel (cols 0-2) with the crossing card over the centre, plus the
  // vertical staff (col 3) read top-to-bottom.
  TarotSpread(
    'celtic-cross',
    'Celtic Cross',
    [
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
    ],
    [
      SpreadCell(1, 1), // Present (centre)
      SpreadCell(1, 1, crossing: true), // Challenge (crosses the centre)
      SpreadCell(1, 2), // Foundation (below)
      SpreadCell(0, 1), // Recent Past (left)
      SpreadCell(1, 0), // Crown (above)
      SpreadCell(2, 1), // Near Future (right)
      SpreadCell(3, 3), // Self (staff, bottom)
      SpreadCell(3, 2), // Environment
      SpreadCell(3, 1), // Hopes & Fears
      SpreadCell(3, 0), // Outcome (staff, top)
    ],
  ),
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

/// Resolves the layout for a *logged* spread from its stored name + drawn card
/// [count] (journal payloads keep only the name). Prefers an exact name match,
/// then a unique card-count match; null when nothing fits (caller falls back to
/// a plain strip). Keeps rendering robust across future/renamed spreads.
TarotSpread? spreadForLog(String? name, int count) {
  if (name != null) {
    for (final s in kTarotSpreads) {
      if (s.name == name && s.count == count) return s;
    }
  }
  final byCount = kTarotSpreads.where((s) => s.count == count).toList();
  return byCount.length == 1 ? byCount.first : null;
}

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
