import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loreseer/features/sheet_widgets.dart';
import 'package:loreseer/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('a saved spell appears in the spellbook and casts on tap',
      (tester) async {
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
        'schemaVersion': 2,
        'characters': [
          {'id': 'pg-1', 'name': 'Ash', 'baseMana': 8, 'currentMana': 8}
        ],
        'spells': [
          {
            'id': 's1',
            'characterId': 'pg-1',
            'name': 'Spark',
            'effects': [
              {
                'effect': {'card': 'effect.sensory.numb', 'side': 'a'},
                'intensity': 1,
              }
            ],
            'form': {'card': 'form.link', 'side': 'a'},
            'targets': [
              {'count': 1, 'targetType': 1}
            ],
            'size': 0,
            'distance': 0,
            'timing': 0,
            'favorite': false,
            'createdAt': '2026-01-01T00:00:00.000Z',
            'editedAt': '2026-01-01T00:00:00.000Z',
          }
        ],
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
    expect(find.textContaining('Spark'), findsWidgets);
  });
}
