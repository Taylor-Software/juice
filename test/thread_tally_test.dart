// test/thread_tally_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/engine/tally.dart';

void main() {
  test('Thread carries an optional tally through copyWith + JSON', () {
    final t = Thread(id: 'a', title: 'Escape')
        .copyWith(tally: const Tally(start: 4, current: 4, target: 8));
    expect(t.tally?.label, '4(8)');

    final round = Thread.fromJson(t.toJson());
    expect(round.tally, equals(t.tally));

    // clearTally drops it
    expect(t.copyWith(clearTally: true).tally, isNull);

    // absent in JSON when null
    expect(Thread(id: 'b', title: 'x').toJson().containsKey('tally'), isFalse);
  });
}
