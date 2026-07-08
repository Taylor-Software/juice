/// Entity-mention markup for journal prose (spec: cycle4 §4).
/// Token form: `@[Display Name](char:ID)`, `@[Title](thread:ID)`,
/// `@[Place](place:ID)`, or `@[Name](npc:ID)`.
library;

enum MentionKind { text, character, thread, place, npc }

class MentionSegment {
  const MentionSegment(this.text, this.kind, [this.id]);
  final String text;
  final MentionKind kind;
  final String? id; // entity id for a mention; null for text
}

final _mentionRe = RegExp(r'@\[([^\]]+)\]\((char|thread|place|npc):([^)]+)\)');

MentionKind _kindFromTag(String tag) => switch (tag) {
      'char' => MentionKind.character,
      'thread' => MentionKind.thread,
      'place' => MentionKind.place,
      'npc' => MentionKind.npc,
      _ => MentionKind.text,
    };

String _tagFromKind(MentionKind kind) => switch (kind) {
      MentionKind.character => 'char',
      MentionKind.thread => 'thread',
      MentionKind.place => 'place',
      MentionKind.npc => 'npc',
      MentionKind.text => 'char', // never tokenized; safe fallback
    };

/// Splits [body] into text and mention segments in order.
List<MentionSegment> parseMentions(String body) {
  final out = <MentionSegment>[];
  var last = 0;
  for (final m in _mentionRe.allMatches(body)) {
    if (m.start > last) {
      out.add(MentionSegment(body.substring(last, m.start), MentionKind.text));
    }
    out.add(MentionSegment(m.group(1)!, _kindFromTag(m.group(2)!), m.group(3)));
    last = m.end;
  }
  if (last < body.length) {
    out.add(MentionSegment(body.substring(last), MentionKind.text));
  }
  return out.isEmpty ? [MentionSegment(body, MentionKind.text)] : out;
}

String mentionToken(String display, MentionKind kind, String id) =>
    '@[$display](${_tagFromKind(kind)}:$id)';

/// Replaces every mention token with its display name (export / search).
String mentionsToPlain(String body) =>
    body.replaceAllMapped(_mentionRe, (m) => m.group(1)!);

/// Character ids referenced by mentions in [body].
Set<String> mentionedCharIds(String body) => {
      for (final m in _mentionRe.allMatches(body))
        if (m.group(2) == 'char') m.group(3)!,
    };

/// Derives the journal composer's live affordance state from its [text] and
/// caret [selectionOffset] (-1 = no explicit selection → treat as end). Pure so
/// the slash/mention/question detection is unit-testable apart from the widget.
({bool slash, String? mention, bool question}) parseComposerState(
    String text, int selectionOffset) {
  final slash = text.startsWith('/');
  final sel = (selectionOffset < 0 ? text.length : selectionOffset)
      .clamp(0, text.length);
  String? mention;
  if (!slash && sel > 0) {
    final upToCaret = text.substring(0, sel);
    final at = upToCaret.lastIndexOf('@');
    if (at >= 0 && !upToCaret.substring(at).contains(' ')) {
      mention = upToCaret.substring(at + 1);
    }
  }
  final trimmed = text.trim();
  final question =
      !slash && mention == null && trimmed.endsWith('?') && trimmed.length > 1;
  return (slash: slash, mention: mention, question: question);
}
