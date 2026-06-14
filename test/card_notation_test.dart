import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/card_notation.dart';

void main() {
  test('standard playing cards', () {
    expect(cardName('Ah'), 'Ace of Hearts');
    expect(cardName('Ks'), 'King of Spades');
    expect(cardName('10d'), 'Ten of Diamonds'); // two-char rank
    expect(cardName('2c'), 'Two of Clubs');
    expect(cardName('Qs'), 'Queen of Spades');
  });

  test('jokers and colours', () {
    expect(cardName('Jkr'), 'Joker');
    expect(cardName('RJkr'), 'Red Joker');
    expect(cardName('BJkr'), 'Black Joker');
    expect(cardName('R'), 'Red');
    expect(cardName('B'), 'Black');
  });

  test('tarot major arcana, upright and reversed', () {
    expect(cardName('M0'), 'The Fool');
    expect(cardName('M16'), 'The Tower');
    expect(cardName('M16r'), 'The Tower (reversed)');
    expect(cardName('M21'), 'The World');
    expect(cardName('M22'), isNull); // out of range
  });

  test('tarot minor arcana, upright and reversed', () {
    expect(cardName('ACu'), 'Ace of Cups');
    expect(cardName('KnPe'), 'Knight of Pentacles');
    expect(cardName('KWa'), 'King of Wands');
    expect(cardName('5Swr'), 'Five of Swords (reversed)');
    expect(cardName('KnCu'), 'Knight of Cups'); // trailing-r only when reversed
  });

  test('unrecognized tokens return null', () {
    expect(cardName(''), isNull);
    expect(cardName('Zz'), isNull);
    expect(cardName('Pe'), isNull); // suit with no rank
    expect(cardName('99h'), isNull); // bad rank
    expect(cardName('r'), isNull);
  });
}
