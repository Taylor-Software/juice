import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/card_images.dart';
import 'package:juice_oracle/engine/models.dart';

void main() {
  test('slugs and asset paths', () {
    expect(cardSlug('The Tower'), 'the-tower');
    expect(cardSlug('Ace of Wands'), 'ace-of-wands');
    expect(cardSlug('10 of Clubs'), '10-of-clubs');
    expect(tarotImageAsset('The Tower'), 'assets/tarot/the-tower.jpg');
    expect(playingCardImageAsset('Ace of Spades'),
        'assets/playing/ace-of-spades.svg');
  });

  test('cardImageAsset resolves tarot, strips reversed, null otherwise', () {
    expect(cardImageAsset('The Fool'), startsWith('assets/tarot/'));
    expect(
        cardImageAsset('The Tower (reversed)'), 'assets/tarot/the-tower.jpg');
    expect(cardImageAsset('King of Hearts'), startsWith('assets/playing/'));
    expect(cardImageAsset('Not A Card'), isNull);
  });

  test('every tarot card maps to a non-null asset path', () {
    for (final c in kTarotDeck) {
      expect(tarotImageAsset(c), isNotNull, reason: c);
    }
  });
}
