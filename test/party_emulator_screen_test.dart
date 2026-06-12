import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/emulator_data.dart';
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

  // Dice(Random(seed)) dN(6) sequences used below:
  //   seed 7 -> 5, 6, 3…   seed 9 -> 2, 3…   seed 5 -> 5, 1…
  //   seed 2 -> 4, 4, 5…   seed 10 -> 2, 2…  seed 0 -> 4, 6, 5, 2…
  Future<ProviderContainer> pump(WidgetTester tester,
      {required int seed}) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.characters.v1.default': seededChar,
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
}
