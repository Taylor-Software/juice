import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/state/blob_store.dart';
import 'package:juice_oracle/state/blob_store_io.dart';

void main() {
  group('blobId', () {
    test('deterministic; differs on content; encodes length', () {
      const a = [1, 2, 3, 4];
      const b = [1, 2, 3, 5];
      expect(blobId(a), blobId(a)); // stable
      expect(blobId(a), isNot(blobId(b))); // content-sensitive
      expect(blobId(a), startsWith('4-')); // length prefix
      expect(blobId(const []), startsWith('0-'));
    });
  });

  group('InMemoryBlobStore', () {
    test('put/get round-trip + dedupe + delete + list + exists', () async {
      final s = InMemoryBlobStore();
      final id = await s.put(const [10, 20, 30]);
      expect(await s.exists(id), isTrue);
      expect(await s.get(id), [10, 20, 30]);

      // Same bytes → same id → single stored copy (dedupe).
      final id2 = await s.put(const [10, 20, 30]);
      expect(id2, id);
      expect(await s.list(), [id]);

      // Distinct content → distinct id.
      final other = await s.put(const [99]);
      expect(other, isNot(id));
      expect((await s.list()).length, 2);

      expect(await s.get('missing'), isNull);
      await s.delete(id);
      expect(await s.exists(id), isFalse);
    });

    test('ext is appended to the id', () async {
      final s = InMemoryBlobStore();
      final id = await s.put(const [1, 2], ext: 'pdf');
      expect(id, endsWith('.pdf'));
      expect(await s.get(id), [1, 2]);
    });
  });

  group('FileBlobStore (temp dir)', () {
    late Directory tmp;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('blobstore_test');
    });
    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    FileBlobStore store() => FileBlobStore(dir: () async => tmp);

    test('persists to disk and round-trips; survives a fresh instance',
        () async {
      final id = await store().put(const [1, 2, 3], ext: 'pdf');
      expect(File('${tmp.path}/$id').existsSync(), isTrue);
      // A new instance over the same dir reads it back (real persistence).
      final fresh = store();
      expect(await fresh.get(id), [1, 2, 3]);
      expect(await fresh.exists(id), isTrue);
      expect(await fresh.list(), [id]);
    });

    test('get-missing is null; delete removes the file', () async {
      final s = store();
      expect(await s.get('nope'), isNull);
      final id = await s.put(const [7, 7]);
      await s.delete(id);
      expect(await s.exists(id), isFalse);
      expect(File('${tmp.path}/$id').existsSync(), isFalse);
    });
  });
}
