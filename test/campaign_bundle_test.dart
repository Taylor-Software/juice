import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/engine/sketch.dart';
import 'package:juice_oracle/state/blob_store.dart';
import 'package:juice_oracle/state/campaign_bundle.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('campaign bundle codec', () {
    test('encode → decode round-trips the json and blobs', () {
      final blobs = {
        '12-abc.png': Uint8List.fromList([1, 2, 3, 4]),
        '5-def': Uint8List.fromList([9, 9]),
      };
      final bytes = encodeCampaignBundle('{"a":1}', blobs);
      final b = decodeCampaignBundle(bytes)!;
      expect(b.campaignJson, '{"a":1}');
      expect(b.blobs.keys, containsAll(['12-abc.png', '5-def']));
      expect(b.blobs['12-abc.png'], [1, 2, 3, 4]);
      expect(b.blobs['5-def'], [9, 9]);
    });

    test('plain JSON / junk bytes are not a bundle', () {
      expect(decodeCampaignBundle(utf8.encode('{"app":"juice-oracle"}')), isNull);
      expect(decodeCampaignBundle(const [1, 2]), isNull);
    });
  });

  group('referencedBlobIds', () {
    test('collects sketch background ids, ignores non-sketches and no-bg', () {
      final journal = jsonEncode([
        {
          'kind': 'sketch',
          'payload': {
            'sketch': {'bg': 'id-1.png'}
          }
        },
        {
          'kind': 'sketch',
          'payload': {'sketch': {}}
        },
        {'kind': 'note', 'body': 'x'},
      ]);
      expect(referencedBlobIds({'juice.journal.v2': journal}), {'id-1.png'});
    });

    test('tolerant of missing / malformed journal', () {
      expect(referencedBlobIds(const {}), isEmpty);
      expect(referencedBlobIds({'juice.journal.v2': 'garbage'}), isEmpty);
    });

    test('collects both the raster (bg) and the source PDF (pdf) blob ids', () {
      final journal = jsonEncode([
        {
          'kind': 'sketch',
          'payload': {
            'sketch': {'bg': 'raster.png', 'pdf': 'src.pdf'}
          }
        },
      ]);
      expect(referencedBlobIds({'juice.journal.v2': journal}),
          {'raster.png', 'src.pdf'});
    });
  });

  test('blobExtFromId extracts the extension or null', () {
    expect(blobExtFromId('12-abc.png'), 'png');
    expect(blobExtFromId('12-abc'), isNull);
  });

  test('export bundles a referenced blob; import restores it on a fresh store',
      () async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    });
    // Source device: a sketch annotates an image stored in storeA.
    final storeA = InMemoryBlobStore();
    final a = ProviderContainer(
        overrides: [blobStoreProvider.overrideWithValue(storeA)]);
    addTearDown(a.dispose);
    await a.read(sessionsProvider.future);
    final id = await storeA.put(Uint8List.fromList([1, 2, 3, 4, 5]), ext: 'png');
    final pdfId =
        await storeA.put(Uint8List.fromList([8, 8, 8, 8]), ext: 'pdf');
    await a.read(journalProvider.notifier).addSketch(SketchData(
        canvasWidth: 10,
        canvasHeight: 10,
        backgroundBlobId: id,
        pdfBlobId: pdfId,
        pdfPage: 0));

    final file = await a.read(sessionsProvider.notifier).exportActiveFile();
    expect(file.ext, 'zip'); // has blobs → bundled, not plain json

    // Target device: a fresh, empty blob store.
    final storeB = InMemoryBlobStore();
    final b = ProviderContainer(
        overrides: [blobStoreProvider.overrideWithValue(storeB)]);
    addTearDown(b.dispose);
    await b.read(sessionsProvider.future);
    expect(await storeB.exists(id), isFalse);

    await b.read(sessionsProvider.notifier).importCampaignData(file.bytes);

    // Both the raster and the source PDF landed under the SAME ids, and the
    // journal sketch still references the raster.
    expect(await storeB.exists(id), isTrue);
    expect(await storeB.exists(pdfId), isTrue);
    final journalB = await b.read(journalProvider.future);
    final sketches =
        journalB.where((e) => e.kind == JournalKind.sketch).toList();
    expect(sketches, hasLength(1));
    expect(sketches.first.payload?['sketch']?['bg'], id);
  });

  test('export with no blobs stays plain json', () async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    });
    final c = ProviderContainer(
        overrides: [blobStoreProvider.overrideWithValue(InMemoryBlobStore())]);
    addTearDown(c.dispose);
    await c.read(sessionsProvider.future);
    final file = await c.read(sessionsProvider.notifier).exportActiveFile();
    expect(file.ext, 'json');
    expect(decodeCampaignBundle(file.bytes), isNull);
  });
}
