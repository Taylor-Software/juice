import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice_oracle/engine/custom_table.dart';
import 'package:juice_oracle/state/providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('adds, persists, and reloads custom tables', () async {
    SharedPreferences.setMockInitialValues({});
    final c1 = ProviderContainer();
    await c1.read(customTablesProvider.future);
    await c1.read(customTablesProvider.notifier).add(
        const CustomTable(id: 'a', name: 'Names', rows: ['X', 'Y']));
    expect(c1.read(customTablesProvider).value, hasLength(1));
    c1.dispose();

    // New container reads the same mock store -> persisted.
    final c2 = ProviderContainer();
    final loaded = await c2.read(customTablesProvider.future);
    expect(loaded.single.name, 'Names');
    expect(loaded.single.rows, ['X', 'Y']);
    c2.dispose();
  });

  test('replace and remove', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    final n = c.read(customTablesProvider.notifier);
    await c.read(customTablesProvider.future);
    await n.add(const CustomTable(id: 'a', name: 'A', rows: ['1']));
    await n.replace(const CustomTable(id: 'a', name: 'A2', rows: ['1', '2']));
    expect(c.read(customTablesProvider).value!.single.name, 'A2');
    await n.remove('a');
    expect(c.read(customTablesProvider).value, isEmpty);
    c.dispose();
  });
}
