import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/engine/tarot_spreads.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

OracleData _loadData() =>
    OracleData(jsonDecode(File('assets/oracle_data.json').readAsStringSync())
        as Map<String, dynamic>);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final data = _loadData();

  group('Card decks (data)', () {
    test('standard deck is 52; tarot is 78 (22 major + 56 minor)', () {
      expect(kPlayingDeck.length, 52);
      expect(kPlayingDeck.toSet().length, 52); // all distinct
      expect(kTarotMajor.length, 22);
      expect(kTarotDeck.length, 78);
      expect(kTarotDeck.toSet().length, 78);
      expect(kPlayingDeck.first, 'Ace of Spades');
      expect(kTarotDeck.first, 'The Fool');
    });
  });

  group('DeckState', () {
    test('fresh deck reads as full; drawn reduces remaining', () {
      expect(const DeckState().remaining, 0);
      expect(const DeckState().remainingOf(52), 52); // un-shuffled = full
      final s = DeckState(order: List.generate(52, (i) => i), drawn: 5);
      expect(s.remaining, 47);
      expect(s.remainingOf(52), 47);
    });

    test('round-trips and tolerates junk', () {
      const s = DeckState(order: [3, 1, 2], drawn: 1);
      final back = DeckState.fromJson(s.toJson());
      expect(back.order, [3, 1, 2]);
      expect(back.drawn, 1);
      expect(DeckState.fromJson('nope').order, isEmpty);
      const ds = DecksState(standard: s);
      expect(DecksState.fromJson(ds.toJson()).standard.drawn, 1);
      expect(DecksState.fromJson(ds.toJson()).tarot.order, isEmpty);
    });
  });

  group('Oracle.drawCard', () {
    test('draws without replacement; reshuffles when exhausted', () {
      final oracle = Oracle(data, Dice(Random(7)));
      var state = const DeckState();
      final seen = <String>{};
      for (var i = 0; i < kPlayingDeck.length; i++) {
        final r =
            oracle.drawCard(deck: kPlayingDeck, state: state, title: 'Card');
        expect(seen.add(r.result.summary!), isTrue,
            reason: 'no repeat within a shuffle');
        state = r.next;
      }
      expect(seen.length, 52); // drew the whole deck, all distinct
      expect(state.remaining, 0);
      // Next draw reshuffles a fresh 52.
      final r =
          oracle.drawCard(deck: kPlayingDeck, state: state, title: 'Card');
      expect(r.next.order.length, 52);
      expect(r.next.drawn, 1);
      expect(r.result.rolls.last.value, '1/52');
    });

    test('tarot reversible yields both orientations', () {
      final oracle = Oracle(data, Dice(Random(3)));
      var state = const DeckState();
      var up = false, rev = false;
      for (var i = 0; i < 200; i++) {
        final r = oracle.drawCard(
            deck: kTarotDeck, state: state, title: 'Tarot', reversible: true);
        if (r.result.summary!.contains('(reversed)')) {
          rev = true;
        } else {
          up = true;
        }
        state = r.next;
      }
      expect(up && rev, isTrue);
    });
  });

  group('Oracle.drawSpread', () {
    test('draws one card per position, advances state, builds rolls', () {
      final oracle = Oracle(data, Dice(Random(5)));
      final spread = kTarotSpreads.first; // three-card
      final out = oracle.drawSpread(
        deck: kTarotDeck,
        state: const DeckState(),
        spread: spread,
        reversible: true,
      );
      expect(out.cards, hasLength(3));
      expect(out.cards.map((c) => c.position).toList(), spread.positions);
      expect(out.next.drawn, 3); // advanced by the spread size
      expect(out.result.title, 'Tarot Spread');
      expect(out.result.summary, spread.name);
      expect(out.result.rolls, hasLength(3));
      expect(out.result.rolls.map((r) => r.label).toList(), spread.positions);
      // Every drawn card is a real tarot card (orientation suffix stripped).
      for (final c in out.cards) {
        final base = c.shown.replaceAll(' (reversed)', '');
        expect(kTarotDeck.contains(base), isTrue);
      }
    });
  });

  group('DecksNotifier', () {
    test('draw persists deck state; reshuffle resets it', () async {
      SharedPreferences.setMockInitialValues({
        'juice.sessions.v1':
            '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      });
      final oracle = Oracle(data, Dice(Random(1)));
      final c = ProviderContainer(
          overrides: [oracleProvider.overrideWith((ref) async => oracle)]);
      addTearDown(c.dispose);
      await c.read(decksProvider.future);

      final g = await c.read(decksProvider.notifier).draw(oracle, tarot: false);
      expect(g.title, 'Card');
      final s = c.read(decksProvider).valueOrNull!;
      expect(s.standard.drawn, 1);
      expect(s.standard.remainingOf(52), 51);
      expect(s.tarot.order, isEmpty); // untouched

      await c.read(decksProvider.notifier).reshuffle(tarot: false);
      expect(c.read(decksProvider).valueOrNull!.standard.order, isEmpty);
    });

    test('drawSpread persists advanced tarot state; returns positioned cards',
        () async {
      SharedPreferences.setMockInitialValues({
        'juice.sessions.v1':
            '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      });
      final oracle = Oracle(data, Dice(Random(2)));
      final c = ProviderContainer(
          overrides: [oracleProvider.overrideWith((ref) async => oracle)]);
      addTearDown(c.dispose);
      await c.read(decksProvider.future);

      final spread = kTarotSpreads.first; // three-card
      final out =
          await c.read(decksProvider.notifier).drawSpread(oracle, spread);
      expect(out.cards, hasLength(3));
      expect(out.result.title, 'Tarot Spread');
      // Tarot deck advanced by 3; standard untouched.
      final s = c.read(decksProvider).valueOrNull!;
      expect(s.tarot.drawn, 3);
      expect(s.standard.order, isEmpty);
    });

    test('drawAndLog logs a cards entry; tarot folds in its meaning', () async {
      SharedPreferences.setMockInitialValues({
        'juice.sessions.v1':
            '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      });
      final oracle = Oracle(data, Dice(Random(1)));
      final c = ProviderContainer(
          overrides: [oracleProvider.overrideWith((ref) async => oracle)]);
      addTearDown(c.dispose);
      await c.read(decksProvider.future);
      await c.read(journalProvider.future);

      final tg =
          await c.read(decksProvider.notifier).drawAndLog(oracle, tarot: true);
      final sg =
          await c.read(decksProvider.notifier).drawAndLog(oracle, tarot: false);

      final entries = c.read(journalProvider).valueOrNull!;
      expect(entries, hasLength(2));
      expect(entries.every((e) => e.sourceTool == 'cards'), isTrue);
      // Tarot entry carries an orientation+meaning line; standard does not.
      final tarotEntry =
          entries.firstWhere((e) => e.body.contains(tg.summary!));
      expect(tarotEntry.body,
          anyOf(contains('Upright —'), contains('Reversed —')));
      final stdEntry = entries.firstWhere((e) => e.body.contains(sg.summary!));
      expect(stdEntry.body, isNot(contains('—')));
    });
  });
}
