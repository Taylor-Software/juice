import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/features/people_pane.dart';
import 'package:juice_oracle/features/places_pane.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _container() async {
  SharedPreferences.setMockInitialValues({
    'juice.sessions.v1':
        '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
  });
  final c = ProviderContainer();
  addTearDown(c.dispose);
  await c.read(sessionsProvider.future);
  return c;
}

Future<void> _pump(WidgetTester t, ProviderContainer c, Widget child) async {
  t.view.physicalSize = const Size(900, 1800);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(home: Scaffold(body: child)),
  ));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('Places: New adds a place with kind + note', (t) async {
    final c = await _container();
    await _pump(t, c, const PlacesPane());

    expect(find.text('No places yet.'), findsOneWidget);
    await t.tap(find.byKey(const Key('places-add')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('place-name')), 'The Crimson Tower');
    await t.enterText(
        find.byKey(const Key('place-note')), 'A recluse lives here');
    await t.tap(find.byKey(const Key('place-save')));
    await t.pumpAndSettle();

    final places = c.read(placesProvider).value!;
    expect(places.single.name, 'The Crimson Tower');
    expect(places.single.note, 'A recluse lives here');
    expect(find.text('The Crimson Tower'), findsOneWidget);
  });

  testWidgets('Places: blank name is not saved', (t) async {
    final c = await _container();
    await _pump(t, c, const PlacesPane());
    await t.tap(find.byKey(const Key('places-add')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('place-save')));
    await t.pumpAndSettle();
    expect(c.read(placesProvider).value, isEmpty);
  });

  testWidgets('People: New adds an NPC; promote adds a companion Character',
      (t) async {
    final c = await _container();
    await _pump(t, c, const PeoplePane());

    await t.tap(find.byKey(const Key('people-add')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('npc-name')), 'Bram');
    await t.enterText(find.byKey(const Key('npc-role')), 'Innkeeper');
    await t.tap(find.byKey(const Key('npc-save')));
    await t.pumpAndSettle();

    final npc = c.read(npcsProvider).value!.single;
    expect(npc.name, 'Bram');
    expect(npc.role, 'Innkeeper');

    // Promote to the party as a companion.
    await t.tap(find.byKey(Key('npc-party-${npc.id}')));
    await t.pumpAndSettle();
    final chars = c.read(charactersProvider).value!;
    expect(chars.single.name, 'Bram');
    expect(chars.single.role, CharacterRole.companion);
  });

  testWidgets('People: an NPC can be linked to an existing place', (t) async {
    final c = await _container();
    await c.read(placesProvider.notifier).add('Harbor');
    await _pump(t, c, const PeoplePane());

    await t.tap(find.byKey(const Key('people-add')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('npc-name')), 'Sal');
    // Pick the place from the dropdown.
    await t.tap(find.byKey(const Key('npc-place')));
    await t.pumpAndSettle();
    await t.tap(find.text('Harbor').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('npc-save')));
    await t.pumpAndSettle();

    final npc = c.read(npcsProvider).value!.single;
    final harbor = c.read(placesProvider).value!.single;
    expect(npc.placeId, harbor.id);
    // The card shows the linked place name.
    expect(find.text('Harbor'), findsWidgets);
  });
}
