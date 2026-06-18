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

  Future<ProviderContainer> pumpStarforged(WidgetTester tester,
      {String sf = '{"edge":3,"heart":2,"iron":2,"shadow":1,"wits":1,'
          '"health":5,"spirit":5,"supply":5,"momentum":2,"xpEarned":0,'
          '"xpSpent":0,"questsLegacy":0,"bondsLegacy":0,"discoveriesLegacy":0}'}) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1",'
              '"systems":["ironsworn"]}]}',
      'juice.characters.v1.default':
          '[{"id":"sf","name":"Nova","note":"","stats":[],"tracks":[],'
              '"tags":[],"starforged":$sf}]',
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CharactersPane()))));
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
        tester.element(find.byType(CharactersPane)));
  }

  testWidgets('opening a Starforged character shows the bespoke sheet',
      (tester) async {
    await pumpStarforged(tester);
    await tester.tap(find.text('Nova'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('starforged-sheet')), findsOneWidget);
    expect(find.text('EDGE'), findsOneWidget);
    // 'Quests' label is in Legacy Tracks section, below the 600px test viewport;
    // drag to scroll it into view so the lazy ListView builds the widget.
    await tester.drag(
        find.byKey(const Key('starforged-sheet')), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.text('Quests'), findsOneWidget);
  });

  testWidgets('SF meter/momentum/legacy steppers persist', (tester) async {
    final c = await pumpStarforged(tester);
    await tester.tap(find.text('Nova'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sf-health-minus')));
    await tester.pumpAndSettle();
    expect(
        (await c.read(charactersProvider.future)).single.starforged!.health, 4);
    await tester.tap(find.byKey(const Key('sf-mom-minus')));
    await tester.pumpAndSettle();
    expect(
        (await c.read(charactersProvider.future)).single.starforged!.momentum,
        1);
    // sf-quests-plus is below the 600px test viewport; drag to scroll it into
    // view before ensureVisible (lazy ListView won't build it until near-visible).
    await tester.drag(
        find.byKey(const Key('starforged-sheet')), const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('sf-quests-plus')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sf-quests-plus')));
    await tester.pumpAndSettle();
    expect(
        (await c.read(charactersProvider.future))
            .single
            .starforged!
            .questsLegacy,
        1);
  });

  testWidgets('SF Burn resets; impact lowers max', (tester) async {
    final c = await pumpStarforged(tester,
        sf: '{"edge":3,"heart":2,"iron":2,"shadow":1,"wits":1,"health":5,'
            '"spirit":5,"supply":5,"momentum":9,"xpEarned":0,"xpSpent":0,'
            '"questsLegacy":0,"bondsLegacy":0,"discoveriesLegacy":0}');
    await tester.tap(find.text('Nova'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sf-burn')));
    await tester.pumpAndSettle();
    expect(
        (await c.read(charactersProvider.future)).single.starforged!.momentum,
        2);
    await tester.ensureVisible(find.byKey(const Key('sf-imp-doomed')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sf-imp-doomed')));
    await tester.pumpAndSettle();
    final s = (await c.read(charactersProvider.future)).single.starforged!;
    expect(s.impacts, {'doomed'});
    expect(s.momentumMax, 9);
  });

  testWidgets('create flow offers Starforged and makes a premade SF character',
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
    await tester.tap(find.byKey(const Key('new-starforged')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('starforged-sheet')), findsOneWidget);
    final chars = await c.read(charactersProvider.future);
    expect(chars.single.starforged!.edge, 3);
  });

  testWidgets('SF add a vow and a connection, then mark progress',
      (tester) async {
    final c = await pumpStarforged(tester);
    await tester.tap(find.text('Nova'));
    await tester.pumpAndSettle();
    // Vow — drag first so the lazy ListView builds items below the fold.
    await tester.drag(
        find.byKey(const Key('starforged-sheet')), const Offset(0, -800));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('sf-add-vow')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sf-add-vow')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('vow-name')), 'Reach the Forge');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('sf-vow-0-mark')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sf-vow-0-mark')));
    await tester.pumpAndSettle();
    expect(
        (await c.read(charactersProvider.future))
            .single
            .starforged!
            .vows
            .single
            .ticks,
        8);
    // Connection
    await tester.ensureVisible(find.byKey(const Key('sf-add-conn')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sf-add-conn')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('conn-name')), 'Lara');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    final sf = (await c.read(charactersProvider.future)).single.starforged!;
    expect(sf.connections.single.name, 'Lara');
  });

  testWidgets('SF pick an asset and toggle an ability', (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1",'
              '"systems":["ironsworn"]}]}',
      'juice.rulesets.v1': '["starforged"]',
      'juice.characters.v1.default':
          '[{"id":"sf","name":"Nova","note":"","stats":[],"tracks":[],'
              '"tags":[],"starforged":{"edge":3,"heart":2,"iron":2,"shadow":1,'
              '"wits":1,"health":5,"spirit":5,"supply":5,"momentum":2,'
              '"xpEarned":0,"xpSpent":0,"questsLegacy":0,"bondsLegacy":0,'
              '"discoveriesLegacy":0}}]',
    });
    final fixture = {
      'asset_collections': [
        {
          'name': 'Path',
          'assets': [
            {
              'id': 'starforged/assets/path/ace',
              'name': 'Ace',
              'category': 'Path',
              'abilities': [
                {'text': 'Reroll a die', 'enabled': true},
                {'text': 'Push your luck', 'enabled': false},
              ],
            },
          ],
        },
      ],
    };
    final c = ProviderContainer(overrides: [
      rulesetDataProvider('starforged').overrideWith((ref) async => fixture),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CharactersPane()))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nova'));
    await tester.pumpAndSettle();
    // Assets section is deep in the sheet (after vows/connections); pre-scroll
    // so the lazy ListView builds the widget before ensureVisible.
    await tester.drag(
        find.byKey(const Key('starforged-sheet')), const Offset(0, -1200));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('sf-add-asset')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sf-add-asset')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const Key('pick-asset-starforged/assets/path/ace')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ace'), findsOneWidget);
    var asset = (await c.read(charactersProvider.future))
        .single
        .starforged!
        .assets
        .single;
    expect(asset.enabledAbilities, [true, false]);
    await tester.ensureVisible(find.byKey(const Key('sf-asset-0-ability-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sf-asset-0-ability-1')));
    await tester.pumpAndSettle();
    asset = (await c.read(charactersProvider.future))
        .single
        .starforged!
        .assets
        .single;
    expect(asset.enabledAbilities, [true, true]);
  });

  Future<ProviderContainer> pumpDnd(WidgetTester tester,
      {String dnd = '{"abilities":{"str":15,"dex":13,"con":14,"int":8,"wis":12,'
          '"cha":10},"className":"Fighter","level":1,"ac":16,"currentHp":12,'
          '"maxHp":12,"hitDiceRemaining":1,"speed":30,'
          '"saveProficiencies":["str","con"],'
          '"skillProficiencies":["athletics","perception"]}'}) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1",'
              '"systems":["dnd"]}]}',
      'juice.characters.v1.default':
          '[{"id":"dd","name":"Tarin","note":"","stats":[],"tracks":[],'
              '"tags":[],"dnd":$dnd}]',
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CharactersPane()))));
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
        tester.element(find.byType(CharactersPane)));
  }

  testWidgets('opening a D&D character shows the bespoke sheet',
      (tester) async {
    await pumpDnd(tester);
    await tester.tap(find.text('Tarin'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dnd-sheet')), findsOneWidget);
    expect(find.byKey(const Key('dnd-ability-str-plus')), findsOneWidget);
    expect(find.text('Saving Throws'), findsOneWidget);
  });

  testWidgets('ability stepper updates the modifier and persists',
      (tester) async {
    final c = await pumpDnd(tester);
    await tester.tap(find.text('Tarin'));
    await tester.pumpAndSettle();
    // STR 15 (+2). Bump to 16 (+3).
    await tester.tap(find.byKey(const Key('dnd-ability-str-plus')));
    await tester.pumpAndSettle();
    expect(
        (await c.read(charactersProvider.future)).single.dnd!.score('str'), 16);
    expect(find.text('+3'), findsWidgets); // STR mod now +3
  });

  testWidgets('save proficiency toggle changes the shown save bonus',
      (tester) async {
    final c = await pumpDnd(tester);
    await tester.tap(find.text('Tarin'));
    await tester.pumpAndSettle();
    await tester.drag(
        find.byKey(const Key('dnd-sheet')), const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('dnd-save-dex')));
    await tester.pumpAndSettle();
    // DEX save starts +1 (mod only). Toggle proficiency -> +3 (mod +1 + prof +2).
    await tester.tap(find.byKey(const Key('dnd-save-dex')));
    await tester.pumpAndSettle();
    expect(
        (await c.read(charactersProvider.future))
            .single
            .dnd!
            .saveProficiencies
            .contains('dex'),
        isTrue);
  });

  testWidgets('create flow makes a premade D&D character', (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1",'
              '"systems":["dnd"]}]}',
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
    await tester.tap(find.byKey(const Key('new-dnd')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dnd-sheet')), findsOneWidget);
    expect((await c.read(charactersProvider.future)).single.dnd!.className,
        'Fighter');
  });

  testWidgets('skill proficiency + expertise change the skill bonus',
      (tester) async {
    final c = await pumpDnd(tester);
    await tester.tap(find.text('Tarin'));
    await tester.pumpAndSettle();
    // Stealth (DEX +1), not proficient. Scroll the lazy list until built.
    await tester.scrollUntilVisible(
        find.byKey(const Key('dnd-skill-stealth-prof')), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dnd-skill-stealth-prof')));
    await tester.pumpAndSettle();
    var sheet = (await c.read(charactersProvider.future)).single.dnd!;
    expect(sheet.skillProficiencies.contains('stealth'), isTrue);
    expect(sheet.skillBonus('stealth'), 3); // dex +1 + prof +2
    // Expertise doubles proficiency.
    await tester.tap(find.byKey(const Key('dnd-skill-stealth-exp')));
    await tester.pumpAndSettle();
    sheet = (await c.read(charactersProvider.future)).single.dnd!;
    expect(sheet.skillExpertise.contains('stealth'), isTrue);
    expect(sheet.skillBonus('stealth'), 5); // dex +1 + prof*2 (+4)
  });

  testWidgets('condition toggle and exhaustion stepper persist',
      (tester) async {
    final c = await pumpDnd(tester);
    await tester.tap(find.text('Tarin'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.byKey(const Key('dnd-cond-poisoned')), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dnd-cond-poisoned')));
    await tester.pumpAndSettle();
    expect(
        (await c.read(charactersProvider.future))
            .single
            .dnd!
            .conditions
            .contains('poisoned'),
        isTrue);
    await tester.tap(find.byKey(const Key('dnd-exhaustion-plus')));
    await tester.pumpAndSettle();
    expect(
        (await c.read(charactersProvider.future)).single.dnd!.exhaustionLevel,
        1);
  });

  testWidgets('create flow makes a Sundered Isles character with SI label',
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
    await tester.tap(find.byKey(const Key('new-sundered')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('starforged-sheet')), findsOneWidget);
    expect(find.text('Sundered Isles'), findsOneWidget);
    final chars = await c.read(charactersProvider.future);
    expect(chars.single.starforged!.assetRuleset, 'sundered_isles');
  });

  Future<ProviderContainer> pumpShadowdark(WidgetTester tester,
      {String sd = '{"abilities":{"str":13,"dex":12,"con":14,"int":8,"wis":10,'
          '"cha":10},"className":"Fighter","ancestry":"Human",'
          '"alignment":"Neutral","level":1,"ac":13,"currentHp":8,"maxHp":8}'}) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1",'
              '"systems":["shadowdark"]}]}',
      'juice.characters.v1.default':
          '[{"id":"sd","name":"Mort","note":"","stats":[],"tracks":[],'
              '"tags":[],"shadowdark":$sd}]',
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CharactersPane()))));
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
        tester.element(find.byType(CharactersPane)));
  }

  testWidgets('opening a Shadowdark character shows the bespoke sheet',
      (tester) async {
    await pumpShadowdark(tester);
    await tester.tap(find.text('Mort'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shadowdark-sheet')), findsOneWidget);
    expect(find.text('STR'), findsOneWidget);
    expect(find.textContaining('Gear'), findsWidgets);
  });

  testWidgets('SD ability stepper + luck toggle persist', (tester) async {
    final c = await pumpShadowdark(tester);
    await tester.tap(find.text('Mort'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sd-ability-str-plus')));
    await tester.pumpAndSettle();
    expect(
        (await c.read(charactersProvider.future))
            .single
            .shadowdark!
            .score('str'),
        14);
    await tester.scrollUntilVisible(find.byKey(const Key('sd-luck')), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sd-luck')));
    await tester.pumpAndSettle();
    expect(
        (await c.read(charactersProvider.future)).single.shadowdark!.luckToken,
        isTrue);
  });

  testWidgets('Wizard shows Spells section; Fighter does not', (tester) async {
    await pumpShadowdark(tester,
        sd: '{"abilities":{"str":8,"dex":12,"con":10,"int":16,"wis":10,'
            '"cha":10},"className":"Wizard","ancestry":"Elf",'
            '"alignment":"Neutral","level":1,"ac":11,"currentHp":4,"maxHp":4}');
    await tester.tap(find.text('Mort'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('sd-spells')), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const Key('sd-spells')), findsOneWidget);
  });

  testWidgets('create flow makes a premade Shadowdark character',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1",'
              '"systems":["shadowdark"]}]}',
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
    await tester.tap(find.byKey(const Key('new-shadowdark')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shadowdark-sheet')), findsOneWidget);
    expect(
        (await c.read(charactersProvider.future)).single.shadowdark!.className,
        'Fighter');
  });

  testWidgets('Shadowdark Combat/HP rows do not overflow at 360px width',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // Stress: a Priest (caster + deity field), 4-digit XP, 2-digit AC/HP.
    await pumpShadowdark(tester,
        sd: '{"abilities":{"str":15,"dex":12,"con":14,"int":8,"wis":16,'
            '"cha":10},"className":"Priest","ancestry":"Dwarf",'
            '"alignment":"Lawful","level":10,"xp":1234,"ac":18,'
            '"currentHp":88,"maxHp":88}');
    await tester.tap(find.text('Mort'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shadowdark-sheet')), findsOneWidget);
    // Scroll through the sheet so every fixed-width row lays out; a RenderFlex
    // overflow would throw during the scroll.
    await tester.scrollUntilVisible(find.byKey(const Key('sd-luck')), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('D&D Combat rows do not overflow at 360px width', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // High-level fixture: 3-digit HP and a long hit-dice label stress the
    // Combat HP + hit-dice rows hardest.
    await pumpDnd(tester,
        dnd: '{"abilities":{"str":15,"dex":13,"con":14,"int":8,"wis":12,'
            '"cha":10},"className":"Fighter","level":20,"ac":18,'
            '"currentHp":188,"maxHp":188,"hitDiceRemaining":20,"speed":30,'
            '"saveProficiencies":["str","con"],'
            '"skillProficiencies":["athletics","perception"]}');
    await tester.tap(find.text('Tarin'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dnd-sheet')), findsOneWidget);
    // Scroll the whole sheet so the lazy ListView builds (and lays out) every
    // fixed-width row — AC/HP/hit-dice near the top and the death-saves row
    // below the fold. Any RenderFlex overflow is captured during the scroll.
    await tester.scrollUntilVisible(
        find.byKey(const Key('dnd-death-ok-plus')), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Ironsworn XP row does not overflow at 360px width',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpIronsworn(tester,
        iron: '{"edge":3,"heart":2,"iron":2,"shadow":1,"wits":1,"health":5,'
            '"spirit":5,"supply":5,"momentum":2,"xpEarned":30,"xpSpent":28,'
            '"bonds":0}');
    await tester.tap(find.text('Ulla'));
    await tester.pumpAndSettle();
    // The XP row lives in the Experience & Bonds section below the fold; scroll
    // it into view so the lazy ListView lays it out.
    await tester.scrollUntilVisible(
        find.byKey(const Key('iw-xpEarned-plus')), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  String wizardDnd({int level = 5}) =>
      '{"abilities":{"str":8,"dex":14,"con":12,"int":16,"wis":10,"cha":10},'
      '"className":"Wizard","level":$level,"ac":12,"currentHp":20,"maxHp":20,'
      '"hitDiceRemaining":$level,"speed":30}';

  testWidgets('caster sheet shows Spellcasting with derived DC + slot stepper',
      (tester) async {
    final c = await pumpDnd(tester, dnd: wizardDnd());
    await tester.tap(find.text('Tarin'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.byKey(const Key('dnd-slot-1-plus')), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.text('Spellcasting'), findsOneWidget);
    expect(find.textContaining('DC 14'), findsOneWidget); // 8 + prof3 + int+3
    // Expend a level-1 slot.
    await tester.tap(find.byKey(const Key('dnd-slot-1-plus')));
    await tester.pumpAndSettle();
    expect(
        (await c.read(charactersProvider.future)).single.dnd!.spellSlotsUsed[0],
        1);
  });

  testWidgets('Warlock shows a Pact Magic row', (tester) async {
    await pumpDnd(tester,
        dnd: '{"abilities":{"str":10,"dex":14,"con":12,"int":10,"wis":10,'
            '"cha":16},"className":"Warlock","level":5,"ac":12,"currentHp":20,'
            '"maxHp":20,"hitDiceRemaining":5,"speed":30}');
    await tester.tap(find.text('Tarin'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('dnd-pact-plus')), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Pact'), findsOneWidget);
  });

  testWidgets('non-caster (Fighter) shows no Spellcasting section',
      (tester) async {
    await pumpDnd(tester); // premade Fighter
    await tester.tap(find.text('Tarin'));
    await tester.pumpAndSettle();
    expect(find.text('Spellcasting'), findsNothing);
  });

  testWidgets('Sundered Isles picker lists SI assets', (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1",'
              '"systems":["ironsworn"]}]}',
      'juice.rulesets.v1': '["starforged","sundered_isles"]',
      'juice.characters.v1.default':
          '[{"id":"si","name":"Mara","note":"","stats":[],"tracks":[],'
              '"tags":[],"starforged":{"edge":3,"heart":2,"iron":2,"shadow":1,'
              '"wits":1,"health":5,"spirit":5,"supply":5,"momentum":2,'
              '"xpEarned":0,"xpSpent":0,"questsLegacy":0,"bondsLegacy":0,'
              '"discoveriesLegacy":0,"assetRuleset":"sundered_isles"}}]',
    });
    final fixture = {
      'asset_collections': [
        {
          'name': 'Path',
          'assets': [
            {
              'id': 'asset:sundered_isles/path/corsair',
              'name': 'Corsair',
              'category': 'Path',
              'abilities': [
                {'text': 'Sail hard', 'enabled': true},
              ],
            },
          ],
        },
      ],
    };
    final c = ProviderContainer(overrides: [
      rulesetDataProvider('sundered_isles')
          .overrideWith((ref) async => fixture),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: CharactersPane()))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mara'));
    await tester.pumpAndSettle();
    expect(find.text('Sundered Isles'), findsOneWidget);
    await tester.drag(
        find.byKey(const Key('starforged-sheet')), const Offset(0, -1200));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('sf-add-asset')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sf-add-asset')));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const Key('pick-asset-asset:sundered_isles/path/corsair')),
        findsOneWidget);
  });

  testWidgets(
      'sheet picker hides Ironsworn family when ironsworn system is off',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1",'
              '"systems":["dnd"]}]}',
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
    // ironsworn system is off, so the Ironsworn-family options are hidden.
    expect(find.byKey(const Key('new-ironsworn')), findsNothing);
    expect(find.byKey(const Key('new-starforged')), findsNothing);
    expect(find.byKey(const Key('new-sundered')), findsNothing);
    // Generic + the enabled D&D option remain.
    expect(find.byKey(const Key('new-generic')), findsOneWidget);
    expect(find.byKey(const Key('new-dnd')), findsOneWidget);
  });

  testWidgets('sheet picker hints how to enable D&D/Shadowdark when off',
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
    expect(find.textContaining('Edit systems'), findsOneWidget);
  });

  testWidgets('sheet picker omits the hint when D&D and Shadowdark are on',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1",'
              '"systems":["dnd","shadowdark"]}]}',
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
    expect(find.textContaining('Edit systems'), findsNothing);
    expect(find.byKey(const Key('new-dnd')), findsOneWidget);
    expect(find.byKey(const Key('new-shadowdark')), findsOneWidget);
  });
}
