import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dice_scan.dart';

void main() {
  List<String> tokens(String s) => scanDice(s).map((d) => d.notation).toList();

  test('finds common dice forms', () {
    expect(tokens('hit for 2d6+3 damage'), ['2d6+3']);
    expect(tokens('roll d20 to notice'), ['d20']);
    expect(tokens('4d6kh3 for stats'), ['4d6kh3']);
    expect(tokens('d20adv on this'), ['d20adv']);
    expect(tokens('roll d% now'), ['d%']);
    expect(tokens('4dF aspects'), ['4dF']);
  });

  test('finds multiple, in order, with correct ranges', () {
    final s = 'I rolled 2d6 and d20.';
    final spans = scanDice(s);
    expect(spans.map((d) => d.notation).toList(), ['2d6', 'd20']);
    for (final d in spans) {
      expect(s.substring(d.start, d.end), d.notation);
    }
    expect(spans[0].end, lessThanOrEqualTo(spans[1].start));
  });

  test('rejects false positives', () {
    expect(tokens('sword20 is sharp'), isEmpty); // d not at a word boundary
    expect(tokens('just add it'), isEmpty); // "add" has no dice
    expect(tokens('rolled a d1'), isEmpty); // d1 fails parseDice (sides 2-1000)
    expect(tokens('a lone d here'), isEmpty); // bare d, no sides
    expect(tokens('100 gold'), isEmpty); // number, no die
    expect(tokens('the road20 sign'), isEmpty); // d inside a word
  });

  test('blank / no-dice text yields nothing', () {
    expect(scanDice(''), isEmpty);
    expect(scanDice('a plain sentence with no rolls'), isEmpty);
  });
}
