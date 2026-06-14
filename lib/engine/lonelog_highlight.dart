/// Classifies a single Lonelog log line into typed spans for syntax
/// highlighting. Tolerant: anything unrecognized stays [LonelogSpanKind.text],
/// and the concatenation of span texts always equals the input line.
///
/// This is the minimal "proven parser" for P1 — NOT a Markdown
/// parser/serializer (P2) and NOT a dice evaluator (P4). It recognizes the
/// leading symbol, an `@(Name)` actor, bracket tags, whole-line block
/// delimiters, and `(keyword: ...)` meta asides. Mid-line `->`/`=>` are not
/// re-highlighted; legend examples are written one symbol per line.
library;

enum LonelogSpanKind { symbol, actor, tag, block, meta, text }

class LonelogSpan {
  const LonelogSpan(this.text, this.kind);
  final String text;
  final LonelogSpanKind kind;

  @override
  bool operator ==(Object other) =>
      other is LonelogSpan && other.text == text && other.kind == kind;

  @override
  int get hashCode => Object.hash(text, kind);

  @override
  String toString() => '${kind.name}:"$text"';
}

/// Leading symbols, longest-first so `d:`/`->`/`=>`/`tbl:` win over prefixes.
const _leadingSymbols = ['=>', '->', 'tbl:', 'gen:', 'd:', '@', '?'];

/// Reserved structural block names (digital `[NAME]`/`[/NAME]`).
const lonelogBlockNames = [
  'COMBAT',
  'DUNGEON STATUS',
  'RESOURCES',
  'BATTLE',
  'CAMPAIGN',
];

/// A whole line that is just a KNOWN block delimiter, e.g. `[COMBAT]` or
/// `[/DUNGEON STATUS]`. Matching is restricted to [lonelogBlockNames] so a
/// colon-less uppercase tag written alone (e.g. `[N]`) is not mistaken for a
/// block — it falls through to the inline scanner as a tag.
final _blockLineRe = RegExp(r'^\s*\[/?([A-Z][A-Z ]*)\]\s*$');

bool _isBlockLine(String line) {
  final m = _blockLineRe.firstMatch(line);
  return m != null && lonelogBlockNames.contains(m.group(1));
}

/// Inline tokens: a bracket tag, or a `(keyword: ...)` meta aside.
final _inlineRe = RegExp(
    r'\[[^\]]+\]|\((?:note|reflection|reminder|question|house rule):[^)]*\)');

List<LonelogSpan> highlight(String line) {
  if (line.isEmpty) return const [LonelogSpan('', LonelogSpanKind.text)];
  if (_isBlockLine(line)) {
    return [LonelogSpan(line, LonelogSpanKind.block)];
  }

  final spans = <LonelogSpan>[];
  final lead = RegExp(r'^\s*').firstMatch(line)!.group(0)!;
  var body = line.substring(lead.length);
  if (lead.isNotEmpty) spans.add(LonelogSpan(lead, LonelogSpanKind.text));

  String? sym;
  for (final s in _leadingSymbols) {
    if (body.startsWith(s)) {
      sym = s;
      break;
    }
  }
  if (sym != null) {
    spans.add(LonelogSpan(sym, LonelogSpanKind.symbol));
    body = body.substring(sym.length);
    if (sym == '@') {
      final actor = RegExp(r'^\([^)]*\)').firstMatch(body);
      if (actor != null) {
        spans.add(LonelogSpan(actor.group(0)!, LonelogSpanKind.actor));
        body = body.substring(actor.end);
      }
    }
  }

  var idx = 0;
  for (final m in _inlineRe.allMatches(body)) {
    if (m.start > idx) {
      spans
          .add(LonelogSpan(body.substring(idx, m.start), LonelogSpanKind.text));
    }
    final tok = m.group(0)!;
    spans.add(LonelogSpan(
        tok, tok.startsWith('[') ? LonelogSpanKind.tag : LonelogSpanKind.meta));
    idx = m.end;
  }
  if (idx < body.length) {
    spans.add(LonelogSpan(body.substring(idx), LonelogSpanKind.text));
  }
  return spans;
}
