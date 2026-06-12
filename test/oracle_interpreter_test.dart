import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/oracle_interpreter.dart';

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

    test('empty fields become explicit placeholders', () {
      const seed = OracleSeed(resultText: 'Story: Betrayal / Ally');
      final p = buildOraclePrompt(seed);
      expect(p, contains('genre: (unspecified)'));
      expect(p, contains('tone: (unspecified)'));
      expect(p, contains('scene: (none given)'));
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
      expect(lines, hasLength(6)); // INPUT:, genre, tone, result, scene, OUTPUT:
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
      final cards = parseInterpretations(
          '<think>\nthe player wants…\n</think>\n$clean');
      expect(cards, hasLength(4));
      expect(cards.first.reading, 'A');
    });

    test('prose around the JSON object is ignored', () {
      expect(parseInterpretations('Here you go!\n$clean\nEnjoy.'), hasLength(4));
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

  test('system instruction states the contract', () {
    expect(oracleSystemInstruction, contains('"interpretations"'));
    for (final lens in kLenses) {
      expect(oracleSystemInstruction, contains(lens));
    }
    expect(oracleSystemInstruction, contains('ONLY a JSON object'));
  });
}
