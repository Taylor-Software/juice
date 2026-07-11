// Flesh-out coverage on the world trackers: People, Places, and Rumors cards
// carry an aiReady-gated AI button that generates detail, reviews it in the
// shared Append/Cancel dialog, and appends to the entity's note.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/features/people_pane.dart';
import 'package:juice_oracle/features/places_pane.dart';
import 'package:juice_oracle/features/rumors_pane.dart';
import 'package:juice_oracle/state/interpreter.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_interpreter.dart';

FakeInterpreterService _fake() => FakeInterpreterService(
    initial: const InterpreterStatus(InterpreterPhase.ready));

Future<ProviderContainer> _container(FakeInterpreterService fake,
    {bool aiEnabled = true}) async {
  SharedPreferences.setMockInitialValues({
    'juice.sessions.v1':
        '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    if (aiEnabled) 'juice.ai_enabled.v1': true,
  });
  final c = ProviderContainer(overrides: [
    interpreterServiceProvider.overrideWithValue(fake),
  ]);
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
  testWidgets('People: flesh-out appends detail to the NPC note', (t) async {
    final fake = _fake();
    final c = await _container(fake);
    await c
        .read(npcsProvider.notifier)
        .upsert(const Npc(id: 'n1', name: 'Marta', role: 'ferrywoman'));
    await _pump(t, c, const PeoplePane());

    await t.tap(find.byKey(const Key('flesh-out-npc-n1')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('flesh-out-review')), findsOneWidget);
    await t.tap(find.byKey(const Key('flesh-out-append')));
    await t.pumpAndSettle();

    expect(fake.lastFleshOutSeed?.entityKind, 'NPC');
    expect(fake.lastFleshOutSeed?.name, 'Marta');
    expect(fake.lastFleshOutSeed?.existingDetail, 'ferrywoman');
    final npc = c.read(npcsProvider).value!.single;
    expect(npc.note, 'Fleshed-out detail.');
  });

  testWidgets('People: Cancel leaves the note untouched', (t) async {
    final fake = _fake();
    final c = await _container(fake);
    await c
        .read(npcsProvider.notifier)
        .upsert(const Npc(id: 'n1', name: 'Marta', note: 'Old note.'));
    await _pump(t, c, const PeoplePane());

    await t.tap(find.byKey(const Key('flesh-out-npc-n1')));
    await t.pumpAndSettle();
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();

    expect(c.read(npcsProvider).value!.single.note, 'Old note.');
  });

  testWidgets('Places: flesh-out appends detail to the place note', (t) async {
    final fake = _fake();
    final c = await _container(fake);
    await c.read(placesProvider.notifier).upsert(
        const Place(id: 'p1', name: 'The Old Mill', note: 'Burned once.'));
    await _pump(t, c, const PlacesPane());

    await t.tap(find.byKey(const Key('flesh-out-place-p1')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('flesh-out-append')));
    await t.pumpAndSettle();

    expect(fake.lastFleshOutSeed?.entityKind, 'location');
    final place = c.read(placesProvider).value!.single;
    expect(place.note, 'Burned once.\n\nFleshed-out detail.');
  });

  testWidgets('Rumors: flesh-out appends detail to the rumor note', (t) async {
    final fake = _fake();
    final c = await _container(fake);
    await c.read(rumorsProvider.notifier).add('The mine is haunted.');
    await _pump(t, c, const RumorsPane());

    final rumor = c.read(rumorsProvider).value!.single;
    await t.tap(find.byKey(Key('flesh-out-rumor-${rumor.id}')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('flesh-out-append')));
    await t.pumpAndSettle();

    expect(fake.lastFleshOutSeed?.entityKind, 'rumor');
    expect(fake.lastFleshOutSeed?.name, 'The mine is haunted.');
    expect(c.read(rumorsProvider).value!.single.note, 'Fleshed-out detail.');
  });

  testWidgets('AI off hides every world-tracker flesh-out button', (t) async {
    final c = await _container(_fake(), aiEnabled: false);
    await c
        .read(npcsProvider.notifier)
        .upsert(const Npc(id: 'n1', name: 'Marta'));
    await _pump(t, c, const PeoplePane());
    expect(find.byKey(const Key('flesh-out-npc-n1')), findsNothing);
  });
}
