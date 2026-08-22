import 'package:flutter_test/flutter_test.dart';
import 'package:loreseer/engine/campaign_search.dart';
import 'package:loreseer/engine/models.dart';

// Minimal constructors for test fixtures.
JournalEntry _entry(String id, String title, String body) => JournalEntry(
      id: id,
      timestamp: DateTime(2026),
      title: title,
      body: body,
    );

Thread _thread(String id, String title,
        {String note = '', ThreadStage stage = ThreadStage.active}) =>
    Thread(id: id, title: title, note: note, stage: stage);

Character _char(String id, String name, {String note = ''}) =>
    Character(id: id, name: name, note: note);

void main() {
  group('searchCampaign — empty query', () {
    test('returns all entities when query is blank', () {
      final results = searchCampaign(
        '',
        entries: [_entry('j1', 'Village', 'burning')],
        threads: [_thread('t1', 'The Curse')],
        characters: [_char('c1', 'Aldric')],
      );
      expect(results, hasLength(3));
    });
  });

  group('searchCampaign — journal entries', () {
    test('matches title', () {
      final r = searchCampaign('village', entries: [
        _entry('j1', 'Village raid', ''),
        _entry('j2', 'Camp', '')
      ]);
      expect(r, hasLength(1));
      expect(r.first.id, 'j1');
      expect(r.first.kind, SearchResultKind.journalEntry);
    });

    test('matches body', () {
      final r = searchCampaign('cursed',
          entries: [_entry('j1', 'Night', 'The sword is cursed')]);
      expect(r.single.kind, SearchResultKind.journalEntry);
    });
  });

  group('searchCampaign — threads', () {
    test('matches title', () {
      final r = searchCampaign('curse', threads: [
        _thread('t1', 'The Curse of Eld', note: ''),
        _thread('t2', 'Find the king')
      ]);
      expect(r.single.id, 't1');
      expect(r.single.kind, SearchResultKind.thread);
    });

    test('matches note', () {
      final r = searchCampaign('shadow',
          threads: [_thread('t1', 'Mystery', note: 'Something shadow lurks')]);
      expect(r.single.kind, SearchResultKind.thread);
    });

    test('rumor-stage threads are found as threads', () {
      final results = searchCampaign('whisper', threads: [
        Thread(id: 'r1', title: 'Whispered lead', stage: ThreadStage.rumor),
      ]);
      expect(results.single.kind, SearchResultKind.thread);
      expect(results.single.subtab, 'threads');
    });
  });

  group('searchCampaign — characters', () {
    test('matches name', () {
      final r = searchCampaign('aldric',
          characters: [_char('c1', 'Aldric'), _char('c2', 'Brynn')]);
      expect(r.single.id, 'c1');
      expect(r.single.kind, SearchResultKind.character);
    });

    test('matches note', () {
      final r = searchCampaign('blacksmith',
          characters: [_char('c1', 'Garret', note: 'retired blacksmith')]);
      expect(r.single.kind, SearchResultKind.character);
    });
  });

  group('searchCampaign — multi-term AND', () {
    test('requires all terms to match', () {
      final r = searchCampaign('cursed sword', entries: [
        _entry('j1', 'Cursed sword found', ''),
        _entry('j2', 'Cursed ring', ''),
        _entry('j3', 'Old sword', ''),
      ]);
      expect(r.single.id, 'j1');
    });
  });

  group('searchCampaign — cross-entity', () {
    test('returns results from all three kinds in one call', () {
      final r = searchCampaign(
        'dragon',
        entries: [_entry('j1', 'Dragon spotted', '')],
        threads: [_thread('t1', 'Slay the dragon')],
        characters: [_char('c1', 'Dragonborn warrior')],
      );
      expect(r, hasLength(3));
      final kinds = r.map((x) => x.kind).toSet();
      expect(kinds, {
        SearchResultKind.journalEntry,
        SearchResultKind.thread,
        SearchResultKind.character,
      });
    });
  });

  group('CampaignSearchResult navigation', () {
    test('journal entry navigates to journal', () {
      final r =
          searchCampaign('village', entries: [_entry('j1', 'Village', '')])
              .single;
      expect(r.destination, SearchDestination.journal);
    });

    test('thread navigates to track/threads', () {
      final r =
          searchCampaign('curse', threads: [_thread('t1', 'The Curse')]).single;
      expect(r.destination, SearchDestination.track);
      expect(r.subtab, 'threads');
    });

    test('character navigates to sheet/characters', () {
      final r =
          searchCampaign('aldric', characters: [_char('c1', 'Aldric')]).single;
      expect(r.destination, SearchDestination.sheet);
      expect(r.subtab, 'characters');
    });
  });
}
