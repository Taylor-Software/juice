import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';

void main() {
  test('terrain + pois round-trip; omitted when empty', () {
    const bare = HexCell(col: 0, row: 0, envRow: 3);
    expect(bare.terrain, isNull);
    expect(bare.pois, isEmpty);
    expect(bare.toJson().containsKey('terrain'), false);
    expect(bare.toJson().containsKey('pois'), false);

    const full =
        HexCell(col: 1, row: 2, envRow: 5, terrain: 'forest', pois: [3, 7]);
    final back = HexCell.maybeFromJson(full.toJson())!;
    expect(back.terrain, 'forest');
    expect(back.pois, [3, 7]);
    expect(back.envRow, 5);
  });

  test('copyWith sets terrain + pois', () {
    const c = HexCell(col: 0, row: 0, envRow: 1);
    final t = c.copyWith(terrain: 'desert', pois: [1]);
    expect(t.terrain, 'desert');
    expect(t.pois, [1]);
  });
}
