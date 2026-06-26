import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juice_oracle/state/providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ThreadNotifier.addReturningId', () {
    test('returns the new id and the thread is present with that id', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(sessionsProvider.future);
      final notifier = container.read(threadsProvider.notifier);
      final id = await notifier.addReturningId('The Vow');
      expect(id, isNotEmpty);
      final threads = await container.read(threadsProvider.future);
      expect(threads.any((t) => t.id == id && t.title == 'The Vow'), isTrue);
    });
  });

  group('ThreadNotifier.setProgress', () {
    test('clamps value into 0..progressMax and persists', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(sessionsProvider.future);
      final notifier = container.read(threadsProvider.notifier);
      final id = await notifier.addReturningId('The Vow'); // default max 10

      // over max -> clamps to 10
      await notifier.setProgress(id, 99);
      var threads = await container.read(threadsProvider.future);
      expect(threads.firstWhere((t) => t.id == id).progress, 10);

      // below zero -> clamps to 0
      await notifier.setProgress(id, -5);
      threads = await container.read(threadsProvider.future);
      expect(threads.firstWhere((t) => t.id == id).progress, 0);

      // in-range value persists exactly
      await notifier.setProgress(id, 4);
      threads = await container.read(threadsProvider.future);
      expect(threads.firstWhere((t) => t.id == id).progress, 4);

      // unknown id is a no-op (no throw)
      await notifier.setProgress('nope', 3);
    });
  });

  group('CharacterNotifier.addReturningId', () {
    test('returns the new id and the character is present with that id',
        () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(sessionsProvider.future);
      final notifier = container.read(charactersProvider.notifier);
      final id = await notifier.addReturningId('Mara');
      expect(id, isNotEmpty);
      final characters = await container.read(charactersProvider.future);
      expect(characters.any((c) => c.id == id && c.name == 'Mara'), isTrue);
    });
  });
}
