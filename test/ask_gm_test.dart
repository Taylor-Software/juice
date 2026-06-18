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
}
