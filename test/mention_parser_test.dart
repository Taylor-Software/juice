import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/mention_parser.dart';

void main() {
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
