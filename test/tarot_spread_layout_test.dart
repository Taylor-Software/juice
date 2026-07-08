import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/tarot_spreads.dart';
import 'package:juice_oracle/features/tarot_spread_layout.dart';
import 'package:juice_oracle/shared/card_image.dart';

List<({String position, String shown})> _cardsFor(TarotSpread s) =>
    [for (final p in s.positions) (position: p, shown: 'The Fool')];

Widget _host(Widget child) => MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: Center(child: child))));

void main() {
  group('spread data', () {
    test('every built-in spread has one cell per position', () {
      for (final s in kTarotSpreads) {
        expect(s.cells.length, s.positions.length, reason: s.id);
      }
    });

    test('only the Celtic Cross has a crossing card', () {
      for (final s in kTarotSpreads) {
        final crossings = s.cells.where((c) => c.crossing).length;
        expect(crossings, s.id == 'celtic-cross' ? 1 : 0, reason: s.id);
      }
    });

    test('the crossing card shares a cell with a base card', () {
      final celtic = kTarotSpreads.firstWhere((s) => s.id == 'celtic-cross');
      final cross = celtic.cells.firstWhere((c) => c.crossing);
      final base = celtic.cells.where((c) => !c.crossing);
      expect(base.any((c) => c.col == cross.col && c.row == cross.row), isTrue);
    });
  });

  group('spreadForLog', () {
    test('resolves by name + count', () {
      expect(spreadForLog('Celtic Cross', 10)?.id, 'celtic-cross');
    });
    test('falls back to a unique card-count match when name is missing', () {
      expect(spreadForLog(null, 5)?.id, 'cross');
    });
    test('returns null when nothing fits', () {
      expect(spreadForLog('Nonexistent', 7), isNull);
    });
  });

  group('TarotSpreadLayout', () {
    testWidgets('renders one card per position for the Celtic Cross',
        (tester) async {
      final s = kTarotSpreads.firstWhere((x) => x.id == 'celtic-cross');
      await tester
          .pumpWidget(_host(TarotSpreadLayout(spread: s, cards: _cardsFor(s))));
      await tester.pumpAndSettle();
      expect(find.byType(CardImage), findsNWidgets(10));
      // The crossing position is captioned with the ⟂ marker.
      expect(find.textContaining('⟂'), findsOneWidget);
    });

    testWidgets('mismatched card count falls back to a plain wrap',
        (tester) async {
      final s = kTarotSpreads.firstWhere((x) => x.id == 'three-card');
      await tester.pumpWidget(_host(TarotSpreadLayout(
          spread: s, cards: const [(position: 'Only', shown: 'The Fool')])));
      await tester.pumpAndSettle();
      expect(find.byType(CardImage), findsOneWidget);
      expect(find.textContaining('⟂'), findsNothing);
    });
  });
}
