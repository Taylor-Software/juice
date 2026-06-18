import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';

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
}
