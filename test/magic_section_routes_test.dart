import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loreseer/features/sheet_widgets.dart';
import 'package:loreseer/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _pumpLinked(WidgetTester tester) async {
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
        'polarityId': 'pg-1',
      }
    ]),
    'loreseer.magic.v1.c1': jsonEncode({
      'characters': [
        {'id': 'pg-1', 'name': 'Ash', 'baseMana': 4, 'currentMana': 4}
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
          return magicSection(context, ref, live);
        }),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('Build spell pushes the spell builder screen', (tester) async {
    await _pumpLinked(tester);
    await tester.tap(find.byKey(const Key('magic-build')));
    await tester.pumpAndSettle();
    expect(find.byType(Scaffold), findsWidgets);
    expect(find.textContaining('Spell'), findsWidgets);
  });

  testWidgets('Card reference pushes the reference screen', (tester) async {
    await _pumpLinked(tester);
    await tester.tap(find.byKey(const Key('magic-reference')));
    await tester.pumpAndSettle();
    expect(find.text('Card Reference'), findsOneWidget);
  });

  testWidgets('User guide pushes the guide screen', (tester) async {
    await _pumpLinked(tester);
    await tester.tap(find.byKey(const Key('magic-guide')));
    await tester.pumpAndSettle();
    expect(find.text('User Guide'), findsOneWidget);
  });
}
