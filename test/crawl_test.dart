import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/state/providers.dart';

OracleData _loadData() {
  final raw = File('assets/oracle_data.json').readAsStringSync();
  return OracleData(jsonDecode(raw) as Map<String, dynamic>);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final data = _loadData();

  group('CrawlState model', () {
    test('defaults: no environment yet, not lost, dialog at center', () {
      const s = CrawlState();
      expect(s.envRow, isNull);
      expect(s.lost, isFalse);
      expect(s.dialogRow, 2);
      expect(s.dialogCol, 2);
    });

    test('json round-trip preserves all fields', () {
      const s = CrawlState(envRow: 7, lost: true, dialogRow: 0, dialogCol: 4);
      final back = CrawlState.fromJson(s.toJson());
      expect(back.envRow, 7);
      expect(back.lost, isTrue);
      expect(back.dialogRow, 0);
      expect(back.dialogCol, 4);
    });

    test('copyWith can clear envRow via sentinel', () {
      const s = CrawlState(envRow: 3, lost: true);
      final reset = s.copyWith(clearEnvRow: true, lost: false);
      expect(reset.envRow, isNull);
      expect(reset.lost, isFalse);
      expect(reset.dialogRow, 2);
    });
  });

  group('Dialog marker persistence hooks', () {
    test('restore and read back the marker', () {
      final oracle = Oracle(data);
      oracle.restoreDialogPos(0, 4);
      expect(oracle.dialogPos, (row: 0, col: 4));
    });

    test('marker moves on a non-doubles beat and resets on doubles', () {
      final oracle = Oracle(data);
      var sawMove = false;
      var sawReset = false;
      for (var i = 0; i < 500; i++) {
        final before = oracle.dialogPos;
        final r = oracle.npcDialog();
        if (r.summary == 'Conversation ends') {
          expect(oracle.dialogPos, (row: 2, col: 2));
          sawReset = true;
        } else if (oracle.dialogPos != before) {
          sawMove = true;
        }
      }
      expect(sawMove, isTrue);
      expect(sawReset, isTrue);
    });
  });

  group('Dungeon linger', () {
    test('linger rolls d6: only first six encounter entries appear', () {
      final oracle = Oracle(data);
      final firstSix = data.table('dungeon_encounter').take(6).toList();
      for (var i = 0; i < 3000; i++) {
        final r = oracle.dungeonLinger();
        expect(r.title, 'Dungeon Linger');
        final enc = r.rolls.firstWhere((x) => x.label == 'Encounter');
        expect(firstSix, contains(enc.value));
      }
    });

    test('dungeonRoom still produces area, passage, condition, encounter', () {
      final oracle = Oracle(data);
      for (var i = 0; i < 500; i++) {
        final r = oracle.dungeonRoom();
        final labels = r.rolls.map((x) => x.label).toList();
        expect(labels,
            containsAll(['Next Area', 'Passage', 'Condition', 'Encounter']));
      }
    });
  });

  group('Wilderness travel state machine', () {
    test('first step rolls an environment; later steps drift by at most 2', () {
      final oracle = Oracle(data);
      for (var i = 0; i < 500; i++) {
        final first = oracle.wildernessTravel(const CrawlState());
        final env1 = first.state.envRow!;
        expect(env1, inInclusiveRange(1, 10));
        final second = oracle.wildernessTravel(first.state);
        final env2 = second.state.envRow!;
        expect((env2 - env1).abs(), lessThanOrEqualTo(2));
        expect(env2, inInclusiveRange(1, 10));
      }
    });

    test('rolling encounter 10 while exploring sets lost; 6 while lost clears it', () {
      final oracle = Oracle(data);
      var state = const CrawlState();
      var sawLost = false;
      var sawFound = false;
      for (var i = 0; i < 5000; i++) {
        final wasLost = state.lost;
        final r = oracle.wildernessTravel(state);
        final enc = r.result.rolls.firstWhere((x) => x.label == 'Encounter');
        if (!wasLost && r.state.lost) {
          sawLost = true;
          expect(enc.value, 'Destination/Lost');
        }
        if (wasLost && !r.state.lost) {
          sawFound = true;
          expect(enc.value, 'River/Road');
        }
        if (wasLost) {
          final idx = data.table('wilderness_encounter').indexOf(enc.value);
          expect(idx, lessThan(6));
        }
        state = r.state;
      }
      expect(sawLost, isTrue);
      expect(sawFound, isTrue);
    });
  });

  group('Crawl provider persistence', () {
    test('loads persisted state and saves updates', () async {
      SharedPreferences.setMockInitialValues({
        'juice.crawl.v1':
            '{"envRow":4,"lost":true,"dialogRow":1,"dialogCol":3}',
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final loaded = await container.read(crawlProvider.future);
      expect(loaded.envRow, 4);
      expect(loaded.lost, isTrue);
      expect(loaded.dialogRow, 1);

      await container
          .read(crawlProvider.notifier)
          .save(const CrawlState(envRow: 9, lost: false));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('juice.crawl.v1'), contains('"envRow":9'));
    });

    test('reset returns to defaults and persists them', () async {
      SharedPreferences.setMockInitialValues({
        'juice.crawl.v1': '{"envRow":4,"lost":true,"dialogRow":1,"dialogCol":3}',
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(crawlProvider.future);
      await container.read(crawlProvider.notifier).reset();
      final state = await container.read(crawlProvider.future);
      expect(state.envRow, isNull);
      expect(state.lost, isFalse);
      expect(state.dialogRow, 2);
    });
  });
}
