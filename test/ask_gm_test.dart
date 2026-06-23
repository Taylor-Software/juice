import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/oracle_interpreter.dart';

void main() {
  group('buildAskGmPrompt', () {
    test('includes the question and the scene line when present', () {
      final p = buildAskGmPrompt(const AskGmSeed(
          question: 'Is the door locked?', sceneTitle: 'The vault'));
      expect(p, contains('Is the door locked?'));
      expect(p, contains('The vault'));
      expect(p, contains('OUTPUT'));
    });

    test('omits the scene line when no scene', () {
      final p = buildAskGmPrompt(const AskGmSeed(question: 'What do I smell?'));
      expect(p, contains('What do I smell?'));
      expect(p.toLowerCase(), isNot(contains('scene:')));
    });

    test('caps a very long question to protect the token budget', () {
      final long = 'x' * (kAskGmMaxFieldChars + 200);
      final p = buildAskGmPrompt(AskGmSeed(question: long));
      expect(p, contains('x' * kAskGmMaxFieldChars));
      expect(p, contains('…'));
      expect(p, isNot(contains('x' * (kAskGmMaxFieldChars + 1))));
    });
  });

  group('parseAskGmResponse', () {
    test('strips think spans and trims', () {
      expect(parseAskGmResponse('<think>x</think>  Yes, it is locked. '),
          'Yes, it is locked.');
    });
    test('throws on empty', () {
      expect(() => parseAskGmResponse('  '), throwsFormatException);
    });
  });

  group('buildAskGmPrompt grounding', () {
    test('grounds the question in system/pc/scene/recall', () {
      final p = buildAskGmPrompt(const AskGmSeed(
        question: 'Does the guard let me pass?',
        sceneTitle: 'The city gate at dusk',
        systemPrimer:
            'Ironsworn: perilous Iron Lands; roll action vs challenge.',
        activeCharacter: 'Taurin (PC)',
        journalContext: ['The gate captain owes Taurin a favor.'],
      ));
      expect(p, contains('system: Ironsworn'));
      expect(p, contains('pc: Taurin (PC)'));
      expect(p, contains('scene: The city gate at dusk'));
      expect(p, contains('recall: The gate captain owes Taurin a favor.'));
      expect(p, contains('question: Does the guard let me pass?'));
    });

    test('omits empty grounding lines', () {
      final p = buildAskGmPrompt(const AskGmSeed(question: 'What now?'));
      expect(p, isNot(contains('system:')));
      expect(p, isNot(contains('pc:')));
      expect(p, isNot(contains('scene:')));
      expect(p, isNot(contains('recall:')));
      expect(p, contains('question: What now?'));
    });
  });
}
