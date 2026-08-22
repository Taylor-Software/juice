import 'package:flutter_test/flutter_test.dart';
import 'package:loreseer/engine/models.dart';

void main() {
  test('stage round-trips through JSON and omits the default', () {
    final rumor =
        Thread(id: 't1', title: 'Heard a noise', stage: ThreadStage.rumor);
    final json = rumor.toJson();
    expect(json['stage'], 'rumor');
    expect(Thread.fromJson(json).stage, ThreadStage.rumor);

    final active = Thread(id: 't2', title: 'Find the sword');
    expect(active.toJson().containsKey('stage'), isFalse);
    expect(active.toJson().containsKey('open'), isFalse);
    expect(Thread.fromJson(active.toJson()).stage, ThreadStage.active);
  });

  test('legacy open:false reads as done, open:true as active', () {
    expect(Thread.fromJson({'id': 'a', 'title': 'x', 'open': false}).stage,
        ThreadStage.done);
    expect(Thread.fromJson({'id': 'b', 'title': 'y', 'open': true}).stage,
        ThreadStage.active);
  });

  test('open getter derives from stage', () {
    expect(Thread(id: 'a', title: 'x', stage: ThreadStage.rumor).open, isTrue);
    expect(Thread(id: 'b', title: 'y').open, isTrue);
    expect(Thread(id: 'c', title: 'z', stage: ThreadStage.done).open, isFalse);
  });

  test('copyWith changes stage and keeps everything else', () {
    final t = Thread(id: 'a', title: 'x', note: 'n', pinned: true, progress: 3);
    final done = t.copyWith(stage: ThreadStage.done);
    expect(done.stage, ThreadStage.done);
    expect(done.note, 'n');
    expect(done.pinned, isTrue);
    expect(done.progress, 3);
  });
}
