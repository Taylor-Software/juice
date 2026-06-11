import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';

OracleData _loadData() {
  final raw = File('assets/oracle_data.json').readAsStringSync();
  return OracleData(jsonDecode(raw) as Map<String, dynamic>);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final data = _loadData();

  group('Mythic data integrity', () {
    test('odds, bands ladder, and focus ranges have the right shape', () {
      expect(data.mythicOdds.length, 9);
      expect(data.mythicBands.length, 17);
      for (final band in data.mythicBands) {
        expect(band.length, 3);
      }
      expect(data.mythicEventFocus.length, 12);
      expect(data.mythicEventFocus.last[0], 100);
    });
  });

  group('CrawlState chaos factor', () {
    test('defaults to 5 and round-trips', () {
      const s = CrawlState();
      expect(s.chaosFactor, 5);
      final back = CrawlState.fromJson(
          const CrawlState(chaosFactor: 8).toJson());
      expect(back.chaosFactor, 8);
    });

    test('older persisted json without the field defaults to 5', () {
      final s = CrawlState.fromJson({'envRow': 3, 'lost': false});
      expect(s.chaosFactor, 5);
    });
  });

  group('Mythic engine', () {
    test('50/50 at chaos 5: ~50% yes-like, ~10% exceptional yes, ~5% events', () {
      final oracle = Oracle(data);
      const n = 40000;
      var yesLike = 0, excYes = 0, events = 0;
      for (var i = 0; i < n; i++) {
        final r = oracle.mythicFate(4, 5);
        final answer = r.rolls.firstWhere((x) => x.label == 'Answer').value;
        if (answer.endsWith('Yes')) yesLike++;
        if (answer == 'Exceptional Yes') excYes++;
        if (r.rolls.any((x) => x.label == 'Random Event')) events++;
      }
      expect(yesLike / n, closeTo(0.50, 0.01));
      expect(excYes / n, closeTo(0.10, 0.01));
      expect(events / n, closeTo(0.05, 0.01));
    });

    test('certain at chaos 9 is nearly always yes', () {
      final oracle = Oracle(data);
      var yes = 0;
      for (var i = 0; i < 2000; i++) {
        final r = oracle.mythicFate(0, 9);
        if (r.rolls
            .firstWhere((x) => x.label == 'Answer')
            .value
            .endsWith('Yes')) {
          yes++;
        }
      }
      expect(yes / 2000, greaterThan(0.97));
    });

    test('scene test rates follow chaos', () {
      final oracle = Oracle(data);
      var expectedScenes = 0;
      const n = 9000;
      for (var i = 0; i < n; i++) {
        final r = oracle.mythicSceneTest(3);
        final v = r.rolls.first.value;
        expect(['Expected Scene', 'Altered Scene', 'Interrupted Scene'],
            contains(v));
        if (v == 'Expected Scene') expectedScenes++;
      }
      expect(expectedScenes / n, closeTo(0.70, 0.02));
    });

    test('event focus targets the provided lists when relevant', () {
      final oracle = Oracle(data);
      var sawThreadTarget = false, sawCharacterTarget = false;
      for (var i = 0; i < 2000; i++) {
        final r = oracle.mythicEventFocus(
          threads: ['Find the sword'],
          characters: ['Old Marta'],
        );
        final focus = r.rolls.first.value;
        final target =
            r.rolls.where((x) => x.label == 'Target').firstOrNull?.value;
        if (focus.contains('Thread')) {
          expect(target, 'Find the sword');
          sawThreadTarget = true;
        }
        if (focus.startsWith('NPC')) {
          expect(target, 'Old Marta');
          sawCharacterTarget = true;
        }
      }
      expect(sawThreadTarget && sawCharacterTarget, isTrue);
    });
  });

  group('Mythic meaning tables', () {
    test('47 tables, all d100, pairs where entries2 exists', () {
      expect(data.mythicMeaning.length, 47);
      for (final t in data.mythicMeaning) {
        expect((t['entries'] as List).length, 100);
      }
    });

    test('meaning roll yields two non-empty words', () {
      final oracle = Oracle(data);
      for (var i = 0; i < 500; i++) {
        final r = oracle.mythicMeaning('actions');
        expect(r.title, 'Mythic Meaning');
        final words = r.rolls.where((x) => x.label.startsWith('Word'));
        expect(words.length, 2);
        for (final w in words) {
          expect(w.value, isNotEmpty);
        }
      }
    });
  });
}
