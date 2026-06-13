import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';

void main() {
  test('kAllSystems is the four optional systems', () {
    expect(kAllSystems, {'juice', 'mythic', 'ironsworn', 'party'});
  });

  test('legacy meta (no systems) enables all', () {
    final m = SessionMeta.fromJson({'id': 'a', 'name': 'A'});
    expect(m.systems, isNull);
    expect(m.enabledSystems, kAllSystems);
  });

  test('explicit systems round-trip and drive enabledSystems', () {
    const m = SessionMeta(id: 'a', name: 'A', systems: ['juice', 'mythic']);
    final back = SessionMeta.fromJson(m.toJson());
    expect(back.systems, ['juice', 'mythic']);
    expect(back.enabledSystems, {'juice', 'mythic'});
  });

  test('empty systems means only core (no optional systems)', () {
    const m = SessionMeta(id: 'a', name: 'A', systems: []);
    expect(m.enabledSystems, isEmpty);
  });

  test('toJson omits systems when null (byte-stable legacy)', () {
    expect(
        const SessionMeta(id: 'a', name: 'A').toJson().containsKey('systems'),
        isFalse);
  });
}
