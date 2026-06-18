import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/engine/system_primer.dart';

void main() {
  group('LocationRef', () {
    test('room ref round-trips', () {
      const r = LocationRef(roomId: 'room-3');
      final back = LocationRef.fromJson(r.toJson());
      expect(back.roomId, 'room-3');
      expect(back.hexCol, isNull);
      expect(back.isEmpty, isFalse);
    });

    test('hex ref round-trips', () {
      const r = LocationRef(hexCol: 2, hexRow: 5);
      final back = LocationRef.fromJson(r.toJson());
      expect(back.hexCol, 2);
      expect(back.hexRow, 5);
      expect(back.roomId, isNull);
    });

    test('empty ref is empty', () {
      expect(const LocationRef().isEmpty, isTrue);
    });
  });

  group('PlayContext', () {
    test('defaults are all null', () {
      const c = PlayContext();
      expect(c.activeCharacterId, isNull);
      expect(c.activeSceneId, isNull);
      expect(c.activeLocation, isNull);
    });

    test('round-trips full state', () {
      const c = PlayContext(
        activeCharacterId: 'c1',
        activeSceneId: 's1',
        activeLocation: LocationRef(roomId: 'r1'),
      );
      final back = PlayContext.fromJson(c.toJson());
      expect(back.activeCharacterId, 'c1');
      expect(back.activeSceneId, 's1');
      expect(back.activeLocation?.roomId, 'r1');
    });

    test('round-trips empty state', () {
      final back = PlayContext.fromJson(const PlayContext().toJson());
      expect(back.activeCharacterId, isNull);
      expect(back.activeLocation, isNull);
    });
  });

  group('resolveSystem', () {
    test('dnd wins over everything', () {
      expect(resolveSystem({'dnd', 'ironsworn'}, {'classic'}), 'dnd');
    });
    test('shadowdark before ironsworn family', () {
      expect(resolveSystem({'shadowdark', 'ironsworn'}, {}), 'shadowdark');
    });
    test('ironsworn family refined by ruleset', () {
      expect(
          resolveSystem({'ironsworn'}, {'sundered_isles'}), 'sundered_isles');
      expect(resolveSystem({'ironsworn'}, {'starforged'}), 'starforged');
      expect(resolveSystem({'ironsworn'}, {'classic'}), 'ironsworn');
    });
    test('nothing covered returns empty', () {
      expect(resolveSystem({'juice', 'mythic'}, {}), '');
    });
  });

  group('EncounterState.locationRef', () {
    test('absent decodes to null', () {
      final e = EncounterState.fromJson({'combatants': [], 'round': 1});
      expect(e.locationRef, isNull);
    });
    test('round-trips a room location', () {
      const e = EncounterState(locationRef: LocationRef(roomId: 'r2'));
      final back = EncounterState.fromJson(e.toJson());
      expect(back.locationRef?.roomId, 'r2');
    });
    test('copyWith can clear the location', () {
      const e = EncounterState(locationRef: LocationRef(roomId: 'r1'));
      expect(e.copyWith(clearLocationRef: true).locationRef, isNull);
      expect(e.copyWith().locationRef?.roomId, 'r1'); // unchanged when omitted
    });
  });
}
