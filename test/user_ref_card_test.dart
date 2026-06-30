import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/quick_ref.dart';

void main() {
  group('parseRefSections', () {
    test('empty input -> []', () {
      expect(parseRefSections(''), isEmpty);
      expect(parseRefSections('   \n\n'), isEmpty);
    });
    test('headings split sections; bullets attach to current', () {
      final s = parseRefSections('# Combat\nroll to hit\ndeal damage\n# Rest\nsleep');
      expect(s.map((e) => e.title).toList(), ['Combat', 'Rest']);
      expect(s[0].lines, ['roll to hit', 'deal damage']);
      expect(s[1].lines, ['sleep']);
    });
    test('pre-heading lines go under a leading Notes section', () {
      final s = parseRefSections('house rule: crits explode\n# Combat\nhit');
      expect(s.first.title, 'Notes');
      expect(s.first.lines, ['house rule: crits explode']);
      expect(s[1].title, 'Combat');
    });
    test('blank lines ignored; empty headings dropped', () {
      final s = parseRefSections('# A\n\nx\n#\n# B\ny');
      expect(s.map((e) => e.title).toList(), ['A', 'B']);
    });
  });

  group('UserRefCard', () {
    test('toQuickRefCard carries title + sections', () {
      const c = UserRefCard(
          id: '1', title: 'My Rules', sections: [QuickRefSection('A', ['x'])]);
      final q = c.toQuickRefCard();
      expect(q.title, 'My Rules');
      expect(q.sections.single.lines, ['x']);
    });
    test('JSON round-trips; maybeFromJson tolerant', () {
      const c = UserRefCard(
          id: '1', title: 'T', sections: [QuickRefSection('A', ['x', 'y'])]);
      final back = UserRefCard.maybeFromJson(c.toJson());
      expect(back?.id, '1');
      expect(back?.title, 'T');
      expect(back?.sections.single.title, 'A');
      expect(back?.sections.single.lines, ['x', 'y']);
      expect(UserRefCard.maybeFromJson(null), isNull);
      expect(UserRefCard.maybeFromJson(const {'id': 1}), isNull);
    });
  });
}
