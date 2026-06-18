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
}
