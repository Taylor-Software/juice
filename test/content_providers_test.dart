import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/state/providers.dart';

void main() {
  test('contentMonstersProvider aggregates + de-dups by id', () async {
    final container = ProviderContainer(overrides: [
      systemFoesProvider('dnd').overrideWith((ref) async =>
          [const Creature(id: 'dnd-goblin', name: 'Goblin')]),
      systemFoesProvider('cairn').overrideWith((ref) async =>
          [const Creature(id: 'cairn-wolf', name: 'Wolf')]),
      foesProvider.overrideWith((ref) async => const []),
      bestiaryProvider.overrideWith(() => _FakeBestiary([
            const Creature(id: 'dnd-goblin', name: 'Goblin (dupe)'),
          ])),
      enabledContentSystemsProvider.overrideWith((ref) => ['dnd', 'cairn']),
    ]);
    addTearDown(container.dispose);
    final monsters = await container.read(contentMonstersProvider.future);
    final ids = monsters.map((m) => m.id).toList();
    expect(ids, containsAll(['dnd-goblin', 'cairn-wolf']));
    expect(ids.where((i) => i == 'dnd-goblin').length, 1); // de-duped
  });
}

class _FakeBestiary extends BestiaryNotifier {
  _FakeBestiary(this._seed);
  final List<Creature> _seed;
  @override
  Future<List<Creature>> build() async => _seed;
}
