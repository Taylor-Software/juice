import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/tarot_spreads.dart';

void main() {
  test('kTarotSpreads: unique ids, count matches positions, non-empty', () {
    final ids = kTarotSpreads.map((s) => s.id).toSet();
    expect(ids.length, kTarotSpreads.length); // ids unique
    for (final s in kTarotSpreads) {
      expect(s.positions, isNotEmpty, reason: '${s.id} has positions');
      expect(s.count, s.positions.length, reason: '${s.id} count');
      expect(s.name.trim(), isNotEmpty, reason: '${s.id} name');
    }
    expect(kTarotSpreads.first.count, 3); // three-card is first (UI default)
    expect(kTarotSpreads.any((s) => s.count == 10), isTrue); // celtic cross
  });

  test('spreadBody lists each position with a tarot meaning line', () {
    final body = spreadBody('Past · Present · Future', [
      (position: 'Past', shown: 'The Tower (reversed)'),
      (position: 'Present', shown: 'Three of Cups'),
      (position: 'Future', shown: 'Ace of Wands'),
    ]);
    expect(body, startsWith('Past · Present · Future'));
    expect(body, contains('Past — The Tower (reversed)'));
    expect(body, contains('Present — Three of Cups'));
    expect(body, contains('Future — Ace of Wands'));
    expect(body, contains('Reversed —')); // the Tower is reversed
    expect(body, contains('Upright —')); // the others upright
  });

  group('resolveSpread', () {
    test('empty or unknown arg → the default (first) spread', () {
      expect(resolveSpread(''), kTarotSpreads.first);
      expect(resolveSpread('   '), kTarotSpreads.first);
      expect(resolveSpread('zzz'), kTarotSpreads.first);
    });

    test('matches by id prefix and name substring, case-insensitive', () {
      expect(resolveSpread('celtic').id, 'celtic-cross');
      expect(resolveSpread('CELTIC').id, 'celtic-cross');
      expect(resolveSpread('cross').id, 'cross'); // 5-card, before celtic-cross
      expect(resolveSpread('five').id, 'cross'); // name "Five-card Cross"
      expect(resolveSpread('three').id, 'three-card');
    });
  });
}
