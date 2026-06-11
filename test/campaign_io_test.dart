import 'package:flutter_test/flutter_test.dart';

import 'package:juice_oracle/state/campaign_io.dart';

void main() {
  group('Campaign file encode/parse', () {
    test('round-trip preserves name and per-key payloads', () {
      final encoded = encodeCampaign(
        name: 'West Marches',
        savedAt: DateTime.utc(2026, 6, 11),
        rawByKey: {
          'juice.threads.v1': '[{"id":"t1","title":"Vow","note":"","open":true}]',
          'juice.crawl.v1': '{"envRow":7,"lost":true,"dialogRow":2,"dialogCol":2}',
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
            '{"app":"juice-oracle","schemaVersion":2,"name":"x","data":{}}'),
        throwsFormatException,
      );
      expect(
        () => parseCampaign(
            '{"app":"juice-oracle","schemaVersion":1,"name":"x","data":[]}'),
        throwsFormatException,
      );
    });

    test('unknown data keys are ignored on parse', () {
      final parsed = parseCampaign(
          '{"app":"juice-oracle","schemaVersion":1,"name":"x",'
          '"data":{"juice.threads.v1":[],"someday.v9":{}}}');
      expect(parsed.rawByKey.keys, ['juice.threads.v1']);
    });
  });
}
