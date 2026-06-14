import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/state/campaign_io.dart';
import 'package:juice_oracle/state/providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Campaign file encode/parse', () {
    test('round-trip preserves name and per-key payloads', () {
      final encoded = encodeCampaign(
        name: 'West Marches',
        savedAt: DateTime.utc(2026, 6, 11),
        rawByKey: {
          'juice.threads.v1':
              '[{"id":"t1","title":"Vow","note":"","open":true}]',
          'juice.crawl.v1':
              '{"envRow":7,"lost":true,"dialogRow":2,"dialogCol":2}',
        },
      );
      final parsed = parseCampaign(encoded);
      expect(parsed.name, 'West Marches');
      expect(parsed.rawByKey.keys,
          unorderedEquals(['juice.threads.v1', 'juice.crawl.v1']));
      expect(parsed.rawByKey['juice.threads.v1'], contains('"title":"Vow"'));
      expect(parsed.rawByKey['juice.crawl.v1'], contains('"envRow":7'));
    });

    test('rejects non-JSON, wrong app marker, and newer schema versions', () {
      expect(() => parseCampaign('not json'), throwsFormatException);
      expect(
        () => parseCampaign(
            '{"app":"other","schemaVersion":1,"name":"x","data":{}}'),
        throwsFormatException,
      );
      expect(
        () => parseCampaign(
            '{"app":"juice-oracle","schemaVersion":4,"name":"x","data":{}}'),
        throwsFormatException,
      );
      expect(
        () => parseCampaign(
            '{"app":"juice-oracle","schemaVersion":1,"name":"x","data":[]}'),
        throwsFormatException,
      );
    });

    test('unknown data keys are ignored on parse', () {
      final parsed =
          parseCampaign('{"app":"juice-oracle","schemaVersion":1,"name":"x",'
              '"data":{"juice.threads.v1":[],"someday.v9":{}}}');
      expect(parsed.rawByKey.keys, ['juice.threads.v1']);
    });

    test('non-string name falls back instead of throwing', () {
      final parsed = parseCampaign(
          '{"app":"juice-oracle","schemaVersion":1,"name":42,"data":{}}');
      expect(parsed.name, 'Imported campaign');
    });

    test('rejects data payloads of the wrong shape', () {
      expect(
        () =>
            parseCampaign('{"app":"juice-oracle","schemaVersion":1,"name":"x",'
                '"data":{"juice.threads.v1":"garbage"}}'),
        throwsFormatException,
      );
      expect(
        () =>
            parseCampaign('{"app":"juice-oracle","schemaVersion":1,"name":"x",'
                '"data":{"juice.threads.v1":[{"nope":true}]}}'),
        throwsFormatException,
      );
      expect(
        () =>
            parseCampaign('{"app":"juice-oracle","schemaVersion":1,"name":"x",'
                '"data":{"juice.crawl.v1":[1,2,3]}}'),
        throwsFormatException,
      );
    });

    test('writes schemaVersion 3 and journal data', () {
      final out = encodeCampaign(
        name: 'C1',
        savedAt: DateTime(2026, 6, 11),
        rawByKey: {
          'juice.journal.v2':
              '[{"id":"a","timestamp":"2026-06-11T09:00:00.000","title":"T","body":"B","kind":"text"}]',
        },
      );
      final decoded = jsonDecode(out) as Map<String, dynamic>;
      expect(decoded['schemaVersion'], 3);
      expect(decoded['data'], contains('juice.journal.v2'));
    });

    test('rumors round-trip through campaign files', () {
      const rumors = '[{"id":"r1","text":"North gate","resolved":true}]';
      final out = encodeCampaign(
        name: 'C1',
        savedAt: DateTime(2026, 6, 11),
        rawByKey: {'juice.rumors.v1': rumors},
      );
      final parsed = parseCampaign(out);
      expect(parsed.rawByKey, contains('juice.rumors.v1'));
      final back = (jsonDecode(parsed.rawByKey['juice.rumors.v1']!) as List)
          .cast<Map<String, dynamic>>()
          .map(Rumor.fromJson)
          .single;
      expect(back.text, 'North gate');
      expect(back.resolved, isTrue);
    });

    test('v2 file without rumors key imports fine', () {
      final v2 = jsonEncode({
        'app': 'juice-oracle',
        'schemaVersion': 2,
        'savedAt': '2026-06-11T00:00:00.000',
        'name': 'Old campaign',
        'data': {
          'juice.threads.v1': [
            {'id': 't1', 'title': 'Vow', 'note': '', 'open': true},
          ],
        },
      });
      final parsed = parseCampaign(v2);
      expect(parsed.rawByKey.containsKey('juice.rumors.v1'), isFalse);
      expect(parsed.rawByKey, contains('juice.threads.v1'));
    });

    test('character sheets round-trip through campaign files', () {
      const sheet = '[{"id":"c1","name":"Ash","note":"ranger",'
          '"stats":[{"label":"Iron","value":"+2"}],'
          '"tracks":[{"label":"HP","current":7,"max":10}],'
          '"tags":["wounded"]}]';
      final out = encodeCampaign(
        name: 'C1',
        savedAt: DateTime(2026, 6, 11),
        rawByKey: {'juice.characters.v1': sheet},
      );
      final parsed = parseCampaign(out);
      final back = (jsonDecode(parsed.rawByKey['juice.characters.v1']!) as List)
          .cast<Map<String, dynamic>>()
          .map(Character.fromJson)
          .single;
      expect(back.stats.single.value, '+2');
      expect(back.tracks.single.max, 10);
      expect(back.tags, ['wounded']);
    });

    test('imports a v1 campaign file (log key only)', () {
      final v1 = jsonEncode({
        'app': 'juice-oracle',
        'schemaVersion': 1,
        'savedAt': '2026-06-11T00:00:00.000',
        'name': 'Old campaign',
        'data': {
          'juice.log.v1': [
            {
              'id': 'a',
              'timestamp': '2026-06-11T09:00:00.000',
              'title': 'T',
              'body': 'B'
            }
          ],
        },
      });
      final parsed = parseCampaign(v1);
      expect(parsed.rawByKey, contains('juice.log.v1'));
    });

    test('rejects malformed journal payloads', () {
      final bad = jsonEncode({
        'app': 'juice-oracle',
        'schemaVersion': 2,
        'savedAt': '2026-06-11T00:00:00.000',
        'name': 'X',
        'data': {
          'juice.journal.v2': [
            {'id': 42}
          ],
        },
      });
      expect(() => parseCampaign(bad), throwsFormatException);
    });

    test('campaign export/import carries juice.settings.v1', () {
      final encoded = encodeCampaign(
        name: 'S',
        savedAt: DateTime(2026, 6, 11),
        rawByKey: {
          'juice.settings.v1': '{"genre":"grimdark","tone":"tense"}',
        },
      );
      final parsed = parseCampaign(encoded);
      expect(parsed.rawByKey['juice.settings.v1'], contains('grimdark'));
    });

    test('malformed settings section rejects the file', () {
      final encoded = encodeCampaign(
        name: 'S',
        savedAt: DateTime(2026, 6, 11),
        rawByKey: {'juice.settings.v1': '[1,2]'},
      );
      expect(() => parseCampaign(encoded), throwsFormatException);
    });
  });

  group('Provider export/import', () {
    test('exportActive embeds the active session data', () async {
      SharedPreferences.setMockInitialValues({
        'juice.sessions.v1':
            '{"active":"default","sessions":[{"id":"default","name":"Campaign 1"}]}',
        'juice.threads.v1.default':
            '[{"id":"t1","title":"Slay the wyrm","note":"","open":true}]',
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(sessionsProvider.future);
      final file =
          await container.read(sessionsProvider.notifier).exportActive();
      expect(file, contains('"app": "juice-oracle"'));
      expect(file, contains('Slay the wyrm'));
      expect(file, contains('"name": "Campaign 1"'));
    });

    test('importCampaign creates a new isolated active session', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(sessionsProvider.future);

      final file = encodeCampaign(
        name: 'From File',
        savedAt: DateTime.utc(2026, 6, 11),
        rawByKey: {
          'juice.threads.v1':
              '[{"id":"x","title":"Imported vow","note":"","open":true}]',
        },
      );
      await container.read(sessionsProvider.notifier).importCampaign(file);

      final s = await container.read(sessionsProvider.future);
      expect(s.sessions.length, 2);
      expect(s.activeMeta.name, 'From File');
      final threads = await container.read(threadsProvider.future);
      expect(threads.single.title, 'Imported vow');

      // original session untouched
      await container.read(sessionsProvider.notifier).switchTo('default');
      expect(await container.read(threadsProvider.future), isEmpty);
    });
  });
}
