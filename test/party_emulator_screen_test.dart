import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/emulator_data.dart';
import 'package:juice_oracle/engine/party_emulator.dart';
import 'package:juice_oracle/features/party_emulator_screen.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final data = EmulatorData(
      jsonDecode(File('assets/emulator_data.json').readAsStringSync())
          as Map<String, dynamic>);

  const seededChar =
      '[{"id":"c1","name":"Ash","note":"","stats":[],"tracks":[],"tags":["brave","curious"]}]';

  /// Ash with a seeded emulation block (PET tests).
  String charsWith(
          {int? agendaKey,
          int? focusKey,
          int tokens = 0,
          List<String> usedTags = const []}) =>
      jsonEncode([
        {
          'id': 'c1',
          'name': 'Ash',
          'note': '',
          'stats': [],
          'tracks': [],
          'tags': ['brave', 'curious'],
          'emulation': {
            if (agendaKey != null) 'agendaKey': agendaKey,
            if (focusKey != null) 'focusKey': focusKey,
            'tokens': tokens,
            'prominentTags': [],
            'usedTags': usedTags,
          },
        }
      ]);

  // Dice(Random(seed)) dN(6) sequences used below:
  //   seed 7 -> 5, 6, 3…   seed 9 -> 2, 3…   seed 5 -> 5, 1…
  //   seed 2 -> 4, 4, 5…   seed 10 -> 2, 2…  seed 0 -> 4, 6, 5, 2…
  Future<ProviderContainer> pump(WidgetTester tester,
      {required int seed, String chars = seededChar}) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.characters.v1.default': chars,
    });
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: [emulatorDataProvider.overrideWith((ref) async => data)],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: PartyEmulatorScreen(dice: Dice(Random(seed)))),
      ),
    ));
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
        tester.element(find.byType(PartyEmulatorScreen)));
  }

  Future<void> pickAsh(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('pe-character')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ash').last);
    await tester.pumpAndSettle();
  }

  String fieldText(WidgetTester tester, String key) =>
      tester.widget<TextField>(find.byKey(Key(key))).controller!.text;

  String keyedText(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(Key(key))).data!;

  testWidgets('picker, course fields, roll buttons, and attribution render',
      (tester) async {
    await pump(tester, seed: 7);
    expect(find.byKey(const Key('pe-character')), findsOneWidget);
    expect(find.text('No one'), findsOneWidget);
    expect(find.byKey(const Key('pe-obvious')), findsOneWidget);
    expect(find.byKey(const Key('pe-option')), findsOneWidget);
    expect(find.byKey(const Key('pe-odd')), findsOneWidget);
    expect(find.text('Roll d6'), findsOneWidget);
    expect(find.text('Double-Down (2d6)'), findsOneWidget);
    expect(find.byKey(const Key('pe-group-mode')), findsOneWidget);
    expect(find.byKey(const Key('pe-assign')), findsNothing);
    expect(find.text('PET & Sidekick © Tam H (hedonic.ink), CC-BY 4.0'),
        findsOneWidget);
    expect(find.text('Triple-O © Cezar Capacle / Critical Kit, CC-BY-SA 4.0'),
        findsOneWidget);
  });

  testWidgets('single roll renders the band, die, and matching course text',
      (tester) async {
    await pump(tester, seed: 7); // first d6 = 5 -> The Obvious
    await tester.enterText(
        find.byKey(const Key('pe-obvious')), 'Charge the gate');
    await tester.enterText(find.byKey(const Key('pe-option')), 'Parley');
    await tester.enterText(find.byKey(const Key('pe-odd')), 'Sing');
    await tester.tap(find.byKey(const Key('pe-roll')));
    await tester.pumpAndSettle();
    expect(keyedText(tester, 'pe-result-band'), 'The Obvious');
    expect(keyedText(tester, 'pe-result-roll'), 'Roll: 5');
    expect(keyedText(tester, 'pe-result-course'), 'Charge the gate');
  });

  testWidgets('rolling into a blank course shows the undefined hint',
      (tester) async {
    await pump(tester, seed: 9); // first d6 = 2 -> The Option (left blank)
    await tester.enterText(
        find.byKey(const Key('pe-obvious')), 'Hold the line');
    await tester.tap(find.byKey(const Key('pe-roll')));
    await tester.pumpAndSettle();
    expect(keyedText(tester, 'pe-result-band'), 'The Option');
    expect(
        keyedText(tester, 'pe-result-course'), '(undefined — make it up now)');
  });

  testWidgets('double-down keep flow resolves the band from the kept die',
      (tester) async {
    await pump(tester, seed: 5); // rolls 5 & 1
    await tester.enterText(find.byKey(const Key('pe-obvious')), 'Attack');
    await tester.tap(find.byKey(const Key('pe-double-down')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pe-result-band')), findsNothing);
    expect(find.byKey(const Key('pe-log')), findsNothing);
    expect(find.text('Keep 5'), findsOneWidget);
    expect(find.text('Keep 1'), findsOneWidget);
    await tester.tap(find.byKey(const Key('pe-keep-1')));
    await tester.pumpAndSettle();
    expect(keyedText(tester, 'pe-result-band'), 'The Odd');
    expect(keyedText(tester, 'pe-result-roll'), 'Rolls: 5 & 1 — kept 1');
    expect(find.byKey(const Key('pe-doubles')), findsNothing);
  });

  testWidgets('doubles: mark trait prominent writes emulation.prominentTags',
      (tester) async {
    final container = await pump(tester, seed: 2); // rolls 4 & 4
    await pickAsh(tester);
    await tester.enterText(find.byKey(const Key('pe-obvious')), 'Smash');
    await tester.tap(find.byKey(const Key('pe-double-down')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pe-doubles')), findsNothing,
        reason: 'banner only after the favorite die is kept');
    await tester.tap(find.byKey(const Key('pe-keep-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pe-doubles')), findsOneWidget);
    expect(find.text('Doubles — this behavior grows'), findsOneWidget);
    await tester.tap(find.text('Mark trait prominent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('brave').last);
    await tester.pumpAndSettle();
    final chars = await container.read(charactersProvider.future);
    expect(chars.single.emulation!.prominentTags, ['brave']);
    expect(chars.single.tags, ['brave', 'curious']);
  });

  testWidgets('doubles: add new trait appends to the character tags',
      (tester) async {
    final container = await pump(tester, seed: 10); // rolls 2 & 2
    await pickAsh(tester);
    await tester.tap(find.byKey(const Key('pe-double-down')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pe-keep-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add new trait'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('pe-trait-input')), 'reckless');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    final chars = await container.read(charactersProvider.future);
    expect(chars.single.tags, ['brave', 'curious', 'reckless']);
  });

  testWidgets('doubles with no character selected: banner text only',
      (tester) async {
    await pump(tester, seed: 2); // rolls 4 & 4
    await tester.tap(find.byKey(const Key('pe-double-down')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pe-keep-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pe-doubles')), findsOneWidget);
    expect(find.text('Mark trait prominent'), findsNothing);
    expect(find.text('Add new trait'), findsNothing);
  });

  testWidgets('group mode: assign by dice reorders the courses, then checks',
      (tester) async {
    await pump(tester, seed: 0); // d6s 4, 6, 5 then 2
    await tester.tap(find.byKey(const Key('pe-group-mode')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('pe-obvious')), 'A');
    await tester.enterText(find.byKey(const Key('pe-option')), 'B');
    await tester.enterText(find.byKey(const Key('pe-odd')), 'C');
    await tester.tap(find.byKey(const Key('pe-assign')));
    await tester.pumpAndSettle();
    expect(fieldText(tester, 'pe-obvious'), 'B'); // course 2 rolled 6
    expect(fieldText(tester, 'pe-option'), 'C'); // course 3 rolled 5
    expect(fieldText(tester, 'pe-odd'), 'A'); // course 1 rolled 4
    expect(keyedText(tester, 'pe-assign-dice'), 'Assigned by dice: 6 · 5 · 4');
    await tester.tap(find.byKey(const Key('pe-roll'))); // next d6 = 2
    await tester.pumpAndSettle();
    expect(keyedText(tester, 'pe-result-band'), 'The Option');
    expect(keyedText(tester, 'pe-result-course'), 'C');
  });

  testWidgets('journal entry carries band title, character, courses, rolls',
      (tester) async {
    final container = await pump(tester, seed: 2); // rolls 4 & 4
    await pickAsh(tester);
    await tester.enterText(find.byKey(const Key('pe-obvious')), 'Smash');
    await tester.enterText(find.byKey(const Key('pe-option')), 'Sneak');
    await tester.tap(find.byKey(const Key('pe-double-down')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pe-keep-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pe-log')));
    await tester.pumpAndSettle();
    final entries = container.read(journalProvider).valueOrNull ?? [];
    expect(entries, hasLength(1));
    expect(entries.single.title, 'Triple-O — The Obvious');
    final body = entries.single.body;
    expect(body, contains('Character: Ash'));
    expect(body, contains('The Obvious: Smash'));
    expect(body, contains('The Option: Sneak'));
    expect(body, contains('The Odd: (undefined — make it up now)'));
    expect(body, contains('Rolls: 4 & 4 — kept 4'));
    expect(body, contains('Doubles — this behavior grows into a Trait.'));
  });

  // -- PET (phase 3) ---------------------------------------------------------

  /// The ACT lines the screen renders for one [ActResult].
  List<String> actLines(ActResult r) {
    final a = data.agendaEntry(r.agendaKey);
    return [
      'Agenda: ${a.name}',
      'Ask: ${a.ask}${r.heads ? '' : ' (inverted)'}',
      'Modifier: ${actModeLabel(r.modifier)}',
      'Rolls: agenda ${r.agendaKey} · coin ${r.heads ? 'heads' : 'tails'}'
          ' · modifier ${r.modifierDie}',
    ];
  }

  testWidgets('emulation panel: placeholders, then Roll Agenda persists',
      (tester) async {
    final container = await pump(tester, seed: 7);
    expect(find.byKey(const Key('pe-emulation')), findsOneWidget);
    expect(find.byKey(const Key('pe-pet-actions')), findsOneWidget);
    expect(keyedText(tester, 'pe-agenda-line'), 'Agenda: —');
    expect(keyedText(tester, 'pe-focus-line'), 'Focus: —');
    expect(keyedText(tester, 'pe-tokens'), 'Tokens: 0');
    await pickAsh(tester);
    final key = roll2d6Key(Dice(Random(7))); // 5 + 6 = 11
    final a = data.agendaEntry(key);
    await tester.tap(find.byKey(const Key('pe-roll-agenda')));
    await tester.pumpAndSettle();
    expect(keyedText(tester, 'pe-agenda-line'),
        'Agenda: ${a.name} — Ask: ${a.ask}');
    final chars = await container.read(charactersProvider.future);
    expect(chars.single.emulation!.agendaKey, key);
  });

  testWidgets('Roll Focus persists the focus key and renders name + blurb',
      (tester) async {
    final container = await pump(tester, seed: 9);
    await pickAsh(tester);
    final key = roll2d6Key(Dice(Random(9))); // 2 + 3 = 5
    final f = data.focusEntry(key);
    await tester.tap(find.byKey(const Key('pe-roll-focus')));
    await tester.pumpAndSettle();
    expect(keyedText(tester, 'pe-focus-line'), 'Focus: ${f.name} — ${f.blurb}');
    final chars = await container.read(charactersProvider.future);
    expect(chars.single.emulation!.focusKey, key);
  });

  testWidgets('token stepper: plus increments, minus clamps at 0, persists',
      (tester) async {
    final container = await pump(tester, seed: 7);
    await pickAsh(tester);
    await tester.tap(find.byKey(const Key('pe-token-minus')));
    await tester.pumpAndSettle();
    expect(keyedText(tester, 'pe-tokens'), 'Tokens: 0', reason: 'clamps at 0');
    await tester.tap(find.byKey(const Key('pe-token-plus')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pe-token-plus')));
    await tester.pumpAndSettle();
    expect(keyedText(tester, 'pe-tokens'), 'Tokens: 2');
    await tester.tap(find.byKey(const Key('pe-token-minus')));
    await tester.pumpAndSettle();
    expect(keyedText(tester, 'pe-tokens'), 'Tokens: 1');
    final chars = await container.read(charactersProvider.future);
    expect(chars.single.emulation!.tokens, 1);
  });

  testWidgets('ACT on the current agenda grants +1 token and notes the match',
      (tester) async {
    final expected = rollAct(Dice(Random(2)));
    final container = await pump(tester,
        seed: 2, chars: charsWith(agendaKey: expected.agendaKey));
    await pickAsh(tester);
    await tester.tap(find.byKey(const Key('pe-act')));
    await tester.pumpAndSettle();
    final lines = keyedText(tester, 'pe-pet-lines');
    for (final line in actLines(expected)) {
      expect(lines, contains(line));
    }
    expect(lines, contains('Agenda match — +1 token'));
    final chars = await container.read(charactersProvider.future);
    expect(chars.single.emulation!.tokens, 1);
    expect(chars.single.emulation!.agendaKey, expected.agendaKey);
  });

  testWidgets('ACT on a different agenda grants no token, keeps the agenda',
      (tester) async {
    final expected = rollAct(Dice(Random(2)));
    final other = expected.agendaKey == 2 ? 3 : expected.agendaKey - 1;
    final container =
        await pump(tester, seed: 2, chars: charsWith(agendaKey: other));
    await pickAsh(tester);
    await tester.tap(find.byKey(const Key('pe-act')));
    await tester.pumpAndSettle();
    final lines = keyedText(tester, 'pe-pet-lines');
    expect(lines, isNot(contains('Agenda match')));
    final chars = await container.read(charactersProvider.future);
    expect(chars.single.emulation!.tokens, 0);
    expect(chars.single.emulation!.agendaKey, other);
  });

  testWidgets('ACT with no agenda set adopts the rolled agenda, no token',
      (tester) async {
    final expected = rollAct(Dice(Random(5)));
    final a = data.agendaEntry(expected.agendaKey);
    final container = await pump(tester, seed: 5);
    await pickAsh(tester);
    await tester.tap(find.byKey(const Key('pe-act')));
    await tester.pumpAndSettle();
    expect(keyedText(tester, 'pe-pet-title'),
        'ACT — ${a.name} (${expected.heads ? 'as written' : 'inverted'})');
    expect(
        keyedText(tester, 'pe-pet-lines'), contains('Agenda set to ${a.name}'));
    final chars = await container.read(charactersProvider.future);
    expect(chars.single.emulation!.agendaKey, expected.agendaKey);
    expect(chars.single.emulation!.tokens, 0);
  });

  testWidgets('REFOCUS persists the new focus and shows name + blurb',
      (tester) async {
    final key = roll2d6Key(Dice(Random(5))); // 5 + 1 = 6
    final f = data.focusEntry(key);
    final container = await pump(tester, seed: 5);
    await pickAsh(tester);
    await tester.tap(find.byKey(const Key('pe-refocus')));
    await tester.pumpAndSettle();
    expect(keyedText(tester, 'pe-pet-title'), 'REFOCUS — ${f.name}');
    expect(keyedText(tester, 'pe-pet-lines'), 'Focus: ${f.name} — ${f.blurb}');
    final chars = await container.read(charactersProvider.future);
    expect(chars.single.emulation!.focusKey, key);
  });

  testWidgets('tag spend: picker lists unspent only, two readings, marks used',
      (tester) async {
    final probe = Dice(Random(0));
    final first = rollAct(probe);
    final second = rollAct(probe);
    final container = await pump(tester,
        seed: 0, chars: charsWith(usedTags: const ['brave']));
    await pickAsh(tester);
    await tester.tap(find.byKey(const Key('pe-tag-spend')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(SimpleDialogOption, 'curious'), findsOneWidget);
    expect(find.widgetWithText(SimpleDialogOption, 'brave'), findsNothing);
    await tester.tap(find.widgetWithText(SimpleDialogOption, 'curious'));
    await tester.pumpAndSettle();
    expect(keyedText(tester, 'pe-pet-title'), 'Tag spend — curious');
    final lines = keyedText(tester, 'pe-pet-lines');
    expect(lines, contains('Spent: curious'));
    expect(lines, contains('Reading 1'));
    expect(lines, contains('Reading 2'));
    for (final line in [...actLines(first), ...actLines(second)]) {
      expect(lines, contains(line));
    }
    final chars = await container.read(charactersProvider.future);
    expect(chars.single.emulation!.usedTags, ['brave', 'curious']);
    expect(chars.single.emulation!.tokens, 0,
        reason: 'no agenda-match token on tag-spend rolls');
    expect(chars.single.emulation!.agendaKey, isNull,
        reason: 'tag-spend readings never adopt an agenda');
  });

  testWidgets('tag spend is disabled once every tag is spent', (tester) async {
    await pump(tester,
        seed: 0, chars: charsWith(usedTags: const ['brave', 'curious']));
    await pickAsh(tester);
    final button =
        tester.widget<OutlinedButton>(find.byKey(const Key('pe-tag-spend')));
    expect(button.onPressed, isNull);
  });

  testWidgets('session start: new focus + real-life line, clears used tags',
      (tester) async {
    final probe = Dice(Random(7));
    final key = roll2d6Key(probe); // 5 + 6 = 11
    final life = data.realLife[probe.dN(6) - 1]; // d6 = 3
    final f = data.focusEntry(key);
    final container = await pump(tester,
        seed: 7, chars: charsWith(usedTags: const ['brave', 'curious']));
    await pickAsh(tester);
    await tester.tap(find.byKey(const Key('pe-session-start')));
    await tester.pumpAndSettle();
    expect(keyedText(tester, 'pe-pet-title'), 'Session start');
    final lines = keyedText(tester, 'pe-pet-lines');
    expect(lines, contains('Focus: ${f.name} — ${f.blurb}'));
    expect(lines, contains('Real life: $life'));
    final chars = await container.read(charactersProvider.future);
    expect(chars.single.emulation!.focusKey, key);
    expect(chars.single.emulation!.usedTags, isEmpty);
  });

  // Lost-update regression (live-browser repro): a token-plus press after
  // session start used to read-modify-write the BUILD-captured emulation
  // snapshot, resurrecting the pre-session-start focus/usedTags. Two tests:
  // the settled sequence (guards the common path; passed even pre-fix once a
  // rebuild refreshed `selected`) and the same-frame double press (no rebuild
  // between the presses — this one reproduced the clobber pre-fix).
  testWidgets('session start then token-plus (settled): no lost update',
      (tester) async {
    final key = roll2d6Key(Dice(Random(7))); // 5 + 6 = 11
    final container = await pump(tester,
        seed: 7, chars: charsWith(focusKey: 4, usedTags: const ['brave']));
    await pickAsh(tester);
    await tester.tap(find.byKey(const Key('pe-session-start')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pe-token-plus')));
    await tester.pumpAndSettle();
    final e =
        (await container.read(charactersProvider.future)).single.emulation!;
    expect(e.tokens, 1);
    expect(e.usedTags, isEmpty,
        reason: 'token-plus must not resurrect spent tags');
    expect(e.focusKey, key,
        reason: 'token-plus must not clobber the session-start focus');
  });

  testWidgets('session start + token-plus in one frame: no lost update',
      (tester) async {
    final key = roll2d6Key(Dice(Random(7))); // 5 + 6 = 11
    final container = await pump(tester,
        seed: 7, chars: charsWith(focusKey: 4, usedTags: const ['brave']));
    await pickAsh(tester);
    // No pump between the taps: the session-start write lands in the
    // provider, but the widget has not rebuilt, so the token handler still
    // holds the stale build-captured character.
    await tester.tap(find.byKey(const Key('pe-session-start')));
    await tester.tap(find.byKey(const Key('pe-token-plus')));
    await tester.pumpAndSettle();
    final e =
        (await container.read(charactersProvider.future)).single.emulation!;
    expect(e.tokens, 1);
    expect(e.usedTags, isEmpty,
        reason: 'token-plus must not resurrect spent tags');
    expect(e.focusKey, key,
        reason: 'token-plus must not clobber the session-start focus');
  });

  testWidgets('consequence rolls a d6 GM move without persisting',
      (tester) async {
    final move = data.consequences[Dice(Random(9)).dN(6) - 1]; // d6 = 2
    final container = await pump(tester, seed: 9);
    await pickAsh(tester);
    await tester.tap(find.byKey(const Key('pe-consequence')));
    await tester.pumpAndSettle();
    expect(keyedText(tester, 'pe-pet-title'), 'Consequence');
    expect(keyedText(tester, 'pe-pet-lines'), 'Consequence: $move');
    final chars = await container.read(charactersProvider.future);
    expect(chars.single.emulation, isNull, reason: 'consequence never writes');
  });

  testWidgets('PET journal entries: ACT and tag-spend titles and bodies',
      (tester) async {
    final probe = Dice(Random(10));
    final act = rollAct(probe);
    final first = rollAct(probe);
    final second = rollAct(probe);
    final a = data.agendaEntry(act.agendaKey);
    final container = await pump(tester, seed: 10);
    await pickAsh(tester);
    await tester.tap(find.byKey(const Key('pe-act')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pe-pet-log')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pe-tag-spend')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SimpleDialogOption, 'brave'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pe-pet-log')));
    await tester.pumpAndSettle();
    final entries = container.read(journalProvider).valueOrNull ?? [];
    expect(entries, hasLength(2));
    // Newest first: the tag spend, then the ACT.
    expect(entries[1].title,
        'ACT — ${a.name} (${act.heads ? 'as written' : 'inverted'})');
    expect(entries[1].body, startsWith('Character: Ash'));
    for (final line in [...actLines(act), 'Agenda set to ${a.name}']) {
      expect(entries[1].body, contains(line));
    }
    expect(entries[0].title, 'Tag spend — brave');
    expect(entries[0].body, startsWith('Character: Ash'));
    for (final line in [
      'Spent: brave',
      'Reading 1',
      ...actLines(first),
      'Reading 2',
      ...actLines(second),
    ]) {
      expect(entries[0].body, contains(line));
    }
  });

  testWidgets('No one: transient emulation renders, provider untouched',
      (tester) async {
    final container = await pump(tester, seed: 0);
    final key = roll2d6Key(Dice(Random(0))); // 4 + 6 = 10
    final a = data.agendaEntry(key);
    await tester.tap(find.byKey(const Key('pe-roll-agenda')));
    await tester.pumpAndSettle();
    expect(keyedText(tester, 'pe-agenda-line'),
        'Agenda: ${a.name} — Ask: ${a.ask}');
    await tester.tap(find.byKey(const Key('pe-token-plus')));
    await tester.pumpAndSettle();
    expect(keyedText(tester, 'pe-tokens'), 'Tokens: 1');
    final button =
        tester.widget<OutlinedButton>(find.byKey(const Key('pe-tag-spend')));
    expect(button.onPressed, isNull, reason: 'No one has no tags to spend');
    final chars = await container.read(charactersProvider.future);
    expect(chars.single.emulation, isNull,
        reason: 'No one rolls never touch the roster');
    // Picking a character swaps the panel to their (empty) emulation.
    await pickAsh(tester);
    expect(keyedText(tester, 'pe-agenda-line'), 'Agenda: —');
    expect(keyedText(tester, 'pe-tokens'), 'Tokens: 0');
  });
}
