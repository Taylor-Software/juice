import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/campaign_search.dart';
import 'package:juice_oracle/engine/models.dart';

// Minimal constructors for test fixtures.
JournalEntry _entry(String id, String title, String body) => JournalEntry(
      id: id,
      timestamp: DateTime(2026),
      title: title,
      body: body,
    );

Thread _thread(String id, String title, {String note = ''}) =>
    Thread(id: id, title: title, note: note);

Rumor _rumor(String id, String text, {String note = ''}) =>
    Rumor(id: id, text: text, note: note);

Track _track(String id, String name, {String note = ''}) =>
    Track(id: id, name: name, note: note);

Character _char(String id, String name, {String note = ''}) =>
    Character(id: id, name: name, note: note);

void main() {
  group('searchCampaign — empty query', () {
    test('returns all entities when query is blank', () {
      final results = searchCampaign(
        '',
        entries: [_entry('j1', 'Village', 'burning')],
        threads: [_thread('t1', 'The Curse')],
        rumors: [_rumor('r1', 'Strange lights')],
        tracks: [_track('tr1', 'Doom clock')],
        characters: [_char('c1', 'Aldric')],
      );
      expect(results, hasLength(5));
    });
  });

  group('searchCampaign — journal entries', () {
    test('matches title', () {
      final r = searchCampaign('village',
          entries: [_entry('j1', 'Village raid', ''), _entry('j2', 'Camp', '')]);
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
      final r = searchCampaign('curse',
          threads: [_thread('t1', 'The Curse of Eld', note: ''),
                    _thread('t2', 'Find the king')]);
      expect(r.single.id, 't1');
      expect(r.single.kind, SearchResultKind.thread);
    });

    test('matches note', () {
      final r = searchCampaign('shadow',
          threads: [_thread('t1', 'Mystery', note: 'Something shadow lurks')]);
      expect(r.single.kind, SearchResultKind.thread);
    });
  });

  group('searchCampaign — rumors', () {
    test('matches text', () {
      final r = searchCampaign('lights',
          rumors: [_rumor('r1', 'Strange lights seen'), _rumor('r2', 'Lost merchant')]);
      expect(r.single.id, 'r1');
    });

    test('matches note', () {
      final r = searchCampaign('goblin',
          rumors: [_rumor('r1', 'Old rumor', note: 'goblin sighting')]);
      expect(r.single.kind, SearchResultKind.rumor);
    });
  });

  group('searchCampaign — tracks', () {
    test('matches name', () {
      final r = searchCampaign('doom',
          tracks: [_track('tr1', 'Doom Clock'), _track('tr2', 'Reputation')]);
      expect(r.single.id, 'tr1');
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
      final r = searchCampaign('cursed sword',
          entries: [
            _entry('j1', 'Cursed sword found', ''),
            _entry('j2', 'Cursed ring', ''),
            _entry('j3', 'Old sword', ''),
          ]);
      expect(r.single.id, 'j1');
    });
  });

  group('searchCampaign — cross-entity', () {
    test('returns results from all five kinds in one call', () {
      final r = searchCampaign(
        'dragon',
        entries: [_entry('j1', 'Dragon spotted', '')],
        threads: [_thread('t1', 'Slay the dragon')],
        rumors: [_rumor('r1', 'Dragon gold')],
        tracks: [_track('tr1', 'Dragon threat')],
        characters: [_char('c1', 'Dragonborn warrior')],
      );
      expect(r, hasLength(5));
      final kinds = r.map((x) => x.kind).toSet();
      expect(kinds, {
        SearchResultKind.journalEntry,
        SearchResultKind.thread,
        SearchResultKind.rumor,
        SearchResultKind.track,
        SearchResultKind.character,
      });
    });
  });

  group('CampaignSearchResult navigation', () {
    test('journal entry navigates to journal', () {
      final r = searchCampaign('village',
          entries: [_entry('j1', 'Village', '')]).single;
      expect(r.destination, SearchDestination.journal);
    });

    test('thread navigates to track/threads', () {
      final r = searchCampaign('curse',
          threads: [_thread('t1', 'The Curse')]).single;
      expect(r.destination, SearchDestination.track);
      expect(r.subtab, 'threads');
    });

    test('rumor navigates to track/rumors', () {
      final r = searchCampaign('lights',
          rumors: [_rumor('r1', 'Strange lights')]).single;
      expect(r.destination, SearchDestination.track);
      expect(r.subtab, 'rumors');
    });

    test('track navigates to track/tracks', () {
      final r = searchCampaign('doom',
          tracks: [_track('tr1', 'Doom Clock')]).single;
      expect(r.destination, SearchDestination.track);
      expect(r.subtab, 'tracks');
    });

    test('character navigates to sheet/characters', () {
      final r = searchCampaign('aldric',
          characters: [_char('c1', 'Aldric')]).single;
      expect(r.destination, SearchDestination.sheet);
      expect(r.subtab, 'characters');
    });
  });
}
