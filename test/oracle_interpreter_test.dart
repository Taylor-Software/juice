import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/gm_chat.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/engine/oracle_interpreter.dart';

import 'fake_interpreter.dart';

void main() {
  group('buildOraclePrompt', () {
    test('carries result, genre, tone, scene', () {
      const seed = OracleSeed(
        resultText: 'Fate Check (Likely) — Yes, and…',
        genre: 'grimdark fantasy',
        tone: 'tense',
        sceneContext: 'Scene: The burned mill (Chaos 5)',
      );
      final p = buildOraclePrompt(seed);
      expect(p, contains('genre: grimdark fantasy'));
      expect(p, contains('tone: tense'));
      expect(p, contains('result: Fate Check (Likely) — Yes, and…'));
      expect(p, contains('scene: Scene: The burned mill (Chaos 5)'));
      expect(p, endsWith('OUTPUT:'));
    });

    test('systemPrimer renders a system: line between tone and result', () {
      const seed = OracleSeed(
        resultText: 'Fate Check — Yes',
        systemPrimer: 'D&D 5e: heroic high fantasy.',
      );
      final lines = buildOraclePrompt(seed).split('\n');
      final toneIdx = lines.indexWhere((l) => l.startsWith('tone:'));
      expect(lines[toneIdx + 1], 'system: D&D 5e: heroic high fantasy.');
      expect(lines.indexWhere((l) => l.startsWith('result:')),
          greaterThan(toneIdx + 1));
      expect(lines.last, 'OUTPUT:');
    });

    test('empty systemPrimer emits no system: line', () {
      const seed = OracleSeed(resultText: 'Story: Betrayal / Ally');
      expect(buildOraclePrompt(seed), isNot(contains('system:')));
    });

    test('empty fields become explicit placeholders', () {
      const seed = OracleSeed(resultText: 'Story: Betrayal / Ally');
      final p = buildOraclePrompt(seed);
      expect(p, contains('genre: (unspecified)'));
      expect(p, contains('tone: (unspecified)'));
      expect(p, contains('scene: (none given)'));
    });

    test('journalContext renders recall lines between result and scene', () {
      const seed = OracleSeed(
        resultText: 'Fate Check — Yes',
        journalContext: ['a', 'b'],
      );
      expect(buildOraclePrompt(seed).split('\n'), [
        'INPUT:',
        'genre: (unspecified)',
        'tone: (unspecified)',
        'result: Fate Check — Yes',
        'recall: a',
        'recall: b',
        'scene: (none given)',
        'OUTPUT:',
      ]);
    });

    test('recall lines are capped and truncated for the token budget', () {
      // Caps are load-bearing budget discipline (see kRecallMaxEntries/Chars).
      final seed = OracleSeed(
        resultText: 'r',
        // More entries than the cap; the first is over the char cap.
        journalContext: ['x' * 400, 'b', 'c', 'd', 'e', 'f', 'g'],
      );
      final recalls = buildOraclePrompt(seed)
          .split('\n')
          .where((l) => l.startsWith('recall: '))
          .toList();
      expect(recalls, hasLength(kRecallMaxEntries)); // capped (7 → 6)
      expect(recalls[0], 'recall: ${'x' * kRecallMaxChars}…'); // truncated
      expect(recalls[1], 'recall: b');
    });

    test('no journalContext -> no recall line', () {
      const seed = OracleSeed(resultText: 'Story: Betrayal / Ally');
      expect(buildOraclePrompt(seed), isNot(contains('recall:')));
    });

    test('recall strings are whitespace-flattened', () {
      const seed = OracleSeed(
        resultText: 'r',
        journalContext: ['Omen draw —\n  black   feather'],
      );
      expect(buildOraclePrompt(seed),
          contains('recall: Omen draw — black feather'));
    });

    test('multi-line seed fields collapse to one prompt line each', () {
      const seed = OracleSeed(
        resultText: 'Title\nBody line',
        genre: 'grim  dark',
        tone: 'tense',
        sceneContext: 'Scene one\n(Chaos 5)',
      );
      final p = buildOraclePrompt(seed);
      expect(p, contains('result: Title Body line'));
      expect(p, contains('genre: grim dark'));
      expect(p, contains('scene: Scene one (Chaos 5)'));
      final lines = p.split('\n');
      expect(
          lines, hasLength(6)); // INPUT:, genre, tone, result, scene, OUTPUT:
      expect(lines.first, 'INPUT:');
      expect(lines.last, 'OUTPUT:');
    });
  });

  group('parseInterpretations', () {
    const clean =
        '{"interpretations":[{"lens":"literal","reading":"A"},{"lens":"symbolic","reading":"B"},'
        '{"lens":"complication","reading":"C"},{"lens":"foreshadow","reading":"D"}]}';

    test('clean JSON -> four cards in order', () {
      final cards = parseInterpretations(clean);
      expect(cards.map((c) => c.lens).toList(), kLenses);
      expect(cards.map((c) => c.reading).toList(), ['A', 'B', 'C', 'D']);
    });

    test('fenced JSON parses', () {
      expect(parseInterpretations('```json\n$clean\n```'), hasLength(4));
    });

    test('think tags are stripped before parsing', () {
      final cards =
          parseInterpretations('<think>\nthe player wants…\n</think>\n$clean');
      expect(cards, hasLength(4));
      expect(cards.first.reading, 'A');
    });

    test('prose around the JSON object is ignored', () {
      expect(
          parseInterpretations('Here you go!\n$clean\nEnjoy.'), hasLength(4));
    });

    test('trailing prose containing a brace is ignored', () {
      expect(parseInterpretations('$clean\nEnjoy :-}'), hasLength(4));
    });

    test('unterminated think tag yields no cards', () {
      expect(parseInterpretations('<think> hmm {partial'), isEmpty);
    });

    test('interpretations key holding a non-list falls back to raw', () {
      final cards = parseInterpretations('{"interpretations":"x"}');
      expect(cards.single.lens, 'raw');
    });

    test('numeric reading is tolerated via toString', () {
      final cards = parseInterpretations(
          '{"interpretations":[{"lens":"literal","reading":42}]}');
      expect(cards.single.lens, 'literal');
      expect(cards.single.reading, '42');
    });

    test('entries missing a reading are dropped; empty lens defaults', () {
      final cards = parseInterpretations(
          '{"interpretations":[{"lens":"literal","reading":""},'
          '{"reading":"only one"}]}');
      expect(cards, hasLength(1));
      expect(cards.single.lens, 'reading');
      expect(cards.single.reading, 'only one');
    });

    test('garbage falls back to a single raw card', () {
      final cards = parseInterpretations('not json at all');
      expect(cards.single.lens, 'raw');
      expect(cards.single.reading, 'not json at all');
    });

    test('empty/whitespace output -> no cards', () {
      expect(parseInterpretations('   \n'), isEmpty);
    });

    test('malformed JSON inside braces falls back to raw', () {
      final cards = parseInterpretations('{"interpretations": [oops');
      expect(cards.single.lens, 'raw');
    });

    group('salvage of unescaped-quote output', () {
      // Verbatim Gemma3 1B (web) capture: structurally correct lens/reading
      // sequence, but the literal reading contains unescaped double quotes,
      // and the model rambled extra INPUT lines after the object.
      const captured =
          r'''{"interpretations":[{"lens":"literal","reading":"The wood creaks and glows fire-swept, no warmth you look for," but you recognize the scent of iron," you're not alone."},{"lens":"symbolic","reading":"The stones within the mill pulse with a slow betrayal, a reckoning waiting."},{"lens":"complication","reading":"The map you seek is a lie. Return to the city gate."},{"lens":"foreshadow","reading":"A shadow coalesces within the mill and a whisper speaks."}]}

INPUT:
genre: grimdark fantasy
tone: tense and dangerous
result: Fate Check (Likely) — Yes, and…
''';

      test('real captured Gemma output -> four cards, quotes preserved', () {
        final cards = parseInterpretations(captured);
        expect(cards, hasLength(4));
        expect(cards.map((c) => c.lens).toList(), kLenses);
        expect(cards.first.reading, contains("you're not alone"));
        expect(cards.first.reading, contains(r'scent of iron,"'));
        expect(cards.first.reading, endsWith("you're not alone."));
        expect(cards.last.reading,
            'A shadow coalesces within the mill and a whisper speaks.');
      });

      test('unescaped quote in a middle card only -> four cards', () {
        final cards = parseInterpretations(
            '{"interpretations":[{"lens":"literal","reading":"A"},'
            '{"lens":"symbolic","reading":"He said "no" and left."},'
            '{"lens":"complication","reading":"C"},'
            '{"lens":"foreshadow","reading":"D"}]}');
        expect(cards, hasLength(4));
        expect(cards.map((c) => c.lens).toList(), kLenses);
        expect(cards[1].reading, 'He said "no" and left.');
        expect(cards[3].reading, 'D');
      });

      test('garbage with quotes and braces but no delimiters -> raw', () {
        const garbage = 'the "model" said {nothing useful} at all"}';
        final cards = parseInterpretations(garbage);
        expect(cards.single.lens, 'raw');
        expect(cards.single.reading, garbage);
      });
    });
  });

  group('buildVoicePrompt', () {
    test('carries line, mood, chips, character, settings, and the contract',
        () {
      const seed = VoiceSeed(
        line: "I'm not getting any younger.",
        mood: 'sassy',
        tone: 'eager',
        topic: 'a want/desire',
        characterName: 'Ash',
        characterTags: ['brave', 'curious'],
        genre: 'grimdark fantasy',
        toneSetting: 'tense and dangerous',
      );
      final p = buildVoicePrompt(seed);
      expect(p, contains("line: I'm not getting any younger."));
      expect(p, contains('mood: sassy'));
      expect(p, contains('line tone: eager'));
      expect(p, contains('topic: a want/desire'));
      expect(p, contains('character: Ash'));
      expect(p, contains('traits: brave, curious'));
      expect(p, contains('genre: grimdark fantasy'));
      expect(p, contains('tone: tense and dangerous'));
      // The compact plain-text instruction rides inside the prompt (the web
      // session cannot take a per-chat system instruction).
      expect(p, contains('ONE'));
      expect(p, contains('1-2 short sentences'));
      expect(p, contains('plain text'));
      expect(p, isNot(contains('JSON shape')));
      expect(p, endsWith('OUTPUT:'));
    });

    test('systemPrimer renders a system: line after tone', () {
      const seed = VoiceSeed(
        line: 'Hold the line!',
        mood: 'default',
        systemPrimer: 'Shadowdark: lethal old-school dungeon-crawling.',
      );
      final lines = buildVoicePrompt(seed).split('\n');
      final toneIdx = lines.indexWhere((l) => l.startsWith('tone:'));
      expect(lines[toneIdx + 1],
          'system: Shadowdark: lethal old-school dungeon-crawling.');
      expect(lines.last, 'OUTPUT:');
    });

    test('empty systemPrimer emits no system: line in the INPUT block', () {
      const seed = VoiceSeed(line: 'Hi', mood: 'default');
      final p = buildVoicePrompt(seed);
      final input = p.substring(p.indexOf('INPUT:'));
      expect(input, isNot(contains('system:')));
    });

    test('optional fields are omitted; empty settings get placeholders', () {
      const seed = VoiceSeed(line: 'Duck.', mood: 'taciturn');
      final p = buildVoicePrompt(seed);
      // The instruction block mentions field names in prose; the omission
      // assertions only concern the INPUT block.
      final input = p.substring(p.indexOf('INPUT:'));
      expect(input, contains('line: Duck.'));
      expect(input, contains('mood: taciturn'));
      expect(input, isNot(contains('line tone:')));
      expect(input, isNot(contains('topic:')));
      expect(input, isNot(contains('character:')));
      expect(input, isNot(contains('traits:')));
      expect(input, contains('genre: (unspecified)'));
      expect(input, contains('tone: (unspecified)'));
      expect(input, isNot(contains('recall:')));
    });

    test('recall lines are capped and truncated like the oracle prompt', () {
      final seed = VoiceSeed(
        line: 'Go.',
        mood: 'default',
        journalContext: ['x' * 400, 'b', 'c', 'd', 'e', 'f', 'g'],
      );
      final recalls = buildVoicePrompt(seed)
          .split('\n')
          .where((l) => l.startsWith('recall: '))
          .toList();
      expect(recalls, hasLength(kRecallMaxEntries)); // capped (7 → 6)
      expect(recalls[0], 'recall: ${'x' * kRecallMaxChars}…');
      expect(recalls[1], 'recall: b');
    });

    test('multi-line seed fields collapse to one prompt line each', () {
      const seed = VoiceSeed(line: 'Look\n  out!', mood: 'default');
      expect(buildVoicePrompt(seed), contains('line: Look out!'));
    });
  });

  group('parseVoiceResponse', () {
    test('strips think tags and trims', () {
      expect(parseVoiceResponse('<think>hmm</think>\n  Get down, now!  '),
          'Get down, now!');
    });

    test('plain text passes through trimmed', () {
      expect(parseVoiceResponse('  Right behind you.\n'), 'Right behind you.');
    });

    test('empty, whitespace, or all-think output throws FormatException', () {
      expect(() => parseVoiceResponse(''), throwsFormatException);
      expect(() => parseVoiceResponse('   \n'), throwsFormatException);
      expect(() => parseVoiceResponse('<think>still going'),
          throwsFormatException);
    });
  });

  group('FakeInterpreterService.voiceLine', () {
    test('captures the seed, drains the queue, then falls back canned',
        () async {
      final fake = FakeInterpreterService();
      fake.queuedVoice.addAll(['First!', 'Second.']);
      const seed = VoiceSeed(line: 'Go.', mood: 'default');
      expect(await fake.voiceLine(seed), 'First!');
      expect(fake.lastVoiceSeed, same(seed));
      expect(await fake.voiceLine(seed), 'Second.');
      final canned = await fake.voiceLine(seed);
      expect(canned, isNotEmpty);
      expect(fake.voiceCalls, 3);
    });

    test('throws the scripted error', () async {
      final fake = FakeInterpreterService()
        ..voiceError = StateError('Interpreter not ready');
      expect(fake.voiceLine(const VoiceSeed(line: 'Go.', mood: 'default')),
          throwsStateError);
    });
  });

  test('system instruction states the contract', () {
    expect(oracleSystemInstruction, contains('"interpretations"'));
    for (final lens in kLenses) {
      expect(oracleSystemInstruction, contains(lens));
    }
    expect(oracleSystemInstruction, contains('ONLY a JSON object'));
    expect(oracleSystemInstruction, contains('recall:'));
  });

  group('recallLines', () {
    test('formats relatedEntries output as "Title — body" / body-only', () {
      final journal = [
        JournalEntry(
            id: '1',
            timestamp: DateTime(2026, 1, 1),
            title: 'The Tower',
            body: 'A black gate guards the ruined tower.'),
        JournalEntry(
            id: '2',
            timestamp: DateTime(2026, 1, 2),
            title: '',
            body: 'The black gate is sealed with old runes.'),
      ];
      final target = JournalEntry(
          id: 't',
          timestamp: DateTime(2026, 1, 3),
          title: 'gate',
          body: 'the black gate and the tower');
      final lines = recallLines(journal, target);
      expect(lines, isNotEmpty);
      expect(lines.any((l) => l.startsWith('The Tower — ')), isTrue);
      expect(lines.any((l) => l == 'The black gate is sealed with old runes.'),
          isTrue);
    });
  });

  test('recall budget is loosened for the on-device model', () {
    expect(kRecallMaxEntries, 6);
    expect(kRecallMaxChars, 280);
  });

  group('activeCharacterLine', () {
    test('null → empty', () => expect(activeCharacterLine(null), ''));
    test('PC with conditions → "Name (PC) — cond"', () {
      const c = Character(
          id: 'c1',
          name: 'Taurin',
          role: CharacterRole.pc,
          conditions: ['wounded', 'hexed']);
      expect(activeCharacterLine(c), 'Taurin (PC) — wounded, hexed');
    });
    test('companion, no conditions → "Name (companion)"', () {
      const c = Character(id: 'c2', name: 'Vex', role: CharacterRole.companion);
      expect(activeCharacterLine(c), 'Vex (companion)');
    });
  });

  test('buildOraclePrompt renders a pc: line when present, omits when empty',
      () {
    final withPc = buildOraclePrompt(const OracleSeed(
        resultText: 'A door opens.', activeCharacter: 'Taurin (PC)'));
    expect(withPc, contains('\npc: Taurin (PC)\n'));
    final noPc =
        buildOraclePrompt(const OracleSeed(resultText: 'A door opens.'));
    expect(noPc, isNot(contains('pc:')));
  });

  test('buildVoicePrompt renders pc: distinct from the spoken character:', () {
    final p = buildVoicePrompt(const VoiceSeed(
        line: 'Hello there.',
        mood: 'default',
        characterName: 'The Innkeeper',
        activeCharacter: 'Taurin (PC)'));
    expect(p, contains('character: The Innkeeper')); // the spoken NPC
    expect(p, contains('pc: Taurin (PC)')); // the player character
  });

  group('buildNarratePrompt', () {
    test('continueScene grounds + uses the narrate-next-beat instruction', () {
      final p = buildNarratePrompt(const NarrateSeed(
        mode: NarrateMode.continueScene,
        sceneTitle: 'The collapsing bridge',
        systemPrimer: 'Ironsworn: perilous Iron Lands.',
        activeCharacter: 'Taurin (PC)',
        journalContext: ['The rope is fraying.'],
      ));
      expect(p, contains('Narrate the next beat'));
      expect(p, contains('system: Ironsworn'));
      expect(p, contains('pc: Taurin (PC)'));
      expect(p, contains('scene: The collapsing bridge'));
      expect(p, contains('recall: The rope is fraying.'));
      expect(p.trimRight(), endsWith('Narration:'));
    });

    test('complication uses the twist instruction', () {
      final p =
          buildNarratePrompt(const NarrateSeed(mode: NarrateMode.complication));
      expect(p, contains('complication or twist'));
      expect(p, isNot(contains('system:'))); // empty grounding omitted
      expect(p, isNot(contains('scene:'))); // null sceneTitle omitted too
      expect(p.trimRight(), endsWith('Narration:'));
    });

    test('caps an over-long sceneTitle with an ellipsis', () {
      final long = 'a' * 400; // > kAskGmMaxFieldChars (300)
      final p = buildNarratePrompt(NarrateSeed(
        mode: NarrateMode.continueScene,
        sceneTitle: long,
      ));
      expect(p, contains('…')); // truncated
      expect(p, isNot(contains(long))); // full untruncated title absent
    });

    test('parseNarrateResponse strips think + throws on empty', () {
      expect(parseNarrateResponse('<think>x</think> The bridge groans. '),
          'The bridge groans.');
      expect(() => parseNarrateResponse('  '), throwsFormatException);
    });
  });

  group('buildFleshOutPrompt', () {
    test('renders instruction + grounding + name/existing + Detail cue', () {
      final p = buildFleshOutPrompt(const FleshOutSeed(
        entityKind: 'NPC',
        name: 'Sister Vane',
        existingDetail: 'A grim cleric.',
        systemPrimer: 'Ironsworn: perilous Iron Lands.',
        sceneTitle: 'The crypt',
        journalContext: ['Sister Vane barred the door.'],
      ));
      expect(p, contains('Flesh out the following NPC'));
      expect(p, contains('system: Ironsworn'));
      expect(p, contains('scene: The crypt'));
      expect(p, contains('recall: Sister Vane barred the door.'));
      expect(p, contains('name: Sister Vane'));
      expect(p, contains('existing: A grim cleric.'));
      expect(p.trimRight(), endsWith('Detail:'));
    });

    test('omits the existing line + empty grounding', () {
      final p = buildFleshOutPrompt(
          const FleshOutSeed(entityKind: 'location', name: 'The Old Mill'));
      expect(p, contains('Flesh out the following location'));
      expect(p, isNot(contains('existing:')));
      expect(p, isNot(contains('system:')));
      expect(p.trimRight(), endsWith('Detail:'));
    });

    test('parseFleshOutResponse strips think + throws on empty', () {
      expect(parseFleshOutResponse('<think>x</think> A damp vault. '),
          'A damp vault.');
      expect(() => parseFleshOutResponse('   '), throwsFormatException);
    });
  });

  group('buildGmChatPrompt', () {
    test('grounds the chat + renders the transcript + trailing GM:', () {
      final p = buildGmChatPrompt(const GmChatSeed(
        history: [
          ChatTurn(ChatRole.player, 'Who guards the gate?'),
          ChatTurn(ChatRole.gm, 'A bored sergeant named Doll.'),
          ChatTurn(ChatRole.player, 'Can I bribe her?'),
        ],
        sceneTitle: 'The city gate',
        systemPrimer: 'Ironsworn: perilous Iron Lands.',
        activeCharacter: 'Taurin (PC)',
        journalContext: ['Doll owes Taurin a favor.'],
      ));
      expect(p, contains('system: Ironsworn'));
      expect(p, contains('pc: Taurin (PC)'));
      expect(p, contains('scene: The city gate'));
      expect(p, contains('recall: Doll owes Taurin a favor.'));
      expect(p, contains('Player: Who guards the gate?'));
      expect(p, contains('GM: A bored sergeant named Doll.'));
      expect(p, contains('Player: Can I bribe her?'));
      expect(p.trimRight(), endsWith('GM:')); // model continues as GM
    });

    test('keeps only the last kGmChatHistoryTurns turns', () {
      final history = [
        for (var i = 0; i < kGmChatHistoryTurns + 3; i++)
          ChatTurn(ChatRole.player, 'turn$i'),
      ];
      final p = buildGmChatPrompt(GmChatSeed(history: history));
      expect(p, isNot(contains('turn0'))); // dropped (oldest)
      expect(p, contains('turn${kGmChatHistoryTurns + 2}')); // newest kept
      final shown = 'Player:'.allMatches(p).length;
      expect(shown, kGmChatHistoryTurns);
    });

    test('parseGmChatResponse strips think + throws on empty', () {
      expect(
          parseGmChatResponse('<think>x</think> Doll grins. '), 'Doll grins.');
      expect(() => parseGmChatResponse('  '), throwsFormatException);
    });
  });
}
