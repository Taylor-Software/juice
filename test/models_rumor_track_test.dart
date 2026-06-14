import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';

void main() {
  test('Rumor round-trips through json', () {
    const r = Rumor(
        id: '1',
        text: 'Smugglers use the north gate',
        note: 'from the barkeep');
    final back = Rumor.fromJson(r.toJson());
    expect(back.id, '1');
    expect(back.text, r.text);
    expect(back.note, r.note);
    expect(back.resolved, isFalse);
  });

  test('Rumor copyWith toggles resolved', () {
    const r = Rumor(id: '1', text: 'x');
    expect(r.copyWith(resolved: true).resolved, isTrue);
  });
}
