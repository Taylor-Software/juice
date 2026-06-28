import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/features/sheet_widgets.dart';

void main() {
  group('StatBlock / Attack', () {
    test('round-trips through JSON', () {
      const sb = StatBlock(
        ac: 14,
        attacks: [
          Attack(name: 'Shortbow', detail: '+4, 1d6+2'),
          Attack(name: 'Bite'),
        ],
        saves: 'Dex +2',
        speed: '30 ft',
        notes: 'Nimble Escape',
      );
      final back = StatBlock.maybeFromJson(sb.toJson())!;
      expect(back.ac, 14);
      expect(back.attacks.length, 2);
      expect(back.attacks.first.name, 'Shortbow');
      expect(back.attacks.first.detail, '+4, 1d6+2');
      expect(back.attacks[1].detail, ''); // omitted detail round-trips to ''
      expect(back.saves, 'Dex +2');
      expect(back.speed, '30 ft');
      expect(back.notes, 'Nimble Escape');
    });

    test('isEmpty true only when everything blank', () {
      expect(const StatBlock().isEmpty, true);
      expect(const StatBlock(ac: 12).isEmpty, false);
      expect(const StatBlock(attacks: [Attack(name: 'x')]).isEmpty, false);
      expect(const StatBlock(notes: 'x').isEmpty, false);
    });

    test('maybeFromJson tolerant: non-map -> null; bad attacks dropped', () {
      expect(StatBlock.maybeFromJson('nope'), isNull);
      final sb = StatBlock.maybeFromJson({
        'ac': 10,
        'attacks': [
          {'name': 'Claw'},
          {'detail': 'no name -> dropped'},
          'garbage',
        ],
      })!;
      expect(sb.ac, 10);
      expect(sb.attacks.length, 1);
      expect(sb.attacks.single.name, 'Claw');
    });

    test('toJson omits empty fields', () {
      expect(const StatBlock(ac: 12).toJson(), {'ac': 12});
      expect(const StatBlock().toJson(), <String, dynamic>{});
    });

    test('Combatant carries a statBlock through JSON', () {
      const c = Combatant(
        id: 'g', name: 'Goblin', initiative: 12,
        statBlock: StatBlock(ac: 13, attacks: [Attack(name: 'Scimitar')]),
      );
      final back = Combatant.fromJson(c.toJson());
      expect(back.statBlock, isNotNull);
      expect(back.statBlock!.ac, 13);
      expect(back.statBlock!.attacks.single.name, 'Scimitar');
    });

    test('Combatant without a statBlock round-trips to null (legacy)', () {
      const c = Combatant(id: 'g', name: 'Goblin', initiative: 12);
      expect(Combatant.fromJson(c.toJson()).statBlock, isNull);
      // legacy JSON with no statBlock key:
      final legacy = Combatant.fromJson({
        'id': 'g', 'name': 'Goblin', 'initiative': 12,
        'track': null, 'tags': const [], 'defeated': false,
      });
      expect(legacy.statBlock, isNull);
    });

    test('copyWith sets and clears statBlock', () {
      const c = Combatant(id: 'g', name: 'G', initiative: 1);
      final withSb = c.copyWith(statBlock: const StatBlock(ac: 12));
      expect(withSb.statBlock!.ac, 12);
      expect(withSb.copyWith(clearStatBlock: true).statBlock, isNull);
      // a plain copyWith preserves it:
      expect(withSb.copyWith(defeated: true).statBlock!.ac, 12);
    });
  });

  group('StatBlockView', () {
    testWidgets('StatBlockView renders AC, attacks, saves/speed/notes',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: StatBlockView(
            block: StatBlock(
              ac: 14,
              attacks: [Attack(name: 'Scimitar', detail: '+4, 1d6+2')],
              saves: 'Dex +2',
              speed: '30 ft',
              notes: 'Nimble Escape',
            ),
            curHp: 7,
            maxHp: 7,
          ),
        ),
      ));
      expect(find.textContaining('AC 14'), findsOneWidget);
      expect(find.textContaining('7/7'), findsOneWidget);
      expect(find.textContaining('30 ft'), findsOneWidget);
      expect(find.text('Scimitar'), findsOneWidget);
      expect(find.textContaining('+4, 1d6+2'), findsOneWidget);
      expect(find.textContaining('Dex +2'), findsOneWidget);
      expect(find.textContaining('Nimble Escape'), findsOneWidget);
    });

    testWidgets('StatBlockView omits empty sections', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: StatBlockView(block: StatBlock(ac: 12))),
      ));
      expect(find.textContaining('AC 12'), findsOneWidget);
      expect(find.text('SAVES'), findsNothing);
      expect(find.text('ATTACKS'), findsNothing);
    });
  });
}
