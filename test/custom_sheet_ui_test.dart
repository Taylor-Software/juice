import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/custom_sheet.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('addCustom seeds a character with the given blocks', () async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.characters.v1.default': '[]',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(charactersProvider.future);

    const blocks = [
      CustomBlock(id: 'b1', type: CustomBlockType.counter, label: 'AC'),
    ];
    final id =
        await container.read(charactersProvider.notifier).addCustom(blocks);

    final chars = await container.read(charactersProvider.future);
    final c = chars.firstWhere((e) => e.id == id);
    expect(c.custom, isNotNull);
    expect(c.custom!.blocks.single.label, 'AC');
  });
}
