import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loreseer/features/sheet_widgets.dart';
import 'package:loreseer/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _pump(WidgetTester tester,
    {String? polarityId}) async {
  SharedPreferences.setMockInitialValues({
    'loreseer.sessions.v1':
        '{"active":"c1","sessions":[{"id":"c1","name":"Test"}]}',
    'loreseer.characters.v1.c1': jsonEncode([
      {
        'id': 'ch1',
        'name': 'Ash',
        'stats': [],
        'tracks': [],
        'tags': [],
        if (polarityId != null) 'polarityId': polarityId,
      }
    ]),
    if (polarityId != null)
      'loreseer.magic.v1.c1': jsonEncode({
        'characters': [
          {'id': polarityId, 'name': 'Ash', 'baseMana': 4, 'currentMana': 4}
        ],
        'spells': [],
      }),
  });
  final container = ProviderContainer();
  addTearDown(container.dispose);
  final char = (await container.read(charactersProvider.future)).single;
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(
        body: Consumer(builder: (context, ref, __) {
          final live =
              ref.watch(charactersProvider).valueOrNull?.firstOrNull ?? char;
          return SingleChildScrollView(child: magicSection(context, ref, live));
        }),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('shows an enable button when magic is not linked',
      (tester) async {
    await _pump(tester);
    expect(find.byKey(const Key('magic-enable')), findsOneWidget);
    expect(find.byKey(const Key('magic-mana-bar')), findsNothing);
  });

  testWidgets('tapping enable creates the link and swaps in the mana bar',
      (tester) async {
    final c = await _pump(tester);
    await tester.tap(find.byKey(const Key('magic-enable')));
    await tester.pumpAndSettle();
    final chars = await c.read(charactersProvider.future);
    expect(chars.single.polarityId, isNotNull);
    expect(find.byKey(const Key('magic-mana-bar')), findsOneWidget);
  });

  testWidgets('shows the mana bar directly when already linked',
      (tester) async {
    await _pump(tester, polarityId: 'pg-1');
    expect(find.byKey(const Key('magic-enable')), findsNothing);
    expect(find.byKey(const Key('magic-mana-bar')), findsOneWidget);
  });

  testWidgets(
      'when linked but the pg.Character is missing, shows magic-disable '
      'instead of the mana bar; tapping it clears the link', (tester) async {
    // polarityId is set on the juice character but loreseer.magic.v1 has no
    // matching pg.Character (e.g. orphaned by a bug, or hand-edited data).
    SharedPreferences.setMockInitialValues({
      'loreseer.sessions.v1':
          '{"active":"c1","sessions":[{"id":"c1","name":"Test"}]}',
      'loreseer.characters.v1.c1': jsonEncode([
        {
          'id': 'ch1',
          'name': 'Ash',
          'stats': [],
          'tracks': [],
          'tags': [],
          'polarityId': 'missing-pg',
        }
      ]),
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final char = (await container.read(charactersProvider.future)).single;
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(builder: (context, ref, __) {
            final live =
                ref.watch(charactersProvider).valueOrNull?.firstOrNull ?? char;
            return SingleChildScrollView(
                child: magicSection(context, ref, live));
          }),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('magic-mana-bar')), findsNothing);
    expect(find.byKey(const Key('magic-disable')), findsOneWidget);

    await tester.tap(find.byKey(const Key('magic-disable')));
    await tester.pumpAndSettle();

    final chars = await container.read(charactersProvider.future);
    expect(chars.single.polarityId, isNull);
    expect(find.byKey(const Key('magic-enable')), findsOneWidget);
  });

  testWidgets(
      'when normally linked, magic-disable sits beside the mana bar and '
      'confirming clears the link back to magic-enable', (tester) async {
    await _pump(tester, polarityId: 'pg-1');
    expect(find.byKey(const Key('magic-mana-bar')), findsOneWidget);
    expect(find.byKey(const Key('magic-disable')), findsOneWidget);

    await tester.tap(find.byKey(const Key('magic-disable')));
    await tester.pumpAndSettle();
    // Confirm dialog: "Disable magic casting?" -> tap Disable.
    expect(find.text('Disable magic casting?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Disable'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('magic-enable')), findsOneWidget);
    expect(find.byKey(const Key('magic-mana-bar')), findsNothing);
  });
}
