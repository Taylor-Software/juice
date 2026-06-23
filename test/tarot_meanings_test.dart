import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/engine/tarot_meanings.dart';

void main() {
  test('readTarot parses orientation and looks up meaning', () {
    final up = readTarot('The Fool');
    expect(up.name, 'The Fool');
    expect(up.reversed, isFalse);
    expect(up.meaning, isNotNull);

    final rev = readTarot('The Tower (reversed)');
    expect(rev.name, 'The Tower');
    expect(rev.reversed, isTrue);
    expect(rev.meaning, isNotNull);
  });

  test('readTarot returns null meaning for a non-tarot (standard) card', () {
    final r = readTarot('Ace of Spades');
    expect(r.name, 'Ace of Spades');
    expect(r.reversed, isFalse);
    expect(r.meaning, isNull);
  });

  test('tarotMeaningSuffix folds in orientation + meaning, empty for non-tarot',
      () {
    expect(tarotMeaningSuffix('The Tower'), startsWith('\nUpright — '));
    expect(tarotMeaningSuffix('The Tower (reversed)'),
        startsWith('\nReversed — '));
    expect(tarotMeaningSuffix('Ace of Spades'), ''); // standard deck
  });

  test('every tarot card has an authored meaning, upright != reversed', () {
    for (final card in kTarotDeck) {
      final m = kTarotMeanings[card];
      expect(m, isNotNull, reason: 'missing meaning for "$card"');
      expect(m!.upright.trim(), isNotEmpty, reason: 'upright "$card"');
      expect(m.reversed.trim(), isNotEmpty, reason: 'reversed "$card"');
      expect(m.upright, isNot(m.reversed), reason: 'distinct "$card"');
    }
    expect(kTarotMeanings.length, kTarotDeck.length); // no stray keys
  });
}
