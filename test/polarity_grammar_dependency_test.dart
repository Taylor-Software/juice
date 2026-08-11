import 'package:flutter_test/flutter_test.dart';
import 'package:polarity_grammar/polarity_grammar.dart' as pg;

void main() {
  test('polarity_grammar package resolves and its effect deck loads', () {
    // 44 effect pairs per the ruleset (polarity-grammar.md §2).
    expect(pg.kEffects.length, 44);
  });
}
