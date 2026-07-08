import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/mention_parser.dart';

void main() {
  group('parseComposerState', () {
    test('slash command', () {
      final s = parseComposerState('/roll', 5);
      expect(s.slash, isTrue);
      expect(s.mention, isNull);
      expect(s.question, isFalse);
    });
    test('active @mention up to the caret', () {
      final s = parseComposerState('hi @bran', 8);
      expect(s.mention, 'bran');
      expect(s.slash, isFalse);
      expect(s.question, isFalse);
    });
    test('a space after @ closes the mention', () {
      expect(parseComposerState('hi @bran the bold', 17).mention, isNull);
    });
    test('trailing ? (not slash/mention) is a question', () {
      final s = parseComposerState('what lurks here?', -1);
      expect(s.question, isTrue);
      expect(s.mention, isNull);
    });
    test('a bare ? is not a question', () {
      expect(parseComposerState('?', -1).question, isFalse);
    });
    test('out-of-range caret is clamped (no throw)', () {
      expect(parseComposerState('hi', 99).slash, isFalse);
    });
  });

  test('plain text → one text segment', () {
    final segs = parseMentions('hello world');
    expect(segs, hasLength(1));
    expect(segs.single.text, 'hello world');
    expect(segs.single.kind, MentionKind.text);
  });

  test('parses a char mention into a tappable segment', () {
    final segs = parseMentions('met @[Mara](char:c1) at dawn');
    expect(segs.map((s) => s.kind),
        [MentionKind.text, MentionKind.character, MentionKind.text]);
    expect(segs[1].text, 'Mara');
    expect(segs[1].id, 'c1');
    expect(segs[0].text, 'met ');
    expect(segs[2].text, ' at dawn');
  });

  test('parses a thread mention', () {
    final segs = parseMentions('re @[The Vow](thread:t9)');
    expect(segs.last.kind, MentionKind.thread);
    expect(segs.last.id, 't9');
    expect(segs.last.text, 'The Vow');
  });

  test('mentionToken builds the canonical form', () {
    expect(
        mentionToken('Mara', MentionKind.character, 'c1'), '@[Mara](char:c1)');
    expect(mentionToken('The Vow', MentionKind.thread, 't9'),
        '@[The Vow](thread:t9)');
    expect(
        mentionToken('Harbor', MentionKind.place, 'p1'), '@[Harbor](place:p1)');
    expect(mentionToken('Bram', MentionKind.npc, 'n1'), '@[Bram](npc:n1)');
  });

  test('parses place + npc mentions and round-trips', () {
    final segs = parseMentions('at @[Harbor](place:p1) met @[Bram](npc:n1)');
    expect(segs.map((s) => s.kind), [
      MentionKind.text,
      MentionKind.place,
      MentionKind.text,
      MentionKind.npc,
    ]);
    expect(segs.where((s) => s.kind == MentionKind.place).single.id, 'p1');
    expect(segs.where((s) => s.kind == MentionKind.npc).single.id, 'n1');
    expect(mentionsToPlain('at @[Harbor](place:p1) met @[Bram](npc:n1)'),
        'at Harbor met Bram');
  });

  test('mentionsToPlain strips tokens to display names', () {
    expect(mentionsToPlain('met @[Mara](char:c1) and @[Vow](thread:t9)'),
        'met Mara and Vow');
  });

  test('mentionedCharIds collects character ids only', () {
    final ids =
        mentionedCharIds('@[Mara](char:c1) @[Vow](thread:t9) @[Bo](char:c2)');
    expect(ids, {'c1', 'c2'});
  });

  test('malformed token renders as plain text', () {
    final segs = parseMentions('email a@[b].c not a mention');
    expect(segs, hasLength(1));
    expect(segs.single.kind, MentionKind.text);
  });
}
