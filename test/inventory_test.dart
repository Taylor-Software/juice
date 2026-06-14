import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/state/providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('InvItem round-trips; props omitted when empty', () {
    const i = InvItem(id: '1', name: 'Torch', qty: 3, props: 'lit');
    final back = InvItem.fromJson(i.toJson());
    expect(back.name, 'Torch');
    expect(back.qty, 3);
    expect(back.props, 'lit');
    expect(const InvItem(id: '2', name: 'Rope').toJson().containsKey('props'),
        isFalse);
  });

  test('InventoryNotifier add/adjust/setProps/remove persist', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(sessionsProvider.future);
    final n = c.read(inventoryProvider.notifier);
    await c.read(inventoryProvider.future);

    await n.add('Torch', qty: 2);
    final items = await c.read(inventoryProvider.future);
    expect(items.single.qty, 2);
    final id = items.single.id;

    await n.adjustQty(id, 3);
    expect((await c.read(inventoryProvider.future)).single.qty, 5);
    await n.adjustQty(id, -100); // clamps at 0
    expect((await c.read(inventoryProvider.future)).single.qty, 0);

    await n.setProps(id, 'burning');
    expect((await c.read(inventoryProvider.future)).single.props, 'burning');

    await n.remove(id);
    expect(await c.read(inventoryProvider.future), isEmpty);
  });
}
