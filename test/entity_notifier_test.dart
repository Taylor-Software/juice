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
