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
    await c1.read(customTablesProvider.notifier).add(const CustomTable(
        id: 'a', name: 'Names', rows: [CustomRow('X'), CustomRow('Y')]));
    expect(c1.read(customTablesProvider).value, hasLength(1));
    c1.dispose();

    final c2 = ProviderContainer();
    final loaded = await c2.read(customTablesProvider.future);
    expect(loaded.single.name, 'Names');
    expect(loaded.single.rows.map((r) => r.text).toList(), ['X', 'Y']);
    c2.dispose();
  });

  test('persists ranges mode + dice + spans', () async {
    SharedPreferences.setMockInitialValues({});
    final c1 = ProviderContainer();
    await c1.read(customTablesProvider.future);
    await c1.read(customTablesProvider.notifier).add(const CustomTable(
          id: 'r',
          name: 'Loot',
          mode: TableRoll.ranges,
          dice: 'd100',
          rows: [CustomRow('Gold', min: 1, max: 100)],
        ));
    c1.dispose();

    final c2 = ProviderContainer();
    final loaded = await c2.read(customTablesProvider.future);
    expect(loaded.single.mode, TableRoll.ranges);
    expect(loaded.single.dice, 'd100');
    expect(loaded.single.rows.single.max, 100);
    c2.dispose();
  });

  test('loads legacy string-row tables from prefs', () async {
    SharedPreferences.setMockInitialValues({
      'juice.custom_tables.v1':
          '[{"id":"old","name":"Legacy","rows":["A","B"]}]',
    });
    final c = ProviderContainer();
    final loaded = await c.read(customTablesProvider.future);
    expect(loaded.single.mode, TableRoll.uniform);
    expect(loaded.single.rows.map((r) => r.text).toList(), ['A', 'B']);
    c.dispose();
  });

  test('replace and remove', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    final n = c.read(customTablesProvider.notifier);
    await c.read(customTablesProvider.future);
    await n.add(const CustomTable(id: 'a', name: 'A', rows: [CustomRow('1')]));
    await n.replace(const CustomTable(
        id: 'a', name: 'A2', rows: [CustomRow('1'), CustomRow('2')]));
    expect(c.read(customTablesProvider).value!.single.name, 'A2');
    await n.remove('a');
    expect(c.read(customTablesProvider).value, isEmpty);
    c.dispose();
  });
}
