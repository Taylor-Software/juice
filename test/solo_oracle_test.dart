import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/solo_oracle.dart';

void main() {
  group('classifyYesNo', () {
    test('roll 1 is always yes + boon', () {
      for (final o in SoloLikelihood.values) {
        final r = classifyYesNo(o, 1);
        expect(r.yes, isTrue);
        expect(r.twist, SoloTwist.boon);
      }
    });

    test('roll 10 is always no + complication', () {
      for (final o in SoloLikelihood.values) {
        final r = classifyYesNo(o, 10);
        expect(r.yes, isFalse);
        expect(r.twist, SoloTwist.complication);
      }
    });

    test('even (target 5): under=yes, exact=yes+complication, over=no', () {
      expect(classifyYesNo(SoloLikelihood.even, 4),
          predicate<SoloYesNo>((r) => r.yes && r.twist == SoloTwist.none));
      expect(classifyYesNo(SoloLikelihood.even, 5),
          predicate<SoloYesNo>((r) => r.yes && r.twist == SoloTwist.complication));
      expect(classifyYesNo(SoloLikelihood.even, 6),
          predicate<SoloYesNo>((r) => !r.yes && r.twist == SoloTwist.none));
    });

    test('likely (target 7): 6=yes, 7=yes+complication, 8=no', () {
      expect(classifyYesNo(SoloLikelihood.likely, 6).yes, isTrue);
      expect(classifyYesNo(SoloLikelihood.likely, 7).twist, SoloTwist.complication);
      expect(classifyYesNo(SoloLikelihood.likely, 8).yes, isFalse);
    });

    test('toGenResult carries the roll + a phrase, sourceTool-ready', () {
      final g = classifyYesNo(SoloLikelihood.likely, 1).toGenResult();
      expect(g.title, contains('Yes/No'));
      expect(g.asText.toLowerCase(), contains('boon'));
    });
  });

  test('toGenResult uses the asked question as the entry title', () {
    final r = classifyYesNo(SoloLikelihood.even, 2); // plain Yes
    final g = r.toGenResult(question: '  Is the bridge guarded?  ');
    expect(g.title, 'Is the bridge guarded?');
    expect(g.summary, 'Yes');
    expect(g.asText, contains('Odds: Even'));
    // No question -> the P1 title survives unchanged.
    expect(r.toGenResult().title, 'Yes/No — Even');
  });
}
