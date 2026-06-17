import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/features/tracker_screen.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const seeded =
      '[{"id":"c1","name":"Ash","note":"","stats":[],"tracks":[{"label":"HP","current":7,"max":10}],"tags":[]}]';

  // The Threads/Characters tab chrome now lives in tracking_tab.dart; these
  // tests pump the public panes directly.
  Future<ProviderContainer> pump(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.characters.v1.default': seeded,
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CharactersPane()))));
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
        tester.element(find.byType(CharactersPane)));
  }

  Future<ProviderContainer> pumpThreads(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.threads.v1.default':
          '[{"id":"t1","title":"Find the Relic","open":true}]',
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: ThreadsPane()))));
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(ThreadsPane)));
  }

  testWidgets('list row shows first-track summary', (tester) async {
    await pump(tester);
    expect(find.text('Ash'), findsOneWidget);
    expect(find.text('HP 7/10'), findsOneWidget);
  });

  testWidgets('track steppers adjust and persist, clamped', (tester) async {
    final container = await pump(tester);
    await tester.tap(find.text('Ash'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('track-plus-0')));
    await tester.pumpAndSettle();
    expect(find.text('8/10'), findsOneWidget);
    final chars = await container.read(charactersProvider.future);
    expect(chars.single.tracks.single.current, 8);
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.byKey(const Key('track-plus-0')));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('10/10'), findsOneWidget);
  });

  testWidgets('add stat and tag from the editor; back returns to list',
      (tester) async {
    final container = await pump(tester);
    await tester.tap(find.text('Ash'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-stat')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('stat-label')), 'Iron');
    await tester.enterText(find.byKey(const Key('stat-value')), '+2');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Iron'), findsOneWidget);
    await tester.tap(find.byKey(const Key('add-tag')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('tag-input')), 'wounded');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('wounded'), findsOneWidget);
    final c = (await container.read(charactersProvider.future)).single;
    expect(c.stats.single.value, '+2');
    expect(c.tags, ['wounded']);
    await tester.tap(find.byKey(const Key('sheet-back')));
    await tester.pumpAndSettle();
    expect(find.text('HP 7/10'), findsOneWidget);
  });

  testWidgets('sheet shows the emulation summary only when emulation exists',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.characters.v1.default':
          '[{"id":"c1","name":"Ash","note":"","stats":[],"tracks":[],"tags":[]},'
              '{"id":"c2","name":"Em","note":"","stats":[],"tracks":[],"tags":["brave"],'
              '"emulation":{"tokens":3,"prominentTags":["brave","bold"],"usedTags":[]}}]',
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CharactersPane()))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Em'));
    await tester.pumpAndSettle();
    expect(
        find.text('Emulation: 2 prominent traits · 3 tokens'), findsOneWidget);
    await tester.tap(find.byKey(const Key('sheet-back')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ash'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Emulation:'), findsNothing);
  });

  testWidgets('sheet falls back to list when the character disappears',
      (tester) async {
    final container = await pump(tester);
    await tester.tap(find.text('Ash'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sheet-back')), findsOneWidget);
    // Character removed underneath the open sheet (session switch, import…).
    await container.read(charactersProvider.notifier).remove('c1');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('sheet-back')), findsNothing);
    expect(find.textContaining('No characters yet'), findsOneWidget);
  });

  testWidgets('character list row has star IconButton that toggles starred',
      (tester) async {
    final container = await pump(tester);
    // Star button present in list row.
    expect(find.byKey(const Key('star-char-c1')), findsOneWidget);
    // Initially not starred.
    expect((await container.read(charactersProvider.future)).single.starred,
        isFalse);
    // Tap star → starred.
    await tester.tap(find.byKey(const Key('star-char-c1')));
    await tester.pumpAndSettle();
    expect((await container.read(charactersProvider.future)).single.starred,
        isTrue);
    // Tap again → unstarred.
    await tester.tap(find.byKey(const Key('star-char-c1')));
    await tester.pumpAndSettle();
    expect((await container.read(charactersProvider.future)).single.starred,
        isFalse);
  });

  testWidgets('thread list row has pin IconButton that toggles pinned',
      (tester) async {
    final container = await pumpThreads(tester);
    // Pin button present.
    expect(find.byKey(const Key('pin-thread-t1')), findsOneWidget);
    // Initially not pinned.
    expect(
        (await container.read(threadsProvider.future)).single.pinned, isFalse);
    // Tap pin → pinned.
    await tester.tap(find.byKey(const Key('pin-thread-t1')));
    await tester.pumpAndSettle();
    expect(
        (await container.read(threadsProvider.future)).single.pinned, isTrue);
    // Tap again → unpinned.
    await tester.tap(find.byKey(const Key('pin-thread-t1')));
    await tester.pumpAndSettle();
    expect(
        (await container.read(threadsProvider.future)).single.pinned, isFalse);
  });

  // A character that already carries an Ironsworn sheet (skips create flow).
  Future<ProviderContainer> pumpIronsworn(WidgetTester tester,
      {String iron = '{"edge":3,"heart":2,"iron":2,"shadow":1,"wits":1,'
          '"health":5,"spirit":5,"supply":5,"momentum":2,'
          '"xpEarned":0,"xpSpent":0,"bonds":0}'}) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1",'
              '"systems":["ironsworn"]}]}',
      'juice.characters.v1.default':
          '[{"id":"iw","name":"Ulla","note":"","stats":[],"tracks":[],'
              '"tags":[],"ironsworn":$iron}]',
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CharactersPane()))));
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
        tester.element(find.byType(CharactersPane)));
  }

  testWidgets('opening an Ironsworn character shows the bespoke sheet',
      (tester) async {
    await pumpIronsworn(tester);
    await tester.tap(find.text('Ulla'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ironsworn-sheet')), findsOneWidget);
    expect(find.text('EDGE'), findsOneWidget);
    expect(find.text('Health'), findsOneWidget);
  });

  testWidgets('meter and momentum steppers adjust and persist', (tester) async {
    final c = await pumpIronsworn(tester);
    await tester.tap(find.text('Ulla'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('iw-health-minus')));
    await tester.pumpAndSettle();
    expect(
        (await c.read(charactersProvider.future)).single.ironsworn!.health, 4);
    await tester.tap(find.byKey(const Key('iw-mom-minus')));
    await tester.pumpAndSettle();
    expect((await c.read(charactersProvider.future)).single.ironsworn!.momentum,
        1);
  });

  testWidgets('Burn sets momentum to reset; debility lowers max',
      (tester) async {
    final c = await pumpIronsworn(tester,
        iron: '{"edge":3,"heart":2,"iron":2,"shadow":1,"wits":1,"health":5,'
            '"spirit":5,"supply":5,"momentum":9,"xpEarned":0,"xpSpent":0,'
            '"bonds":0}');
    await tester.tap(find.text('Ulla'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('iw-burn')));
    await tester.pumpAndSettle();
    expect((await c.read(charactersProvider.future)).single.ironsworn!.momentum,
        2);
    // Mark a debility: max drops to 9.
    await tester.drag(
        find.byKey(const Key('ironsworn-sheet')), const Offset(0, -200));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('iw-deb-shaken')));
    await tester.pumpAndSettle();
    final s = (await c.read(charactersProvider.future)).single.ironsworn!;
    expect(s.debilities, {'shaken'});
    expect(s.momentumMax, 9);
  });

  testWidgets('add a vow then mark progress', (tester) async {
    final c = await pumpIronsworn(tester);
    await tester.tap(find.text('Ulla'));
    await tester.pumpAndSettle();
    await tester.drag(
        find.byKey(const Key('ironsworn-sheet')), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('iw-add-vow')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('vow-name')), 'Avenge');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('Avenge'), findsOneWidget);
    // Mark one progress (default rank dangerous => +8 ticks => 2 boxes).
    await tester.tap(find.byKey(const Key('iw-vow-0-mark')));
    await tester.pumpAndSettle();
    final vow =
        (await c.read(charactersProvider.future)).single.ironsworn!.vows.single;
    expect(vow.name, 'Avenge');
    expect(vow.ticks, 8);
    expect(vow.boxes, 2);
  });

  testWidgets('pick an asset from the ruleset and toggle an ability',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1",'
              '"systems":["ironsworn"]}]}',
      'juice.rulesets.v1': '["classic"]',
      'juice.characters.v1.default':
          '[{"id":"iw","name":"Ulla","note":"","stats":[],"tracks":[],'
              '"tags":[],"ironsworn":{"edge":3,"heart":2,"iron":2,"shadow":1,'
              '"wits":1,"health":5,"spirit":5,"supply":5,"momentum":2,'
              '"xpEarned":0,"xpSpent":0,"bonds":0}}]',
    });
    final fixture = {
      'asset_collections': [
        {
          'name': 'Combat Talent',
          'assets': [
            {
              'id': 'classic/assets/combat_talent/swordmaster',
              'name': 'Swordmaster',
              'category': 'Combat Talent',
              'abilities': [
                {'text': 'Strike harder', 'enabled': true},
                {'text': 'Press the attack', 'enabled': false},
              ],
            },
          ],
        },
      ],
    };
    final c = ProviderContainer(overrides: [
      rulesetDataProvider('classic').overrideWith((ref) async => fixture),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CharactersPane()))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ulla'));
    await tester.pumpAndSettle();
    await tester.drag(
        find.byKey(const Key('ironsworn-sheet')), const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('iw-add-asset')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(
        const Key('pick-asset-classic/assets/combat_talent/swordmaster')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Swordmaster'), findsOneWidget);
    var asset = (await c.read(charactersProvider.future))
        .single
        .ironsworn!
        .assets
        .single;
    expect(asset.enabledAbilities, [true, false]);
    // Toggle the second ability on.
    await tester.ensureVisible(find.byKey(const Key('iw-asset-0-ability-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('iw-asset-0-ability-1')));
    await tester.pumpAndSettle();
    asset = (await c.read(charactersProvider.future))
        .single
        .ironsworn!
        .assets
        .single;
    expect(asset.enabledAbilities, [true, true]);
  });

  testWidgets('create flow makes a pre-made Ironsworn character',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1",'
              '"systems":["ironsworn"]}]}',
      'juice.characters.v1.default': '[]',
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CharactersPane()))));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new-ironsworn')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ironsworn-sheet')), findsOneWidget);
    final chars = await c.read(charactersProvider.future);
    expect(chars.single.ironsworn!.edge, 3);
  });
}
