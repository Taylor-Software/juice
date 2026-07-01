// test/apply_loop_kit_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice_oracle/engine/custom_table.dart';
import 'package:juice_oracle/engine/loop_kit.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/engine/quick_ref.dart';
import 'package:juice_oracle/state/play_context.dart';
import 'package:juice_oracle/state/providers.dart';

Future<WidgetRef> _pumpRef(WidgetTester tester) async {
  late WidgetRef captured;
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      home: Consumer(builder: (context, ref, _) {
        captured = ref;
        return const SizedBox();
      }),
    ),
  ));
  await tester.pump();
  return captured;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'applyLoopKit appends tables/cards and activates the starter scene',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"s1","sessions":[{"id":"s1","name":"Test"}]}',
    });
    final ref = await _pumpRef(tester);
    await ref.read(sessionsProvider.future);

    const kit = LoopKit(
      name: 'Ash and Embers',
      system: 'ironsworn',
      tables: [
        CustomTable(id: 't1', name: 'Ashland Omens', rows: [CustomRow('X')]),
      ],
      refCards: [
        UserRefCard(id: 'c1', title: 'Ashland Facts', sections: []),
      ],
      sceneTitle: 'Cinders on the Wind',
      sceneBody: 'You wake in a burned grove.',
    );

    await applyLoopKit(ref, kit);

    final tables = ref.read(customTablesProvider).value!;
    expect(tables, hasLength(1));
    expect(tables.single.name, 'Ashland Omens');

    final cards = ref.read(userRefCardsProvider).value!;
    expect(cards, hasLength(1));
    expect(cards.single.title, 'Ashland Facts');

    final journal = ref.read(journalProvider).value!;
    expect(journal, hasLength(1));
    expect(journal.single.kind, JournalKind.scene);
    expect(journal.single.title, 'Cinders on the Wind');
    expect(journal.single.body, 'You wake in a burned grove.');

    final ctx = ref.read(playContextProvider).value!;
    expect(ctx.activeSceneId, journal.single.id);
  });

  testWidgets('a kit with no scene text does not create a journal entry',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"s1","sessions":[{"id":"s1","name":"Test"}]}',
    });
    final ref = await _pumpRef(tester);
    await ref.read(sessionsProvider.future);

    const kit = LoopKit(name: 'Tables Only', tables: [
      CustomTable(id: 't1', name: 'T', rows: [CustomRow('X')]),
    ]);
    await applyLoopKit(ref, kit);

    expect(ref.read(journalProvider).value, isEmpty);
    expect(ref.read(playContextProvider).value!.activeSceneId, isNull);
  });
}
