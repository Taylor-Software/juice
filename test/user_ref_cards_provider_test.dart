// test/user_ref_cards_provider_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice_oracle/engine/quick_ref.dart';
import 'package:juice_oracle/state/providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('addAll appends with fresh ids, never clobbers existing', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    await c.read(userRefCardsProvider.future);
    await c.read(userRefCardsProvider.notifier).add(
        const UserRefCard(id: 'existing', title: 'Existing', sections: []));

    await c.read(userRefCardsProvider.notifier).addAll([
      const UserRefCard(id: 'incoming-1', title: 'Imported A', sections: [
        QuickRefSection('Notes', ['line one']),
      ]),
      const UserRefCard(id: 'incoming-1', title: 'Imported B', sections: []),
    ]);

    final loaded = c.read(userRefCardsProvider).value!;
    expect(loaded, hasLength(3));
    expect(loaded.map((c) => c.title).toList(),
        ['Existing', 'Imported A', 'Imported B']);
    // Fresh ids: the two imported cards shared id 'incoming-1' in the
    // source but must not collide after import.
    final importedIds =
        loaded.where((c) => c.title.startsWith('Imported')).map((c) => c.id);
    expect(importedIds.toSet(), hasLength(2));
    c.dispose();
  });

  test('addAll of an empty list is a no-op', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    await c.read(userRefCardsProvider.future);
    await c.read(userRefCardsProvider.notifier).addAll([]);
    expect(c.read(userRefCardsProvider).value, isEmpty);
    c.dispose();
  });
}
