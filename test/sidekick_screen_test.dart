import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/emulator_data.dart';
import 'package:juice_oracle/engine/party_emulator.dart';
import 'package:juice_oracle/features/sidekick_screen.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/interpreter.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_interpreter.dart';

void main() {
  final data = EmulatorData(
      jsonDecode(File('assets/emulator_data.json').readAsStringSync())
          as Map<String, dynamic>);

  const seededChar =
      '[{"id":"c1","name":"Ash","note":"","stats":[],"tracks":[],"tags":["brave","curious"]}]';

  /// Ash with a seeded emulation block (mood / hexflower position).
  String charsWith({String? mood, int? hexIndex}) => jsonEncode([
        {
          'id': 'c1',
          'name': 'Ash',
          'note': '',
          'stats': [],
          'tracks': [],
          'tags': ['brave', 'curious'],
          'emulation': {
            if (mood != null) 'mood': mood,
            if (hexIndex != null) 'hexIndex': hexIndex,
            'tokens': 0,
            'prominentTags': [],
            'usedTags': [],
          },
        }
      ]);

  /// Mirrors the screen's mood label ('high_strung' → 'High strung').
  String label(String id) =>
      id[0].toUpperCase() + id.substring(1).replaceAll('_', ' ');

  Future<(FakeInterpreterService, ProviderContainer)> pump(
    WidgetTester tester, {
    required int seed,
    String chars = seededChar,
    InterpreterStatus? interp,
    String? journal,
    String? settings,
  }) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.characters.v1.default': chars,
      if (journal != null) 'juice.journal.v2.default': journal,
      if (settings != null) 'juice.settings.v1.default': settings,
    });
    final fake = FakeInterpreterService(
        initial: interp ?? const InterpreterStatus(InterpreterPhase.ready));
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        emulatorDataProvider.overrideWith((ref) async => data),
        interpreterServiceProvider.overrideWithValue(fake),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: SidekickScreen(dice: Dice(Random(seed)))),
      ),
    ));
    await tester.pumpAndSettle();
    final container =
        ProviderScope.containerOf(tester.element(find.byType(SidekickScreen)));
    return (fake, container);
  }

  Future<void> pickAsh(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('sd-character')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ash').last);
    await tester.pumpAndSettle();
  }

  Future<void> pickNoOne(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('sd-character')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No one').last);
    await tester.pumpAndSettle();
  }

  Future<void> openHexTab(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('sd-hex-tab')));
    await tester.pumpAndSettle();
  }

  String keyedText(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(Key(key))).data!;

  // -- Dialogue tab -----------------------------------------------------------

  testWidgets('non-doubles roll renders the line, chips, dice; mood kept',
      (tester) async {
    final r = rollDialogue(Dice(Random(7))); // rolls 5 & 6 — no doubles
    expect(r.moodChanged, isFalse, reason: 'seed sanity');
    final container = (await pump(tester, seed: 7)).$2;
    expect(find.byKey(const Key('sd-character')), findsOneWidget);
    expect(keyedText(tester, 'sd-mood'), 'Mood: Default');
    expect(find.text('PET & Sidekick © Tam H (hedonic.ink), CC-BY 4.0'),
        findsOneWidget);
    expect(find.text('Triple-O © Cezar Capacle / Critical Kit, CC-BY-SA 4.0'),
        findsOneWidget);
    await pickAsh(tester);
    await tester.tap(find.byKey(const Key('sd-roll')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sd-result')), findsOneWidget);
    expect(keyedText(tester, 'sd-result-line'),
        '"${data.dialogueLine('default', r.lineKey)}"');
    final lines = keyedText(tester, 'sd-result-lines');
    expect(lines, contains('Mood: Default'));
    expect(
        lines,
        contains('Tone: ${data.tones[r.toneIx]}'
            ' · Topic: ${data.topics[r.topicIx]}'));
    expect(
        lines,
        contains('Said: ${data.saidHowA[r.saidHowAIx]},'
            ' ${data.saidHowB[r.saidHowBIx]}'));
    expect(
        lines, contains('Rolls: ${r.dice.$1} & ${r.dice.$2} → ${r.lineKey}'));
    final chars = await container.read(charactersProvider.future);
    expect(chars.single.emulation?.mood, isNull,
        reason: 'no doubles — nothing persisted');
  });

  testWidgets('doubles persist the new mood first and reroll under it',
      (tester) async {
    final r = rollDialogue(Dice(Random(2))); // rolls 4 & 4 — doubles
    expect(r.moodChanged, isTrue, reason: 'seed sanity');
    final mood = r.newMood!;
    final container = (await pump(tester, seed: 2)).$2;
    await pickAsh(tester);
    await tester.tap(find.byKey(const Key('sd-roll')));
    await tester.pumpAndSettle();
    expect(keyedText(tester, 'sd-mood'), 'Mood: ${label(mood)}');
    expect(keyedText(tester, 'sd-result-line'),
        '"${data.dialogueLine(mood, r.lineKey)}"');
    final lines = keyedText(tester, 'sd-result-lines');
    expect(lines, contains('Mood changed → ${label(mood)}'));
    expect(
        lines,
        contains('Rolls: ${r.dice.$1} & ${r.dice.$2}'
            ' — doubles; reroll → ${r.lineKey}'));
    final chars = await container.read(charactersProvider.future);
    expect(chars.single.emulation!.mood, mood);
  });

  testWidgets('mood persists across character reselect; No one is transient',
      (tester) async {
    final r = rollDialogue(Dice(Random(2))); // doubles → mood change
    final mood = r.newMood!;
    await pump(tester, seed: 2);
    await pickAsh(tester);
    await tester.tap(find.byKey(const Key('sd-roll')));
    await tester.pumpAndSettle();
    expect(keyedText(tester, 'sd-mood'), 'Mood: ${label(mood)}');
    await pickNoOne(tester);
    expect(keyedText(tester, 'sd-mood'), 'Mood: Default',
        reason: 'No one keeps its own transient mood');
    await pickAsh(tester);
    expect(keyedText(tester, 'sd-mood'), 'Mood: ${label(mood)}');
  });

  testWidgets('No one: doubles change the transient mood, roster untouched',
      (tester) async {
    final r = rollDialogue(Dice(Random(10))); // rolls 2 & 2 — doubles
    expect(r.moodChanged, isTrue, reason: 'seed sanity');
    final container = (await pump(tester, seed: 10)).$2;
    await tester.tap(find.byKey(const Key('sd-roll')));
    await tester.pumpAndSettle();
    expect(keyedText(tester, 'sd-mood'), 'Mood: ${label(r.newMood!)}');
    final chars = await container.read(charactersProvider.future);
    expect(chars.single.emulation, isNull,
        reason: 'No one rolls never touch the roster');
  });

  testWidgets('seeded mood drives the line table', (tester) async {
    final r = rollDialogue(Dice(Random(7))); // no doubles
    await pump(tester, seed: 7, chars: charsWith(mood: 'savvy'));
    await pickAsh(tester);
    expect(keyedText(tester, 'sd-mood'), 'Mood: Savvy');
    await tester.tap(find.byKey(const Key('sd-roll')));
    await tester.pumpAndSettle();
    expect(keyedText(tester, 'sd-result-line'),
        '"${data.dialogueLine('savvy', r.lineKey)}"');
  });

  // -- Voice this -------------------------------------------------------------

  testWidgets('voice-this surfaces the line and seeds the interpreter',
      (tester) async {
    const recallJournal =
        '[{"id":"j2","timestamp":"2026-06-11T12:00:00.000","title":"Omen","body":"There is nothing in the vault.","kind":"result"},'
        '{"id":"j1","timestamp":"2026-06-11T11:00:00.000","title":"Weather","body":"Cold rain falls.","kind":"result"}]';
    final r = rollDialogue(Dice(Random(7))); // default mood, key 11
    final (fake, _) = await pump(tester,
        seed: 7,
        journal: recallJournal,
        settings: '{"genre":"grimdark fantasy","tone":"tense"}');
    fake.queuedVoice.add('Nothing in my pockets but lint and bad luck.');
    await pickAsh(tester);
    await tester.tap(find.byKey(const Key('sd-roll')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sd-voice')));
    await tester.pumpAndSettle();
    expect(keyedText(tester, 'sd-voice-line'),
        '"Nothing in my pockets but lint and bad luck."');
    final seed = fake.lastVoiceSeed!;
    expect(seed.line, data.dialogueLine('default', r.lineKey));
    expect(seed.mood, 'default');
    expect(seed.tone, data.tones[r.toneIx]);
    expect(seed.topic, data.topics[r.topicIx]);
    expect(seed.characterName, 'Ash');
    expect(seed.characterTags, ['brave', 'curious']);
    expect(seed.genre, 'grimdark fantasy');
    expect(seed.toneSetting, 'tense');
    // The related entry (shares 'nothing' with the rolled line) rides
    // along; the unrelated one does not.
    expect(seed.journalContext, ['Omen — There is nothing in the vault.']);
  });

  testWidgets('voice error shows inline text and a retry that recovers',
      (tester) async {
    final (fake, _) = await pump(tester, seed: 7);
    fake.voiceError = StateError('boom');
    await pickAsh(tester);
    await tester.tap(find.byKey(const Key('sd-roll')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sd-voice')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sd-voice-line')), findsNothing);
    expect(find.textContaining('boom'), findsOneWidget);
    fake.voiceError = null;
    fake.queuedVoice.add('Back on script.');
    await tester.tap(find.byKey(const Key('sd-voice-retry')));
    await tester.pumpAndSettle();
    expect(keyedText(tester, 'sd-voice-line'), '"Back on script."');
    expect(find.byKey(const Key('sd-voice-retry')), findsNothing);
  });

  testWidgets('voice button is disabled until the interpreter is ready',
      (tester) async {
    await pump(tester,
        seed: 7,
        interp: const InterpreterStatus(InterpreterPhase.needsDownload));
    await tester.tap(find.byKey(const Key('sd-roll')));
    await tester.pumpAndSettle();
    final button =
        tester.widget<OutlinedButton>(find.byKey(const Key('sd-voice')));
    expect(button.onPressed, isNull);
  });

  testWidgets('voice button is absent on an unsupported platform',
      (tester) async {
    await pump(tester,
        seed: 7, interp: const InterpreterStatus(InterpreterPhase.unsupported));
    await tester.tap(find.byKey(const Key('sd-roll')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sd-result')), findsOneWidget);
    expect(find.byKey(const Key('sd-voice')), findsNothing);
  });

  // -- Hexflower tab ----------------------------------------------------------

  testWidgets('hex step walks the flower, persists, and renders the readout',
      (tester) async {
    // Probe-replay of the documented step dice order: 2d6 direction, d3
    // priority.
    final probe = Dice(Random(11));
    final a = probe.dN(6), b = probe.dN(6);
    final priority = const ['me', 'you', 'us'][probe.dN(3) - 1];
    final direction = data.hexDirection(a + b);
    final to = data.hexStep(0, a + b)!; // center always has a neighbor
    final container = (await pump(tester, seed: 11)).$2;
    await pickAsh(tester);
    await openHexTab(tester);
    expect(find.byKey(const Key('sd-hex-canvas')), findsOneWidget);
    expect(keyedText(tester, 'sd-hex-readout'),
        'Topic: fact · Context: current events (red)');
    await tester.tap(find.byKey(const Key('sd-hex-step')));
    await tester.pumpAndSettle();
    final hex = data.hex(to);
    final context =
        hex.context == 'gray' ? 'history (gray)' : 'current events (red)';
    expect(keyedText(tester, 'sd-hex-readout'),
        'Topic: ${hex.topic} · Context: $context');
    final lines = keyedText(tester, 'sd-hex-lines');
    expect(lines, contains('Stepped $direction → ${hex.topic}'));
    expect(lines, contains('Priority: $priority'));
    expect(lines, contains('Rolls: $a & $b ($direction) · d3'));
    final switched = hex.context != data.hex(0).context;
    expect(lines.contains('Context switch'), switched,
        reason: 'context-switch note tracks the crossing');
    final chars = await container.read(charactersProvider.future);
    expect(chars.single.emulation!.hexIndex, to);
  });

  testWidgets('stepping off the flower edge stays put', (tester) async {
    // Find a seed whose 2d6 walks off the edge from hex 7 (the top).
    var edgeSeed = 0;
    while (true) {
      final p = Dice(Random(edgeSeed));
      if (data.hexStep(7, p.dN(6) + p.dN(6)) == null) break;
      edgeSeed++;
    }
    final container =
        (await pump(tester, seed: edgeSeed, chars: charsWith(hexIndex: 7))).$2;
    await pickAsh(tester);
    await openHexTab(tester);
    final before = keyedText(tester, 'sd-hex-readout');
    await tester.tap(find.byKey(const Key('sd-hex-step')));
    await tester.pumpAndSettle();
    expect(keyedText(tester, 'sd-hex-lines'), contains('Edge — stay put'));
    expect(keyedText(tester, 'sd-hex-readout'), before);
    final chars = await container.read(charactersProvider.future);
    expect(chars.single.emulation!.hexIndex, 7);
  });

  // -- Journal ----------------------------------------------------------------

  testWidgets('journal: dialogue entry carries the voiced line; hex entry too',
      (tester) async {
    final r = rollDialogue(Dice(Random(7))); // no doubles, default mood
    final probe = Dice(Random(7));
    for (var i = 0; i < 6; i++) {
      probe.dN(6); // skip the dialogue draws (2d6 + four chips)
    }
    final a = probe.dN(6), b = probe.dN(6);
    final priority = const ['me', 'you', 'us'][probe.dN(3) - 1];
    final to = data.hexStep(0, a + b)!;
    final (fake, container) = await pump(tester, seed: 7);
    fake.queuedVoice.add('Empty hands, empty pockets.');
    await pickAsh(tester);
    await tester.tap(find.byKey(const Key('sd-roll')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sd-voice')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sd-log')));
    await tester.pumpAndSettle();
    await openHexTab(tester);
    await tester.tap(find.byKey(const Key('sd-hex-step')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sd-hex-log')));
    await tester.pumpAndSettle();
    final entries = container.read(journalProvider).valueOrNull ?? [];
    expect(entries, hasLength(2));
    // Newest first: the hex step, then the dialogue line.
    final hex = data.hex(to);
    expect(entries[0].title, 'Hexflower — ${hex.topic}');
    expect(entries[0].body, startsWith('Character: Ash'));
    expect(entries[0].body, contains('Topic: ${hex.topic}'));
    expect(
        entries[0].body,
        contains(
            'Context: ${hex.context == 'gray' ? 'history (gray)' : 'current events (red)'}'));
    expect(entries[0].body, contains('Priority: $priority'));
    expect(entries[0].body, contains('Rolls: $a & $b'));
    expect(entries[1].title, 'Sidekick — Default');
    expect(entries[1].body, startsWith('Character: Ash'));
    expect(entries[1].body,
        contains('"${data.dialogueLine('default', r.lineKey)}"'));
    expect(entries[1].body, contains('Tone: ${data.tones[r.toneIx]}'));
    expect(entries[1].body, contains('Said: ${data.saidHowA[r.saidHowAIx]}'));
    expect(entries[1].body, contains('Rolls: ${r.dice.$1} & ${r.dice.$2}'));
    expect(entries[1].body, contains('Voiced: "Empty hands, empty pockets."'));
  });
}
