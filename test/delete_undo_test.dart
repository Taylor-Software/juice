import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:loreseer/state/providers.dart';

void _seed(Map<String, String> scoped) {
  SharedPreferences.setMockInitialValues({
    'loreseer.sessions.v1':
        '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    ...scoped,
  });
}

void main() {
  test('restoreAt re-inserts a deleted row at its old index', () async {
    _seed({
      'loreseer.threads.v1.default':
          '[{"id":"a","title":"A"},{"id":"b","title":"B"},{"id":"c","title":"C"}]',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final threads = await c.read(threadsProvider.future);
    final doomed = threads[1];

    await c.read(threadsProvider.notifier).remove('b');
    expect(c.read(threadsProvider).value!.map((t) => t.id), ['a', 'c']);

    await c.read(threadsProvider.notifier).restoreAt(1, doomed);
    expect(c.read(threadsProvider).value!.map((t) => t.id), ['a', 'b', 'c']);
  });

  test('restoreAt clamps an out-of-range index', () async {
    _seed({
      'loreseer.threads.v1.default': '[{"id":"a","title":"A"}]',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final only = (await c.read(threadsProvider.future)).single;

    await c.read(threadsProvider.notifier).remove('a');
    await c.read(threadsProvider.notifier).restoreAt(99, only);
    expect(c.read(threadsProvider).value!.single.id, 'a');
  });

  test('undismiss returns a dismissed suggestion key', () async {
    _seed({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(dismissedSuggestionsProvider.future);

    await c.read(dismissedSuggestionsProvider.notifier).dismiss('char:Kara');
    expect(c.read(dismissedSuggestionsProvider).value, contains('char:Kara'));

    await c.read(dismissedSuggestionsProvider.notifier).undismiss('char:Kara');
    expect(c.read(dismissedSuggestionsProvider).value,
        isNot(contains('char:Kara')));
  });
}
