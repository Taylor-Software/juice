import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';

void main() {
  test('DndSheet.spellIds round-trips and defaults empty', () {
    expect(const DndSheet().spellIds, isEmpty);
    final s = const DndSheet().copyWith(spellIds: ['dnd-fireball']);
    final back = DndSheet.maybeFromJson(s.toJson())!;
    expect(back.spellIds, ['dnd-fireball']);
  });
}
