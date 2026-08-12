import 'package:flutter_test/flutter_test.dart';
import 'package:loreseer/engine/models.dart';

void main() {
  test('Character.polarityId round-trips through JSON', () {
    const c = Character(id: 'c1', name: 'Ash', polarityId: 'pg-1');
    final decoded = Character.fromJson(c.toJson());
    expect(decoded.polarityId, 'pg-1');
  });

  test('Character.polarityId is omitted from JSON when null', () {
    const c = Character(id: 'c1', name: 'Ash');
    expect(c.toJson().containsKey('polarityId'), isFalse);
  });

  test('copyWith clearPolarityId nulls it out', () {
    const c = Character(id: 'c1', name: 'Ash', polarityId: 'pg-1');
    final cleared = c.copyWith(clearPolarityId: true);
    expect(cleared.polarityId, isNull);
  });
}
