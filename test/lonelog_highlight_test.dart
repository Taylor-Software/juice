import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/lonelog_highlight.dart';

void main() {
  test('classifies a bare action', () {
    expect(highlight('@ Pick the lock'), [
      const LonelogSpan('@', LonelogSpanKind.symbol),
      const LonelogSpan(' Pick the lock', LonelogSpanKind.text),
    ]);
  });

  test('classifies an attributed action with an actor', () {
    expect(highlight('@(Jonah) Keeps watch'), [
      const LonelogSpan('@', LonelogSpanKind.symbol),
      const LonelogSpan('(Jonah)', LonelogSpanKind.actor),
      const LonelogSpan(' Keeps watch', LonelogSpanKind.text),
    ]);
  });

  test('classifies an oracle question and a consequence with a tag', () {
    expect(
        highlight('? Is the guard asleep').first.kind, LonelogSpanKind.symbol);
    final spans = highlight('=> The door opens [E:AlertClock 1/6]');
    expect(spans.first, const LonelogSpan('=>', LonelogSpanKind.symbol));
    expect(spans.last,
        const LonelogSpan('[E:AlertClock 1/6]', LonelogSpanKind.tag));
  });

  test('classifies a whole-line block delimiter', () {
    expect(highlight('[COMBAT]'), [
      const LonelogSpan('[COMBAT]', LonelogSpanKind.block),
    ]);
    expect(highlight('[/DUNGEON STATUS]').single.kind, LonelogSpanKind.block);
  });

  test('classifies a standalone tag line and a meta aside', () {
    expect(highlight('[N:Jonah|captured]').single.kind, LonelogSpanKind.tag);
    expect(highlight('(note: trying a flashback)').single.kind,
        LonelogSpanKind.meta);
  });

  test('is tolerant: unknown content is plain text', () {
    expect(highlight('just some prose'), [
      const LonelogSpan('just some prose', LonelogSpanKind.text),
    ]);
  });

  test('span texts always reconstruct the original line (round-trip)', () {
    for (final line in [
      '@ Pick the lock',
      '@(Jonah) Keeps watch',
      'd: d20+5=17 vs DC 15',
      '=> The door opens [E:AlertClock 1/6]',
      '[COMBAT]',
      '(note: aside)',
      '',
    ]) {
      expect(highlight(line).map((s) => s.text).join(), line);
    }
  });

  test('every asset example line classifies without loss', () {
    final data = jsonDecode(File('assets/lonelog_data.json').readAsStringSync())
        as Map<String, dynamic>;
    for (final ex in (data['examples'] as List)) {
      for (final line in ((ex as Map)['lines'] as List).cast<String>()) {
        final spans = highlight(line);
        expect(spans, isNotEmpty);
        expect(spans.map((s) => s.text).join(), line);
      }
    }
  });
}
