import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // Tests run with CWD = project root, so read the asset file directly.
  final root = jsonDecode(File('assets/help_data.json').readAsStringSync())
      as Map<String, dynamic>;
  final sections = (root['sections'] as List).cast<Map<String, dynamic>>();

  List<Map<String, dynamic>> pagesOf(String sectionId) =>
      (sections.firstWhere((s) => s['id'] == sectionId)['pages'] as List)
          .cast<Map<String, dynamic>>();

  test('three sections in order: guide, systems, about', () {
    expect(sections, hasLength(3));
    expect(
        sections.map((s) => s['id']).toList(), ['guide', 'systems', 'about']);
  });

  test('section and page ids unique; pages have title and blocks', () {
    final sectionIds = sections.map((s) => s['id'] as String).toList();
    expect(sectionIds.toSet().length, sectionIds.length);
    final pageIds = <String>[];
    for (final s in sections) {
      for (final p in (s['pages'] as List).cast<Map<String, dynamic>>()) {
        pageIds.add(p['id'] as String);
        expect((p['title'] as String).trim(), isNotEmpty,
            reason: 'page ${p['id']} title');
        expect(p['blocks'] as List, isNotEmpty,
            reason: 'page ${p['id']} blocks');
      }
    }
    expect(pageIds.toSet().length, pageIds.length);
  });

  test('every block is a 1-key map of a known kind with non-empty content', () {
    const known = {'h', 'p', 'tip', 'steps'};
    for (final s in sections) {
      for (final p in (s['pages'] as List).cast<Map<String, dynamic>>()) {
        for (final b in (p['blocks'] as List).cast<Map<String, dynamic>>()) {
          expect(b.keys, hasLength(1), reason: 'page ${p['id']}');
          final kind = b.keys.single;
          expect(known, contains(kind), reason: 'page ${p['id']}');
          if (kind == 'steps') {
            final steps = (b['steps'] as List).cast<String>();
            expect(steps, isNotEmpty, reason: 'page ${p['id']}');
            for (final step in steps) {
              expect(step.trim(), isNotEmpty, reason: 'page ${p['id']}');
            }
          } else {
            expect((b[kind] as String).trim(), isNotEmpty,
                reason: 'page ${p['id']}');
          }
        }
      }
    }
  });

  test('guide section contains exactly the expected pages', () {
    expect(pagesOf('guide').map((p) => p['id']).toList(), [
      'getting-started',
      'journal',
      'sessions-campaigns',
      'fate-check',
      'roll-high',
      'mythic-gme',
      'dice-roller',
      'story-scenes',
      'npcs-dialog',
      'generators-tables',
      'reading-tarot',
      'party-emulator',
      'behavior-tables',
      'sidekick-dialogue',
      'threads-characters',
      'encounter',
      'maps',
      'verdant',
      'moves',
      'interpreter',
    ]);
  });

  test('systems section contains exactly the expected pages', () {
    expect(pagesOf('systems').map((p) => p['id']).toList(), [
      'juice-oracle',
      'roll-high-system',
      'mythic-gme-system',
      'ironsworn-family',
      'triple-o',
      'pet',
      'sidekick',
    ]);
  });

  test('about section contains exactly the credits page', () {
    expect(pagesOf('about').map((p) => p['id']).toList(), ['credits']);
  });

  test("every systems page ends with a 'p' attribution block containing ©", () {
    for (final p in pagesOf('systems')) {
      final last = (p['blocks'] as List).cast<Map<String, dynamic>>().last;
      expect(last.keys.single, 'p', reason: 'page ${p['id']}');
      expect(last['p'] as String, contains('©'), reason: 'page ${p['id']}');
    }
  });

  test('credits page carries every license and credit string', () {
    final credits = pagesOf('about').single;
    final text = (credits['blocks'] as List)
        .cast<Map<String, dynamic>>()
        .map((b) => b.values.single is List
            ? (b.values.single as List).join('\n')
            : b.values.single as String)
        .join('\n');
    for (final needle in [
      'jrruethe',
      'CC BY-NC-SA 4.0',
      'Word Mill Games',
      'CC-BY-NC 4.0',
      'Shawn Tomkin',
      'CC-BY 4.0',
      'Sundered Isles',
      'CC-BY-NC-SA 4.0',
      'Cezar Capacle',
      'CC-BY-SA 4.0',
      'Tam H',
      'hedonic.ink',
      'thunder9861',
      'Gemma',
      'free',
    ]) {
      expect(text, contains(needle));
    }
    expect(text, contains('non-commercial'));
  });
}
