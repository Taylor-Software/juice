import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/help_data.dart';

void main() {
  // Tests run with CWD = project root, so read the asset file directly.
  final data = HelpData(
      jsonDecode(File('assets/help_data.json').readAsStringSync())
          as Map<String, dynamic>);

  test('sections come back ordered with id, title, and pages', () {
    expect(
        data.sections.map((s) => s.id).toList(), ['guide', 'systems', 'about']);
    final guide = data.sections.first;
    expect(guide.title, 'User guide');
    expect(guide.pages, isNotEmpty);
    expect(guide.pages.first.id, 'getting-started');
  });

  test('page() finds a page anywhere in the asset', () {
    final page = data.page('triple-o');
    expect(page.id, 'triple-o');
    expect(page.title, 'Triple-O (player emulator)');
    expect(page.blocks, isNotEmpty);
  });

  test('page() throws ArgumentError on unknown ids', () {
    expect(() => data.page('nope'), throwsArgumentError);
  });

  test('the Reading tarot guide page exists with blocks', () {
    final page = data.page('reading-tarot');
    expect(page.title, 'Reading tarot');
    expect(page.blocks, isNotEmpty);
  });

  test('pagesOf() returns a section\'s pages in order; throws on unknown', () {
    final pages = data.pagesOf('guide');
    expect(pages.first.id, 'getting-started');
    expect(pages.last.id, 'interpreter');
    expect(() => data.pagesOf('nope'), throwsArgumentError);
  });

  test('blocks parse into kinds with text or items', () {
    final blocks = data.page('getting-started').blocks;
    expect(blocks[0].kind, HelpBlockKind.p);
    expect(blocks[0].text, contains('campaign journal'));
    expect(blocks[1].kind, HelpBlockKind.h);
    expect(blocks[1].text, 'Move around');
    expect(blocks[2].kind, HelpBlockKind.steps);
    expect(blocks[2].items, hasLength(3));
    expect(blocks[3].kind, HelpBlockKind.tip);
    expect(blocks[3].text, contains('keeps its state'));
  });

  test('unknown block keys are skipped', () {
    final doctored = HelpData({
      'sections': [
        {
          'id': 's',
          'title': 'S',
          'pages': [
            {
              'id': 'p1',
              'title': 'P1',
              'blocks': [
                {'p': 'kept'},
                {'video': 'dropped'},
                {'tip': 'also kept'},
              ],
            }
          ],
        }
      ],
    });
    final blocks = doctored.page('p1').blocks;
    expect(blocks, hasLength(2));
    expect(blocks[0].text, 'kept');
    expect(blocks[1].kind, HelpBlockKind.tip);
  });
}
