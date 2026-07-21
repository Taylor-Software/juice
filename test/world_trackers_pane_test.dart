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
    await t.enterText(find.byKey(const Key('npc-race')), 'Dwarf');
    await t.enterText(find.byKey(const Key('npc-role')), 'Innkeeper');
    await t.tap(find.byKey(const Key('npc-save')));
    await t.pumpAndSettle();

    final npc = c.read(npcsProvider).value!.single;
    expect(npc.name, 'Bram');
    expect(npc.race, 'Dwarf');
    expect(npc.role, 'Innkeeper');
    // Card subtitle folds race · role · disposition.
    expect(find.textContaining('Dwarf'), findsOneWidget);

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

  testWidgets('NPC card shows a tappable place chip + On-map when pinned',
      (t) async {
    final c = await _container();
    // A place pinned to a hex + an NPC linked to it.
    await c.read(placesProvider.notifier).add('Harbor');
    final place = c.read(placesProvider).value!.single;
    await c.read(placesProvider.notifier).upsert(
        place.copyWith(location: const LocationRef(hexCol: 2, hexRow: 3)));
    await c.read(npcsProvider.notifier).add('Sal', role: 'Dockhand');
    final npc = c.read(npcsProvider).value!.single;
    await c.read(npcsProvider.notifier).upsert(npc.copyWith(placeId: place.id));

    await _pump(t, c, const PeoplePane());
    expect(find.byKey(Key('npc-place-${npc.id}')), findsOneWidget);
    expect(find.byKey(Key('npc-map-${npc.id}')), findsOneWidget);
  });

  testWidgets('People: add a relationship in the editor; card shows the tie',
      (t) async {
    final c = await _container();
    await c.read(npcsProvider.notifier).add('Bram', role: 'Innkeeper');
    await c.read(npcsProvider.notifier).add('Sela', role: 'Guard');
    await _pump(t, c, const PeoplePane());

    final bram =
        c.read(npcsProvider).value!.firstWhere((n) => n.name == 'Bram');
    final sela =
        c.read(npcsProvider).value!.firstWhere((n) => n.name == 'Sela');

    await t.tap(find.byKey(Key('npc-edit-${bram.id}')));
    await t.pumpAndSettle();
    // Pick Sela as the relation target + label it.
    await t.tap(find.byKey(const Key('npc-rel-target')));
    await t.pumpAndSettle();
    await t.tap(find.text('Sela').last);
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('npc-rel-label')), 'rival');
    await t.tap(find.byKey(const Key('npc-rel-add')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('npc-save')));
    await t.pumpAndSettle();

    // Stored on Bram.
    final saved =
        c.read(npcsProvider).value!.firstWhere((n) => n.id == bram.id);
    expect(saved.relations.single.npcId, sela.id);
    expect(saved.relations.single.label, 'rival');
    // Bram's card shows the outgoing tie; Sela's card shows the incoming tie.
    expect(find.byKey(Key('npc-rel-${bram.id}-${sela.id}')), findsOneWidget);
    expect(find.byKey(Key('npc-rel-${sela.id}-${bram.id}')), findsOneWidget);
  });

  testWidgets('Place card shows a people-here backlink chip', (t) async {
    final c = await _container();
    await c.read(placesProvider.notifier).add('Harbor');
    final place = c.read(placesProvider).value!.single;
    await c.read(npcsProvider.notifier).add('Sal');
    final npc = c.read(npcsProvider).value!.single;
    await c.read(npcsProvider.notifier).upsert(npc.copyWith(placeId: place.id));

    await _pump(t, c, const PlacesPane());
    final chip = find.byKey(Key('place-people-${place.id}'));
    expect(chip, findsOneWidget);
    expect(find.text('1 person'), findsOneWidget);
  });
}
