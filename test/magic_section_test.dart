import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loreseer/features/sheet_widgets.dart';
import 'package:loreseer/state/magic_controller.dart';
import 'package:loreseer/state/providers.dart';
import 'package:polarity_grammar/polarity_grammar.dart' as pg;
import 'package:shared_preferences/shared_preferences.dart';

/// A [MagicController] whose [build] never completes — forces
/// `ref.watch(magicProvider)` to stay `AsyncLoading` for the duration of a
/// test, so `magicSection`'s loading branch is exercised for real instead of
/// by inspection only.
class _HangingMagicController extends MagicController {
  @override
  Future<pg.Library> build() => Completer<pg.Library>().future;
}

/// A [MagicController] whose [build] always throws — forces
/// `ref.watch(magicProvider)` into `AsyncError`, so `magicSection`'s error
/// branch (incl. the `magic-retry` button) is exercised for real.
class _ThrowingMagicController extends MagicController {
  @override
  Future<pg.Library> build() async {
    throw StateError('simulated magic library load failure');
  }
}

Future<ProviderContainer> _pumpWithMagicOverride(
    WidgetTester tester, MagicController Function() factory) async {
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
  });
  final container =
      ProviderContainer(overrides: [magicProvider.overrideWith(factory)]);
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
  return container;
}

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

  testWidgets(
      'AsyncLoading: shows the Magic header + magic-loading spinner instead '
      'of vanishing', (tester) async {
    await _pumpWithMagicOverride(tester, () => _HangingMagicController());
    await tester.pump();

    expect(find.text('Magic'), findsOneWidget);
    expect(find.byKey(const Key('magic-loading')), findsOneWidget);
    expect(find.byKey(const Key('magic-mana-bar')), findsNothing);
    expect(find.byKey(const Key('magic-enable')), findsNothing);
  });

  testWidgets(
      'AsyncError: shows the Magic header + error text + magic-retry; '
      'tapping retry does not throw', (tester) async {
    await _pumpWithMagicOverride(tester, () => _ThrowingMagicController());
    await tester.pumpAndSettle();

    expect(find.text('Magic'), findsOneWidget);
    expect(find.byKey(const Key('magic-retry')), findsOneWidget);
    expect(find.textContaining('Could not load magic data'), findsOneWidget);
    expect(find.byKey(const Key('magic-mana-bar')), findsNothing);

    await tester.tap(find.byKey(const Key('magic-retry')));
    await tester.pumpAndSettle();
    // The overridden factory throws again on retry (same simulated failure),
    // so this proves the retry path re-invalidates + re-renders without
    // crashing, not that retry can ever succeed.
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('magic-retry')), findsOneWidget);
  });
}
