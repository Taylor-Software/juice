import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/journal_search.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/engine/oracle_interpreter.dart';
import 'package:juice_oracle/state/play_context.dart';

JournalEntry _e(String id, String title, String body,
        {List<String> tags = const [],
        JournalKind kind = JournalKind.result}) =>
    JournalEntry(
      id: id,
      timestamp: DateTime(2026, 7, 15).add(Duration(minutes: id.hashCode % 60)),
      title: title,
      body: body,
      tags: tags,
      kind: kind,
    );

void main() {
  group('relatedEntriesForText', () {
    test('ranks by shared terms against a raw roll string', () {
      final journal = [
        _e('a', 'The ferrywoman', 'Marta poles the skiff across the river'),
        _e('b', 'Market day', 'Bought turnips and rope'),
      ];
      final hits = relatedEntriesForText(journal, 'a skiff on the river');
      expect(hits.map((e) => e.id), ['a']);
    });

    test('excludes the excludeId entry and scene headers', () {
      final journal = [
        _e('self', 'Rusted key', 'a rusted key'),
        _e('scene', 'Rusted key scene', 'a rusted key',
            kind: JournalKind.scene),
        _e('other', 'Locksmith', 'a rusted key sits on the bench'),
      ];
      final hits =
          relatedEntriesForText(journal, 'rusted key', excludeId: 'self');
      expect(hits.map((e) => e.id), ['other']);
    });

    test('drops zero-score entries rather than padding to the limit', () {
      final journal = [_e('a', 'Unrelated', 'nothing in common whatsoever')];
      expect(relatedEntriesForText(journal, 'zzzz qqqq'), isEmpty);
    });

    test('relatedEntries still ranks on title+body+tags (delegation intact)',
        () {
      final journal = [
        _e('tagged', 'Elsewhere', 'no shared words', tags: ['harbor']),
        _e('none', 'Nothing', 'no shared words at all'),
      ];
      final target = _e('t', 'Target', 'totally different', tags: ['harbor']);
      // +3 for the shared tag alone is enough to surface it.
      expect(relatedEntries(journal, target).map((e) => e.id), ['tagged']);
    });
  });

  group('appendReading', () {
    const card = OracleInterpretation(
        lens: 'symbolic', reading: 'A teacup kept for someone who never came.');

    test('folds the reading under an existing body', () {
      final out = appendReading('d66: 34 / 12', card);
      expect(
          out,
          'd66: 34 / 12\n\n— Oracle reading (symbolic): '
          'A teacup kept for someone who never came.');
    });

    test('omits the leading blank line when the body is empty', () {
      expect(appendReading('   ', card), startsWith('— Oracle reading'));
      expect(appendReading('', card), isNot(startsWith('\n')));
    });

    test('is stable under repeated appends (each reading on its own line)', () {
      final once = appendReading('roll', card);
      final twice = appendReading(once, card);
      expect('— Oracle reading'.allMatches(twice).length, 2);
    });
  });

  group('sceneContextLine', () {
    test('matches the shape the interpret few-shots were authored against', () {
      final scene = JournalEntry(
        id: 's',
        timestamp: DateTime(2026, 7, 15),
        title: 'Begging entry at the city gate after dark',
        body: '',
        kind: JournalKind.scene,
        chaosFactor: 6,
      );
      expect(sceneContextLine(scene),
          'Scene: Begging entry at the city gate after dark (Chaos 6)');
    });

    test('carries the scene description when there is one', () {
      final scene = JournalEntry(
        id: 's',
        timestamp: DateTime(2026, 7, 15),
        title: 'The burned mill',
        body: 'Ash still warm underfoot.',
        kind: JournalKind.scene,
        chaosFactor: 5,
      );
      expect(sceneContextLine(scene),
          'Scene: The burned mill (Chaos 5) — Ash still warm underfoot.');
    });

    test('omits chaos when unset, and is empty with no scene', () {
      final scene = JournalEntry(
        id: 's',
        timestamp: DateTime(2026, 7, 15),
        title: 'A quiet road',
        body: '',
        kind: JournalKind.scene,
      );
      expect(sceneContextLine(scene), 'Scene: A quiet road');
      expect(sceneContextLine(null), isEmpty);
    });
  });

  group('interpretSeedFrom', () {
    final journal = [
      _e('s1', 'At the gate', 'The postern door is barred',
          kind: JournalKind.scene),
      _e('r1', 'Ferry', 'Marta the ferrywoman waits at the river'),
    ];

    test('always populates recall — the fix for the Run/Loop seams', () {
      final seed = interpretSeedFrom(
        resultText: 'Marta the ferrywoman appears',
        journal: journal,
      );
      expect(seed.journalContext, isNotEmpty,
          reason: 'a roll must carry recall, not just scene + pc');
      expect(seed.journalContext.first, contains('Marta'));
    });

    test('scene context follows the pinned activeSceneId', () {
      final seed = interpretSeedFrom(
        resultText: 'anything',
        journal: journal,
        activeSceneId: 's1',
      );
      expect(seed.sceneContext, contains('At the gate'));
      expect(seed.sceneContext, contains('postern'));
    });

    test('falls back to the newest scene when nothing is pinned', () {
      final seed = interpretSeedFrom(resultText: 'x', journal: journal);
      expect(seed.sceneContext, contains('At the gate'));
    });

    test('empty scene context when the journal has no scene', () {
      final seed = interpretSeedFrom(
        resultText: 'x',
        journal: [_e('r1', 'A', 'b')],
      );
      expect(seed.sceneContext, isEmpty);
    });

    test('carries genre, tone, primer and pc straight through', () {
      final seed = interpretSeedFrom(
        resultText: 'x',
        journal: journal,
        genre: 'grimdark fantasy',
        tone: 'tense',
        systemPrimer: 'Ironsworn:…',
        activeCharacter: 'Kesh (PC) — wounded',
      );
      expect(seed.genre, 'grimdark fantasy');
      expect(seed.tone, 'tense');
      expect(seed.systemPrimer, 'Ironsworn:…');
      expect(seed.activeCharacter, 'Kesh (PC) — wounded');
    });

    test('excludeId keeps an entry out of its own recall', () {
      final seed = interpretSeedFrom(
        resultText: 'Marta the ferrywoman waits at the river',
        journal: journal,
        excludeId: 'r1',
      );
      expect(seed.journalContext, isEmpty);
    });
  });

  group('buildOraclePrompt grounding', () {
    test('a seeded roll renders every grounding line in canonical order', () {
      final seed = interpretSeedFrom(
        resultText: 'Story: Discover / Object',
        journal: [
          _e('s', 'The cottage', 'Rain on the thatch', kind: JournalKind.scene),
          _e('r', 'Hearth', 'A loose hearthstone by the object shelf'),
        ],
        genre: 'cozy folk mystery',
        tone: 'warm but uneasy',
        systemPrimer: 'Cairn: d20 roll-under saves.',
        activeCharacter: 'Wren (PC)',
      );
      final prompt = buildOraclePrompt(seed);
      final order = [
        prompt.indexOf('genre:'),
        prompt.indexOf('tone:'),
        prompt.indexOf('system:'),
        prompt.indexOf('pc:'),
        prompt.indexOf('scene:'),
        prompt.indexOf('recall:'),
        prompt.indexOf('result:'),
      ];
      expect(order, everyElement(greaterThanOrEqualTo(0)),
          reason: 'every grounding line must render: $prompt');
      final sorted = [...order]..sort();
      expect(order, sorted, reason: 'canonical field order drifted: $prompt');
    });
  });
}
